#[cfg(test)]
mod TestModifyPosition {
    use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, CheatTarget};
    use starknet::{contract_address_const, get_block_timestamp};
    use vesu::vendor::erc20::ERC20ABIDispatcherTrait;
    use vesu::{
        units::{SCALE, DAY_IN_SECONDS, YEAR_IN_SECONDS},
        singleton::{ISingletonDispatcherTrait, Amount, AmountType, AmountDenomination, ModifyPositionParams,},
        test::{setup::{setup, TestConfig, LendingTerms},},
        extension::default_extension::{IDefaultExtensionDispatcherTrait},
    };

    #[test]
    #[should_panic(expected: "asset-config-nonexistent")]
    fn test_modify_position_unknown_pool_id() {
        let (singleton, _, _, users, _) = setup();

        // deposit collateral which is later borrowed by the borrower
        let params = ModifyPositionParams {
            pool_id: 'non existent',
            collateral_asset: contract_address_const::<'collateral'>(),
            debt_asset: contract_address_const::<'debt'>(),
            user: users.lender,
            collateral: Default::default(),
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_modify_position_collateral_amounts() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, collateral_scale, .. } = config;
        let LendingTerms{collateral_to_deposit, .. } = terms;

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

        let asset_config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(asset_config.total_collateral_shares == position.collateral_shares, 'Shares not matching');

        singleton.donate_to_reserve(pool_id, collateral_asset.contract_address, collateral_to_deposit / 2);

        let asset_config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(asset_config.total_collateral_shares == position.collateral_shares, 'Shares not matching');

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(collateral_to_deposit / 4).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let asset_config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(asset_config.total_collateral_shares == position.collateral_shares, 'Shares not matching');

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: (((collateral_to_deposit / 2) * SCALE) / collateral_scale).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: -(((collateral_to_deposit / 4) * SCALE) / collateral_scale).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: (collateral_to_deposit / 4).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: ((collateral_to_deposit * SCALE / collateral_scale) / 2).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let asset_config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(asset_config.total_collateral_shares == position.collateral_shares, 'Shares not matching');
        assert(asset_config.reserve == 0, 'Reserve not zero');
        assert(asset_config.total_collateral_shares == 0, 'Total shares not zero');

        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_modify_position_debt_amounts() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, debt_scale, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, debt_to_draw, .. } = terms;

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);

        // add liquidity
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

        singleton.modify_position(params);

        // collateralize position
        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_warp(CheatTarget::All, get_block_timestamp() + DAY_IN_SECONDS);

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let (position, _, debt) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(position.nominal_debt < debt * SCALE / debt_scale, 'No interest');

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(debt_to_draw / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: ((debt_to_draw / 2) * SCALE / debt_scale).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Native,
                value: -((debt_to_draw / 4) * SCALE / debt_scale).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Assets,
                value: (debt_to_draw / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target,
                denomination: AmountDenomination::Native,
                value: ((debt_to_draw * SCALE / debt_scale) / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        singleton.modify_position(params);

        let asset_config = singleton.asset_configs(pool_id, debt_asset.contract_address);
        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.lender);
        assert(asset_config.total_nominal_debt == position.nominal_debt, 'Shares not matching');
        assert(asset_config.total_nominal_debt == 0, 'Total nominal debt not zero');

        stop_prank(CheatTarget::One(singleton.contract_address));
    }

    #[test]
    fn test_modify_position_complex() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, collateral_scale, debt_scale, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, debt_to_draw, nominal_debt_to_draw, .. } = terms;

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);
        let initial_borrower_collateral_asset_balance = collateral_asset.balance_of(users.borrower);
        let initial_borrower_debt_asset_balance = debt_asset.balance_of(users.borrower);

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

        let (position, collateral, debt) = singleton
            .positions(pool_id, debt_asset.contract_address, collateral_asset.contract_address, users.lender);
        assert!(position.collateral_shares == liquidity_to_deposit * SCALE / debt_scale, "Collateral Shares not set");

        assert!(collateral == liquidity_to_deposit, "Collateral not set");
        assert!(position.nominal_debt == 0, "Nominal Debt should be 0");
        assert!(debt == 0, "Debt should be 0");

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

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // check that collateral has been deposited and the targeted amount has been borrowed

        // collateral asset has been transferred from the borrower to the singleton
        let balance = collateral_asset.balance_of(users.borrower);
        assert!(
            balance == initial_borrower_collateral_asset_balance - collateral_to_deposit,
            "Not transferred from borrower"
        );
        let balance = collateral_asset.balance_of(singleton.contract_address);
        assert!(balance == collateral_to_deposit, "Not transferred to Singleton");

        // debt asset has been transferred from the singleton to the borrower
        let balance = debt_asset.balance_of(users.borrower);
        assert!(balance == initial_borrower_debt_asset_balance + debt_to_draw, "Debt asset not transferred");
        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(balance == liquidity_to_deposit - debt_to_draw, "Debt asset not transferred");

        // collateral asset reserve has been updated
        let config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        assert!(config.reserve == collateral_to_deposit, "Collateral not in reserve");

        // debt asset reserve has been updated
        let config = singleton.asset_configs(pool_id, debt_asset.contract_address);
        assert!(config.reserve == liquidity_to_deposit - debt_to_draw, "Debt not taken from reserve");

        // position's collateral balance has been updated
        let (position, collateral, debt) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert!(
            position.collateral_shares == collateral_to_deposit * SCALE / collateral_scale, "Collateral Shares not set"
        );
        assert!(collateral == collateral_to_deposit, "Collateral not set");
        // position's debt balance has been updated (no interest accrued yet)
        assert!(position.nominal_debt == nominal_debt_to_draw, "Nominal Debt not set");
        assert!(debt == nominal_debt_to_draw * debt_scale / SCALE, "Debt not set");
        // interest accrued should be reflected since time has passed
        start_warp(CheatTarget::All, get_block_timestamp() + DAY_IN_SECONDS);
        let (position, collateral, debt) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert!(
            position.collateral_shares == collateral_to_deposit * SCALE / collateral_scale, "C.S. should not change"
        );
        assert!(collateral == collateral_to_deposit, "Collateral should not change");
        assert!(position.nominal_debt == nominal_debt_to_draw, "Nominal Debt should not change");
        assert!(debt > nominal_debt_to_draw * debt_scale / SCALE, "Debt should accrue due interest");

        // repay debt assets
        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(collateral_to_deposit / 2).into(),
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(debt_to_draw / 2).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // check that some debt has been repayed and that some collateral has been withdrawn
        let balance = debt_asset.balance_of(users.borrower);
        assert!(
            balance <= initial_borrower_debt_asset_balance + debt_to_draw - debt_to_draw / 2,
            "Debt asset not transferred"
        );

        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(balance >= liquidity_to_deposit - debt_to_draw + debt_to_draw / 2, "Debt asset not transferred");

        let config = singleton.asset_configs(pool_id, debt_asset.contract_address);
        assert!(
            config.reserve >= liquidity_to_deposit - debt_to_draw + debt_to_draw / 2, "Repayed assets not in reserve"
        );

        let (position, _, debt) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        assert!(position.nominal_debt < nominal_debt_to_draw, "Nominal Debt should be less");
        assert!(debt < debt_to_draw, "Debt should be less");

        let balance = collateral_asset.balance_of(users.borrower);
        assert!(
            balance <= initial_borrower_collateral_asset_balance - collateral_to_deposit / 2,
            "Collateral not transferred"
        );

        let balance = collateral_asset.balance_of(singleton.contract_address);
        assert!(balance >= collateral_to_deposit / 2, "Collateral not transferred");

        let config = singleton.asset_configs(pool_id, collateral_asset.contract_address);
        assert!(config.reserve >= collateral_to_deposit / 2, "Withdrawn assets not in reserve");

        // fund borrower with debt assets to repay interest
        start_prank(CheatTarget::One(debt_asset.contract_address), users.lender);
        debt_asset.transfer(users.borrower, debt_to_draw);
        stop_prank(CheatTarget::One(debt_asset.contract_address));

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: Zeroable::zero(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Assets, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // check that all debt has been repayed and all collateral has been withdrawn
        assert!(
            debt_asset.balance_of(singleton.contract_address) >= liquidity_to_deposit, "Debt asset not transferred"
        );

        let config = singleton.asset_configs(pool_id, debt_asset.contract_address);
        assert!(config.reserve >= liquidity_to_deposit, "Repayed assets not in reserve");

        let balance = collateral_asset.balance_of(users.borrower);
        assert!(balance == initial_borrower_collateral_asset_balance, "Collateral not transferred");

        stop_warp(CheatTarget::All);
    }

    #[test]
    fn test_modify_position_fees() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, third_asset, third_scale, .. } = config;
        let LendingTerms{collateral_to_deposit, liquidity_to_deposit_third, .. } = terms;

        // Supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: third_asset.contract_address,
            debt_asset: collateral_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: (liquidity_to_deposit_third).into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // Borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: collateral_to_deposit.into(),
            },
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: (SCALE / 4).into(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        start_warp(CheatTarget::All, get_block_timestamp() + YEAR_IN_SECONDS.try_into().unwrap());

        // fund borrower with debt assets to repay interest
        start_prank(CheatTarget::One(third_asset.contract_address), users.lender);
        third_asset.transfer(users.borrower, third_scale);
        stop_prank(CheatTarget::One(third_asset.contract_address));

        let total_collateral_shares = singleton
            .asset_configs(pool_id, third_asset.contract_address)
            .total_collateral_shares;

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: third_asset.contract_address,
            user: users.borrower,
            collateral: Default::default(),
            debt: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: Zeroable::zero(),
            },
            data: ArrayTrait::new().span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.borrower);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (p, _, _) = singleton
            .positions(
                pool_id, third_asset.contract_address, collateral_asset.contract_address, extension.contract_address
            );
        assert(p.collateral_shares > 0, 'Fee shares not minted');

        // fees increase total_collateral_shares
        assert(
            singleton
                .asset_configs(pool_id, third_asset.contract_address)
                .total_collateral_shares > total_collateral_shares,
            'Shares not increased'
        );
    }
}
