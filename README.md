# VESU Contracts V1

This repository contains the Cairo contracts for VESU V1.

## Setup

### Requirements

This project uses Starknet Foundry for testing. To install Starknet Foundry follow [these instructions](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html).

### Install

We advise that you use [nvm](https://github.com/nvm-sh/nvm) to manage your Node versions.

```sh
yarn
```

### Install the devnet (run in project root folder)

You should have docker installed, then you can start the devnet by running the following command:

```shell
scarb run startDevnet
```

### Test

```sh
snforge test
```

## Deployment

### Prerequisite

Copy and update the contents of `.env.example` to `.env`.

### Declare and deploy contracts

Declare and deploy all contracts under `src` using the account with `ACCOUNT_PRIVATE_KEY` and `ACCOUNT_ADDRESS` specified in `.env`

```sh
scarb run deployProtocol
```
