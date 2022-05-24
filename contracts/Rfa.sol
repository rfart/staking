// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Rfa is ERC20, Ownable {
    constructor() ERC20("Rfa", "RFA") Ownable() {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}