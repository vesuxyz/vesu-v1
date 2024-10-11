#[cfg(test)]
mod TestCommon {
    use starknet::get_block_timestamp;
    use alexandria_math::i257::{i257, i257_new, U256IntoI257};
    use snforge_std::{cheatcodes::{start_warp, stop_warp, CheatTarget}};
    use vesu::data_model::{AssetConfig, Context, Position, Amount, AmountType, AmountDenomination};
    use vesu::{
        units::{SCALE, DAY_IN_SECONDS, YEAR_IN_SECONDS, PERCENT},
        common::{
            calculate_nominal_debt, calculate_debt, calculate_utilization, calculate_collateral_shares,
            calculate_collateral, deconstruct_collateral_amount, deconstruct_debt_amount, is_collateralized,
            apply_position_update_to_context, calculate_rate_accumulator, calculate_collateral_and_debt_value,
            calculate_fee_shares
        }
    };

    fn get_default_asset_config() -> AssetConfig {
        let asset_scale = 100_000_000;
        AssetConfig {
            total_collateral_shares: SCALE,
            total_nominal_debt: SCALE / 2,
            reserve: 5 * asset_scale,
            max_utilization: SCALE,
            floor: SCALE,
            scale: asset_scale,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 6517893350,
            fee_rate: 0
        }
    }

    #[test]
    #[fuzzer(runs: 256, seed: 100)]
    fn test_calculate_nominial_debt_calculate_debt_inverse_relation(seed: u128) {
        let asset_scale = 100_000_000;
        let debt = seed.into() * asset_scale + seed.into();
        let rate_accumulator = SCALE;
        let nominal_debt = calculate_nominal_debt(debt, rate_accumulator, asset_scale, false);
        let debt_calc = calculate_debt(nominal_debt, rate_accumulator, asset_scale, true);
        assert!(debt_calc == debt, "Debt calculations aren't invertible");
    }

    #[test]
    #[fuzzer(runs: 256, seed: 100)]
    fn test_calculate_nominal_calculate_debt_inverse_relation(seed: u16) {
        let asset_scale = SCALE;
        let nominal_debt = seed.into() * SCALE + seed.into();
        let rate_accumulator = SCALE;
        let debt = calculate_debt(nominal_debt, rate_accumulator, asset_scale, true);
        let nominal_debt_calc = calculate_nominal_debt(debt, rate_accumulator, asset_scale, false);
        assert!(nominal_debt_calc == nominal_debt, "Debt calculations aren't invertible");
    }

    // checks rounding occurs
    #[test]
    #[fuzzer(runs: 256, seed: 101)]
    fn test_calculate_nominal_debt_rounding(mut init_debt: u128, mut rate_accumulator: u8) {
        if init_debt.is_zero() || rate_accumulator.is_zero() {
            init_debt += 1;
            rate_accumulator += 1;
        }
        let initial_debt = init_debt.into() * SCALE;
        let rate_accumulator = rate_accumulator.into() * SCALE;

        let nominal_debt = calculate_nominal_debt(initial_debt, rate_accumulator, SCALE, true);

        let rounded_nominal_debt = ((initial_debt * SCALE) / rate_accumulator) + 1;

        if (((initial_debt * SCALE) / rate_accumulator) * rate_accumulator) / SCALE < initial_debt {
            assert!(nominal_debt == rounded_nominal_debt, "Debt is incorrectly rounded");
        }
    }

    #[test]
    fn test_calculate_nominal_debt_precision() {
        let nominal_debt_rounded = calculate_nominal_debt(22_222_222, 3 * SCALE, 100_000_000, true);
        assert!(nominal_debt_rounded == 74074073333333334, "Debt is rounding is not precise");
        let nominal_debt_rounded = calculate_nominal_debt(55_555_555, 3 * SCALE, 100_000_000, true);
        assert!(nominal_debt_rounded == 185185183333333334, "Debt is rounding is not precise");
        let nominal_debt_rounded = calculate_nominal_debt(77_777_777, 3 * SCALE, 100_000_000, true);
        assert!(nominal_debt_rounded == 259259256666666667, "Debt is rounding is not precise");
        let nominal_debt_rounded = calculate_nominal_debt(88_888_888, 3 * SCALE, 100_000_000, true);
        assert!(nominal_debt_rounded == 296296293333333334, "Debt is rounding is not precise");
        let nominal_debt_rounded = calculate_nominal_debt(77_777_777, 2 * SCALE, 100_000_000, true);
        assert!(nominal_debt_rounded == 388888885000000000, "Debt is rounding is not precise");
    }

