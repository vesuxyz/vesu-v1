use vesu::vendor::ekubo::PoolKey;

#[starknet::interface]
trait IMockEkuboCore<TContractState> {
    fn get_pool_liquidity(self: @TContractState, pool_key: PoolKey) -> u128;
    fn set_pool_liquidity(ref self: TContractState, pool_key: PoolKey, liquidity: u128);
}

#[starknet::contract]
mod MockEkuboCore {
    use vesu::vendor::ekubo::PoolKey;

    #[storage]
    struct Storage {
        // Mapping of (base_token, quote_token) tuple to x128 price
        liquidity: LegacyMap::<PoolKey, u128>,
    }

    #[abi(embed_v0)]
    impl MockEkuboCoreImpl of super::IMockEkuboCore<ContractState> {
        fn get_pool_liquidity(self: @ContractState, pool_key: PoolKey) -> u128 {
            self.liquidity.read(pool_key)
        }

        fn set_pool_liquidity(ref self: ContractState, pool_key: PoolKey, liquidity: u128) {
            self.liquidity.write(pool_key, liquidity);
        }
    }
}

