#!/bin/bash
if nc -z 127.0.0.1 5050; then
  echo "Port is not free, devnet might be already running"
  exit 1
else
  echo "Starting Devnet"
  docker run -p 127.0.0.1:5050:5050 shardlabs/starknet-devnet-rs:8d9a2aed69098239fe68b19c9f3bfd4fd882ea43 --gas-price 36000000000 --timeout 320 --seed 0
  # docker run -p 127.0.0.1:5050:5050 shardlabs/starknet-devnet-rs:2fc753bf5ce7d4ab4f2b216cb9c1c993079dac1a --seed 0 --fork-network 'http://starknet-mainnet.public.blastapi.io'
fi
