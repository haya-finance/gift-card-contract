// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {GasOracle} from "../src/GasOracle.sol";

contract GasOracleScript is Script {
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
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(GasOracle).creationCode, abi.encode(owner)));
        if (initCodeHash != 0xdb0ca76e433372693b9ae1c0d5a8c8af1306f3f7608c4ffc7bb359bd19666023) {
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
        GasOracle oracle =
            new GasOracle{salt: 0x0000000000000000000000000000000000000000000000000000000000000000}(owner);
        if (address(oracle) != 0x651D121E1286a82d8165220c573dA746D765260c) {
            revert DeployedAddressMismatch(address(oracle));
        }
        _initContract(oracle);
        console.log("GasOracle:", address(oracle));
        console.log();
        vm.stopBroadcast();
    }

    function _initContract(GasOracle oracle) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log("Haya Token:", hayaToken);
        console.log("Price for Gas:", priceForGas);
        console.log();
        console.log("********************************");
        oracle.updateToken(hayaToken);
        oracle.updatePrice(priceForGas);
    }
}
