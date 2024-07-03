#[cfg(test)]
mod TestCreatePool {
    use snforge_std::{start_prank, stop_prank, CheatTarget, get_class_hash, ContractClass};
    use vesu::{
        units::{SCALE, PERCENT}, test::setup::{setup_env, create_pool, TestConfig, deploy_assets, deploy_asset},
        singleton::{ISingletonDispatcherTrait}, data_model::{AssetParams, LTVParams, LTVConfig},
        extension::default_extension::{
            InterestRateConfig, PragmaOracleParams, LiquidationParams, IDefaultExtensionDispatcherTrait
        }
    };

    #[test]
    fn test_create_pool() {
        let (singleton, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero(),
        );

        let old_creator_nonce = singleton.creator_nonce(extension.contract_address);

        create_pool(extension, config, users.creator, Option::None);

        let new_creator_nonce = singleton.creator_nonce(extension.contract_address);
        assert!(new_creator_nonce == old_creator_nonce + 1, "Creator nonce not incremented");

        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;

        assert!(singleton.extension(pool_id).is_non_zero(), "Pool not created");

        let ltv = singleton.ltv_config(pool_id, debt_asset.contract_address, collateral_asset.contract_address).max_ltv;
        assert!(ltv > 0, "Not set");
        let ltv = singleton.ltv_config(pool_id, collateral_asset.contract_address, debt_asset.contract_address).max_ltv;
        assert!(ltv > 0, "Not set");

        let asset_config = singleton.asset_config(pool_id, collateral_asset.contract_address);
        assert!(asset_config.floor != 0, "Asset config not set");
        assert!(asset_config.scale == config.collateral_scale, "Invalid scale");
        assert!(asset_config.last_rate_accumulator >= SCALE, "Last rate accumulator too low");
        assert!(asset_config.last_rate_accumulator < 10 * SCALE, "Last rate accumulator too high");
        let asset_config = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(asset_config.floor != 0, "Debt asset config not set");
    }

    #[test]
    #[should_panic(expected: "asset-config-nonexistent")]
    fn test_nonexistent_asset_config() {
        let (singleton, _, _, _) = setup_env(Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero());
        singleton.asset_config(12345, 67890.try_into().unwrap());
    }

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
    #[should_panic(expected: "extension-not-set")]
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

        let asset_config = singleton.asset_config(config.pool_id, config.collateral_asset.contract_address);
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
    #[should_panic(expected: "caller-not-owner")]
    fn test_add_asset_not_owner() {
        let (_, extension, config, users) = setup_env(
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

        let interest_rate_config = InterestRateConfig {
            min_target_utilization: 75_000,
            max_target_utilization: 85_000,
            target_utilization: 87_500,
            min_full_utilization_rate: 1582470460,
            max_full_utilization_rate: 32150205761,
            zero_utilization_rate: 158247046,
            rate_half_life: 172_800,
            target_rate_percent: 20 * PERCENT,
        };

        let pragma_oracle_params = PragmaOracleParams {
            pragma_key: 19514442401534788, timeout: 1, number_of_sources: 2
        };

        let liquidation_params = LiquidationParams { liquidation_discount: 1 };

        extension
            .add_asset(config.pool_id, asset_params, interest_rate_config, pragma_oracle_params, liquidation_params);
    }

    #[test]
    fn test_add_asset() {
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

        let interest_rate_config = InterestRateConfig {
            min_target_utilization: 75_000,
            max_target_utilization: 85_000,
            target_utilization: 87_500,
            min_full_utilization_rate: 1582470460,
            max_full_utilization_rate: 32150205761,
            zero_utilization_rate: 158247046,
            rate_half_life: 172_800,
            target_rate_percent: 20 * PERCENT,
        };

        let pragma_oracle_params = PragmaOracleParams {
            pragma_key: 19514442401534788, timeout: 1, number_of_sources: 2
        };

        let liquidation_params = LiquidationParams { liquidation_discount: 1 };

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .add_asset(config.pool_id, asset_params, interest_rate_config, pragma_oracle_params, liquidation_params);
        stop_prank(CheatTarget::One(extension.contract_address));

        let asset_config = singleton.asset_config(config.pool_id, config.collateral_asset.contract_address);
        assert!(asset_config.floor != 0, "Asset config not set");
        assert!(asset_config.scale == config.collateral_scale, "Invalid scale");
        assert!(asset_config.last_rate_accumulator >= SCALE, "Last rate accumulator too low");
        assert!(asset_config.last_rate_accumulator < 10 * SCALE, "Last rate accumulator too high");
    }

    #[test]
    #[should_panic(expected: "caller-not-owner")]
    fn test_extension_set_asset_parameter_not_owner() {
        let (_, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        extension.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'max_utilization', 0);
    }

    #[test]
    fn test_extension_set_asset_parameter() {
        let (_, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'max_utilization', 0);
        stop_prank(CheatTarget::One(extension.contract_address));

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'floor', SCALE);
        stop_prank(CheatTarget::One(extension.contract_address));

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension.set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'fee_rate', SCALE);
        stop_prank(CheatTarget::One(extension.contract_address));

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .set_asset_parameter(config.pool_id, config.collateral_asset.contract_address, 'liquidation_discount', 1);
        stop_prank(CheatTarget::One(extension.contract_address));
    }

    #[test]
    #[should_panic(expected: "caller-not-owner")]
    fn test_set_pool_owner_not_owner() {
        let (_, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        extension.set_pool_owner(config.pool_id, users.lender);
    }

    #[test]
    fn test_set_pool_owner() {
        let (_, extension, config, users) = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );

        create_pool(extension, config, users.creator, Option::None);

        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension.set_pool_owner(config.pool_id, users.lender);
        stop_prank(CheatTarget::One(extension.contract_address));
    }

    // #[test]
    // #[should_panic(expected: "caller-not-owner")]
    // fn test_set_ltv_config_caller_not_owner() {
    //     let (singleton, extension, config, users) = setup_env(
    //         Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
    //     );

    //     create_pool(extension, config, users.creator, Option::None);

    //     singleton.set_ltv_config(
    //         config.pool_id,
    //         config.collateral_asset.contract_address,
    //         config.debt_asset.contract_address,
    //         LTVConfig { max_ltv: (40 * PERCENT).try_into().unwrap() }
    //     );
    // }

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
}
// interest-rate-params-mismatch

// pragma-oracle-params-mismatch

// liquidation-params-mismatch


