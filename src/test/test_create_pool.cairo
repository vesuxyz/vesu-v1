#[cfg(test)]
mod TestCreatePool {
    use snforge_std::{start_prank, stop_prank, CheatTarget};
    use vesu::{
        units::{SCALE, PERCENT}, test::setup::{setup_env, create_pool, TestConfig},
        singleton::{ISingletonDispatcherTrait}, data_model::{AssetParams, LTVParams}
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

        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;

        assert!(singleton.pools(pool_id).is_non_zero(), "Pool not created");

        let ltv = singleton.max_position_ltv(pool_id, debt_asset.contract_address, collateral_asset.contract_address);
        assert!(ltv > 0, "Not set");
        let ltv = singleton.max_position_ltv(pool_id, collateral_asset.contract_address, debt_asset.contract_address);
        assert!(ltv > 0, "Not set");

        let asset_config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        assert!(asset_config.floor != 0, "Asset config not set");
        assert!(asset_config.scale == config.collateral_scale, "Invalid scale");
        assert!(asset_config.last_rate_accumulator >= SCALE, "Last rate accumulator too low");
        assert!(asset_config.last_rate_accumulator < 10 * SCALE, "Last rate accumulator too high");
        let asset_config = singleton.asset_configs(pool_id, debt_asset.contract_address);
        assert!(asset_config.floor != 0, "Debt asset config not set");
    }

    #[test]
    #[should_panic(expected: "asset-config-nonexistent")]
    fn test_nonexistent_asset_config() {
        let (singleton, _, _, _) = setup_env(Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero());
        singleton.asset_configs(12345, 67890.try_into().unwrap());
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
        let max_position_ltv_params_0 = LTVParams { collateral_asset_index: 1, debt_asset_index: 0, ltv: 80 * PERCENT };
        let max_position_ltv_params_1 = LTVParams { collateral_asset_index: 0, debt_asset_index: 1, ltv: 80 * PERCENT };

        let asset_params = array![collateral_asset_params, collateral_asset_params].span();
        let max_position_ltv_params = array![max_position_ltv_params_0, max_position_ltv_params_1].span();

        singleton.create_pool(asset_params, max_position_ltv_params, extension.contract_address);
    }
}
