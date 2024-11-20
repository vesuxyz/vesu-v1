import { assert } from "console";
import fs from "fs";
import { CallData, shortString, uint256 } from "starknet";
import { Amount, SCALE, formatRate, setup, toAddress, toI257 } from "../lib";

const deployer = await setup("sepolia");
const protocol = await deployer.deployEnvAndProtocol();
const { singleton, assets, extensionPO } = protocol;

// CREATE POOL

const [pool] = await protocol.createPool("genesis-pool", { devnetEnv: true });

assert(
  toAddress(await extensionPO.pragma_oracle()) === protocol.pragma.oracle.address.toLowerCase(),
  "pragma_oracle-neq",
);
assert(toAddress(await extensionPO.pool_owner(pool.id)) === pool.params.owner.toLowerCase(), "pool_owner-neq");
assert(
  toAddress((await extensionPO.fee_config(pool.id)).fee_recipient) ===
    pool.params.fee_params.fee_recipient.toLowerCase(),
  "fee_recipient-neq",
);
const shutdown_config = await extensionPO.shutdown_config(pool.id);
assert(shutdown_config.recovery_period === pool.params.shutdown_params.recovery_period, "recovery_period-neq");
assert(
  shutdown_config.subscription_period === pool.params.shutdown_params.subscription_period,
  "subscription_period-neq",
);

for (const [index, asset] of assets.entries()) {
  const oracle_config = await extensionPO.oracle_config(pool.id, asset.address);
  assert(
    shortString.decodeShortString(oracle_config.pragma_key) === pool.params.pragma_oracle_params[index].pragma_key,
    "pragma_key-neq",
  );
  assert(oracle_config.timeout === pool.params.pragma_oracle_params[index].timeout, "timeout-neq");
  assert(
    oracle_config.number_of_sources === pool.params.pragma_oracle_params[index].number_of_sources,
    "number_of_sources-neq",
  );

  const interest_rate_config = await extensionPO.interest_rate_config(pool.id, asset.address);
  assert(
    interest_rate_config.min_target_utilization === pool.params.interest_rate_configs[index].min_target_utilization,
    "min_target_utilization-neq",
  );
  assert(
    interest_rate_config.max_target_utilization === pool.params.interest_rate_configs[index].max_target_utilization,
    "max_target_utilization-neq",
  );
  assert(
    interest_rate_config.target_utilization === pool.params.interest_rate_configs[index].target_utilization,
    "target_utilization-neq",
  );
  assert(
    interest_rate_config.min_full_utilization_rate ===
      pool.params.interest_rate_configs[index].min_full_utilization_rate,
    "min_full_utilization_rate-neq",
  );
  assert(
    interest_rate_config.max_full_utilization_rate ===
      pool.params.interest_rate_configs[index].max_full_utilization_rate,
    "max_full_utilization_rate-neq",
  );
  assert(
    interest_rate_config.zero_utilization_rate === pool.params.interest_rate_configs[index].zero_utilization_rate,
    "zero_utilization_rate-neq",
  );
  assert(
    interest_rate_config.rate_half_life === pool.params.interest_rate_configs[index].rate_half_life,
    "rate_half_life-neq",
  );
  assert(
    interest_rate_config.target_rate_percent === pool.params.interest_rate_configs[index].target_rate_percent,
    "target_rate_percent-neq",
  );

  const { "0": asset_config } = await singleton.asset_config_unsafe(pool.id, asset.address);
  assert(asset_config.total_collateral_shares === 0n, "total_collateral_shares-neq");
  assert(asset_config.total_nominal_debt === 0n, "total_nominal_debt-neq");
  assert(asset_config.reserve === 0n, "reserve-neq");
  assert(asset_config.max_utilization > 0n, "max_utilization-neq");
  assert(asset_config.floor > 0n, "floor-neq");
  assert(asset_config.scale > 0n, "scale-neq");
  assert(asset_config.is_legacy === false, "is_legacy-neq");
  assert(asset_config.last_updated > 0n, "last_updated-neq");
  assert(asset_config.last_rate_accumulator > 0n, "last_rate_accumulator-neq");
  assert(asset_config.last_full_utilization_rate > 0n, "last_full_utilization_rate-neq");
  assert(asset_config.fee_rate === 0n, "fee_rate-neq");

  assert((await extensionPO.price(pool.id, asset.address)).value > 0n, "price-neq");
  assert((await singleton.rate_accumulator_unsafe(pool.id, asset.address)) > 0n, "rate_accumulator-neq");
  assert((await singleton.utilization_unsafe(pool.id, asset.address)) === 0n, "utilization-neq");
}

