// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {HumanResources} from "../src/HumanResources.sol";
import {IHumanResources} from "../interfaces/IHumanResources.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HumanResourcesTest is Test {
    HumanResources public hr;
    address public hrManager;
    address public employee1;
    address public employee2;
    
    // Optimism Mainnet addresses
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    // Test constants
    uint256 constant WEEK = 7 * 24 * 60 * 60;
    uint256 constant SCALE = 1e18;
    uint256 constant WEEKLY_SALARY = 1000 * SCALE; // 1000 USD per week

    function setUp() public {
        // Fork Optimism mainnet
        string memory rpc = vm.envString("RPC_URL");
        vm.createSelectFork(rpc);
        
        // Setup accounts
        hrManager = makeAddr("hrManager");
        employee1 = makeAddr("employee1");
        employee2 = makeAddr("employee2");
        
        // Deploy contract
        hr = new HumanResources(hrManager);
        
        // Fund contract with USDC for salary payments
        deal(USDC, address(hr), 1_000_000 * SCALE);
    }

    function test_RegisterEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        (uint256 salary, uint256 since, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY);
        assertEq(since, block.timestamp);
        assertEq(terminated, 0);
        assertEq(hr.getActiveEmployeeCount(), 1);
        vm.stopPrank();
    }

    function test_TerminateEmployee() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Terminate employee
        vm.prank(hrManager);
        hr.terminateEmployee(employee1);
        
        (,, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(terminated, block.timestamp);
        assertEq(hr.getActiveEmployeeCount(), 0);
    }

    function test_WithdrawSalary() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Advance time by 1 day
        skip(1 days);
        
        // Withdraw salary
        uint256 expectedSalary = (WEEKLY_SALARY * 1 days) / WEEK;
        // Convert expected salary from 18 decimals to 6 decimals for USDC
        uint256 scaledExpectedSalary = expectedSalary / 1e12;
        
        vm.prank(employee1);
        hr.withdrawSalary();
        
        assertEq(IERC20(USDC).balanceOf(employee1), scaledExpectedSalary);
    }

    function test_SwitchCurrency() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Switch to ETH payments
        vm.prank(employee1);
        hr.switchCurrency();
        
        // Verify currency switch
        (uint256 salary,,) = hr.getEmployeeInfo(employee1);
        // Salary amount should remain unchanged
        assertEq(salary, WEEKLY_SALARY); 
    }

    function test_RevertWhenUnauthorized() public {
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        vm.expectRevert(IHumanResources.EmployeeNotRegistered.selector);
        vm.prank(employee1);
        hr.withdrawSalary();
    }

    function test_SalaryCalculation() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Advance time
        skip(3 days);
        
        uint256 expectedSalary = (WEEKLY_SALARY * 3 days) / WEEK;
        assertEq(hr.salaryAvailable(employee1), expectedSalary);
    }

    /*function test_TerminatedEmployeeWithdrawal() public {
        // Register and terminate employee
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        skip(2 days);
        hr.terminateEmployee(employee1);
        vm.stopPrank();
        
        // Verify terminated employee can still withdraw accumulated salary
        uint256 expectedSalary = (WEEKLY_SALARY * 2 days) / WEEK;
        vm.prank(employee1);
        hr.withdrawSalary();
        
        assertEq(IERC20(USDC).balanceOf(employee1), expectedSalary);
    }*/

    function test_EarlyWithdrawalAttempt() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Try to withdraw immediately
        vm.expectRevert("No salary available");
        vm.prank(employee1);
        hr.withdrawSalary();
    }

    function test_ReregistrationAfterTermination() public {
        // Register and terminate employee
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        skip(2 days);
        hr.terminateEmployee(employee1);
        
        // Re-register the same employee
        hr.registerEmployee(employee1, WEEKLY_SALARY * 2); // Different salary
        vm.stopPrank();
        
        (uint256 salary, uint256 since, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY * 2);
        assertEq(since, block.timestamp);
        assertEq(terminated, 0);
    }

    function test_CurrencyPreferenceResetOnReregistration() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Switch to ETH
        vm.prank(employee1);
        hr.switchCurrency();
        
        // Terminate and re-register
        vm.startPrank(hrManager);
        hr.terminateEmployee(employee1);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();
        
        // Should be able to switch currency again (proving it was reset to USDC)
        vm.prank(employee1);
        hr.switchCurrency();
    }

    function test_WithdrawalAfterTerminationWithCurrencySwitch() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Accumulate some salary
        skip(3 days);
        
        // Switch to ETH
        vm.prank(employee1);
        hr.switchCurrency();
        
        // Accumulate more salary after currency switch
        skip(2 days);
        
        // Terminate employee
        vm.prank(hrManager);
        hr.terminateEmployee(employee1);
        
        // Check initial ETH balance
        uint256 initialBalance = employee1.balance;
        
        // Withdraw final salary
        vm.prank(employee1);
        hr.withdrawSalary();
        
        // Check that ETH balance has increased
        assertTrue(employee1.balance > initialBalance, "Balance should increase after withdrawal");
    }

    function test_MultipleWithdrawals() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Advance time by 2 days
        skip(2 days);
        
        // First withdrawal
        uint256 expectedSalary = (WEEKLY_SALARY * 2 days) / WEEK;
        // Convert expected salary from 18 decimals to 6 decimals for USDC
        uint256 scaledExpectedSalary = expectedSalary / 1e12;
        
        vm.prank(employee1);
        hr.withdrawSalary();
        
        assertEq(IERC20(USDC).balanceOf(employee1), scaledExpectedSalary);
        
        // Advance time by another 3 days
        skip(3 days);
        
        // Second withdrawal
        uint256 expectedSalary2 = (WEEKLY_SALARY * 3 days) / WEEK;
        // Convert expected salary from 18 decimals to 6 decimals for USDC
        uint256 scaledExpectedSalary2 = expectedSalary2 / 1e12;
        
        vm.prank(employee1);
        hr.withdrawSalary();
        
        assertEq(IERC20(USDC).balanceOf(employee1), scaledExpectedSalary + scaledExpectedSalary2);
    }
}
