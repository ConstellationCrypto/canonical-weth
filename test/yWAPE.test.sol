// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.28;

import "forge-std/Test.sol";
import "../src/yWAPE.sol";
import "../src/ArbInfo.sol";

contract MockArbInfo {
    constructor() {}

    function configureAutomaticYield() external {}
}

contract yWAPETest is Test {
    yWAPE public token;
    MockArbInfo public arbInfo;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public dave = address(0x4);
    uint256 public constant INITIAL_BALANCE = 100 ether;

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad, uint256 nativeAmount);

    function setUp() public {
        arbInfo = new MockArbInfo();
        token = new yWAPE(address(arbInfo));

        // Fund test accounts
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);
        vm.deal(dave, INITIAL_BALANCE);
    }

    function testMetadata() public view {
        assertEq(token.name(), "Yield-bearing Wrapped APE");
        assertEq(token.symbol(), "yWAPE");
        assertEq(token.decimals(), 18);
    }

    function testDeposit() public {
        uint256 depositAmount = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, depositAmount);
        vm.prank(alice);
        token.deposit{value: depositAmount}();

        // the first deposit is always 1:1
        assertEq(token.balanceOf(alice), depositAmount);
        assertEq(address(token).balance, depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposit(bob, depositAmount);
        vm.prank(bob);
        token.deposit{value: depositAmount}();

        // the second deposit's shares are identical to the first since the share price is 1:1
        uint256 bobExpectedShares = depositAmount;
        assertEq(token.balanceOf(bob), bobExpectedShares);
        assertEq(address(token).balance, depositAmount * 2);

        // Now we generate 10% (0.2 ether) yield
        vm.deal(address(token), address(token).balance + 0.2 ether);

        // the third depositor should get ~0.90909090909090909 shares (share price has gone up)
        vm.expectEmit(true, true, true, true);
        emit Deposit(charlie, depositAmount);
        vm.prank(charlie);
        token.deposit{value: depositAmount}();
        assertApproxEqAbs(token.balanceOf(charlie), 9.09e17, 1e16);
        assertEq(address(token).balance, 3.2 ether);

        // Now we generate another 10% yield (0.32 ether)
        vm.deal(address(token), address(token).balance + 0.32 ether);

        // the fourth depositor should get ~0.82644628099173554 shares (share price has gone up)
        vm.expectEmit(true, true, true, true);
        emit Deposit(dave, depositAmount);
        vm.prank(dave);
        token.deposit{value: depositAmount}();
        assertApproxEqAbs(token.balanceOf(dave), 8.26e17, 1e16);
        assertEq(address(token).balance, 4.52 ether);
    }

    function testDepositTo() public {
        uint256 depositAmount = 1 ether;

        vm.expectEmit(true, false, false, true);
        emit Deposit(bob, depositAmount);

        vm.prank(alice);
        token.deposit{value: depositAmount}(bob);

        assertEq(token.balanceOf(bob), depositAmount);
        assertEq(address(token).balance, depositAmount);
    }

    function testReceive() public {
        uint256 depositAmount = 1 ether;

        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, depositAmount);

        vm.prank(alice);
        (bool success,) = address(token).call{value: depositAmount}("");
        assertTrue(success);

        assertEq(token.balanceOf(alice), depositAmount);
        assertEq(address(token).balance, depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        token.deposit{value: depositAmount}();

        vm.prank(bob);
        token.deposit{value: depositAmount}();

        // Now we generate 10% (0.2 ether) yield
        vm.deal(address(token), address(token).balance + 0.2 ether);

        vm.prank(charlie);
        token.deposit{value: depositAmount}();

        // Now we generate another 10% yield (0.32 ether)
        vm.deal(address(token), address(token).balance + 0.32 ether);

        vm.prank(dave);
        token.deposit{value: depositAmount}();

        // now we withdraw all the shares and verify the output amounts
        vm.prank(alice);
        token.withdrawAll();
        assertEq(alice.balance, INITIAL_BALANCE + 0.21 ether, "alice should have earned 0.21 eth yield");

        vm.prank(bob);
        token.withdrawAll();
        assertEq(bob.balance, INITIAL_BALANCE + 0.21 ether, "bob should have earned 0.21 eth yield");

        vm.prank(charlie);
        token.withdrawAll();
        assertEq(charlie.balance, INITIAL_BALANCE + 0.1 ether, "charlie should have earned 0.1 eth yield");

        vm.prank(dave);
        token.withdrawAll();
        assertEq(dave.balance, INITIAL_BALANCE + 0 ether, "dave should have earned 0 eth yield");

        assertEq(address(token).balance, 0, "token should have 0 remaining balance");
        assertEq(token.totalSupply(), 0, "token should have 0 remaining total supply");
    }

    function testWithdrawTo() public {
        uint256 depositAmount = 1 ether;
        vm.startPrank(alice);
        token.deposit{value: depositAmount}();

        vm.expectEmit(true, true, true, true);
        emit Withdrawal(alice, depositAmount, depositAmount);
        token.withdraw(bob, depositAmount);

        // Bob should have received the deposit amount
        assertEq(bob.balance, INITIAL_BALANCE + depositAmount);

        // Both alice and bob should have 0 shares
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function testWithdrawAll() public {
        vm.startPrank(alice);
        uint256 depositAmount = 1 ether;
        token.deposit{value: depositAmount}();

        uint256 preBalance = alice.balance;

        token.withdrawAll();

        assertEq(token.balanceOf(alice), 0);
        assertEq(alice.balance, preBalance + depositAmount);
        vm.stopPrank();
    }

    // Share Calculation Tests
    function testShareCalculations() public {
        // First deposit establishes the initial share ratio (1.0 share for 1.0 eth)
        vm.startPrank(alice);
        token.deposit{value: 1 ether}();
        vm.stopPrank();

        // Second deposit should get proportional shares (2.0 shares for 2.0 eth)
        vm.startPrank(bob);
        token.deposit{value: 2 ether}();
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 2 ether);
        assertEq(address(token).balance, 3 ether);

        // Now assume we generated 0.3 ether yield
        vm.deal(address(token), address(token).balance + 0.3 ether);

        // the third depositor should have ~0.909 shares
        vm.startPrank(charlie);
        token.deposit{value: 1 ether}();
        vm.stopPrank();

        assertApproxEqAbs(token.balanceOf(charlie), 0.909 ether, 1e16);
        assertEq(address(token).balance, 4.3 ether);

        // Now assume we generated another 0.3 ether yield
        vm.deal(address(token), address(token).balance + 0.3 ether);

        // the fourth depositor should have ~0.849 shares
        vm.startPrank(dave);
        token.deposit{value: 1 ether}();
        vm.stopPrank();

        assertApproxEqAbs(token.balanceOf(dave), 0.849 ether, 1e16);
        assertEq(address(token).balance, 5.6 ether);
    }

    function testYieldDistribution() public {
        // Initial deposits
        vm.startPrank(alice);
        token.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.startPrank(bob);
        token.deposit{value: 1 ether}();
        vm.stopPrank();

        // Now we generate 0.5 ether yield
        vm.deal(address(token), address(token).balance + 0.5 ether);

        // Alice withdraws half of her shares
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(alice, 0.5e18, 0.625 ether);
        token.withdraw(0.5e18);
        vm.stopPrank();

        // Alice should have received 0.625 ether
        assertEq(alice.balance, INITIAL_BALANCE - 0.375 ether);
        assertEq(token.balanceOf(alice), 0.5e18);

        // The contract should have 1.875 ether
        assertEq(address(token).balance, 1.875 ether);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(bob, 1e18, 1.25 ether);
        token.withdrawAll();
        vm.stopPrank();

        // Bob should have received 1.25 ether
        assertEq(bob.balance, INITIAL_BALANCE + 0.25 ether);
        assertEq(address(token).balance, 0.625 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function testSequentialDepositsWithYield() public {
        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = dave;

        // Sequential deposits with yield between each
        for (uint256 i = 0; i < users.length; i++) {
            uint256 expectedShares = i == 0
                ? 1 ether // first deposit is always 1:1
                : (1 ether * token.totalSupply() / address(token).balance);

            vm.prank(users[i]);
            token.deposit{value: 1 ether}();

            // Add yield after each deposit except the last
            if (i < users.length - 1) {
                vm.deal(address(token), address(token).balance + 0.1 ether);
            }

            assertEq(token.balanceOf(users[i]), expectedShares, "user should have receive proportional shares");
        }
    }

    function testFuzzMultipleDeposits(uint256 amount1, uint256 amount2, uint256 yieldAmount) public {
        // Bound inputs to reasonable ranges
        amount1 = bound(amount1, 1, 100 ether);
        amount2 = bound(amount2, 1, 100 ether);
        yieldAmount = bound(yieldAmount, 0, 100 ether);

        // First deposit
        vm.deal(alice, amount1);
        vm.prank(alice);
        token.deposit{value: amount1}();

        // Add yield
        if (yieldAmount > 0) {
            vm.deal(address(this), yieldAmount);
            (bool success,) = address(token).call{value: yieldAmount}("");
            require(success);
        }

        // Second deposit
        vm.deal(bob, amount2);
        vm.prank(bob);
        token.deposit{value: amount2}();

        // Check the ratio of shares
        assertEq(token.balanceOf(alice) * amount2, token.balanceOf(bob) * amount1);
    }

    function testFuzzSequentialDepositsWithYield(uint256[4] memory depositAmounts, uint256[3] memory yieldAmounts)
        public
    {
        // Bound inputs to reasonable ranges
        for (uint256 i = 0; i < 4; i++) {
            depositAmounts[i] = bound(depositAmounts[i], 0.1 ether, 100 ether);
        }
        for (uint256 i = 0; i < 3; i++) {
            yieldAmounts[i] = bound(yieldAmounts[i], 0.01 ether, 1 ether);
        }

        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = dave;

        // Sequential deposits with yield between each
        for (uint256 i = 0; i < users.length; i++) {
            uint256 expectedShares = i == 0
                ? depositAmounts[i] // first deposit is always 1:1
                : (depositAmounts[i] * token.totalSupply() / address(token).balance);

            vm.prank(users[i]);
            token.deposit{value: depositAmounts[i]}();

            // Add yield after each deposit except the last
            if (i < users.length - 1) {
                vm.deal(address(token), address(token).balance + yieldAmounts[i]);
            }

            assertEq(token.balanceOf(users[i]), expectedShares, "user should have received proportional shares");
        }
    }

    function testFuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound the amounts to reasonable values
        depositAmount = bound(depositAmount, 1, 100 ether);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.deal(alice, depositAmount);
        vm.startPrank(alice);

        token.deposit{value: depositAmount}();
        token.withdraw(withdrawAmount);

        assertEq(token.balanceOf(alice), depositAmount - withdrawAmount);
        vm.stopPrank();
    }

    function testInvariantTotalSupplyTracksShares() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 0.5 ether;

        uint256 expectedSupply = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            vm.deal(alice, amounts[i]);
            vm.prank(alice);
            token.deposit{value: amounts[i]}();
            expectedSupply += amounts[i];
        }

        assertEq(token.totalSupply(), expectedSupply);
    }

    function testInvariantShareValueMaintained() public {
        // Initial deposit
        vm.prank(alice);
        token.deposit{value: 1 ether}();

        uint256 initialSharePrice = address(token).balance * 1e18 / token.totalSupply();

        // Multiple operations
        vm.prank(bob);
        token.deposit{value: 2 ether}();

        vm.prank(charlie);
        token.deposit{value: 0.5 ether}();

        vm.prank(alice);
        token.withdraw(0.3 ether);

        // Share price should remain constant without yield
        uint256 finalSharePrice = address(token).balance * 1e18 / token.totalSupply();
        assertEq(initialSharePrice, finalSharePrice);
    }

    function testRevertWithdrawInsufficientBalance() public {
        vm.startPrank(alice);
        vm.expectRevert(); // Should revert due to insufficient balance
        token.withdraw(1 ether);
        vm.stopPrank();
    }

    function testRevertWithdrawToZeroAddress() public {
        vm.startPrank(alice);
        token.deposit{value: 1 ether}();

        vm.expectRevert();
        token.withdraw(address(0), 1 ether);
        vm.stopPrank();
    }

    function testRevertZeroDeposit() public {
        vm.expectRevert(ZeroDeposit.selector);
        token.deposit{value: 0}();
    }
}
