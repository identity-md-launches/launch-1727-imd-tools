// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDTools} from "../src/IMDTools.sol";

/// @dev Local factory model only; not a contract for launch.
contract TokenFactoryHarness {
    function deploy() external returns (IMDTools) {
        return new IMDTools();
    }

    function deployCreate2(bytes32 salt) external returns (IMDTools) {
        return new IMDTools{salt: salt}();
    }

    function distribute(IMDTools token, address distributor, address poolManager, address remainder) external {
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply * 1000 / 10_000));
        require(token.transfer(poolManager, supply * 8800 / 10_000));
        require(token.transfer(remainder, supply * 200 / 10_000));
    }
}

contract IMDToolsTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    IMDTools internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new IMDTools();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "IMD Tools");
        assertEq(token.symbol(), "TOOLS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        IMDTools deployed = new IMDTools();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_FactoryReceivesEntireSupplyWithCreateAndCreate2() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        vm.startPrank(alice, bob);
        IMDTools created = factory.deploy();
        IMDTools created2 = factory.deployCreate2(keccak256("local test salt"));
        vm.stopPrank();

        assertEq(created.totalSupply(), SUPPLY);
        assertEq(created.balanceOf(address(factory)), SUPPLY);
        assertEq(created.balanceOf(alice), 0);
        assertEq(created.balanceOf(bob), 0);
        assertEq(created2.totalSupply(), SUPPLY);
        assertEq(created2.balanceOf(address(factory)), SUPPLY);
        assertEq(created2.balanceOf(alice), 0);
        assertEq(created2.balanceOf(bob), 0);
    }

    function test_LaunchDistributionClaimsAndTradeTransfersAreExact() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        IMDTools launched = factory.deploy();
        address distributor = makeAddr("local distributor model");
        address poolManager = makeAddr("local pool manager model");
        address remainder = makeAddr("local remainder recipient");

        factory.distribute(launched, distributor, poolManager, remainder);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(poolManager), SUPPLY * 88 / 100);
        assertEq(launched.balanceOf(remainder), SUPPLY * 2 / 100);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, SUPPLY / 10));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), SUPPLY / 10);

        uint256 bought = 1234e18;
        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, bought));
        assertEq(launched.balanceOf(bob), bought);
        assertEq(launched.balanceOf(poolManager), SUPPLY * 88 / 100 - bought);
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, bought));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolManager), SUPPLY * 88 / 100);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 25e18);
        assertTrue(token.transfer(alice, 25e18));
        assertEq(token.balanceOf(address(this)), SUPPLY - 25e18);
        assertEq(token.balanceOf(alice), 25e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferMoreThanBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_EmptyAccountCannotTransferOrSelfTransferPositiveAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(alice, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_ApproveEmitsEventAndCanReplaceOrRevokeAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 90e18);
        assertTrue(token.approve(spender, 90e18));
        assertEq(token.allowance(address(this), spender), 90e18);
        assertTrue(token.approve(spender, 2e18));
        assertEq(token.allowance(address(this), spender), 2e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApprovalDoesNotRequireATokenBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromEmitsEventAndSpendsFiniteAllowance() public {
        token.approve(spender, 50e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 20e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20e18));
        assertEq(token.allowance(address(this), spender), 30e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20e18);
        assertEq(token.balanceOf(alice), 20e18);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 30e18));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 30e18);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), bob, 1);
    }

    function test_MaximumAllowanceIsNotDecremented() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromCannotExceedAllowance() public {
        token.approve(spender, 2);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        token.transferFrom(address(this), alice, 3);
        assertEq(token.allowance(address(this), spender), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_AllowanceBelongsToTheSpecificSpender() public {
        token.approve(spender, 100);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevokedAllowanceCannotBeSpent() public {
        token.approve(spender, 100);
        token.approve(spender, 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_FailedTransferFromRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10));
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToZeroRevertsAndRestoresAllowance() public {
        token.approve(spender, 10);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_ZeroTransferFromZeroOwnerReverts() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromSelfStillSpendsAllowance() public {
        token.approve(spender, 50);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 50));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_DeployerCannotMoveAnotherHoldersTokens() public {
        token.transfer(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_NoPostDeploymentMintBurnAdminOrUpgradeEntrypoints() public {
        token.transfer(alice, 100);
        bytes[] memory calls = new bytes[](18);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1);
        calls[4] = abi.encodeWithSignature("initialize(address)", bob);
        calls[5] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[7] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[8] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[9] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[10] = abi.encodeWithSignature("pause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[12] = abi.encodeWithSignature("freeze(address)", alice);
        calls[13] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[14] = abi.encodeWithSignature("seize(address)", alice);
        calls[15] = abi.encodeWithSignature("disableTransfers()");
        calls[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[17] = abi.encodeWithSignature("setOwner(address)", bob);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "unexpected deployer privilege");
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "unexpected public entrypoint");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100);
            assertEq(token.balanceOf(bob), 0);
        }

        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_RuntimeHasNoDelegationOrDestructionOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden runtime opcode");
            }
        }
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        if (recipient == address(0) || recipient == address(this)) recipient = alice;
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawRevertsWithoutMovingTokens(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApproveAndTransferFrom(uint256 allowance, uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, allowance < SUPPLY ? allowance : SUPPLY);
        assertTrue(token.approve(spender, allowance));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(
            token.allowance(address(this), spender), allowance == type(uint256).max ? allowance : allowance - amount
        );
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceIsAtomic(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowance = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, allowance + 1, SUPPLY);
        token.approve(spender, allowance);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
        );
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), allowance);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
