# HumanResources Smart Contract Documentation

## Overview

The HumanResources smart contract is a decentralized payroll management system implemented on the Optimism network. It enables organizations to manage employee registrations and process salary payments in either USDC or ETH, leveraging Chainlink price feeds and Uniswap V3 for currency conversions.

## Architecture

### Core Components

- **Contract**: `HumanResources.sol`
- **Network**: Optimism
- **Solidity Version**: ^0.8.24

### External Integrations

- **Chainlink Price Feed**: ETH/USD oracle for accurate price conversion
- **Uniswap V3**: Facilitates USDC-ETH swaps for salary payments
- **WETH**: Wrapped ETH for DEX interactions
- **USDC**: Stablecoin for salary denomination

### Key Addresses (Optimism)

```solidity
USDC: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85
WETH: 0x4200000000000000000000000000000000000006
Chainlink ETH/USD: 0x13e3Ee699D1909E989722E753853AE30b17e08c5
Uniswap Router: 0xE592427A0AEce92De3Edee1F18E0157C05861564
```

## Interface Implementation

### Employee Management Functions

#### `registerEmployee`
```solidity
function registerEmployee(address employee, uint256 weeklyUsdSalary) external
```
- **Description**: Registers a new employee with their weekly salary in USD
- **Access**: Only HR Manager
- **Parameters**:
  - `employee`: Employee's wallet address
  - `weeklyUsdSalary`: Weekly salary amount in USD (6 decimal places)
- **Events**: Emits `EmployeeRegistered`
- **Security**: Prevents duplicate registrations

#### `terminateEmployee`
```solidity
function terminateEmployee(address employee) external
```
- **Description**: Terminates an employee's contract
- **Access**: Only HR Manager
- **Parameters**:
  - `employee`: Address of employee to terminate
- **Events**: Emits `EmployeeTerminated`
- **Effects**: Updates employee count and sets termination timestamp

### Salary Management Functions

#### `withdrawSalary`
```solidity
function withdrawSalary() external
```
- **Description**: Processes salary payment in preferred currency (USDC/ETH)
- **Access**: Only registered employees
- **Features**:
  - Calculates pro-rated salary based on employment duration
  - Handles currency conversion if ETH is preferred
  - Implements slippage protection (2%)
- **Security**: Uses ReentrancyGuard

#### `switchCurrency`
```solidity
function switchCurrency() external
```
- **Description**: Toggles employee's preferred payment currency
- **Access**: Only registered employees
- **Events**: Emits `CurrencySwitched`
- **Process**: 
  1. Withdraws available salary in current currency
  2. Switches preference for future payments

### Query Functions

#### `salaryAvailable`
```solidity
function salaryAvailable(address employee) external view returns (uint256)
```
- **Description**: Calculates available salary for withdrawal
- **Returns**: Amount in preferred currency (USDC or ETH)
- **Calculation**: Pro-rated based on time worked since last withdrawal

#### `getHrManager`
```solidity
function getHrManager() external view returns (address)
```
- **Description**: Returns HR manager's address
- **Usage**: For verification and transparency

#### `getActiveEmployeeCount`
```solidity
function getActiveEmployeeCount() external view returns (uint256)
```
- **Description**: Returns current number of active employees
- **Updates**: Automatically maintained during registration/termination

#### `getEmployeeInfo`
```solidity
function getEmployeeInfo(address employee) external view returns (uint256, uint256, uint256)
```
- **Description**: Retrieves employee details
- **Returns**: Tuple of (weeklyUsdSalary, employedSince, terminatedAt)

## AMM Integration

The contract integrates with Uniswap V3 for USDC-ETH conversions:

1. **Price Determination**:
   - Uses Chainlink ETH/USD price feed for accurate conversion rates
   - Implements 2% slippage protection

2. **Swap Process**:
   ```solidity
   ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
       tokenIn: USDC_ADDRESS,
       tokenOut: WETH_ADDRESS,
       fee: 3000,
       recipient: address(this),
       deadline: block.timestamp + 60,
       amountIn: salary,
       amountOutMinimum: ethAmount * 98 / 100,
       sqrtPriceLimitX96: 0
   });
   ```

## Oracle Integration

Chainlink price feed integration for reliable ETH/USD conversion:

```solidity
(, int256 price,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_ADDRESS).latestRoundData();
uint256 ethAmount = salary * 1e12 / uint256(price);
```

## Security Features

