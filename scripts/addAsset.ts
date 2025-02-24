import { isEmpty } from "lodash-es";
import { Account, RpcProvider, AccountInterface, TransactionType } from "starknet";
import { setup } from "../lib";
import { AssetParams } from "../lib/model";

const deployer = await setup(process.env.NETWORK);

const protocol = await deployer.loadProtocol();

const poolName = "genesis-pool";
const pool = await protocol.loadPool(poolName);
console.log("Using pool:", poolName, "with id:", pool.id);

const extension = await deployer.loadContract("0x2334189e831d804d4a11d3f71d4a982ec82614ac12ed2e9ca2f8da4e6374fa");

const extensionPOV0 = await deployer.loadExtensionPOV(extension);
console.log("Using extensionPOV0:", extensionPOV0.address);

const account = new Account(deployer.provider, "0x040bA3Ce5615A5c605E0caA592B4883052c804f8B1b326C1CaB2D5820F003aA1", "0x0");

extensionPOV0.connect(account);

const index = deployer.config.pools[poolName].params.asset_params.map(asset => asset.asset).indexOf(
  "0x0057912720381af14b0e5c87aa4718ed5e527eab60b3801ebf702ab09139e38b"
);

// const response = await extensionPOV0.populateTransaction.add_asset(
//   pool.id,
//   deployer.config.pools[poolName].params.asset_params[index],
//   deployer.config.pools[poolName].params.v_token_params[index],
//   deployer.config.pools[poolName].params.interest_rate_configs[index],
//   {
//     pragma_key: deployer.config.pools[poolName].params.pragma_oracle_params[index].pragma_key,
//     timeout: deployer.config.pools[poolName].params.pragma_oracle_params[index].timeout,
//     number_of_sources: deployer.config.pools[poolName].params.pragma_oracle_params[index].number_of_sources,
//   }
// );

// console.log(response);

// console.log(
//   pool.id,
//   deployer.config.pools[poolName].params.asset_params[index],
//   deployer.config.pools[poolName].params.v_token_params[index],
//   deployer.config.pools[poolName].params.interest_rate_configs[index],
//   {
//     pragma_key: deployer.config.pools[poolName].params.pragma_oracle_params[index].pragma_key,
//     timeout: deployer.config.pools[poolName].params.pragma_oracle_params[index].timeout,
//     number_of_sources: deployer.config.pools[poolName].params.pragma_oracle_params[index].number_of_sources,
//   }
// );

// const ltv_params = deployer.config.pools[poolName].params.ltv_params.filter(ltv_params => ltv_params.collateral_asset_index === index || ltv_params.debt_asset_index === index);
// console.log(
//   ltv_params.map(ltv_param => ({
//     collateral_asset: deployer.config.pools[poolName].params.asset_params[ltv_param.collateral_asset_index].asset,
//     debt_asset: deployer.config.pools[poolName].params.asset_params[ltv_param.debt_asset_index].asset,
//     max_ltv: ltv_param.max_ltv,
//   }))
// );

// const liquidation_params = deployer.config.pools[poolName].params.liquidation_params.filter(liquidation => liquidation.collateral_asset_index === index || liquidation.debt_asset_index === index);
// console.log(
//   liquidation_params.map(liquidation_param => ({
//     collateral_asset: deployer.config.pools[poolName].params.asset_params[liquidation_param.collateral_asset_index].asset,
//     debt_asset: deployer.config.pools[poolName].params.asset_params[liquidation_param.debt_asset_index].asset,
//     liquidation_factor: liquidation_param.liquidation_factor,
//   }))
// );

const shutdown_params = deployer.config.pools[poolName].params.shutdown_params.ltv_params.filter(shutdown_ltv => shutdown_ltv.collateral_asset_index === index || shutdown_ltv.debt_asset_index === index);
console.log(
  shutdown_params.map(shutdown_param => ({
    collateral_asset: deployer.config.pools[poolName].params.asset_params[shutdown_param.collateral_asset_index].asset,
    debt_asset: deployer.config.pools[poolName].params.asset_params[shutdown_param.debt_asset_index].asset,
    max_ltv: shutdown_param.max_ltv,
  }))
);
