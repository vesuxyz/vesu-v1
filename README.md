# VESU Contracts V1

This repository contains the Cairo contracts for VESU V1.

## Overview

<p align="center">
  <img width="800" alt="Screenshot 2024-05-21 at 16 26 34" src="https://github.com/vesuxyz/protocol/assets/45110941/5a5d90d0-6b6f-443c-a916-f9862ffc7d17">
</p>

## Setup

### Requirements

This project uses Starknet Foundry for testing. To install Starknet Foundry follow [these instructions](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html).

### Install

We advise that you use [nvm](https://github.com/nvm-sh/nvm) to manage your Node versions.

```sh
yarn
```

### Test

```sh
scarb run test
```

### Gas Reporting

Requires running a local devnet. You should have docker installed, then you can start the devnet by running the following command:

```shell
scarb run startDevnet
# in another terminal instance
scarb run updateGasReport
```

## Deployment

### Prerequisite

Copy and update the contents of `.env.example` to `.env`.

### Declare and deploy contracts

Declare and deploy all contracts under `src` using the account with `PRIVATE_KEY` and `ADDRESS` specified in `.env`

```sh
scarb run deployProtocol
scarb run deploySepolia
scarb run deployMainnet
```
