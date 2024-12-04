use vesu::vendor::pragma::AggregationMode;

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct OracleConfig {
    pragma_key: felt252,
    timeout: u64, // [seconds]
    number_of_sources: u32, // [0, 255]
    start_time_offset: u64, // [seconds]
    time_window: u64, // [seconds]
    aggregation_mode: AggregationMode
}

fn assert_oracle_config(oracle_config: OracleConfig) {
    assert!(oracle_config.pragma_key != 0, "pragma-key-must-be-set");
    assert!(
        oracle_config.time_window <= oracle_config.start_time_offset, "time-window-must-be-less-than-start-time-offset"
    );
}

#[starknet::component]
mod pragma_oracle_component {
    use starknet::{ContractAddress, get_block_timestamp};
    use vesu::{
        units::{SCALE, SCALE_128}, math::{pow_10},
        vendor::pragma::{
            PragmaPricesResponse, DataType, AggregationMode, IPragmaABIDispatcher, IPragmaABIDispatcherTrait,
            ISummaryStatsABIDispatcher, ISummaryStatsABIDispatcherTrait
        },
        extension::components::pragma_oracle::{OracleConfig, assert_oracle_config}
    };

    #[storage]
    struct Storage {
        oracle_address: ContractAddress,
        summary_address: ContractAddress,
        // (pool_id, asset) -> oracle configuration
        oracle_configs: LegacyMap::<(felt252, ContractAddress), OracleConfig>,
    }

    #[derive(Drop, starknet::Event)]
    struct SetOracleConfig {
        pool_id: felt252,
        asset: ContractAddress,
        oracle_config: OracleConfig,
    }

    #[derive(Drop, starknet::Event)]
    struct SetOracleParameter {
        pool_id: felt252,
        asset: ContractAddress,
        parameter: felt252,
        value: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetOracleConfig: SetOracleConfig,
        SetOracleParameter: SetOracleParameter
    }

    #[generate_trait]
    impl PragmaOracleTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        /// Sets the address of the summary contract
        /// # Arguments
        /// * `summary_address` - address of the summary contract
        fn set_summary_address(ref self: ComponentState<TContractState>, summary_address: ContractAddress) {
            self.summary_address.write(summary_address);
        }

        /// Returns the address of the summary contract
        /// # Returns
        /// * `summary_address` - address of the summary contract
        fn summary_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.summary_address.read()
        }

        /// Sets the address of the pragma oracle contract
        /// # Arguments
        /// * `oracle_address` - address of the pragma oracle contract
        fn set_oracle(ref self: ComponentState<TContractState>, oracle_address: ContractAddress) {
            assert!(self.oracle_address.read().is_zero(), "oracle-already-initialized");
            self.oracle_address.write(oracle_address);
        }

        /// Returns the address of the pragma oracle contract
        /// # Returns
        /// * `oracle_address` - address of the pragma oracle contract
        fn oracle_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.oracle_address.read()
        }

        /// Returns the current price for an asset in a given pool and the validity status of the price.
        /// The price can be invalid if price is too old (stale) or if the number of price sources is too low.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `price` - current price of the asset
        /// * `valid` - whether the price is valid
        fn price(self: @ComponentState<TContractState>, pool_id: felt252, asset: ContractAddress) -> (u256, bool) {
            let OracleConfig { pragma_key,
            timeout,
            number_of_sources,
            start_time_offset,
            time_window,
            aggregation_mode } =
                self
                .oracle_configs
                .read((pool_id, asset));
            let dispatcher = IPragmaABIDispatcher { contract_address: self.oracle_address.read() };
            let response = dispatcher.get_data(DataType::SpotEntry(pragma_key), aggregation_mode);

            // calculate the twap if start_time_offset and time_window are set
            let price = if start_time_offset == 0 || time_window == 0 {
                response.price.into() * SCALE / pow_10(response.decimals.into())
            } else {
                let summary = ISummaryStatsABIDispatcher { contract_address: self.summary_address.read() };
                let (value, decimals) = summary
                    .calculate_twap(
                        DataType::SpotEntry(pragma_key),
                        aggregation_mode,
                        time_window,
                        get_block_timestamp() - start_time_offset
                    );
                value.into() * SCALE / pow_10(decimals.into())
            };

            // ensure that price is not stale and that the number of sources is sufficient
            let time_delta = if response.last_updated_timestamp >= get_block_timestamp() {
                0
            } else {
                get_block_timestamp() - response.last_updated_timestamp
            };
            let valid = (timeout == 0 || (timeout != 0 && time_delta <= timeout))
                && (number_of_sources == 0
                    || (number_of_sources != 0 && number_of_sources <= response.num_sources_aggregated));

            (price, valid)
        }

        /// Sets the oracle configuration for a given pool and asset
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `oracle_config` - oracle configuration
        fn set_oracle_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            oracle_config: OracleConfig
        ) {
            let OracleConfig { pragma_key, .. } = self.oracle_configs.read((pool_id, asset));
            assert!(pragma_key == 0, "oracle-config-already-set");
            assert_oracle_config(oracle_config);

            self.oracle_configs.write((pool_id, asset), oracle_config);

            self.emit(SetOracleConfig { pool_id, asset, oracle_config });
        }

        /// Sets a parameter for a given oracle configuration of an asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_oracle_parameter(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            parameter: felt252,
            value: felt252
        ) {
            let mut oracle_config: OracleConfig = self.oracle_configs.read((pool_id, asset));
            assert!(oracle_config.pragma_key != 0, "oracle-config-not-set");

            if parameter == 'pragma_key' {
                oracle_config.pragma_key = value;
            } else if parameter == 'timeout' {
                oracle_config.timeout = value.try_into().unwrap();
            } else if parameter == 'number_of_sources' {
                oracle_config.number_of_sources = value.try_into().unwrap();
            } else if parameter == 'start_time_offset' {
                oracle_config.start_time_offset = value.try_into().unwrap();
            } else if parameter == 'time_window' {
                oracle_config.time_window = value.try_into().unwrap();
            } else if parameter == 'aggregation_mode' {
                if value == 'Median' {
                    oracle_config.aggregation_mode = AggregationMode::Median;
                } else if value == 'Mean' {
                    oracle_config.aggregation_mode = AggregationMode::Mean;
                } else {
                    assert!(false, "invalid-aggregation-mode");
                }
            } else {
                assert!(false, "invalid-oracle-parameter");
            }

            assert_oracle_config(oracle_config);
            self.oracle_configs.write((pool_id, asset), oracle_config);

            self.emit(SetOracleParameter { pool_id, asset, parameter, value });
        }
    }
}
