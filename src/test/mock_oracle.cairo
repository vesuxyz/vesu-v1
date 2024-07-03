use vesu::vendor::pragma::{PragmaPricesResponse, DataType};

#[starknet::interface]
trait IMockPragmaOracle<TContractState> {
    fn get_data_median(ref self: TContractState, data_type: DataType) -> PragmaPricesResponse;
    fn get_num_sources_aggregated(ref self: TContractState, key: felt252) -> u32;
    fn get_last_updated_timestamp(ref self: TContractState, key: felt252) -> u64;
    fn set_price(ref self: TContractState, key: felt252, price: u128);
    fn set_num_sources_aggregated(ref self: TContractState, key: felt252, num_sources_aggregated: u32);
    fn set_last_updated_timestamp(ref self: TContractState, key: felt252, last_updated_timestamp: u64);
}

#[starknet::contract]
mod MockPragmaOracle {
    use starknet::get_block_timestamp;
    use vesu::{vendor::pragma::{PragmaPricesResponse, DataType}, test::mock_oracle::IMockPragmaOracle};

    #[storage]
    struct Storage {
        prices: LegacyMap::<felt252, u128>,
        num_sources_aggregated: LegacyMap::<felt252, u32>,
        last_updated_timestamp: LegacyMap::<felt252, u64>,
    }

    #[abi(embed_v0)]
    impl MockPragmaOracleImpl of super::IMockPragmaOracle<ContractState> {
        fn get_num_sources_aggregated(ref self: ContractState, key: felt252) -> u32 {
            let num_sources_aggregated = self.num_sources_aggregated.read(key);
            if num_sources_aggregated == 0 {
                2
            } else {
                num_sources_aggregated
            }
        }

        fn get_last_updated_timestamp(ref self: ContractState, key: felt252) -> u64 {
            let last_updated_timestamp = self.last_updated_timestamp.read(key);
            if last_updated_timestamp == 0 {
                get_block_timestamp()
            } else {
                last_updated_timestamp
            }
        }

        fn get_data_median(ref self: ContractState, data_type: DataType) -> PragmaPricesResponse {
            match data_type {
                DataType::SpotEntry(key) => {
                    PragmaPricesResponse {
                        price: self.prices.read(key),
                        decimals: 18,
                        last_updated_timestamp: self.get_last_updated_timestamp(key),
                        num_sources_aggregated: self.get_num_sources_aggregated(key),
                        expiration_timestamp: Option::None,
                    }
                },
                DataType::FutureEntry => {
                    PragmaPricesResponse {
                        price: 0,
                        decimals: 0,
                        last_updated_timestamp: 0,
                        num_sources_aggregated: 0,
                        expiration_timestamp: Option::None,
                    }
                },
                DataType::GenericEntry => {
                    PragmaPricesResponse {
                        price: 0,
                        decimals: 0,
                        last_updated_timestamp: 0,
                        num_sources_aggregated: 0,
                        expiration_timestamp: Option::None,
                    }
                }
            }
        }

        fn set_price(ref self: ContractState, key: felt252, price: u128) {
            self.prices.write(key, price);
        }

        fn set_num_sources_aggregated(ref self: ContractState, key: felt252, num_sources_aggregated: u32) {
            self.num_sources_aggregated.write(key, num_sources_aggregated);
        }

        fn set_last_updated_timestamp(ref self: ContractState, key: felt252, last_updated_timestamp: u64) {
            self.last_updated_timestamp.write(key, last_updated_timestamp);
        }
    }
}
