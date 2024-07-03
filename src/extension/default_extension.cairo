use starknet::{ContractAddress};
use vesu::{
    data_model::{AssetParams, LTVParams},
    extension::components::{
        interest_rate_model::{InterestRateModel},
        position_hooks::{ShutdownMode, ShutdownStatus, ShutdownConfig, LiquidationConfig}
    },
};

#[derive(PartialEq, Copy, Drop, Serde)]
struct LiquidationParams {
    liquidation_discount: u256, // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct ShutdownParams {
    recovery_period: u64, // [seconds]
    subscription_period: u64, // [seconds]
    ltv_params: Span<LTVParams>,
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct PragmaOracleParams {
    pragma_key: felt252,
    timeout: u64, // [seconds]
    number_of_sources: u32
}

#[starknet::interface]
trait ITimestampManagerCallback<TContractState> {
    fn contains(self: @TContractState, pool_id: felt252, item: u64) -> bool;
    fn insert_before(ref self: TContractState, pool_id: felt252, item_after: u64, item: u64);
    fn remove(ref self: TContractState, pool_id: felt252, item: u64);
    fn first(self: @TContractState, pool_id: felt252) -> u64;
    fn last(self: @TContractState, pool_id: felt252) -> u64;
    fn all(self: @TContractState, pool_id: felt252) -> Array<u64>;
}

#[starknet::interface]
trait IDefaultExtension<TContractState> {
    fn pragma_oracle(self: @TContractState) -> ContractAddress;
    fn liquidation_config(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> LiquidationConfig;
    fn shutdown_config(self: @TContractState, pool_id: felt252) -> ShutdownConfig;
    fn shutdown_ltvs(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> u256;
    fn shutdown_status(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> ShutdownStatus;
    fn violation_timestamp_for_pair(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> u64;
    fn violation_timestamp_count(self: @TContractState, pool_id: felt252, violation_timestamp: u64) -> u128;
    fn oldest_violation_timestamp(self: @TContractState, pool_id: felt252) -> u64;
    fn next_violation_timestamp(self: @TContractState, pool_id: felt252, violation_timestamp: u64) -> u64;
    fn create_pool(
        ref self: TContractState,
        asset_params: Span<AssetParams>,
        max_position_ltv_params: Span<LTVParams>,
        interest_rate_models: Span<InterestRateModel>,
        pragma_oracle_params: Span<PragmaOracleParams>,
        liquidation_params: Span<LiquidationParams>,
        shutdown_params: ShutdownParams,
    ) -> felt252;
    fn update_shutdown_status(
        ref self: TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> ShutdownMode;
}

#[starknet::contract]
mod DefaultExtension {
    use alexandria_math::i257::i257;
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address, get_caller_address};
    use vesu::{
        map_list::{map_list_component, map_list_component::MapListTrait},
        data_model::{Amount, AssetParams, AssetPrice, LTVParams, ModifyPositionParams, Context},
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
        extension::{
            default_extension::{
                LiquidationParams, ShutdownParams, PragmaOracleParams, ITimestampManagerCallback, IDefaultExtension
            },
            interface::{IExtension},
            components::{
                interest_rate_model::{
                    InterestRateModel, interest_rate_model_component,
                    interest_rate_model_component::InterestRateModelTrait
                },
                position_hooks::{
                    position_hooks_component, position_hooks_component::PositionHooksTrait, ShutdownStatus,
                    ShutdownMode, ShutdownConfig, LiquidationConfig
                },
                pragma_oracle::{pragma_oracle_component, pragma_oracle_component::PragmaOracleTrait},
            }
        },
    };

    component!(path: position_hooks_component, storage: position_hooks, event: PositionHooksEvents);
    component!(path: interest_rate_model_component, storage: interest_rate_model, event: InterestRateModelEvents);
    component!(path: pragma_oracle_component, storage: pragma_oracle, event: PragmaOracleEvents);
    component!(path: map_list_component, storage: timestamp_manager, event: MapListEvents);

    #[storage]
    struct Storage {
        singleton: ContractAddress,
        #[substorage(v0)]
        position_hooks: position_hooks_component::Storage,
        #[substorage(v0)]
        interest_rate_model: interest_rate_model_component::Storage,
        #[substorage(v0)]
        pragma_oracle: pragma_oracle_component::Storage,
        #[substorage(v0)]
        timestamp_manager: map_list_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PositionHooksEvents: position_hooks_component::Event,
        InterestRateModelEvents: interest_rate_model_component::Event,
        PragmaOracleEvents: pragma_oracle_component::Event,
        MapListEvents: map_list_component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, singleton: ContractAddress, oracle_address: ContractAddress) {
        self.singleton.write(singleton);
        self.pragma_oracle.initialize(oracle_address);
    }

    impl TimestampManagerCallbackImpl of ITimestampManagerCallback<ContractState> {
        fn contains(self: @ContractState, pool_id: felt252, item: u64) -> bool {
            self.timestamp_manager.contains(pool_id, item)
        }
        fn insert_before(ref self: ContractState, pool_id: felt252, item_after: u64, item: u64) {
            self.timestamp_manager.insert_before(pool_id, item_after, item)
        }
        fn remove(ref self: ContractState, pool_id: felt252, item: u64) {
            self.timestamp_manager.remove(pool_id, item)
        }
        fn first(self: @ContractState, pool_id: felt252) -> u64 {
            self.timestamp_manager.first(pool_id)
        }
        fn last(self: @ContractState, pool_id: felt252) -> u64 {
            self.timestamp_manager.last(pool_id)
        }
        fn all(self: @ContractState, pool_id: felt252) -> Array<u64> {
            self.timestamp_manager.all(pool_id)
        }
    }

    #[abi(embed_v0)]
    impl DefaultExtensionImpl of IDefaultExtension<ContractState> {
        /// Returns the address of the pragma oracle contract
        /// # Returns
        /// * `oracle_address` - address of the pragma oracle contract
        fn pragma_oracle(self: @ContractState) -> ContractAddress {
            self.pragma_oracle.oracle_address()
        }

        /// Returns the liquidation configuration for a given pool and asset
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `liquidation_config` - liquidation configuration
        fn liquidation_config(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> LiquidationConfig {
            self.position_hooks.liquidation_configs.read((pool_id, asset))
        }

        /// Returns the shutdown configuration for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// # Returns
        /// * `recovery_period` - recovery period
        /// * `subscription_period` - subscription period
        fn shutdown_config(self: @ContractState, pool_id: felt252) -> ShutdownConfig {
            self.position_hooks.shutdown_config.read(pool_id)
        }

        /// Returns the shutdown LTV for a given pair in a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `ltv` - shutdown LTV
        fn shutdown_ltvs(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> u256 {
            self.position_hooks.shutdown_ltvs.read((pool_id, collateral_asset, debt_asset))
        }

        /// Returns the timestamp at which a given pair in a given pool transitioned to recovery mode
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `violation_timestamp` - timestamp at which the pair transitioned to recovery mode
        fn violation_timestamp_for_pair(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> u64 {
            self.position_hooks.timestamps.read((pool_id, collateral_asset, debt_asset))
        }

        /// Returns the count of how many pairs in a given pool transitioned to recovery mode at a given timestamp
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `violation_timestamp` - timestamp at which the pair transitioned to recovery mode
        /// # Returns
        /// * `count_at_violation_timestamp_timestamp` - count of how many pairs transitioned to recovery mode at that timestamp
        fn violation_timestamp_count(self: @ContractState, pool_id: felt252, violation_timestamp: u64) -> u128 {
            self.position_hooks.timestamp_counts.read((pool_id, violation_timestamp))
        }

        /// Returns the oldest timestamp at which a pair in a given pool transitioned to recovery mode
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// # Returns
        /// * `oldest_violation_timestamp` - oldest timestamp at which a pair transitioned to recovery mode
        fn oldest_violation_timestamp(self: @ContractState, pool_id: felt252) -> u64 {
            self.timestamp_manager.last(pool_id)
        }

        /// Returns the next (older) violation timestamp for a given violation timestamp for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `violation_timestamp` - violation timestamp
        /// # Returns
        /// * `next_violation_timestamp` - next (older) violation timestamp
        fn next_violation_timestamp(self: @ContractState, pool_id: felt252, violation_timestamp: u64) -> u64 {
            self.timestamp_manager.next(pool_id, violation_timestamp.into())
        }

        /// Creates a new pool
        /// # Arguments
        /// * `asset_params` - asset parameters
        /// * `max_position_ltv_params` - max. loan-to-value parameters
        /// * `interest_rate_model_params` - interest rate model parameters
        /// * `pragma_oracle_params` - pragma oracle parameters
        /// * `liquidation_params` - liquidation parameters
        /// * `shutdown_params` - shutdown parameters
        /// # Returns
        /// * `pool_id` - id of the pool
        fn create_pool(
            ref self: ContractState,
            mut asset_params: Span<AssetParams>,
            mut max_position_ltv_params: Span<LTVParams>,
            mut interest_rate_models: Span<InterestRateModel>,
            mut pragma_oracle_params: Span<PragmaOracleParams>,
            mut liquidation_params: Span<LiquidationParams>,
            shutdown_params: ShutdownParams,
        ) -> felt252 {
            assert!(asset_params.len() == interest_rate_models.len(), "interest-rate-model-mismatch");
            assert!(asset_params.len() == pragma_oracle_params.len(), "pragma-oracle-mismatch");
            assert!(asset_params.len() == liquidation_params.len(), "liquidation-mismatch");

            let pool_id = ISingletonDispatcher { contract_address: self.singleton.read() }
                .create_pool(asset_params, max_position_ltv_params, get_contract_address());

            let mut asset_params_copy = asset_params;
            while !asset_params_copy.is_empty() {
                let asset = *asset_params_copy.pop_front().unwrap().asset;

                // unwraps checked above
                let config = *pragma_oracle_params.pop_front().unwrap();
                let PragmaOracleParams{pragma_key, timeout, number_of_sources } = config;
                self.pragma_oracle.set_oracle_config(pool_id, asset, pragma_key, timeout, number_of_sources);

                let model = *interest_rate_models.pop_front().unwrap();
                self.interest_rate_model.set_model(pool_id, asset, model);

                let config = *liquidation_params.pop_front().unwrap();
                self.position_hooks.set_liquidation_config(pool_id, asset, config.liquidation_discount);
            };

            let ShutdownParams{recovery_period, subscription_period, ltv_params } = shutdown_params;
            self.position_hooks.set_shutdown_config(pool_id, recovery_period, subscription_period);

            let mut shutdown_ltv_params = ltv_params;
            while !shutdown_ltv_params.is_empty() {
                let params = *shutdown_ltv_params.pop_front().unwrap();
                let collateral_asset = *asset_params.at(params.collateral_asset_index).asset;
                let debt_asset = *asset_params.at(params.debt_asset_index).asset;
                self.position_hooks.set_shutdown_ltv(pool_id, collateral_asset, debt_asset, params.ltv);
            };

            pool_id
        }

        /// Returns the shutdown mode for a specific pair in a pool.
        /// To check the shutdown status of the pool, the shutdown mode for all pairs must be checked.
        /// See `shutdown_status` in `position_hooks.cairo`.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `shutdown_mode` - shutdown mode
        /// * `violation` - whether the pair currently violates any of the invariants (transitioned to recovery mode)
        /// * `previous_violation_timestamp` - timestamp at which the pair previously violated the invariants (transitioned to recovery mode)
        /// * `count_at_violation_timestamp_timestamp` - count of how many pairs violated the invariants at that timestamp
        fn shutdown_status(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> ShutdownStatus {
            let singleton = ISingletonDispatcher { contract_address: self.singleton.read() };
            let mut context = singleton.context(pool_id, collateral_asset, debt_asset, Zeroable::zero());
            self.position_hooks.shutdown_status(ref context)
        }

        /// Updates the shutdown mode for a specific pair in a pool.
        /// See `update_shutdown_status` in `position_hooks.cairo`.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `shutdown_mode` - shutdown mode
        fn update_shutdown_status(
            ref self: ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> ShutdownMode {
            let singleton = ISingletonDispatcher { contract_address: self.singleton.read() };
            let mut context = singleton.context(pool_id, collateral_asset, debt_asset, Zeroable::zero());
            self.position_hooks.update_shutdown_status(ref context)
        }
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        /// Returns the address of the singleton contract
        /// # Returns
        /// * `singleton` - address of the singleton contract
        fn singleton(self: @ContractState) -> ContractAddress {
            self.singleton.read()
        }

        /// Returns the price for a given asset in a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `AssetPrice` - latest price of the asset and its validity
        fn price(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> AssetPrice {
            let (value, is_valid) = self.pragma_oracle.price(pool_id, asset);
            AssetPrice { value, is_valid }
        }

        /// Returns the current interest rate for a given asset in a given pool, given it's utilization
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `utilization` - utilization of the asset
        /// * `last_updated` - last time the interest rate was updated
        /// * `last_full_utilization_rate` - The interest value when utilization is 100% [SCALE]
        /// # Returns
        /// * `interest_rate` - current interest rate
        fn interest_rate(
            self: @ContractState,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_full_utilization_rate: u256,
        ) -> u256 {
            let (interest_rate, _) = self
                .interest_rate_model
                .interest_rate(pool_id, asset, utilization, last_updated, last_full_utilization_rate);
            interest_rate
        }

        /// Returns the current rate accumulator for a given asset in a given pool, given it's utilization
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `utilization` - utilization of the asset
        /// * `last_updated` - last time the interest rate was updated
        /// * `last_rate_accumulator` - last rate accumulator
        /// * `last_full_utilization_rate` - the interest value when utilization is 100% [SCALE]
        /// # Returns
        /// * `rate_accumulator` - current rate accumulator
        /// * `last_full_utilization_rate` - the interest value when utilization is 100% [SCALE]
        fn rate_accumulator(
            self: @ContractState,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_rate_accumulator: u256,
            last_full_utilization_rate: u256,
        ) -> (u256, u256) {
            self
                .interest_rate_model
                .rate_accumulator(
                    pool_id, asset, utilization, last_updated, last_rate_accumulator, last_full_utilization_rate
                )
        }

        /// Modify position callback. Called by the Singleton contract before updating the position.
        /// See `before_modify_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `data` - modify position data
        /// # Returns
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        fn before_modify_position(
            ref self: ContractState, context: Context, collateral: Amount, debt: Amount, data: Span<felt252>,
        ) -> (Amount, Amount) {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            (collateral, debt)
        }

        /// Modify position callback. Called by the Singleton contract after updating the position.
        /// See `after_modify_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `data` - modify position data
        /// # Returns
        /// * `bool` - true if the callback was successful
        fn after_modify_position(
            ref self: ContractState, context: Context, collateral_delta: i257, debt_delta: i257, data: Span<felt252>
        ) -> bool {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self.position_hooks.after_modify_position(context, collateral_delta, debt_delta, data)
        }

        /// Liquidate position callback. Called by the Singleton contract before liquidating the position.
        /// See `before_liquidate_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `data` - liquidation data
        /// # Returns
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        fn before_liquidate_position(
            ref self: ContractState, context: Context, data: Span<felt252>
        ) -> (Amount, Amount, u256) {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self.position_hooks.before_liquidate_position(context, data)
        }

        /// Liquidate position callback. Called by the Singleton contract after liquidating the position.
        /// See `before_liquidate_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `bad_debt` - accrued bad debt from the liquidation
        /// * `data` - liquidation data
        /// # Returns
        /// * `bool` - true if the callback was successful
        fn after_liquidate_position(
            ref self: ContractState,
            context: Context,
            collateral_delta: i257,
            debt_delta: i257,
            bad_debt: u256,
            data: Span<felt252>,
        ) -> bool {
            true
        }
    }
}