    #[test]
    fn test_calculate_nominal_debt_zero_rate_accumulator() {
        let initial_debt = 20 * SCALE;
        let rate_accumulator = 0_u256;
        assert(calculate_nominal_debt(initial_debt, rate_accumulator, SCALE, false) == 0, 'Did not return 0');
    }

    #[test]
    #[should_panic(expected: "nominal-debt-overflow")]
    fn test_calculate_nominal_debt_nominal_debt_overflow() {
        let initial_debt = integer::BoundedU256::max() / SCALE;
        let rate_accumulator = SCALE / 10;
        calculate_nominal_debt(initial_debt, rate_accumulator, SCALE, false);
    }

    #[test]
    #[should_panic(expected: "collateral-shares-overflow")]
    fn test_calculate_collateral_shares_collateral_shares_overflow() {
        let initial_collateral = integer::BoundedU256::max() / SCALE;

        let config = AssetConfig {
            total_collateral_shares: SCALE,
            total_nominal_debt: 0,
            reserve: SCALE / 10,
            max_utilization: SCALE,
            floor: 0,
            scale: SCALE,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 0,
            fee_rate: 0
        };

        calculate_collateral_shares(initial_collateral, config, false);
    }

    #[test]
    #[should_panic(expected: "collateral-overflow")]
    fn test_calculate_collateral_collateral_overflow() {
        let initial_collateral_shares = integer::BoundedU256::max() / SCALE;

        let config = AssetConfig {
            total_collateral_shares: SCALE / 10,
            total_nominal_debt: 0,
            reserve: SCALE,
            max_utilization: SCALE,
            floor: 0,
            scale: SCALE,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 0,
            fee_rate: 0
        };

        calculate_collateral(initial_collateral_shares, config, false);
    }

    #[test]
    #[fuzzer(runs: 256, seed: 103)]
    fn test_is_collateralized(debt_value: u128, collateral_value: u128, ratio: u8) {
        let max_pair_LTV_ratio = ratio.into() * SCALE;
        let debt_value = debt_value.into() * SCALE;
        let collateral_value = collateral_value.into() * SCALE;
        let check_collat = is_collateralized(collateral_value, debt_value, max_pair_LTV_ratio);
        if ((ratio == 0 && debt_value == 0) || (collateral_value * ratio.into()) >= debt_value) {
            assert!(check_collat, "Collateralization check failed");
        } else {
            assert!(!check_collat, "Collateralization check failed");
        }
    }

    #[test]
    #[fuzzer(runs: 256, seed: 101)]
    fn test_calculate_utilization(total_reserve: u128, total_outstanding: u128) {
        let total_reserve = total_reserve.into() * SCALE;
        let total_outstanding = total_outstanding.into() * SCALE;
        let utilization = calculate_utilization(total_reserve, total_outstanding);
        assert!(
            utilization == (total_outstanding * SCALE) / (total_reserve + total_outstanding),
            "Utilization calculation failed"
        );
        assert!(utilization <= SCALE, "Utilization calculation failed");
    }

    #[test]
    fn test_calculate_utilization_div_zero() {
        // if total total outstanding == 0 utilization should be 0
        let total_reserve = 100 * SCALE;
        let total_outstanding = 0;
        let utilization = calculate_utilization(total_reserve, total_outstanding);
        assert!(utilization == 0, "Utilization calculation failed");

        // if total reserve == 0 utilization should be 100% == 1e18
        let total_reserve = 0;
        let total_outstanding = 2817 * SCALE;
        let utilization = calculate_utilization(total_reserve, total_outstanding);
        assert!(utilization == SCALE, "Utilization calculation failed");
    }

