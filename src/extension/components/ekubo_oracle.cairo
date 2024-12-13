use starknet::ContractAddress;

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct EkuboOracleConfig {
    oracle_pool: ContractAddress, // Ekubo Oracle pool address
    quote_token: ContractAddress,
    period: u64 // [seconds]
}

#[starknet::component]
mod ekubo_oracle_component {
    use starknet::ContractAddress;
    use super::EkuboOracleConfig;
    use vesu::units::SCALE;
    use vesu::vendor::{
        ekubo::{
            IEkuboOracleDispatcher, IEkuboOracleDispatcherTrait, IEkuboCoreDispatcher, IEkuboCoreDispatcherTrait,
            PoolKey, EKUBO_CORE, MAX_TICK_SPACING
        },
        erc20::{IERC20Dispatcher, IERC20DispatcherTrait}
    };

    const TWO_128: u256 = 0x100000000000000000000000000000000; // 2^128

    #[storage]
    struct Storage {
        // (pool_id, asset) -> oracle configuration
        ekubo_oracle_configs: LegacyMap::<(felt252, ContractAddress), EkuboOracleConfig>,
    }

    #[derive(Drop, starknet::Event)]
    struct SetEkuboOracleConfig {
        pool_id: felt252,
        asset: ContractAddress,
        ekubo_oracle_config: EkuboOracleConfig,
    }

    #[derive(Drop, starknet::Event)]
    struct SetEkuboOracleParameter {
        pool_id: felt252,
        asset: ContractAddress,
        parameter: felt252,
        value: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetEkuboOracleConfig: SetEkuboOracleConfig,
        SetEkuboOracleParameter: SetEkuboOracleParameter
    }

    #[generate_trait]
    impl EkuboOracleTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        /// Returns the current price for an asset in a given pool and the validity status of the price.
        /// Status is always true, since it's a single onchain source.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `price` - current price of the asset
        /// * `valid` - always `true`
        fn price(self: @ComponentState<TContractState>, pool_id: felt252, asset: ContractAddress) -> (u256, bool) {
            let EkuboOracleConfig { oracle_pool, quote_token, period } = self
                .ekubo_oracle_configs
                .read((pool_id, asset));
            let oracle = IEkuboOracleDispatcher { contract_address: oracle_pool };
            let price = oracle.get_price_x128_over_last(asset, quote_token, period);

            let price = price * SCALE / TWO_128;

            (price, true)
        }

        /// Sets the Ekubo oracle configuration for a given pool and asset
        /// # Arguments
        /// * `pool_id` - id of the Vesu pool
        /// * `asset` - address of the asset
        /// * `ekubo_oracle_config` - Ekubo oracle configuration
        fn set_ekubo_oracle_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            ekubo_oracle_config: EkuboOracleConfig
        ) {
            let EkuboOracleConfig { oracle_pool, .. } = self.ekubo_oracle_configs.read((pool_id, asset));
            assert!(oracle_pool == Zeroable::zero(), "ekubo-oracle-config-already-set");
            assert!(ekubo_oracle_config.oracle_pool.is_non_zero(), "invalid-ekubo-oracle-pool");
            assert!(ekubo_oracle_config.quote_token.is_non_zero(), "invalid-ekubo-oracle-quote-token");
            assert!(ekubo_oracle_config.period.is_non_zero(), "invalid-ekubo-oracle-period");

            // check if the pool is liquid
            let (token0, token1) = core::cmp::minmax(asset, ekubo_oracle_config.quote_token);

            // oracle pools *must* have 0 fee and max tick spacing, so this key is always valid
            let pool_key = PoolKey {
                token0, token1, fee: 0, tick_spacing: MAX_TICK_SPACING, extension: ekubo_oracle_config.oracle_pool
            };

            let ekubo_core: ContractAddress = EKUBO_CORE.try_into().unwrap();
            let liquidity = IEkuboCoreDispatcher { contract_address: ekubo_core }.get_pool_liquidity(pool_key);
            assert!(liquidity.is_non_zero(), "ekubo-oracle-pool-illiquid");

            self.ekubo_oracle_configs.write((pool_id, asset), ekubo_oracle_config);
            self.emit(SetEkuboOracleConfig { pool_id, asset, ekubo_oracle_config });
        }

        /// Sets a parameter for a given Ekubo oracle configuration of an asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_ekubo_oracle_parameter(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            parameter: felt252,
            value: u64
        ) {
            let mut ekubo_oracle_config: EkuboOracleConfig = self.ekubo_oracle_configs.read((pool_id, asset));

            if parameter == 'period' {
                assert!(value != 0, "invalid-ekubo-oracle-period-value");
                ekubo_oracle_config.period = value;
            } else {
                assert!(false, "invalid-ekubo-oracle-parameter");
            }

            self.ekubo_oracle_configs.write((pool_id, asset), ekubo_oracle_config);
            self.emit(SetEkuboOracleParameter { pool_id, asset, parameter, value });
        }
    }
}
