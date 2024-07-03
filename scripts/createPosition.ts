import { CallData } from "starknet";
import { Amount, setup, toU256 } from "../lib";

const deployer = await setup();

const protocol = await deployer.loadProtocol();

const poolName = "pool-example";
const pool = await protocol.loadPool(poolName);
console.log("Using pool:", poolName, "with id:", pool.id);

const liquidityToDeposit = 10n ** 9n;
const { lender } = deployer;
const { singleton, assets } = protocol;
const { collateral_asset_index, debt_asset_index } = pool.params.ltv_params[0];
const collateralAsset = assets[collateral_asset_index];
const debtAsset = assets[debt_asset_index];

{
  collateralAsset.connect(lender);
  const response = await collateralAsset.approve(singleton.address, toU256(liquidityToDeposit));
  await deployer.waitForTransaction(response.transaction_hash);
}

const response = await pool.lend({
  collateral_asset: debtAsset.address,
  debt_asset: collateralAsset.address,
  collateral: Amount({ amountType: "Delta", denomination: "Assets", value: liquidityToDeposit }),
  debt: Amount(),
  data: CallData.compile([]),
});

console.log("Lend tx:", response.transaction_hash);
await deployer.waitForTransaction(response.transaction_hash);
