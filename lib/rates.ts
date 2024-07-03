import assert from "assert";
import { AssetConfig, InterestRateConfig, ProtocolContracts, SCALE, YEAR_IN_SECONDS } from ".";

const UTILIZATION_SCALE = 10n ** 5n;
const UTILIZATION_SCALE_TO_SCALE = 10n ** 13n;

export async function calculateRates(
  { singleton, extension }: ProtocolContracts,
  poolId: bigint,
  asset: string,
  interest_rate_config: InterestRateConfig,
) {
  const { "0": asset_config } = await singleton.asset_config_unsafe(poolId, asset);
  const utilization = calculateUtilization(asset_config);
  const { last_updated: lastUpdated, last_full_utilization_rate: lastFullUtilizationRate } = asset_config;

  // offchain
  const timeDelta = BigInt(Math.floor(Date.now() / 1000)) - lastUpdated;
  const offchainRate = calculateInterestRate(interest_rate_config, utilization, timeDelta, lastFullUtilizationRate);

  // onchain, comment out in prod
  const onchainRate = await extension.interest_rate(poolId, asset, utilization, lastUpdated, lastFullUtilizationRate);
  assert(formatRate(Number(onchainRate) / 1e18) == formatRate(Number(offchainRate) / 1e18), "Offchain rate mismatch");

  return toAnnualRates(offchainRate, asset_config);
}

function calculateInterestRate(
  interest_rate_config: InterestRateConfig,
  utilization: bigint,
  timeDelta: bigint,
  lastFullUtilizationRate: bigint,
): bigint {
  utilization = utilization / UTILIZATION_SCALE_TO_SCALE;
  const { target_utilization, zero_utilization_rate, target_rate_percent } = interest_rate_config;
  const newFullUtilizationRate = fullUtilizationRate(
    interest_rate_config,
    timeDelta,
    utilization,
    lastFullUtilizationRate,
  );
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
  interest_rate_config: InterestRateConfig,
  timeDelta: bigint,
  utilization: bigint,
  fullUtilizationRate: bigint,
) {
  const { min_target_utilization, max_target_utilization, rate_half_life } = interest_rate_config;
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

  if (newFullUtilizationRate > interest_rate_config.max_full_utilization_rate) {
    return interest_rate_config.max_full_utilization_rate;
  } else if (newFullUtilizationRate < interest_rate_config.min_full_utilization_rate) {
    return interest_rate_config.min_full_utilization_rate;
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
