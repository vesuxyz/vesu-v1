use alexandria_math::i257::i257;
use starknet::ContractAddress;
use vesu::{units::SCALE, math::pow_10};

#[derive(PartialEq, Copy, Drop, Serde, starknet::StorePacking)]
struct Position {
    collateral_shares: u256, // packed as u128 [SCALE] 
    nominal_debt: u256, // packed as u123 [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::StorePacking)]
struct AssetConfig { //                                     | slot | packed | notes
    //                                                      | ---- | ------ | ----- 
    total_collateral_shares: u256, //       [SCALE]         | 1    | u128   |
    total_nominal_debt: u256, //            [SCALE]         | 1    | u123   |
    reserve: u256, //                       [asset scale]   | 2    | u128   |
    max_utilization: u256, //               [SCALE]         | 2    | u8     | constant percentage
    floor: u256, //                         [SCALE]         | 2    | u8     | constant decimals
    scale: u256, //                         [SCALE]         | 2    | u8     | constant decimals 
    is_legacy: bool, //                                     | 2    | u8     | constant
    last_updated: u64, //                   [seconds]       | 3    | u32    |
    last_rate_accumulator: u256, //         [SCALE]         | 3    | u64    |
    last_full_utilization_rate: u256, //    [SCALE]         | 3    | u64    |
    fee_rate: u256, //                      [SCALE]         | 3    | u8     | percentage
}

fn assert_asset_config(asset_config: AssetConfig) {
    assert!(asset_config.scale <= pow_10(18), "scale-exceeded");
    assert!(asset_config.max_utilization <= SCALE, "max-utilization-exceeded");
    assert!(asset_config.last_rate_accumulator >= SCALE, "rate-accumulator-too-low");
    assert!(asset_config.fee_rate <= SCALE, "fee-rate-exceeded");
}

fn assert_asset_config_exists(asset_config: AssetConfig) {
    assert!(asset_config.last_rate_accumulator != 0, "asset-config-nonexistent");
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct LTVConfig {
    max_ltv: u64, // [SCALE]
}

#[inline(always)]
fn assert_ltv_config(ltv_config: LTVConfig) {
    assert!(ltv_config.max_ltv.into() <= SCALE, "invalid-ltv-config");
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
enum AmountType {
    #[default]
    Delta,
    Target,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
enum AmountDenomination {
    #[default]
    Native,
    Assets,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
struct Amount {
    amount_type: AmountType,
    denomination: AmountDenomination,
    value: i257,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
struct UnsignedAmount {
    amount_type: AmountType,
    denomination: AmountDenomination,
    value: u256,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
struct AssetPrice {
    value: u256,
    is_valid: bool,
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct AssetParams {
    asset: ContractAddress,
    floor: u256, // [SCALE]
    initial_rate_accumulator: u256, // [SCALE]
    initial_full_utilization_rate: u256, // [SCALE]
    max_utilization: u256, // [SCALE]
    is_legacy: bool,
    fee_rate: u256, // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct LTVParams {
    collateral_asset_index: usize,
    debt_asset_index: usize,
    max_ltv: u64, // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct DebtCapParams {
    collateral_asset_index: usize,
    debt_asset_index: usize,
    debt_cap: u256, // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct ModifyPositionParams {
    pool_id: felt252,
    collateral_asset: ContractAddress,
    debt_asset: ContractAddress,
    user: ContractAddress,
    collateral: Amount,
    debt: Amount,
    data: Span<felt252>
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct TransferPositionParams {
    pool_id: felt252,
    from_collateral_asset: ContractAddress,
    from_debt_asset: ContractAddress,
    to_collateral_asset: ContractAddress,
    to_debt_asset: ContractAddress,
    from_user: ContractAddress,
    to_user: ContractAddress,
    collateral: UnsignedAmount,
    debt: UnsignedAmount,
    from_data: Span<felt252>,
    to_data: Span<felt252>
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct LiquidatePositionParams {
    pool_id: felt252,
    collateral_asset: ContractAddress,
    debt_asset: ContractAddress,
    user: ContractAddress,
    receive_as_shares: bool,
    data: Span<felt252>
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct UpdatePositionResponse {
    collateral_delta: i257, // [asset scale]
    collateral_shares_delta: i257, // [SCALE]
    debt_delta: i257, // [asset scale]
    nominal_debt_delta: i257, // [SCALE]
    bad_debt: u256, // [asset scale]
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct Context {
    pool_id: felt252,
    extension: ContractAddress,
    collateral_asset: ContractAddress,
    debt_asset: ContractAddress,
    collateral_asset_config: AssetConfig,
    debt_asset_config: AssetConfig,
    collateral_asset_price: AssetPrice,
    debt_asset_price: AssetPrice,
    collateral_asset_fee_shares: u256,
    debt_asset_fee_shares: u256,
    max_ltv: u64,
    user: ContractAddress,
    position: Position
}
