#[cfg(test)]
mod TestShutdown {
    use core::num::traits::{Bounded, Zero};
    use openzeppelin::token::erc20::ERC20ABIDispatcherTrait;
    use snforge_std::{
        start_cheat_block_timestamp_global, start_cheat_caller_address, stop_cheat_block_timestamp_global,
        stop_cheat_caller_address,
    };
    use starknet::get_block_timestamp;
    use vesu::data_model::{
        Amount, AmountDenomination, AmountType, ModifyPositionParams, TransferPositionParams, UnsignedAmount,
    };
    use vesu::extension::components::interest_rate_model::InterestRateConfig;
    use vesu::extension::components::position_hooks::ShutdownMode;
    use vesu::extension::default_extension_po_v2::IDefaultExtensionPOV2DispatcherTrait;
    use vesu::singleton_v2::ISingletonV2DispatcherTrait;
    use vesu::test::mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait};
    use vesu::test::setup_v2::{COLL_PRAGMA_KEY, LendingTerms, THIRD_PRAGMA_KEY, TestConfig, setup, setup_pool};
    use vesu::units::{DAY_IN_SECONDS, SCALE, SCALE_128};
    use vesu::v_token_v2::{IERC4626Dispatcher, IERC4626DispatcherTrait, IVTokenV2Dispatcher, IVTokenV2DispatcherTrait};

    #[test]
    fn test_set_shutdown_mode_recovery() {
        let (_, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;

        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');
    }

    #[test]
    #[should_panic(expected: "shutdown-mode-not-recovery")]
    fn test_set_shutdown_mode_not_recovery() {
        let (_, extension, config, _, _) = setup();
        let TestConfig { pool_id, .. } = config;

        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
    }

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address),
        };
        assert(v_token.max_deposit(Zero::zero()) > 0, 'max_deposit neq');
        assert(v_token.preview_deposit(10000000) > 0, 'preview_deposit neq');
        assert(v_token.max_mint(Zero::zero()) > 0, 'max_mint neq');
        assert(v_token.preview_mint(100000000) > 0, 'preview_mint neq');
        assert(v_token.max_withdraw(users.lender) == 0, 'max_withdraw neq');
        assert(v_token.preview_withdraw(10000000) == 0, 'preview_withdraw neq');
        assert(v_token.max_redeem(users.lender) == 0, 'max_redeem neq');
        assert(v_token.preview_redeem(10000000) == 0, 'preview_redeem neq');

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        // Subscription
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        // Subscription
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address),
        };
        assert(v_token.max_deposit(Zero::zero()) == 0, 'max_deposit neq');
        assert(v_token.preview_deposit(10000000) == 0, 'preview_deposit neq');
        assert(v_token.max_mint(Zero::zero()) == 0, 'max_mint neq');
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        // Subscription
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        // Subscription
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

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
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zero::zero(),
            },
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.subscription_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Redemption);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zero::zero(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

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
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zero::zero(),
            },
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.subscription_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Redemption);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);

        assert(status.shutdown_mode == ShutdownMode::Redemption, 'not-in-redemption');

        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128);

        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address),
        };

        start_cheat_caller_address(v_token.contract_address, extension.contract_address);
        IVTokenV2Dispatcher { contract_address: v_token.contract_address }
            .mint_v_token(users.borrower, 1000_0000000000);
        stop_cheat_caller_address(v_token.contract_address);

        assert(v_token.max_deposit(Zero::zero()) == 0, 'max_deposit neq');
        assert(v_token.preview_deposit(1000_0000000000) == 0, 'preview_deposit neq');
        assert(v_token.max_mint(Zero::zero()) == 0, 'max_mint neq');
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.subscription_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Redemption);
        stop_cheat_caller_address(extension.contract_address);

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

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
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zero::zero(),
            },
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.subscription_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Redemption);
        stop_cheat_caller_address(extension.contract_address);

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);
        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Subscription, 'not-in-subscription');

        // Redemption

        let shutdown_config = extension.shutdown_config(pool_id);
        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.subscription_period + 1);
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Redemption);
        stop_cheat_caller_address(extension.contract_address);

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128 / 41 / 10);

        // Recovery
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Subscription

        let shutdown_config = extension.shutdown_config(pool_id);

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);

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
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zero::zero(),
            },
            data: ArrayTrait::new().span(),
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

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.subscription_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Redemption);
        stop_cheat_caller_address(extension.contract_address);

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
            data: ArrayTrait::new().span(),
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
        let LendingTerms {
            liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, liquidity_to_deposit_third, ..,
        } = terms;

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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

        // Pair 3: None -> Recovery
        // undercollateraliztion in pair 3 --> recovery
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(THIRD_PRAGMA_KEY, SCALE_128 / 41 / 10);
        // update shutdown mode
        extension.update_shutdown_status(pool_id, collateral_asset.contract_address, third_asset.contract_address);

        let status = extension
            .shutdown_status(pool_id, collateral_asset.contract_address, third_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');

        // Pair 1: Recovery --> None
        start_cheat_block_timestamp_global(get_block_timestamp() + 1);
        // oracle recovery in pair 1 --> normal
        mock_pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, 2);
        // update shutdown mode
        extension.update_shutdown_status(pool_id, debt_asset.contract_address, collateral_asset.contract_address);

        let status = extension.shutdown_status(pool_id, debt_asset.contract_address, collateral_asset.contract_address);
        // should still be in recovery because of pair 2
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');
    }

    #[test]
    fn test_recovery_mode_unsafe_rate_accumulator() {
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
            Zero::zero(), Zero::zero(), Zero::zero(), Zero::zero(), true, Option::Some(interest_rate_config),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

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
        let LendingTerms {
            liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, liquidity_to_deposit_third, ..,
        } = terms;

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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);

        let status = extension.shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert(status.shutdown_mode == ShutdownMode::Recovery, 'not-in-recovery');
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
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
    fn test_fixed_shutdown_mode() {
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
            data: ArrayTrait::new().span(),
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
            data: ArrayTrait::new().span(),
        };

        start_cheat_caller_address(singleton.contract_address, users.borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Recovery);
        stop_cheat_caller_address(extension.contract_address);
        let shutdown_mode = extension
            .update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert!(shutdown_mode == ShutdownMode::Recovery, "shutdown-mode-not-recovery");

        let shutdown_config = extension.shutdown_config(pool_id);
        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.recovery_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Subscription);
        stop_cheat_caller_address(extension.contract_address);
        let shutdown_mode = extension
            .update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert!(shutdown_mode == ShutdownMode::Subscription, "shutdown-mode-not-subscription");

        start_cheat_block_timestamp_global(get_block_timestamp() + shutdown_config.subscription_period + 1);

        start_cheat_caller_address(extension.contract_address, users.creator);
        extension.set_shutdown_mode(pool_id, ShutdownMode::Redemption);
        stop_cheat_caller_address(extension.contract_address);
        let shutdown_mode = extension
            .update_shutdown_status(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert!(shutdown_mode == ShutdownMode::Redemption, "shutdown-mode-not-redemption");
    }
}

