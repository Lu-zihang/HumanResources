// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IWETH is IERC20 {
    /// @notice This function is used to swap ETH for WETH or WETH for ETH
    function withdraw(uint256) external;
}

interface IHumanResources {
    /// @notice This error is raised if a user tries to call a function they are not authorized to call
    error NotAuthorized();

    /// @notice This error is raised if a user tries to register an employee that is already registered
    error EmployeeAlreadyRegistered();

    /// @notice This error is raised if a user tries to terminate an employee that is not registered
    error EmployeeNotRegistered();

    /// @notice This event is emitted when an employee is registered
    event EmployeeRegistered(address indexed employee, uint256 weeklyUsdSalary);

    /// @notice This event is emitted when an employee is terminated
    event EmployeeTerminated(address indexed employee);

    /// @notice This event is emitted when an employee withdraws their salary
    /// @param amount must be the amount in the currency the employee prefers ( USDC or ETH ) scaled correctly
    event SalaryWithdrawn(address indexed employee, bool isEth, uint256 amount);

    /// @notice This event is emitted when an employee switches the currency in which they receive the salary
    event CurrencySwitched(address indexed employee, bool isEth);

    /// HR manager functions
    /// Only the address returned by the hrManager  below is able to call these functions
    /// If anyone else tries to call them , the transaction must revert with the NotAuthorized  error above
    /// Registers an employee in the HR system
    /// @param employee address of the employee
    /// @param weeklyUsdSalary salary of the employee in USD scaled with 18 decimals
    function registerEmployee(address employee, uint256 weeklyUsdSalary) external;

    /// Terminates the contract of a given an employee .
    /// The salary of the employee will stop being accumulated .
    /// @param employee address of the employee
    function terminateEmployee(address employee) external;

    /// Employee functions
    /// These are only be callabale by employees
    /// If anyone else tries to call them , the transaction shall revert with the NotAuthorized  error above
    /// Only the withdrawSalary  can be called by non - active (i.e. terminated ) employees
    /// Withdraws the salary of the employee
    /// This sends either USDC or ETH to the employee , depending on the employee s preference
    /// The salary accumulates with time ( regardless of nights , weekends , and other non working hours ) according to the employee weekly salary
    /// This means that after 2 days , the employee will be able to withdraw 2/7 th of his weekly salary
    function withdrawSalary() external;

    /// Switches the currency in which the employee receives the salary
    /// By default , the salary is paid in USDC
    /// If the employee calls this function , the salary will be paid in ETH
    /// If he calls it again , the salary will be paid in USDC again
    /// When the salary is paid in ETH , the contract will swap the amount to be paid from USDC to ETH
    /// When this function is called , the current accumulated salary should be withdrawn automatically ( emitting the ‘SalaryWithdrawn ‘ event )
    function switchCurrency() external;

    // Views
    /// Returns the salary available for withdrawal for a given employee
    /// This returns the amount in the currency the employee prefers ( USDC or ETH )
    /// The amount must be scaled with the correct number of decimals for the currency
    /// @param employee the address of the employee
    function salaryAvailable(address employee) external view returns (uint256);

    /// Returns the address of the HR manager
    function getHrManager() external view returns (address);

    /// Returns the number of active employees registered in the HR system
    function getActiveEmployeeCount() external view returns (uint256);

    /// Returns information about an employee
    /// If the employee does not exist , the function does not revert but all values returned must be 0
    /// @param employee the address of the employee
    /// @return weeklyUsdSalary the weekly salary of the employee in USD , scaled with 18 decimals
    /// @return employedSince the timestamp at which the employee was registered
    /// @return terminatedAt the timestamp at which the employee was terminated (or 0 if the employee is still active )
    function getEmployeeInfo(address employee) external view returns (uint256, uint256, uint256);
}

