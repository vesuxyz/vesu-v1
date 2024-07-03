#[cfg(test)]
mod TestTransferPosition {
    use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, CheatTarget};
    use starknet::{contract_address_const, get_block_timestamp};
    use vesu::vendor::erc20::ERC20ABIDispatcherTrait;
    use vesu::{
        units::{SCALE, DAY_IN_SECONDS, YEAR_IN_SECONDS},
        singleton::{
            ISingletonDispatcherTrait, Amount, AmountType, AmountDenomination, ModifyPositionParams,
            TransferPositionParams
        },
        test::{setup::{setup, TestConfig, LendingTerms},},
        extension::default_extension::{IDefaultExtensionDispatcherTrait},
    };

    #[test]
    #[should_panic(expected: "same-position")]
    fn test_transfer_position_same_position() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.lender,
            to_user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);

        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "collateral-asset-mismatch")]
    fn test_transfer_position_collateral_asset_mismatch() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: third_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: third_asset.contract_address,
            from_user: users.lender,
            to_user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);

        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_transfer_position_collateral() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: third_asset.contract_address,
            from_user: users.lender,
            to_user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);

        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_transfer_position_collateral_target() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: third_asset.contract_address,
            from_user: users.lender,
            to_user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: 0.into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);

        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "debt-asset-mismatch")]
    fn test_transfer_position_debt_asset_mismatch() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, collateral_to_deposit, debt_to_draw, .. } = terms;

        // add liquidity
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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: third_asset.contract_address,
            from_user: users.borrower,
            to_user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 2).into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_transfer_position_debt() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, liquidity_to_deposit_third, collateral_to_deposit, debt_to_draw, .. } =
            terms;

        // add liquidity
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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: third_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 3).into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_transfer_position_debt_target() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, liquidity_to_deposit_third, collateral_to_deposit, debt_to_draw, .. } =
            terms;

        // add liquidity
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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: third_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: 0.into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }
}
