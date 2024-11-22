#[cfg(test)]
mod TestSingleton {
    use snforge_std::{
        start_cheat_caller_address, stop_cheat_caller_address, get_class_hash, ContractClass,
        start_cheat_block_timestamp_global
    };
    use starknet::{get_contract_address, get_block_timestamp};
    use vesu::{
        units::{SCALE, SCALE_128, PERCENT, DAY_IN_SECONDS},
        test::setup::{
            setup, setup_env, create_pool, TestConfig, deploy_assets, deploy_asset, COLL_PRAGMA_KEY,
            deploy_asset_with_decimals, test_interest_rate_config, LendingTerms, Env
        },
        singleton::{ISingletonDispatcherTrait},
        data_model::{AssetParams, LTVParams, LTVConfig, ModifyPositionParams, Amount, AmountType, AmountDenomination},
        extension::default_extension_po::{
            InterestRateConfig, PragmaOracleParams, LiquidationParams, IDefaultExtensionDispatcherTrait, ShutdownParams,
            FeeParams, LiquidationConfig, ShutdownConfig
        },
        vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait},
    };

    #[test]
    fn test_pool_id() {
        let Env { singleton, extension, config, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        let pool_id = singleton.create_pool(array![].span(), array![].span(), extension.contract_address);
        stop_cheat_caller_address(singleton.contract_address);

        assert!(pool_id == config.pool_id, "Invalid pool id");
    }

    #[test]
    #[should_panic(expected: "extension-is-zero")]
    fn test_create_pool_no_extension() {
        let Env { singleton, .. } = setup_env(Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero());
        singleton.create_pool(array![].span(), array![].span(), Zeroable::zero());
    }

    #[test]
    #[should_panic(expected: "asset-config-already-exists")]
    fn test_create_pool_duplicate_asset() {
        let Env { singleton, extension, config, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        let collateral_asset_params = AssetParams {
            asset: config.collateral_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };

        // create ltv config for collateral and borrow assets
        let max_position_ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
        };
        let max_position_ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let asset_params = array![collateral_asset_params, collateral_asset_params].span();
        let max_position_ltv_params = array![max_position_ltv_params_0, max_position_ltv_params_1].span();

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "invalid-ltv-config")]
    fn test_create_pool_assert_ltv_config_invalid_ltv_config() {
        let Env { singleton, extension, config, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        let collateral_asset = deploy_asset(
            ContractClass { class_hash: get_class_hash(config.collateral_asset.contract_address) },
            get_contract_address()
        );

        let collateral_asset_params = AssetParams {
            asset: collateral_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };

        let debt_asset = deploy_asset(
            ContractClass { class_hash: get_class_hash(config.collateral_asset.contract_address) },
            get_contract_address()
        );

        let debt_asset_params = AssetParams {
            asset: debt_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };

        // create ltv config for collateral and borrow assets
        let max_position_ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: 1_000_000_000_000_000_001
        };
        let max_position_ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let asset_params = array![collateral_asset_params, debt_asset_params].span();
        let max_position_ltv_params = array![max_position_ltv_params_0, max_position_ltv_params_1].span();

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "scale-exceeded")]
    fn test_create_pool_assert_asset_config_scale_exceeded() {
        let Env { singleton, extension, config, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        let asset = deploy_asset_with_decimals(
            ContractClass { class_hash: get_class_hash(config.collateral_asset.contract_address) },
            get_contract_address(),
            19
        );

        let collateral_asset_params = AssetParams {
            asset: asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };

        // create ltv config for collateral and borrow assets
        let max_position_ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
        };
        let max_position_ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let asset_params = array![collateral_asset_params, collateral_asset_params].span();
        let max_position_ltv_params = array![max_position_ltv_params_0, max_position_ltv_params_1].span();

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "max-utilization-exceeded")]
    fn test_create_pool_assert_asset_config_max_utilization_exceeded() {
        let Env { singleton, extension, config, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        let collateral_asset_params = AssetParams {
            asset: config.collateral_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE + 1,
            is_legacy: false,
            fee_rate: 0
        };

        // create ltv config for collateral and borrow assets
        let max_position_ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
        };
        let max_position_ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let asset_params = array![collateral_asset_params, collateral_asset_params].span();
        let max_position_ltv_params = array![max_position_ltv_params_0, max_position_ltv_params_1].span();

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "rate-accumulator-too-low")]
    fn test_create_pool_assert_asset_config_rate_accumulator_too_low() {
        let Env { singleton, extension, config, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        let collateral_asset_params = AssetParams {
            asset: config.collateral_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: 1,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };

        // create ltv config for collateral and borrow assets
        let max_position_ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
        };
        let max_position_ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let asset_params = array![collateral_asset_params, collateral_asset_params].span();
        let max_position_ltv_params = array![max_position_ltv_params_0, max_position_ltv_params_1].span();

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "fee-rate-exceeded")]
    fn test_create_pool_assert_asset_config_fee_rate_exceeded() {
        let Env { singleton, extension, config, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        let collateral_asset_params = AssetParams {
            asset: config.collateral_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: SCALE + 1
        };

        // create ltv config for collateral and borrow assets
        let max_position_ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
        };
        let max_position_ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let asset_params = array![collateral_asset_params, collateral_asset_params].span();
        let max_position_ltv_params = array![max_position_ltv_params_0, max_position_ltv_params_1].span();

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_set_asset_config_not_extension() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        let asset = deploy_asset(
            ContractClass { class_hash: get_class_hash(config.collateral_asset.contract_address) }, users.creator
        );

        let asset_params = AssetParams {
            asset: asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };

        singleton.set_asset_config(config.pool_id, asset_params);
    }

    #[test]
    fn test_set_asset_config() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        let asset = deploy_asset(
            ContractClass { class_hash: get_class_hash(config.collateral_asset.contract_address) }, users.creator
        );

        let asset_params = AssetParams {
            asset: asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };
        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_config(config.pool_id, asset_params);
        stop_cheat_caller_address(singleton.contract_address);

        let (asset_config, _) = singleton.asset_config(config.pool_id, config.collateral_asset.contract_address);
        assert!(asset_config.floor != 0, "Asset config not set");
        assert!(asset_config.scale == config.collateral_scale, "Invalid scale");
        assert!(asset_config.last_rate_accumulator >= SCALE, "Last rate accumulator too low");
        assert!(asset_config.last_rate_accumulator < 10 * SCALE, "Last rate accumulator too high");
    }

    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_set_asset_parameter_not_extension() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        singleton.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'max_utilization', 0);
    }

    #[test]
    fn test_set_asset_parameter() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'max_utilization', 0);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'floor', SCALE);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'fee_rate', SCALE);
        stop_cheat_caller_address(singleton.contract_address);

        let (asset_config, _) = singleton.asset_config_unsafe(config.pool_id, config.collateral_asset.contract_address);
        assert!(asset_config.max_utilization == 0, "Max utilization not set");
        assert!(asset_config.floor == SCALE, "Floor not set");
        assert!(asset_config.fee_rate == SCALE, "Fee rate not set");
    }

    #[test]
    fn test_set_asset_parameter_fee_shares() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        assert!(singleton.extension(pool_id).is_non_zero(), "Pool not created");

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_parameter(pool_id, debt_asset.contract_address, 'fee_rate', 10 * PERCENT);
        stop_cheat_caller_address(singleton.contract_address);

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

        // BORROWER

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

        // interest accrued should be reflected since time has passed
        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS);

        let (position, _, _) = singleton
            .position(pool_id, debt_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert!(position.collateral_shares == 0, "No fee shares should not have accrued");

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_parameter(config.pool_id, debt_asset.contract_address, 'fee_rate', SCALE);
        stop_cheat_caller_address(singleton.contract_address);

        let (position, _, _) = singleton
            .position(pool_id, debt_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert!(position.collateral_shares != 0, "Fee shares should have been accrued");

        let (asset_config, _) = singleton.asset_config_unsafe(config.pool_id, debt_asset.contract_address);
        assert!(asset_config.fee_rate == SCALE, "Fee rate not set");
    }

    #[test]
    fn test_set_ltv_config() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton
            .set_ltv_config(
                config.pool_id,
                config.collateral_asset.contract_address,
                config.debt_asset.contract_address,
                LTVConfig { max_ltv: (40 * PERCENT).try_into().unwrap() }
            );
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_set_extension_not_extension() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        singleton.set_extension(config.pool_id, users.creator);
    }
}
