#[starknet::component]
mod pragma_oracle_component {
    use starknet::{ContractAddress, get_block_timestamp};
    use vesu::{
        units::{SCALE}, math::{pow_10},
        vendor::pragma::{
            PragmaPricesResponse, DataType, AggregationMode, IPragmaABIDispatcher, IPragmaABIDispatcherTrait
        },
    };

    #[storage]
    struct Storage {
        oracle_address: ContractAddress,
        // (pool_id, asset) -> (pragma oracle key, timeout)
        oracle_configs: LegacyMap::<(felt252, ContractAddress), (felt252, u64, u32)>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[generate_trait]
    impl PragmaOracleTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, oracle_address: ContractAddress) {
            assert!(self.oracle_address.read().is_zero(), "oracle-already-initialized");
            self.oracle_address.write(oracle_address);
        }

        fn oracle_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.oracle_address.read()
        }

        fn price(self: @ComponentState<TContractState>, pool_id: felt252, asset: ContractAddress) -> (u256, bool) {
            let (key, timeout, sources): (felt252, u64, u32) = self.oracle_configs.read((pool_id, asset));
            let dispatcher = IPragmaABIDispatcher { contract_address: self.oracle_address.read() };
            let response = dispatcher.get_data_median(DataType::SpotEntry(key));
            let denominator = pow_10(response.decimals);
            let price = response.price.into() * SCALE / denominator;
            let valid = (timeout == 0
                || (timeout != 0 && (get_block_timestamp() - response.last_updated_timestamp) <= timeout))
                && (sources == 0 || (sources != 0 && sources <= response.num_sources_aggregated));
            (price, valid)
        }

        fn set_oracle_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            pragma_key: felt252,
            timeout: u64,
            number_of_sources: u32
        ) {
            let (key, _, _): (felt252, u64, u32) = self.oracle_configs.read((pool_id, asset));
            assert!(key == 0, "oracle-already-set");
            self.oracle_configs.write((pool_id, asset), (pragma_key, timeout, number_of_sources));
        }
    }
}
