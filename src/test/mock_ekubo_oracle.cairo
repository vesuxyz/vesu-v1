use starknet::ContractAddress;

#[starknet::interface]
trait IMockEkuboOracle<TContractState> {
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
        // Mapping of (base_token, quote_token) tuple to x128 price
        price_x128: LegacyMap::<(ContractAddress, ContractAddress), u256>,
    }

    #[abi(embed_v0)]
    impl MockEkuboOracleImpl of super::IMockEkuboOracle<ContractState> {
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

