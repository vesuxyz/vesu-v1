#[cfg(test)]
mod TestVToken {
    use alexandria_math::i257::{i257, i257_new, U256IntoI257};
    use integer::BoundedInt;
    use snforge_std::{
        cheatcodes::{start_warp, stop_warp, CheatTarget, start_prank, stop_prank, CheatSpan, prank}, declare
    };
    use starknet::{ContractAddress, get_contract_address, get_caller_address, deploy_syscall, contract_address_const};
    use vesu::{
        extension::default_extension::IDefaultExtensionDispatcherTrait, units::{SCALE, DAY_IN_SECONDS, YEAR_IN_SECONDS},
        data_model::{AssetConfig, Context, Position, Amount, AmountType, AmountDenomination, ModifyPositionParams},
        math::pow_10,
        common::{
            calculate_nominal_debt, calculate_debt, calculate_utilization, calculate_collateral_shares,
            calculate_collateral, deconstruct_collateral_amount, deconstruct_debt_amount, is_collateralized,
            apply_position_update_to_context, calculate_rate_accumulator, calculate_collateral_and_debt_value
        },
        vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait},
        v_token::{IVTokenDispatcher, IVTokenDispatcherTrait, IERC4626Dispatcher, IERC4626DispatcherTrait, VToken},
        test::setup::{deploy_contract, deploy_asset, setup, TestConfig, LendingTerms, deploy_with_args},
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
    };

    fn deploy_v_token() -> ContractAddress {
        let pool_id = '1';
        let v_token_class_hash = declare("VToken").class_hash;

        let singleton = deploy_contract("MockSingleton");
        let args = array![singleton.into()];
        let extension = deploy_with_args("MockExtension", args);
        let asset = deploy_asset(declare("MockAsset"), get_contract_address());
        let name = asset.name();
        let symbol = asset.symbol();

        let (v_token, _) = (deploy_syscall(
            v_token_class_hash.try_into().unwrap(),
            0,
            array!['v' + name, 'v' + symbol, 18, pool_id, extension.into(), asset.contract_address.into()].span(),
            true
        ))
            .unwrap();

        assert!(IVTokenDispatcher { contract_address: v_token }.pool_id() == pool_id, "pool_id not set");

        v_token
    }

    fn balance_of(v_token: ContractAddress, account: ContractAddress) -> u256 {
        IERC20Dispatcher { contract_address: v_token }.balance_of(account)
    }

    #[test]
    fn test_v_token_calculate_withdrawable_assets() {
        let scale = pow_10(12);
        assert(
            VToken::calculate_withdrawable_assets(
                AssetConfig {
                    total_collateral_shares: SCALE,
                    total_nominal_debt: SCALE,
                    reserve: scale,
                    max_utilization: SCALE,
                    floor: 0,
                    scale: scale,
                    is_legacy: false,
                    last_updated: 0,
                    last_rate_accumulator: SCALE,
                    last_full_utilization_rate: SCALE,
                    fee_rate: 0,
                },
                scale
            ) == scale,
            'room neq 1'
        );

        assert(
            VToken::calculate_withdrawable_assets(
                AssetConfig {
                    total_collateral_shares: SCALE,
                    total_nominal_debt: SCALE,
                    reserve: 2 * scale,
                    max_utilization: SCALE,
                    floor: 0,
                    scale: scale,
                    is_legacy: false,
                    last_updated: 0,
                    last_rate_accumulator: SCALE,
                    last_full_utilization_rate: SCALE,
                    fee_rate: 0,
                },
                scale
            ) == 2
                * scale,
            'room neq 2'
        );

        assert(
            VToken::calculate_withdrawable_assets(
                AssetConfig {
                    total_collateral_shares: SCALE,
                    total_nominal_debt: SCALE,
                    reserve: scale,
                    max_utilization: SCALE / 2,
                    floor: 0,
                    scale: scale,
                    is_legacy: false,
                    last_updated: 0,
                    last_rate_accumulator: SCALE,
                    last_full_utilization_rate: SCALE,
                    fee_rate: 0,
                },
                scale
            ) == 0,
            'room neq 3'
        );

        assert(
            VToken::calculate_withdrawable_assets(
                AssetConfig {
                    total_collateral_shares: SCALE,
                    total_nominal_debt: SCALE,
                    reserve: scale,
                    max_utilization: SCALE / 3,
                    floor: 0,
                    scale: scale,
                    is_legacy: false,
                    last_updated: 0,
                    last_rate_accumulator: SCALE,
                    last_full_utilization_rate: SCALE,
                    fee_rate: 0,
                },
                scale
            ) == 0,
            'room neq 4'
        );

        assert(
            VToken::calculate_withdrawable_assets(
                AssetConfig {
                    total_collateral_shares: SCALE,
                    total_nominal_debt: SCALE,
                    reserve: 9 * scale,
                    max_utilization: SCALE / 5,
                    floor: 0,
                    scale: scale,
                    is_legacy: false,
                    last_updated: 0,
                    last_rate_accumulator: SCALE,
                    last_full_utilization_rate: SCALE,
                    fee_rate: 0,
                },
                scale
            ) == 5
                * scale,
            'room neq 5'
        );
    }

    #[test]
    fn test_v_token_mint_v_token() {
        let v_token = IVTokenDispatcher { contract_address: deploy_v_token() };
        prank(CheatTarget::One(v_token.contract_address), v_token.extension(), CheatSpan::TargetCalls(1));
        v_token.mint_v_token(get_contract_address(), 100.into());
        assert(balance_of(v_token.contract_address, get_contract_address()) == 100, 'v_token not minted');
    }

    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_v_token_mint_v_token_not_extension() {
        let v_token = IVTokenDispatcher { contract_address: deploy_v_token() };
        v_token.mint_v_token(get_contract_address(), 100.into());
    }

    #[test]
    fn test_v_token_burn_v_token() {
        let v_token = IVTokenDispatcher { contract_address: deploy_v_token() };

        prank(CheatTarget::One(v_token.contract_address), v_token.extension(), CheatSpan::TargetCalls(1));
        IVTokenDispatcher { contract_address: v_token.contract_address }
            .mint_v_token(get_contract_address(), 100.into());

        assert(
            IERC20Dispatcher { contract_address: v_token.contract_address }.balance_of(get_contract_address()) == 100,
            'v_token not minted'
        );

        IERC20Dispatcher { contract_address: v_token.contract_address }.approve(v_token.extension(), 50.into());

        prank(CheatTarget::One(v_token.contract_address), v_token.extension(), CheatSpan::TargetCalls(1));
        IVTokenDispatcher { contract_address: v_token.contract_address }
            .burn_v_token(get_contract_address(), 50.into());

        assert(
            IERC20Dispatcher { contract_address: v_token.contract_address }.balance_of(get_contract_address()) == 50,
            'amount not burned'
        );
    }

    #[test]
    #[should_panic(expected: "caller-not-extension")]
    fn test_v_token_burn_v_token_not_extension() {
        let v_token = IVTokenDispatcher { contract_address: deploy_v_token() };

        prank(CheatTarget::One(v_token.contract_address), v_token.extension(), CheatSpan::TargetCalls(1));
        IVTokenDispatcher { contract_address: v_token.contract_address }
            .mint_v_token(get_contract_address(), 100.into());

        assert(
            IERC20Dispatcher { contract_address: v_token.contract_address }.balance_of(get_contract_address()) == 100,
            'v_token not minted'
        );

        IERC20Dispatcher { contract_address: v_token.contract_address }.approve(v_token.contract_address, 50.into());

        IVTokenDispatcher { contract_address: v_token.contract_address }
            .burn_v_token(get_contract_address(), 50.into());
    }

    #[test]
    fn test_v_token_asset() {
        let (_, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.asset() == collateral_asset.contract_address, 'asset not set');
    }

    #[test]
    fn test_v_token_total_assets() {
        let (singleton, extension, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let LendingTerms { collateral_to_deposit, .. } = terms;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.total_assets() == 0, 'total_assets');

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, collateral_to_deposit);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        let shares = v_token.deposit(collateral_to_deposit, users.lender);

        assert(
            v_token
                .total_assets() == singleton
                .calculate_collateral(pool_id, collateral_asset.contract_address, shares.into()),
            'total_assets neq'
        );
    }

    #[test]
    fn test_v_token_convert_to_shares() {
        let (singleton, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = v_token.convert_to_shares(assets);
        assert(
            shares == singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into()),
            'shares neq'
        );
    }

    #[test]
    fn test_v_token_convert_to_assets() {
        let (singleton, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let shares = 100000;
        let assets = v_token.convert_to_assets(shares);
        assert(
            assets == singleton.calculate_collateral(pool_id, collateral_asset.contract_address, -shares.into()),
            'assets neq'
        );
    }

    #[test]
    fn test_v_token_max_deposit() {
        let (_, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.max_deposit(Zeroable::zero()) > 0, 'max_deposit not set');
    }

    #[test]
    fn test_v_token_preview_deposit() {
        let (singleton, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = v_token.preview_deposit(assets);
        assert(
            shares == singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into()),
            'shares neq'
        );
    }

    #[test]
    fn test_v_token_deposit() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, assets);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        let shares = v_token.deposit(assets, users.lender);

        assert(
            shares == singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into()),
            'shares neq'
        );

        assert(balance_of(v_token.contract_address, users.lender) == shares, 'v_token not minted');
    }

    #[test]
    fn test_v_token_max_mint() {
        let (_, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.max_mint(Zeroable::zero()) > 0, 'max_mint not set');
    }

    #[test]
    fn test_v_token_preview_mint() {
        let (singleton, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into());
        assert(v_token.preview_mint(shares) == assets, 'assets neq');
    }

    #[test]
    fn test_v_token_mint() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into());

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, assets);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        assert(assets == v_token.mint(shares, users.lender), 'assets neq');

        assert(balance_of(v_token.contract_address, users.lender) == shares, 'v_token not minted');
    }

    #[test]
    fn test_v_token_max_withdraw() {
        let (_, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.max_withdraw(users.lender) == Zeroable::zero(), 'max_withdraw not zero');

        let assets = 100000;

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, assets);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        v_token.deposit(assets, users.lender);

        assert(v_token.max_withdraw(users.lender) == assets, 'max_withdraw not set');
    }

    #[test]
    fn test_v_token_preview_withdraw() {
        let (singleton, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = v_token.preview_withdraw(assets);
        assert(
            shares == singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, -assets.into()),
            'shares neq'
        );
    }

    #[test]
    fn test_v_token_withdraw() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into());

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, assets);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        v_token.deposit(assets, users.lender);

        assert(balance_of(v_token.contract_address, users.lender) == shares, 'v_token not minted');

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        let shares_ = v_token.withdraw(assets, users.lender, users.lender);

        assert(shares == shares_, 'shares neq');

        assert(balance_of(v_token.contract_address, users.lender) == 0, 'v_token not burned');
    }

    #[test]
    #[should_panic]
    fn test_v_token_withdraw_caller_not_approved() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into());

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, assets);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        v_token.deposit(assets, users.lender);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        IERC20Dispatcher { contract_address: v_token.contract_address }.approve(v_token.contract_address, shares);

        prank(CheatTarget::One(v_token.contract_address), users.borrower, CheatSpan::TargetCalls(1));
        v_token.withdraw(assets, users.lender, users.lender);
    }

    #[test]
    fn test_v_token_max_redeem() {
        let (_, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        assert(v_token.max_redeem(users.lender) == Zeroable::zero(), 'max_redeem not zero');

        let assets = 100000;

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, assets);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        let shares = v_token.deposit(assets, users.lender);

        assert(v_token.max_redeem(users.lender) == shares, 'max_redeem not set');
    }

    #[test]
    fn test_v_token_preview_redeem() {
        let (singleton, extension, config, _, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, -assets.into());
        assert(v_token.preview_redeem(shares) == assets, 'assets neq');
    }

    #[test]
    fn test_v_token_redeem() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into());

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, assets);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        v_token.mint(shares, users.lender);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        let assets_ = v_token.redeem(shares, users.lender, users.lender);

        assert(assets == assets_, 'assets neq');

        assert(balance_of(v_token.contract_address, users.lender) == 0, 'v_token not burned');
    }

    #[test]
    #[should_panic]
    fn test_v_token_redeem_caller_not_approved() {
        let (singleton, extension, config, users, _) = setup();
        let TestConfig { pool_id, collateral_asset, .. } = config;
        let v_token = IERC4626Dispatcher {
            contract_address: extension.v_token_for_collateral_asset(pool_id, collateral_asset.contract_address)
        };
        let assets = 100000;
        let shares = singleton.calculate_collateral_shares(pool_id, collateral_asset.contract_address, assets.into());

        prank(CheatTarget::One(collateral_asset.contract_address), users.lender, CheatSpan::TargetCalls(1));
        collateral_asset.approve(v_token.contract_address, assets);

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        v_token.mint(shares, users.lender);

        assert(balance_of(v_token.contract_address, users.lender) == shares, 'v_token not minted');

        prank(CheatTarget::One(v_token.contract_address), users.lender, CheatSpan::TargetCalls(1));
        IERC20Dispatcher { contract_address: v_token.contract_address }.approve(v_token.contract_address, shares);

        prank(CheatTarget::One(v_token.contract_address), users.borrower, CheatSpan::TargetCalls(1));
        v_token.redeem(shares, users.lender, users.lender);
    }
}
