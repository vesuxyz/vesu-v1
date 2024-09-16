#[cfg(test)]
mod TestReentrancy {
    use snforge_std::{
        start_prank, stop_prank, start_warp, CheatTarget, ContractClassTrait, ContractClass, get_class_hash
    };
    use starknet::{ContractAddress, get_contract_address, get_block_timestamp};
    use vesu::{
        test::setup::{setup_env, TestConfig, LendingTerms, deploy_with_args, Env},
        extension::interface::{IExtensionDispatcherTrait, IExtensionDispatcher},
        units::{SCALE, PERCENT, DAY_IN_SECONDS}, math::pow_10,
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait, ModifyPositionParams},
        data_model::{AssetParams, LTVParams, Amount, AmountType, AmountDenomination},
        vendor::erc20::{ERC20ABIDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait}
    };

    #[test]
    #[should_panic(expected: "context-reentrancy")]
    fn test_context_reentrancy() {
        let Env { singleton, config, users, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );
        let TestConfig { debt_asset, debt_scale, .. } = config;

        let args = array![singleton.contract_address.into()];
        let extension = IExtensionDispatcher { contract_address: deploy_with_args("MockExtension", args) };

        let collateral_asset_params = AssetParams {
            asset: config.collateral_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: true,
            fee_rate: 0
        };
        let debt_asset_params = AssetParams {
            asset: config.debt_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };

        let ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
        };
        let ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let asset_params = array![collateral_asset_params, debt_asset_params].span();
        let ltv_params = array![ltv_params_0, ltv_params_1].span();

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        let pool_id = ISingletonDispatcher { contract_address: singleton.contract_address }
            .create_pool(asset_params, ltv_params, extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: debt_asset.contract_address,
            debt_asset: Zeroable::zero(),
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: debt_scale.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "asset-config-reentrancy")]
    fn test_asset_config_reentrancy() {
        let Env { singleton, config, .. } = setup_env(
            Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero()
        );
        let TestConfig { debt_asset, .. } = config;

        let args = array![singleton.contract_address.into()];
        let extension = IExtensionDispatcher { contract_address: deploy_with_args("MockExtension", args) };

        let collateral_asset_params = AssetParams {
            asset: config.collateral_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: true,
            fee_rate: 0
        };
        let debt_asset_params = AssetParams {
            asset: config.debt_asset.contract_address,
            floor: SCALE / 10_000,
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
            max_utilization: SCALE,
            is_legacy: false,
            fee_rate: 0
        };

        let ltv_params_0 = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
        };
        let ltv_params_1 = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
        };

        let asset_params = array![collateral_asset_params, debt_asset_params].span();
        let ltv_params = array![ltv_params_0, ltv_params_1].span();

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        let pool_id = ISingletonDispatcher { contract_address: singleton.contract_address }
            .create_pool(asset_params, ltv_params, extension.contract_address);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_warp(CheatTarget::All, get_block_timestamp() + DAY_IN_SECONDS);

        singleton.asset_config(pool_id, debt_asset.contract_address);
    }
}