    #[test]
    // which ranges to test for rate accumulator? 
    fn test_calculate_rate_accumulator() {
        let last_updated = 95;
        let current_time = last_updated + 5;
        start_warp(CheatTarget::All, current_time);
        let last_rate_accumulator = SCALE;
        let interest_rate = 1050000000000000000;
        let accumulator_1 = calculate_rate_accumulator(last_updated, last_rate_accumulator, interest_rate);
        let accumulator_2 = calculate_rate_accumulator(current_time, accumulator_1, interest_rate);
        assert!(accumulator_1 == accumulator_2, "Rate accumulator failed");
        stop_warp(CheatTarget::All);
    }

    #[test]
    fn test_calculate_unsafe_rate_accumulator() {
        let last_updated = 1707509060;
        let current_time = last_updated + (360 * DAY_IN_SECONDS);
        start_warp(CheatTarget::All, current_time);
        let last_rate_accumulator = SCALE;
        let interest_rate = 100824704600; // 300% per year
        let accumulator = calculate_rate_accumulator(last_updated, last_rate_accumulator, interest_rate);
        assert!(accumulator > 18 * SCALE, "accumulator should be above 18");
        stop_warp(CheatTarget::All);
    }

    #[test]
    fn test_calculate_fee_shares() {
        let asset_scale = 100_000_000;
        let mut asset_config = AssetConfig {
            total_collateral_shares: 100 * SCALE,
            total_nominal_debt: 100 * SCALE,
            reserve: 0,
            max_utilization: SCALE,
            floor: 0,
            scale: asset_scale,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: SCALE,
            fee_rate: 10 * PERCENT
        };
        assert!(calculate_fee_shares(asset_config, SCALE) == 0, "Fee shares should be 0");

        let fee_shares = calculate_fee_shares(asset_config, SCALE + (SCALE * 10 / 100));

        asset_config.total_collateral_shares += fee_shares;
        asset_config.last_rate_accumulator = SCALE + (SCALE * 10 / 100);
        asset_config.last_updated = get_block_timestamp();
        let fee = calculate_collateral(fee_shares, asset_config, false);

        println!("fee:              {}", fee);
        println!("asset_scale * 10: {}", asset_scale * 10);

        assert!(
            fee + 1 == asset_scale * 10,
            "Fee shares should be 10% of the reserve"
        );
    }

    #[test]
    #[fuzzer(runs: 256, seed: 203)]
    fn test_collateral_inverse_relation(num: u16) {
        let asset_scale = 100_000_000;
        let config = AssetConfig {
            total_collateral_shares: SCALE,
            total_nominal_debt: SCALE / 2,
            reserve: num.into() * 10000000,
            max_utilization: SCALE,
            floor: SCALE,
            scale: asset_scale,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 6517893350,
            fee_rate: 0
        };

        let collateral_amount = 5 * asset_scale;

        let collateral_shares = calculate_collateral_shares(collateral_amount, config, false);

        let calculated_collateral = calculate_collateral(collateral_shares, config, true);

        assert!(calculated_collateral == collateral_amount, "Collateral calculations aren't inverse");
    }

