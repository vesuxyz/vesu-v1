import { assert } from "console";
import { shortString } from "starknet";
import { setup, toAddress } from "../lib";

const deployer = await setup("mainnet");

const protocol = await deployer.loadProtocol();
const { singleton, assets, extensionPO } = protocol;

const pool = await protocol.loadPool("genesis-pool");

assert(
  toAddress(await extensionPO.pragma_oracle()) === protocol.pragma.oracle.address.toLowerCase(),
  "pragma_oracle-neq",
);
assert((await extensionPO.pool_owner(pool.id)) === BigInt(pool.params.owner.toLowerCase()), "pool_owner-neq");
assert(
  (await extensionPO.fee_config(pool.id)).fee_recipient === BigInt(pool.params.fee_params.fee_recipient.toLowerCase()),
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
  assert(
    oracle_config.start_time_offset === pool.params.pragma_oracle_params[index].start_time_offset,
    "start_time_offset-neq",
  );
  assert(oracle_config.time_window === pool.params.pragma_oracle_params[index].time_window, "time_window-neq");
  assert(
    JSON.stringify(oracle_config.aggregation_mode) ===
      JSON.stringify(pool.params.pragma_oracle_params[index].aggregation_mode),
    "aggregation_mode-neq",
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
  assert(asset_config.total_collateral_shares >= 0n, "total_collateral_shares-neq");
  assert(asset_config.total_nominal_debt >= 0n, "total_nominal_debt-neq");
  assert(asset_config.reserve >= 0n, "reserve-neq");
  assert(asset_config.max_utilization === pool.params.asset_params[index].max_utilization, "max_utilization-neq");
  assert(asset_config.floor === pool.params.asset_params[index].floor, "floor-neq");
  assert(asset_config.scale > 0n, "scale-neq");
  assert(asset_config.is_legacy === false, "is_legacy-neq");
  assert(asset_config.last_updated > 0n, "last_updated-neq");
  assert(asset_config.last_rate_accumulator > 0n, "last_rate_accumulator-neq");
  assert(asset_config.last_full_utilization_rate > 0n, "last_full_utilization_rate-neq");
  assert(asset_config.fee_rate === pool.params.asset_params[index].fee_rate, "fee_rate-neq");

  assert((await extensionPO.price(pool.id, asset.address)).value > 0n, "price-neq");
  assert((await singleton.rate_accumulator_unsafe(pool.id, asset.address)) > 0n, "rate_accumulator-neq");
  assert((await singleton.utilization_unsafe(pool.id, asset.address)) >= 0n, "utilization-neq");
}

for (const [, asset] of pool.params.ltv_params.entries()) {
  let collateral_asset = assets[asset.collateral_asset_index];
  let debt_asset = assets[asset.debt_asset_index];
  let ltv_config = await singleton.ltv_config(pool.id, collateral_asset.address, debt_asset.address);
  assert(ltv_config.max_ltv === asset.max_ltv, "max_ltv-neq");
}

for (const [, asset] of pool.params.liquidation_params.entries()) {
  let collateral_asset = assets[asset.collateral_asset_index];
  let debt_asset = assets[asset.debt_asset_index];
  let liquidation_config = await extensionPO.liquidation_config(pool.id, collateral_asset.address, debt_asset.address);
  assert(liquidation_config.liquidation_factor === asset.liquidation_factor, "liquidation_factor-neq");
}

for (const [, asset] of pool.params.debt_caps_params.entries()) {
  let collateral_asset = assets[asset.collateral_asset_index];
  let debt_asset = assets[asset.debt_asset_index];
  assert(
    (await extensionPO.debt_caps(pool.id, collateral_asset.address, debt_asset.address)) === asset.debt_cap,
    "debt_cap-neq",
  );
}

for (const [, asset] of pool.params.shutdown_params.ltv_params.entries()) {
  let collateral_asset = assets[asset.collateral_asset_index];
  let debt_asset = assets[asset.debt_asset_index];
  let ltv_config = await extensionPO.shutdown_ltv_config(pool.id, collateral_asset.address, debt_asset.address);
  assert(ltv_config.max_ltv === asset.max_ltv, "shutdown_max_ltv-neq");
}
