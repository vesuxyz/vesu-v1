use alexandria_math::i257::i257;
use starknet::ContractAddress;
use vesu::math::pow_10;
use vesu::units::SCALE;

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct Position {
    pub collateral_shares: u256, // packed as u128 [SCALE] 
    pub nominal_debt: u256 // packed as u123 [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct AssetConfig { //                                     | slot | packed | notes
    //                                                          | ---- | ------ | -----
    pub total_collateral_shares: u256, //       [SCALE]         | 1    | u128   |
    pub total_nominal_debt: u256, //            [SCALE]         | 1    | u123   |
    pub reserve: u256, //                       [asset scale]   | 2    | u128   |
    pub max_utilization: u256, //               [SCALE]         | 2    | u8     | constant percentage
    pub floor: u256, //                         [SCALE]         | 2    | u8     | constant decimals
    pub scale: u256, //                         [SCALE]         | 2    | u8     | constant decimals 
    pub is_legacy: bool, //                                     | 2    | u8     | constant
    pub last_updated: u64, //                   [seconds]       | 3    | u32    |
    pub last_rate_accumulator: u256, //         [SCALE]         | 3    | u64    |
    pub last_full_utilization_rate: u256, //    [SCALE]         | 3    | u64    |
    pub fee_rate: u256 //                      [SCALE]         | 3    | u8     | percentage
}

pub fn assert_asset_config(asset_config: AssetConfig) {
    assert!(asset_config.scale <= pow_10(18), "scale-exceeded");
    assert!(asset_config.max_utilization <= SCALE, "max-utilization-exceeded");
    assert!(asset_config.last_rate_accumulator >= SCALE, "rate-accumulator-too-low");
    assert!(asset_config.fee_rate <= SCALE, "fee-rate-exceeded");
}

pub fn assert_asset_config_exists(asset_config: AssetConfig) {
    assert!(asset_config.scale != 0, "asset-config-nonexistent");
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
pub struct LTVConfig {
    pub max_ltv: u64 // [SCALE]
}

pub fn assert_ltv_config(ltv_config: LTVConfig) {
    assert!(ltv_config.max_ltv.into() <= SCALE, "invalid-ltv-config");
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub enum AmountType {
    #[default]
    Delta,
    Target,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub enum AmountDenomination {
    #[default]
    Native,
    Assets,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub struct Amount {
    pub amount_type: AmountType,
    pub denomination: AmountDenomination,
    pub value: i257,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub struct UnsignedAmount {
    pub amount_type: AmountType,
    pub denomination: AmountDenomination,
    pub value: u256,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub struct AssetPrice {
    pub value: u256,
    pub is_valid: bool,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct AssetParams {
    pub asset: ContractAddress,
    pub floor: u256, // [SCALE]
    pub initial_rate_accumulator: u256, // [SCALE]
    pub initial_full_utilization_rate: u256, // [SCALE]
    pub max_utilization: u256, // [SCALE]
    pub is_legacy: bool,
    pub fee_rate: u256 // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct LTVParams {
    pub collateral_asset_index: usize,
    pub debt_asset_index: usize,
    pub max_ltv: u64 // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct DebtCapParams {
    pub collateral_asset_index: usize,
    pub debt_asset_index: usize,
    pub debt_cap: u256 // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct ModifyPositionParams {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub collateral: Amount,
    pub debt: Amount,
    pub data: Span<felt252>,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct TransferPositionParams {
    pub pool_id: felt252,
    pub from_collateral_asset: ContractAddress,
    pub from_debt_asset: ContractAddress,
    pub to_collateral_asset: ContractAddress,
    pub to_debt_asset: ContractAddress,
    pub from_user: ContractAddress,
    pub to_user: ContractAddress,
    pub collateral: UnsignedAmount,
    pub debt: UnsignedAmount,
    pub from_data: Span<felt252>,
    pub to_data: Span<felt252>,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct LiquidatePositionParams {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub receive_as_shares: bool,
    pub data: Span<felt252>,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct UpdatePositionResponse {
    pub collateral_delta: i257, // [asset scale]
    pub collateral_shares_delta: i257, // [SCALE]
    pub debt_delta: i257, // [asset scale]
    pub nominal_debt_delta: i257, // [SCALE]
    pub bad_debt: u256 // [asset scale]
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct Context {
    pub pool_id: felt252,
    pub extension: ContractAddress,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub collateral_asset_config: AssetConfig,
    pub debt_asset_config: AssetConfig,
    pub collateral_asset_price: AssetPrice,
    pub debt_asset_price: AssetPrice,
    pub collateral_asset_fee_shares: u256,
    pub debt_asset_fee_shares: u256,
    pub max_ltv: u64,
    pub user: ContractAddress,
    pub position: Position,
}
