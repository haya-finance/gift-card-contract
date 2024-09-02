// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {TokenValidators} from "../src/TokenValidators.sol";

contract TokenValidatorsScript is Script {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address owner = vm.envAddress("OWNER");
    address hayaToken = vm.envAddress("HAYA_CONTRACT");
    uint256 priceForGas = vm.envUint("PER_GIFT_CARD_GAS");

    error InitCodeHashMismatch(bytes32 initCodeHash);
    error DeployedAddressMismatch(address deployed);

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        address depolyer = vm.addr(deployerPrivateKey);
        console.log("deployer:", depolyer);
        // Init code hash check
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(TokenValidators).creationCode, abi.encode(owner)));
        if (initCodeHash != 0xe61e1ef23705c5b389f97e1b459c40056caf4768a67cb506ed26c8b17ea0e89d) {
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
        console.log();
        TokenValidators validator =
            new TokenValidators{salt: 0x0000000000000000000000000000000000000000000000000000000000000000}(owner);
        if (address(validator) != 0xB84dbB99DACf86011778df628f760Dc59F759C2D) {
            revert DeployedAddressMismatch(address(validator));
        }
        _initContract(validator);
        console.log("TokenValidators:", address(validator));
        console.log();
        vm.stopBroadcast();
    }

    function _initContract(TokenValidators validator) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log("Haya Token:", hayaToken);
        console.log();
        console.log("********************************");
        validator.addValidToken(hayaToken);
    }
}
