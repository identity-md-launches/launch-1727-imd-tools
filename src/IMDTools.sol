// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IMD Tools (TOOLS)
/// @notice A fixed supply ERC-20 with 18 decimals and ordinary, untaxed transfers.
/// @dev The immediate deployer receives the entire supply. During the launch this
///      is the factory, which handles distribution outside the token contract.
contract IMDTools is ERC20 {
    /// @notice One billion tokens, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("IMD Tools", "TOOLS") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
