// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {IHumanResources} from "../interfaces/IHumanResources.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract HumanResources is IHumanResources, ReentrancyGuard {
    // Constants
    // 1 week
    uint256 private constant SECONDS_PER_WEEK = 7 * 24 * 60 * 60;
    // After 2 days, 2/7ths of the weekly salary
    uint256 private constant SCALE = 1e18;
    // slippage tolerance 2%
    uint256 private constant SLIPPAGE_TOLERANCE = 98;

    // External contract addresses (Optimism mainnet)
    IERC20 public immutable USDC;
    IWETH  public immutable WETH;
    ISwapRouter public immutable swapRouter;
    AggregatorV3Interface public immutable ethUsdPriceFeed;

    // State variables
    address public immutable hr;
    uint256 private activeEmployeeCount;

    struct Employee {
        uint256 weeklyUsdSalary;
        uint256 employedSince;
        uint256 terminatedAt;
        uint256 lastWithdrawal;
        bool prefersEth;
    }

    mapping(address => Employee) private employees;

    event SwapExecuted(uint256 usdcAmount, uint256 ethAmount);

    // Modifiers
    modifier onlyHrManager() {
        if (msg.sender != hr) revert NotAuthorized();
        _;
    }

    /// @notice Modifier to restrict function access to registered employees (both active and terminated)
    /// Only checks if the employee was ever registered (employedSince != 0)
    modifier onlyEmployee() {
        if (employees[msg.sender].employedSince == 0) revert EmployeeNotRegistered();
        _;
    }

    modifier nonZeroAddress(address account) {
        if (account == address(0)) revert NotAuthorized();
        _;
    }

    receive() external payable {}

    // Initialize contract with HR manager address and setup token contracts
    constructor(address _hrManager) nonZeroAddress(_hrManager) {
        hr = _hrManager;
        USDC = IERC20(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
        WETH = IWETH(0x4200000000000000000000000000000000000006);
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        ethUsdPriceFeed = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
    }

    // Register new employee with weekly salary in USD
    function registerEmployee(
        address employee,
        uint256 weeklyUsdSalary
    ) external override onlyHrManager nonZeroAddress(employee) {
        if (
            employees[employee].employedSince != 0 && 
            employees[employee].terminatedAt == 0
        ) revert EmployeeAlreadyRegistered();

        employees[employee] = Employee({
            weeklyUsdSalary: weeklyUsdSalary,
            employedSince: block.timestamp,
            terminatedAt: 0,
            lastWithdrawal: block.timestamp,
            prefersEth: false
        });

        if (employees[employee].terminatedAt == 0) activeEmployeeCount++;

        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    // Terminate an employee's contract
    function terminateEmployee(address employee) external override onlyHrManager nonZeroAddress(employee) {
        // Load employee data from storage for gas efficiency
        Employee storage emp = employees[employee];

        // Validate employee status
        if (emp.employedSince == 0) revert EmployeeNotRegistered();
        if (emp.terminatedAt != 0)  revert EmployeeNotRegistered();

        // Update contract state
        emp.terminatedAt = block.timestamp;
        activeEmployeeCount--;

        // Emit termination event
        emit EmployeeTerminated(employee);
    }

    // Allow employee to withdraw available salary in preferred currency
    function withdrawSalary() external override nonReentrant onlyEmployee {
        Employee storage emp = employees[msg.sender];
        
        // Calculate available salary (for both active and terminated employees)
        uint256 amount = _calculateSalaryAvailable(msg.sender);
        require(amount > 0, "No salary available");

        // Update last withdrawal timestamp
        emp.lastWithdrawal = block.timestamp;

        // Convert from 18 decimals to 6 decimals for USDC
        uint256 scaledAmount = amount / 1e12;  // Convert from 1e18 to 1e6

        // Transfer in preferred currency (works for both active and terminated employees)
        if (emp.prefersEth) {
            _withdrawInEth(scaledAmount);
        } else {
            require(USDC.transfer(msg.sender, scaledAmount), "USDC transfer failed");
        }

        emit SalaryWithdrawn(msg.sender, emp.prefersEth, amount);
    }

    // Switch employee's preferred payment currency between USDC and ETH
    function switchCurrency() external override nonReentrant onlyEmployee {
        Employee storage emp = employees[msg.sender];        
        if (emp.terminatedAt != 0) revert NotAuthorized();

        bool oldPreference = emp.prefersEth;
        
        // First withdraw any accumulated salary with the current preference
        uint256 availableSalary = _calculateSalaryAvailable(msg.sender);
        if (availableSalary > 0) {
            emp.lastWithdrawal = block.timestamp;
            
            // Convert from 18 decimals to 6 decimals for USDC
            uint256 scaledAmount = availableSalary / 1e12;  // Convert from 1e18 to 1e6
            
            // Use the current (old) preference for withdrawal
            if (oldPreference) {
                _withdrawInEth(scaledAmount);
            } else {
                require(USDC.transfer(msg.sender, scaledAmount), "USDC transfer failed");
            }
            
            emit SalaryWithdrawn(msg.sender, oldPreference, availableSalary);
        }

        // Then switch the currency preference
        emp.prefersEth = !oldPreference;
        emit CurrencySwitched(msg.sender, emp.prefersEth);
    }

    // Get available salary amount for an employee
    function salaryAvailable(
        address employee
    ) external view override returns (uint256) {
        return _calculateSalaryAvailable(employee);
    }

    // Get HR manager address
    function hrManager() external view override returns (address) {
        return hr;
    }

    // Get total number of active employees
    function getActiveEmployeeCount() external view override returns (uint256) {
        return activeEmployeeCount;
    }

    // Get employee's salary and employment details
    function getEmployeeInfo(
        address employee
    ) external view override returns (
        uint256 weeklyUsdSalary,
        uint256 employedSince,
        uint256 terminatedAt
    ) {
        Employee storage emp = employees[employee];
        weeklyUsdSalary = emp.weeklyUsdSalary;
        employedSince = emp.employedSince;
        terminatedAt = emp.terminatedAt;
    }

    // Calculate available salary based on time worked
    function _calculateSalaryAvailable(
        address employee
    ) internal view returns (uint256) {
        Employee storage emp = employees[employee];
        if (emp.employedSince == 0) return 0;

        uint256 endTime = emp.terminatedAt == 0 ? block.timestamp : emp.terminatedAt;
        if (endTime <= emp.lastWithdrawal) return 0;

        uint256 timeElapsed = endTime - emp.lastWithdrawal;
        return (emp.weeklyUsdSalary * timeElapsed) / SECONDS_PER_WEEK;
    }

    // Convert USDC to ETH and send to employee
    function _withdrawInEth(uint256 usdcAmount) internal {
        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        require(price > 0, "Invalid ETH price");
        
        uint256 expectedEthAmount = (usdcAmount * 1e18) / (uint256(price) * 1e6);
        uint256 minEthAmount = (expectedEthAmount * SLIPPAGE_TOLERANCE) / 100;
    
        // Approve USDC spending
        require(USDC.approve(address(swapRouter), usdcAmount), "USDC approval failed");
        
        // Swap usdc to weth
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(USDC),
            tokenOut: address(WETH),
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: usdcAmount,
            amountOutMinimum: minEthAmount,
            sqrtPriceLimitX96: 0
        });

        // Execute swap
        uint256 ethAmount = swapRouter.exactInputSingle(params);
        require(ethAmount >= minEthAmount, "Excessive slippage");

        // Convert WETH to ETH and send to employee
        WETH.withdraw(ethAmount);
        (bool success,) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        emit SwapExecuted(usdcAmount, ethAmount);
    }
}
