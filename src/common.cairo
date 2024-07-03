use alexandria_math::i257::{i257, i257_new, U256IntoI257};
use starknet::{get_block_timestamp};
use vesu::{
    math::{pow_scale, pow_10}, units::{SCALE},
    data_model::{AmountType, AmountDenomination, Amount, Position, AssetConfig, Context},
};

/// Calculates the nominal debt for a given amount of debt, the current rate accumulator and debt asset's scale
/// # Arguments
/// * `debt` - debt [asset scale]
/// * `rate_accumulator` - rate accumulator [SCALE]
/// * `asset_scale` - asset scale [asset scale]
/// # Returns
/// * `nominal_debt` - computed nominal debt [SCALE]
fn calculate_nominal_debt(debt: u256, rate_accumulator: u256, asset_scale: u256) -> u256 {
    // TODO: verify check for rounding errors
    let precision_adjusted_debt = integer::u256_wide_mul(debt * SCALE, SCALE);
    let rate_accumulator: NonZero<u256> = rate_accumulator.try_into().expect('zero-rate-accumulator');
    let (nominal_debt, remainder) = integer::u512_safe_div_rem_by_u256(precision_adjusted_debt, rate_accumulator);
    assert!(nominal_debt.limb2 == 0 && nominal_debt.limb3 == 0, "nominal-debt-overflow");
    let nominal_debt = u256 { low: nominal_debt.limb0, high: nominal_debt.limb1 };
    if remainder == 0 {
        nominal_debt / asset_scale
    } else {
        (nominal_debt / asset_scale) + 1
    }
}

/// Calculates the debt for a given amount of nominal debt, the current rate accumulator and debt asset's scale
/// # Arguments
/// * `nominal_debt` - nominal debt [SCALE]
/// * `rate_accumulator` - rate accumulator [SCALE]
/// * `asset_scale` - asset scale [asset scale]
/// # Returns
/// * `debt` - computed debt [asset scale]
fn calculate_debt(nominal_debt: u256, rate_accumulator: u256, asset_scale: u256) -> u256 {
    ((nominal_debt * rate_accumulator) / SCALE) * asset_scale / SCALE
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
    let time_delta = get_block_timestamp() - last_updated;
    last_rate_accumulator * pow_scale(SCALE + interest_rate, time_delta.into(), false) / SCALE
}

/// Calculates the number of collateral shares (that would be e.g. minted) for a given amount of collateral assets
/// # Arguments
/// * `collateral` - collateral asset amount [asset scale]
/// * `asset_config` - collateral asset config
/// # Returns
/// * `collateral_shares` - collateral shares amount [SCALE]
fn calculate_collateral_shares(collateral: u256, asset_config: AssetConfig) -> u256 {
    let AssetConfig{reserve, total_nominal_debt, total_collateral_shares, last_rate_accumulator, scale, .. } =
        asset_config;
    let total_debt = calculate_debt(total_nominal_debt, last_rate_accumulator, scale);
    let total_assets = reserve + total_debt;
    if total_assets == 0 || total_collateral_shares == 0 {
        return collateral * SCALE / scale;
    }

    let mut collateral_shares = (collateral * total_collateral_shares) / total_assets;
    if (collateral_shares * total_assets) / total_collateral_shares < collateral {
        collateral_shares += 1;
    }

    return collateral_shares;
}

