#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct OracleConfig {
    pragma_key: felt252,
    timeout: u64, // [seconds]
    number_of_sources: u32, // [0, 255]
}

fn assert_oracle_config(oracle_config: OracleConfig) {
    assert!(oracle_config.pragma_key != 0, "pragma-key-must-be-set");
}

#[starknet::component]
mod pragma_oracle_component {
    use starknet::{ContractAddress, get_block_timestamp};
    use vesu::{
        units::{SCALE}, math::{pow_10},
        vendor::pragma::{
            PragmaPricesResponse, DataType, AggregationMode, IPragmaABIDispatcher, IPragmaABIDispatcherTrait
        },
        extension::components::pragma_oracle::{OracleConfig, assert_oracle_config}
    };

    #[storage]
    struct Storage {
        oracle_address: ContractAddress,
        // (pool_id, asset) -> oracle configuration
        oracle_configs: LegacyMap::<(felt252, ContractAddress), OracleConfig>,
    }

    #[derive(Drop, starknet::Event)]
    struct SetOracleConfig {
        pool_id: felt252,
        asset: ContractAddress,
        oracle_config: OracleConfig,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetOracleConfig: SetOracleConfig
    }

    #[generate_trait]
    impl PragmaOracleTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
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
            let OracleConfig { pragma_key, timeout, number_of_sources } = self.oracle_configs.read((pool_id, asset));
            let dispatcher = IPragmaABIDispatcher { contract_address: self.oracle_address.read() };
            let response = dispatcher.get_data_median(DataType::SpotEntry(pragma_key));
            let denominator = pow_10(response.decimals);
            let price = response.price.into() * SCALE / denominator;
            let valid = (timeout == 0
                || (timeout != 0 && (get_block_timestamp() - response.last_updated_timestamp) <= timeout))
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
    }
}
