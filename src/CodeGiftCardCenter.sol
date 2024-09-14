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

contract CodeGiftCardCenter is AccessControl, ReentrancyGuard, Pausable {
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
    /// @notice Mapping of code hashes to arrays of gift IDs
    mapping(bytes32 => bytes32[]) public giftCodePairs;

    /// @notice Emitted when a new code gift is created
    /// @param giftId The unique identifier of the gift
    /// @param codeHash The hash of the gift code
    /// @param gift The MultiGift struct containing gift details
    event CodeGiftCreated(bytes32 indexed giftId, bytes32 indexed codeHash, MultiGift gift);

    /// @notice Emitted when a code gift is claimed
    /// @param giftId The unique identifier of the gift
    /// @param recipient The address of the recipient claiming the gift
    /// @param amount The amount of tokens claimed
    event CodeGiftClaimed(bytes32 indexed giftId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a code gift is refunded
    /// @param giftId The unique identifier of the gift
    /// @param recipient The address of the recipient receiving the refund
    /// @param amount The amount of tokens refunded
    event CodeGiftRefunded(bytes32 indexed giftId, address indexed recipient, uint256 amount);

    /// @notice Emitted when the gas oracle address is updated
    /// @param newGasOracle The address of the new gas oracle
    event UpdateGasOracle(address indexed newGasOracle);

    /// @notice Emitted when the token validators address is updated
    /// @param newTokenValidators The address of the new token validators
    event UpdateTokenValidators(address indexed newTokenValidators);

    /// @notice Emitted when an emergency withdrawal is performed
    /// @param token The address of the token withdrawn
    /// @param to The address receiving the withdrawn tokens
    /// @param amount The amount of tokens withdrawn
    event EmergencyWithdrawed(address indexed token, address indexed to, uint256 amount);

    constructor(address _owner) {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _setRoleAdmin(Constants.GIFT_SENDER_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /**
     * @dev Creates a new gift card.
     * @param _codeHash The hash of the gift card code.
     * @param _token The address of the token used for the gift.
     * @param _amount The total amount of tokens for the gift.
     * @param _dividendType The type of dividend (Fixed or Random).
     * @param _splitCount The number of times the gift can be claimed.
     * @param _skin The skin or theme of the gift card.
     * @param _message A message to be included with the gift.
     * @return The unique identifier of the created gift.
     */
    function createGift(
        bytes32 _codeHash,
        address _token,
        uint256 _amount,
        DividendType _dividendType,
        uint256 _splitCount,
        string memory _skin,
        string memory _message
    ) external whenNotPaused nonReentrant returns (bytes32) {
        return _createGift(msg.sender, _codeHash, _token, _amount, _dividendType, _splitCount, _skin, _message);
    }

    // function batchClaimGift()
    /**
     * @dev Claims a gift for a specific account.
     * @param _giftId The hash of the gift card code.
     * @param _account The address of the account claiming the gift.
     * @param _claimAmount The amount to be claimed.
     */
    function claimGift(bytes32 _giftId, address _account, uint256 _claimAmount)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Constants.GIFT_SENDER_MANAGER_ROLE)
    {
        _clainGift(_giftId, _account, _claimAmount);
    }

    /**
     * @dev Batch claims gifts for multiple accounts.
     * @param _giftIds An array of unique identifiers of the gifts.
     * @param _accounts An array of addresses of the accounts claiming the gifts.
     * @param _claimAmounts An array of amounts to be claimed for each gift.
     * @notice This function allows claiming multiple gifts in a single transaction.
     * @notice The lengths of _giftIds, _accounts, and _claimAmounts arrays must be equal.
     */
    function batchClaimGift(bytes32[] calldata _giftIds, address[] calldata _accounts, uint256[] calldata _claimAmounts)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Constants.GIFT_SENDER_MANAGER_ROLE)
    {
        if (_giftIds.length != _accounts.length || _giftIds.length != _claimAmounts.length) {
            revert InvalidParamsLength();
        }
        for (uint256 i = 0; i < _giftIds.length; i++) {
            _clainGift(_giftIds[i], _accounts[i], _claimAmounts[i]);
        }
    }

    /**
     * @dev Internal function to claim a gift for a specific account.
     * @param _giftId The unique identifier of the gift.
     * @param _account The address of the account claiming the gift.
     * @param _claimAmount The amount to be claimed.
     */
    function _clainGift(bytes32 _giftId, address _account, uint256 _claimAmount) internal {
        MultiGift memory gift = multiGifts[_giftId];
        MultiGiftClaimInfo storage claimInfo = multiGiftClaimInfos[_giftId];
        _checkGiftClaimAvailable(_account, _claimAmount, gift, claimInfo);

        claimInfo.claimInfos[_account].claimedAmount = _claimAmount;
        claimInfo.claimInfos[_account].claimedTimestamp = block.timestamp;
        claimInfo.totalClaimedCount += 1;
        claimInfo.totalClaimedAmount += _claimAmount;
        IERC20(gift.token).safeTransfer(_account, _claimAmount);
        emit CodeGiftClaimed(_giftId, _account, _claimAmount);
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
        emit CodeGiftRefunded(_giftId, msg.sender, refundAmount);
    }

    /**
     * @dev Retrieves the gift information for a given gift ID.
     * @param _giftId The unique identifier of the gift.
     * @return The MultiGift struct containing the gift information.
     */
    function getMultiGift(bytes32 _giftId) public view returns (MultiGift memory) {
        return multiGifts[_giftId];
    }

    /**
     * @dev Retrieves the latest gift ID and MultiGift information for a given code hash.
     * @param _codeHash The hash of the gift card code.
     * @return bytes32 The latest gift ID associated with the code hash.
     * @return MultiGift The MultiGift struct containing the gift information.
     */
    function getLatestCodeHashMultiGift(bytes32 _codeHash) public view returns (bytes32, MultiGift memory) {
        bytes32 giftId = giftCodePairs[_codeHash][giftCodePairs[_codeHash].length - 1];
        return (giftId, multiGifts[giftId]);
    }

    /**
     * @dev Retrieves the claim information for a given gift ID.
     * @param _giftId The unique identifier of the gift.
     * @return totalClaimedCount The total number of times the gift has been claimed.
     * @return totalClaimedAmount The total amount that has been claimed from the gift.
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
     * @dev Retrieves the claim information for a specific user and gift.
     * @param _giftId The unique identifier of the gift.
     * @param _account The address of the user.
     * @return claimedAmount The amount claimed by the user.
     * @return claimedTimestamp The timestamp of when the user claimed the gift.
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
     * @dev Checks if a code hash is available for use.
     * @param _codeHash The hash of the gift card code to check.
     * @return A boolean indicating whether the code hash is available.
     */
    function codeHashAvailable(bytes32 _codeHash) public view returns (bool) {
        bytes32 giftId = getLastGiftCodePair(_codeHash);
        if (giftId == bytes32(0)) {
            return true;
        }
        MultiGift memory gift = multiGifts[giftId];
        if (gift.expireTime + Constants.REFUND_DURATION_AFTER_EXPIRED < block.timestamp) {
            return true;
        }
        return false;
    }

    /**
     * @dev Retrieves the last gift ID associated with a code hash.
     * @param _codeHash The hash of the gift card code.
     * @return The gift ID of the last gift associated with the code hash.
     */
    function getLastGiftCodePair(bytes32 _codeHash) public view returns (bytes32) {
        if (giftCodePairs[_codeHash].length == 0) {
            return bytes32(0);
        }
        return giftCodePairs[_codeHash][giftCodePairs[_codeHash].length - 1];
    }

    /**
     * @dev Adds a new gift code pair to the mapping.
     * @param _codeHash The hash of the gift card code.
     * @param _giftId The unique identifier of the gift.
     */
    function _addGiftCodePair(bytes32 _codeHash, bytes32 _giftId) internal {
        giftCodePairs[_codeHash].push(_giftId);
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
     * @dev Grants the GIFT_SENDER_MANAGER_ROLE to the specified account.
     * @param _account The address to be granted the role.
     * @notice Only callable by accounts with the DEFAULT_ADMIN_ROLE.
     */
    function grantGiftSenderManagerRole(address _account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(Constants.GIFT_SENDER_MANAGER_ROLE, _account);
    }

    /**
     * @dev Revokes the GIFT_SENDER_MANAGER_ROLE from the specified account.
     * @param _account The address from which to revoke the role.
     * @notice Only callable by accounts with the DEFAULT_ADMIN_ROLE.
     */
    function revokeGiftSenderManagerRole(address _account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(Constants.GIFT_SENDER_MANAGER_ROLE, _account);
    }

    /**
     * @dev Allows emergency withdrawal of tokens from the contract.
     * @param _token The address of the token to withdraw.
     * @param _to The address to receive the withdrawn tokens.
     * @param _amount The amount of tokens to withdraw.
     * @notice Only callable by accounts with the DEFAULT_ADMIN_ROLE.
     * Emits an EmergencyWithdrawed event upon successful withdrawal.
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
     * @dev Checks if a gift claim is available for a given account.
     * @param _account The address attempting to claim the gift.
     * @param _claimAmount The amount being claimed.
     * @param _gift The gift card information.
     * @param _claimInfo The claim information for the gift.
     * @notice This function verifies the following conditions:
     * 1. The gift has not expired.
     * 2. The claim amount does not exceed the remaining gift amount.
     * 3. The claim count does not exceed the maximum split count.
     * 4. The account has not already claimed from this gift.
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
     * @param _sender The address attempting to refund the gift.
     * @param _gift The gift card information.
     * @param _claimInfo The claim information for the gift.
     * @notice This function verifies the following conditions:
     * 1. The sender must be the original gift sender.
     * 2. The refund time must have passed.
     * 3. The gift must not be fully claimed.
     * 4. The gift must not have been refunded already.
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
     * @dev Get current gas information
     * @return address The address of the gas token
     * @return uint256 The current gas price
     * @notice This function is used to retrieve the current gas token address and price
     */
    function _gasInfo() internal view returns (address, uint256) {
        // If gasOracle is not set, return zero values
        if (gasOracle == address(0)) {
            return (address(0), 0);
        }
        // Get gas token address
        address gasToken = IGasOracle(gasOracle).token();
        // If gas token address is invalid, return zero values
        if (gasToken == address(0)) {
            return (address(0), 0);
        }
        // Return gas token address and current cached gas price
        return (gasToken, IGasOracle(gasOracle).cachedPrice());
    }

    /**
     * @dev Deposits gas fee from the sender to this contract.
     * @param _sender The address of the sender.
     * @param _gasToken The address of the gas token.
     * @param _gasPrice The price of gas.
     * @param _splitNum The number of splits.
     */
    function _gasFeeDeposite(address _sender, address _gasToken, uint256 _gasPrice, uint256 _splitNum) internal {
        IERC20(_gasToken).safeTransferFrom(_sender, address(this), _gasPrice * _splitNum);
    }

    /**
     * @dev Creates a new gift card with the given parameters.
     * @param _sender The address of the gift card sender.
     * @param _codeHash The hash of the gift card code.
     * @param _token The address of the token used for the gift card.
     * @param _amount The total amount of the gift card.
     * @param _dividendType The type of dividend for the gift card.
     * @param _splitCount The number of times the gift card can be split.
     * @param _skin The skin of the gift card.
     * @param _message The message associated with the gift card.
     * @return The unique identifier of the created gift card.
     */
    function _createGift(
        address _sender,
        bytes32 _codeHash,
        address _token,
        uint256 _amount,
        DividendType _dividendType,
        uint256 _splitCount,
        string memory _skin,
        string memory _message
    ) internal paramsValid(_token, _amount, _splitCount, _skin, _message) returns (bytes32) {
        if (!codeHashAvailable(_codeHash)) {
            revert CodeHashAlreadyInUse();
        }
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
            groupId: 0,
            token: _token,
            amount: _amount,
            dividendType: _dividendType,
            splitCount: _splitCount,
            createTime: createTime,
            expireTime: expireTime,
            skin: _skin,
            message: _message
        });
        bytes32 giftId = gift.getCodeGiftId(_codeHash);
        if (multiGifts[giftId].sender != address(0)) {
            revert GiftIdAlreadyInUse();
        }

        multiGifts[giftId] = gift;

        _addGiftCodePair(_codeHash, giftId);
        gasPaids[giftId] = GasPaid(gasToken, gasPrice);
        emit CodeGiftCreated(giftId, _codeHash, gift);
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
        if (_amount / _splitCount < Constants.MIN_GIFT_AMOUNT) {
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
