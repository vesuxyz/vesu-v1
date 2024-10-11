use starknet::ContractAddress;

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct ChainlinkOracleConfig {
    aggregator: ContractAddress,
    timeout: u64 // [seconds]
}

fn assert_chainlink_oracle_config(chainlink_oracle_config: ChainlinkOracleConfig) {
    assert!(chainlink_oracle_config.aggregator != Zeroable::zero(), "chainlink-aggregator-must-be-set");
}

#[starknet::component]
mod chainlink_oracle_component {
    use starknet::{ContractAddress, get_block_timestamp};
    use vesu::{
        units::{SCALE}, math::{pow_10},
        vendor::chainlink::{Round, IChainlinkAggregatorDispatcher, IChainlinkAggregatorDispatcherTrait},
        extension::components::chainlink_oracle::{ChainlinkOracleConfig, assert_chainlink_oracle_config}
    };

    #[storage]
    struct Storage {
        // (pool_id, asset) -> oracle configuration
        chainlink_oracle_configs: LegacyMap::<(felt252, ContractAddress), ChainlinkOracleConfig>,
    }

    #[derive(Drop, starknet::Event)]
    struct SetChainlinkOracleConfig {
        pool_id: felt252,
        asset: ContractAddress,
        chainlink_oracle_config: ChainlinkOracleConfig,
    }

    #[derive(Drop, starknet::Event)]
    struct SetChainlinkOracleParameter {
        pool_id: felt252,
        asset: ContractAddress,
        parameter: felt252,
        value: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetChainlinkOracleConfig: SetChainlinkOracleConfig,
        SetChainlinkOracleParameter: SetChainlinkOracleParameter
    }

    #[generate_trait]
    impl ChainlinkOracleTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        /// Returns the current price for an asset in a given pool and the validity status of the price.
        /// The price can be invalid if price is too old (stale) or if the number of price sources is too low.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `price` - current price of the asset
        /// * `valid` - whether the price is valid
        fn price(self: @ComponentState<TContractState>, pool_id: felt252, asset: ContractAddress) -> (u256, bool) {
            let ChainlinkOracleConfig { aggregator, timeout } = self.chainlink_oracle_configs.read((pool_id, asset));
            let dispatcher = IChainlinkAggregatorDispatcher { contract_address: aggregator };
            let response: Round = dispatcher.latest_round_data();
            let denominator = pow_10(dispatcher.decimals().into());
            let price = response.answer.into() * SCALE / denominator;

            let time_delta = if response.updated_at >= get_block_timestamp() {
                0
            } else {
                get_block_timestamp() - response.updated_at
            };
            let valid = (timeout == 0 || (timeout != 0 && time_delta <= timeout));
            (price, valid)
        }

        /// Sets th chainlink oracle configuration for a given pool and asset
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `chainlink_oracle_config` - chainlink oracle configuration
        fn set_chainlink_oracle_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            chainlink_oracle_config: ChainlinkOracleConfig
        ) {
            let ChainlinkOracleConfig { aggregator, .. } = self.chainlink_oracle_configs.read((pool_id, asset));
            assert!(aggregator == Zeroable::zero(), "chainlink-oracle-config-already-set");
            assert_chainlink_oracle_config(chainlink_oracle_config);

            self.chainlink_oracle_configs.write((pool_id, asset), chainlink_oracle_config);

            self.emit(SetChainlinkOracleConfig { pool_id, asset, chainlink_oracle_config });
        }

        /// Sets a parameter for a given chainlink oracle configuration of an asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_chainlink_oracle_parameter(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            parameter: felt252,
            value: u64
        ) {
            let mut chainlink_oracle_config: ChainlinkOracleConfig = self
                .chainlink_oracle_configs
                .read((pool_id, asset));
            assert!(chainlink_oracle_config.aggregator != Zeroable::zero(), "chainlink-oracle-config-not-set");

            if parameter == 'timeout' {
                chainlink_oracle_config.timeout = value;
            } else {
                assert!(false, "invalid-chainlink-oracle-parameter");
            }

            assert_chainlink_oracle_config(chainlink_oracle_config);
            self.chainlink_oracle_configs.write((pool_id, asset), chainlink_oracle_config);

            self.emit(SetChainlinkOracleParameter { pool_id, asset, parameter, value });
        }
    }
}
