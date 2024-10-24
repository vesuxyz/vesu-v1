use alexandria_math::i257::i257;
use starknet::ContractAddress;
use vesu::data_model::{UnsignedAmount, Amount, Context, AssetPrice};

#[starknet::interface]
trait IExtension<TContractState> {
    fn singleton(self: @TContractState) -> ContractAddress;
    fn price(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> AssetPrice;
    fn interest_rate(
        self: @TContractState,
        pool_id: felt252,
        asset: ContractAddress,
        utilization: u256,
        last_updated: u64,
        last_full_utilization_rate: u256,
    ) -> u256;
    fn rate_accumulator(
        self: @TContractState,
        pool_id: felt252,
        asset: ContractAddress,
        utilization: u256,
        last_updated: u64,
        last_rate_accumulator: u256,
        last_full_utilization_rate: u256,
    ) -> (u256, u256);
    fn before_modify_position(
        ref self: TContractState,
        context: Context,
        collateral: Amount,
        debt: Amount,
        data: Span<felt252>,
        caller: ContractAddress
    ) -> (Amount, Amount);
    fn after_modify_position(
        ref self: TContractState,
        context: Context,
        collateral_delta: i257,
        collateral_shares_delta: i257,
        debt_delta: i257,
        nominal_debt_delta: i257,
        data: Span<felt252>,
        caller: ContractAddress
    ) -> bool;
    fn before_transfer_position(
        ref self: TContractState,
        from_context: Context,
        to_context: Context,
        collateral: UnsignedAmount,
        debt: UnsignedAmount,
        data: Span<felt252>,
        caller: ContractAddress
    ) -> (UnsignedAmount, UnsignedAmount);
    fn after_transfer_position(
        ref self: TContractState,
        from_context: Context,
        to_context: Context,
        collateral_delta: u256,
        collateral_shares_delta: u256,
        debt_delta: u256,
        nominal_debt_delta: u256,
        data: Span<felt252>,
        caller: ContractAddress
    ) -> bool;
    fn before_liquidate_position(
        ref self: TContractState, context: Context, data: Span<felt252>, caller: ContractAddress
    ) -> (u256, u256, u256);
    fn after_liquidate_position(
        ref self: TContractState,
        context: Context,
        collateral_delta: i257,
        collateral_shares_delta: i257,
        debt_delta: i257,
        nominal_debt_delta: i257,
        bad_debt: u256,
        data: Span<felt252>,
        caller: ContractAddress
    ) -> bool;
}
