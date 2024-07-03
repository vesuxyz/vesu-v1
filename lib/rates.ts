import assert from "assert";
import { AssetConfig, InterestRateModel, ProtocolContracts, SCALE, YEAR_IN_SECONDS } from ".";

const UTILIZATION_SCALE = 10n ** 5n;
const UTILIZATION_SCALE_TO_SCALE = 10n ** 13n;

export async function calculateRates(
  { singleton, extension }: ProtocolContracts,
  poolId: bigint,
  asset: string,
  model: InterestRateModel,
) {
  const config = await singleton.asset_configs(poolId, asset);
  const utilization = calculateUtilization(config);
  const { last_updated: lastUpdated, last_full_utilization_rate: lastFullUtilizationRate } = config;

  // offchain
  const timeDelta = BigInt(Math.floor(Date.now() / 1000)) - lastUpdated;
  const offchainRate = calculateInterestRate(model, utilization, timeDelta, lastFullUtilizationRate);

  // onchain, comment out in prod
  const onchainRate = await extension.interest_rate(poolId, asset, utilization, lastUpdated, lastFullUtilizationRate);
  assert(formatRate(Number(onchainRate) / 1e18) == formatRate(Number(offchainRate) / 1e18), "Offchain rate mismatch");

  return toAnnualRates(offchainRate, config);
}

function calculateInterestRate(
  model: InterestRateModel,
  utilization: bigint,
  timeDelta: bigint,
  lastFullUtilizationRate: bigint,
): bigint {
  utilization = utilization / UTILIZATION_SCALE_TO_SCALE;
  const { target_utilization, zero_utilization_rate, target_rate_percent } = model;
  const newFullUtilizationRate = fullUtilizationRate(model, timeDelta, utilization, lastFullUtilizationRate);
  const targetRate =
    ((newFullUtilizationRate - zero_utilization_rate) * target_rate_percent) / SCALE + zero_utilization_rate;
  if (utilization < target_utilization) {
    return zero_utilization_rate + (utilization * (targetRate - zero_utilization_rate)) / target_utilization;
  }
  return (
    targetRate +
    ((utilization - target_utilization) * (newFullUtilizationRate - targetRate)) / (SCALE - target_utilization)
  );
}

function fullUtilizationRate(
  model: InterestRateModel,
  timeDelta: bigint,
  utilization: bigint,
  fullUtilizationRate: bigint,
) {
  const { min_target_utilization, max_target_utilization, rate_half_life } = model;
  const halfLifeScale = rate_half_life * SCALE;

  const newFullUtilizationRate = (() => {
    if (utilization < min_target_utilization) {
      const utilizationDelta = ((min_target_utilization - utilization) * SCALE) / min_target_utilization;
      const decay = halfLifeScale + utilizationDelta * timeDelta;
      return (fullUtilizationRate * halfLifeScale) / decay;
    } else if (utilization > max_target_utilization) {
      const utilizationDelta =
        ((utilization - max_target_utilization) * SCALE) / (UTILIZATION_SCALE - max_target_utilization);
      const growth = halfLifeScale + utilizationDelta * timeDelta;
      return (fullUtilizationRate * growth) / halfLifeScale;
    } else {
      return fullUtilizationRate;
    }
  })();

  if (newFullUtilizationRate > model.max_full_utilization_rate) {
    return model.max_full_utilization_rate;
  } else if (newFullUtilizationRate < model.min_full_utilization_rate) {
    return model.min_full_utilization_rate;
  } else {
    return newFullUtilizationRate;
  }
}

function calculateUtilization({ total_nominal_debt, last_rate_accumulator, scale, reserve }: AssetConfig) {
  const totalDebt = calculateDebt(total_nominal_debt, last_rate_accumulator, scale);
  const totalAssets = reserve + totalDebt;
  return totalAssets == 0n ? 0n : (totalDebt * SCALE) / totalAssets;
}

function calculateDebt(nominalDebt: bigint, rateAccumulator: bigint, assetScale: bigint) {
  return (((nominalDebt * rateAccumulator) / SCALE) * assetScale) / SCALE;
}

function toAnnualRates(
  interestPerSecond: bigint,
  { total_nominal_debt, last_rate_accumulator, reserve, scale }: AssetConfig,
) {
  const borrowAPR = toAPR(interestPerSecond);
  const totalBorrowed = Number((total_nominal_debt * last_rate_accumulator) / SCALE);
  const reserveScale = Number((reserve * SCALE) / scale);
  const supplyAPY = (toAPY(interestPerSecond) * totalBorrowed) / (reserveScale + totalBorrowed);
  return { borrowAPR, supplyAPY };
}

function toAPR(interestPerSecond: bigint) {
  return (Number(interestPerSecond) * YEAR_IN_SECONDS) / Number(SCALE);
}

function toAPY(interestPerSecond: bigint) {
  return (1 + Number(interestPerSecond) / Number(SCALE)) ** YEAR_IN_SECONDS - 1;
}

export function formatRate(rate: number) {
  return `${(rate * 100).toFixed(2)}%`;
}
