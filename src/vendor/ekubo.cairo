use starknet::ContractAddress;

// https://docs.ekubo.org/integration-guides/reference/contract-addresses#upgradeable-contracts
const EKUBO_CORE: felt252 = 0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b;

// https://github.com/EkuboProtocol/oracle-extension/blob/054747d57d865a73ae5e4874e50eab28b777d732/src/oracle.cairo#L539
const MAX_TICK_SPACING: u128 = 354892;

// https://github.com/EkuboProtocol/abis/blob/main/src/types/keys.cairo
#[derive(Copy, Drop, Serde)]
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
    // Returns the geomean average price of a token as a 128.128 over the last `period` seconds
    fn get_price_x128_over_last(
        self: @TContractState, base_token: ContractAddress, quote_token: ContractAddress, period: u64
    ) -> u256;
}
