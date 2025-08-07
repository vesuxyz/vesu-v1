use alexandria_math::i257::{I257Trait, i257};
use core::integer;
use core::num::traits::{WideMul, Zero};
use openzeppelin::utils::math::{Rounding, u256_mul_div};
use starknet::get_block_timestamp;
use vesu::data_model::{Amount, AmountDenomination, AmountType, AssetConfig, Context, Position};
use vesu::math::pow_scale;
use vesu::units::SCALE;

/// Calculates the nominal debt for a given amount of debt, the current rate accumulator and debt asset's scale
/// # Arguments
/// * `debt` - debt [asset scale]
/// * `rate_accumulator` - rate accumulator [SCALE]
/// * `asset_scale` - asset scale [asset scale]
/// # Returns
/// * `nominal_debt` - computed nominal debt [SCALE]
pub fn calculate_nominal_debt(debt: u256, rate_accumulator: u256, asset_scale: u256, round_up: bool) -> u256 {
    if rate_accumulator == 0 {
        return 0;
    }
    let (nominal_debt, remainder) = integer::u512_safe_div_rem_by_u256(
        WideMul::<u256>::wide_mul(debt * SCALE, SCALE), (rate_accumulator * asset_scale).try_into().unwrap(),
    );
    assert!(nominal_debt.limb2 == 0 && nominal_debt.limb3 == 0, "nominal-debt-overflow");
    let mut nominal_debt = u256 { low: nominal_debt.limb0, high: nominal_debt.limb1 };
    if (remainder != 0 && round_up) {
        nominal_debt + 1
    } else {
        nominal_debt
    }
}

/// Calculates the debt for a given amount of nominal debt, the current rate accumulator and debt asset's scale
/// # Arguments
/// * `nominal_debt` - nominal debt [SCALE]
/// * `rate_accumulator` - rate accumulator [SCALE]
/// * `asset_scale` - asset scale [asset scale]
/// # Returns
/// * `debt` - computed debt [asset scale]
pub fn calculate_debt(nominal_debt: u256, rate_accumulator: u256, asset_scale: u256, round_up: bool) -> u256 {
    if rate_accumulator == 0 {
        return 0;
    }
    let (debt, remainder) = integer::u512_safe_div_rem_by_u256(
        WideMul::<u256>::wide_mul(nominal_debt * rate_accumulator, asset_scale), (SCALE * SCALE).try_into().unwrap(),
    );
    assert!(debt.limb2 == 0 && debt.limb3 == 0, "debt-overflow");
    let mut debt = u256 { low: debt.limb0, high: debt.limb1 };
    if (remainder != 0 && round_up) {
        debt + 1
    } else {
        debt
    }
}

/// Calculates the number of collateral shares (that would be e.g. minted) for a given amount of collateral assets
/// # Arguments
/// * `collateral` - collateral asset amount [asset scale]
/// * `asset_config` - collateral asset config
/// # Returns
/// * `collateral_shares` - collateral shares amount [SCALE]
pub fn calculate_collateral_shares(collateral: u256, asset_config: AssetConfig, round_up: bool) -> u256 {
    let AssetConfig {
        reserve, total_nominal_debt, total_collateral_shares, last_rate_accumulator, scale, ..,
    } = asset_config;
    let total_assets = reserve + calculate_debt(total_nominal_debt, last_rate_accumulator, scale, !round_up);
    if total_assets == 0 || total_collateral_shares == 0 {
        if scale == 0 {
            return 0;
        }
        return u256_mul_div(collateral, SCALE, scale, if round_up {
            Rounding::Ceil
        } else {
            Rounding::Floor
        });
    }
    let (collateral_shares, remainder) = integer::u512_safe_div_rem_by_u256(
        WideMul::<u256>::wide_mul(collateral, total_collateral_shares), total_assets.try_into().unwrap(),
    );
    assert!(collateral_shares.limb2 == 0 && collateral_shares.limb3 == 0, "collateral-shares-overflow");
    let mut collateral_shares = u256 { low: collateral_shares.limb0, high: collateral_shares.limb1 };
    if (remainder != 0 && round_up) {
        collateral_shares + 1
    } else {
        collateral_shares
    }
}

