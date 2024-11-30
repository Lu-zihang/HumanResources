# HumanResources Smart Contract Documentation

This document explains how the HumanResources contract implements each function in the IHumanResources interface, and details the integration of AMM (Uniswap V3) and Oracle (Chainlink) for currency conversion.

## Core Features

- **Dual Currency Support**: Employees can choose to receive salaries in either USDC or ETH
- **Dynamic Salary Calculation**: Pro-rata calculation based on time elapsed
- **Automated Currency Conversion**: Seamless conversion between USDC and ETH using Uniswap V3
- **Price Oracle Integration**: Real-time ETH/USD price feeds from Chainlink
- **Access Control**: Role-based permissions for HR managers and employees
- **Gas Optimization**: Efficient storage layout and gas-optimized operations

## Interface Implementation

### HR Manager Functions

#### `registerEmployee(address employee, uint256 weeklyUsdSalary)`
Implements employee registration with the following features:
- Enforces HR manager-only access through `onlyHrManager` modifier
- Validates employee address is not zero using `nonZeroAddress` modifier
- Checks if employee is already registered and active
- Initializes employee struct with:
  - Weekly salary in USD (18 decimals)
  - Current timestamp for employedSince and lastWithdrawal
  - Default currency preference as USDC (prefersEth = false)
- Increments activeEmployeeCount for new employees
- Emits `EmployeeRegistered` event with employee address and salary
- Error cases:
  - Reverts with `NotAuthorized` if caller is not HR manager
  - Reverts with `EmployeeAlreadyRegistered` if employee is active

#### `terminateEmployee(address employee)`
Handles employee termination with:
- Restricts access to HR manager through `onlyHrManager` modifier
- Validates employee exists and is not already terminated
- Records termination timestamp
- Decrements activeEmployeeCount
- Emits `EmployeeTerminated` event
- Preserves employee data for salary withdrawal
- Error cases:
  - Reverts with `NotAuthorized` if caller is not HR manager
  - Reverts with `EmployeeNotRegistered` if employee doesn't exist or is terminated

### Employee Functions

#### `withdrawSalary()`
Processes salary withdrawals with these features:
- Validates caller is a registered employee using `onlyEmployee` modifier
- Protects against reentrancy with `nonReentrant` modifier
- Calculates available salary based on time elapsed:
  - For active employees: from last withdrawal to current time
  - For terminated employees: from last withdrawal to termination time
- Handles both USDC and ETH payments:
  - USDC: Direct transfer after decimal conversion (18 -> 6)
  - ETH: Multi-step conversion process:
    1. Gets ETH/USD price from Chainlink oracle
    2. Calculates expected ETH amount based on price
    3. Applies 2% slippage tolerance
    4. Approves USDC spending for Uniswap
    5. Executes swap through Uniswap V3
    6. Converts WETH to ETH
    7. Transfers ETH to employee
- Updates lastWithdrawal timestamp
- Emits `SalaryWithdrawn` event with amount and currency type
- Error cases:
  - Reverts if no salary is available
  - Reverts if USDC transfer fails
  - Reverts if slippage is too high
  - Reverts if ETH transfer fails

#### `switchCurrency()`
Manages payment currency preference:
- Restricts access to active employees only
- Automatically processes any pending salary withdrawal:
  - Calculates available amount
  - Processes withdrawal in current currency preference
  - Updates lastWithdrawal timestamp
- Toggles prefersEth flag in employee struct
- Emits both `SalaryWithdrawn` (if applicable) and `CurrencySwitched` events
- Error cases:
  - Reverts with `NotAuthorized` if employee is terminated
  - Reverts if withdrawal of pending salary fails

### View Functions

#### `salaryAvailable(address employee)`
Calculates withdrawable salary:
- Returns amount in employee's preferred currency
- Uses pro-rata calculation: (elapsed_time * weekly_salary) / SECONDS_PER_WEEK
- Handles both active and terminated employees:
  - Active: uses current timestamp as end time
  - Terminated: uses termination timestamp as end time
- Returns 0 for:
  - Non-existent employees
  - No time elapsed since last withdrawal
  - Already fully paid employees

#### `hrManager()`
- Returns the immutable HR manager address set at deployment
- Used for access control validation

#### `getActiveEmployeeCount()`
- Returns current count of non-terminated employees
- Maintained through:
  - Increment in registerEmployee
  - Decrement in terminateEmployee
- Used for tracking total active workforce

#### `getEmployeeInfo(address employee)`
Returns employee details:
- weeklyUsdSalary: Base salary rate (18 decimals)
- employedSince: Registration timestamp
- terminatedAt: Termination timestamp or 0 if active
- Returns zeros for non-existent employees
- Gas optimized using single storage read

## Technical Details

### Storage Layout
```solidity
struct Employee {
    uint256 weeklyUsdSalary;    // Weekly salary in USD (18 decimals)
    uint256 employedSince;       // Employment start timestamp
    uint256 terminatedAt;        // Termination timestamp (0 if active)
    uint256 lastWithdrawal;      // Last salary withdrawal timestamp
    bool prefersEth;             // Payment currency preference
}
```

### Constants
- `SECONDS_PER_WEEK`: 604800 (7 * 24 * 60 * 60)
- `SCALE`: 1e18 (internal calculation precision)
- `SLIPPAGE_TOLERANCE`: 98 (2% slippage protection)

## Integration Details

### Uniswap V3 Integration
Used for USDC to ETH conversion in salary payments:
- SwapRouter (`0xE592427A0AEce92De3Edee1F18E0157C05861564`)
- Configuration:
  - Pool fee: 0.3% (3000)
  - Slippage tolerance: 2%
  - Deadline: Current block timestamp
- Swap Process:
  1. Pre-swap:
     - Calculate expected ETH amount using oracle price
     - Determine minimum acceptable output
     - Approve USDC spending
  2. Swap execution:
     - Use exactInputSingle for precise USDC input
     - Verify received ETH meets minimum threshold
  3. Post-swap:
     - Convert WETH to ETH
     - Transfer to employee

### Chainlink Price Feed
Provides ETH/USD conversion rate:
- Price feed: `0x13e3Ee699D1909E989722E753853AE30b17e08c5`
- Implementation:
  - Uses AggregatorV3Interface
  - Fetches latest round data
  - Validates price feed health
- Price Calculation:
  - Converts USDC amount to expected ETH
  - Accounts for decimal differences
  - Used in slippage calculations

## Contract Dependencies
- USDC: `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` (6 decimals)
- WETH: `0x4200000000000000000000000000000000000006` (18 decimals)
- OpenZeppelin:
  - ReentrancyGuard for withdrawal security
  - IERC20 for token interactions
- Custom error types for specific failure cases

## Security Features
- **Reentrancy Protection**:
  - Uses OpenZeppelin's ReentrancyGuard
  - Critical state changes before external calls
- **Access Control**:
  - Role-based modifiers
  - Zero address validation
  - Employee status verification
- **Economic Security**:
  - Slippage protection in swaps
  - Price feed validation
  - Safe decimal handling
- **Error Handling**:
  - Custom error types
  - Comprehensive require statements
  - Event emissions for tracking
