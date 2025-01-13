use starknet::ContractAddress;

#[derive(Drop, Copy, Serde)]
enum DataType {
    SpotEntry: felt252,
    FutureEntry: (felt252, u64),
    GenericEntry: felt252,
}

#[derive(Serde, Drop, Copy, PartialEq, Default, starknet::Store)]
enum AggregationMode {
    #[default]
    Median,
    Mean,
    ConversionRate,
    Error,
}

#[derive(Serde, Drop, Copy)]
struct PragmaPricesResponse {
    price: u128,
    decimals: u32,
    last_updated_timestamp: u64,
    num_sources_aggregated: u32,
    expiration_timestamp: Option<u64>,
}

#[starknet::interface]
trait IPragmaABI<TContractState> {
    fn get_data(self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode) -> PragmaPricesResponse;
    fn get_data_median(self: @TContractState, data_type: DataType) -> PragmaPricesResponse;
}

#[starknet::interface]
trait ISummaryStatsABI<TContractState> {
    fn calculate_twap(
        self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode, time: u64, start_time: u64
    ) -> (u128, u32);
}
