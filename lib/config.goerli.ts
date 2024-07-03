import { Config, PERCENT, SCALE } from ".";

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

export const config: Config = {
  name: "goerli",
  protocol: {
    singleton: "0x1e3a83bb60a6de4e967e931dbf483dba3a50b5d219c53b832d1bc56919f0576",
    extension: "0x21dd473bb5e1014e84b3cf3f5da734ea74927d95d3e2262140d844c8b6f808f",
    oracle: "0x7d42758257ed0fd2c46638001a0b43fcf86d2f244a6ea907e3896345653eea7",
  },
  pools: {
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
        max_position_ltv_params: [
          { collateral_asset_index: 1, debt_asset_index: 0, ltv: 90n * PERCENT },
          { collateral_asset_index: 0, debt_asset_index: 1, ltv: 90n * PERCENT },
          { collateral_asset_index: 1, debt_asset_index: 3, ltv: 90n * PERCENT },
          { collateral_asset_index: 3, debt_asset_index: 1, ltv: 90n * PERCENT },
        ],
        interest_rate_models: testAssets.map(() => ({
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
            { collateral_asset_index: 1, debt_asset_index: 0, ltv: 85n * PERCENT },
            { collateral_asset_index: 0, debt_asset_index: 1, ltv: 85n * PERCENT },
            { collateral_asset_index: 1, debt_asset_index: 3, ltv: 85n * PERCENT },
            { collateral_asset_index: 3, debt_asset_index: 1, ltv: 85n * PERCENT },
          ],
        },
      },
    },
  },
};
