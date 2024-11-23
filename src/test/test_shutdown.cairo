#[cfg(test)]
mod TestShutdown {
    use core::num::traits::Bounded;
    use snforge_std::{
        start_cheat_caller_address, stop_cheat_caller_address, start_cheat_block_timestamp_global,
        stop_cheat_block_timestamp_global
    };
    use starknet::{contract_address_const, get_block_timestamp};
    use vesu::{
        units::{SCALE, SCALE_128, DAY_IN_SECONDS},
        data_model::{
            UnsignedAmount, Amount, AmountDenomination, AmountType, Position, ModifyPositionParams,
            LiquidatePositionParams, TransferPositionParams
        },
        singleton::ISingletonDispatcherTrait,
        test::{
            mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
            setup::{
                setup, setup_env, setup_pool, test_interest_rate_config, TestConfig, LendingTerms, COLL_PRAGMA_KEY,
                DEBT_PRAGMA_KEY, THIRD_PRAGMA_KEY
            },
        },
        extension::{
            default_extension_po::{IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait, InterestRateConfig},
            components::position_hooks::{ShutdownMode}
        },
        v_token::{IERC4626Dispatcher, IERC4626DispatcherTrait, IVTokenDispatcher, IVTokenDispatcherTrait},
        vendor::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait}
    };

    #[test]
    #[should_panic(expected: "in-recovery")]
    fn test_recovery_mode_from_none() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 5 / 10);

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    fn test_recovery_mode_made_safer() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "in-recovery")]
    fn test_recovery_mode_decreasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "in-recovery")]
    fn test_recovery_mode_increasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 * 5 / 10);

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    fn test_subscription_mode_decreasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.max_deposit(Zeroable::zero()) > 0, 'max_deposit neq');
        assert(v_token.preview_deposit(10000000) > 0, 'preview_deposit neq');
        assert(v_token.max_mint(Zeroable::zero()) > 0, 'max_mint neq');
        assert(v_token.preview_mint(100000000) > 0, 'preview_mint neq');
        assert(v_token.max_withdraw(users.lender) == 0, 'max_withdraw neq');
        assert(v_token.preview_withdraw(10000000) == 0, 'preview_withdraw neq');
        assert(v_token.max_redeem(users.lender) == 0, 'max_redeem neq');
        assert(v_token.preview_redeem(10000000) == 0, 'preview_redeem neq');

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "in-subscription")]
    fn test_subscription_mode_increasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);

        // Subscription
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.max_deposit(Zeroable::zero()) == 0, 'max_deposit neq');
        assert(v_token.preview_deposit(10000000) == 0, 'preview_deposit neq');
        assert(v_token.max_mint(Zeroable::zero()) == 0, 'max_mint neq');
        assert(v_token.preview_mint(100000000) == 0, 'preview_mint neq');
        assert(v_token.max_withdraw(users.lender) == 0, 'max_withdraw neq');
        assert(v_token.preview_withdraw(10000000) == 0, 'preview_withdraw neq');
        assert(v_token.max_redeem(users.lender) == 0, 'max_redeem neq');
        assert(v_token.preview_redeem(10000000) == 0, 'preview_redeem neq');

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "in-subscription")]
    fn test_subscription_mode_decreasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);

        // Subscription
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128);

        // User 2

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: -1000_0000000000.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "in-subscription")]
    fn test_subscription_mode_increasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);

        // Subscription
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    fn test_redemption_mode_decreasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_cheat_caller_address(debt_asset.contract_address, users.lender);
        debt_asset.transfer(users.borrower, debt_scale);
        stop_cheat_caller_address(debt_asset.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(
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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "in-redemption")]
    fn test_redemption_mode_increasing_collateral() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_cheat_caller_address(debt_asset.contract_address, users.lender);
        debt_asset.transfer(users.borrower, debt_scale);
        stop_cheat_caller_address(debt_asset.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128);

        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };

        start_cheat_caller_address(v_token.contract_address, extension.contract_address);
        IVTokenDispatcher { contract_address: v_token.contract_address }.mint_v_token(users.borrower, 1000_0000000000);
        stop_cheat_caller_address(v_token.contract_address);

        assert(v_token.max_deposit(Zeroable::zero()) == 0, 'max_deposit neq');
        assert(v_token.preview_deposit(1000_0000000000) == 0, 'preview_deposit neq');
        assert(v_token.max_mint(Zeroable::zero()) == 0, 'max_mint neq');
        assert(v_token.preview_mint(1000_0000000000) == 0, 'preview_mint neq');
        assert(v_token.max_withdraw(users.borrower) > 0, 'max_withdraw neq');
        assert(v_token.preview_withdraw(1000_0000000000) > 0, 'preview_withdraw neq');
        assert(v_token.max_redeem(users.borrower) > 0, 'max_redeem neq');
        assert(v_token.preview_redeem(1000_0000000000) > 0, 'preview_redeem neq');

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "in-redemption")]
    fn test_redemption_mode_decreasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_cheat_caller_address(debt_asset.contract_address, users.lender);
        debt_asset.transfer(users.borrower, debt_scale);
        stop_cheat_caller_address(debt_asset.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "in-redemption")]
    fn test_redemption_mode_increasing_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_cheat_caller_address(debt_asset.contract_address, users.lender);
        debt_asset.transfer(users.borrower, debt_scale);
        stop_cheat_caller_address(debt_asset.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    // non-zero-collateral-shares

    #[test]
    #[should_panic(expected: "non-zero-debt")]
    fn test_redemption_mode_non_zero_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: -1000_0000000000.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    fn test_redemption_mode_max_utilization() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, collateral_scale, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        let borrower = extension.contract_address;

        start_cheat_caller_address(collateral_asset.contract_address, users.lender);
        collateral_asset.transfer(borrower, collateral_to_deposit * 2);
        stop_cheat_caller_address(collateral_asset.contract_address);

        start_cheat_caller_address(collateral_asset.contract_address, borrower);
        collateral_asset.approve(singleton.contract_address, Bounded::<u256>::MAX);
        stop_cheat_caller_address(collateral_asset.contract_address);
        start_cheat_caller_address(debt_asset.contract_address, borrower);
        debt_asset.approve(singleton.contract_address, Bounded::<u256>::MAX);
        stop_cheat_caller_address(debt_asset.contract_address);

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_parameter(pool_id, collateral_asset.contract_address, 'max_utilization', SCALE / 2);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // User 2

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: borrower,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: (nominal_debt_to_draw / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        //

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 11).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(violation_timestamp + shutdown_config.recovery_period + 1);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // fund borrower with debt assets to repay interest
        start_cheat_caller_address(debt_asset.contract_address, users.lender);
        debt_asset.transfer(borrower, collateral_scale);
        stop_cheat_caller_address(debt_asset.contract_address);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        // third user has to borrow from same pair to increase utilization

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_parameter(pool_id, collateral_asset.contract_address, 'max_utilization', SCALE / 100);
        stop_cheat_caller_address(singleton.contract_address);

        let shutdown_config = extension.shutdown_config(pool_id);
        let violation_timestamp = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        start_cheat_block_timestamp_global(
            violation_timestamp + shutdown_config.recovery_period + shutdown_config.subscription_period + 1
        );
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(asset_config.reserve).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    // Scenario:
    // 1. pair 1 transitions into recovery
    // 2. pair 2 transitions into recovery
    // 3. pair 1 transitions out of recovery
    // -> pool should still be in recovery mode
    #[test]
    fn test_recovery_mode_complex() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit,
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
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Pair 1: None -> Recovery
        // warp to non zero block timestamp first
        start_cheat_block_timestamp_global(get_block_timestamp() + 1);
        // oracle failure in pair 1 --> recovery
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 1);
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
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);
        // warp such that next violation is at a different timestamp
        start_cheat_block_timestamp_global(get_block_timestamp() + 1);
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
        mock_pragma_oracle.set_price(THIRD_PRAGMA_KEY, SCALE_128 / 41 / 10);
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
        start_cheat_block_timestamp_global(get_block_timestamp() + 1);
        // oracle recovery in pair 1 --> normal
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 2);
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

    // Scenario:
    // 1. pair 1 transitions into recovery
    // 2. pair 2 transitions into recovery
    // 3. pair 1 transitions out of recovery
    // -> pool should still be in recovery mode (in the same call as pair 1 transitions out of recovery)
    #[test]
    #[should_panic(expected: "in-recovery")]
    fn test_recovery_mode_complex_oldest_timestamp() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Pair 1: None -> Recovery
        // warp to non zero block timestamp first
        start_cheat_block_timestamp_global(get_block_timestamp() + 1);
        // oracle failure in pair 1 --> recovery
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 1);
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
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);
        // warp such that next violation is at a different timestamp
        start_cheat_block_timestamp_global(get_block_timestamp() + 1);
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

        // Pair 1: Recovery --> None
        start_cheat_block_timestamp_global(get_block_timestamp() + 1);
        // oracle recovery in pair 1 --> normal
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 2);

        // should still be in recovery because of pair 2
        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: (nominal_debt_to_draw / 10).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    fn test_unsafe_rate_accumulator() {
        let current_time = 1707509060;
        start_cheat_block_timestamp_global(current_time);

        let interest_rate_config = InterestRateConfig {
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
            Zeroable::zero(),
            Zeroable::zero(),
            Zeroable::zero(),
            Zeroable::zero(),
            true,
            Option::Some(interest_rate_config)
        );

        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let current_time = current_time + (360 * DAY_IN_SECONDS);
        start_cheat_block_timestamp_global(current_time);

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(asset_config.last_rate_accumulator > 18 * SCALE);
        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(asset_config.last_rate_accumulator > 18 * SCALE);

        let context = singleton
            .context(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert!(context.collateral_asset_config.last_rate_accumulator > 18 * SCALE);
        assert!(context.debt_asset_config.last_rate_accumulator > 18 * SCALE);

        // Recovery
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let (asset_config, _) = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(asset_config.last_rate_accumulator > 18 * SCALE);
        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(asset_config.last_rate_accumulator > 18 * SCALE);

        stop_cheat_block_timestamp_global();
    }

    // test that collateral is not double counted
    #[test]
    fn test_shutdown_collateral_accounting() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit,
        collateral_to_deposit,
        nominal_debt_to_draw,
        liquidity_to_deposit_third,
        .. } =
            terms;

        // Lender

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
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Borrower

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: (nominal_debt_to_draw).into(),
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
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: (nominal_debt_to_draw).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        //

        // Pair 1 and Pair 2: None -> Recovery
        // undercollateraliztion in pair 1 and pair 2 --> recovery
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 2);
        // warp such that next violation is at a different timestamp
        start_cheat_block_timestamp_global(get_block_timestamp() + 1);
        // update shutdown mode
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, third_asset.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');
        let violation_timestamp_pair_1 = extension
            .violation_timestamp_for_pair(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(violation_timestamp_pair_1 != 0, 'violation-timestamp-not-set');
        assert(
            violation_timestamp_pair_1 == extension.oldest_violation_timestamp(pool_id),
            'violation-timestamp-not-oldest'
        );
        assert(
            extension.violation_timestamp_count(pool_id, violation_timestamp_pair_1) == 2, 'violation-counter-not-incr'
        );
    }

    #[test]
    fn test_recovery_mode_transfer_within_pair() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 1);

        // Transfer

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 10).into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.transfer_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "shutdown-pair-mismatch")]
    fn test_recovery_mode_transfer_different_pair() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 1);

        // Transfer

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: third_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 10).into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.transfer_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "shutdown-non-zero-debt")]
    fn test_recovery_mode_transfer_non_zero_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

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

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Recovery

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 1);

        // Transfer

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: third_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 10).into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.transfer_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }
}
