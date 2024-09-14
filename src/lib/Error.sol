// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Error thrown when the token parameter is invalid
error InvalidParamsToken();

/// @notice Error thrown when the amount parameter is invalid
error InvalidParamsAmount();

/// @notice Error thrown when the skin parameter is invalid
error InvalidParamsSkin();

/// @notice Error thrown when the message parameter is invalid
error InvalidParamsMessage();

/// @notice Error thrown when the split count parameter is invalid
error InvalidParamsSplitCount();

/// @notice Error thrown when the amount split parameter is invalid
error InvalidParamsAmountSplit();

/// @notice Error thrown when the split number parameter is invalid
error InvalidParamsSplitNum();

/// @notice Error thrown when the refund user is not the sender
error RefundUserNotSender();

/// @notice Error thrown when the refund time is not available
error RefundTimeNotAvalible();

/// @notice Error thrown when the gift has already been claimed
error GiftHasBeenClaimed();

/// @notice Error thrown when the gift has already been refunded
error GiftHasBeenRefunded();

/// @notice Error thrown when the gift card does not exist
error GiftCardNotExist();

/// @notice Error thrown when the gift card has expired
error GiftCardExpired();

/// @notice Error thrown when the transfer fails
error TransferFailed();

/// @notice Error thrown when the claim amount exceeds the available amount
error ClaimAmountExceed();

/// @notice Error thrown when the claim count exceeds the allowed limit
error ClaimCountExceed();

/// @notice Error thrown when the code hash is already in use
error CodeHashAlreadyInUse();

/// @notice Error thrown when the gift ID is already in use
error GiftIdAlreadyInUse();

/// @notice Error thrown when the gift ID does not exist
error GiftIdNotExists();

error InvalidParamsLength();
