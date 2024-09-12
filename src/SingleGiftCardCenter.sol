// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGasOracle} from "./interfaces/IGasOracle.sol";
import {ITokenValidators} from "./interfaces/ITokenValidators.sol";
import {SingleGift, SingleGiftClaimInfo, GiftCardLib, GasPaid, GiftStatus} from "./lib/GiftCardLib.sol";
import {Constants} from "./lib/Constants.sol";
import "./lib/Error.sol";

contract SingleGiftCardCenter is AccessControl, ReentrancyGuard, Pausable {
    using GiftCardLib for SingleGift;
    using SafeERC20 for IERC20;

    /// @notice Address of the gas oracle contract
    address public gasOracle;

    /// @notice Address of the token validators contract
    address public tokenValidators;

    /// @notice Mapping of gift IDs to SingleGift structs
    mapping(bytes32 => SingleGift) public singleGifts;

    /// @notice Mapping of gift IDs to SingleGiftClaimInfo structs
    mapping(bytes32 => SingleGiftClaimInfo) public singleGiftClaimInfos;

    /// @notice Mapping of gift IDs to GasPaid structs
    mapping(bytes32 => GasPaid) public gasPaids;

    /// @notice Emitted when a new single gift is created
    /// @param giftId The unique identifier of the created gift
    /// @param gift The SingleGift struct containing gift details
    event SingleGiftCreated(bytes32 indexed giftId, SingleGift gift);

    /// @notice Emitted when a gift is claimed
    /// @param giftId The unique identifier of the claimed gift
    /// @param recipient The address of the recipient claiming the gift
    /// @param amount The amount claimed
    event SingleGiftClaimed(bytes32 indexed giftId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a gift is refunded
    /// @param giftId The unique identifier of the refunded gift
    /// @param recipient The address of the recipient receiving the refund
    /// @param amount The amount refunded
    event SingleGiftRefunded(bytes32 indexed giftId, address indexed recipient, uint256 amount);

    /// @notice Emitted when the gas oracle address is updated
    /// @param newGasOracle The address of the new gas oracle
    event UpdateGasOracle(address indexed newGasOracle);

    /// @notice Emitted when the token validators address is updated
    /// @param newTokenValidators The address of the new token validators contract
    event UpdateTokenValidators(address indexed newTokenValidators);

    /// @notice Emitted when an emergency withdrawal is performed
    /// @param token The address of the token withdrawn
    /// @param to The address receiving the withdrawn tokens
    /// @param amount The amount withdrawn
    event EmergencyWithdrawed(address indexed token, address indexed to, uint256 amount);

    /**
     * @dev Constructor to initialize the contract.
     * @param _owner The address of the contract owner.
     */
    constructor(address _owner) {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _setRoleAdmin(Constants.GIFT_SENDER_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /**
     * @dev Creates a new single gift card.
     * @param _recipientTGID The Telegram ID of the recipient.
     * @param _token The token address for the gift.
     * @param _amount The amount of tokens for the gift.
     * @param _skin The skin identifier for the gift.
     * @param _message A message associated with the gift.
     * @return The unique identifier of the created gift.
     */
    function createGift(
        uint256 _recipientTGID,
        address _token,
        uint256 _amount,
        string memory _skin,
        string memory _message
    ) external whenNotPaused nonReentrant returns (bytes32) {
        return _createGift(msg.sender, _recipientTGID, _token, _amount, _skin, _message);
    }

    /**
     * @dev Claims a gift for a specific account.
     * @param _giftId The unique identifier of the gift.
     * @param _account The address of the account claiming the gift.
     */
    function claimGift(bytes32 _giftId, address _account)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Constants.GIFT_SENDER_MANAGER_ROLE)
    {
        _claimGift(_giftId, _account);
    }

    function batchClaimGift(bytes32[] calldata _giftIds, address[] calldata _accounts) 
        external
        whenNotPaused
        nonReentrant
        onlyRole(Constants.GIFT_SENDER_MANAGER_ROLE) 
    {
        if (_giftIds.length != _accounts.length) {
            revert InvalidParamsLength();
        }
        for (uint256 i = 0; i < _giftIds.length; i++) {
            _claimGift(_giftIds[i], _accounts[i]);
        }
    }

    function _claimGift(bytes32 _giftId, address _account) internal {
        SingleGift memory gift = singleGifts[_giftId];
        SingleGiftClaimInfo storage claimInfo = singleGiftClaimInfos[_giftId];
        if (claimInfo.recipient != address(0)) {
            revert GiftHasBeenClaimed();
        }
        if (gift.expireTime + Constants.REFUND_DURATION_AFTER_EXPIRED < block.timestamp) {
            revert GiftCardExpired();
        }
        claimInfo.recipient = _account;
        claimInfo.claimInfo.claimedAmount = gift.amount;
        claimInfo.claimInfo.claimedTimestamp = block.timestamp;
        IERC20(gift.token).safeTransfer(_account, gift.amount);
        emit SingleGiftClaimed(_giftId, _account, gift.amount);
    }

    /**
     * @dev Refunds an unclaimed gift to the sender.
     * @param _giftId The unique identifier of the gift to be refunded.
     */
    function refundGift(bytes32 _giftId) external whenNotPaused nonReentrant {
        SingleGift memory gift = singleGifts[_giftId];
        SingleGiftClaimInfo storage claimInfo = singleGiftClaimInfos[_giftId];
        if (gift.sender != msg.sender) {
            revert RefundUserNotSender();
        }
        if (block.timestamp <= gift.expireTime + Constants.REFUND_DURATION_AFTER_EXPIRED) {
            revert RefundTimeNotAvalible();
        }
        if (claimInfo.claimInfo.claimedAmount >= gift.amount) {
            revert GiftHasBeenClaimed();
        }
        if (claimInfo.status == GiftStatus.Refunded) {
            revert GiftHasBeenRefunded();
        }
        claimInfo.status = GiftStatus.Refunded;
        IERC20(gift.token).safeTransfer(msg.sender, gift.amount);
        GasPaid memory gasPaid = gasPaids[_giftId];
        IERC20(gasPaid.token).safeTransfer(msg.sender, gasPaid.amount);
        emit SingleGiftRefunded(_giftId, msg.sender, gift.amount);
    }

    /**
     * @dev Retrieves the details of a single gift.
     * @param _giftId The unique identifier of the gift.
     * @return The SingleGift struct containing the gift details.
     */
    function getSingleGift(bytes32 _giftId) public view returns (SingleGift memory) {
        return singleGifts[_giftId];
    }

    /**
     * @dev Retrieves the claim information for a single gift.
     * @param _giftId The unique identifier of the gift.
     * @return The SingleGiftClaimInfo struct containing the claim details.
     */
    function getSingleGiftClaimInfo(bytes32 _giftId) public view returns (SingleGiftClaimInfo memory) {
        return singleGiftClaimInfos[_giftId];
    }

    /**
     * @dev Retrieves the ID of a single gift card.
     * @param _gift The SingleGift struct representing the gift card.
     * @return The ID of the gift card as a bytes32 value.
     */
    function getGiftCardID(SingleGift memory _gift) public pure returns (bytes32) {
        return _gift.getSingleGiftId();
    }

    /**
     * @dev Sets the address of the gas oracle.
     * Only the account with the DEFAULT_ADMIN_ROLE can call this function.
     * @param _gasOracle The address of the gas oracle to be set.
     * Emits an `UpdateGasOracle` event.
     */
    function setGasOracle(address _gasOracle) public onlyRole(DEFAULT_ADMIN_ROLE) {
        gasOracle = _gasOracle;
        emit UpdateGasOracle(_gasOracle);
    }

    /**
     * @dev Sets the address of the token validators contract.
     * Only the account with the DEFAULT_ADMIN_ROLE can call this function.
     *
     * @param _tokenValidators The address of the token validators contract.
     *
     * Emits an {UpdateTokenValidators} event.
     */
    function setTokenValidators(address _tokenValidators) public onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenValidators = _tokenValidators;
        emit UpdateTokenValidators(_tokenValidators);
    }

    /**
     * @dev Pauses the contract.
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Grants the GIFT_SENDER_MANAGER_ROLE to a specified account.
     * @param _account The address of the account to be granted the role.
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     */
    function grantGiftSenderManagerRole(address _account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(Constants.GIFT_SENDER_MANAGER_ROLE, _account);
    }

    /**
     * @dev Revokes the GIFT_SENDER_MANAGER_ROLE from a specified account.
     * @param _account The address of the account from which the role is to be revoked.
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     */
    function revokeGiftSenderManagerRole(address _account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(Constants.GIFT_SENDER_MANAGER_ROLE, _account);
    }

    /**
     * @dev Allows emergency withdrawal of tokens from the contract.
     * @param _token The address of the token to be withdrawn.
     * @param _to The address to which the tokens will be sent.
     * @param _amount The amount of tokens to be withdrawn.
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     * Emits an EmergencyWithdrawed event.
     */
    function emergencyWithdraw(address _token, address _to, uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).safeTransfer(_to, _amount);
        emit EmergencyWithdrawed(_token, _to, _amount);
    }

    /**
     * @dev Fallback function to reject any incoming Ether transfers.
     * Reverts the transaction to reject the transfer.
     */
    receive() external payable {
        revert();
    }

    /**
     * @dev Creates a new single gift card.
     * @param _sender The address of the gift sender.
     * @param _recipientTGID The Telegram ID of the recipient.
     * @param _token The address of the gift token.
     * @param _amount The amount of the gift.
     * @param _skin The skin of the gift.
     * @param _message The message for the gift.
     * @return The unique identifier of the created gift.
     */
    function _createGift(
        address _sender,
        uint256 _recipientTGID,
        address _token,
        uint256 _amount,
        string memory _skin,
        string memory _message
    ) internal paramsValid(_token, _amount, _skin, _message) returns (bytes32) {
        (address gasToken, uint256 gasPrice) = _gasInfo();
        _gasFeeDeposite(msg.sender, gasToken, gasPrice, 1);

        uint256 createTime = block.timestamp;
        uint256 expireTime = createTime + Constants.GIFT_CARD_EXPIRE_DURATION;
        uint256 prevBal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(_sender, address(this), _amount);
        uint256 postBal = IERC20(_token).balanceOf(address(this));
        if (postBal - prevBal < _amount) {
            revert TransferFailed();
        }
        SingleGift memory gift = SingleGift({
            sender: _sender,
            recipientTGID: _recipientTGID,
            token: _token,
            amount: _amount,
            createTime: createTime,
            expireTime: expireTime,
            skin: _skin,
            message: _message
        });
        bytes32 giftId = gift.getSingleGiftId();
        singleGifts[giftId] = gift;
        gasPaids[giftId] = GasPaid(gasToken, gasPrice);
        emit SingleGiftCreated(giftId, gift);
        return giftId;
    }

    /**
     * @dev Retrieves the gas information from the gas oracle.
     * @return The address of the gas token and the current gas price.
     */
    function _gasInfo() internal view returns (address, uint256) {
        if (gasOracle == address(0)) {
            return (address(0), 0);
        }
        address gasToken = IGasOracle(gasOracle).token();
        if (gasToken == address(0)) {
            return (address(0), 0);
        }
        return (gasToken, IGasOracle(gasOracle).cachedPrice());
    }

    /**
     * @dev Deposits gas fee from the sender.
     * @param _sender The address of the sender.
     * @param _gasToken The address of the gas token.
     * @param _gasPrice The current gas price.
     * @param _splitNum The number of splits for the gift.
     */
    function _gasFeeDeposite(address _sender, address _gasToken, uint256 _gasPrice, uint256 _splitNum) internal {
        IERC20(_gasToken).safeTransferFrom(_sender, address(this), _gasPrice * _splitNum);
    }

    /*
     * @dev Modifier to validate the parameters for creating a gift card.
     * @param _token The address of the token to be used for the gift card.
     * @param _amount The amount of the gift card.
     * @param _skin The skin string for the gift card.
     * @param _message The message string for the gift card.
     * @throws InvalidParamsToken if the token is not valid.
     * @throws InvalidParamsAmount if the amount is less than the minimum gift amount.
     * @throws InvalidParamsSkin if the skin string length exceeds the maximum allowed length.
     * @throws InvalidParamsMessage if the message string length exceeds the maximum allowed length.
     */
    modifier paramsValid(address _token, uint256 _amount, string memory _skin, string memory _message) {
        if (!ITokenValidators(tokenValidators).validateToken(_token)) {
            revert InvalidParamsToken();
        }
        if (_amount < Constants.MIN_GIFT_AMOUNT) {
            revert InvalidParamsAmount();
        }
        if (bytes(_skin).length > Constants.MAX_SKIN_STRING_LENGTH) {
            revert InvalidParamsSkin();
        }
        if (bytes(_message).length > Constants.MAX_MESSAGE_STRING_LENGTH) {
            revert InvalidParamsMessage();
        }
        _;
    }
}