/// Calculates the amount of collateral assets (that can e.g. be redeemed)  for a given amount of collateral shares
/// # Arguments
/// * `collateral_shares` - collateral shares amount [SCALE]
/// * `asset_config` - collateral asset config
/// # Returns
/// * `collateral` - collateral asset amount [asset scale]
fn calculate_collateral(collateral_shares: u256, asset_config: AssetConfig) -> u256 {
    let AssetConfig{reserve, total_nominal_debt, total_collateral_shares, last_rate_accumulator, scale, .. } =
        asset_config;
    let total_debt = calculate_debt(total_nominal_debt, last_rate_accumulator, scale);
    if total_collateral_shares == 0 {
        return collateral_shares * scale / SCALE;
    }
    let total_assets = reserve + total_debt;
    (collateral_shares * total_assets) / total_collateral_shares
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
            let delta = calculate_collateral(collateral_shares_delta.abs, asset_config);
            (i257_new(delta, collateral_shares_delta.is_negative), collateral_shares_delta)
        } else {
            let collateral_delta = collateral.value;
            let collateral_shares_delta = calculate_collateral_shares(collateral_delta.abs, asset_config);
            (collateral_delta, i257_new(collateral_shares_delta, collateral_delta.is_negative))
        }
    } else {
        if collateral.denomination == AmountDenomination::Native {
            let collateral_shares_target = collateral.value.abs;
            if position.collateral_shares >= collateral_shares_target {
                let delta = calculate_collateral(position.collateral_shares - collateral_shares_target, asset_config);
                (-delta.into(), -(position.collateral_shares - collateral_shares_target).into())
            } else {
                let delta = calculate_collateral(collateral_shares_target - position.collateral_shares, asset_config);
                (delta.into(), (collateral_shares_target - position.collateral_shares).into())
            }
        } else {
            let collateral_target = collateral.value.abs;
            let position_collateral = calculate_collateral(position.collateral_shares, asset_config);
            if position_collateral >= collateral_target {
                let shares_delta = calculate_collateral_shares(position_collateral - collateral_target, asset_config);
                (-(position_collateral - collateral_target).into(), -shares_delta.into())
            } else {
                let shares_delta = calculate_collateral_shares(collateral_target - position_collateral, asset_config);
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
            let debt_delta = calculate_debt(nominal_debt_delta.abs, rate_accumulator, asset_scale);
            (i257_new(debt_delta, nominal_debt_delta.is_negative), nominal_debt_delta)
        } else {
            let debt_delta = debt.value;
            let nominal_debt_delta = calculate_nominal_debt(debt_delta.abs, rate_accumulator, asset_scale);
            (debt_delta, i257_new(nominal_debt_delta, debt_delta.is_negative))
        };
    }
    if debt.denomination == AmountDenomination::Native {
        let nominal_debt_target = debt.value;
        if position.nominal_debt >= nominal_debt_target.abs {
            let debt_delta = calculate_debt(
                position.nominal_debt - nominal_debt_target.abs, rate_accumulator, asset_scale
            );
            let nominal_debt_delta = position.nominal_debt - nominal_debt_target.abs;
            (-debt_delta.into(), -nominal_debt_delta.into())
        } else {
            let debt_delta = calculate_debt(
                nominal_debt_target.abs - position.nominal_debt, rate_accumulator, asset_scale
            );
            let nominal_debt_delta = nominal_debt_target.abs - position.nominal_debt;
            (debt_delta.into(), nominal_debt_delta.into())
        }
    } else {
        let debt_target = debt.value;
        let position_debt = calculate_debt(position.nominal_debt, rate_accumulator, asset_scale);
        if position_debt >= debt_target.abs {
            // derive nominal debt from debt value, since user provided debt amount should be adjusted
            let nominal_delta = calculate_nominal_debt(position_debt - debt_target.abs, rate_accumulator, asset_scale);
            let debt_delta = position_debt - debt_target.abs;
            (-debt_delta.into(), -nominal_delta.into())
        } else {
            // derive nominal debt from debt value, since user provided debt amount should be adjusted
            let nominal_delta = calculate_nominal_debt(debt_target.abs - position_debt, rate_accumulator, asset_scale);
            let debt_delta = debt_target.abs - position_debt;
            (debt_delta.into(), nominal_delta.into())
        }
    }
}

/// Checks that the collateralization of a position is not above the max. loan-to-value ratio
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
/// # Returns
/// * `collateral` - collateral amount [asset scale]
/// * `collateral_value` - collateral value [SCALE]
/// * `debt` - debt amount [asset scale]
/// * `debt_value` - debt value [SCALE]
fn calculate_collateral_and_debt_value(context: Context) -> (u256, u256, u256, u256) {
    let Context{collateral_asset_config, debt_asset_config, position, .. } = context;

    let collateral = calculate_collateral(position.collateral_shares, collateral_asset_config);
    let debt = calculate_debt(position.nominal_debt, debt_asset_config.last_rate_accumulator, debt_asset_config.scale);

    let collateral_value = collateral * context.collateral_asset_price.value / collateral_asset_config.scale;
    let debt_value = debt * context.debt_asset_price.value / debt_asset_config.scale;

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
    let (collateral_delta, collateral_shares_delta) = deconstruct_collateral_amount(
        collateral, context.position, context.collateral_asset_config,
    );

    // update the collateral balances
    if collateral_delta > Zeroable::zero() {
        context.position.collateral_shares += collateral_shares_delta.abs;
        context.collateral_asset_config.total_collateral_shares += collateral_shares_delta.abs;
        context.collateral_asset_config.reserve += collateral_delta.abs;
    } else if collateral_delta < Zeroable::zero() {
        context.position.collateral_shares -= collateral_shares_delta.abs;
        context.collateral_asset_config.total_collateral_shares -= collateral_shares_delta.abs;
        context.collateral_asset_config.reserve -= collateral_delta.abs;
    }

    // deconstruct the debt amount
    let (debt_delta, nominal_debt_delta) = deconstruct_debt_amount(
        debt, context.position, context.debt_asset_config.last_rate_accumulator, context.debt_asset_config.scale
    );

    // update the debt balances
    if debt_delta > Zeroable::zero() {
        context.position.nominal_debt += nominal_debt_delta.abs;
        context.debt_asset_config.total_nominal_debt += nominal_debt_delta.abs;
        context.debt_asset_config.reserve -= debt_delta.abs;
    } else if debt_delta < Zeroable::zero() {
        context.position.nominal_debt -= nominal_debt_delta.abs;
        context.debt_asset_config.total_nominal_debt -= nominal_debt_delta.abs;
        context.debt_asset_config.reserve += debt_delta.abs - bad_debt; // bad debt is not paid back
    }

    (collateral_delta, collateral_shares_delta, debt_delta, nominal_debt_delta)
}
