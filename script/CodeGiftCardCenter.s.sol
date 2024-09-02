// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {CodeGiftCardCenter} from "../src/CodeGiftCardCenter.sol";

contract CodeGiftCardCenterScript is Script {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public owner = vm.envAddress("OWNER");
    address public gasOracle = vm.envAddress("GAS_ORACLE");
    address public tokenValidators = vm.envAddress("TOKEN_VALIDATOR");

    error InitCodeHashMismatch(bytes32 initCodeHash);
    error DeployedAddressMismatch(address deployed);

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        // Init code hash check
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(CodeGiftCardCenter).creationCode, abi.encode(owner)));
        if (initCodeHash != 0x9711606b3b1dab4604d7637f6d9c2cfd8be097e9e09ad5051f7ec940f1f0b19a) {
            revert InitCodeHashMismatch(initCodeHash);
        }
        console.log("********************************");
        console.log("******** Deploy Inputs *********");
        console.log("********************************");
        console.log("Owner:", owner);
        console.log();
        console.log("********************************");
        console.log("******** Deploying.... *********");
        console.log("********************************");

        CodeGiftCardCenter center =
            new CodeGiftCardCenter{salt: 0x00000000000000000000000000000000000000000000000000000000000000aa}(owner);
        if (address(center) != 0xE0fB732dBd012E749aaEBd0B15c3a6A7d5465a5e) {
            revert DeployedAddressMismatch(address(center));
        }
        _initContract(center);
        console.log("CodeGiftCardCenter:", address(center));
        console.log();
        vm.stopBroadcast();
    }

    function _initContract(CodeGiftCardCenter center) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log();
        console.log("********************************");

        center.setGasOracle(gasOracle);
        center.setTokenValidators(tokenValidators);
    }
}
