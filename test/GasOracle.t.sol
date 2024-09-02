// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GasOracle} from "../src/GasOracle.sol";

contract GasOracleTest is Test {
    GasOracle gasOracle;
    address gasToken;

    function setUp() public {
        gasToken = address(0x123);
        gasOracle = new GasOracle(address(this));
    }

    function testTokenPrice() public {
        gasOracle.updateToken(gasToken);
        gasOracle.updatePrice(100);
        assertEq(gasOracle.cachedPrice(), 100, "cached price should be 100");
    }

    function testFailTokenNotSet() public {
        vm.expectRevert(GasOracle.GasTokenNotSet.selector);
        gasOracle.updatePrice(100);
    }
}
