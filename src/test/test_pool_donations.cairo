#[cfg(test)]
mod TestPoolDonation {
    use snforge_std::{
        start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait, ContractClass, get_class_hash,
        start_cheat_block_timestamp_global
    };
    use starknet::get_block_timestamp;
    use vesu::{
        units::{SCALE, PERCENT, DAY_IN_SECONDS}, math::pow_10, test::setup::{setup, TestConfig, LendingTerms},
        singleton::{ISingletonDispatcherTrait, ModifyPositionParams},
        data_model::{AssetParams, LTVParams, Amount, AmountType, AmountDenomination},
        vendor::erc20::{ERC20ABIDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait}
    };

    #[test]
    fn test_donate_to_reserve_pool() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);

        assert!(singleton.extension(pool_id).is_non_zero(), "Pool not created");

        start_cheat_caller_address(singleton.contract_address, extension.contract_address);
        singleton.set_asset_parameter(pool_id, debt_asset.contract_address, 'fee_rate', 10 * PERCENT);
        stop_cheat_caller_address(singleton.contract_address);

        let initial_singleton_debt_asset_balance = debt_asset.balance_of(singleton.contract_address);

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

        // check that liquidity has been deposited
        let balance = debt_asset.balance_of(users.lender);
        assert!(balance == initial_lender_debt_asset_balance - liquidity_to_deposit, "Not transferred from Lender");

        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(balance == initial_singleton_debt_asset_balance + liquidity_to_deposit, "Not transferred to Singleton");

        let (old_position, collateral, _) = singleton
            .position(pool_id, debt_asset.contract_address, collateral_asset.contract_address, users.lender);

        assert!(collateral == liquidity_to_deposit, "Collateral not set");

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let old_pool_reserve = asset_config.reserve;

        let amount_to_donate_to_reserve = 25 * debt_scale;

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
        let response = singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // interest accrued should be reflected since time has passed
        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS);

        let (position, _, _) = singleton
            .position(pool_id, debt_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert!(position.collateral_shares == 0, "No fee shares should not have accrued");

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.donate_to_reserve(pool_id, debt_asset.contract_address, amount_to_donate_to_reserve);
        stop_cheat_caller_address(singleton.contract_address);

        let (position, _, _) = singleton
            .position(pool_id, debt_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert!(position.collateral_shares != 0, "Fee shares should have been accrued");

        let balance = debt_asset.balance_of(users.lender);
        assert!(
            balance == initial_lender_debt_asset_balance - liquidity_to_deposit - amount_to_donate_to_reserve,
            "Not transferred from Lender"
        );

        let (new_position, _, _) = singleton
            .position(pool_id, debt_asset.contract_address, collateral_asset.contract_address, users.lender);

        assert!(new_position.collateral_shares == old_position.collateral_shares, "Collateral shares should unchanged");

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        let new_pool_reserve = asset_config.reserve;
        assert!(
            new_pool_reserve == old_pool_reserve + amount_to_donate_to_reserve - response.debt_delta.abs,
            "Reserves not updated"
        );
    }

    #[test]
    #[should_panic(expected: "unknown-pool")]
    fn test_donate_to_reserve_pool_wrong_pool_id() {
        let (singleton, _, config, users, _) = setup();
        let TestConfig { pool_id, debt_asset, debt_scale, .. } = config;

        assert!(singleton.extension(pool_id).is_non_zero(), "Pool not created");
        assert!(singleton.extension(100).is_zero(), "Pool exists");

        let amount_to_donate_to_reserve = 25 * debt_scale;

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.donate_to_reserve(100, debt_asset.contract_address, amount_to_donate_to_reserve);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[should_panic(expected: "asset-config-nonexistent")]
    fn test_donate_to_reserve_pool_incorrect_asset() {
        let (singleton, _, config, users, _) = setup();
        let TestConfig { pool_id, debt_asset, .. } = config;

        let mock_asset_class = ContractClass { class_hash: get_class_hash(debt_asset.contract_address) };

        let decimals = 8;
        let fake_asset_scale = pow_10(decimals);
        let supply = 5 * fake_asset_scale;
        let calldata = array![
            'Fake', 'FKE', decimals.into(), supply.low.into(), supply.high.into(), users.lender.into()
        ];
        let (contract_address, _) = mock_asset_class.deploy(@calldata).unwrap();
        let fake_asset = IERC20Dispatcher { contract_address };

        assert!(fake_asset.balance_of(users.lender) == supply, "Fake asset not minted");
        start_cheat_caller_address(singleton.contract_address, users.lender);
        fake_asset.approve(singleton.contract_address, supply);
        stop_cheat_caller_address(singleton.contract_address);

        assert!(singleton.extension(pool_id).is_non_zero(), "Pool not created");

        let amount_to_donate_to_reserve = 2 * fake_asset_scale;

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.donate_to_reserve(pool_id, fake_asset.contract_address, amount_to_donate_to_reserve);
        stop_cheat_caller_address(singleton.contract_address);
    }
}
