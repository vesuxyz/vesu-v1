#[cfg(test)]
mod TestPoolDonation {
    use snforge_std::{start_prank, stop_prank, CheatTarget, ContractClassTrait, ContractClass, get_class_hash};
    use vesu::{
        units::{SCALE, PERCENT}, math::pow_10, test::setup::{setup, TestConfig, LendingTerms},
        singleton::{ISingletonDispatcherTrait, ModifyPositionParams},
        data_model::{AssetParams, LTVParams, Amount, AmountType, AmountDenomination},
        vendor::erc20::{ERC20ABIDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait}
    };

    #[test]
    fn test_donate_to_reserve_pool() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms{liquidity_to_deposit, .. } = terms;

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);

        assert!(singleton.pools(pool_id).is_non_zero(), "Pool not created");

        // LENDER

        // deposit collateral which is later borrowed by the borrower
        let params = ModifyPositionParams {
            pool_id,
            debt_asset: collateral_asset.contract_address,
            collateral_asset: debt_asset.contract_address,
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

        // check that liquidity has been deposited
        let balance = debt_asset.balance_of(users.lender);
        assert!(balance == initial_lender_debt_asset_balance - liquidity_to_deposit, "Not transferred from Lender");

        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(balance == liquidity_to_deposit, "Not transferred to Singleton");

        let (old_position, _, _) = singleton
            .positions(pool_id, debt_asset.contract_address, collateral_asset.contract_address, users.lender);

        assert!(
            old_position.collateral_shares == liquidity_to_deposit * SCALE / debt_scale, "Collateral Shares not set"
        );

        let old_pool_reserve = singleton.asset_configs(pool_id, debt_asset.contract_address).reserve;

        let amount_to_donate_to_reserve = 25 * debt_scale;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.donate_to_reserve(pool_id, debt_asset.contract_address, amount_to_donate_to_reserve);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let balance = debt_asset.balance_of(users.lender);
        assert!(
            balance == initial_lender_debt_asset_balance - liquidity_to_deposit - amount_to_donate_to_reserve,
            "Not transferred from Lender"
        );

        let (new_position, _, _) = singleton
            .positions(pool_id, debt_asset.contract_address, collateral_asset.contract_address, users.lender);

        assert!(
            new_position.collateral_shares == new_position.collateral_shares, "New collateral shares were allocated"
        );

        let new_pool_reserve = singleton.asset_configs(pool_id, debt_asset.contract_address).reserve;
        assert!(new_pool_reserve == old_pool_reserve + amount_to_donate_to_reserve, "Asset config not set");
    }

    #[test]
    #[should_panic(expected: "asset-config-nonexistent")]
    fn test_donate_to_reserve_pool_wrong_pool_id() {
        let (singleton, _, config, users, _) = setup();
        let TestConfig{pool_id, debt_asset, debt_scale, .. } = config;

        assert!(singleton.pools(pool_id).is_non_zero(), "Pool not created");
        assert!(singleton.pools(100).is_zero(), "Pool exists");

        let amount_to_donate_to_reserve = 25 * debt_scale;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.donate_to_reserve(100, debt_asset.contract_address, amount_to_donate_to_reserve);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "asset-config-nonexistent")]
    fn test_donate_to_reserve_pool_incorrect_asset() {
        let (singleton, _, config, users, _) = setup();
        let TestConfig{pool_id, debt_asset, .. } = config;

        let mock_asset_class = ContractClass { class_hash: get_class_hash(debt_asset.contract_address) };

        let decimals = 8;
        let fake_asset_scale = pow_10(decimals);
        let supply = 5 * fake_asset_scale;
        let calldata = array![
            'Fake', 'FKE', decimals.into(), supply.low.into(), supply.high.into(), users.lender.into()
        ];
        let fake_asset = IERC20Dispatcher { contract_address: mock_asset_class.deploy(@calldata).unwrap() };

        assert!(fake_asset.balance_of(users.lender) == supply, "Fake asset not minted");
        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        fake_asset.approve(singleton.contract_address, supply);
        stop_prank(CheatTarget::One(singleton.contract_address));

        assert!(singleton.pools(pool_id).is_non_zero(), "Pool not created");

        let amount_to_donate_to_reserve = 2 * fake_asset_scale;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.donate_to_reserve(pool_id, fake_asset.contract_address, amount_to_donate_to_reserve);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }
}
