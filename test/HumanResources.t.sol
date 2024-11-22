// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../lib/forge-std/src/Test.sol";
import "../src/HumanResources.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol"; // Import Chainlink ETH/USD price interface

contract HumanResourcesTest is Test {
    // Contract instance
    HumanResources public hr;
    
    // Test accounts
    address public hrManager;
    address public employee1;
    address public employee2;
    
    // Contract addresses on Optimism
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    // Chainlink ETH/USD price feed address
    address constant CHAINLINK_ETH_USD_ADDRESS = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
    
    // Initial USDC balance
    uint256 constant INITIAL_USDC_BALANCE = 1000000 * 1e6; // 1,000,000 USDC
    
    // Weekly salary amount (in USDC with 6 decimals)
    uint256 constant WEEKLY_SALARY = 1000 * 1e6; // 1,000 USDC
    
    function setUp() public {
        // Set up fork environment with latest Optimism block
        vm.createSelectFork("https://rpc.ankr.com/optimism", 128235869);
        
        // Set up test accounts
        hrManager = makeAddr("hrManager");
        employee1 = makeAddr("employee1");
        employee2 = makeAddr("employee2");
        
        // Deploy contract
        vm.prank(hrManager);
        hr = new HumanResources();
        
        // Transfer initial USDC and WETH to contract
        deal(USDC, address(hr), INITIAL_USDC_BALANCE);
        deal(WETH, address(hr), INITIAL_USDC_BALANCE);
        
        // Verify initial balances
        assertEq(IERC20(USDC).balanceOf(address(hr)), INITIAL_USDC_BALANCE);
        assertEq(IERC20(WETH).balanceOf(address(hr)), INITIAL_USDC_BALANCE);
    }
    
    /// @notice Test employee registration
    function testRegisterEmployee() public {
        // Try registering with non-HR account (should fail)
        vm.prank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Register with HR account (should succeed)
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Verify employee info
        (uint256 salary, uint256 employedSince,) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY);
        assertEq(employedSince, block.timestamp);
        
        // Try registering same employee again (should fail)
        vm.prank(hrManager);
        vm.expectRevert(IHumanResources.EmployeeAlreadyRegistered.selector);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
    }
    
    /// @notice Test employee termination
    function testTerminateEmployee() public {
        // Register employee first
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Try terminating with non-HR account (should fail)
        vm.prank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.terminateEmployee(employee1);
        
        // Terminate with HR account (should succeed)
        vm.prank(hrManager);
        hr.terminateEmployee(employee1);
        
        // Verify termination status
        (,, uint256 terminatedAt) = hr.getEmployeeInfo(employee1);
        assertEq(terminatedAt, block.timestamp);
    }
    
    /// @notice Test salary calculation
    function testSalaryCalculation() public {
        // Register employee
        vm.prank(hrManager);
        // 1000 usd
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Advance time by 2 week
        skip(14 days);
        
        // Check available salary
        uint256 availableSalary = hr.salaryAvailable(employee1);
        console.log("weekly salary:", availableSalary);
        assertEq(availableSalary, WEEKLY_SALARY * 2);
    }
    
    /// @notice Test USDC salary withdrawal
    function testWithdrawSalaryInUSDC() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Advance time by 1 week
        skip(7 days);
        
        // Withdraw salary
        vm.prank(employee1);
        hr.withdrawSalary();
        
        // Verify USDC balance
        assertEq(IERC20(USDC).balanceOf(employee1), WEEKLY_SALARY);
    }
    
    /// @notice Test currency switching
    function testSwitchCurrency() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Advance time by 1 week to accumulate salary
        skip(7 days);
        
        // Switch to ETH payments
        vm.prank(employee1);
        hr.switchCurrency();  // This will pay in USDC first
        
        // Advance time again to accumulate salary in ETH mode
        skip(7 days);
        
        // Record initial ETH balance
        uint256 initialBalance = employee1.balance;
        
        // Now withdraw in ETH mode
        vm.prank(employee1);
        hr.withdrawSalary();
        
        // Verify ETH balance increased with fees and slippage consideration
        uint256 ethAmount = WEEKLY_SALARY * 1e12 / uint256(getEthUsdPrice());
        // Account for 0.3% Uniswap fee and additional 1% for price impact and rounding
        uint256 minExpectedAmount = ethAmount * 987 / 1000; // 98.7% of expected amount
        assertTrue(employee1.balance >= initialBalance + minExpectedAmount, "ETH received is less than minimum expected");
        
        // Check USDC balance decreased (with 0.3% slippage tolerance)
        uint256 expectedUsdcBalance = INITIAL_USDC_BALANCE - (2 * WEEKLY_SALARY);
        uint256 actualUsdcBalance = IERC20(USDC).balanceOf(address(hr));
        assertTrue(
            actualUsdcBalance >= expectedUsdcBalance - (expectedUsdcBalance * 3 / 1000) &&
            actualUsdcBalance <= expectedUsdcBalance,
            "USDC balance outside acceptable range"
        );
    }
    
    /// @notice Test active employee count
    function testActiveEmployeeCount() public {
        assertEq(hr.getActiveEmployeeCount(), 0);
        
        // Register two employees
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.registerEmployee(employee2, WEEKLY_SALARY);
        vm.stopPrank();
        
        assertEq(hr.getActiveEmployeeCount(), 2);
        
        // Terminate one employee
        vm.prank(hrManager);
        hr.terminateEmployee(employee1);
        
        assertEq(hr.getActiveEmployeeCount(), 1);
    }

    /// @notice Test failed scenarios
    function testFailedWithdrawals() public {
        // Test withdrawal without registration
        vm.prank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.withdrawSalary();

        // Test withdrawal with zero salary
        vm.prank(hrManager);
        hr.registerEmployee(employee1, 0);
        vm.prank(employee1);
        vm.expectRevert("No salary to withdraw");
        hr.switchCurrency();

        // Test withdrawal after termination
        vm.prank(hrManager);
        hr.registerEmployee(employee2, WEEKLY_SALARY);
        hr.terminateEmployee(employee2);
        skip(7 days);
        vm.prank(employee2);
        hr.withdrawSalary(); // Should succeed but with final payment
        vm.prank(employee2);
        vm.expectRevert("No salary to withdraw");
        hr.withdrawSalary(); // Should fail on second attempt
    }

    /// @notice Fuzz test salary registration
    function testFuzz_RegisterSalary(uint256 salary) public {
        vm.assume(salary > 0 && salary < 1000000 * 1e18); // Reasonable salary range
        
        vm.prank(hrManager);
        hr.registerEmployee(employee1, salary);
        
        (uint256 registeredSalary,,) = hr.getEmployeeInfo(employee1);
        assertEq(registeredSalary, salary);
    }

    /// @notice Fuzz test time-based salary calculation
    function testFuzz_TimeBasedSalary(uint256 timeSkip) public {
        vm.assume(timeSkip > 0 && timeSkip < 365 days); // Maximum 1 year
        
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        skip(timeSkip);
        
        uint256 expectedSalary = (WEEKLY_SALARY * timeSkip) / (7 days);
        uint256 actualSalary = hr.salaryAvailable(employee1);
        
        // Allow for small rounding differences
        assertApproxEqRel(actualSalary, expectedSalary, 1e16); // 1% tolerance
    }

    /// @notice Test contract pause functionality
    function testPauseFunctionality() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Pause contract
        vm.startPrank(hrManager);
        hr.pause();
        vm.stopPrank();
        
        // Try operations while paused
        vm.startPrank(employee1);
        // 0xd93c0665 -> _requireNotPaused
        vm.expectRevert(0xd93c0665);
        hr.withdrawSalary();
        // 0xd93c0665 -> _requireNotPaused
        vm.expectRevert(0xd93c0665);
        hr.switchCurrency();
        vm.stopPrank();
        
        // Unpause and verify operations work again
        vm.startPrank(hrManager);
        hr.unpause();
        vm.stopPrank();

        vm.prank(employee1);
        hr.switchCurrency(); // Should work now
    }

    /// @notice Test getHrManager function
    function testGetHrManager() public view {
        assertEq(hr.getHrManager(), hrManager, "HR manager address mismatch");
    }

    /// @notice Test getActiveEmployeeCount function
    function testGetActiveEmployeeCount() public {
        // Initial count should be 0
        assertEq(hr.getActiveEmployeeCount(), 0, "Initial employee count should be 0");

        // Register one employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        assertEq(hr.getActiveEmployeeCount(), 1, "Count should be 1 after registration");

        // Register another employee
        vm.prank(hrManager);
        hr.registerEmployee(employee2, WEEKLY_SALARY);
        assertEq(hr.getActiveEmployeeCount(), 2, "Count should be 2 after second registration");

        // Terminate one employee
        vm.prank(hrManager);
        hr.terminateEmployee(employee1);
        assertEq(hr.getActiveEmployeeCount(), 1, "Count should be 1 after termination");
    }

    /// @notice Test getEmployeeInfo function for non-existent employee
    function testGetEmployeeInfoNonExistent() public view {
        // Test non-existent employee
        (uint256 salary, uint256 employed, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(salary, 0, "Non-existent employee salary should be 0");
        assertEq(employed, 0, "Non-existent employee employment time should be 0");
        assertEq(terminated, 0, "Non-existent employee termination time should be 0");
    }

    /// @notice Test getEmployeeInfo function for active employee
    function testGetEmployeeInfoActive() public {
        // Register employee
        vm.prank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        
        // Check active employee info
        (uint256 salary, uint256 employed, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY, "Active employee salary mismatch");
        assertEq(employed, block.timestamp, "Active employee employment time mismatch");
        assertEq(terminated, 0, "Active employee should not have termination time");
    }

    /// @notice Test getEmployeeInfo function for terminated employee
    function testGetEmployeeInfoTerminated() public {
        // Register and then terminate employee
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        skip(1 days); // Add some time gap
        hr.terminateEmployee(employee1);
        vm.stopPrank();
        
        // Check terminated employee info
        (uint256 salary, uint256 employed, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY, "Terminated employee salary should remain unchanged");
        assertTrue(employed > 0, "Terminated employee should have employment time");
        assertTrue(terminated > employed, "Termination time should be after employment time");
        assertEq(terminated, block.timestamp, "Termination time should match block timestamp");
    }

    /// @notice Get ETH/USD price from Chainlink
    function getEthUsdPrice() internal view returns (int256) {
        (, int256 price,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_ADDRESS).latestRoundData();
        return price;
    }
}