/// Calculates the amount of collateral assets (that can e.g. be redeemed)  for a given amount of collateral shares
/// # Arguments
/// * `collateral_shares` - collateral shares amount [SCALE]
/// * `asset_config` - collateral asset config
/// # Returns
/// * `collateral` - collateral asset amount [asset scale]
pub fn calculate_collateral(collateral_shares: u256, asset_config: AssetConfig, round_up: bool) -> u256 {
    let AssetConfig {
        reserve, total_nominal_debt, total_collateral_shares, last_rate_accumulator, scale, ..,
    } = asset_config;
    if total_collateral_shares == 0 {
        return u256_mul_div(collateral_shares, scale, SCALE, if round_up {
            Rounding::Ceil
        } else {
            Rounding::Floor
        });
    }
    let total_assets = reserve + calculate_debt(total_nominal_debt, last_rate_accumulator, scale, round_up);
    let (collateral, remainder) = integer::u512_safe_div_rem_by_u256(
        WideMul::<u256>::wide_mul(collateral_shares * total_assets, SCALE),
        (total_collateral_shares * SCALE).try_into().unwrap(),
    );
    assert!(collateral.limb2 == 0 && collateral.limb3 == 0, "collateral-overflow");
    let mut collateral = u256 { low: collateral.limb0, high: collateral.limb1 };
    if (remainder != 0 && round_up) {
        collateral + 1
    } else {
        collateral
    }
}

/// Calculates the current utilization (for an asset) given its total reserve and the total debt outstanding
/// # Arguments
/// * `total_reserve` - amount of assets in reserve [asset scale]
/// * `total_debt` - amount of debt outstanding [asset scale]
/// # Returns
/// * `utilization` - utilization [SCALE]
pub fn calculate_utilization(total_reserve: u256, total_debt: u256) -> u256 {
    let total_assets = total_reserve + total_debt;
    if total_assets == 0 {
        0
    } else {
        u256_mul_div(total_debt, SCALE, total_assets, Rounding::Floor)
    }
}

/// Calculates the current (using the current block's timestamp) rate accumulator
/// # Arguments
/// * `last_updated` - timestamp when the rate accumulator was last updated [seconds]
/// * `last_rate_accumulator` - last rate accumulator [SCALE]
/// * `interest_rate` - interest rate [SCALE]
/// # Returns
/// * `rate_accumulator` - new computed rate accumulator [SCALE]
pub fn calculate_rate_accumulator(last_updated: u64, last_rate_accumulator: u256, interest_rate: u256) -> u256 {
    let time_delta = if last_updated >= get_block_timestamp() {
        0
    } else {
        get_block_timestamp() - last_updated
    };
    u256_mul_div(
        last_rate_accumulator, pow_scale(SCALE + interest_rate, time_delta.into(), false), SCALE, Rounding::Floor,
    )
}

/// Calculate fee (collateral) shares that are minted to the fee recipient of the pool
/// # Arguments
/// * `asset_config` - asset config
/// * `new_rate_accumulator` - new rate accumulator [SCALE]
/// # Returns
/// * `fee_shares` - fee shares amount [SCALE]
pub fn calculate_fee_shares(asset_config: AssetConfig, new_rate_accumulator: u256) -> u256 {
    let rate_accumulator_delta = if new_rate_accumulator > asset_config.last_rate_accumulator {
        new_rate_accumulator - asset_config.last_rate_accumulator
    } else {
        0
    };

    let AssetConfig {
        reserve, total_nominal_debt, total_collateral_shares, last_rate_accumulator, scale, fee_rate, ..,
    } = asset_config;

    if fee_rate == 0 {
        return 0;
    }

    let accrued_interest = calculate_debt(
        asset_config.total_nominal_debt, rate_accumulator_delta, asset_config.scale, false,
    );
    let fee = u256_mul_div(accrued_interest, fee_rate, SCALE, Rounding::Floor);
    let total_assets = reserve + calculate_debt(total_nominal_debt, last_rate_accumulator, scale, false);

    if total_assets == 0 {
        return 0;
    }

    u256_mul_div(fee, total_collateral_shares, total_assets + (accrued_interest - fee), Rounding::Floor)
}