    #[test]
    #[fuzzer(runs: 256, seed: 100)]
    fn test_calculate_collateral_and_debt_value(debt: u16, collateral: u16) {
        let asset_scale = 100_000_000;
        let initial_debt = debt.into() * asset_scale;
        let collateral_amount = collateral.into() * asset_scale;
        let rate_accumulator = SCALE;
        let config = AssetConfig {
            total_collateral_shares: SCALE,
            total_nominal_debt: SCALE / 2,
            reserve: 100 * asset_scale,
            max_utilization: SCALE,
            floor: SCALE,
            scale: asset_scale,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 6517893350,
            fee_rate: 0
        };
        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral_amount, config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, rate_accumulator, asset_scale, false),
        };

        let mut context = Context {
            pool_id: 1,
            extension: Zeroable::zero(),
            collateral_asset: Zeroable::zero(),
            debt_asset: Zeroable::zero(),
            collateral_asset_config: config,
            debt_asset_config: config,
            collateral_asset_price: Default::default(),
            debt_asset_price: Default::default(),
            collateral_asset_fee_shares: 0,
            debt_asset_fee_shares: 0,
            max_ltv: 2,
            user: Zeroable::zero(),
            position: position
        };

        let (collateral, _, debt, _) = calculate_collateral_and_debt_value(context, context.position);

        let expected_collateral = calculate_collateral(
            position.collateral_shares, context.collateral_asset_config, false
        );
        let expected_debt = calculate_debt(position.nominal_debt, config.last_rate_accumulator, config.scale, false);

        assert!(collateral == expected_collateral, "Collateral calculation failed");
        assert!(debt == expected_debt, "Debt calculation failed");
    }

    #[test]
    #[fuzzer(runs: 256, seed: 100)]
    fn test_calculate_collateral_and_debt_value_2(debt: u16, collateral: u16) {
        let asset_scale = 100_000_000;
        let initial_debt = debt.into() * asset_scale;
        let collateral_amount = collateral.into() * asset_scale;
        let rate_accumulator = SCALE;
        let config = AssetConfig {
            total_collateral_shares: SCALE,
            total_nominal_debt: SCALE / 2,
            reserve: 100 * asset_scale,
            max_utilization: SCALE,
            floor: SCALE,
            scale: asset_scale,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 6517893350,
            fee_rate: 0
        };
        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral_amount, config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, rate_accumulator, asset_scale, false),
        };

        let mut context = Context {
            pool_id: 1,
            extension: Zeroable::zero(),
            collateral_asset: Zeroable::zero(),
            debt_asset: Zeroable::zero(),
            collateral_asset_config: config,
            debt_asset_config: config,
            collateral_asset_price: Default::default(),
            debt_asset_price: Default::default(),
            collateral_asset_fee_shares: 0,
            debt_asset_fee_shares: 0,
            max_ltv: 2,
            user: Zeroable::zero(),
            position: position
        };

        let (collateral, collateral_value, debt, debt_value) = calculate_collateral_and_debt_value(
            context, context.position
        );

        let expected_collateral_value = collateral * context.collateral_asset_price.value / config.scale;
        let expected_debt_value = debt * context.debt_asset_price.value / config.scale;

        assert!(collateral_value == expected_collateral_value, "Collateral calculation failed");
        assert!(debt_value == expected_debt_value, "Debt calculation failed");
    }


    #[test]
    fn test_deconstruct_collateral_shares_asset_delta() {
        let asset_scale = 100_000_000;
        let collateral = asset_scale;
        let initial_debt = 2 * collateral;
        let asset_config = get_default_asset_config();

        let collateral_amount_asset_delta = Amount {
            amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: (12 * asset_scale).into()
        };
        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (collateral_delta, collateral_shares_delta) = deconstruct_collateral_amount(
            collateral_amount_asset_delta, position, asset_config
        );
        let expected_collateral_shares_delta = calculate_collateral_shares(collateral_delta.abs, asset_config, false);

        assert!(collateral_delta == collateral_amount_asset_delta.value, "Delta incorrect");
        assert!(collateral_shares_delta.abs == expected_collateral_shares_delta, "Deconstruct collateral failed");
        assert!(
            collateral_delta.is_negative == collateral_amount_asset_delta.value.is_negative,
            "Deconstruct collateral failed"
        );

        let converted_collateral = calculate_collateral(collateral_shares_delta.abs, asset_config, false);
        // expect a loss of one unit of collateral because collateral_shares_delta calculation is rounding down
        assert!(converted_collateral <= collateral_amount_asset_delta.value.abs, "Retrieve collateral failed");
    }

    #[test]
    fn test_deconstruct_native_collateral_delta() {
        let asset_scale = 100_000_000;
        let collateral = asset_scale;
        let initial_debt = 2 * collateral;
        let asset_config = get_default_asset_config();

        let collateral_amount_native_delta = Amount {
            amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: (10 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (collateral_delta, collateral_shares_delta) = deconstruct_collateral_amount(
            collateral_amount_native_delta, position, asset_config
        );

        assert!(
            collateral_delta == i257_new(
                calculate_collateral(collateral_shares_delta.abs, asset_config, true),
                collateral_shares_delta.is_negative
            ),
            "Deconstruct collateral failed"
        );
        assert!(collateral_shares_delta == collateral_amount_native_delta.value, "Deconstruct collateral failed");
    }

    #[test]
    #[should_panic(expected: "collateral-target-negative")]
    fn test_deconstruct_collateral_target_collateral_target_negative() {
        let asset_scale = 100_000_000;
        let collateral = asset_scale;
        let initial_debt = 2 * collateral;
        let asset_config = get_default_asset_config();

        let collateral_amount_native_target = Amount {
            amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: -(15 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        deconstruct_collateral_amount(collateral_amount_native_target, position, asset_config);
    }

    #[test]
    fn test_deconstruct_native_collateral_target() {
        let asset_scale = 100_000_000;
        let collateral = asset_scale;
        let initial_debt = 2 * collateral;
        let asset_config = get_default_asset_config();

        let collateral_amount_native_target = Amount {
            amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: (15 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (collateral_delta, collateral_shares_delta) = deconstruct_collateral_amount(
            collateral_amount_native_target, position, asset_config
        );

        let expected_delta = calculate_collateral(
            position.collateral_shares - collateral_amount_native_target.value.abs, asset_config, false
        );

        assert!(collateral_delta.abs == expected_delta, "Deconstruct collateral failed");
        assert!(
            collateral_shares_delta == -(position.collateral_shares.into() - collateral_amount_native_target.value),
            "Deconstruct collateral failed"
        );

        // value exceeds collateral shares
        let collateral_amount_native_target = Amount {
            amount_type: AmountType::Target,
            denomination: AmountDenomination::Native,
            value: (20 * 10000000000 * asset_scale).into()
        };

        let (collateral_delta, collateral_shares_delta) = deconstruct_collateral_amount(
            collateral_amount_native_target, position, asset_config
        );

        let expected_delta = calculate_collateral(
            collateral_amount_native_target.value.abs - position.collateral_shares, asset_config, true
        );

        assert!(collateral_delta.abs == expected_delta, "Deconstruct collateral failed");
        assert!(
            collateral_shares_delta == (collateral_amount_native_target.value - position.collateral_shares.into()),
            "Deconstruct collateral failed"
        );
    }

    #[test]
    fn test_deconstruct_asset_collateral_target() {
        let asset_scale = 100_000_000;
        let collateral = 20 * asset_scale;
        let initial_debt = 2 * collateral;
        let asset_config = get_default_asset_config();

        let collateral_amount_asset_target = Amount {
            amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: (20 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (collateral_delta, collateral_shares_delta) = deconstruct_collateral_amount(
            collateral_amount_asset_target, position, asset_config
        );

        let position_collateral = calculate_collateral(position.collateral_shares, asset_config, false);

        let expected_shares_delta = calculate_collateral_shares(
            collateral_amount_asset_target.value.abs - position_collateral, asset_config, false
        );

        assert!(collateral_shares_delta.abs == expected_shares_delta, "Deconstruct collateral failed");
        assert!(
            (collateral_amount_asset_target.value.abs - position_collateral).into() == collateral_delta,
            "Deconstruct collateral failed"
        );

        // collateral exceed value
        let collateral_amount_asset_target = Amount {
            amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: asset_scale.into()
        };

        let position_collateral = calculate_collateral(position.collateral_shares, asset_config, false);

        let expected_shares_delta = calculate_collateral_shares(
            position_collateral - collateral_amount_asset_target.value.abs, asset_config, true
        );

        let (collateral_delta, collateral_shares_delta) = deconstruct_collateral_amount(
            collateral_amount_asset_target, position, asset_config
        );

        assert!(collateral_shares_delta.abs == expected_shares_delta, "Deconstruct collateral failed");
        assert!(
            -(position_collateral - collateral_amount_asset_target.value.abs).into() == collateral_delta,
            "Deconstruct collateral failed"
        );
    }

    #[test]
    fn test_deconstruct_native_debt_delta() {
        let asset_scale = 100_000_000;
        let rate_accumulator = SCALE;
        let asset_config = get_default_asset_config();
        let collateral = 20 * asset_scale;
        let initial_debt = 2 * collateral;
        let debt_amount_asset_delta = Amount {
            amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: (10 * asset_scale).into()
        };
        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (debt_delta, nominal_debt_delta) = deconstruct_debt_amount(
            debt_amount_asset_delta, position, rate_accumulator, asset_scale
        );

        assert!(nominal_debt_delta == debt_amount_asset_delta.value, "Deconstruct debt delta failed");
        assert!(
            debt_delta == i257_new(
                calculate_debt(nominal_debt_delta.abs, rate_accumulator, asset_scale, false),
                nominal_debt_delta.is_negative
            ),
            "Deconstruct nominal debt failed"
        );
    }

    #[test]
    fn test_deconstruct_asset_debt_delta() {
        let asset_scale = 100_000_000;
        let rate_accumulator = SCALE;
        let asset_config = get_default_asset_config();
        let collateral = 20 * asset_scale;
        let initial_debt = 2 * collateral;

        let debt_amount_asset_delta = Amount {
            amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: (20 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (debt_delta, nominal_debt_delta) = deconstruct_debt_amount(
            debt_amount_asset_delta, position, rate_accumulator, asset_scale
        );

        assert!(debt_delta == debt_amount_asset_delta.value, "Deconstruct debt delta failed");
        assert!(
            nominal_debt_delta == i257_new(
                calculate_nominal_debt(debt_delta.abs, rate_accumulator, asset_scale, false), debt_delta.is_negative
            ),
            "Deconstruct nominal debt failed"
        );
    }

    #[test]
    #[should_panic(expected: "debt-target-negative")]
    fn test_deconstruct_debt_target_debt_target_negative() {
        let asset_scale = 100_000_000;
        let rate_accumulator = SCALE;
        let asset_config = get_default_asset_config();
        let collateral = 20 * asset_scale;
        let initial_debt = 2 * collateral;

        let debt_amount_native_target = Amount {
            amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: -(15 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        deconstruct_debt_amount(debt_amount_native_target, position, rate_accumulator, asset_scale);
    }

    #[test]
    fn test_deconstruct_native_debt_target() {
        let asset_scale = 100_000_000;
        let rate_accumulator = SCALE;
        let asset_config = get_default_asset_config();
        let collateral = 20 * asset_scale;
        let initial_debt = 2 * collateral;

        let debt_amount_native_target = Amount {
            amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: (15 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (debt_delta, nominal_debt_delta) = deconstruct_debt_amount(
            debt_amount_native_target, position, rate_accumulator, asset_scale
        );

        let expected_debt_delta = calculate_debt(
            position.nominal_debt - debt_amount_native_target.value.abs, rate_accumulator, asset_scale, true
        );

        assert!(debt_delta.abs == expected_debt_delta, "Deconstruct debt delta failed");
        assert!(
            nominal_debt_delta.abs == position.nominal_debt - debt_amount_native_target.value.abs,
            "Deconstruct nominal debt failed"
        );
    }

    #[test]
    fn test_deconstruct_asset_debt_target() {
        let asset_scale = 100_000_000;
        let rate_accumulator = SCALE;
        let asset_config = get_default_asset_config();
        let collateral = 20 * asset_scale;
        let initial_debt = 2 * collateral;

        let debt_amount_asset_target = Amount {
            amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: (25 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (debt_delta, nominal_debt_delta) = deconstruct_debt_amount(
            debt_amount_asset_target, position, rate_accumulator, asset_scale
        );

        let position_debt = calculate_debt(position.nominal_debt, rate_accumulator, asset_scale, false);
        let expected_nominal_delta = calculate_nominal_debt(
            position_debt - debt_amount_asset_target.value.abs, rate_accumulator, asset_scale, false
        );

        assert!(debt_delta.abs == position_debt - debt_amount_asset_target.value.abs, "Deconstruct debt delta failed");
        assert!(nominal_debt_delta == -expected_nominal_delta.into(), "Deconstruct nominal debt failed");

        // positional debt < debt amount

        let debt_amount_asset_target = Amount {
            amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: (50 * asset_scale).into()
        };

        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral, asset_config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, SCALE, asset_scale, false),
        };

        let (debt_delta, nominal_debt_delta) = deconstruct_debt_amount(
            debt_amount_asset_target, position, rate_accumulator, asset_scale
        );

        let position_debt = calculate_debt(position.nominal_debt, rate_accumulator, asset_scale, false);

        let expected_nominal_delta = calculate_nominal_debt(
            debt_amount_asset_target.value.abs - position_debt, rate_accumulator, asset_scale, false
        );

        assert!(debt_delta.abs == debt_amount_asset_target.value.abs - position_debt, "Deconstruct debt delta failed");
        assert!(nominal_debt_delta == expected_nominal_delta.into(), "Deconstruct nominal debt failed");
    }

    #[test]
    fn test_apply_position_update_to_context_positive_delta() {
        let asset_scale = 100_000_000;
        let initial_debt = 2 * asset_scale;
        let collateral_amount = 20 * asset_scale;
        let rate_accumulator = SCALE;
        let config = AssetConfig {
            total_collateral_shares: SCALE,
            total_nominal_debt: SCALE / 2,
            reserve: 100 * asset_scale,
            max_utilization: SCALE,
            floor: SCALE,
            scale: asset_scale,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 6517893350,
            fee_rate: 0
        };
        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral_amount, config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, rate_accumulator, asset_scale, false),
        };

        let mut context = Context {
            pool_id: 1,
            extension: Zeroable::zero(),
            collateral_asset: Zeroable::zero(),
            debt_asset: Zeroable::zero(),
            collateral_asset_config: config,
            debt_asset_config: config,
            collateral_asset_price: Default::default(),
            debt_asset_price: Default::default(),
            collateral_asset_fee_shares: Zeroable::zero(),
            debt_asset_fee_shares: Zeroable::zero(),
            max_ltv: 2,
            user: Zeroable::zero(),
            position: position
        };

        let debt = Amount {
            amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: (10 * asset_scale).into()
        };
        let collateral = Amount {
            amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: (20 * asset_scale).into()
        };

        let bad_debt = 0;

        let (expected_debt_delta, expected_nominal_debt_delta) = deconstruct_debt_amount(
            debt, context.position, context.debt_asset_config.last_rate_accumulator, context.debt_asset_config.scale
        );

        let (expected_collateral_delta, expected_collateral_shares_delta) = deconstruct_collateral_amount(
            collateral, context.position, context.collateral_asset_config,
        );

        let original_context = context;

        let (
            calculated_collateral_delta,
            calculated_collateral_shares_delta,
            calculated_debt_delta,
            calculated_nominal_debt_delta
        ) =
            apply_position_update_to_context(
            ref context, collateral, debt, bad_debt
        );

        //deconstruction works correctly 
        assert!(expected_collateral_delta == calculated_collateral_delta, "Collateral delta deconstruction incorrect");
        assert!(
            expected_collateral_shares_delta == calculated_collateral_shares_delta,
            "Collateral shares delta deconstruction incorrect"
        );
        assert!(expected_debt_delta == calculated_debt_delta, "Debt delta deconstruction incorrect");
        assert!(
            expected_nominal_debt_delta == calculated_nominal_debt_delta, "Nominal debt delta deconstruction incorrect"
        );

        // context is updated correctly

        assert!(
            context.position.collateral_shares == original_context.position.collateral_shares
                + expected_collateral_shares_delta.abs,
            "Context collateral shares update failed"
        );
        assert!(
            context
                .collateral_asset_config
                .total_collateral_shares == original_context
                .collateral_asset_config
                .total_collateral_shares
                + expected_collateral_shares_delta.abs,
            "Context total collateral shares update failed"
        );
        assert!(
            context.collateral_asset_config.reserve == original_context.collateral_asset_config.reserve
                + expected_collateral_delta.abs,
            "Context reserve update failed"
        );

        assert!(
            context.position.nominal_debt == original_context.position.nominal_debt + expected_nominal_debt_delta.abs,
            "Context nominal debt update failed"
        );
        assert!(
            context.debt_asset_config.total_nominal_debt == original_context.debt_asset_config.total_nominal_debt
                + expected_nominal_debt_delta.abs,
            "Context total nominal debt update failed"
        );
        assert!(
            context.debt_asset_config.reserve == original_context.debt_asset_config.reserve - expected_debt_delta.abs,
            "Context reserve debt update failed"
        );
    }

    #[test]
    fn test_apply_position_update_to_context_negative_delta() {
        let asset_scale = 100_000_000;
        let initial_debt = 20 * asset_scale;
        let collateral_amount = 30 * asset_scale;
        let rate_accumulator = SCALE;
        let config = AssetConfig {
            total_collateral_shares: SCALE * 4,
            total_nominal_debt: SCALE * 2,
            reserve: 500 * asset_scale,
            max_utilization: SCALE,
            floor: SCALE,
            scale: asset_scale,
            is_legacy: false,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 6517893350,
            fee_rate: 0
        };
        let position = Position {
            collateral_shares: calculate_collateral_shares(collateral_amount, config, false),
            nominal_debt: calculate_nominal_debt(initial_debt, rate_accumulator, asset_scale, false),
        };

        let mut context = Context {
            pool_id: 1,
            extension: Zeroable::zero(),
            collateral_asset: Zeroable::zero(),
            debt_asset: Zeroable::zero(),
            collateral_asset_config: config,
            debt_asset_config: config,
            collateral_asset_price: Default::default(),
            debt_asset_price: Default::default(),
            collateral_asset_fee_shares: Zeroable::zero(),
            debt_asset_fee_shares: Zeroable::zero(),
            max_ltv: 2,
            user: Zeroable::zero(),
            position: position
        };

        let debt = Amount {
            amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: -(asset_scale).into()
        };
        let collateral = Amount {
            amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: -(asset_scale).into()
        };

        let bad_debt = 0;

        let (expected_debt_delta, expected_nominal_debt_delta) = deconstruct_debt_amount(
            debt, context.position, context.debt_asset_config.last_rate_accumulator, context.debt_asset_config.scale
        );

        let (expected_collateral_delta, expected_collateral_shares_delta) = deconstruct_collateral_amount(
            collateral, context.position, context.collateral_asset_config,
        );

        let original_context = context;

        let (
            calculated_collateral_delta,
            calculated_collateral_shares_delta,
            calculated_debt_delta,
            calculated_nominal_debt_delta
        ) =
            apply_position_update_to_context(
            ref context, collateral, debt, bad_debt
        );

        //deconstruction works correctly 
        assert!(expected_collateral_delta == calculated_collateral_delta, "Collateral delta deconstruction incorrect");
        assert!(
            expected_collateral_shares_delta == calculated_collateral_shares_delta,
            "Collateral shares delta deconstruction incorrect"
        );
        assert!(expected_debt_delta == calculated_debt_delta, "Debt delta deconstruction incorrect");
        assert!(
            expected_nominal_debt_delta == calculated_nominal_debt_delta, "Nominal debt delta deconstruction incorrect"
        );

        // context is updated correctly
        assert!(
            context.position.collateral_shares == original_context.position.collateral_shares
                - expected_collateral_shares_delta.abs,
            "Context collateral shares update failed"
        );
        assert!(
            context
                .collateral_asset_config
                .total_collateral_shares == original_context
                .collateral_asset_config
                .total_collateral_shares
                - expected_collateral_shares_delta.abs,
            "Context total collateral shares update failed"
        );
        assert!(
            context.collateral_asset_config.reserve == original_context.collateral_asset_config.reserve
                - expected_collateral_delta.abs,
            "Context debt reserve update failed"
        );
        assert!(
            context.position.nominal_debt == original_context.position.nominal_debt - expected_nominal_debt_delta.abs,
            "Context nominal debt update failed"
        );
        assert!(
            context.debt_asset_config.total_nominal_debt == original_context.debt_asset_config.total_nominal_debt
                - expected_nominal_debt_delta.abs,
            "Context total nominal debt update failed"
        );
        assert!(
            context.debt_asset_config.reserve == original_context.debt_asset_config.reserve
                + expected_debt_delta.abs
                - bad_debt,
            "Context collateral reserve debt update failed"
        );
    }
}
