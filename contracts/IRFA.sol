// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface IRFA is IERC20{
    function mint(address to, uint256 amount) external;
}