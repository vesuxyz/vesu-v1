use alexandria_math::i257::{i257, i257_new, U256IntoI257};
use starknet::get_block_timestamp;
use vesu::{
    math::{pow_scale}, units::SCALE,
    data_model::{AmountType, AmountDenomination, Amount, Position, AssetConfig, Context},
};

#[inline(always)]
/// Safe division of two u256 numbers
/// # Arguments
/// * `numerator` - numerator
/// * `denominator` - denominator
/// * `round_up` - round up the result
/// # Returns
/// * `quotient` - quotient
fn safe_div(numerator: u256, denominator: u256, round_up: bool) -> u256 {
    let (quotient, remainder) = integer::u256_safe_div_rem(numerator, integer::u256_as_non_zero(denominator));
    if remainder == 0 || !round_up {
        return quotient;
    } else {
        quotient + 1
    }
}

/// Calculates the nominal debt for a given amount of debt, the current rate accumulator and debt asset's scale
/// # Arguments
/// * `debt` - debt [asset scale]
/// * `rate_accumulator` - rate accumulator [SCALE]
/// * `asset_scale` - asset scale [asset scale]
/// # Returns
/// * `nominal_debt` - computed nominal debt [SCALE]
fn calculate_nominal_debt(debt: u256, rate_accumulator: u256, asset_scale: u256, round_up: bool) -> u256 {
    if rate_accumulator == 0 {
        return 0;
    }
    let rate_accumulator: NonZero<u256> = rate_accumulator.try_into().unwrap();
    let scaled_debt = integer::u256_wide_mul(debt * SCALE, SCALE);
    let (nominal_debt, remainder) = integer::u512_safe_div_rem_by_u256(scaled_debt, rate_accumulator);
    assert!(nominal_debt.limb2 == 0 && nominal_debt.limb3 == 0, "nominal-debt-overflow");
    let mut nominal_debt = u256 { low: nominal_debt.limb0, high: nominal_debt.limb1 };
    nominal_debt = if (remainder != 0 && round_up) {
        nominal_debt + 1
    } else {
        nominal_debt
    };
    safe_div(nominal_debt, asset_scale, round_up)
}

/// Calculates the debt for a given amount of nominal debt, the current rate accumulator and debt asset's scale
/// # Arguments
/// * `nominal_debt` - nominal debt [SCALE]
/// * `rate_accumulator` - rate accumulator [SCALE]
/// * `asset_scale` - asset scale [asset scale]
/// # Returns
/// * `debt` - computed debt [asset scale]
fn calculate_debt(nominal_debt: u256, rate_accumulator: u256, asset_scale: u256, round_up: bool) -> u256 {
    if rate_accumulator == 0 {
        return 0;
    }
    let scaled_nominal_debt = integer::u256_wide_mul(nominal_debt * rate_accumulator, asset_scale);
    let (debt, remainder) = integer::u512_safe_div_rem_by_u256(scaled_nominal_debt, SCALE.try_into().unwrap());
    assert!(debt.limb2 == 0 && debt.limb3 == 0, "debt-overflow");
    let mut debt = u256 { low: debt.limb0, high: debt.limb1 };
    debt = if (remainder != 0 && round_up) {
        debt + 1
    } else {
        debt
    };
    safe_div(debt, SCALE, round_up)
}

/// Calculates the number of collateral shares (that would be e.g. minted) for a given amount of collateral assets
/// # Arguments
/// * `collateral` - collateral asset amount [asset scale]
/// * `asset_config` - collateral asset config
/// # Returns
/// * `collateral_shares` - collateral shares amount [SCALE]
fn calculate_collateral_shares(collateral: u256, asset_config: AssetConfig, round_up: bool) -> u256 {
    let AssetConfig { reserve, total_nominal_debt, total_collateral_shares, last_rate_accumulator, scale, .. } =
        asset_config;
    let total_debt = calculate_debt(total_nominal_debt, last_rate_accumulator, scale, !round_up);
    let total_assets = reserve + total_debt;
    if total_assets == 0 || total_collateral_shares == 0 {
        if scale == 0 {
            return 0;
        }
        return safe_div(collateral * SCALE, scale, round_up);
    }
    let scaled_collateral_mul = integer::u256_wide_mul(collateral * total_collateral_shares, SCALE);
    let total_assets: NonZero<u256> = total_assets.try_into().unwrap();
    let (scaled_collateral_shares, remainder) = integer::u512_safe_div_rem_by_u256(scaled_collateral_mul, total_assets);
    assert!(scaled_collateral_shares.limb2 == 0 && scaled_collateral_shares.limb3 == 0, "collateral-shares-overflow");
    let mut scaled_collateral_shares = u256 {
        low: scaled_collateral_shares.limb0, high: scaled_collateral_shares.limb1
    };
    scaled_collateral_shares =
        if (remainder != 0 && round_up) {
            scaled_collateral_shares + 1
        } else {
            scaled_collateral_shares
        };
    safe_div(scaled_collateral_shares, SCALE, round_up)
}

