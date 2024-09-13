// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGasOracle} from "./interfaces/IGasOracle.sol";
import {ITokenValidators} from "./interfaces/ITokenValidators.sol";
import {MultiGift, MultiGiftClaimInfo, GiftCardLib, DividendType, GasPaid, GiftStatus} from "./lib/GiftCardLib.sol";
import {Constants} from "./lib/Constants.sol";
import "./lib/Error.sol";

contract MultiGiftCardCenter is AccessControl, ReentrancyGuard, Pausable {
    using GiftCardLib for MultiGift;
    using SafeERC20 for IERC20;

    /// @notice Address of the gas oracle contract
    address public gasOracle;

    /// @notice Address of the token validators contract
    address public tokenValidators;

    /// @notice Mapping of gift IDs to MultiGift structs
    mapping(bytes32 => MultiGift) public multiGifts;

    /// @notice Mapping of gift IDs to MultiGiftClaimInfo structs
    mapping(bytes32 => MultiGiftClaimInfo) public multiGiftClaimInfos;

    /// @notice Mapping of gift IDs to GasPaid structs
    mapping(bytes32 => GasPaid) public gasPaids;

    /// @notice Emitted when a new multi-gift is created
    /// @param giftId The unique identifier of the created gift
    /// @param gift The MultiGift struct containing gift details
    event MultiGiftCreated(bytes32 indexed giftId, MultiGift gift);

    /// @notice Emitted when a gift is claimed
    /// @param giftId The unique identifier of the claimed gift
    /// @param recipient The address of the recipient claiming the gift
    /// @param amount The amount claimed
    event MultiGiftClaimed(bytes32 indexed giftId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a gift is refunded
    /// @param giftId The unique identifier of the refunded gift
    /// @param recipient The address of the recipient receiving the refund
    /// @param amount The amount refunded
    event MultiGiftRefunded(bytes32 indexed giftId, address indexed recipient, uint256 amount);

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
     * @dev Creates a new gift card.
     * @param _groupId The group ID for the gift.
     * @param _token The token address for the gift.
     * @param _amount The amount of tokens for the gift.
     * @param _dividendType The type of dividend for the gift.
     * @param _splitCount The number of splits for the gift.
     * @param _skin The skin identifier for the gift.
     * @param _message A message associated with the gift.
     * @return The unique identifier of the created gift.
     */
    function createGift(
        uint256 _groupId,
        address _token,
        uint256 _amount,
        DividendType _dividendType,
        uint256 _splitCount,
        string memory _skin,
        string memory _message
    ) external whenNotPaused nonReentrant returns (bytes32) {
        return _createGift(msg.sender, _groupId, _token, _amount, _dividendType, _splitCount, _skin, _message);
    }

    /**
     * @dev Claims a gift for a specific account.
     * @param _giftId The unique identifier of the gift.
     * @param _account The address of the account claiming the gift.
     * @param _claimAmount The amount to be claimed.
     */
    function claimGift(bytes32 _giftId, address _account, uint256 _claimAmount)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Constants.GIFT_SENDER_MANAGER_ROLE)
    {
        _claimGift(_giftId, _account, _claimAmount);
    }

    function batchClaimGift(bytes32[] calldata _giftIds, address[] calldata _accounts, uint256[] calldata _claimAmounts) external whenNotPaused nonReentrant {
        if (_giftIds.length != _accounts.length || _giftIds.length != _claimAmounts.length) {
            revert InvalidParamsLength();
        }
        for (uint256 i = 0; i < _giftIds.length; i++) {
            _claimGift(_giftIds[i], _accounts[i], _claimAmounts[i]);
        }
    }

    function _claimGift(bytes32 _giftId, address _account, uint256 _claimAmount) internal {
        MultiGift memory gift = multiGifts[_giftId];
        MultiGiftClaimInfo storage claimInfo = multiGiftClaimInfos[_giftId];

        _checkGiftClaimAvailable(_account, _claimAmount, gift, claimInfo);

        claimInfo.claimInfos[_account].claimedAmount = _claimAmount;
        claimInfo.claimInfos[_account].claimedTimestamp = block.timestamp;
        claimInfo.totalClaimedCount += 1;
        claimInfo.totalClaimedAmount += _claimAmount;
        IERC20(gift.token).safeTransfer(_account, _claimAmount);
        emit MultiGiftClaimed(_giftId, _account, _claimAmount);
    }
    /**
     * @dev Refunds an unclaimed gift to the sender.
     * @param _giftId The unique identifier of the gift to be refunded.
     */
    function refundGift(bytes32 _giftId) external whenNotPaused nonReentrant {
        MultiGift memory gift = multiGifts[_giftId];
        MultiGiftClaimInfo storage claimInfo = multiGiftClaimInfos[_giftId];

        _checkGiftRefundAvailable(msg.sender, gift, claimInfo);

        claimInfo.status = GiftStatus.Refunded;
        uint256 refundAmount = gift.amount - claimInfo.totalClaimedAmount;

        IERC20(gift.token).safeTransfer(msg.sender, refundAmount);

        uint256 leftSplit = (gift.splitCount - claimInfo.totalClaimedCount);
        GasPaid memory gasPaid = gasPaids[_giftId];
        IERC20(gasPaid.token).safeTransfer(msg.sender, gasPaid.amount * leftSplit);
        emit MultiGiftRefunded(_giftId, msg.sender, refundAmount);
    }

    /**
     * @dev Retrieves the details of a specific gift.
     * @param _giftId The unique identifier of the gift.
     * @return The MultiGift struct containing the gift details.
     */
    function getMultiGift(bytes32 _giftId) public view returns (MultiGift memory) {
        return multiGifts[_giftId];
    }

    /**
     * @dev Retrieves the claim information for a specific gift.
     * @param _giftId The unique identifier of the gift.
     * @return totalClaimedCount The total number of claims made.
     * @return totalClaimedAmount The total amount claimed.
     * @return status The current status of the gift.
     */
    function getMultiGiftClaimInfo(bytes32 _giftId)
        public
        view
        returns (uint256 totalClaimedCount, uint256 totalClaimedAmount, GiftStatus status)
    {
        MultiGiftClaimInfo storage info = multiGiftClaimInfos[_giftId];
        return (info.totalClaimedCount, info.totalClaimedAmount, info.status);
    }

    /**
     * @dev Get the claim information for a user regarding a specific gift card
     * @param _giftId The unique identifier of the gift card
     * @param _account The address of the user to query
     * @return claimedAmount The amount claimed by the user
     * @return claimedTimestamp The timestamp when the user claimed
     */
    function getUserClaimInfo(bytes32 _giftId, address _account)
        public
        view
        returns (uint256 claimedAmount, uint256 claimedTimestamp)
    {
        MultiGiftClaimInfo storage info = multiGiftClaimInfos[_giftId];
        return (info.claimInfos[_account].claimedAmount, info.claimInfos[_account].claimedTimestamp);
    }

    /**
     * @dev Retrieves the ID of a single gift card.
     * @param _gift The MultiGift struct representing the gift card.
     * @return The ID of the gift card as a bytes32 value.
     */
    function getGiftCardID(MultiGift memory _gift) public pure returns (bytes32) {
        return _gift.getMultiGiftId();
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
     * @dev Checks if a gift claim is available.
     * @param _account The address of the account attempting to claim.
     * @param _claimAmount The amount being claimed.
     * @param _gift The gift being claimed.
     * @param _claimInfo The claim information for the gift.
     * @notice This function will revert if the claim is not available.
     */
    function _checkGiftClaimAvailable(
        address _account,
        uint256 _claimAmount,
        MultiGift memory _gift,
        MultiGiftClaimInfo storage _claimInfo
    ) internal view {
        if (_gift.expireTime + Constants.REFUND_DURATION_AFTER_EXPIRED < block.timestamp) {
            revert GiftCardExpired();
        }
        if (_gift.amount < _claimAmount + _claimInfo.totalClaimedAmount) {
            revert ClaimAmountExceed();
        }
        if (_gift.splitCount < _claimInfo.totalClaimedCount + 1) {
            revert ClaimCountExceed();
        }
        if (_claimInfo.claimInfos[_account].claimedAmount > 0) {
            revert GiftHasBeenClaimed();
        }
    }

    /**
     * @dev Checks if a gift refund is available.
     * @param _sender The address of the account attempting to refund.
     * @param _gift The gift being refunded.
     * @param _claimInfo The claim information for the gift.
     * @notice This function will revert if the refund is not available.
     */
    function _checkGiftRefundAvailable(address _sender, MultiGift memory _gift, MultiGiftClaimInfo storage _claimInfo)
        internal
        view
    {
        if (_sender != _gift.sender) {
            revert RefundUserNotSender();
        }
        if (block.timestamp <= _gift.expireTime + Constants.REFUND_DURATION_AFTER_EXPIRED) {
            revert RefundTimeNotAvalible();
        }
        if (_claimInfo.totalClaimedAmount >= _gift.amount) {
            revert GiftHasBeenClaimed();
        }
        if (_claimInfo.status == GiftStatus.Refunded) {
            revert GiftHasBeenRefunded();
        }
    }

    /**
     * @dev Retrieves gas information from the gas oracle.
     * @return The gas token address and the current gas price.
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

    /**
     * @dev Creates a new gift.
     * @param _sender The address of the gift sender.
     * @param _token The address of the gift token.
     * @param _amount The amount of the gift.
     * @param _dividendType The dividend type of the gift.
     * @param _splitCount The number of splits for the gift.
     * @param _skin The skin of the gift.
     * @param _message The message for the gift.
     * @return The unique identifier of the created gift.
     */
    function _createGift(
        address _sender,
        uint256 _groupId,
        address _token,
        uint256 _amount,
        DividendType _dividendType,
        uint256 _splitCount,
        string memory _skin,
        string memory _message
    ) internal paramsValid(_token, _amount, _splitCount, _skin, _message) returns (bytes32) {
        (address gasToken, uint256 gasPrice) = _gasInfo();
        _gasFeeDeposite(msg.sender, gasToken, gasPrice, _splitCount);

        uint256 createTime = block.timestamp;
        uint256 expireTime = createTime + Constants.GIFT_CARD_EXPIRE_DURATION;
        uint256 prevBal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(_sender, address(this), _amount);
        uint256 postBal = IERC20(_token).balanceOf(address(this));
        if (postBal - prevBal < _amount) {
            revert TransferFailed();
        }
        MultiGift memory gift = MultiGift({
            sender: _sender,
            groupId: _groupId,
            token: _token,
            amount: _amount,
            dividendType: _dividendType,
            splitCount: _splitCount,
            createTime: createTime,
            expireTime: expireTime,
            skin: _skin,
            message: _message
        });
        bytes32 giftId = gift.getMultiGiftId();
        if (multiGifts[giftId].sender != address(0)) {
            revert GiftIdAlreadyInUse();
        }
        multiGifts[giftId] = gift;
        gasPaids[giftId] = GasPaid(gasToken, gasPrice);
        emit MultiGiftCreated(giftId, gift);
        return giftId;
    }

    /**
     * @dev Modifier to validate the parameters for creating a group gift card.
     * @param _token The address of the token to be used for the gift card.
     * @param _amount The amount of the gift card.
     * @param _splitCount The number of splits for the gift card.
     * @param _skin The skin string for the gift card.
     * @param _message The message string for the gift card.
     */
    modifier paramsValid(
        address _token,
        uint256 _amount,
        uint256 _splitCount,
        string memory _skin,
        string memory _message
    ) {
        if (!ITokenValidators(tokenValidators).validateToken(_token)) {
            revert InvalidParamsToken();
        }
        if (_amount < Constants.MIN_GIFT_AMOUNT) {
            revert InvalidParamsAmount();
        }
        if (_amount % _splitCount != 0) {
            revert InvalidParamsAmountSplit();
        }
        if (_amount / _splitCount % Constants.MIN_GIFT_AMOUNT != 0) {
            revert InvalidParamsAmountSplit();
        }
        if (_splitCount < 2 || _splitCount > Constants.MAX_SPLIT_COUNT) {
            revert InvalidParamsSplitNum();
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
