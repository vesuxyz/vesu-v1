#[cfg(test)]
mod TestLiquidatePosition {
    use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, CheatTarget};
    use starknet::{contract_address_const, get_block_timestamp, get_caller_address};
    use vesu::vendor::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use vesu::{
        units::{SCALE, SCALE_128},
        data_model::{
            Amount, AmountType, AmountDenomination, ModifyPositionParams, LiquidatePositionParams, AssetConfig,
            Position, Context
        },
        singleton::ISingletonDispatcherTrait,
        test::{
            mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
            setup::{setup, TestConfig, LendingTerms, COLL_PRAGMA_KEY, DEBT_PRAGMA_KEY},
            mock_asset::{IMintableDispatcherTrait, IMintableDispatcher},
        },
        extension::{
            default_extension::{IDefaultExtensionDispatcherTrait},
            components::position_hooks::{LiquidationData, LiquidationConfig},
            interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
        },
    };

    #[test]
    #[should_panic(expected: "caller-not-singleton")]
    fn test_before_liquidate_position_caller_not_singleton() {
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
            .before_liquidate_position(context, data: ArrayTrait::new().span(), caller: get_caller_address());
    }

    // before_liquidate_position: invalid-liquidation-data

    #[test]
    #[should_panic(expected: "caller-not-singleton")]
    fn test_after_liquidate_position_caller_not_singleton() {
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
            .after_liquidate_position(
                context,
                Default::default(),
                Default::default(),
                Default::default(),
                Default::default(),
                Default::default(),
                data: ArrayTrait::new().span(),
                caller: get_caller_address()
            );
    }

    #[test]
    #[should_panic(expected: "not-undercollateralized")]
    fn test_liquidate_position_not_undercollateralized() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        let (_, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(collateralized, "Not collateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "emergency-mode")]
    fn test_liquidate_position_invalid_oracle_1() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 1);

        let (_, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "emergency-mode")]
    fn test_liquidate_position_invalid_oracle_2() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);
        mock_pragma_oracle.set_num_sources_aggregated(DEBT_PRAGMA_KEY, 1);

        let (_, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: 'invalid-liquidation-data')]
    fn test_liquidate_position_invalid_liquidation_data() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

        let (position_before, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == position_before.collateral_shares / 2, 'not half of collateral shares');
        assert(position.nominal_debt == position_before.nominal_debt / 2, 'not half of nominal debt');

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);

        assert(position.collateral_shares == 0, 'should not have shares');
    }

    #[test]
    fn test_liquidate_position_partial_no_bad_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

        let (position_before, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == position_before.collateral_shares / 2, 'not half of collateral shares');
        assert(position.nominal_debt == position_before.nominal_debt / 2, 'not half of nominal debt');

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);

        assert(position.collateral_shares == 0, 'should not have shares');
    }

    // #[test]
    // fn test_liquidate_position_partial_floor() {
    //     let (singleton, extension, config, users, terms) = setup();
    //     let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
    //     let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

    //     // LENDER

    //     // deposit collateral which is later borrowed by the borrower
    //     let params = ModifyPositionParams {
    //         pool_id,
    //         collateral_asset: debt_asset.contract_address,
    //         debt_asset: collateral_asset.contract_address,
    //         user: users.lender,
    //         collateral: Amount {
    //             amount_type: AmountType::Delta,
    //             denomination: AmountDenomination::Assets,
    //             value: liquidity_to_deposit.into(),
    //         },
    //         debt: Default::default(),
    //         data: ArrayTrait::new().span()
    //     };

    //     start_prank(CheatTarget::One(singleton.contract_address), users.lender);
    //     singleton.modify_position(params);
    //     stop_prank(CheatTarget::One(singleton.contract_address));

    //     // BORROWER

    //     let params = ModifyPositionParams {
    //         pool_id,
    //         collateral_asset: collateral_asset.contract_address,
    //         debt_asset: debt_asset.contract_address,
    //         user: users.borrower,
    //         collateral: Amount {
    //             amount_type: AmountType::Target,
    //             denomination: AmountDenomination::Assets,
    //             value: collateral_to_deposit.into(),
    //         },
    //         debt: Amount {
    //             amount_type: AmountType::Target,
    //             denomination: AmountDenomination::Native,
    //             value: nominal_debt_to_draw.into(),
    //         },
    //         data: ArrayTrait::new().span()
    //     };

    //     start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
    //     singleton.modify_position(params);
    //     stop_prank(CheatTarget::One(singleton.contract_address));

    //     start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
    //     singleton.set_asset_parameter(pool_id, collateral_asset.contract_address, 'floor', SCALE);
    //     stop_prank(CheatTarget::One(singleton.contract_address));

    //     // LIQUIDATOR

    //     // reduce oracle price
    //     let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
    //     mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

    //     let (_, _, debt) = singleton
    //         .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

    //     let (collateralized, _, _) = singleton
    //         .check_collateralization(
    //             pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
    //         );
    //     assert!(!collateralized, "Not undercollateralized");

    //     let mut liquidation_data: Array<felt252> = ArrayTrait::new();
    //     LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

    //     let params = LiquidatePositionParams {
    //         pool_id,
    //         collateral_asset: collateral_asset.contract_address,
    //         debt_asset: debt_asset.contract_address,
    //         user: users.borrower,
    //         receive_as_shares: false,
    //         data: liquidation_data.span()
    //     };

    //     start_prank(CheatTarget::One(singleton.contract_address), users.lender);
    //     singleton.liquidate_position(params);
    //     stop_prank(CheatTarget::One(singleton.contract_address));

    //     let (position, _, _) = singleton
    //         .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
    //     assert(position.collateral_shares == 0, 'no shares should be remaining');
    //     assert(position.nominal_debt == 0, 'should debt should be remaining');

    //     let (position, _, _) = singleton
    //         .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);

    //     assert(position.collateral_shares == 0, 'should not have shares');
    // }

    // #[test]
    // fn test_liquidate_position_partial_no_bad_debt_discounted() {
    //     let (singleton, extension, config, users, terms) = setup();
    //     let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
    //     let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

    //     start_prank(CheatTarget::One(extension.contract_address), users.creator);
    //     extension
    //         .set_asset_parameter(pool_id, collateral_asset.contract_address, 'liquidation_factor', 90 * SCALE / 100);
    //     stop_prank(CheatTarget::One(extension.contract_address));

    //     // LENDER

    //     // deposit collateral which is later borrowed by the borrower
    //     let params = ModifyPositionParams {
    //         pool_id,
    //         collateral_asset: debt_asset.contract_address,
    //         debt_asset: collateral_asset.contract_address,
    //         user: users.lender,
    //         collateral: Amount {
    //             amount_type: AmountType::Delta,
    //             denomination: AmountDenomination::Assets,
    //             value: liquidity_to_deposit.into(),
    //         },
    //         debt: Default::default(),
    //         data: ArrayTrait::new().span()
    //     };

    //     start_prank(CheatTarget::One(singleton.contract_address), users.lender);
    //     singleton.modify_position(params);
    //     stop_prank(CheatTarget::One(singleton.contract_address));

    //     // BORROWER

    //     let params = ModifyPositionParams {
    //         pool_id,
    //         collateral_asset: collateral_asset.contract_address,
    //         debt_asset: debt_asset.contract_address,
    //         user: users.borrower,
    //         collateral: Amount {
    //             amount_type: AmountType::Target,
    //             denomination: AmountDenomination::Assets,
    //             value: collateral_to_deposit.into(),
    //         },
    //         debt: Amount {
    //             amount_type: AmountType::Target,
    //             denomination: AmountDenomination::Native,
    //             value: nominal_debt_to_draw.into(),
    //         },
    //         data: ArrayTrait::new().span()
    //     };

    //     start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
    //     singleton.modify_position(params);
    //     stop_prank(CheatTarget::One(singleton.contract_address));

    //     // LIQUIDATOR

    //     // reduce oracle price
    //     let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
    //     mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

    //     let (position_before, _, debt) = singleton
    //         .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

    //     let mut liquidation_data: Array<felt252> = ArrayTrait::new();
    //     LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

    //     let params = LiquidatePositionParams {
    //         pool_id,
    //         collateral_asset: collateral_asset.contract_address,
    //         debt_asset: debt_asset.contract_address,
    //         user: users.borrower,
    //         receive_as_shares: false,
    //         data: liquidation_data.span()
    //     };

    //     start_prank(CheatTarget::One(singleton.contract_address), users.lender);
    //     singleton.liquidate_position(params);
    //     stop_prank(CheatTarget::One(singleton.contract_address));

    //     let (position, _, _) = singleton
    //         .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
    //     assert(position.collateral_shares < position_before.collateral_shares / 2, 'not half of collateral shares');
    //     assert(position.nominal_debt == position_before.nominal_debt / 2, 'not half of nominal debt');

    //     let (position, _, _) = singleton
    //         .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);

    //     assert(position.collateral_shares == 0, 'should not have shares');
    // }

    #[test]
    fn test_liquidate_position_partial_no_bad_debt_in_shares() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

        let (position_before, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: true,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == position_before.collateral_shares / 2, 'not half of collateral shares');
        assert(position.nominal_debt == position_before.nominal_debt / 2, 'not half of nominal debt');

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);

        assert(position.collateral_shares == position_before.collateral_shares / 2, 'not half of collateral shares');
    }

    #[test]
    fn test_liquidate_position_partial_bad_debt_2() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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
                value: (nominal_debt_to_draw + nominal_debt_to_draw / 10).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let reserve_before = asset_config.reserve;

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

        let (position_before, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

        // print debt asset balance of liquidator
        let balance_before = ERC20ABIDispatcher { contract_address: debt_asset.contract_address }
            .balance_of(users.lender);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let balance_after = ERC20ABIDispatcher { contract_address: debt_asset.contract_address }
            .balance_of(users.lender);
        let balance_delta = balance_before - balance_after;
        assert(balance_delta <= debt / 2, 'not more than specified');

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        assert(position.collateral_shares < position_before.collateral_shares / 2, 'not lt half collateral shares');
        assert(position.nominal_debt < position_before.nominal_debt / 2, 'not lt half of nominal debt');

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);

        assert(reserve_before + debt / 2 == asset_config.reserve, 'reserve should eq');
        assert(reserve_before + balance_delta == asset_config.reserve, 'covered debt added to reserve');
    }

    #[test]
    #[should_panic(expected: "less-than-min-collateral")]
    fn test_liquidate_position_partial_insufficient_collateral_released() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

        let (position_before, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: collateral_to_deposit.into(), debt_to_repay: debt / 2 }
            .serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == position_before.collateral_shares / 2, 'not half of collateral shares');
        assert(position.nominal_debt == position_before.nominal_debt / 2, 'not half of nominal debt');
    }

    #[test]
    fn test_liquidate_position_partial_bad_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let reserve_before = asset_config.reserve;

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

        let (_, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert(reserve_before == asset_config.reserve, 'reserve should be the same');
    }

    #[test]
    fn test_liquidate_position_full_bad_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let reserve_before = asset_config.reserve;

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 4);

        let (_, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert(reserve_before > asset_config.reserve, 'reserve should be the same');
    }

    #[test]
    fn test_liquidate_position_full_no_bad_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let reserve_before = asset_config.reserve;

        // BORROWER

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 1 / 2);

        let (_, _, debt) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert(reserve_before == asset_config.reserve, 'reserve should be the same');
    }

    #[test]
    fn test_liquidate_position_scenario_1_full_liquidation() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, collateral_scale, debt_scale, .. } = config;

        let liquidity_to_deposit = 100 * debt_scale;
        let collateral = 80 * collateral_scale;
        let debt = 10 * debt_scale;
        let collateral_price = 1 * SCALE;
        let debt_price = 10 * SCALE;
        let liquidation_factor = 90 * SCALE / 100;
        let min_collateral_to_receive = collateral;
        let debt_to_repay = (((collateral * collateral_price / SCALE) * liquidation_factor) / debt_price)
            * debt_scale
            / collateral_scale;

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .set_liquidation_config(
                pool_id,
                collateral_asset.contract_address,
                debt_asset.contract_address,
                LiquidationConfig { liquidation_factor: liquidation_factor.try_into().unwrap() }
            );
        stop_prank(CheatTarget::One(extension.contract_address));

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.lender);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, 2000);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, debt);
        IMintableDispatcher { contract_address: collateral_asset.contract_address }.mint(users.borrower, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: collateral.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: debt.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.borrower);
        collateral_asset.approve(singleton.contract_address, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let collateral_reserve_before = asset_config.reserve;

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let debt_reserve_before = asset_config.reserve;

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(DEBT_PRAGMA_KEY, debt_price.try_into().unwrap());

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive, debt_to_repay }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        let response = singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        assert(response.collateral_delta.abs == collateral, 'collateral_to_receive neq');
        assert(response.debt_delta.abs == debt, 'debt_to_repay neq');
        assert(response.bad_debt != 0, 'bad_debt neq');

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(collateral_reserve_before - collateral == asset_config.reserve, "collateral reserve should decrease");

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(debt_reserve_before + debt - response.bad_debt == asset_config.reserve, "debt reserve should increase");
    }

    #[test]
    fn test_liquidate_position_scenario_2_full_liquidation() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, collateral_scale, debt_scale, .. } = config;

        let liquidity_to_deposit = 100 * debt_scale;
        let collateral = 80 * collateral_scale;
        let debt = 10 * debt_scale;
        let debt_price = 10 * SCALE;
        let liquidation_factor = 90 * SCALE / 100;
        let min_collateral_to_receive = collateral;
        let debt_to_repay = debt;

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .set_liquidation_config(
                pool_id,
                collateral_asset.contract_address,
                debt_asset.contract_address,
                LiquidationConfig { liquidation_factor: liquidation_factor.try_into().unwrap() }
            );
        stop_prank(CheatTarget::One(extension.contract_address));

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.lender);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, 2000);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, debt);
        IMintableDispatcher { contract_address: collateral_asset.contract_address }.mint(users.borrower, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: collateral.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: debt.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.borrower);
        collateral_asset.approve(singleton.contract_address, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let collateral_reserve_before = asset_config.reserve;

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let debt_reserve_before = asset_config.reserve;

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(DEBT_PRAGMA_KEY, debt_price.try_into().unwrap());

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive, debt_to_repay }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        let response = singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        assert(response.collateral_delta.abs == collateral, 'collateral_to_receive neq');
        assert(response.debt_delta.abs == debt, 'debt_to_repay neq');
        assert(response.bad_debt != 0, 'bad_debt neq');

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(collateral_reserve_before - collateral == asset_config.reserve, "collateral reserve should decrease");

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(debt_reserve_before + debt - response.bad_debt == asset_config.reserve, "debt reserve should increase");
    }

    #[test]
    fn test_liquidate_position_scenario_3_full_liquidation() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, collateral_scale, debt_scale, .. } = config;

        let liquidity_to_deposit = 100 * debt_scale;
        let collateral = 80 * collateral_scale;
        let debt = 10 * debt_scale;
        let debt_price = 10 * SCALE;
        let liquidation_factor = 90 * SCALE / 100;
        let min_collateral_to_receive = collateral;
        let debt_to_repay = debt * 90 / 100;

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .set_liquidation_config(
                pool_id,
                collateral_asset.contract_address,
                debt_asset.contract_address,
                LiquidationConfig { liquidation_factor: liquidation_factor.try_into().unwrap() }
            );
        stop_prank(CheatTarget::One(extension.contract_address));

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.lender);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, 2000);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, debt);
        IMintableDispatcher { contract_address: collateral_asset.contract_address }.mint(users.borrower, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: collateral.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: debt.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.borrower);
        collateral_asset.approve(singleton.contract_address, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let collateral_reserve_before = asset_config.reserve;

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let debt_reserve_before = asset_config.reserve;

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(DEBT_PRAGMA_KEY, debt_price.try_into().unwrap());

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive, debt_to_repay }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        let response = singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        assert(response.collateral_delta.abs == collateral, 'collateral_to_receive neq');
        assert(response.debt_delta.abs == debt, 'debt_to_repay neq');
        assert(response.bad_debt != 0, 'bad_debt neq');

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(collateral_reserve_before - collateral == asset_config.reserve, "collateral reserve should decrease");

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(debt_reserve_before + debt - response.bad_debt == asset_config.reserve, "debt reserve should increase");
    }

    #[test]
    fn test_liquidate_position_scenario_4_full_liquidation() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, collateral_scale, debt_scale, .. } = config;

        let liquidity_to_deposit = 100 * debt_scale;
        let collateral = 80 * collateral_scale;
        let debt = 10 * debt_scale;
        let debt_price = 10 * SCALE;
        let liquidation_factor = 90 * SCALE / 100;
        let min_collateral_to_receive = collateral;
        let debt_to_repay = debt * 2;

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .set_liquidation_config(
                pool_id,
                collateral_asset.contract_address,
                debt_asset.contract_address,
                LiquidationConfig { liquidation_factor: liquidation_factor.try_into().unwrap() }
            );
        stop_prank(CheatTarget::One(extension.contract_address));

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.lender);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, 2000);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, debt);
        IMintableDispatcher { contract_address: collateral_asset.contract_address }.mint(users.borrower, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: collateral.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: debt.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.borrower);
        collateral_asset.approve(singleton.contract_address, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let collateral_reserve_before = asset_config.reserve;

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let debt_reserve_before = asset_config.reserve;

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(DEBT_PRAGMA_KEY, debt_price.try_into().unwrap());

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive, debt_to_repay }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        let response = singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        assert(response.collateral_delta.abs == collateral, 'collateral_to_receive neq');
        assert(response.debt_delta.abs == debt, 'debt_to_repay neq');
        assert(response.bad_debt != 0, 'bad_debt neq');

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(collateral_reserve_before - collateral == asset_config.reserve, "collateral reserve should decrease");

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(debt_reserve_before + debt - response.bad_debt == asset_config.reserve, "debt reserve should increase");
    }

    #[test]
    fn test_liquidate_position_scenario_5_partial_liquidation() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, collateral_scale, debt_scale, .. } = config;

        let liquidity_to_deposit = 100 * debt_scale;
        let collateral = 80 * collateral_scale;
        let debt = 10 * debt_scale;
        let collateral_price = 1 * SCALE;
        let debt_price = 10 * SCALE;
        let liquidation_factor = 90 * SCALE / 100;
        let min_collateral_to_receive = collateral / 2;
        let debt_to_repay = (((collateral * collateral_price / collateral_scale) * liquidation_factor / SCALE)
            * debt_scale)
            / (debt_price * 2);

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .set_liquidation_config(
                pool_id,
                collateral_asset.contract_address,
                debt_asset.contract_address,
                LiquidationConfig { liquidation_factor: liquidation_factor.try_into().unwrap() }
            );
        stop_prank(CheatTarget::One(extension.contract_address));

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.lender);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, 2000);
        IMintableDispatcher { contract_address: debt_asset.contract_address }.mint(users.lender, debt);
        IMintableDispatcher { contract_address: collateral_asset.contract_address }.mint(users.borrower, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: collateral.into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: debt.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(collateral_asset.contract_address), users.borrower);
        collateral_asset.approve(singleton.contract_address, collateral);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        let collateral_reserve_before = asset_config.reserve;

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let debt_reserve_before = asset_config.reserve;

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(DEBT_PRAGMA_KEY, debt_price.try_into().unwrap());

        let (collateralized, _, _) = singleton
            .check_collateralization(
                pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower
            );
        assert!(!collateralized, "Not undercollateralized");

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive, debt_to_repay }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        let response = singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        assert(response.collateral_delta.abs == collateral / 2, 'collateral_to_receive neq');
        assert(response.debt_delta.abs == debt / 2, 'debt_to_repay neq');
        assert(response.bad_debt != 0, 'bad_debt neq');

        let (position, p_collateral, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        assert!(p_collateral == (collateral / 2), "collateral should be half");
        assert!(position.nominal_debt == (debt * SCALE) / (2 * debt_scale), "debt shares should be half");

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(
            collateral_reserve_before - (collateral / 2) == asset_config.reserve, "collateral reserve should decrease"
        );

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(
            debt_reserve_before + (debt / 2) - response.bad_debt == asset_config.reserve, "debt reserve should increase"
        );
    }
}