/// Calculates the amount of collateral assets (that can e.g. be redeemed)  for a given amount of collateral shares
/// # Arguments
/// * `collateral_shares` - collateral shares amount [SCALE]
/// * `asset_config` - collateral asset config
/// # Returns
/// * `collateral` - collateral asset amount [asset scale]
fn calculate_collateral(collateral_shares: u256, asset_config: AssetConfig, round_up: bool) -> u256 {
    let AssetConfig { reserve, total_nominal_debt, total_collateral_shares, last_rate_accumulator, scale, .. } =
        asset_config;
    let total_debt = calculate_debt(total_nominal_debt, last_rate_accumulator, scale, round_up);
    if total_collateral_shares == 0 {
        return safe_div(collateral_shares * scale, SCALE, round_up);
    }
    let total_assets = reserve + total_debt;

    let scaled_collateral_mul = integer::u256_wide_mul(collateral_shares * total_assets, SCALE);
    let total_collateral_shares: NonZero<u256> = total_collateral_shares.try_into().unwrap();
    let (scaled_collateral, remainder) = integer::u512_safe_div_rem_by_u256(
        scaled_collateral_mul, total_collateral_shares
    );
    assert!(scaled_collateral.limb2 == 0 && scaled_collateral.limb3 == 0, "collateral-overflow");
    let mut scaled_collateral = u256 { low: scaled_collateral.limb0, high: scaled_collateral.limb1 };
    scaled_collateral = if (remainder != 0 && round_up) {
        scaled_collateral + 1
    } else {
        scaled_collateral
    };
    safe_div(scaled_collateral, SCALE, round_up)
}

/// Calculates the current utilization (for an asset) given its total reserve and the total debt outstanding
/// # Arguments
/// * `total_reserve` - amount of assets in reserve [asset scale]
/// * `total_debt` - amount of debt outstanding [asset scale]
/// # Returns
/// * `utilization` - utilization [SCALE]
fn calculate_utilization(total_reserve: u256, total_debt: u256) -> u256 {
    let total_assets = total_reserve + total_debt;
    if total_assets == 0 {
        0
    } else {
        (total_debt * SCALE) / total_assets
    }
}

/// Calculates the current (using the current block's timestamp) rate accumulator
/// # Arguments
/// * `last_updated` - timestamp when the rate accumulator was last updated [seconds]
/// * `last_rate_accumulator` - last rate accumulator [SCALE]
/// * `interest_rate` - interest rate [SCALE]
/// # Returns
/// * `rate_accumulator` - new computed rate accumulator [SCALE]
fn calculate_rate_accumulator(last_updated: u64, last_rate_accumulator: u256, interest_rate: u256) -> u256 {
    let time_delta = if last_updated >= get_block_timestamp() {
        0
    } else {
        get_block_timestamp() - last_updated
    };
    last_rate_accumulator * pow_scale(SCALE + interest_rate, time_delta.into(), false) / SCALE
}

/// Calculate fee (collateral) shares that are minted to the fee recipient of the pool
/// # Arguments
/// * `asset_config` - asset config
/// * `new_rate_accumulator` - new rate accumulator [SCALE]
/// # Returns
/// * `fee_shares` - fee shares amount [SCALE]
fn calculate_fee_shares(asset_config: AssetConfig, new_rate_accumulator: u256) -> u256 {
    let rate_accumulator_delta = if new_rate_accumulator > asset_config.last_rate_accumulator {
        new_rate_accumulator - asset_config.last_rate_accumulator
    } else {
        0
    };
    calculate_collateral_shares(
        calculate_debt(asset_config.total_nominal_debt, rate_accumulator_delta, asset_config.scale, false),
        asset_config,
        false
    )
        * asset_config.fee_rate
        / SCALE
}

