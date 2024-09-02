// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITokenValidators {
    function validateToken(address token) external view returns (bool);
}
