#[cfg(test)]
mod TestPragmaOracle {
    use core::serde::Serde;
    use snforge_std::{
        start_cheat_block_timestamp_global, stop_cheat_block_timestamp_global, start_cheat_caller_address,
        stop_cheat_caller_address, cheat_caller_address, store, map_entry_address, CheatSpan
    };
    use starknet::{ContractAddress, get_block_timestamp};
    use vesu::{
        units::{SCALE, SCALE_128, PERCENT, DAY_IN_SECONDS},
        data_model::{Amount, AmountType, AmountDenomination, ModifyPositionParams, DebtCapParams},
        singleton::{ISingletonDispatcherTrait, ISingletonDispatcher},
        test::{
            setup::{setup, setup_env, TestConfig, LendingTerms, COLL_PRAGMA_KEY, DEBT_PRAGMA_KEY, Env},
            mock_oracle::{
                {
                    IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait, IMockPragmaSummaryDispatcher,
                    IMockPragmaSummaryDispatcherTrait
                }
            }
        },
        extension::{
            interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
            default_extension_po::{
                IDefaultExtensionDispatcherTrait, IDefaultExtensionDispatcher, InterestRateConfig, PragmaOracleParams,
                LiquidationParams, ShutdownParams, FeeParams, VTokenParams
            }
        },
        data_model::{AssetParams, LTVParams}, math::pow_10, common::{is_collateralized},
        vendor::pragma::{AggregationMode}
    };


    fn create_custom_pool(
        extension: IDefaultExtensionDispatcher,
        creator: ContractAddress,
        singleton: ISingletonDispatcher,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        timeout: u64,
        number_of_sources: u32,
    ) -> felt252 {
        let pool_id = singleton.calculate_pool_id(extension.contract_address, 1);

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

        let collateral_asset_params = AssetParams {
            asset: collateral_asset,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: true,
            fee_rate: 0,
        };
        let debt_asset_params = AssetParams {
            asset: debt_asset,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0,
        };

        let collateral_asset_oracle_params = PragmaOracleParams {
            pragma_key: COLL_PRAGMA_KEY,
            timeout,
            number_of_sources,
            start_time_offset: 0,
            time_window: 0,
            aggregation_mode: AggregationMode::Median(())
        };
        let debt_asset_oracle_params = PragmaOracleParams {
            pragma_key: DEBT_PRAGMA_KEY,
            timeout,
            number_of_sources,
            start_time_offset: 0,
            time_window: 0,
            aggregation_mode: AggregationMode::Median(())
        };

        let collateral_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Collateral', v_token_symbol: 'vCOLL' };
        let debt_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Debt', v_token_symbol: 'vDEBT' };

        // create ltv config for collateral and borrow assets
        let max_position_ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
        };
        let max_position_ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let collateral_asset_liquidation_params = LiquidationParams {
            collateral_asset_index: 0, debt_asset_index: 1, liquidation_factor: 0
        };
        let debt_asset_liquidation_params = LiquidationParams {
            collateral_asset_index: 1, debt_asset_index: 0, liquidation_factor: 0
        };

        let collateral_asset_debt_cap_params = DebtCapParams {
            collateral_asset_index: 0, debt_asset_index: 1, debt_cap: 0
        };
        let debt_asset_debt_cap_params = DebtCapParams { collateral_asset_index: 1, debt_asset_index: 0, debt_cap: 0 };