const { lender, borrower } = deployer;
const collateralAsset = protocol.assets[1]; // WBTC
const debtAsset = protocol.assets[2]; // USDC
const collateralScale = 10n ** (await collateralAsset.decimals());
const debtScale = 10n ** (await debtAsset.decimals());

// LEND

// lending terms
const liquidityToDeposit = 40_000n * debtScale; // 40k USDC ($40k)
const collateralToDeposit = 1n * collateralScale; // 1 WBTC ($40k)
const debtToDraw = liquidityToDeposit / 2n; // 20k USDC ($20k)
const rateAccumulator = await singleton.rate_accumulator_unsafe(pool.id, debtAsset.address);
const nominalDebtToDraw = await singleton.calculate_nominal_debt(toI257(debtToDraw), rateAccumulator, debtScale);

{
  const response = await pool.lend({
    collateral_asset: debtAsset.address,
    debt_asset: collateralAsset.address,
    collateral: Amount({ amountType: "Delta", denomination: "Assets", value: liquidityToDeposit }),
    debt: Amount(),
    data: CallData.compile([]),
  });
  await deployer.provider.waitForTransaction(response.transaction_hash);
}

// BORROW

// fund borrower with collateral
{
  collateralAsset.connect(lender);
  const response = await collateralAsset.transfer(borrower.address, collateralToDeposit);
  await deployer.provider.waitForTransaction(response.transaction_hash);
}

{
  const response = await pool.borrow({
    collateral_asset: collateralAsset.address,
    debt_asset: debtAsset.address,
    collateral: Amount({ amountType: "Target", denomination: "Assets", value: collateralToDeposit }),
    debt: Amount({ amountType: "Target", denomination: "Native", value: nominalDebtToDraw }),
    data: CallData.compile([]),
  });
  await deployer.provider.waitForTransaction(response.transaction_hash);
}

const { borrowAPR, supplyAPY } = await pool.borrowAndSupplyRates(debtAsset.address);
assert(formatRate(borrowAPR) === "5.15%", `Incorrect borrow APR: ${formatRate(borrowAPR)} !== 5.15%`);
assert(formatRate(supplyAPY) === "2.64%", `Incorrect supply APY: ${formatRate(supplyAPY)} !== 2.64%`);

// LIQUIDATE

{
  // reduce oracle price
  const { pragma } = protocol;
  pragma.oracle.connect(deployer);
  const response = await pragma.oracle.set_price("WBTC/USD", 10_000n * SCALE);
  await deployer.provider.waitForTransaction(response.transaction_hash);
}

const { "0": collateralized } = await singleton.check_collateralization_unsafe(
  pool.id,
  collateralAsset.address,
  debtAsset.address,
  borrower.address,
);
assert(collateralized === false, "Not undercollateralized");

{
  const response = await pool.liquidate({
    collateral_asset: collateralAsset.address,
    debt_asset: debtAsset.address,
    data: CallData.compile([uint256.bnToUint256(0n), uint256.bnToUint256(debtToDraw)]),
  });
  await deployer.provider.waitForTransaction(response.transaction_hash);
}

{
  // reset oracle price
  const { pragma } = protocol;
  pragma.oracle.connect(deployer);
  const response = await pragma.oracle.set_price("WBTC/USD", 40_000n * SCALE);
  await deployer.provider.waitForTransaction(response.transaction_hash);
}

const deployment = {
  singleton: protocol.singleton.address,
  extensionPO: protocol.extensionPO.address,
  oracle: protocol.pragma.oracle.address,
  assets: protocol.assets.map((asset) => asset.address),
  pools: [pool.id.toString()],
};

fs.writeFileSync(
  `deployment_${shortString.decodeShortString(await deployer.provider.getChainId()).toLowerCase()}.json`,
  JSON.stringify(deployment, null, 2),
);
