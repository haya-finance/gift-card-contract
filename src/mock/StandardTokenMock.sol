// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// mock class using BasicToken
contract StandardTokenMock is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint() external {
        _mint(msg.sender, 1_000_000 * 10 ** uint256(decimals()));
    }

    function mintWithAmount(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
