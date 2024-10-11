#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
struct Round {
    // used as u128 internally, but necessary for phase-prefixed round ids as returned by proxy
    round_id: felt252,
    answer: u128,
    block_num: u64,
    started_at: u64,
    updated_at: u64,
}

#[starknet::interface]
trait IChainlinkAggregator<TContractState> {
    fn latest_round_data(self: @TContractState) -> Round;
    fn round_data(self: @TContractState, round_id: u128) -> Round;
    fn description(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn latest_answer(self: @TContractState) -> u128;
}
