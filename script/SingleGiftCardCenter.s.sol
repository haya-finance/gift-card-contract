// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {SingleGiftCardCenter} from "../src/SingleGiftCardCenter.sol";

contract SingleGiftCardCenterScript is Script {
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
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(SingleGiftCardCenter).creationCode, abi.encode(owner)));
        if (initCodeHash != 0x70867e413f618d68b194c0ea75fa9a7db9de2058021455adc695a9104d98a6e8) {
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

        SingleGiftCardCenter center =
            new SingleGiftCardCenter{salt: 0x0000000000000000000000000000000000000000000000000000000000000000}(owner);
        if (address(center) != 0xCb0837E4A66e8B837207f623fE271fE60c58E0DF) {
            revert DeployedAddressMismatch(address(center));
        }
        _initContract(center);
        console.log("SingleGiftCardCenter:", address(center));
        console.log();
        vm.stopBroadcast();
    }

    function _initContract(SingleGiftCardCenter center) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log();
        console.log("********************************");

        center.setGasOracle(gasOracle);
        center.setTokenValidators(tokenValidators);
    }
}
