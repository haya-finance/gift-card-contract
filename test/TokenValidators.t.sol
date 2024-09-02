// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenValidators} from "../src/TokenValidators.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TokenValidatorsTest is Test {
    TokenValidators tokenValidators;
    address public token1;
    address public token2;

    function setUp() public {
        tokenValidators = new TokenValidators(address(this));
        token1 = address(0x123);
        token2 = address(0x456);
    }

    function testValidateToken() public view {
        assertFalse(tokenValidators.validateToken(token1));
        assertFalse(tokenValidators.validateToken(token2));
    }

    function testAddValidToken() public {
        tokenValidators.addValidToken(token1);
        assertTrue(tokenValidators.validateToken(token1));
    }

    function testFailNotOwner() public {
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        tokenValidators.addValidToken(token2);
    }
}
