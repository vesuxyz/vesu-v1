#!/bin/bash

set -o allexport
source .env
set +o allexport

sed -e "s~MAINNET_RPC_URL~$MAINNET_RPC_URL~g" \
    Scarb.toml.template > Scarb.toml
