#[cfg(test)]
mod TestAssetRetrieval {
    use snforge_std::{start_prank, stop_prank, CheatTarget};
    use starknet::{contract_address_const};
    use vesu::vendor::erc20::ERC20ABIDispatcherTrait;
    use vesu::{
        data_model::{Amount, AmountType, AmountDenomination, ModifyPositionParams},
        singleton::ISingletonDispatcherTrait, extension::default_extension::{IDefaultExtensionDispatcherTrait},
        test::{setup::{setup, TestConfig, LendingTerms},},
    };

    #[test]
    fn test_retrieve_from_reserve_total_balance() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);

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
        let pre_retrieval_balance = debt_asset.balance_of(singleton.contract_address);
        assert!(pre_retrieval_balance - 2 == liquidity_to_deposit, "Not transferred to Singleton");

        // retrieve entire balance 

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.retrieve_from_reserve(pool_id, debt_asset.contract_address, users.lender, pre_retrieval_balance);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let post_retrieval_balance = debt_asset.balance_of(singleton.contract_address);
        let post_retrieval_user_balance = debt_asset.balance_of(users.lender);
        assert!(post_retrieval_balance == 0, "Asset not transferred out of the Singleton");

        assert!(
            post_retrieval_user_balance - 2 == initial_lender_debt_asset_balance, "Asset not transferred to the user"
        );

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(asset_config.reserve == 0, "Reserve not updated");
    }

    #[test]
    fn test_retrieve_from_reserve_partial_balance() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);

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
        let pre_retrieval_balance = debt_asset.balance_of(singleton.contract_address);
        assert!(pre_retrieval_balance - 2 == liquidity_to_deposit, "Not transferred to Singleton");

        let (asset_config_pre_retrieval, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(asset_config_pre_retrieval.reserve - 2 == liquidity_to_deposit, "Reserve not updated");

        // retrieve % of total balance 
        let amount_to_retrieve = pre_retrieval_balance / 2;

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.retrieve_from_reserve(pool_id, debt_asset.contract_address, users.lender, amount_to_retrieve);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let post_retrieval_balance = debt_asset.balance_of(singleton.contract_address);
        let post_retrieval_user_balance = debt_asset.balance_of(users.lender);
        assert!(
            post_retrieval_balance == pre_retrieval_balance - amount_to_retrieve,
            "Asset not transferred out of the Singleton"
        );
        assert!(
            post_retrieval_user_balance - 2 == initial_lender_debt_asset_balance - amount_to_retrieve,
            "Asset not transferred to the user"
        );

        let (asset_config, _) = singleton.asset_config(pool_id, debt_asset.contract_address);
        assert!(asset_config.reserve == asset_config_pre_retrieval.reserve - amount_to_retrieve, "Reserve not updated");
    }


    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_retrieve_from_reserve_incorrect_caller() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

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
        let pre_retrieval_balance = debt_asset.balance_of(singleton.contract_address);
        assert!(pre_retrieval_balance - 2 == liquidity_to_deposit, "Not transferred to Singleton");

        let incorrect_caller = contract_address_const::<'incorrect_caller'>();

        start_prank(CheatTarget::One(singleton.contract_address), incorrect_caller);
        singleton.retrieve_from_reserve(pool_id, debt_asset.contract_address, incorrect_caller, pre_retrieval_balance);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }
}
