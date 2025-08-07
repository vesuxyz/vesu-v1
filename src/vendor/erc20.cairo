#[starknet::interface]
pub trait IERC20Metadata<TState> {
    /// Returns the name of the token.
    fn name(self: @TState) -> felt252;

    /// Returns the symbol of the token.
    fn symbol(self: @TState) -> felt252;

    /// Returns the number of decimals used to get its user representation.
    fn decimals(self: @TState) -> u8;
}
