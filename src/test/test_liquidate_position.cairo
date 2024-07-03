#[cfg(test)]
mod TestLiquidatePosition {
    use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, CheatTarget};
    use starknet::{contract_address_const, get_block_timestamp};
    use vesu::vendor::erc20::ERC20ABIDispatcherTrait;
    use vesu::{
        units::{SCALE_128},
        singleton::{
            ISingletonDispatcherTrait, Amount, AmountType, AmountDenomination, ModifyPositionParams,
            LiquidatePositionParams,
        },
        test::{
            mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
            setup::{setup, TestConfig, LendingTerms},
        },
        extension::default_extension::{IDefaultExtensionDispatcherTrait},
        extension::components::position_hooks::{LiquidationData}
    };

    #[test]
    fn test_liquidate_position_partial() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 * 1 / 2);

        let (position_before, _, debt) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt / 2 }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == position_before.collateral_shares / 2, 'not half of collateral shares');
        assert(position.nominal_debt == position_before.nominal_debt / 2, 'not half of nominal debt');
    }

    #[test]
    #[should_panic(expected: ('less-than-min-collateral',))]
    fn test_liquidate_position_partial_insufficient_collateral_released() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        // BORROWER

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

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 * 1 / 2);

        let (position_before, _, debt) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: collateral_to_deposit.into(), debt_to_repay: debt / 2 }
            .serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == position_before.collateral_shares / 2, 'not half of collateral shares');
        assert(position.nominal_debt == position_before.nominal_debt / 2, 'not half of nominal debt');
    }

    #[test]
    fn test_liquidate_position_full_no_bad_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let reserve_before = singleton.asset_configs(pool_id, debt_asset.contract_address).reserve;

        // BORROWER

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

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 * 1 / 2);

        let (_, _, debt) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');
        assert(
            reserve_before == singleton.asset_configs(pool_id, debt_asset.contract_address).reserve,
            'reserve should be the same'
        );
    }

    #[test]
    fn test_liquidate_position_full_bad_debt() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig{pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms{liquidity_to_deposit, collateral_to_deposit, nominal_debt_to_draw, .. } = terms;

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

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.modify_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let reserve_before = singleton.asset_configs(pool_id, debt_asset.contract_address).reserve;

        // BORROWER

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

        // LIQUIDATOR

        // reduce oracle price
        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128 * 1 / 4);

        let (_, _, debt) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: debt }.serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: collateral_asset.contract_address,
            debt_asset: debt_asset.contract_address,
            user: users.borrower,
            data: liquidation_data.span()
        };

        start_prank(CheatTarget::One(singleton.contract_address), users.lender);
        singleton.liquidate_position(params);
        stop_prank(CheatTarget::One(singleton.contract_address));

        let (position, _, _) = singleton
            .positions(pool_id, collateral_asset.contract_address, debt_asset.contract_address, users.borrower);
        assert(position.collateral_shares == 0, 'collateral shares should be 0');
        assert(position.nominal_debt == 0, 'debt shares should be 0');
        assert(
            reserve_before > singleton.asset_configs(pool_id, debt_asset.contract_address).reserve,
            'reserve should be the same'
        );
    }
}