contract HumanResources is IHumanResources, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    // Constants
    /// @notice The Uniswap V3 fee -> 0.3%
    uint24  public constant UNISWAP_FEE                 = 3000;
    address public constant USDC_ADDRESS                = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address public constant WETH_ADDRESS                = 0x4200000000000000000000000000000000000006;
    address public constant CHAINLINK_ETH_USD_ADDRESS   = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
    address public constant UNISWAP_ROUTER_ADDRESS      = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // HR manager address
    address public immutable hrManager;

    // Employee information struct
    struct Employee {
        uint256 weeklyUsdSalary; // Weekly salary (USD, 6 decimals)
        uint256 employedSince; // Employment start timestamp
        uint256 terminatedAt; // Termination timestamp (0 if not terminated)
        bool isEthPreferred; // Preference for ETH payments
    }

    // Employee mapping
    mapping(address => Employee) public employees;
    // Active employee count
    uint256 public activeEmployeeCount;

    // Constructor: sets HR manager address
    constructor() {
        hrManager = msg.sender;
    }

    /// Modifier: only HR manager can call
    modifier onlyHrManager() {
        if (msg.sender != hrManager) revert NotAuthorized();
        _;
    }

    /// Modifier: only employees can call
    modifier onlyEmployee() {
        if (employees[msg.sender].weeklyUsdSalary == 0) revert NotAuthorized();
        _;
    }

    /// @notice Register employee
    function registerEmployee(address employee, uint256 weeklyUsdSalary) external onlyHrManager {
        if (employee == address(0)) revert NotAuthorized();
        if (employees[employee].weeklyUsdSalary != 0) revert EmployeeAlreadyRegistered();

        employees[employee] = Employee({
            weeklyUsdSalary:    weeklyUsdSalary,
            employedSince:      block.timestamp,
            terminatedAt:       0,
            isEthPreferred:     false
        });
        activeEmployeeCount++;

        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    /// @notice Terminate employee
    function terminateEmployee(address employee) external onlyHrManager {
        if (employee == address(0)) revert NotAuthorized();
        if (employees[employee].weeklyUsdSalary == 0) revert EmployeeNotRegistered();

        employees[employee].terminatedAt = block.timestamp;
        activeEmployeeCount--;

        emit EmployeeTerminated(employee);
    }

    /// @notice Calculate employee's available salary
    function calculateSalary(address employee) public view returns (uint256) {
        Employee memory emp = employees[employee];
        if (emp.weeklyUsdSalary == 0) return 0;
        
        uint256 timeWorked = emp.terminatedAt > 0 ? 
            emp.terminatedAt - emp.employedSince : block.timestamp - emp.employedSince;
        
        // Then calculate the pro-rata amount
        // Multiply first to maintain precision
        uint256 salary = (emp.weeklyUsdSalary * timeWorked) / (7 days);
        
        return salary;
    }

    /// @notice Withdraw salary
    function withdrawSalary() external nonReentrant whenNotPaused onlyEmployee {
        uint256 salary = calculateSalary(msg.sender);
        if (salary == 0) return;

        uint256 minAmountOut = salary * 98 / 100;
        if (employees[msg.sender].isEthPreferred) {
            // Get ETH/USD price
            (, int256 price,,, ) = AggregatorV3Interface(CHAINLINK_ETH_USD_ADDRESS).latestRoundData();
            uint256 ethAmount = USDCAmountToWETH(salary, 6) / uint256(price);

            // Swap USDC for ETH
            IERC20(USDC_ADDRESS).approve(UNISWAP_ROUTER_ADDRESS, salary); 
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC_ADDRESS,
                tokenOut: WETH_ADDRESS,
                fee: UNISWAP_FEE,
                recipient: address(this),
                deadline: block.timestamp + 60,
                amountIn: salary,
                amountOutMinimum: ethAmount * 98 / 100, 
                sqrtPriceLimitX96: 0
            });
            uint256 amountOut = ISwapRouter(UNISWAP_ROUTER_ADDRESS).exactInputSingle(params);
            require(amountOut >= minAmountOut, "Insufficient withdrawable amount");

            // Withdraw WETH and send to employee
            IWETH(WETH_ADDRESS).withdraw(amountOut);
            (bool success, ) = payable(msg.sender).call{value: amountOut}('');
            require(success, "Withdraw failed");

            emit SalaryWithdrawn(msg.sender, true, amountOut);
        } else {
            // Send USDC directly
            IERC20(USDC_ADDRESS).safeTransfer(msg.sender, salary);
            emit SalaryWithdrawn(msg.sender, false, salary);
        }
    }

    /// @notice Switch salary payment currency
    function switchCurrency() external nonReentrant whenNotPaused onlyEmployee {
        // Withdraw current salary
        uint256 salary = calculateSalary(msg.sender);
        if (salary == 0) return;

        uint256 minAmountOut = salary * 98 / 100;
        if (employees[msg.sender].isEthPreferred) {
            // Get ETH/USD price
            (, int256 price,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_ADDRESS).latestRoundData();
            uint256 ethAmount = USDCAmountToWETH(salary, 6) / uint256(price);

            // Swap USDC for ETH
            IERC20(USDC_ADDRESS).approve(UNISWAP_ROUTER_ADDRESS, salary); 
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC_ADDRESS,
                tokenOut: WETH_ADDRESS,
                fee: UNISWAP_FEE,
                recipient: address(this),
                deadline: block.timestamp + 60,
                amountIn: salary,
                amountOutMinimum: ethAmount * 98 / 100, 
                sqrtPriceLimitX96: 0
            });

            uint256 amountOut = ISwapRouter(UNISWAP_ROUTER_ADDRESS).exactInputSingle(params);
            require(amountOut >= minAmountOut, "Insufficient withdrawable amount");

            // Withdraw WETH and send to employee
            IWETH(WETH_ADDRESS).withdraw(amountOut);
            (bool success, ) = payable(msg.sender).call{value: amountOut}('');
            require(success, "Withdraw failed");

            emit SalaryWithdrawn(msg.sender, true, amountOut);
        } else {
            // Send USDC directly
            IERC20(USDC_ADDRESS).safeTransfer(msg.sender, salary);

            emit SalaryWithdrawn(msg.sender, false, salary);
        }

        employees[msg.sender].isEthPreferred = !employees[msg.sender].isEthPreferred;
        
        emit CurrencySwitched(msg.sender, employees[msg.sender].isEthPreferred);
    }

    /// @notice View employee's available salary
    function salaryAvailable(address employee) external view returns (uint256) {
        uint256 salary = calculateSalary(employee);
        if (employees[employee].isEthPreferred) {
            (, int256 price,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_ADDRESS).latestRoundData();
            return USDCAmountToWETH(salary, 6) / uint256(price);
        } else {
            return salary;
        }
    }

    /// @notice Get HR manager address
    function getHrManager() external view returns (address) {
        return hrManager;
    }

    /// @notice Get active employee count
    function getActiveEmployeeCount() external view returns (uint256) {
        return activeEmployeeCount;
    }

    /// @notice Get employee information
    function getEmployeeInfo(address employee) external view returns (uint256, uint256, uint256) {
        return (
            employees[employee].weeklyUsdSalary,
            employees[employee].employedSince,
            employees[employee].terminatedAt
        );
    }

    /// @notice Pause the contract
    /// @dev Only callable by the HR manager
    function pause() external onlyHrManager {
        _pause();
    }

    /// @notice Unpause the contract
    /// @dev Only callable by the HR manager
    function unpause() external onlyHrManager {
        _unpause();
    }

    /// ======================== Library Functions ========================

    /// @notice Converts token amount between different decimal precisions
    /// @param tokenAmount The amount to convert
    /// @param tokenDecimals The decimal precision of the input amount
    /// @param targetDecimals The desired decimal precision for the output
    /// @return The converted amount with target decimal precision
    function tokenAmountToDecimals(uint256 tokenAmount, uint8 tokenDecimals, uint8 targetDecimals)
        internal
        pure
        returns (uint256)
    {
        if (tokenDecimals < targetDecimals) {
            return tokenAmount * (10 ** uint256(targetDecimals - tokenDecimals));
        } else if (tokenDecimals > targetDecimals) {
            // Add half divisor for rounding
            uint256 divisor = 10 ** uint256(tokenDecimals - targetDecimals);
            return (tokenAmount + (divisor / 2)) / divisor;
        }
        return tokenAmount;
    }

    /// @notice Converts any token amount to WETH's 18 decimal precision
    /// @param tokenAmount The amount to convert
    /// @param tokenDecimals The decimal precision of the input amount
    /// @return The amount converted to 18 decimal precision
    function USDCAmountToWETH(uint256 tokenAmount, uint8 tokenDecimals)
        internal
        pure
        returns (uint256)
    {
        if (tokenDecimals == 6) { // 如果是 USDC (6位小数)
            return tokenAmount * 1e12; // 直接乘以 1e12 转换为 18 位小数
        }
        // 其他情况使用通用转换
        return tokenAmountToDecimals(tokenAmount, tokenDecimals, 18);
    }

    /// @notice Converts any token amount to USDC's 6 decimal precision
    /// @param tokenAmount The amount to convert
    /// @param tokenDecimals The decimal precision of the input amount
    /// @return The amount converted to 6 decimal precision
    function WETHAmountToUSDC(uint256 tokenAmount, uint8 tokenDecimals)
        internal
        pure
        returns (uint256)
    {
        if (tokenDecimals == 18) { // 如果是 WETH (18位小数)
            return tokenAmount / 1e12; // 直接除以 1e12 转换为 6 位小数
        }
        // 其他情况使用通用转换
        return tokenAmountToDecimals(tokenAmount, tokenDecimals, 6);
    }

    receive() external payable {}
}