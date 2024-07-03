import { Config, EnvAssetParams, PERCENT, SCALE, mapAssetPairs } from ".";

const env = [
  new EnvAssetParams("Ether", "ETH", 18n, 100n, "key-eth", 2000n * SCALE, true, 0n),
  new EnvAssetParams("Wrapped Bitcoin", "WBTC", 18n, 100n, "key-wbtc", 40_000n * SCALE, true, 0n),
  new EnvAssetParams("Tether", "USDT", 6n, 1_000_000n, "key-usdt", SCALE, true, 0n),
  new EnvAssetParams("USD Coin", "USDC", 6n, 1_000_000n, "key-usdc", SCALE, false, 0n),
  new EnvAssetParams("DAI", "DAI", 18n, 1_000_000n, "key-dai", SCALE, false, 0n),
  new EnvAssetParams("Wrapped stETH", "wstETH", 18n, 100n, "key-steth", 2000n * SCALE, true, 0n),
  new EnvAssetParams("Rocket Pool ETH", "rETH", 18n, 100n, "key-reth", 2000n * SCALE, false, 0n),
  new EnvAssetParams("Stark Token", "STRK", 18n, 100n, "key-strk", 0xdeadbeefn * SCALE, true, 0n),
];

const stables = ["USDC", "USDT", "DAI"];
const majors = ["ETH", "WBTC", "wstETH", "rETH"];

export const config: Config = {
  name: "devnet",
  protocol: {
    singleton: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    extension: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    oracle: "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  },
  env,
  pools: {
    "gas-report-pool": {
      id: 1000000000000000000000000000000000000000000000000000000000000000000000000000n,
      description: "",
      type: "",
      params: {
        asset_params: env.map(({ isLegacy }) => ({
          asset: "0x0000000000000000000000000000000000000000000000000000000000000000",
          floor: SCALE / 10_000n,
          initial_rate_accumulator: SCALE,
          initial_full_utilization_rate: (1582470460n + 32150205761n) / 2n,
          max_utilization: SCALE,
          is_legacy: isLegacy,
          fee_rate: 0n,
        })),
        max_position_ltv_params: mapAssetPairs(env, (collateral, debt, indexes) => {
          if (collateral === debt) {
            return;
          }
          if (stables.includes(collateral.symbol) && stables.includes(debt.symbol)) {
            return { ...indexes, ltv: 90n * PERCENT };
          }
          if ([...stables, ...majors].includes(collateral.symbol)) {
            return { ...indexes, ltv: 80n * PERCENT };
          }
          return { ...indexes, ltv: 70n * PERCENT };
        }),
        interest_rate_models: env.map(() => ({
          min_target_utilization: 75_000n,
          max_target_utilization: 85_000n,
          target_utilization: 87_500n,
          min_full_utilization_rate: 1582470460n,
          max_full_utilization_rate: 32150205761n,
          zero_utilization_rate: 158247046n,
          rate_half_life: 172_800n,
          target_rate_percent: 20n * PERCENT,
        })),
        pragma_oracle_params: env.map(({ pragmaKey }) => ({
          pragma_key: pragmaKey,
          timeout: 0n,
          number_of_sources: 0n,
        })),
        liquidation_params: env.map(() => ({ liquidation_discount: 0n })),
        shutdown_params: {
          recovery_period: 0n,
          subscription_period: 0n,
          ltv_params: mapAssetPairs(env, (collateral, debt, indexes) => {
            if (collateral === debt) {
              return;
            }
            if (stables.includes(collateral.symbol) && stables.includes(debt.symbol)) {
              return { ...indexes, ltv: 85n * PERCENT };
            }
            if ([...stables, ...majors].includes(collateral.symbol)) {
              return { ...indexes, ltv: 75n * PERCENT };
            }
            return { ...indexes, ltv: 65n * PERCENT };
          }),
        },
      },
    },
  },
};
