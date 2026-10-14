// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDTools} from "src/IMDTools.sol";

/// @dev Complements the existing suite with boundary and multi-call properties.
/// forge-config: default.fuzz.runs = 1024
contract IMDToolsEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    IMDTools internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new IMDTools();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
    }

    function test_OneSmallestUnitCanTransferAndReturnThroughAllowance() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferCannotWrapBalanceOrSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);

        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsSpentRatherThanTreatedAsInfinite() public {
        uint256 allowance = type(uint256).max - 1;
        token.approve(spender, allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), allowance - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_HolderNeedsAllowanceToUseTransferFromOnOwnBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_ZeroDelegatedSelfTransferPreservesExistingAllowance() public {
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 0));
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedDelegatedOverdrawCanRetryAfterFunding(
        uint256 balanceSeed,
        uint256 amountSeed,
        uint256 allowanceSeed,
        bool infinite
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 amount = bound(amountSeed, balance + 1, SUPPLY);
        uint256 allowance = infinite ? type(uint256).max : bound(allowanceSeed, amount, type(uint256).max - 1);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, allowance);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), allowance);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);

        token.transfer(alice, amount - balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), infinite ? allowance : allowance - amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidReceiverPreservesAllowanceForRetry(uint256 amountSeed, uint256 allowanceSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 allowance = bound(allowanceSeed, amount, type(uint256).max);
        token.approve(spender, allowance);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), allowance);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(
            token.allowance(address(this), spender), allowance == type(uint256).max ? allowance : allowance - amount
        );
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReplaceInfiniteApprovalThenRevoke(uint256 finiteSeed, uint256 amountSeed) public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        uint256 finite = bound(finiteSeed, 0, type(uint256).max - 1);
        token.approve(spender, finite);
        uint256 amount = bound(amountSeed, 0, finite < SUPPLY - 1 ? finite : SUPPLY - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), finite - amount);

        token.approve(spender, 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(alice), amount + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransfersEqualOneTransfer(
        uint256 firstSeed,
        uint256 secondSeed,
        uint256 allowanceSeed
    ) public {
        uint256 first = bound(firstSeed, 0, SUPPLY);
        uint256 second = bound(secondSeed, 0, SUPPLY - first);
        uint256 total = first + second;
        uint256 allowance = bound(allowanceSeed, total, type(uint256).max);
        IMDTools split = new IMDTools();
        token.approve(spender, allowance);
        split.approve(spender, allowance);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, total));
        assertTrue(split.transferFrom(address(this), alice, first));
        assertTrue(split.transferFrom(address(this), alice, second));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), total);
        assertEq(split.balanceOf(alice), token.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(split.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(
            token.allowance(address(this), spender), allowance == type(uint256).max ? allowance : allowance - total
        );
        assertEq(split.allowance(address(this), spender), token.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(split.totalSupply(), SUPPLY);
    }

    function testFuzz_RepeatedRoundTripsPreserveAllBalances(uint256 amountSeed, uint8 countSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 count = bound(uint256(countSeed), 1, 8);
        for (uint256 i; i < count; ++i) {
            assertTrue(token.transfer(alice, amount));
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            vm.prank(alice);
            assertTrue(token.transfer(address(this), amount));
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }
}
