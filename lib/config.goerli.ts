import { Config, EnvAssetParams, PERCENT, SCALE, mapAssetPairs } from ".";

// env:

// Deployed: {
//   assets: [
//     '0x5ba38f2fe5a3a7dd63f6c68958e0847c5c91288db774fc1a6083b42048d36ab',
//     '0x11edca5da4e340fd8647e87861ef66c74a0576e7913a07fdb69d2cd4fddcc13',
//     '0x3cac16241abe71d3d846aed80e7c7c62c6b03888b0a756eeef59b72d53f3613',
//     '0x27761acfa6de90e959651a5fc97c2eea274418609f06aaaad85a97f0b244929',
//     '0x6d8866aa791851ec2de3a6acbb53d74876e31ec857f2c566c721dbdc154a9b3',
//     '0xca29d3c060b8b7c630eafdd2b536f1b8abc79a32029616a483d4eff51f57b1',
//     '0x7ab3da81e0622d47de0df737194b67b3d1d2e5f21e3d10158729758f6c5c36c',
//     '0x39be6cfd9220797550875fb30d29759ede4a9d49e002321e0f069bfc12871bb'
//   ],
//   oracle: '0x7d42758257ed0fd2c46638001a0b43fcf86d2f244a6ea907e3896345653eea7'
// }
// Deployment tx: 0x536413dd716093327304355bd43e9e8366e3f799fd0fad55d7c25eb33fe7880

// protocol:

let testAssets = [
  { address: "0x5ba38f2fe5a3a7dd63f6c68958e0847c5c91288db774fc1a6083b42048d36ab", pragma_key: "key-eth" },
  { address: "0x11edca5da4e340fd8647e87861ef66c74a0576e7913a07fdb69d2cd4fddcc13", pragma_key: "key-wbtc" },
  { address: "0x3cac16241abe71d3d846aed80e7c7c62c6b03888b0a756eeef59b72d53f3613", pragma_key: "key-usdt" },
  { address: "0x27761acfa6de90e959651a5fc97c2eea274418609f06aaaad85a97f0b244929", pragma_key: "key-usdc" },
];

const env = [
  new EnvAssetParams("Ether", "ETH", 18n, 100n, "key-eth", 2000n * SCALE, true, 0n),
  new EnvAssetParams("Wrapped Bitcoin", "WBTC", 18n, 100n, "key-wbtc", 40_000n * SCALE, true, 0n),
  new EnvAssetParams("Tether", "USDT", 6n, 1_000_000n, "key-usdt", SCALE, true, 0n),
  new EnvAssetParams("USD Coin", "USDC", 6n, 1_000_000n, "key-usdc", SCALE, false, 0n),
  new EnvAssetParams("DAI", "DAI", 18n, 1_000_000n, "key-dai", SCALE, false, 0n),
  new EnvAssetParams("Wrapped stETH", "wstETH", 18n, 100n, "key-steth", 2000n * SCALE, true, 0n),
  new EnvAssetParams("Rocket Pool ETH", "rETH", 18n, 100n, "key-reth", 2000n * SCALE, false, 0n),
  new EnvAssetParams("Stark Token", "STRK", 18n, 100n, "key-strk", SCALE / 2n, true, 0n),
];

const stables = ["USDC", "USDT", "DAI"];
const majors = ["ETH", "WBTC", "wstETH", "rETH"];

export const config: Config = {
  name: "goerli",
  protocol: {
    singleton: "0x0",
    extension: "0x0",
    oracle: "0x0",
  },
  pools: {
    "genesis-pool": {
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
        ltv_params: mapAssetPairs(env, (collateral, debt, indexes) => {
          if (collateral === debt) {
            return;
          }
          if (stables.includes(collateral.symbol) && stables.includes(debt.symbol)) {
            return { ...indexes, max_ltv: 90n * PERCENT };
          }
          if ([...stables, ...majors].includes(collateral.symbol)) {
            return { ...indexes, max_ltv: 80n * PERCENT };
          }
          return { ...indexes, max_ltv: 70n * PERCENT };
        }),
        interest_rate_configs: env.map(() => ({
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
              return { ...indexes, max_ltv: 85n * PERCENT };
            }
            if ([...stables, ...majors].includes(collateral.symbol)) {
              return { ...indexes, max_ltv: 75n * PERCENT };
            }
            return { ...indexes, max_ltv: 65n * PERCENT };
          }),
        },
        fee_params: { fee_recipient: "0x0" },
        owner: "0x0",
      },
    },
    "gas-report-pool": {
      id: 1000000000000000000000000000000000000000000000000000000000000000000000000000n,
      description:
        "Pool with 2 assets created at tx hash 0x6d065b472997aef4f053f892ba0eb85aa3df6bb3569ba9443be1c7c48ff90e2.",
      type: "Default extension.",
      params: {
        asset_params: testAssets.map(({ address }) => ({
          asset: address,
          floor: SCALE / 10_000n,
          initial_rate_accumulator: SCALE,
          initial_full_utilization_rate: (1582470460n + 32150205761n) / 2n,
          max_utilization: SCALE,
          is_legacy: false,
          fee_rate: 0n,
        })),
        ltv_params: [
          { collateral_asset_index: 1, debt_asset_index: 0, max_ltv: 90n * PERCENT },
          { collateral_asset_index: 0, debt_asset_index: 1, max_ltv: 90n * PERCENT },
          { collateral_asset_index: 1, debt_asset_index: 3, max_ltv: 90n * PERCENT },
          { collateral_asset_index: 3, debt_asset_index: 1, max_ltv: 90n * PERCENT },
        ],
        interest_rate_configs: testAssets.map(() => ({
          min_target_utilization: 75000n,
          max_target_utilization: 85000n,
          target_utilization: 87500n,
          min_full_utilization_rate: 1582470460n,
          max_full_utilization_rate: 32150205761n,
          zero_utilization_rate: 158247046n,
          rate_half_life: 172800n,
          target_rate_percent: 200000000000000000n,
        })),
        pragma_oracle_params: testAssets.map(({ pragma_key }) => ({ pragma_key, timeout: 0n, number_of_sources: 0n })),
        liquidation_params: testAssets.map(() => ({ liquidation_discount: 0n })),
        shutdown_params: {
          recovery_period: 0n,
          subscription_period: 0n,
          ltv_params: [
            { collateral_asset_index: 1, debt_asset_index: 0, max_ltv: 85n * PERCENT },
            { collateral_asset_index: 0, debt_asset_index: 1, max_ltv: 85n * PERCENT },
            { collateral_asset_index: 1, debt_asset_index: 3, max_ltv: 85n * PERCENT },
            { collateral_asset_index: 3, debt_asset_index: 1, max_ltv: 85n * PERCENT },
          ],
        },
        fee_params: { fee_recipient: "0x0" },
        owner: "0x0",
      },
    },
  },
};
