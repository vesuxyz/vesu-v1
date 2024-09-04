use vesu::vendor::chainlink::Round;

#[starknet::interface]
trait IMockChainlinkAggregator<TContractState> {
    fn latest_round_data(ref self: TContractState) -> Round;
    fn decimals(ref self: TContractState) -> u8;
    fn set_round(ref self: TContractState, round: Round);
}

#[starknet::contract]
mod MockChainlinkAggregator {
    use starknet::{get_block_timestamp, get_caller_address};
    use vesu::vendor::chainlink::{Round};

    #[storage]
    struct Storage {
        round: Round
    }

    #[abi(embed_v0)]
    impl MockChainlinkAggregatorImpl of super::IMockChainlinkAggregator<ContractState> {
        fn decimals(ref self: ContractState) -> u8 {
            8_u8
        }

        fn latest_round_data(ref self: ContractState) -> Round {
            self.round.read()
        }

        fn set_round(ref self: ContractState, round: Round) {
            self.round.write(round);
        }
    }
}

