// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGasOracle} from "./interfaces/IGasOracle.sol";

/**
 * @title GasOracle
 * @dev Contract for managing the gas token address.
 */
contract GasOracle is IGasOracle, Ownable {
    /// @notice The address of the gas token
    address public gasToken;

    /// @notice The cached gas price
    uint256 private _cachedPrice;

    /// @notice Timestamp of when the gas price was last cached
    uint48 private _cachedPriceTimestamp;

    /// @notice Error thrown when gas token is not set
    error GasTokenNotSet();

    /**
     * @dev GasPriceUpdated event is emitted when the gas price is updated.
     * @param currentPrice The current gas price.
     * @param previousPrice The previous gas price.
     * @param cachedPriceTimestamp The timestamp when the gas price was last cached.
     */
    event GasPriceUpdated(uint256 currentPrice, uint256 previousPrice, uint256 cachedPriceTimestamp);

    /**
     * @dev Emitted when the gas token address is updated.
     * @param gasToken The new gas token address.
     */
    event GasTokenUpdated(address gasToken);

    constructor(address _owner) Ownable(_owner) {}

    /**
     * @dev Returns the address of the gas token.
     */
    function token() public view override gasTokenSet returns (address) {
        return gasToken;
    }

    /**
     * @dev Returns the cached price.
     * @return The cached price as a uint256 value.
     */
    function cachedPrice() public view override gasTokenSet returns (uint256) {
        return _cachedPrice;
    }

    /**
     * @dev Returns the timestamp of the cached price.
     * @return The timestamp of the cached price as a uint48 value.
     */
    function cachedPriceTimestamp() public view override gasTokenSet returns (uint48) {
        return _cachedPriceTimestamp;
    }

    /**
     * @dev Updates the cached price of the GasOracle contract.
     * @param force Boolean flag indicating whether to force update the cached price.
     * @return The updated cached price.
     */
    function updateCachedPrice(bool force) public gasTokenSet returns (uint256) {
        if (force) {
            _cachedPriceTimestamp = uint48(block.timestamp);
        }
        return _cachedPrice;
    }

    /**
     * @dev Updates the gas token address.
     * @param _gasToken The address of the gas token to be set.
     * Emits a `GasTokenUpdated` event.
     */
    function updateToken(address _gasToken) public onlyOwner {
        gasToken = _gasToken;
        emit GasTokenUpdated(gasToken);
    }

    /**
     * @dev Updates the gas price used by the contract.
     * @param _price The new gas price to be set.
     * Requirements:
     * - Only the contract owner can call this function.
     * Emits a {GasPriceUpdated} event with the updated gas price, cached price, and timestamp.
     */
    function updatePrice(uint256 _price) public onlyOwner {
        _cachedPrice = _price;
        _cachedPriceTimestamp = uint48(block.timestamp);
        emit GasPriceUpdated(_price, _cachedPrice, _cachedPriceTimestamp);
    }

    modifier gasTokenSet() {
        if (gasToken == address(0)) {
            revert GasTokenNotSet();
        }
        _;
    }
}
