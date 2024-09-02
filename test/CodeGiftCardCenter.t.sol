// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CodeGiftCardCenter} from "../src/CodeGiftCardCenter.sol";
import {GasOracle} from "../src/GasOracle.sol";
import {TokenValidators} from "../src/TokenValidators.sol";
import {StandardTokenMock} from "../src/mock/StandardTokenMock.sol";
import {MutilGift, MutilGiftClaimInfo, DividendType, GiftStatus} from "../src/lib/GiftCardLib.sol";
import "../src/lib/Error.sol";

contract CodeGiftCardCenterTest is Test {
    CodeGiftCardCenter giftCardCenter;
    GasOracle gasOracle;
    TokenValidators tokenValidators;
    StandardTokenMock gasToken;
    StandardTokenMock invalidToken;

    address alice;
    address bob;
    address manager;
    bytes32 defaultCodeHash;

    function setUp() public {
        alice = address(0x456);
        bob = address(0x789);
        defaultCodeHash = bytes32("0x123");
        manager = address(0xabc);
        gasToken = new StandardTokenMock("x", "xx");
        invalidToken = new StandardTokenMock("y", "yy");
        gasOracle = new GasOracle(address(this));
        gasOracle.updateToken(address(gasToken));
        gasOracle.updatePrice(5 ether);
        tokenValidators = new TokenValidators(address(this));
        tokenValidators.addValidToken(address(gasToken));
        giftCardCenter = new CodeGiftCardCenter(address(this));
        giftCardCenter.setGasOracle(address(gasOracle));
        giftCardCenter.setTokenValidators(address(tokenValidators));

        giftCardCenter.grantGiftSenderManagerRole(manager);
    }

    function testCreateGiftCard() public {
        deal(address(gasToken), alice, 1000 ether);
        vm.startPrank(alice);
        gasToken.approve(address(giftCardCenter), type(uint256).max);
        bytes32 giftId = giftCardCenter.createGift(
            defaultCodeHash, address(gasToken), 10 ether, DividendType.Fixed, 100, "skin", "msg"
        );
        vm.stopPrank();

        assertEq(
            gasToken.balanceOf(address(giftCardCenter)),
            10 ether + 5 ether * 100,
            "gift card center should have 510 ether"
        );
        assertEq(gasToken.balanceOf(alice), 1000 ether - 10 ether - 5 ether * 100, "deployer should have 490 ether");

        MutilGift memory gift = giftCardCenter.getMutilGift(giftId);
        assertEq(gift.sender, alice, "sender should be alice");
        assertEq(gift.token, address(gasToken), "token should be gasToken");
        assertEq(gift.amount, 10 ether, "amount should be 10 ether");
        assertEq(uint256(gift.dividendType), uint256(DividendType.Fixed), "dividendType should be Fixed");
        assertEq(gift.skin, "skin", "skin should be skin");
        assertEq(gift.message, "msg", "message should be msg");

        bytes32 lastGiftCodePair = giftCardCenter.getLastGiftCodePair(defaultCodeHash);
        assertEq(lastGiftCodePair, giftId, "lastGiftCodePair should be giftId");
    }

    function testClaimGiftCard() public {
        bytes32 giftId = _createGiftCard(defaultCodeHash);
        vm.prank(manager);
        giftCardCenter.claimGift(defaultCodeHash, bob, 10 ether);

        (uint256 totalClaimedCount, uint256 totalClaimedAmount, GiftStatus status) =
            giftCardCenter.getMutilGiftClaimInfo(giftId);
        assertEq(totalClaimedCount, 1, "totalClaimedCount should be 1");
        assertEq(totalClaimedAmount, 10 ether, "totalClaimedAmount should be 10 ether");
        assertEq(uint256(status), uint256(GiftStatus.None), "GiftStatus should be None");
    }

    function testRefundGiftCard() public {
        bytes32 giftId = _createGiftCard(defaultCodeHash);
        MutilGift memory gift = giftCardCenter.getMutilGift(giftId);
        vm.warp(gift.expireTime + 1 days + 1);
        vm.prank(alice);
        giftCardCenter.refundGift(giftId);
        assertEq(gasToken.balanceOf(alice), 10000 ether, "alice should have 10000 ether");
        (uint256 totalClaimedCount, uint256 totalClaimedAmount, GiftStatus status) =
            giftCardCenter.getMutilGiftClaimInfo(giftId);
        assertEq(uint256(status), uint256(GiftStatus.Refunded), "isRefunded should be true");
        assertEq(totalClaimedCount, 0, "totalClaimedCount should be 0");
        assertEq(totalClaimedAmount, 0, "totalClaimedAmount should be 0");
    }

    function testFailClaimAuth() public {
        _createGiftCard(defaultCodeHash);
        vm.prank(alice);
        giftCardCenter.claimGift(defaultCodeHash, bob, 10 ether);
    }

    function testFailDuplicateCreateGift() public {
        _createGiftCard(defaultCodeHash);
        _createGiftCard(defaultCodeHash);
    }

    function testRecreateGiftAfterLastGiftHasBeenExpired() public {
        bytes32 giftId = _createGiftCard(defaultCodeHash);
        MutilGift memory gift = giftCardCenter.getMutilGift(giftId);
        vm.warp(gift.expireTime + 1 days + 1);
        _createGiftCard(defaultCodeHash);
    }

    function testAfterExpiredRefundAndCodeHashRecreated() public {
        bytes32 giftId = _createGiftCard(defaultCodeHash);
        MutilGift memory gift = giftCardCenter.getMutilGift(giftId);
        vm.warp(gift.expireTime + 1 days + 1);
        _createGiftCard(defaultCodeHash);
        bytes32 lastGiftCodePair = giftCardCenter.getLastGiftCodePair(defaultCodeHash);
        assertNotEq(lastGiftCodePair, giftId, "lastGiftCodePair should be different giftId");
        uint256 beforeRefundBalance = gasToken.balanceOf(alice);
        uint256 gasPrice = gasOracle.cachedPrice();
        uint256 gasPaid = gasPrice * gift.splitCount;
        vm.prank(alice);
        giftCardCenter.refundGift(giftId);
        uint256 afterRefundBalance = gasToken.balanceOf(alice);
        assertEq(afterRefundBalance, beforeRefundBalance + gift.amount + gasPaid, "alice should have 10 ether");
        (uint256 totalClaimedCount, uint256 totalClaimedAmount, GiftStatus status) =
            giftCardCenter.getMutilGiftClaimInfo(giftId);
        assertEq(totalClaimedCount, 0, "totalClaimedCount should be 0");
        assertEq(totalClaimedAmount, 0, "totalClaimedAmount should be 0");
        assertEq(uint256(status), uint256(GiftStatus.Refunded), "GiftStatus should be Refunded");
    }

    function testRefundOnlySender() public {
        bytes32 giftId = _createGiftCard(defaultCodeHash);
        MutilGift memory gift = giftCardCenter.getMutilGift(giftId);
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
        giftCardCenter.createGift(
            defaultCodeHash, address(invalidToken), 10 ether, DividendType.Fixed, 100, "skin", "msg"
        );
    }

    function testGiftHasBeenClaimed() public {
        _createGiftCard(defaultCodeHash);
        vm.prank(manager);
        giftCardCenter.claimGift(defaultCodeHash, bob, 1 ether);
        vm.expectRevert(GiftHasBeenClaimed.selector);
        vm.prank(manager);
        giftCardCenter.claimGift(defaultCodeHash, bob, 1 ether);
    }

    function testGiftHasBeenExpired() public {
        bytes32 giftId = _createGiftCard(defaultCodeHash);
        MutilGift memory gift = giftCardCenter.getMutilGift(giftId);
        vm.warp(gift.expireTime + 1 days + 1);
        vm.expectRevert(GiftCardExpired.selector);
        vm.prank(manager);
        giftCardCenter.claimGift(defaultCodeHash, bob, 1 ether);
    }

    function _createGiftCard(bytes32 _codeHash) internal returns (bytes32) {
        deal(address(gasToken), alice, 10000 ether);
        vm.prank(alice);
        gasToken.approve(address(giftCardCenter), type(uint256).max);
        vm.prank(alice);
        bytes32 giftId =
            giftCardCenter.createGift(_codeHash, address(gasToken), 10 ether, DividendType.Fixed, 100, "skin", "msg");
        return giftId;
    }
}
