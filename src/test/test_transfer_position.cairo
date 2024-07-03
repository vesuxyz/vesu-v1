#[cfg(test)]
mod TestTransferPosition {
    use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, CheatTarget, CheatSpan, prank};
    use starknet::{contract_address_const, get_block_timestamp};
    use vesu::vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait};
    use vesu::{
        units::{SCALE, DAY_IN_SECONDS, YEAR_IN_SECONDS, PERCENT},
        data_model::{
            UnsignedAmount, Amount, AmountDenomination, AmountType, ModifyPositionParams, TransferPositionParams
        },
        singleton::ISingletonDispatcherTrait, extension::default_extension::{IDefaultExtensionDispatcherTrait},
        v_token::{IVTokenDispatcher, IVTokenDispatcherTrait}, test::setup::{setup, TestConfig, LendingTerms},
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
            collateral: UnsignedAmount {
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
            collateral: UnsignedAmount {
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
            collateral: UnsignedAmount {
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
    #[should_panic(expected: "invalid-transfer-amounts")]
    fn test_transfer_position_collateral_target_increase_from() {
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
            collateral: UnsignedAmount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit + 1).into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);

        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "invalid-transfer-amounts")]
    fn test_transfer_position_debt_target_increase_from() {
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
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 2).into(),
            },
            debt: UnsignedAmount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: ((debt_to_draw / 2) + 100).into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_delegation(pool_id, users.borrower, true);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "dusty-collateral-balance")]
    fn test_transfer_position_collateral_dusty_collateral_balance_from() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, liquidity_to_deposit_third, collateral_to_deposit, .. } = terms;

        // set floor to 0
        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .set_asset_parameter(pool_id, collateral_asset.contract_address, 'floor', 100_000_000_000); // (* price)
        extension.set_asset_parameter(pool_id, debt_asset.contract_address, 'floor', 0);
        stop_prank(CheatTarget::One(extension.contract_address));

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
            debt: Amount { amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: 1.into(), },
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
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: ((collateral_to_deposit / 2) - 1).into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_delegation(pool_id, users.borrower, true);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "dusty-collateral-balance")]
    fn test_transfer_position_collateral_dusty_collateral_balance_to() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, liquidity_to_deposit_third, collateral_to_deposit, .. } = terms;

        // set floor to 0
        start_prank(CheatTarget::One(extension.contract_address), users.creator);
        extension
            .set_asset_parameter(pool_id, collateral_asset.contract_address, 'floor', 100_000_000_000); // (* price)
        extension.set_asset_parameter(pool_id, debt_asset.contract_address, 'floor', 0);
        stop_prank(CheatTarget::One(extension.contract_address));

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
            debt: Amount { amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: 1.into(), },
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
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: 10.into(),
            },
            debt: UnsignedAmount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: 1.into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_delegation(pool_id, users.borrower, true);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
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
            collateral: UnsignedAmount {
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
            debt: UnsignedAmount {
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
    #[should_panic(expected: "no-delegation")]
    fn test_transfer_position_debt_no_delegate() {
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
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 3).into(),
            },
            debt: UnsignedAmount {
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
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 3).into(),
            },
            debt: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 3).into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_delegation(pool_id, users.borrower, true);
        stop_prank(CheatTarget::One(singleton.contract_address));

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
            debt: UnsignedAmount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: 0.into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "not-collateralized")]
    fn test_transfer_position_debt_from_undercollateralized() {
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
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit).into(),
            },
            debt: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 3).into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_delegation(pool_id, users.borrower, true);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    #[should_panic(expected: "dusty-debt-balance")]
    fn test_transfer_position_debt_dusty_debt_balance_from() {
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
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: ((collateral_to_deposit / 2) - 100000).into(),
            },
            debt: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: ((debt_to_draw / 2) - 1).into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_delegation(pool_id, users.borrower, true);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    // transfer to position less than floor
    #[test]
    #[should_panic(expected: "dusty-debt-balance")]
    fn test_transfer_position_debt_dusty_debt_balance_to() {
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
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: 10000000.into(),
            },
            debt: UnsignedAmount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: 1.into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_delegation(pool_id, users.borrower, true);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_transfer_position_collateral_v_token() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);

        let collateral_shares_to_deposit = singleton
            .calculate_collateral_shares(pool_id, collateral_asset.contract_address, collateral_to_deposit.into());

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
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
            to_debt_asset: Zeroable::zero(),
            from_user: users.lender,
            to_user: extension.contract_address,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);

        let v_token = IERC20Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.balance_of(users.lender) == collateral_shares_to_deposit.into(), 'vToken not minted');

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        v_token.approve(extension.contract_address, collateral_shares_to_deposit);

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: Zeroable::zero(),
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: extension.contract_address,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        // ensure that get_contract_caller is the extension when calling modify_delegation in before_transfer_position
        stop_prank(CheatTarget::One(singleton.contract_address));
        prank(CheatTarget::One(singleton.contract_address), users.lender, CheatSpan::TargetCalls(1));

        singleton.transfer_position(params);

        assert(v_token.balance_of(users.lender) == 0.into(), 'vToken not burned');
    }

    #[test]
    fn test_transfer_position_collateral_v_token_from_zero_debt_asset() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);

        let collateral_shares_to_deposit = singleton
            .calculate_collateral_shares(pool_id, collateral_asset.contract_address, collateral_to_deposit.into());

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: Zeroable::zero(),
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: Zeroable::zero(),
            to_debt_asset: Zeroable::zero(),
            from_user: users.lender,
            to_user: extension.contract_address,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);

        let v_token = IERC20Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.balance_of(users.lender) == collateral_shares_to_deposit.into(), 'vToken not minted');

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        v_token.approve(extension.contract_address, collateral_shares_to_deposit);

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: Zeroable::zero(),
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: Zeroable::zero(),
            from_user: extension.contract_address,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        // ensure that get_contract_caller is the extension when calling modify_delegation in before_transfer_position
        stop_prank(CheatTarget::One(singleton.contract_address));
        prank(CheatTarget::One(singleton.contract_address), users.lender, CheatSpan::TargetCalls(1));

        singleton.transfer_position(params);

        assert(v_token.balance_of(users.lender) == 0.into(), 'vToken not burned');
    }

    #[test]
    fn test_transfer_position_zero_debt_asset() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);

        let collateral_shares_to_deposit = singleton
            .calculate_collateral_shares(pool_id, collateral_asset.contract_address, collateral_to_deposit.into());

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
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
            to_debt_asset: Zeroable::zero(),
            from_user: users.lender,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);

        let v_token = IERC20Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.balance_of(users.lender) == 0, 'vToken not minted');

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: Zeroable::zero(),
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.lender,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: collateral_shares_to_deposit.into(),
            },
            debt: Default::default(),
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        singleton.transfer_position(params);
    }

    #[test]
    fn test_transfer_position_fee_shares() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, third_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, liquidity_to_deposit_third, collateral_to_deposit, debt_to_draw, .. } =
            terms;

        start_prank(CheatTarget::One(singleton.contract_address), extension.contract_address);
        singleton.set_asset_parameter(pool_id, debt_asset.contract_address, 'fee_rate', 10 * PERCENT);
        stop_prank(CheatTarget::One(singleton.contract_address));

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

        start_warp(CheatTarget::All, get_block_timestamp() + DAY_IN_SECONDS);

        let params = TransferPositionParams {
            pool_id,
            from_collateral_asset: collateral_asset.contract_address,
            from_debt_asset: debt_asset.contract_address,
            to_collateral_asset: collateral_asset.contract_address,
            to_debt_asset: debt_asset.contract_address,
            from_user: users.borrower,
            to_user: users.lender,
            collateral: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 3).into(),
            },
            debt: UnsignedAmount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 3).into(),
            },
            from_data: ArrayTrait::new().span(),
            to_data: ArrayTrait::new().span(),
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_delegation(pool_id, users.borrower, true);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.transfer_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .position(pool_id, debt_asset.contract_address, Zeroable::zero(), extension.contract_address);
        assert!(position.collateral_shares > 0, "Fee shares should have been minted");
    }
}
