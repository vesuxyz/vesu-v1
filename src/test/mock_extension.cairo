#[starknet::contract]
mod MockExtension {
    use alexandria_math::i257::i257;
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address, get_caller_address};
    use vesu::{
        data_model::{
            Amount, UnsignedAmount, AssetParams, AssetPrice, LTVParams, ModifyPositionParams, Context, LTVConfig
        },
        units::SCALE, singleton::{ISingletonDispatcher, ISingletonDispatcherTrait}, extension::interface::IExtension,
    };

    #[storage]
    struct Storage {
        singleton: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState, singleton: ContractAddress,) {
        self.singleton.write(singleton);
    }

    #[abi(embed_v0)]
    impl MockExtensionImpl of IExtension<ContractState> {
        fn singleton(self: @ContractState) -> ContractAddress {
            self.singleton.read()
        }

        fn price(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> AssetPrice {
            ISingletonDispatcher { contract_address: self.singleton.read() }
                .context(pool_id, asset, Zeroable::zero(), Zeroable::zero());
            AssetPrice { value: SCALE, is_valid: true }
        }

        fn interest_rate(
            self: @ContractState,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_full_utilization_rate: u256,
        ) -> u256 {
            ISingletonDispatcher { contract_address: self.singleton.read() }
                .context(pool_id, asset, Zeroable::zero(), Zeroable::zero());
            SCALE
        }

        fn rate_accumulator(
            self: @ContractState,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_rate_accumulator: u256,
            last_full_utilization_rate: u256,
        ) -> (u256, u256) {
            ISingletonDispatcher { contract_address: self.singleton.read() }.asset_config(pool_id, asset);
            (SCALE, SCALE)
        }

        fn before_modify_position(
            ref self: ContractState,
            context: Context,
            collateral: Amount,
            debt: Amount,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> (Amount, Amount) {
            (collateral, debt)
        }

        fn after_modify_position(
            ref self: ContractState,
            context: Context,
            collateral_delta: i257,
            collateral_shares_delta: i257,
            debt_delta: i257,
            nominal_debt_delta: i257,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            true
        }

        fn before_transfer_position(
            ref self: ContractState,
            from_context: Context,
            to_context: Context,
            collateral: UnsignedAmount,
            debt: UnsignedAmount,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> (UnsignedAmount, UnsignedAmount) {
            (Default::default(), Default::default())
        }

        fn after_transfer_position(
            ref self: ContractState,
            from_context: Context,
            to_context: Context,
            collateral_delta: u256,
            collateral_shares_delta: u256,
            debt_delta: u256,
            nominal_debt_delta: u256,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            true
        }

        fn before_liquidate_position(
            ref self: ContractState, context: Context, data: Span<felt252>, caller: ContractAddress
        ) -> (u256, u256, u256) {
            (Default::default(), Default::default(), Default::default())
        }

        fn after_liquidate_position(
            ref self: ContractState,
            context: Context,
            collateral_delta: i257,
            collateral_shares_delta: i257,
            debt_delta: i257,
            nominal_debt_delta: i257,
            bad_debt: u256,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            true
        }
    }
}