/// Deconstructs the collateral amount into collateral delta, collateral shares delta and it's sign
/// # Arguments
/// * `collateral` - collateral amount
/// * `position` - position state
/// * `asset_config` - collateral asset config
/// # Returns
/// * `collateral_delta` - signed collateral delta [asset scale]
/// * `collateral_shares_delta` - signed collateral shares delta [SCALE]
fn deconstruct_collateral_amount(collateral: Amount, position: Position, asset_config: AssetConfig) -> (i257, i257) {
    if collateral.amount_type == AmountType::Delta {
        if collateral.denomination == AmountDenomination::Native {
            let collateral_shares_delta = collateral.value;
            // positive -> round up, negative -> round down
            let delta = calculate_collateral(
                collateral_shares_delta.abs, asset_config, !collateral_shares_delta.is_negative
            );
            (i257_new(delta, collateral_shares_delta.is_negative), collateral_shares_delta)
        } else {
            let collateral_delta = collateral.value;
            // positive -> round down, negative -> round up
            let collateral_shares_delta = calculate_collateral_shares(
                collateral_delta.abs, asset_config, collateral_delta.is_negative
            );
            (collateral_delta, i257_new(collateral_shares_delta, collateral_delta.is_negative))
        }
    } else {
        assert!(!collateral.value.is_negative, "collateral-target-negative");
        if collateral.denomination == AmountDenomination::Native || collateral.value.abs == 0 {
            let collateral_shares_target = collateral.value.abs;
            if position.collateral_shares >= collateral_shares_target {
                // negative -> round down
                let delta = calculate_collateral(
                    position.collateral_shares - collateral_shares_target, asset_config, false
                );
                (-delta.into(), -(position.collateral_shares - collateral_shares_target).into())
            } else {
                // positive -> round up
                let delta = calculate_collateral(
                    collateral_shares_target - position.collateral_shares, asset_config, true
                );
                (delta.into(), (collateral_shares_target - position.collateral_shares).into())
            }
        } else {
            let collateral_target = collateral.value.abs;
            // round down
            let position_collateral = calculate_collateral(position.collateral_shares, asset_config, false);
            if position_collateral >= collateral_target {
                // derive collateral shares from collateral amount, since user provided collateral amount should not be adjusted
                // negative -> round up
                let shares_delta = calculate_collateral_shares(
                    position_collateral - collateral_target, asset_config, true
                );
                (-(position_collateral - collateral_target).into(), -shares_delta.into())
            } else {
                // derive collateral shares from collateral amount, since user provided collateral amount should not be adjusted
                // positive -> round down
                let shares_delta = calculate_collateral_shares(
                    collateral_target - position_collateral, asset_config, false
                );
                ((collateral_target - position_collateral).into(), shares_delta.into())
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
fn deconstruct_debt_amount(
    debt: Amount, position: Position, rate_accumulator: u256, asset_scale: u256
) -> (i257, i257) {
    if debt.amount_type == AmountType::Delta {
        return if debt.denomination == AmountDenomination::Native {
            let nominal_debt_delta = debt.value;
            // positive -> round down, negative -> round up
            let debt_delta = calculate_debt(
                nominal_debt_delta.abs, rate_accumulator, asset_scale, nominal_debt_delta.is_negative
            );
            (i257_new(debt_delta, nominal_debt_delta.is_negative), nominal_debt_delta)
        } else {
            let debt_delta = debt.value;
            // positive -> round up, negative -> round down
            let nominal_debt_delta = calculate_nominal_debt(
                debt_delta.abs, rate_accumulator, asset_scale, !debt_delta.is_negative
            );
            (debt_delta, i257_new(nominal_debt_delta, debt_delta.is_negative))
        };
    } else {
        assert!(!debt.value.is_negative, "debt-target-negative");
        if debt.denomination == AmountDenomination::Native || debt.value.abs == 0 {
            let nominal_debt_target = debt.value;
            if position.nominal_debt >= nominal_debt_target.abs {
                // negative -> round up
                let debt_delta = calculate_debt(
                    position.nominal_debt - nominal_debt_target.abs, rate_accumulator, asset_scale, true
                );
                let nominal_debt_delta = position.nominal_debt - nominal_debt_target.abs;
                (-debt_delta.into(), -nominal_debt_delta.into())
            } else {
                // positive -> round down
                let debt_delta = calculate_debt(
                    nominal_debt_target.abs - position.nominal_debt, rate_accumulator, asset_scale, false
                );
                let nominal_debt_delta = nominal_debt_target.abs - position.nominal_debt;
                (debt_delta.into(), nominal_debt_delta.into())
            }
        } else {
            let debt_target = debt.value;
            // round down
            let position_debt = calculate_debt(position.nominal_debt, rate_accumulator, asset_scale, false);
            if position_debt >= debt_target.abs {
                // derive nominal debt from debt amount, since user provided debt amount should not be adjusted
                // negative -> round down
                let nominal_delta = calculate_nominal_debt(
                    position_debt - debt_target.abs, rate_accumulator, asset_scale, false
                );
                let debt_delta = position_debt - debt_target.abs;
                (-debt_delta.into(), -nominal_delta.into())
            } else {
                // derive nominal debt from debt amount, since user provided debt amount should not be adjusted
                // positive -> round up
                let nominal_delta = calculate_nominal_debt(
                    debt_target.abs - position_debt, rate_accumulator, asset_scale, true
                );
                let debt_delta = debt_target.abs - position_debt;
                (debt_delta.into(), nominal_delta.into())
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
fn is_collateralized(collateral_value: u256, debt_value: u256, max_ltv_ratio: u256) -> bool {
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
fn calculate_collateral_and_debt_value(context: Context, position: Position) -> (u256, u256, u256, u256) {
    let Context { collateral_asset_config, debt_asset_config, .. } = context;

    let collateral = calculate_collateral(position.collateral_shares, collateral_asset_config, false);
    let debt = calculate_debt(
        position.nominal_debt, debt_asset_config.last_rate_accumulator, debt_asset_config.scale, true
    );

    let collateral_value = if collateral_asset_config.scale == 0 {
        0
    } else {
        collateral * context.collateral_asset_price.value / collateral_asset_config.scale
    };
    let debt_value = if debt_asset_config.scale == 0 {
        0
    } else {
        debt * context.debt_asset_price.value / debt_asset_config.scale
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
fn apply_position_update_to_context(
    ref context: Context, collateral: Amount, debt: Amount, bad_debt: u256
) -> (i257, i257, i257, i257) {
    let (mut collateral_delta, mut collateral_shares_delta) = deconstruct_collateral_amount(
        collateral, context.position, context.collateral_asset_config,
    );

    // update the collateral balances
    if collateral_shares_delta > Zeroable::zero() {
        context.position.collateral_shares += collateral_shares_delta.abs;
        context.collateral_asset_config.total_collateral_shares += collateral_shares_delta.abs;
        context.collateral_asset_config.reserve += collateral_delta.abs;
    } else if collateral_shares_delta < Zeroable::zero() {
        if collateral_shares_delta.abs > context.position.collateral_shares {
            collateral_shares_delta = i257_new(context.position.collateral_shares, collateral_shares_delta.is_negative);
            collateral_delta =
                i257_new(
                    calculate_collateral(collateral_shares_delta.abs, context.collateral_asset_config, false),
                    collateral_delta.is_negative
                );
        }
        context.position.collateral_shares -= collateral_shares_delta.abs;
        context.collateral_asset_config.total_collateral_shares -= collateral_shares_delta.abs;
        context.collateral_asset_config.reserve -= collateral_delta.abs;
    }

    // deconstruct the debt amount
    let (mut debt_delta, mut nominal_debt_delta) = deconstruct_debt_amount(
        debt, context.position, context.debt_asset_config.last_rate_accumulator, context.debt_asset_config.scale
    );

    // update the debt balances
    if nominal_debt_delta > Zeroable::zero() {
        context.position.nominal_debt += nominal_debt_delta.abs;
        context.debt_asset_config.total_nominal_debt += nominal_debt_delta.abs;
        context.debt_asset_config.reserve -= debt_delta.abs;
    } else if nominal_debt_delta < Zeroable::zero() {
        if nominal_debt_delta.abs > context.position.nominal_debt {
            nominal_debt_delta = i257_new(context.position.nominal_debt, nominal_debt_delta.is_negative);
            debt_delta =
                i257_new(
                    calculate_debt(
                        nominal_debt_delta.abs,
                        context.debt_asset_config.last_rate_accumulator,
                        context.debt_asset_config.scale,
                        true
                    ),
                    debt_delta.is_negative
                );
        }
        context.position.nominal_debt -= nominal_debt_delta.abs;
        context.debt_asset_config.total_nominal_debt -= nominal_debt_delta.abs;
        context.debt_asset_config.reserve += debt_delta.abs - bad_debt; // bad debt is not paid back
    }

    (collateral_delta, collateral_shares_delta, debt_delta, nominal_debt_delta)
}
