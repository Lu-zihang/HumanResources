# HumanResources Smart Contract Development Guide

This guide will help you set up the development environment and run the HumanResources smart contract project.

## Prerequisites

1. [Git](https://git-scm.com/downloads)
2. [Node.js](https://nodejs.org/) (v16 or higher recommended)
3. [Foundry](https://book.getfoundry.sh/getting-started/installation)

## Installation Steps

### 1. Clone the Project

```bash
git clone https://github.com/Lu-zihang/HumanResources.git
cd HumanResources
```

### 2. Install Foundry Dependencies

```bash
forge install
```

This will install:
- OpenZeppelin Contracts
- Chainlink Contracts

### 3. Install Node.js Dependencies

```bash
npm install
```

This will install:
- @uniswap/v3-periphery
- @uniswap/v3-core

## Project Structure

```
.
├── src/                    # Contract source code
│   └── HumanResources.sol
├── test/                   # Test files
│   └── HumanResources.t.sol
├── lib/                    # Foundry dependencies
│   ├── openzeppelin-contracts/
│   └── chainlink/
├── node_modules/          # Node.js dependencies
│   ├── @uniswap/v3-periphery/
│   └── @uniswap/v3-core/
└── foundry.toml          # Foundry configuration file
```

## Foundry Configuration

The project uses the following `foundry.toml` configuration:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib", "node_modules"]

remappings = [
    "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
    "@chainlink/contracts/src/=lib/chainlink/contracts/src/",
    "@uniswap/v3-periphery/=node_modules/@uniswap/v3-periphery/",
    "@uniswap/v3-core/=node_modules/@uniswap/v3-core/"
]
```

## Compiling Contracts

```bash
forge build
```

## Running Tests

### Run All Tests (Verbose Output)

```bash
forge test -vv
```
### Example console
```
[⠊] Compiling...
[⠘] Compiling 37 files with Solc 0.8.26
[⠃] Solc 0.8.26 finished in 1.71s
Compiler run successful!

Ran 15 tests for test/HumanResources.t.sol:HumanResourcesTest
[PASS] testActiveEmployeeCount() (gas: 166939)
[PASS] testFailedWithdrawals() (gas: 85805)
[PASS] testFuzz_RegisterSalary(uint256) (runs: 256, μ: 87968, ~: 87968)
[PASS] testFuzz_TimeBasedSalary(uint256) (runs: 256, μ: 89344, ~: 89344)
[PASS] testGetActiveEmployeeCount() (gas: 170212)
[PASS] testGetEmployeeInfoActive() (gas: 89594)
[PASS] testGetEmployeeInfoNonExistent() (gas: 19418)
[PASS] testGetEmployeeInfoTerminated() (gas: 94336)
[PASS] testGetHrManager() (gas: 11064)
[PASS] testPauseFunctionality() (gas: 112579)
[PASS] testRegisterEmployee() (gas: 92055)
[PASS] testSalaryCalculation() (gas: 91967)
[PASS] testSwitchCurrency() (gas: 377757)
[PASS] testTerminateEmployee() (gas: 92756)
[PASS] testWithdrawSalaryInUSDC() (gas: 140618)
Suite result: ok. 15 passed; 0 failed; 0 skipped; finished in 1.15s (152.82ms CPU time)

Ran 1 test suite in 1.17s (1.15s CPU time): 15 tests passed, 0 failed, 0 skipped (15 total tests)
```
### Run Specific Test

```bash
forge test -vv --match-test testWithdrawSalary
```

### Test Output Verbosity Levels

- `-vv`: Shows test logs and events
- `-vvv`: Shows more detailed stack traces
- `-vvvv`: Shows full debug information

## Deployment

### 1. Set Environment Variables

Create a `.env` file:

```env
OPTIMISM_RPC_URL=<your-optimism-rpc-url>
PRIVATE_KEY=<your-private-key>
HR_MANAGER_ADDRESS=<hr-manager-wallet-address>
USDC_ADDRESS=<usdc-token-address>
WETH_ADDRESS=<weth-token-address>
CHAINLINK_ETH_USD_ADDRESS=<chainlink-eth-usd-address>
UNISWAP_ROUTER_ADDRESS=<uniswap-router-address>
```

### 2. Deploy to Optimism Network

```bash
# Deploy the contract
forge create --rpc-url $OPTIMISM_RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $HR_MANAGER_ADDRESS $USDC_ADDRESS $WETH_ADDRESS $CHAINLINK_ETH_USD_ADDRESS $UNISWAP_ROUTER_ADDRESS \
    src/HumanResources.sol:HumanResources \
    --verify

# Example with actual addresses (Optimism)
forge create --rpc-url $OPTIMISM_RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $HR_MANAGER_ADDRESS \
    0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85 \
    0x4200000000000000000000000000000000000006 \
    0x13e3Ee699D1909E989722E753853AE30b17e08c5 \
    0xE592427A0AEce92De3Edee1F18E0157C05861564 \
    src/HumanResources.sol:HumanResources \
    --verify
```

Note: Make sure to set the environment variables before deployment.

The `--verify` flag will automatically verify the contract on Optimism's block explorer. Remove it if verification is not needed.

## Troubleshooting

### 1. Dependency Issues

If you encounter dependency-related errors, try:

```bash
forge clean
forge update
forge build
```

### 2. Compilation Errors

Check Solidity version compatibility:

```bash
forge --version
solc --version
```

### 3. Test Failures

Use verbose logging mode to see specific errors:

```bash
forge test -vvvv
```

## Code Style and Best Practices

1. Use `forge fmt` to format code
2. Run `forge snapshot` to generate gas reports
3. Use `forge coverage` to check test coverage

## Useful Commands

```bash
# Format code
forge fmt

# Check gas usage
forge snapshot

# Check test coverage
forge coverage

# Generate documentation
forge doc

# Clean build files
forge clean
```

## Contributing Guidelines

1. Fork the project
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

GPL-3.0
