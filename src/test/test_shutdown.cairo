#[cfg(test)]
mod TestShutdown {
    use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, CheatTarget};
    use starknet::{contract_address_const, get_block_timestamp};
    use vesu::vendor::erc20::ERC20ABIDispatcherTrait;
    use vesu::{
        units::{SCALE, SCALE_128, DAY_IN_SECONDS},
        singleton::{
            ISingletonDispatcherTrait, Amount, AmountType, AmountDenomination, ModifyPositionParams,
            LiquidatePositionParams,
        },
        test::{
            mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
            setup::{setup, setup_env, setup_pool, test_interest_rate_model, TestConfig, LendingTerms},
        },
        extension::{
            default_extension::{IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait, InterestRateModel},
            components::position_hooks::{ShutdownMode}
        }
    };

    #[test]
    // #[should_panic(expected: "in-recovery")]
    #[should_panic(expected: ('in-recovery',))]
    fn test_recovery_mode_from_none() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 * 5 / 10);

        // User 1

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 10).into(),
            },
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: (SCALE / 5_000).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_recovery_mode_made_safer() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // User 2

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount { amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into() },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: ('in-recovery',))]
    fn test_recovery_mode_decreasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // User 1

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 10).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(collateral_to_deposit / 1000).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: ('in-recovery',))]
    fn test_recovery_mode_increasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 * 5 / 10);

        // User 1

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 10).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: (nominal_debt_to_draw / 100).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_subscription_mode_decreasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        start_warp(CheatTarget::All, violation_timestamp + shutdown_config.recovery_period + 1);

        // Subscription
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // User 2

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: -1_u256.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: ('in-subscription',))]
    fn test_subscription_mode_increasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        start_warp(CheatTarget::All, violation_timestamp + shutdown_config.recovery_period + 1);

        // Subscription
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // User 2

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: SCALE.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: ('in-subscription',))]
    fn test_subscription_mode_decreasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        start_warp(CheatTarget::All, violation_timestamp + shutdown_config.recovery_period + 1);

        // Subscription
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        mock_pragma_oracle.set_price(19514442401534788, SCALE_128);

        // User 2

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: -(SCALE / 1000).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: ('in-subscription',))]
    fn test_subscription_mode_increasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        start_warp(CheatTarget::All, violation_timestamp + shutdown_config.recovery_period + 1);

        // Subscription
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        mock_pragma_oracle.set_price(19514442401534788, SCALE_128);

        // User 2

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: (nominal_debt_to_draw / 10).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_redemption_mode_decreasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_warp(CheatTarget::All, violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_prank(CheatTarget::One(debt_asset.contract_address), users.lender);
        debt_asset.transfer(users.borrower, debt_scale);
        stop_prank(CheatTarget::One(debt_asset.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_warp(
            CheatTarget::All,
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: ('in-redemption',))]
    fn test_redemption_mode_increasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_warp(CheatTarget::All, violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_prank(CheatTarget::One(debt_asset.contract_address), users.lender);
        debt_asset.transfer(users.borrower, debt_scale);
        stop_prank(CheatTarget::One(debt_asset.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_warp(
            CheatTarget::All,
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        mock_pragma_oracle.set_price(19514442401534788, SCALE_128);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Native, value: SCALE.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: ('in-redemption',))]
    fn test_redemption_mode_decreasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_warp(CheatTarget::All, violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_prank(CheatTarget::One(debt_asset.contract_address), users.lender);
        debt_asset.transfer(users.borrower, debt_scale);
        stop_prank(CheatTarget::One(debt_asset.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: (nominal_debt_to_draw / 10).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_warp(
            CheatTarget::All,
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        mock_pragma_oracle.set_price(19514442401534788, SCALE_128);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: -(nominal_debt_to_draw / 10).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: ('in-redemption',))]
    fn test_redemption_mode_increasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_warp(CheatTarget::All, violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_prank(CheatTarget::One(debt_asset.contract_address), users.lender);
        debt_asset.transfer(users.borrower, debt_scale);
        stop_prank(CheatTarget::One(debt_asset.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_warp(
            CheatTarget::All,
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        mock_pragma_oracle.set_price(19514442401534788, SCALE_128);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: (nominal_debt_to_draw / 10).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    // Scenario:
    // 1. pair 1 transitions into recovery
    // 2. pair 2 transitions into recovery
    // 3. pair 1 transitions out of recovery
    // -> pool should still be in recovery mode
    #[test]
    fn test_recovery_mode_complex() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit,
        collateral_to_deposit,
        nominal_debt_to_draw,
        liquidity_to_deposit_third,
        .. } =
            terms;

        // User 1

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // User 2

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
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: nominal_debt_to_draw.into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // Pair 1: None -> Recovery
        // warp to non zero block timestamp first
        start_warp(CheatTarget::All, get_block_timestamp() + 1);
        // oracle failure in pair 1 --> recovery
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_num_sources_aggregated(19514442401534788, 1);
        // update shutdown mode
        extension.update_shutdown_status(pool_id, debt_asset.contract_address, collateral_asset.contract_address);

        let status = extension.shutdown_status(pool_id, debt_asset.contract_address, collateral_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');
        let violation_timestamp_pair_1 = extension
            .violation_timestamp_for_pair(pool_id, debt_asset.contract_address, collateral_asset.contract_address);
        assert(violation_timestamp_pair_1 != 0, 'violation-timestamp-not-set');
        assert(
            violation_timestamp_pair_1 == extension.oldest_violation_timestamp(pool_id),
            'violation-timestamp-not-oldest'
        );
        assert(
            extension.violation_timestamp_count(pool_id, violation_timestamp_pair_1) == 1, 'violation-counter-not-incr'
        );

        // Pair 2: None -> Recovery
        // undercollateraliztion in pair 2 --> recovery
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 / 41 / 10);
        // warp such that next violation is at a different timestamp
        start_warp(CheatTarget::All, get_block_timestamp() + 1);
        // update shutdown mode
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');
        let violation_timestamp_pair_2 = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(violation_timestamp_pair_1 != violation_timestamp_pair_2, 'violation-timestamp-not-set');
        assert(violation_timestamp_pair_2 != 0, 'violation-timestamp-not-set');
        assert(
            violation_timestamp_pair_1 == extension.oldest_violation_timestamp(pool_id),
            'violation-timestamp-not-oldest'
        );
        assert(
            extension.violation_timestamp_count(pool_id, violation_timestamp_pair_2) == 1, 'violation-counter-not-incr'
        );

        // Pair 3: None -> Recovery
        // undercollateraliztion in pair 3 --> recovery
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(18669995996566340, SCALE_128 / 41 / 10);
        // update shutdown mode
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, third_asset.contract_address);

        let status = extension
            .shutdown_status(pool_id, collateral_asset.contract_address, third_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');
        let violation_timestamp_pair_3 = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, third_asset.contract_address);
        assert(violation_timestamp_pair_1 != violation_timestamp_pair_3, 'violation-timestamp-not-set');
        assert(violation_timestamp_pair_3 != 0, 'violation-timestamp-not-set');
        assert(
            violation_timestamp_pair_1 == extension.oldest_violation_timestamp(pool_id),
            'violation-timestamp-not-oldest'
        );
        assert(violation_timestamp_pair_2 == violation_timestamp_pair_3, 'violation-timestamps-not-e');
        assert(
            extension.violation_timestamp_count(pool_id, violation_timestamp_pair_3) == 2, 'violation-counter-not-incr'
        );

        // Pair 1: Recovery --> None
        start_warp(CheatTarget::All, get_block_timestamp() + 1);
        // oracle recovery in pair 1 --> normal
        mock_pragma_oracle.set_num_sources_aggregated(19514442401534788, 2);
        // update shutdown mode
        extension.update_shutdown_status(pool_id, debt_asset.contract_address, collateral_asset.contract_address);

        let status = extension.shutdown_status(pool_id, debt_asset.contract_address, collateral_asset.contract_address);
        // should still be in recovery because of pair 2
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');
        let violation_timestamp_pair_1 = extension
            .violation_timestamp_for_pair(pool_id, debt_asset.contract_address, collateral_asset.contract_address);
        assert(violation_timestamp_pair_1 == 0, 'violation-timestamp-not-reset');
        assert(
            violation_timestamp_pair_2 == extension.oldest_violation_timestamp(pool_id),
            'oldest-violation-t-not-updated'
        );
        assert(
            extension.violation_timestamp_count(pool_id, violation_timestamp_pair_1) == 0, 'violation-counter-not-decr'
        );
    }

    #[test]
    // #[should_panic(expected: ('in-subscription',))]
    fn test_unsafe_rate_accumulator() {
        let current_time = 1707509060;
        start_warp(CheatTarget::All, current_time);

        let model = InterestRateModel {
            min_target_utilization: 100_000,
            max_target_utilization: 100_000,
            target_utilization: 100_000,
            min_full_utilization_rate: 100824704600, // 300% per year
            max_full_utilization_rate: 100824704600,
            zero_utilization_rate: 100824704600,
            rate_half_life: 172_800,
            target_rate_percent: SCALE,
        };

        let (singleton, extension, config, users, terms) = setup_pool(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), true, Option::Some(model)
        );

        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        // User 1

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

        // User 2

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

        let current_time = current_time + (360 * DAY_IN_SECONDS);
        start_warp(CheatTarget::All, current_time);

        let config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        assert!(config.last_rate_accumulator == SCALE);
        let config = singleton.asset_configs(pool_id, debt_asset.contract_address);
        assert!(config.last_rate_accumulator == SCALE);

        let context = singleton
            .context(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert!(context.collateral_asset_config.last_rate_accumulator > 18 * SCALE);
        assert!(context.debt_asset_config.last_rate_accumulator > 18 * SCALE);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        assert!(config.last_rate_accumulator == SCALE);
        let config = singleton.asset_configs(pool_id, debt_asset.contract_address);
        assert!(config.last_rate_accumulator == SCALE);

        stop_warp(CheatTarget::All);
    }
}
