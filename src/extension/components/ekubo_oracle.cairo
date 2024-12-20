use starknet::ContractAddress;

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct EkuboOracleConfig {
    decimals: u8,
    period: u64 // [seconds]
}

#[starknet::component]
mod ekubo_oracle_component {
    use starknet::ContractAddress;
    use super::EkuboOracleConfig;
    use vesu::math::pow_10;
    use vesu::units::SCALE;
    use vesu::vendor::{
        ekubo::{
            construct_oracle_pool_key, IEkuboOracleDispatcher, IEkuboOracleDispatcherTrait, IEkuboCoreDispatcher,
            IEkuboCoreDispatcherTrait, PoolKey,
        },
        erc20::{IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait}
    };

    const TWO_128: u256 = 0x100000000000000000000000000000000; // 2^128

    #[storage]
    struct Storage {
        core: ContractAddress,
        oracle_address: ContractAddress,
        // (pool_id, asset) -> oracle configuration
        ekubo_oracle_configs: LegacyMap::<(felt252, ContractAddress), EkuboOracleConfig>,
        quote_asset: ContractAddress,
        quote_asset_decimals: u8,
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
        value: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetEkuboOracleConfig: SetEkuboOracleConfig,
        SetEkuboOracleParameter: SetEkuboOracleParameter
    }

    #[generate_trait]
    impl EkuboOracleTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        /// Sets the address of the Ekubo core contract
        /// # Arguments
        /// * `core` - address of the Ekubo core contract
        fn set_core(ref self: ComponentState<TContractState>, core: ContractAddress) {
            assert!(self.core.read().is_zero(), "core-already-initialized");
            self.core.write(core);
        }

        /// Returns the address of the Ekubo core contract
        /// # Returns
        /// * `oracle_address` - address of the Ekubo core contract
        fn core(self: @ComponentState<TContractState>) -> ContractAddress {
            self.core.read()
        }

        /// Sets the address of the Ekubo oracle extension contract
        /// # Arguments
        /// * `oracle_address` - address of the Ekubo oracle extension contract
        fn set_oracle(ref self: ComponentState<TContractState>, oracle_address: ContractAddress) {
            assert!(self.oracle_address.read().is_zero(), "oracle-already-initialized");
            self.oracle_address.write(oracle_address);
        }

        /// Returns the address of the Ekubo oracle extension contract
        /// # Returns
        /// * `oracle_address` - address of the Ekubo oracle extension contract
        fn oracle_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.oracle_address.read()
        }

        /// Sets the address of the quote asset
        /// # Arguments
        /// * `quote_asset` - address of the asset to be used for quoting prices
        fn set_quote_asset(ref self: ComponentState<TContractState>, quote_asset: ContractAddress) {
            assert!(self.quote_asset.read().is_zero(), "quote-asset-already-initialized");
            assert!(quote_asset.is_non_zero(), "invalid-ekubo-oracle-quote-token");
            self.quote_asset.write(quote_asset);

            let quote_asset_decimals: u8 = IERC20MetadataDispatcher { contract_address: quote_asset }.decimals();
            self.quote_asset_decimals.write(quote_asset_decimals);
        }

        /// Returns the address of the asset to be used for quoting prices
        /// # Returns
        /// * `quote_asset` - address of the quote asset
        fn quote_asset(self: @ComponentState<TContractState>) -> ContractAddress {
            self.quote_asset.read()
        }

        /// Returns the current price for an asset in a given pool and the validity status of the price.
        /// Status is always true, since it's a single onchain source.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `price` - current price of the asset
        /// * `valid` - always `true`
        fn price(self: @ComponentState<TContractState>, pool_id: felt252, asset: ContractAddress) -> (u256, bool) {
            let EkuboOracleConfig { decimals, period } = self.ekubo_oracle_configs.read((pool_id, asset));
            let oracle = IEkuboOracleDispatcher { contract_address: self.oracle_address.read() };
            let price = oracle.get_price_x128_over_last(asset, self.quote_asset.read(), period);

            // Adjust the scale based on the difference in precision between the base asset 
            // and the quote asset
            let quote_asset_decimals: u8 = self.quote_asset_decimals.read();
            let adjusted_scale = if quote_asset_decimals <= decimals {
                SCALE * pow_10((decimals - quote_asset_decimals).into())
            } else {
                SCALE / pow_10((quote_asset_decimals - decimals).into())
            };

            let price = price * adjusted_scale / TWO_128;

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
            assert!(ekubo_oracle_config.period.is_non_zero(), "invalid-ekubo-oracle-period");

            // check if the pool is liquid
            let pool_key: PoolKey = construct_oracle_pool_key(
                asset, self.quote_asset.read(), self.oracle_address.read()
            );

            let liquidity = IEkuboCoreDispatcher { contract_address: self.core.read() }.get_pool_liquidity(pool_key);
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
            value: felt252
        ) {
            let mut ekubo_oracle_config: EkuboOracleConfig = self.ekubo_oracle_configs.read((pool_id, asset));
            assert!(ekubo_oracle_config.period.is_non_zero(), "ekubo-oracle-config-not-set");

            if parameter == 'period' {
                assert!(value != 0, "invalid-ekubo-oracle-period-value");
                ekubo_oracle_config.period = value.try_into().unwrap();
            } else {
                assert!(false, "invalid-ekubo-oracle-parameter");
            }

            self.ekubo_oracle_configs.write((pool_id, asset), ekubo_oracle_config);
            self.emit(SetEkuboOracleParameter { pool_id, asset, parameter, value });
        }
    }
}
