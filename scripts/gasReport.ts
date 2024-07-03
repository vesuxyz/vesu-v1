import assert from "assert";
import { CallData, uint256 } from "starknet";
import { Amount, SCALE, formatRate, newProfiler, setup, toI257 } from "../lib";

const deployer = await setup();

const profiler = newProfiler(deployer);

const protocol = await deployer.deployEnvAndProtocol();
// const protocol = await deployer.loadProtocol();

// CREATE POOL

const [pool, response] = await protocol.createPool("gas-report-pool", { devnetEnv: true });
await profiler.profile("Create pool", response);
console.log("Pool ID: ", pool.id);

// LEND

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
const nominalDebtToDraw = await singleton.calculate_nominal_debt(toI257(debtToDraw), rateAccumulator, debtScale);

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
  await profiler.profile("Lend", response);
}

// BORROW

{
  const response = await pool.borrow({
    collateral_asset: collateralAsset.address,
    debt_asset: debtAsset.address,
    collateral: Amount({ amountType: "Target", denomination: "Assets", value: collateralToDeposit }),
    debt: Amount({ amountType: "Target", denomination: "Native", value: nominalDebtToDraw }),
    data: CallData.compile([]),
  });
  await deployer.provider.waitForTransaction(response.transaction_hash);
  await profiler.profile("Borrow", response);
}

const { borrowAPR, supplyAPY } = await pool.borrowAndSupplyRates(debtAsset.address);
assert(formatRate(borrowAPR) === "6.43%", `Incorrect borrow APR: ${formatRate(borrowAPR)} !== 6.43%`);
assert(formatRate(supplyAPY) === "3.32%", `Incorrect supply APY: ${formatRate(supplyAPY)} !== 3.32%`);

// LIQUIDATE

{
  // reduce oracle price
  const { oracle } = protocol;
  oracle.connect(deployer);
  const response = await oracle.set_price("key-wbtc", 10_000n * SCALE);
  await deployer.provider.waitForTransaction(response.transaction_hash);
}

{
  const response = await pool.liquidate({
    collateral_asset: collateralAsset.address,
    debt_asset: debtAsset.address,
    data: CallData.compile([uint256.bnToUint256(0n), uint256.bnToUint256(debtToDraw)]),
  });
  await deployer.provider.waitForTransaction(response.transaction_hash);
  await profiler.profile("Liquidate", response);
}

profiler.printSummary();
profiler.updateOrCheckReport();
