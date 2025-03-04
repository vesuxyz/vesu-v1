use starknet::ContractAddress;

// https://github.com/EkuboProtocol/oracle-extension/blob/054747d57d865a73ae5e4874e50eab28b777d732/src/oracle.cairo#L539
const MAX_TICK_SPACING: u128 = 354892;

// https://github.com/EkuboProtocol/abis/blob/main/src/types/keys.cairo
#[derive(Copy, Drop, Hash, Serde, starknet::Store)]
pub struct PoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
    pub extension: ContractAddress,
}

// https://github.com/EkuboProtocol/abis/blob/main/src/interfaces/core.cairo
#[starknet::interface]
trait IEkuboCore<TContractState> {
    fn get_pool_liquidity(self: @TContractState, pool_key: PoolKey) -> u128;
}

// https://github.com/EkuboProtocol/oracle-extension/blob/main/src/oracle.cairo
#[starknet::interface]
trait IEkuboOracle<TContractState> {
    // Returns the timestamp of the earliest observation for a given pair, or Option::None if the
    // pair has no observations
    fn get_earliest_observation_time(
        self: @TContractState, token_a: ContractAddress, token_b: ContractAddress
    ) -> Option<u64>;
    // Returns the geomean average price of a token as a 128.128 over the last `period` seconds
    fn get_price_x128_over_last(
        self: @TContractState, base_token: ContractAddress, quote_token: ContractAddress, period: u64
    ) -> u256;
}

pub fn construct_oracle_pool_key(
    token0: ContractAddress, token1: ContractAddress, extension: ContractAddress
) -> PoolKey {
    let (token0, token1) = core::cmp::minmax(token0, token1);

    // oracle pools *must* have 0 fee and max tick spacing, so this key is always valid
    PoolKey { token0, token1, fee: 0, tick_spacing: MAX_TICK_SPACING, extension }
}
