#[cfg(test)]
mod TestSingleton {
    use snforge_std::{start_prank, stop_prank, CheatTarget, get_class_hash, ContractClass, declare};
    use starknet::get_contract_address;
    use vesu::{
        units::{SCALE, SCALE_128, PERCENT, DAY_IN_SECONDS},
        test::setup::{setup_env, create_pool, TestConfig, deploy_assets, deploy_asset},
        singleton::{ISingletonDispatcherTrait}, data_model::{AssetParams, LTVParams, LTVConfig},
        extension::default_extension::{
            InterestRateConfig, PragmaOracleParams, LiquidationParams, IDefaultExtensionDispatcherTrait, ShutdownParams,
            FeeParams, LiquidationConfig, ShutdownConfig
        },
        test::setup::{COLL_PRAGMA_KEY, deploy_asset_with_decimals, test_interest_rate_config}
    };

    #[test]
    fn test_pool_id() {
        let (singleton, extension, config, _) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        let pool_id = singleton.create_pool(array![].span(), array![].span(), extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));

        assert!(pool_id == config.pool_id, "Invalid pool id");
    }

    #[test]
    #[should_panic(expected: "extension-is-zero")]
    fn test_create_pool_no_extension() {
        let (singleton, _, _, _) = setup_env(Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero());
        singleton.create_pool(array![].span(), array![].span(), Zeroable::zero());
    }

    #[test]
    #[should_panic(expected: "asset-config-already-exists")]
    fn test_create_pool_duplicate_asset() {
        let (singleton, extension, config, _) = setup_env(
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

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "invalid-ltv-config")]
    fn test_create_pool_assert_ltv_config_invalid_ltv_config() {
        let (singleton, extension, config, _) = setup_env(
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

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "scale-exceeded")]
    fn test_create_pool_assert_asset_config_scale_exceeded() {
        let (singleton, extension, config, _) = setup_env(
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

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "max-utilization-exceeded")]
    fn test_create_pool_assert_asset_config_max_utilization_exceeded() {
        let (singleton, extension, config, _) = setup_env(
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

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "rate-accumulator-too-low")]
    fn test_create_pool_assert_asset_config_rate_accumulator_too_low() {
        let (singleton, extension, config, _) = setup_env(
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

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "fee-rate-exceeded")]
    fn test_create_pool_assert_asset_config_fee_rate_exceeded() {
        let (singleton, extension, config, _) = setup_env(
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

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_set_asset_config_not_extension() {
        let (singleton, extension, config, users) = setup_env(
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
        let (singleton, extension, config, users) = setup_env(
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
        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.set_asset_config(config.pool_id, asset_params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (asset_config, _) = singleton.asset_config(config.pool_id, config.collateral_asset.contract_address);
        assert!(asset_config.floor != 0, "Asset config not set");
        assert!(asset_config.scale == config.collateral_scale, "Invalid scale");
        assert!(asset_config.last_rate_accumulator >= SCALE, "Last rate accumulator too low");
        assert!(asset_config.last_rate_accumulator < 10 * SCALE, "Last rate accumulator too high");
    }

    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_set_asset_parameter_not_extension() {
        let (singleton, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        singleton.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'max_utilization', 0);
    }

    #[test]
    fn test_set_asset_parameter() {
        let (singleton, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'max_utilization', 0);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'floor', SCALE);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'fee_rate', SCALE);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_set_ltv_config() {
        let (singleton, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton
            .set_ltv_config(
                config.pool_id,
                config.collateral_asset.contract_address,
                config.debt_asset.contract_address,
                LTVConfig { max_ltv: (40 * PERCENT).try_into().unwrap() }
            );
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_set_extension_not_extension() {
        let (singleton, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        singleton.set_extension(config.pool_id, users.creator);
    }
}
