#[derive(Drop, Copy, Serde)]
pub enum DataType {
    SpotEntry: felt252,
    FutureEntry: (felt252, u64),
    GenericEntry: felt252,
}

#[derive(Serde, Drop, Copy, PartialEq, Default, starknet::Store)]
pub enum AggregationMode {
    #[default]
    Median,
    Mean,
    Error,
}

#[derive(Serde, Drop, Copy)]
pub struct PragmaPricesResponse {
    pub price: u128,
    pub decimals: u32,
    pub last_updated_timestamp: u64,
    pub num_sources_aggregated: u32,
    pub expiration_timestamp: Option<u64>,
}

#[starknet::interface]
pub trait IPragmaABI<TContractState> {
    fn get_data(self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode) -> PragmaPricesResponse;
    fn get_data_median(self: @TContractState, data_type: DataType) -> PragmaPricesResponse;
}

#[starknet::interface]
pub trait ISummaryStatsABI<TContractState> {
    fn calculate_twap(
        self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode, time: u64, start_time: u64,
    ) -> (u128, u32);
}
