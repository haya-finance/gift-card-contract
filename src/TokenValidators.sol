// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITokenValidators} from "./interfaces/ITokenValidators.sol";

contract TokenValidators is Ownable, ITokenValidators {
    /// @dev Mapping to store valid token addresses
    mapping(address => bool) internal validTokens;

    /// @dev Emitted when a valid token is added
    /// @param token The address of the added token
    event ValidTokenAdded(address indexed token);

    /// @dev Emitted when a valid token is removed
    /// @param token The address of the removed token
    event ValidTokenRemoved(address indexed token);

    /// @dev Error thrown when an invalid token operation is attempted
    error InvalidToken();

    /// @dev Error thrown when a zero address is provided
    error ZeroAddress();

    /// @dev Constructor to initialize the contract
    /// @param _owner The address of the contract owner
    constructor(address _owner) Ownable(_owner) {}

    /// @dev Adds a single token to the list of valid tokens
    /// @param _token The address of the token to add
    function addValidToken(address _token) public onlyOwner {
        _addValidToken(_token);
    }

    /// @dev Removes a single token from the list of valid tokens
    /// @param _token The address of the token to remove
    function removeValidToken(address _token) public onlyOwner {
        _removeValidToken(_token);
    }

    /// @dev Adds multiple tokens to the list of valid tokens
    /// @param _tokens An array of token addresses to add
    function addValidTokens(address[] calldata _tokens) public onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            _addValidToken(_tokens[i]);
        }
    }

    /// @dev Removes multiple tokens from the list of valid tokens
    /// @param _tokens An array of token addresses to remove
    function removeValidTokens(address[] calldata _tokens) public onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            _removeValidToken(_tokens[i]);
        }
    }

    /// @dev Checks if a token is valid
    /// @param _token The address of the token to validate
    /// @return bool True if the token is valid, false otherwise
    function validateToken(address _token) public view override returns (bool) {
        return validTokens[_token];
    }

    /// @dev Internal function to add a valid token
    /// @param _token The address of the token to add
    function _addValidToken(address _token) internal {
        if (_token == address(0)) {
            revert ZeroAddress();
        }
        if (validTokens[_token]) {
            revert InvalidToken();
        }

        validTokens[_token] = true;

        emit ValidTokenAdded(_token);
    }

    /// @dev Internal function to remove a valid token
    /// @param _token The address of the token to remove
    function _removeValidToken(address _token) internal {
        if (!validTokens[_token]) {
            revert InvalidToken();
        }

        validTokens[_token] = false;

        emit ValidTokenRemoved(_token);
    }
}
