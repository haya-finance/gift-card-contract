// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {GasOracle} from "../src/GasOracle.sol";
import {TokenValidators} from "../src/TokenValidators.sol";
import {SingleGiftCardCenter} from "../src/SingleGiftCardCenter.sol";
import {MultiGiftCardCenter} from "../src/MultiGiftCardCenter.sol";
import {CodeGiftCardCenter} from "../src/CodeGiftCardCenter.sol";

contract DeployScript is Script {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address owner = vm.envAddress("OWNER");
    address hayaToken = vm.envAddress("HAYA_CONTRACT");
    uint256 priceForGas = vm.envUint("PER_GIFT_CARD_GAS");
    bytes32 codeSalt = 0x0000000000000000000000000000000000000000000000000000000000000007;
    address gasOracle;
    address tokenValidators;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        address depolyer = vm.addr(deployerPrivateKey);
        console.log("deployer:", depolyer);

        console.log("********************************");
        console.log("******** Deploy Inputs *********");
        console.log("********************************");
        console.log("Owner:", owner);
        console.log();
        console.log("********************************");
        console.log("******** Deploying.... *********");
        console.log("********************************");
        console.log();
        GasOracle oracle = new GasOracle{salt: codeSalt}(owner);
        _initGasOracleContract(oracle);
        console.log("GasOracle:", address(oracle));
        console.log();
        gasOracle = address(oracle);

        TokenValidators validator = new TokenValidators{salt: codeSalt}(owner);
        _initTokenValidatorsContract(validator);
        console.log("TokenValidators:", address(validator));
        console.log();
        tokenValidators = address(validator);

        SingleGiftCardCenter singleCenter = new SingleGiftCardCenter{salt: codeSalt}(owner);

        _initSingleGiftCardCenterContract(singleCenter);
        console.log("SingleGiftCardCenter:", address(singleCenter));
        console.log();

        MultiGiftCardCenter multiCenter = new MultiGiftCardCenter{salt: codeSalt}(owner);

        _initMultiGiftCardCenterContract(multiCenter);
        console.log("MultiGiftCardCenter:", address(multiCenter));
        console.log();

        CodeGiftCardCenter codeCenter = new CodeGiftCardCenter{salt: codeSalt}(owner);

        _initCodeGiftCardCenterContract(codeCenter);
        console.log("CodeGiftCardCenter:", address(codeCenter));
        console.log();

        vm.stopBroadcast();
    }

    function _initGasOracleContract(GasOracle oracle) internal {
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

    function _initTokenValidatorsContract(TokenValidators validator) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log("Haya Token:", hayaToken);
        console.log();
        console.log("********************************");
        validator.addValidToken(hayaToken);
    }

    function _initSingleGiftCardCenterContract(SingleGiftCardCenter center) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log();
        console.log("********************************");

        center.setGasOracle(gasOracle);
        center.setTokenValidators(tokenValidators);
    }

    function _initMultiGiftCardCenterContract(MultiGiftCardCenter center) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log();
        console.log("********************************");

        center.setGasOracle(gasOracle);
        center.setTokenValidators(tokenValidators);
    }

    function _initCodeGiftCardCenterContract(CodeGiftCardCenter center) internal {
        console.log("********************************");
        console.log("******** Initializing.... *********");
        console.log("********************************");
        console.log();
        console.log("********************************");

        center.setGasOracle(gasOracle);
        center.setTokenValidators(tokenValidators);
    }
}
