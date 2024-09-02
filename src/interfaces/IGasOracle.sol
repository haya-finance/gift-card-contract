// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/**
 * @title IGasOracle
 * @dev Interface for the Gas Oracle contract.
 */

interface IGasOracle {
    function token() external view returns (address);
    function cachedPrice() external view returns (uint256);
    function cachedPriceTimestamp() external view returns (uint48);
    function updateCachedPrice(bool force) external returns (uint256);
}
