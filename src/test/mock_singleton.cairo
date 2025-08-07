use starknet::ContractAddress;
use vesu::data_model::{AssetConfig, Position};

#[starknet::interface]
pub trait IMockSingleton<TContractState> {
    fn asset_config(ref self: TContractState, pool_id: felt252, asset: ContractAddress) -> (AssetConfig, u256);
    fn position(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
    ) -> (Position, u256, u256);
}

#[starknet::contract]
mod MockSingleton {
    use starknet::ContractAddress;
    use vesu::data_model::{AssetConfig, Position};
    use vesu::test::mock_singleton::IMockSingleton;
    use vesu::units::SCALE;

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
                0,
            )
        }

        fn position(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            user: ContractAddress,
        ) -> (Position, u256, u256) {
            (Position { collateral_shares: 0, nominal_debt: 0 }, 0, 0)
        }
    }
}