        let shutdown_ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (75 * PERCENT).try_into().unwrap()
        };
        let shutdown_ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (75 * PERCENT).try_into().unwrap()
        };

        let shutdown_ltv_params = array![shutdown_ltv_params_0, shutdown_ltv_params_1].span();

        let asset_params = array![collateral_asset_params, debt_asset_params].span();
        let v_token_params = array![collateral_asset_v_token_params, debt_asset_v_token_params].span();
        let max_position_ltv_params = array![max_position_ltv_params_0, max_position_ltv_params_1].span();
        let models = array![interest_rate_config, interest_rate_config].span();
        let oracle_params = array![collateral_asset_oracle_params, debt_asset_oracle_params].span();
        let liquidation_params = array![collateral_asset_liquidation_params, debt_asset_liquidation_params].span();
        let debt_caps = array![collateral_asset_debt_cap_params, debt_asset_debt_cap_params].span();
        let shutdown_params = ShutdownParams {
            recovery_period: DAY_IN_SECONDS, subscription_period: DAY_IN_SECONDS, ltv_params: shutdown_ltv_params
        };
        let fee_params = FeeParams { fee_recipient: creator };

        cheat_caller_address(extension.contract_address, creator, CheatSpan::TargetCalls(1));
        extension
            .create_pool(
                'DefaultExtensionPO',
                asset_params,
                v_token_params,
                max_position_ltv_params,
                models,
                oracle_params,
                liquidation_params,
                debt_caps,
                shutdown_params,
                fee_params,
                creator
            );
        stop_cheat_caller_address(extension.contract_address);
        pool_id
    }

    #[test]
    fn test_get_default_price() {
        let (_, default_extension_po, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;

        let extension_dispatcher = IExtensionDispatcher { contract_address: default_extension_po.contract_address };

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);
        let debt_asset_price = extension_dispatcher.price(pool_id, debt_asset.contract_address);

        assert!(collateral_asset_price.value == SCALE, "Collateral asset price not correctly set");
        assert!(debt_asset_price.value == SCALE, "Debt asset price not correctly set");
        assert!(collateral_asset_price.is_valid, "Debt asset validity should be true");
        assert!(debt_asset_price.is_valid, "Debt asset validity should be true");
    }

    #[test]
    fn test_get_price_high() {
        let (_, default_extension_po, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;

        let extension_dispatcher = IExtensionDispatcher { contract_address: default_extension_po.contract_address };

        let pragma_oracle = IMockPragmaOracleDispatcher { contract_address: default_extension_po.pragma_oracle() };

        let max: u128 = integer::BoundedInt::max();
        // set collateral asset price
        pragma_oracle.set_price(COLL_PRAGMA_KEY, max);
        // set debt asset price
        pragma_oracle.set_price(DEBT_PRAGMA_KEY, max);

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);
        let debt_asset_price = extension_dispatcher.price(pool_id, debt_asset.contract_address);

        assert!(collateral_asset_price.value == max.into(), "Collateral asset price not correctly set");
        assert!(debt_asset_price.value == max.into(), "Debt asset price not correctly set");
        assert!(collateral_asset_price.is_valid, "Debt asset validity should be true");
        assert!(debt_asset_price.is_valid, "Debt asset validity should be true");

        let max_pair_LTV_ratio = 10 * SCALE;
        let check_collat = is_collateralized(collateral_asset_price.value, debt_asset_price.value, max_pair_LTV_ratio);
        assert!(check_collat, "Collateralization check failed");
    }

    #[test]
    fn test_is_valid_timeout() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero(),
        );
        let TestConfig { collateral_asset, debt_asset, .. } = config;

        let timeout = 10;

        let pool_id = create_custom_pool(
            extension,
            users.creator,
            singleton,
            collateral_asset.contract_address,
            debt_asset.contract_address,
            timeout,
            2
        );

        let extension_dispatcher = IExtensionDispatcher { contract_address: extension.contract_address };
        let pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        pragma_oracle.set_last_updated_timestamp(COLL_PRAGMA_KEY, get_block_timestamp());

        // called at timeout
        start_cheat_block_timestamp_global(get_block_timestamp() + timeout);

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);

        assert!(collateral_asset_price.value == SCALE, "Collateral asset price not correctly returned");

        assert!(collateral_asset_price.is_valid, "Debt asset validity should be true");
        stop_cheat_block_timestamp_global();

        // called at timeout - 1
        start_cheat_block_timestamp_global(get_block_timestamp() + timeout - 1);

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);

        assert!(collateral_asset_price.value == SCALE, "Collateral asset price not correctly returned");

        assert!(collateral_asset_price.is_valid, "Debt asset validity should be true");
        stop_cheat_block_timestamp_global();
    }

    #[test]
    fn test_is_valid_timeout_stale_price() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero(),
        );
        let TestConfig { collateral_asset, debt_asset, .. } = config;

        let timeout = 10;

        let pool_id = create_custom_pool(
            extension,
            users.creator,
            singleton,
            collateral_asset.contract_address,
            debt_asset.contract_address,
            timeout,
            2
        );

        let extension_dispatcher = IExtensionDispatcher { contract_address: extension.contract_address };
        let pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        pragma_oracle.set_last_updated_timestamp(COLL_PRAGMA_KEY, get_block_timestamp());

        // called at timeout + 1
        start_cheat_block_timestamp_global(get_block_timestamp() + timeout + 1);

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);

        assert!(collateral_asset_price.value == SCALE, "Collateral asset price not correctly returned");

        // stale price
        assert!(!collateral_asset_price.is_valid, "Debt asset validity should be false");
        stop_cheat_block_timestamp_global();
    }

    #[test]
    fn test_is_valid_sources_reached() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero(),
        );
        let TestConfig { collateral_asset, debt_asset, .. } = config;

        let min_number_of_sources = 2;
        let pool_id = create_custom_pool(
            extension,
            users.creator,
            singleton,
            collateral_asset.contract_address,
            debt_asset.contract_address,
            0,
            min_number_of_sources
        );

        let extension_dispatcher = IExtensionDispatcher { contract_address: extension.contract_address };
        let pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };

        // number of sources == min_number_of_sources + 1
        pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, min_number_of_sources + 1);

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);

        assert!(collateral_asset_price.is_valid, "Debt asset validity should be true");

        // number of sources == min_number_of_sources
        pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, min_number_of_sources + 1);

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);

        assert!(collateral_asset_price.is_valid, "Debt asset validity should be true");
    }

    #[test]
    fn test_is_valid_sources_not_reached() {
        let Env { singleton, extension, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero(),
        );
        let TestConfig { collateral_asset, debt_asset, .. } = config;

        let min_number_of_sources = 2;
        let pool_id = create_custom_pool(
            extension,
            users.creator,
            singleton,
            collateral_asset.contract_address,
            debt_asset.contract_address,
            0,
            min_number_of_sources
        );

        let extension_dispatcher = IExtensionDispatcher { contract_address: extension.contract_address };
        let pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };

        // number of sources == min_number_of_sources - 1
        pragma_oracle.set_num_sources_aggregated(COLL_PRAGMA_KEY, min_number_of_sources - 1);

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);

        assert!(!collateral_asset_price.is_valid, "Debt asset validity should be false");
    }

    #[test]
    fn test_price_twap() {
        let (_, default_extension_po, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;

        store(
            default_extension_po.contract_address,
            map_entry_address(
                selector!("oracle_configs"), array![pool_id, collateral_asset.contract_address.into()].span(),
            ),
            array![COLL_PRAGMA_KEY, 0, 2, 1, 1, 1].span()
        );

        store(
            default_extension_po.contract_address,
            map_entry_address(selector!("oracle_configs"), array![pool_id, debt_asset.contract_address.into()].span(),),
            array![DEBT_PRAGMA_KEY, 0, 2, 1, 1, 1].span()
        );

        let extension_dispatcher = IExtensionDispatcher { contract_address: default_extension_po.contract_address };
        let pragma_oracle = IMockPragmaOracleDispatcher { contract_address: default_extension_po.pragma_oracle() };
        let pragma_summary = IMockPragmaSummaryDispatcher { contract_address: default_extension_po.pragma_summary() };

        let max: u128 = integer::BoundedInt::max();
        // set collateral asset price
        pragma_oracle.set_price(COLL_PRAGMA_KEY, 0);
        pragma_summary.set_twap(COLL_PRAGMA_KEY, max, 18);
        // set debt asset price
        pragma_oracle.set_price(DEBT_PRAGMA_KEY, 0);
        pragma_summary.set_twap(DEBT_PRAGMA_KEY, max, 18);

        let collateral_asset_price = extension_dispatcher.price(pool_id, collateral_asset.contract_address);
        let debt_asset_price = extension_dispatcher.price(pool_id, debt_asset.contract_address);

        assert!(collateral_asset_price.value == max.into(), "Collateral asset price not correctly set");
        assert!(debt_asset_price.value == max.into(), "Debt asset price not correctly set");
        assert!(collateral_asset_price.is_valid, "Debt asset validity should be true");
        assert!(debt_asset_price.is_valid, "Debt asset validity should be true");

        let max_pair_LTV_ratio = 10 * SCALE;
        let check_collat = is_collateralized(collateral_asset_price.value, debt_asset_price.value, max_pair_LTV_ratio);
        assert!(check_collat, "Collateralization check failed");
    }
}
