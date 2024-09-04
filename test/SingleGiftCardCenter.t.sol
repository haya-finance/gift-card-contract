// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SingleGiftCardCenter} from "../src/SingleGiftCardCenter.sol";
import {GasOracle} from "../src/GasOracle.sol";
import {TokenValidators} from "../src/TokenValidators.sol";
import {StandardTokenMock} from "../src/mock/StandardTokenMock.sol";
import {SingleGift, SingleGiftClaimInfo, GiftStatus} from "../src/lib/GiftCardLib.sol";
import "../src/lib/Error.sol";

contract SingleGiftCardCenterTest is Test {
    SingleGiftCardCenter giftCardCenter;
    GasOracle gasOracle;
    TokenValidators tokenValidators;
    StandardTokenMock gasToken;
    StandardTokenMock invalidToken;

    address alice;
    address bob;
    address manager;

    function setUp() public {
        alice = address(0x456);
        bob = address(0x789);
        manager = address(0xabc);
        gasToken = new StandardTokenMock("x", "xx");
        invalidToken = new StandardTokenMock("y", "yy");
        gasOracle = new GasOracle(address(this));
        gasOracle.updateToken(address(gasToken));
        gasOracle.updatePrice(5 ether);
        tokenValidators = new TokenValidators(address(this));
        tokenValidators.addValidToken(address(gasToken));
        giftCardCenter = new SingleGiftCardCenter(address(this));
        giftCardCenter.setGasOracle(address(gasOracle));
        giftCardCenter.setTokenValidators(address(tokenValidators));

        giftCardCenter.grantGiftSenderManagerRole(manager);
    }

    function testCreateGiftCard() public {
        deal(address(gasToken), alice, 1000 ether);
        vm.startPrank(alice);
        gasToken.approve(address(giftCardCenter), 1000 ether);
        bytes32 giftId = giftCardCenter.createGift(11, address(gasToken), 10 ether, "skin", "msg");
        vm.stopPrank();

        assertEq(
            gasToken.balanceOf(address(giftCardCenter)), 10 ether + 5 ether, "gift card center should have 15 ether"
        );
        assertEq(gasToken.balanceOf(alice), 1000 ether - 10 ether - 5 ether, "deployer should have 985 ether");

        SingleGift memory gift = giftCardCenter.getSingleGift(giftId);
        assertEq(gift.sender, alice, "sender should be alice");
        assertEq(gift.recipientTGID, 11, "recipientTGID should be 11");
        assertEq(gift.token, address(gasToken), "token should be gasToken");
        assertEq(gift.amount, 10 ether, "amount should be 10 ether");
        assertEq(gift.skin, "skin", "skin should be skin");
        assertEq(gift.message, "msg", "message should be msg");
    }

    function testClaimGiftCard() public {
        bytes32 giftId = _createGiftCard();
        vm.prank(manager);
        giftCardCenter.claimGift(giftId, bob);

        assertEq(gasToken.balanceOf(bob), 10 ether, "bob should have 10 ether");
        SingleGiftClaimInfo memory claimInfo = giftCardCenter.getSingleGiftClaimInfo(giftId);
        assertEq(claimInfo.recipient, bob, "recipient should be bob");
        assertEq(claimInfo.claimInfo.claimedAmount, 10 ether, "claimed amount should be 10 ether");
        assertEq(claimInfo.claimInfo.claimedTimestamp, block.timestamp, "claimed timestamp should be current timestamp");
        assertEq(uint256(claimInfo.status), uint256(GiftStatus.None), "isRefunded should be None");
    }

    function testRefundGiftCard() public {
        bytes32 giftId = _createGiftCard();
        SingleGift memory gift = giftCardCenter.getSingleGift(giftId);
        vm.warp(gift.expireTime + 1 days + 1);
        vm.prank(alice);
        giftCardCenter.refundGift(giftId);
        assertEq(gasToken.balanceOf(alice), 1000 ether, "alice should have 1000 gas");
        SingleGiftClaimInfo memory claimInfo = giftCardCenter.getSingleGiftClaimInfo(giftId);
        assertEq(uint256(claimInfo.status), uint256(GiftStatus.Refunded), "isRefunded should be Refunded");
    }

    function testFailClaimAuth() public {
        bytes32 giftId = _createGiftCard();
        vm.prank(alice);
        giftCardCenter.claimGift(giftId, bob);
    }

    function testRefundOnlySender() public {
        bytes32 giftId = _createGiftCard();
        SingleGift memory gift = giftCardCenter.getSingleGift(giftId);
        vm.warp(gift.expireTime + 1 days + 1);
        vm.expectRevert(RefundUserNotSender.selector);
        vm.prank(bob);
        giftCardCenter.refundGift(giftId);
    }

    function testCreateGiftCardInvalidParamsToken() public {
        deal(address(invalidToken), alice, 1000 ether);
        deal(address(gasToken), alice, 1000 ether);
        vm.prank(alice);
        invalidToken.approve(address(giftCardCenter), 1000 ether);
        vm.prank(alice);
        gasToken.approve(address(giftCardCenter), 1000 ether);
        vm.expectRevert(InvalidParamsToken.selector);
        vm.prank(alice);
        giftCardCenter.createGift(11, address(invalidToken), 10 ether, "skin", "msg");
    }

    function testGiftHasBeenClaimed() public {
        bytes32 giftId = _createGiftCard();
        vm.prank(manager);
        giftCardCenter.claimGift(giftId, bob);
        vm.expectRevert(GiftHasBeenClaimed.selector);
        vm.prank(manager);
        giftCardCenter.claimGift(giftId, bob);
    }

    function testGiftHasBeenExpired() public {
        bytes32 giftId = _createGiftCard();
        SingleGift memory gift = giftCardCenter.getSingleGift(giftId);
        vm.warp(gift.expireTime + 1 days + 1);
        vm.expectRevert(GiftCardExpired.selector);
        vm.prank(manager);
        giftCardCenter.claimGift(giftId, bob);
    }

    function testEmergencyWithdraw() public {
        _createGiftCard();
        giftCardCenter.emergencyWithdraw(address(gasToken), bob, 10 ether);
        assertEq(gasToken.balanceOf(bob), 10 ether, "bob should have 10 ether");
    }

    function testFailEmergencyWithdraw() public {
        _createGiftCard();
        vm.prank(alice);
        giftCardCenter.emergencyWithdraw(address(gasToken), bob, 10 ether);
    }

    function _createGiftCard() internal returns (bytes32) {
        deal(address(gasToken), alice, 1000 ether);
        vm.prank(alice);
        gasToken.approve(address(giftCardCenter), 1000 ether);
        vm.prank(alice);
        bytes32 giftId = giftCardCenter.createGift(11, address(gasToken), 10 ether, "skin", "msg");
        return giftId;
    }
}
