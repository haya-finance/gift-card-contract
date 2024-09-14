// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Constants Library
/// @notice This library contains constant values used throughout the gift card system
library Constants {
    /// @notice Duration after expiration during which a refund can be claimed
    uint256 public constant REFUND_DURATION_AFTER_EXPIRED = 1 days;

    /// @notice Duration for which a gift card remains valid
    uint256 public constant GIFT_CARD_EXPIRE_DURATION = 1 days;

    /// @notice Minimum amount allowed for a gift
    uint256 public constant MIN_GIFT_AMOUNT = 10**6;

    /// @notice Maximum number of splits allowed for a multi-recipient gift
    uint256 public constant MAX_SPLIT_COUNT = 2000;

    /// @notice Maximum length allowed for the skin string
    uint256 public constant MAX_SKIN_STRING_LENGTH = 128;

    /// @notice Maximum length allowed for the message string
    uint256 public constant MAX_MESSAGE_STRING_LENGTH = 1024;

    /// @notice Role identifier for gift sender managers
    bytes32 public constant GIFT_SENDER_MANAGER_ROLE = keccak256("GIFT_SENDER_MANAGER_ROLE");
}
