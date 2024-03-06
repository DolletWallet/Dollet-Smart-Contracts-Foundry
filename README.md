# Dollet Smart Contracts Repository

Welcome to the Dollet Smart Contracts repository. This repository houses a suite of smart contracts utilized by the
Dollet Wallet application, including those related to DeFi strategies.

### Prerequisites

The code is written using Solidity language and Foundry framework. Ensure you have `solc`, `forge` and `make` installed
to execute the commands.

### Environment Setup

An example `.env.example` file is provided. Duplicate this file, rename it to `.env`, and populate the variables
accordingly.

### Access Control

The contracts within this repository employ an access control system for administrators and super administrators. All
actions must be executed through a timelock contract, which includes a waiting period before actions can be performed.
Only multisignature wallets are permitted to propose or execute actions.

## DeFi Strategies

DeFi strategies are designed to facilitate the investment of crypto assets by leveraging various protocols. This
approach aims to yield higher returns for users and simplify the investment process.

Each strategy implementation may interact with different protocols and implement its own tests and deployment scripts.
However, the repository's design allows for a consistent general architecture across different implementations.

## Current Implementations

### Pendle LSDs

This strategy enables users to invest using various tokens such as USDT, USDC, ETH, WBTC, etc. Users can use the
`ERC20.approve()` or the `ERC20.permit()` functions for supported tokens. The tokens are swapped and deposited on Pendle
via the Pendle router.

The vault contract serves as the primary point of interaction with the strategy. It manages user shares and validates
inputs. The vault contract interacts with the strategy, and the strategy interacts with the underlying protocols, such
as Pendle. Pendle returns LP tokens (want) in exchange for the deposited tokens.

Over time, the deposit generates reward tokens that are compounded to yield more rewards. Compounding occurs with every
deposit and withdrawal, provided the minimum amount of rewards exceeds a certain threshold. This strategy may charge a
performance fee (from rewards) and a management fee (from deposit). The admin can adjust the percentage and recipient of
these fees.

The files related to this strategy are located at `src/strategies/pendle/` and `src/vaults/pendle`

## Testing instructions

Tests are run on forked environments, each configured within the test file itself. Ensure to populate the
`RPC_ETH_MAINNET` variable in the `.env` file.

Tests are divided into different files for the various contracts available. Predefined commands are available in the
`Makefile` to run some of these files. For example:

```bash
make test-vaults
make test-libraries
make test-oracles
make test-general
```

To run any other specific file, use: `forge test --match-path PATH_TO_FILE`

## Deployment instructions

Deployment scripts are divided into different files to provide flexibility when deploying specific contracts. The
commands to execute these scripts are located in the makefile.

```bash
make deploy-temporary-admin-structure
make deploy-strategy-helper
make deploy-fee-manager
make deploy-strategy-helper-uniswap-v3-venue
make deploy-pendle-uniswap-v3-oracle
make deploy-pendle-lsd-strategy
make deploy-pendle-lsd-vault
```