/// Deconstructs the collateral amount into collateral delta, collateral shares delta and it's sign
/// # Arguments
/// * `collateral` - collateral amount
/// * `position` - position state
/// * `asset_config` - collateral asset config
/// # Returns
/// * `collateral_delta` - signed collateral delta [asset scale]
/// * `collateral_shares_delta` - signed collateral shares delta [SCALE]
pub fn deconstruct_collateral_amount(
    collateral: Amount, position: Position, asset_config: AssetConfig,
) -> (i257, i257) {
    if collateral.amount_type == AmountType::Delta {
        if collateral.denomination == AmountDenomination::Native {
            let collateral_shares_delta = collateral.value;
            // positive -> round up, negative -> round down
            let delta = calculate_collateral(
                collateral_shares_delta.abs(), asset_config, !collateral_shares_delta.is_negative(),
            );
            (I257Trait::new(delta, collateral_shares_delta.is_negative()), collateral_shares_delta)
        } else {
            let collateral_delta = collateral.value;
            // positive -> round down, negative -> round up
            let collateral_shares_delta = calculate_collateral_shares(
                collateral_delta.abs(), asset_config, collateral_delta.is_negative(),
            );
            (collateral_delta, I257Trait::new(collateral_shares_delta, collateral_delta.is_negative()))
        }
    } else {
        assert!(!collateral.value.is_negative(), "collateral-target-negative");
        if collateral.denomination == AmountDenomination::Native || collateral.value.abs() == 0 {
            let collateral_shares_target = collateral.value.abs();
            if position.collateral_shares >= collateral_shares_target {
                // negative -> round down
                let delta = calculate_collateral(
                    position.collateral_shares - collateral_shares_target, asset_config, false,
                );
                (
                    I257Trait::new(delta, true),
                    I257Trait::new((position.collateral_shares - collateral_shares_target), true),
                )
            } else {
                // positive -> round up
                let delta = calculate_collateral(
                    collateral_shares_target - position.collateral_shares, asset_config, true,
                );
                (
                    I257Trait::new(delta, false),
                    I257Trait::new((collateral_shares_target - position.collateral_shares), false),
                )
            }
        } else {
            let collateral_target = collateral.value.abs();
            // round down
            let position_collateral = calculate_collateral(position.collateral_shares, asset_config, false);
            if position_collateral >= collateral_target {
                // derive collateral shares from collateral amount, since user provided collateral amount should not be
                // adjusted negative -> round up
                let shares_delta = calculate_collateral_shares(
                    position_collateral - collateral_target, asset_config, true,
                );
                (I257Trait::new((position_collateral - collateral_target), true), I257Trait::new(shares_delta, true))
            } else {
                // derive collateral shares from collateral amount, since user provided collateral amount should not be
                // adjusted positive -> round down
                let shares_delta = calculate_collateral_shares(
                    collateral_target - position_collateral, asset_config, false,
                );
                (I257Trait::new((collateral_target - position_collateral), false), I257Trait::new(shares_delta, false))
            }
        }
    }
}

