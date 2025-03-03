import { CallData, hash, shortString } from "starknet";
import { setup, toI257 } from "../lib";

const deployer = await setup(process.env.NETWORK);

const protocol = await deployer.loadProtocol();
const { singleton, assets, extensionPO } = protocol;
await extensionPO.connect(deployer.creator);

const poolName = "genesis-pool";
const pool = await protocol.loadPool(poolName);

const oldest_violation_timestamp = await extensionPO.oldest_violation_timestamp(pool.id);
if (oldest_violation_timestamp !== 0n) {
  console.log("Violation found at timestamp: ", oldest_violation_timestamp);
  const violation_timestamp_count = await extensionPO.violation_timestamp_count(pool.id, oldest_violation_timestamp);
  console.log("Violation count: ", violation_timestamp_count);
}

console.log("");
console.log("Checking shutdown status for each pair...");

for (const [, asset] of pool.params.ltv_params.entries()) {
  let collateral_asset = assets[asset.collateral_asset_index];
  let debt_asset = assets[asset.debt_asset_index];
  const collateral_asset_symbol = shortString.decodeShortString((await collateral_asset.symbol()));
  const debt_asset_symbol = shortString.decodeShortString((await debt_asset.symbol()));

  console.log("");
  console.log(`  • ${collateral_asset_symbol} / ${debt_asset_symbol}`);

  const context = await singleton.context_unsafe(pool.id, collateral_asset.address, debt_asset.address, "0x0");
  
  const collateral_asset_price = Number(context.collateral_asset_price.value) / 1e18;
  const debt_asset_price = Number(context.debt_asset_price.value) / 1e18;

  if (collateral_asset_price === 0 || collateral_asset_price > 100000 || !context.collateral_asset_price.is_valid) {
    console.log("    Invalid price of collateral asset");
    console.log("      price: ", collateral_asset_price, collateral_asset_symbol);
    console.log("      valid: ", context.collateral_asset_price.is_valid);
  }

  if (debt_asset_price === 0 || debt_asset_price > 100000 || !context.debt_asset_price.is_valid) {
    console.log("    Invalid price of debt asset");
    console.log("      price: ", debt_asset_price, debt_asset_symbol);
    console.log("      valid: ", context.debt_asset_price.is_valid);
  }

  const collateral_accumulator = Number(context.collateral_asset_config.last_rate_accumulator) / 1e18;
  const debt_accumulator = Number(context.debt_asset_config.last_rate_accumulator) / 1e18;

  if (collateral_accumulator === 0 || collateral_accumulator > 18) {
    console.log("    Invalid collateral rate_accumulator");
    console.log("      rate_accumulator: ", collateral_accumulator);
  }

  if (debt_accumulator === 0 || debt_accumulator > 18) {
    console.log("    Invalid debt rate_accumulator");
    console.log("      rate_accumulator: ", debt_accumulator);
  }
  
  const pair = await extensionPO.pairs(pool.id, collateral_asset.address, debt_asset.address);
  const collateral = Number(await singleton.calculate_collateral_unsafe(pool.id, collateral_asset.address, toI257(pair.total_collateral_shares))) / Number(context.collateral_asset_config.scale);
  const debt = Number(await singleton.calculate_debt(toI257(pair.total_nominal_debt), context.debt_asset_config.last_rate_accumulator, context.debt_asset_config.scale)) / Number(context.debt_asset_config.scale);
  const collateral_value = collateral * collateral_asset_price;
  const debt_value = debt * debt_asset_price;
  
  const shutdown_ltv = (debt_value === 0) ? 0 : debt_value / collateral_value;
  const shutdown_ltv_max = Number((await extensionPO.shutdown_ltv_config(pool.id, collateral_asset.address, debt_asset.address)).max_ltv) / 1e18;

  if (shutdown_ltv >= shutdown_ltv_max) {
    console.log("    Shutdown LTV is greater than or equal to the max LTV");
    console.log("      shutdown_ltv:    ", shutdown_ltv);
    console.log("      shutdown_ltv_max:", shutdown_ltv_max);
  }
  
  const shutdown_status = await extensionPO.shutdown_status(pool.id, collateral_asset.address, debt_asset.address);

  if (shutdown_status.violating) {
    console.log("    Shutdown status is violating");
    console.log("      shutdown_mode:", shutdown_status.shutdown_mode);
  }
  
  const violation_timestamp = await extensionPO.violation_timestamp_for_pair(pool.id, collateral_asset.address, debt_asset.address);

  if (violation_timestamp !== 0n) {
    console.log("    Violation timestamp found");
    console.log("      violation_timestamp:", violation_timestamp);
  }

  // const response = await extensionPO.update_shutdown_status(pool.id, collateral_asset.address, debt_asset.address);
  // await deployer.waitForTransaction(response.transaction_hash);
}