### Access Control
```solidity
modifier onlyHrManager() {
    if (msg.sender != hrManager) revert NotAuthorized();
    _;
}

modifier onlyEmployee() {
    if (employees[msg.sender].weeklyUsdSalary == 0) revert NotAuthorized();
    _;
}
```
- **HR Manager Functions**: Protected by `onlyHrManager`
  - Employee registration
  - Employee termination
  - Contract pause/unpause
- **Employee Functions**: Protected by `onlyEmployee`
  - Salary withdrawal
  - Currency preference switching
- **Zero-address Validation**
- **Employee Status Checks**

### Reentrancy Protection
```solidity
contract HumanResources is IHumanResources, ReentrancyGuard, Pausable {
    // ... 
    function withdrawSalary() external nonReentrant whenNotPaused {
        // Implementation
    }
}
```
- OpenZeppelin's ReentrancyGuard implementation
- State changes before external calls
- Secure withdrawal pattern
- Check-Effects-Interaction pattern

### Circuit Breaker
```solidity
function pause() external onlyHrManager {
    _pause();
}

function unpause() external onlyHrManager {
    _unpause();
}
```
- Emergency pause functionality
- HR manager control
- Automatic operation suspension
- State preservation during pause

### Slippage Protection
```solidity
ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    // ...
    amountOutMinimum: ethAmount * 98 / 100, // 2% slippage tolerance
    // ...
});
```
- 2% slippage tolerance
- Minimum output validation
- Price impact protection
- Short-term manipulation resistance

### Time-based Protection
```solidity
deadline: block.timestamp + 60,  // 60-second deadline
```
- Short trade execution window
- Accurate timestamp handling
- Employment period validation

## Evaluation Criteria

### Correctness
#### Interface Implementation
```solidity
interface IHumanResources {
    function registerEmployee(address employee, uint256 weeklyUsdSalary) external;
    function terminateEmployee(address employee) external;
    // ...
}
```
- Complete interface compliance
- Parameter validation
- Return value accuracy
- Event emission

#### Edge Cases
- Zero value handling
- Decimal precision management
- Time calculation accuracy
- Boundary condition handling

### Security
#### Access Control Implementation
```solidity
if (msg.sender != hrManager) revert NotAuthorized();
if (employees[msg.sender].weeklyUsdSalary == 0) revert NotAuthorized();
```
- Role-based restrictions
- Function-level protection
- State validation
- Critical operation safety

#### Error Handling
```solidity
error NotAuthorized();
error EmployeeAlreadyRegistered();
error EmployeeNotRegistered();
```
- Custom error types
- Descriptive messages
- Proper revert conditions

### Integration
#### AMM Integration
```solidity
uint256 amountOut = ISwapRouter(UNISWAP_ROUTER_ADDRESS).exactInputSingle(params);
```
- Uniswap V3 compatibility
- Proper swap parameters
- Pool interaction safety

#### Oracle Integration
```solidity
(, int256 price,,,) = AggregatorV3Interface(CHAINLINK_ETH_USD_ADDRESS).latestRoundData();
```
- Chainlink price feed usage
- Price staleness checks
- Decimal conversion

### Code Quality
#### Architecture
- Modular contract design
- Clean inheritance structure
- Gas optimization
- Clear state management

#### Documentation
- NatSpec comments
- Function documentation
- Security considerations
- Integration guidelines

### Testing
#### Core Tests
```solidity
function testWithdrawSalary() public {
    // Setup
    vm.prank(hrManager);
    hr.registerEmployee(employee1, WEEKLY_SALARY);
    
    // Test logic
    skip(7 days);
    vm.prank(employee1);
    hr.withdrawSalary();
    
    // Assertions
    // ...
}
```
- Function coverage
- State transitions
- Event verification
- Error conditions

#### Integration Tests
- Cross-contract interactions
- Oracle price feeds
- AMM swaps
- Fork test environment

## Events

```solidity
event EmployeeRegistered(address indexed employee, uint256 weeklyUsdSalary)
event EmployeeTerminated(address indexed employee)
event SalaryWithdrawn(address indexed employee, bool isEth, uint256 amount)
event CurrencySwitched(address indexed employee, bool isEth)
```

## Error Handling

Custom error types for precise error reporting:
```solidity
error NotAuthorized()
error EmployeeAlreadyRegistered()
error EmployeeNotRegistered()
```

## Testing

Comprehensive test suite available in `test/HumanResources.t.sol`:
- Unit tests for all core functionalities
- Integration tests with Uniswap and Chainlink
- Fork testing on Optimism network

## License

GPL-3.0