/// Deconstructs the debt amount into debt delta, nominal debt delta and it's sign
/// # Arguments
/// * `debt` - debt amount
/// * `position` - position state
/// * `rate_accumulator` - rate accumulator [SCALE]
/// * `asset_scale` - asset scale [asset scale]
/// # Returns
/// * `debt_delta` - signed debt delta [asset scale]
/// * `nominal_debt_delta` - signed nominal debt delta [SCALE]
pub fn deconstruct_debt_amount(
    debt: Amount, position: Position, rate_accumulator: u256, asset_scale: u256,
) -> (i257, i257) {
    if debt.amount_type == AmountType::Delta {
        return if debt.denomination == AmountDenomination::Native {
            let nominal_debt_delta = debt.value;
            // positive -> round down, negative -> round up
            let debt_delta = calculate_debt(
                nominal_debt_delta.abs(), rate_accumulator, asset_scale, nominal_debt_delta.is_negative(),
            );
            (I257Trait::new(debt_delta, nominal_debt_delta.is_negative()), nominal_debt_delta)
        } else {
            let debt_delta = debt.value;
            // positive -> round up, negative -> round down
            let nominal_debt_delta = calculate_nominal_debt(
                debt_delta.abs(), rate_accumulator, asset_scale, !debt_delta.is_negative(),
            );
            (debt_delta, I257Trait::new(nominal_debt_delta, debt_delta.is_negative()))
        };
    } else {
        assert!(!debt.value.is_negative(), "debt-target-negative");
        if debt.denomination == AmountDenomination::Native || debt.value.abs() == 0 {
            let nominal_debt_target = debt.value;
            if position.nominal_debt >= nominal_debt_target.abs() {
                // negative -> round up
                let debt_delta = calculate_debt(
                    position.nominal_debt - nominal_debt_target.abs(), rate_accumulator, asset_scale, true,
                );
                let nominal_debt_delta = position.nominal_debt - nominal_debt_target.abs();
                (I257Trait::new(debt_delta, true), I257Trait::new(nominal_debt_delta, true))
            } else {
                // positive -> round down
                let debt_delta = calculate_debt(
                    nominal_debt_target.abs() - position.nominal_debt, rate_accumulator, asset_scale, false,
                );
                let nominal_debt_delta = nominal_debt_target.abs() - position.nominal_debt;
                (I257Trait::new(debt_delta, false), I257Trait::new(nominal_debt_delta, false))
            }
        } else {
            let debt_target = debt.value;
            // round down
            let position_debt = calculate_debt(position.nominal_debt, rate_accumulator, asset_scale, false);
            if position_debt >= debt_target.abs() {
                // derive nominal debt from debt amount, since user provided debt amount should not be adjusted
                // negative -> round down
                let nominal_delta = calculate_nominal_debt(
                    position_debt - debt_target.abs(), rate_accumulator, asset_scale, false,
                );
                let debt_delta = position_debt - debt_target.abs();
                (I257Trait::new(debt_delta, true), I257Trait::new(nominal_delta, true))
            } else {
                // derive nominal debt from debt amount, since user provided debt amount should not be adjusted
                // positive -> round up
                let nominal_delta = calculate_nominal_debt(
                    debt_target.abs() - position_debt, rate_accumulator, asset_scale, true,
                );
                let debt_delta = debt_target.abs() - position_debt;
                (I257Trait::new(debt_delta, false), I257Trait::new(nominal_delta, false))
            }
        }
    }
}

/// Checks that the collateralization of a position is not above the max. loan-to-value ratio.
/// Note that if `max_ltv_ratio` and `debt_value` is 0, then the position is considered collateralized.
/// # Arguments
/// * `collateral_value` - usd value of the collateral [SCALE]
/// * `debt_value` - usd value of the debt [SCALE]
/// * `max_ltv_ratio` - max loan to value ratio [SCALE]
/// # Returns
/// * `is_collateralized` - true if the position is collateralized
pub fn is_collateralized(collateral_value: u256, debt_value: u256, max_ltv_ratio: u256) -> bool {
    collateral_value * max_ltv_ratio >= debt_value * SCALE
}

/// Calculates the collateral and debt value of a position
/// # Arguments
/// * `context` - Contextual state of the user (position owner)
/// * `position` - Position [SCALE]
/// # Returns
/// * `collateral` - collateral amount [asset scale]
/// * `collateral_value` - collateral value [SCALE]
/// * `debt` - debt amount [asset scale]
/// * `debt_value` - debt value [SCALE]
pub fn calculate_collateral_and_debt_value(context: Context, position: Position) -> (u256, u256, u256, u256) {
    let Context { collateral_asset_config, debt_asset_config, .. } = context;

    let collateral = calculate_collateral(position.collateral_shares, collateral_asset_config, false);
    let debt = calculate_debt(
        position.nominal_debt, debt_asset_config.last_rate_accumulator, debt_asset_config.scale, true,
    );

    let collateral_value = if collateral_asset_config.scale == 0 {
        0
    } else {
        u256_mul_div(collateral, context.collateral_asset_price.value, collateral_asset_config.scale, Rounding::Floor)
    };
    let debt_value = if debt_asset_config.scale == 0 {
        0
    } else {
        u256_mul_div(debt, context.debt_asset_price.value, debt_asset_config.scale, Rounding::Ceil)
    };

    (collateral, collateral_value, debt, debt_value)
}

