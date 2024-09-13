// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Enum representing the dividend distribution type for multi-gifts
/// @dev Fixed: Equal distribution, Random: Random distribution
enum DividendType {
    Fixed,
    Random
}

/// @notice Struct representing a single gift card
/// @dev Contains all necessary information for a single recipient gift
struct SingleGift {
    address sender; // Address of the gift sender
    uint256 recipientTGID; // Telegram ID of the recipient
    address token; // Address of the gift token
    uint256 amount; // Amount of tokens in the gift
    uint256 createTime; // Timestamp of gift creation
    uint256 expireTime; // Timestamp when the gift expires
    string skin; // Visual theme of the gift card
    string message; // Personal message attached to the gift
}

/// @notice Struct representing a multi-recipient gift card
/// @dev Contains information for gifts that can be claimed by multiple recipients
struct MultiGift {
    address sender; // Address of the gift sender
    uint256 groupId; // Group ID of the gift
    address token; // Address of the gift token
    uint256 amount; // Total amount of tokens in the gift
    DividendType dividendType; // Type of distribution (Fixed or Random)
    uint256 splitCount; // Number of parts the gift is split into
    uint256 createTime; // Timestamp of gift creation
    uint256 expireTime; // Timestamp when the gift expires
    string skin; // Visual theme of the gift card
    string message; // Personal message attached to the gift
}

/// @notice Struct containing claim information for a gift
struct ClaimInfo {
    uint256 claimedAmount; // Amount of tokens claimed
    uint256 claimedTimestamp; // Timestamp of the claim
}

/// @notice Struct containing claim information for a single gift
struct SingleGiftClaimInfo {
    address recipient; // Address of the recipient who claimed the gift
    ClaimInfo claimInfo; // Claim information
    GiftStatus status;
}

/// @notice Enum representing the status of a gift
enum GiftStatus {
    None, // Default status
    Refunded // Gift has been refunded

}

/// @notice Struct containing claim information for a multi-gift
struct MultiGiftClaimInfo {
    mapping(address => ClaimInfo) claimInfos; // Mapping of recipient addresses to their claim info
    address[] recipients; // Array of recipient addresses
    uint256 totalClaimedCount; // Total number of claims made
    uint256 totalClaimedAmount; // Total amount of tokens claimed
    GiftStatus status; // Current status of the multi-gift
}

/// @notice Struct representing gas fee payment information
struct GasPaid {
    address token; // Address of the token used for gas payment
    uint256 amount; // Amount of tokens paid for gas
}

/// @notice Library containing utility functions for gift card operations
library GiftCardLib {
    /// @notice Generates a unique identifier for a single gift
    /// @param card The SingleGift struct
    /// @return bytes32 The unique identifier
    function getSingleGiftId(SingleGift memory card) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                card.sender,
                card.recipientTGID,
                card.token,
                card.amount,
                card.createTime,
                card.expireTime,
                card.skin,
                card.message
            )
        );
    }

    /// @notice Generates a unique identifier for a multi-gift
    /// @param card The MultiGift struct
    /// @return bytes32 The unique identifier
    function getMultiGiftId(MultiGift memory card) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                card.sender,
                card.token,
                card.amount,
                card.dividendType,
                card.splitCount,
                card.createTime,
                card.expireTime,
                card.skin,
                card.message
            )
        );
    }

    /// @notice Generates a unique identifier for a code-based multi-gift
    /// @param card The MultiGift struct
    /// @param codeHash The hash of the gift code
    /// @return bytes32 The unique identifier
    function getCodeGiftId(MultiGift memory card, bytes32 codeHash) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                card.sender,
                card.token,
                card.amount,
                card.dividendType,
                card.splitCount,
                card.createTime,
                card.expireTime,
                card.skin,
                card.message,
                codeHash
            )
        );
    }
}
