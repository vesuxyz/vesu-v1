use starknet::{ContractAddress};
use vesu::data_model::AssetConfig;

#[starknet::interface]
trait IMockSingleton<TContractState> {
    fn asset_config(ref self: TContractState, pool_id: felt252, asset: ContractAddress) -> (AssetConfig, u256);
}

#[starknet::contract]
mod MockSingleton {
    use alexandria_math::i257::i257;
    use starknet::ContractAddress;
    use vesu::{data_model::AssetConfig, units::SCALE, test::mock_singleton::IMockSingleton};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MockSingletonImpl of IMockSingleton<ContractState> {
        fn asset_config(ref self: ContractState, pool_id: felt252, asset: ContractAddress) -> (AssetConfig, u256) {
            (
                AssetConfig {
                    total_collateral_shares: SCALE,
                    total_nominal_debt: SCALE,
                    reserve: SCALE,
                    max_utilization: SCALE,
                    floor: SCALE,
                    scale: SCALE,
                    is_legacy: false,
                    last_updated: 0,
                    last_rate_accumulator: SCALE,
                    last_full_utilization_rate: SCALE,
                    fee_rate: SCALE,
                },
                0
            )
        }
    }
}
