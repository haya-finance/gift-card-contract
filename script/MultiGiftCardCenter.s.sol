// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MultiGiftCardCenter} from "../src/MultiGiftCardCenter.sol";

contract MultiGiftCardCenterScript is Script {
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
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(MultiGiftCardCenter).creationCode, abi.encode(owner)));
        if (initCodeHash != 0x4fc6f62bf4836b22cf7544162cdad3a4fc3d1b48d76bbc039916a73e18c50b1b) {
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

        MultiGiftCardCenter center =
            new MultiGiftCardCenter{salt: 0x00000000000000000000000000000000000000000000000000000000000000aa}(owner);
        if (address(center) != 0x9bE175D0f614DA4b30273C8cd52905f72454494F) {
            revert DeployedAddressMismatch(address(center));
        }
        _initContract(center);
        console.log("MultiGiftCardCenter:", address(center));
        console.log();
        vm.stopBroadcast();
    }

    function _initContract(MultiGiftCardCenter center) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log();
        console.log("********************************");

        center.setGasOracle(gasOracle);
        center.setTokenValidators(tokenValidators);
    }
}
