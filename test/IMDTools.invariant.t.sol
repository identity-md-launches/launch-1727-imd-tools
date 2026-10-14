// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDTools} from "../src/IMDTools.sol";

/// @dev Keeps an independent ledger for a closed set of local test actors.
contract TokenHandler is Test {
    IMDTools public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(IMDTools token_) {
        token = token_;
        actors[0] = makeAddr("invariant initial holder");
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant spender");
        expectedBalance[actors[0]] = 1_000_000_000 * 1e18;
    }

    function transfer(uint8 fromIndex, uint8 toIndex, uint256 amountSeed) public {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint8 ownerIndex, uint8 spenderIndex, uint256 amount) public {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 ownerIndex, uint8 spenderIndex, uint8 toIndex, uint256 amountSeed) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 maximum = allowance < expectedBalance[owner] ? allowance : expectedBalance[owner];
        uint256 amount = bound(amountSeed, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowance != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    function rejectOverdraw(uint8 fromIndex, uint8 toIndex, uint256 amountSeed) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transfer(to, amount);
    }

    function rejectOverspend(uint8 ownerIndex, uint8 spenderIndex, uint8 toIndex) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        if (allowance == type(uint256).max) return;
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, allowance + 1)
        );
        token.transferFrom(owner, to, allowance + 1);
    }

    /// @dev Reach empty accounts and full-balance self-transfers throughout a sequence.
    function transferEntireBalance(uint8 fromIndex, uint8 toIndex) external {
        transfer(fromIndex, toIndex, expectedBalance[actors[fromIndex % actors.length]]);
    }

    /// @dev Explicitly visit allowance boundaries instead of relying on the random dictionary.
    function approveBoundary(uint8 ownerIndex, uint8 spenderIndex, uint8 mode) external {
        uint256[4] memory amounts = [uint256(0), 1, uint256(1_000_000_000 * 1e18), type(uint256).max];
        approve(ownerIndex, spenderIndex, amounts[mode % amounts.length]);
    }

    /// @dev A sufficient allowance must survive a failure later in transferFrom.
    function rejectDelegatedOverdraw(
        uint8 ownerIndex,
        uint8 spenderIndex,
        uint8 toIndex,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        approve(ownerIndex, spenderIndex, infinite ? type(uint256).max : amount);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        token.transferFrom(owner, to, amount);
        // No ghost spending: the invariants check rollback of both balance and allowance.
    }

    function rejectZeroReceiver(uint8 ownerIndex, uint8 spenderIndex, uint256 amountSeed, bool delegated) external {
        address owner = actors[ownerIndex % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        if (delegated) {
            address spender = actors[spenderIndex % actors.length];
            approve(ownerIndex, spenderIndex, amount);
            vm.prank(spender);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint8 ownerIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        assertEq(token.allowance(owner, address(0)), 0);
    }

    function revokeAndReject(uint8 ownerIndex, uint8 spenderIndex, uint8 toIndex, uint256 amountSeed) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 amount = bound(amountSeed, 1, 1_000_000_000 * 1e18);
        approve(ownerIndex, spenderIndex, 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        token.transferFrom(owner, to, amount);
    }
}

/// @dev Pin the campaign in the test file so verification does not depend on config edits.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract IMDToolsInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    IMDTools internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new IMDTools();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectOverdraw.selector;
        selectors[4] = TokenHandler.rejectOverspend.selector;
        selectors[5] = TokenHandler.transferEntireBalance.selector;
        selectors[6] = TokenHandler.approveBoundary.selector;
        selectors[7] = TokenHandler.rejectDelegatedOverdraw.selector;
        selectors[8] = TokenHandler.rejectZeroReceiver.selector;
        selectors[9] = TokenHandler.rejectZeroSpender.selector;
        selectors[10] = TokenHandler.revokeAndReject.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyIsConservedAndBalancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_MetadataRemainsFixed() public view {
        assertEq(token.name(), "IMD Tools");
        assertEq(token.symbol(), "TOOLS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}
