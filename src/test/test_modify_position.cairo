#[cfg(test)]
mod TestModifyPosition {
    use snforge_std::{
        start_cheat_caller_address, stop_cheat_caller_address, start_cheat_block_timestamp_global,
        stop_cheat_block_timestamp_global
    };
    use starknet::{contract_address_const, get_block_timestamp, get_caller_address};
    use vesu::vendor::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use vesu::{
        units::{SCALE, DAY_IN_SECONDS, YEAR_IN_SECONDS},
        data_model::{Amount, AmountType, AmountDenomination, ModifyPositionParams, Context, AssetConfig, Position},
        singleton::ISingletonDispatcherTrait,
        test::{setup::{setup, TestConfig, LendingTerms}, mock_asset::{IMintableDispatcher, IMintableDispatcherTrait}},
        extension::{
            default_extension_po::{IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait},
            interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
        }
    };

    #[test]
    #[should_panic(expected: "caller-not-singleton")]
    fn test_before_modify_position_caller_not_singleton() {
        let (_, extension, _, _, _) = setup();

        let asset_scale = 100_000_000;

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

        let position = Position { collateral_shares: Default::default(), nominal_debt: Default::default(), };

        let context = Context {
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

        IExtensionDispatcher { contract_address: extension.contract_address }
            .before_modify_position(
                context,
                Default::default(),
                Default::default(),
                data: ArrayTrait::new().span(),
                caller: get_caller_address()
            );
    }

    #[test]
    #[should_panic(expected: "caller-not-singleton")]
    fn test_after_modify_position_caller_not_singleton() {
        let (_, extension, _, _, _) = setup();

        let asset_scale = 100_000_000;

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

        let position = Position { collateral_shares: Default::default(), nominal_debt: Default::default(), };

        let context = Context {
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

        IExtensionDispatcher { contract_address: extension.contract_address }
            .after_modify_position(
                context,
                Default::default(),
                Default::default(),
                Default::default(),
                Default::default(),
                data: ArrayTrait::new().span(),
                caller: get_caller_address()
            );
    }

    #[test]
    #[should_panic(expected: "unknown-pool")]
    fn test_modify_position_unknown_pool() {
        let (singleton, _, _, users, _) = setup();

        // deposit collateral which is later borrowed by the borrower
        let params = ModifyPositionParams {
            pool_id: 'non existent',
            collateral_asset: contract_address_const::<'collateral'>(),
            debt_asset: contract_address_const::<'debt'>(),
            user: users.lender,
            collateral: Default::default(),
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    // identical-assets

    #[test]
    #[should_panic(expected: "no-delegation")]
    fn test_modify_position_no_delegation() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit_third, .. } = terms;

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "utilization-exceeded")]
    fn test_modify_position_utilization_exceeded() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, third_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, liquidity_to_deposit_third, .. } = terms;

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // set max utilization
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_asset_parameter(pool_id, third_asset.contract_address, 'max_utilization', SCALE / 10);
        stop_cheat_caller_address(extension.contract_address);

        // Borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: (SCALE / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "not-collateralized")]
    fn test_modify_position_not_collateralized() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, third_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, liquidity_to_deposit_third, .. } = terms;

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: (SCALE / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: SCALE.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    // // not applicable anymore due to rounding conventions
    // // expected for amounts less than 1e(SCALE-asset.scale)
    // #[test]
    // #[should_panic(expected: "zero-shares-minted")]
    // fn test_modify_position_zero_shares_minted() {
    //     let (singleton, extension, config, users, terms) = setup();
    //     let TestConfig { pool_id, collateral_asset, third_asset, .. } = config;
    //     let LendingTerms { collateral_to_deposit, .. } = terms;

    //     // set floor to 0
    //     start_cheat_caller_address(extension.contract_address, users.creator);
    //     extension.set_asset_parameter(pool_id, collateral_asset.contract_address, 'floor', 0);
    //     extension.set_asset_parameter(pool_id, third_asset.contract_address, 'floor', 0);
    //     stop_cheat_caller_address(extension.contract_address);

    //     // Supply

    //     let params = ModifyPositionParams {
    //         pool_id,
    //         collateral_asset: collateral_asset.contract_address,
    //         debt_asset: third_asset.contract_address,
    //         user: users.lender,
    //         collateral: Amount {
    //             amount_type: AmountType::Delta,
    //             denomination: AmountDenomination::Assets,
    //             value: collateral_to_deposit.into(),
    //         },
    //         debt: Default::default(),
    //         data: ArrayTrait::new().span()
    //     };

    //     start_cheat_caller_address(singleton.contract_address, users.lender);
    //     singleton.modify_position(params);
    //     stop_cheat_caller_address(singleton.contract_address);

    //     let params = ModifyPositionParams {
    //         pool_id,
    //         collateral_asset: collateral_asset.contract_address,
    //         debt_asset: third_asset.contract_address,
    //         user: users.lender,
    //         collateral: Amount {
    //             amount_type: AmountType::Delta,
    //             denomination: AmountDenomination::Native,
    //             value: 1_000_000_000
    //                 .into(), // 1e(SCALE-asset.scale) -> 1e(18-8) -> 1e10, 1e9 yields 1 since it's rounding up
    //         },
    //         debt: Default::default(),
    //         data: ArrayTrait::new().span()
    //     };

    //     start_cheat_caller_address(singleton.contract_address, users.lender);
    //     singleton.modify_position(params);
    //     stop_cheat_caller_address(singleton.contract_address);
    // }

    #[test]
    #[should_panic(expected: "dusty-collateral-balance")]
    fn test_modify_position_dusty_collateral_balance() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

        // set floor to 0
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension
            .set_asset_parameter(pool_id, collateral_asset.contract_address, 'floor', 100_000_000_000); // (* price)
        extension.set_asset_parameter(pool_id, debt_asset.contract_address, 'floor', 0);
        stop_cheat_caller_address(extension.contract_address);

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: liquidity_to_deposit.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: 10.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: 1.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "dusty-debt-balance")]
    fn test_modify_position_dusty_debt_balance() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, .. } = terms;

        // set floor to 0
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_asset_parameter(pool_id, collateral_asset.contract_address, 'floor', 0);
        extension.set_asset_parameter(pool_id, debt_asset.contract_address, 'floor', 1_000_000); // (* price)
        stop_cheat_caller_address(extension.contract_address);

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: liquidity_to_deposit.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: 1.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    // #[test]
    // #[should_panic(expected: "pack-collateral-shares")]
    // fn test_modify_position_collateral_amount_too_large() {
    //     let (singleton, extension, config, users, terms) = setup();
    //     let TestConfig { pool_id, collateral_asset, third_asset, .. } = config;

    //     // Supply

    //     let amount: u256 = integer::BoundedInt::<u128>::max().into();

    //     let params = ModifyPositionParams {
    //         pool_id,
    //         collateral_asset: collateral_asset.contract_address,
    //         debt_asset: third_asset.contract_address,
    //         user: users.lender,
    //         collateral: Amount {
    //             amount_type: AmountType::Delta,
    //             denomination: AmountDenomination::Assets,
    //             value: amount.into(),
    //         },
    //         debt: Default::default(),
    //         data: ArrayTrait::new().span()
    //     };

    //     start_cheat_caller_address(singleton.contract_address, users.lender);
    //     singleton.modify_position(params);
    //     stop_cheat_caller_address(singleton.contract_address);
    // }

    // after-modify-position-failed

    #[test]
    #[fuzzer(runs: 256, seed: 100)]
    fn test_fuzz_modify_position_deposit_withdraw_collateral(seed: u128) {
        let (singleton, _, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;

        start_cheat_caller_address(singleton.contract_address, users.lender);

        // restrict values slightly to avoid overflow due to inflation mitigation deposit
        let amount: u256 = if seed > 20000000000000 {
            seed.into() - 20000000000000
        } else {
            seed.into()
        };
        let collateral_amount = singleton
            .calculate_collateral(pool_id, collateral_asset.contract_address, amount.into());
        IMintableDispatcher { contract_address: collateral_asset.contract_address }
            .mint(users.lender, collateral_amount);

        // Delta, Native

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: amount.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: -amount.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        // Delta, Assets

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_amount.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -collateral_amount.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        // Target, Native

        let collateral_shares = singleton
            .calculate_collateral_shares(pool_id, collateral_asset.contract_address, collateral_amount.into());

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: collateral_shares.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        // Target, Assets

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: collateral_amount.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: 0.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(position.collateral_shares == 0, 'Shares not zero');
    }

    #[test]
    #[fuzzer(runs: 256, seed: 100)]
    fn test_fuzz_modify_position_borrow_repay_debt(seed: u128) {
        let (singleton, _, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;

        let amount: u256 = seed.into() / 10000000000000;
        let collateral_amount = singleton
            .calculate_collateral(pool_id, collateral_asset.contract_address, amount.into());
        let mut debt_amount = singleton.calculate_debt(amount.into(), SCALE, debt_scale);
        debt_amount = debt_amount / 2;

        start_cheat_caller_address(singleton.contract_address, users.lender);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, debt_amount);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        IMintableDispatcher { contract_address: collateral_asset.contract_address }
            .mint(users.borrower, collateral_amount);
        // compensate for rounding up calculation of repayment amount (in two places)
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.borrower, debt_amount + 2);

        // Add liquidity

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: debt_amount.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        // Delta, Native

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: amount.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: (amount / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: -amount.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: -(amount / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        // Delta, Assets

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_amount.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: debt_amount.into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -collateral_amount.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: -debt_amount.into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let collateral_shares = singleton
            .calculate_collateral_shares(pool_id, collateral_asset.contract_address, collateral_amount.into());

        // Target, Native

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: collateral_shares.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: (collateral_shares / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        // Target, Assets

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: collateral_amount.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: debt_amount.into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: 0.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: 0.into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(position.collateral_shares == 0 && position.nominal_debt == 0, 'Position not zero');
    }

    #[test]
    fn test_modify_position_collateral_amounts() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;

        let inflation_fee: u256 = 2000_0000000000; // 2x for each pair

        start_cheat_caller_address(singleton.contract_address, users.lender);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);

        assert(
            asset_config.total_collateral_shares - inflation_fee == position.collateral_shares, 'Shares not matching'
        );

        singleton.donate_to_reserve(pool_id, collateral_asset.contract_address, collateral_to_deposit / 2);

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(
            asset_config.total_collateral_shares - inflation_fee == position.collateral_shares, 'Shares not matching'
        );

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(collateral_to_deposit / 4).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(
            asset_config.total_collateral_shares - inflation_fee == position.collateral_shares, 'Shares not matching'
        );

        let collateral_shares = singleton
            .calculate_collateral_shares(
                pool_id, collateral_asset.contract_address, (collateral_to_deposit / 2).into()
            );

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let collateral_shares = singleton
            .calculate_collateral_shares(
                pool_id, collateral_asset.contract_address, -(collateral_to_deposit / 4).into()
            );

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: -collateral_shares.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 4).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let collateral_shares = singleton
            .calculate_collateral_shares(pool_id, collateral_asset.contract_address, collateral_to_deposit.into());

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: collateral_shares.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(
            asset_config.total_collateral_shares - inflation_fee == position.collateral_shares, 'Shares not matching'
        );
        // rounding error might leave some extra units in the pool
        assert(asset_config.reserve == 4000, 'Reserve not zero');
        assert(asset_config.total_collateral_shares == 2000_0000000000, 'Total shares not zero');

        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    fn test_modify_position_debt_amounts() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, debt_to_draw, .. } = terms;

        start_cheat_caller_address(singleton.contract_address, users.lender);

        // add liquidity
        let params = ModifyPositionParams {
            pool_id,
            debt_asset: collateral_asset.contract_address,
            collateral_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: liquidity_to_deposit.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        // collateralize position
        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS);

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let (position, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(position.nominal_debt < debt * SCALE / debt_scale, 'No interest');

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(debt_to_draw / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: ((debt_to_draw / 2) * SCALE / debt_scale).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: -((debt_to_draw / 4) * SCALE / debt_scale).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: ((debt_to_draw * SCALE / debt_scale) / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(asset_config.total_nominal_debt == position.nominal_debt, 'Shares not matching');
        assert(asset_config.total_nominal_debt == 0, 'Total nominal debt not zero');

        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    fn test_modify_position_complex() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, debt_to_draw, nominal_debt_to_draw, .. } =
            terms;

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);
        let initial_borrower_collateral_asset_balance = collateral_asset.balance_of(users.borrower);
        let initial_borrower_debt_asset_balance = debt_asset.balance_of(users.borrower);
        let initial_singleton_debt_asset_balance = debt_asset.balance_of(singleton.contract_address);

        // LENDER

        // deposit collateral which is later borrowed by the borrower
        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: liquidity_to_deposit.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // check that liquidity has been deposited
        let balance = debt_asset.balance_of(users.lender);
        assert!(balance == initial_lender_debt_asset_balance - liquidity_to_deposit, "Not transferred from Lender");

        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(
            balance == initial_singleton_debt_asset_balance + liquidity_to_deposit, "Not transferred to Singleton"
        ); // 2 due to inflation mitigation

        let (position, collateral, debt) = singleton
            .position(pool_id, debt_asset.contract_address, collateral_asset.contract_address, users.lender);

        assert!(collateral == liquidity_to_deposit, "Collateral not set");
        assert!(position.nominal_debt == 0, "Nominal Debt should be 0");
        assert!(debt == 0, "Debt should be 0");

        // BORROWER

        let initial_singleton_collateral_asset_balance = collateral_asset.balance_of(singleton.contract_address);

        // deposit collateral and debt assets
        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: nominal_debt_to_draw.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // check that collateral has been deposited and the targeted amount has been borrowed

        // collateral asset has been transferred from the borrower to the singleton
        let balance = collateral_asset.balance_of(users.borrower);
        assert!(
            balance == initial_borrower_collateral_asset_balance - collateral_to_deposit,
            "Not transferred from borrower"
        );
        let balance = collateral_asset.balance_of(singleton.contract_address);
        assert!(
            balance == initial_singleton_collateral_asset_balance + collateral_to_deposit,
            "Not transferred to Singleton"
        );

        // debt asset has been transferred from the singleton to the borrower
        let balance = debt_asset.balance_of(users.borrower);
        assert!(balance == initial_borrower_debt_asset_balance + debt_to_draw, "Debt asset not transferred");
        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(
            balance == initial_singleton_debt_asset_balance + liquidity_to_deposit - debt_to_draw,
            "Debt asset not transferred"
        );

        // collateral asset reserve has been updated
        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(
            asset_config.reserve == initial_singleton_collateral_asset_balance + collateral_to_deposit,
            "Collateral not in reserve"
        );

        // debt asset reserve has been updated
        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(
            asset_config.reserve == initial_singleton_debt_asset_balance + liquidity_to_deposit - debt_to_draw,
            "Debt not taken from reserve"
        );

        // position's collateral balance has been updated
        let (position, collateral, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        // assert!(
        //     position.collateral_shares == collateral_to_deposit * SCALE / collateral_scale, "Collateral Shares not
        //     set"
        // );
        assert!(collateral == collateral_to_deposit, "Collateral not set");
        // position's debt balance has been updated (no interest accrued yet)
        assert!(position.nominal_debt == nominal_debt_to_draw, "Nominal Debt not set");
        assert!(debt == nominal_debt_to_draw * debt_scale / SCALE, "Debt not set");
        let collateral_shares = position.collateral_shares;
        // interest accrued should be reflected since time has passed
        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS);
        let (position, collateral, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert!(position.collateral_shares == collateral_shares, "C.S. should not change");
        assert!(collateral == collateral_to_deposit, "Collateral should not change");
        assert!(position.nominal_debt == nominal_debt_to_draw, "Nominal Debt should not change");
        assert!(debt > nominal_debt_to_draw * debt_scale / SCALE, "Debt should accrue due interest");

        // repay debt assets
        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(collateral_to_deposit / 2).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(debt_to_draw / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // check that some debt has been repayed and that some collateral has been withdrawn
        let balance = debt_asset.balance_of(users.borrower);
        assert!(
            balance <= initial_borrower_debt_asset_balance + debt_to_draw - debt_to_draw / 2,
            "Debt asset not transferred"
        );

        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(balance >= liquidity_to_deposit - debt_to_draw + debt_to_draw / 2, "Debt asset not transferred");

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(
            asset_config.reserve >= liquidity_to_deposit - debt_to_draw + debt_to_draw / 2,
            "Repayed assets not in reserve"
        );

        let (position, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        assert!(position.nominal_debt < nominal_debt_to_draw, "Nominal Debt should be less");
        assert!(debt < debt_to_draw, "Debt should be less");

        let balance = collateral_asset.balance_of(users.borrower);
        assert!(
            balance <= initial_borrower_collateral_asset_balance - collateral_to_deposit / 2,
            "Collateral not transferred"
        );

        let balance = collateral_asset.balance_of(singleton.contract_address);
        assert!(balance >= collateral_to_deposit / 2, "Collateral not transferred");

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(asset_config.reserve >= collateral_to_deposit / 2, "Withdrawn assets not in reserve");

        // fund borrower with debt assets to repay interest
        start_cheat_caller_address(debt_asset.contract_address, users.lender);
        debt_asset.transfer(users.borrower, debt_to_draw);
        stop_cheat_caller_address(debt_asset.contract_address);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: Zeroable::zero(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // check that all debt has been repayed and all collateral has been withdrawn
        assert!(
            debt_asset.balance_of(singleton.contract_address) >= liquidity_to_deposit, "Debt asset not transferred"
        );

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(asset_config.reserve >= liquidity_to_deposit, "Repayed assets not in reserve");

        let balance = collateral_asset.balance_of(users.borrower);
        assert!(balance == initial_borrower_collateral_asset_balance, "Collateral not transferred");

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert!(position.collateral_shares == 0, "Collateral Shares should be 0");
        assert!(position.nominal_debt == 0, "Nominal Debt should be 0");

        stop_cheat_block_timestamp_global();
    }

    #[test]
    fn test_modify_position_fees() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, third_asset, third_scale, .. } = config;
        let LendingTerms { collateral_to_deposit, liquidity_to_deposit_third, .. } = terms;

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: (SCALE / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let (asset_config, _) = singleton.asset_config(pool_id, third_asset.contract_address);
        let total_collateral_shares = asset_config.total_collateral_shares;

        let pair = extension.pairs(pool_id, collateral_asset.contract_address, third_asset.contract_address);
        assert(pair.total_collateral_shares > 0 && pair.total_nominal_debt > 0, 'Pair not initialized');

        start_cheat_block_timestamp_global(get_block_timestamp() + YEAR_IN_SECONDS.try_into().unwrap());

        // fund borrower with debt assets to repay interest
        start_cheat_caller_address(third_asset.contract_address, users.lender);
        third_asset.transfer(users.borrower, third_scale);
        stop_cheat_caller_address(third_asset.contract_address);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let (p, _, _) = singleton
            .position(pool_id, third_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert(p.collateral_shares > 0, 'Fee shares not minted');

        // fees increase total_collateral_shares
        let (asset_config, _) = singleton.asset_config(pool_id, third_asset.contract_address);
        assert(asset_config.total_collateral_shares > total_collateral_shares, 'Shares not increased');

        // withdraw fees
        let (_, collateral, _) = singleton
            .position(pool_id, third_asset.contract_address, Zeroable::zero(), extension.contract_address);
        let balance_before = third_asset.balance_of(users.creator);
        extension.claim_fees(pool_id, third_asset.contract_address);
        let balance_after = third_asset.balance_of(users.creator);
        assert(balance_before + collateral == balance_after && balance_before < balance_after, 'Fees not claimed');
    }

    #[test]
    fn test_modify_position_accrue_interest() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, third_asset, third_scale, .. } = config;
        let LendingTerms { collateral_to_deposit, liquidity_to_deposit_third, .. } = terms;

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let (p, _, _) = singleton
            .position(pool_id, third_asset.contract_address, Zeroable::zero(), extension.contract_address);
        let mut collateral_fee_shares_before = p.collateral_shares;

        // Borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: (SCALE / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let (p, _, _) = singleton
            .position(pool_id, third_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert(collateral_fee_shares_before == p.collateral_shares, 'no fees shouldve accrued');

        let (asset_config, _) = singleton.asset_config(pool_id, third_asset.contract_address);
        let total_collateral_shares = asset_config.total_collateral_shares;

        start_cheat_block_timestamp_global(get_block_timestamp() + YEAR_IN_SECONDS.try_into().unwrap());

        // Repay 1

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let (p, _, _) = singleton
            .position(pool_id, third_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert(collateral_fee_shares_before < p.collateral_shares, 'fees shouldve accrued');
        collateral_fee_shares_before = p.collateral_shares;

        let rate_accumulator = singleton.rate_accumulator(pool_id, third_asset.contract_address);

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        assert(
            singleton.rate_accumulator(pool_id, third_asset.contract_address) == rate_accumulator,
            'rate_accumulator changed'
        );

        // fund borrower with debt assets to repay interest
        start_cheat_caller_address(third_asset.contract_address, users.lender);
        third_asset.transfer(users.borrower, third_scale);
        stop_cheat_caller_address(third_asset.contract_address);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let (p, _, _) = singleton
            .position(pool_id, third_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert(collateral_fee_shares_before == p.collateral_shares, 'fees shouldve accrued');

        let (p, _, _) = singleton
            .position(pool_id, third_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert(p.collateral_shares > 0, 'Fee shares not minted');

        // fees increase total_collateral_shares
        let (asset_config, _) = singleton.asset_config(pool_id, third_asset.contract_address);
        assert(asset_config.total_collateral_shares > total_collateral_shares, 'Shares not increased');

        // withdraw fees
        let (_, collateral, _) = singleton
            .position(pool_id, third_asset.contract_address, Zeroable::zero(), extension.contract_address);
        let balance_before = third_asset.balance_of(users.creator);
        extension.claim_fees(pool_id, third_asset.contract_address);

        let balance_after = third_asset.balance_of(users.creator);
        assert(balance_before + collateral == balance_after && balance_before < balance_after, 'Fees not claimed');
    }

    #[test]
    fn test_modify_position_zero_asset() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: Zeroable::zero(),
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "zero-debt")]
    fn test_modify_position_zero_asset_borrow() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: Zeroable::zero(),
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: (SCALE / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "not-collateralized")]
    fn test_modify_position_no_pair() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, third_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, liquidity_to_deposit_third, .. } = terms;

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: Zeroable::zero(),
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let ltv_config = singleton.ltv_config(pool_id, third_asset.contract_address, collateral_asset.contract_address);
        assert(ltv_config.max_ltv == 0, 'Pair should not exist');

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: (SCALE / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }
}
