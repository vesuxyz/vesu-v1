use vesu::{
    data_model::{Position, AssetConfig, assert_asset_config_exists}, math::{pow_10_or_0, log_10_or_0}, units::PERCENT
};

impl PositionPacking of starknet::StorePacking<Position, felt252> {
    fn pack(value: Position) -> felt252 {
        let collateral_shares: u128 = value.collateral_shares.try_into().expect('pack-collateral-shares');
        let nominal_debt: u128 = value.nominal_debt.try_into().expect('pack-nominal-debt');
        let nominal_debt = into_u123(nominal_debt, 'pack-nominal-debt-u123');
        collateral_shares.into() + nominal_debt * SHIFT_128
    }

    fn unpack(value: felt252) -> Position {
        let (nominal_debt, collateral_shares) = split_128(value.into());
        Position { collateral_shares: collateral_shares.into(), nominal_debt: nominal_debt.into() }
    }
}

impl AssetConfigPacking of starknet::StorePacking<AssetConfig, (felt252, felt252, felt252)> {
    fn pack(value: AssetConfig) -> (felt252, felt252, felt252) {
        // slot 1
        let total_collateral_shares: u128 = value
            .total_collateral_shares
            .try_into()
            .expect('pack-total-collateral-shares');
        let total_nominal_debt: u128 = value.total_nominal_debt.try_into().expect('pack-total-nominal-debt');
        let total_nominal_debt = into_u123(total_nominal_debt, 'pack-total-nominal-debt-u123');
        let slot1 = total_collateral_shares.into() + total_nominal_debt * SHIFT_128;

        // slot 2
        let reserve: u128 = value.reserve.try_into().expect('pack-reserve');
        let max_utilization: u8 = (value.max_utilization / PERCENT).try_into().expect('pack-max-utilization');
        let floor_decimals: u8 = log_10_or_0(value.floor);
        let scale_decimals: u8 = log_10_or_0(value.scale);
        let slot2 = reserve.into()
            + max_utilization.into() * SHIFT_128
            + floor_decimals.into() * SHIFT_128 * SHIFT_8
            + scale_decimals.into() * SHIFT_128 * SHIFT_8 * SHIFT_8
            + value.is_legacy.into() * SHIFT_128 * SHIFT_8 * SHIFT_8 * SHIFT_8;

        // slot 3
        let last_updated: u32 = value.last_updated.try_into().expect('pack-last-updated');
        let last_rate_accumulator: u64 = value.last_rate_accumulator.try_into().expect('pack-last-rate-accumulator');
        let last_full_utilization_rate: u64 = value
            .last_full_utilization_rate
            .try_into()
            .expect('pack-last-full-utilization-rate');
        let fee_rate: u8 = (value.fee_rate / PERCENT).try_into().expect('pack-fee-rate');
        let slot3 = last_updated.into()
            + last_rate_accumulator.into() * SHIFT_32
            + last_full_utilization_rate.into() * SHIFT_32 * SHIFT_64
            + fee_rate.into() * SHIFT_32 * SHIFT_64 * SHIFT_64;

        (slot1, slot2, slot3)
    }

    fn unpack(value: (felt252, felt252, felt252)) -> AssetConfig {
        let (slot1, slot2, slot3) = value;

        // slot 1
        let (total_nominal_debt, total_collateral_shares) = split_128(slot1.into());

        // slot 2
        let (rest, reserve) = split_128(slot2.into());
        let (rest, max_utilization) = split_8(rest.into());
        let (rest, floor_decimals) = split_8(rest);
        let (rest, scale_decimals) = split_8(rest);
        let (rest, is_legacy) = split_8(rest);
        assert!(rest == 0, "asset-config-slot2-excess-data");

        // slot 3
        let (rest, last_updated) = split_32(slot3.into());
        let (rest, last_rate_accumulator) = split_64(rest);
        let (rest, last_full_utilization_rate) = split_64(rest);
        let (rest, fee_rate) = split_8(rest);
        assert!(rest == 0, "asset-config-slot3-excess-data");

        AssetConfig {
            total_collateral_shares: total_collateral_shares.into(),
            total_nominal_debt: total_nominal_debt.into(),
            reserve: reserve.into(),
            max_utilization: max_utilization.into() * PERCENT,
            floor: pow_10_or_0(floor_decimals.into()),
            scale: pow_10_or_0(scale_decimals.into()),
            is_legacy: is_legacy != 0,
            last_updated: last_updated.into(),
            last_rate_accumulator: last_rate_accumulator.into(),
            last_full_utilization_rate: last_full_utilization_rate.into(),
            fee_rate: fee_rate.into() * PERCENT
        }
    }
}

fn assert_storable_asset_config(asset_config: AssetConfig) {
    assert_asset_config_exists(asset_config);
    let packed = AssetConfigPacking::pack(asset_config);
    let unpacked = AssetConfigPacking::unpack(packed);
    assert!(asset_config.max_utilization == unpacked.max_utilization, "max-utilization-precision-loss");
    assert!(asset_config.floor == unpacked.floor, "floor-precision-loss");
    assert!(asset_config.scale == unpacked.scale, "scale-precision-loss");
    assert!(asset_config.fee_rate == unpacked.fee_rate, "fee-rate-precision-loss");
}

const SHIFT_8: felt252 = 0x100;
const SHIFT_16: felt252 = 0x10000;
const SHIFT_32: felt252 = 0x100000000;
const SHIFT_64: felt252 = 0x10000000000000000;
const SHIFT_128: felt252 = 0x100000000000000000000000000000000;

fn split_8(value: u256) -> (u256, u8) {
    let shift = integer::u256_as_non_zero(SHIFT_8.into());
    let (rest, first) = integer::u256_safe_div_rem(value.into(), shift);
    (rest, first.try_into().unwrap())
}

fn split_16(value: u256) -> (u256, u16) {
    let shift = integer::u256_as_non_zero(SHIFT_16.into());
    let (rest, first) = integer::u256_safe_div_rem(value.into(), shift);
    (rest, first.try_into().unwrap())
}

fn split_32(value: u256) -> (u256, u32) {
    let shift = integer::u256_as_non_zero(SHIFT_32.into());
    let (rest, first) = integer::u256_safe_div_rem(value.into(), shift);
    (rest, first.try_into().unwrap())
}

fn split_64(value: u256) -> (u256, u64) {
    let shift = integer::u256_as_non_zero(SHIFT_64.into());
    let (rest, first) = integer::u256_safe_div_rem(value.into(), shift);
    (rest, first.try_into().unwrap())
}

fn split_128(value: u256) -> (u128, u128) {
    let shift = integer::u256_as_non_zero(SHIFT_128.into());
    let (rest, first) = integer::u256_safe_div_rem(value.into(), shift);
    (rest.try_into().unwrap(), first.try_into().unwrap())
}

const U123_BOUND: u128 = 0x8000000000000000000000000000000;

fn into_u123(value: u128, err: felt252) -> felt252 {
    assert(value < U123_BOUND, err);
    value.into()
}
