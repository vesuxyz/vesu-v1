import fs from "fs";
import { CallData } from "starknet";
import { Amount, setup } from "../lib";

const deployer = await setup();

const protocol = await deployer.deployEnvAndProtocol();
// const protocol = await deployer.loadProtocol();

const [pool, response] = await protocol.createPool("gas-report-pool", { devnetEnv: true });
console.log("Pool ID: ", pool.id.toString());

const { lender, borrower } = deployer;
const { singleton, assets } = protocol;
const collateralAsset = assets[1]; // WBTC
const debtAsset = assets[3]; // USDC
const collateralScale = 10n ** (await collateralAsset.decimals());
const debtScale = 10n ** (await debtAsset.decimals());

// lending terms
const liquidityToDeposit = 40_000n * debtScale; // 40k USDC ($40k)
const collateralToDeposit = 1n * collateralScale; // 1 WBTC ($40k)
const debtToDraw = liquidityToDeposit / 2n; // 20k USDC ($20k)
const rateAccumulator = await singleton.rate_accumulator(pool.id, debtAsset.address);
const nominalDebtToDraw = await singleton.calculate_nominal_debt(debtToDraw, rateAccumulator, debtScale);

// fund borrower with collateral
collateralAsset.connect(lender);
await collateralAsset.transfer(borrower.address, collateralToDeposit);

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

const deployment = {
  singleton: protocol.singleton.address,
  extension: protocol.extension.address,
  oracle: protocol.oracle.address,
  assets: protocol.assets.map((asset) => asset.address),
  pools: [pool.id.toString()],
};

fs.writeFileSync(`deployment-${await deployer.provider.getChainId()}.json`, JSON.stringify(deployment, null, 2));
