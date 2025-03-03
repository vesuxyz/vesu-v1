use starknet::ContractAddress;

#[starknet::interface]
trait IMockEkuboOracle<TContractState> {
    fn get_earliest_observation_time(
        self: @TContractState, token_a: ContractAddress, token_b: ContractAddress
    ) -> Option<u64>;
    fn set_earliest_observation_time(
        ref self: TContractState, token_a: ContractAddress, token_b: ContractAddress, timestamp: u64
    );
    fn get_price_x128_over_last(
        self: @TContractState, base_token: ContractAddress, quote_token: ContractAddress, period: u64
    ) -> u256;
    fn set_price_x128(ref self: TContractState, base_token: ContractAddress, quote_token: ContractAddress, price: u256);
}

#[starknet::contract]
mod MockEkuboOracle {
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        // Mapping of (base token, quote token) to their earliest observation time
        earliest_observation_time: LegacyMap::<(ContractAddress, ContractAddress), u64>,
        // Mapping of (base_token, quote_token) tuple to x128 price
        price_x128: LegacyMap::<(ContractAddress, ContractAddress), u256>,
    }

    #[abi(embed_v0)]
    impl MockEkuboOracleImpl of super::IMockEkuboOracle<ContractState> {
        fn get_earliest_observation_time(
            self: @ContractState, token_a: ContractAddress, token_b: ContractAddress
        ) -> Option<u64> {
            let timestamp = self.earliest_observation_time.read((token_a, token_b));
            if timestamp.is_zero() {
                Option::None
            } else {
                Option::Some(timestamp)
            }
        }

        fn set_earliest_observation_time(
            ref self: ContractState, token_a: ContractAddress, token_b: ContractAddress, timestamp: u64
        ) {
            self.earliest_observation_time.write((token_a, token_b), timestamp)
        }

        fn get_price_x128_over_last(
            self: @ContractState, base_token: ContractAddress, quote_token: ContractAddress, period: u64
        ) -> u256 {
            self.price_x128.read((base_token, quote_token))
        }

        fn set_price_x128(
            ref self: ContractState, base_token: ContractAddress, quote_token: ContractAddress, price: u256
        ) {
            self.price_x128.write((base_token, quote_token), price);
        }
    }
}