/// Applies the collateral and or debt (incl. bad debt) balance updates of a position to the Context
/// # Arguments
/// * `context` - Contextual state of the user (position owner)
/// * `collateral` - collateral amount (delta, target)
/// * `debt` - debt amount (delta, target)
/// * `bad_debt` - accrued bad debt amount
/// # Returns
/// * `collateral_delta` - collateral delta [asset scale]
/// * `collateral_shares_delta` - collateral shares delta [SCALE]
/// * `debt_delta` - debt delta [asset scale]
/// * `nominal_debt_delta` - nominal debt delta [SCALE]
pub fn apply_position_update_to_context(
    ref context: Context, collateral: Amount, debt: Amount, bad_debt: u256,
) -> (i257, i257, i257, i257) {
    let (mut collateral_delta, mut collateral_shares_delta) = deconstruct_collateral_amount(
        collateral, context.position, context.collateral_asset_config,
    );

    // update the collateral balances
    if collateral_shares_delta > Zero::zero() {
        context.position.collateral_shares += collateral_shares_delta.abs();
        context.collateral_asset_config.total_collateral_shares += collateral_shares_delta.abs();
        context.collateral_asset_config.reserve += collateral_delta.abs();
    } else if collateral_shares_delta < Zero::zero() {
        // limit the collateral shares delta to the position's collateral shares
        if collateral_shares_delta.abs() > context.position.collateral_shares {
            collateral_shares_delta =
                I257Trait::new(context.position.collateral_shares, collateral_shares_delta.is_negative());
            collateral_delta =
                I257Trait::new(
                    calculate_collateral(collateral_shares_delta.abs(), context.collateral_asset_config, false),
                    collateral_delta.is_negative(),
                );
        }
        context.position.collateral_shares -= collateral_shares_delta.abs();
        context.collateral_asset_config.total_collateral_shares -= collateral_shares_delta.abs();
        context.collateral_asset_config.reserve -= collateral_delta.abs();
    }

    // deconstruct the debt amount
    let (mut debt_delta, mut nominal_debt_delta) = deconstruct_debt_amount(
        debt, context.position, context.debt_asset_config.last_rate_accumulator, context.debt_asset_config.scale,
    );

    // update the debt balances
    if nominal_debt_delta > Zero::zero() {
        context.position.nominal_debt += nominal_debt_delta.abs();
        context.debt_asset_config.total_nominal_debt += nominal_debt_delta.abs();
        context.debt_asset_config.reserve -= debt_delta.abs();
    } else if nominal_debt_delta < Zero::zero() {
        // limit the nominal debt delta to the position's nominal debt
        if nominal_debt_delta.abs() > context.position.nominal_debt {
            nominal_debt_delta = I257Trait::new(context.position.nominal_debt, nominal_debt_delta.is_negative());
            debt_delta =
                I257Trait::new(
                    calculate_debt(
                        nominal_debt_delta.abs(),
                        context.debt_asset_config.last_rate_accumulator,
                        context.debt_asset_config.scale,
                        true,
                    ),
                    debt_delta.is_negative(),
                );
        }
        context.position.nominal_debt -= nominal_debt_delta.abs();
        context.debt_asset_config.total_nominal_debt -= nominal_debt_delta.abs();
        context.debt_asset_config.reserve += debt_delta.abs() - bad_debt; // bad debt is not paid back
    }

    (collateral_delta, collateral_shares_delta, debt_delta, nominal_debt_delta)
}
