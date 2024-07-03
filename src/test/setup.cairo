use snforge_std::{
    declare, ContractClass, ContractClassTrait, start_prank, stop_prank, start_warp, stop_warp, CheatTarget,
    get_class_hash
};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};
use vesu::vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait};
use vesu::{
    units::{SCALE, SCALE_128, PERCENT, DAY_IN_SECONDS}, singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
    data_model::{AssetParams, LTVParams}, extension::interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
    extension::default_extension::{
        IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait, InterestRateConfig, PragmaOracleParams,
        LiquidationParams, ShutdownParams, FeeParams
    },
    math::{pow_10}, vendor::pragma::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait},
    test::mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
};

#[derive(Copy, Drop, Serde)]
struct Users {
    creator: ContractAddress,
    lender: ContractAddress,
    borrower: ContractAddress,
}

#[derive(Copy, Drop, Serde)]
struct LendingTerms {
    liquidity_to_deposit: u256,
    liquidity_to_deposit_third: u256,
    collateral_to_deposit: u256,
    debt_to_draw: u256,
    rate_accumulator: u256,
    nominal_debt_to_draw: u256,
}

#[derive(Copy, Drop, Serde)]
struct TestConfig {
    pool_id: felt252,
    collateral_asset: IERC20Dispatcher,
    debt_asset: IERC20Dispatcher,
    third_asset: IERC20Dispatcher,
    collateral_scale: u256,
    debt_scale: u256,
    third_scale: u256
}

fn deploy_contract(name: ByteArray) -> ContractAddress {
    declare(name).deploy(@array![]).unwrap()
}

fn deploy_with_args(name: ByteArray, constructor_args: Array<felt252>) -> ContractAddress {
    declare(name).deploy(@constructor_args).unwrap()
}

fn deploy_assets(recipient: ContractAddress) -> (IERC20Dispatcher, IERC20Dispatcher, IERC20Dispatcher) {
    let class = declare("MockAsset");

    // mint 100 collateral and debt assets

    let decimals = 8;
    let supply = 100 * pow_10(decimals);
    let calldata = array![
        'Collateral', 'COLL', decimals.into(), supply.low.into(), supply.high.into(), recipient.into()
    ];
    let collateral_asset = IERC20Dispatcher { contract_address: class.deploy(@calldata).unwrap() };

    let decimals = 12;
    let supply = 100 * pow_10(decimals);
    let calldata = array!['Debt', 'DEBT', decimals.into(), supply.low.into(), supply.high.into(), recipient.into()];
    let debt_asset = IERC20Dispatcher { contract_address: class.deploy(@calldata).unwrap() };

    let decimals = 18;
    let supply = 100 * pow_10(decimals);
    let calldata = array!['Third', 'THIRD', decimals.into(), supply.low.into(), supply.high.into(), recipient.into()];
    let third_asset = IERC20Dispatcher { contract_address: class.deploy(@calldata).unwrap() };

    (collateral_asset, debt_asset, third_asset)
}

fn deploy_asset(class: ContractClass, recipient: ContractAddress) -> IERC20Dispatcher {
    let decimals = 18;
    let supply = 100 * pow_10(decimals);
    let calldata = array!['Asset', 'ASSET', decimals.into(), supply.low.into(), supply.high.into(), recipient.into()];
    let asset = IERC20Dispatcher { contract_address: class.deploy(@calldata).unwrap() };

    asset
}

fn setup_env(
    oracle_address: ContractAddress,
    collateral_address: ContractAddress,
    debt_address: ContractAddress,
    third_address: ContractAddress
) -> (ISingletonDispatcher, IDefaultExtensionDispatcher, TestConfig, Users) {
    let singleton = ISingletonDispatcher { contract_address: deploy_contract("Singleton") };

    start_warp(CheatTarget::All, get_block_timestamp() + 1);

    let users = Users {
        creator: contract_address_const::<'creator'>(),
        lender: contract_address_const::<'lender'>(),
        borrower: contract_address_const::<'borrower'>(),
    };

    let mock_pragma_oracle = IMockPragmaOracleDispatcher {
        contract_address: if oracle_address.is_non_zero() {
            oracle_address
        } else {
            deploy_contract("MockPragmaOracle")
        }
    };

    let args = array![singleton.contract_address.into(), mock_pragma_oracle.contract_address.into()];
    let extension = IDefaultExtensionDispatcher { contract_address: deploy_with_args("DefaultExtension", args) };

    // deploy collateral and borrow assets
    let (collateral_asset, debt_asset, third_asset) = if collateral_address.is_non_zero()
        && debt_address.is_non_zero()
        && third_address.is_non_zero() {
        (
            IERC20Dispatcher { contract_address: collateral_address },
            IERC20Dispatcher { contract_address: debt_address },
            IERC20Dispatcher { contract_address: third_address }
        )
    } else {
        deploy_assets(users.lender)
    };

    // approve Singleton to transfer assets on behalf of lender
    start_prank(CheatTarget::One(debt_asset.contract_address), users.lender);
    debt_asset.approve(singleton.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(debt_asset.contract_address));
    start_prank(CheatTarget::One(collateral_asset.contract_address), users.lender);
    collateral_asset.approve(singleton.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(collateral_asset.contract_address));
    start_prank(CheatTarget::One(third_asset.contract_address), users.lender);
    third_asset.approve(singleton.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(third_asset.contract_address));

    // approve Singleton to transfer assets on behalf of borrower
    start_prank(CheatTarget::One(debt_asset.contract_address), users.borrower);
    debt_asset.approve(singleton.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(debt_asset.contract_address));
    start_prank(CheatTarget::One(collateral_asset.contract_address), users.borrower);
    collateral_asset.approve(singleton.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(collateral_asset.contract_address));
    start_prank(CheatTarget::One(third_asset.contract_address), users.borrower);
    third_asset.approve(singleton.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(third_asset.contract_address));

    if oracle_address.is_zero() {
        mock_pragma_oracle.set_price(19514442401534788, SCALE_128);
        mock_pragma_oracle.set_price(5500394072219931460, SCALE_128);
        mock_pragma_oracle.set_price(18669995996566340, SCALE_128);
    }

    // create pool config
    let pool_id = singleton.calculate_pool_id(extension.contract_address, 1);
    let collateral_scale = pow_10(collateral_asset.decimals().into());
    let debt_scale = pow_10(debt_asset.decimals().into());
    let third_scale = pow_10(third_asset.decimals().into());
    let config = TestConfig {
        pool_id, collateral_asset, debt_asset, collateral_scale, debt_scale, third_asset, third_scale
    };

    (singleton, extension, config, users)
}

fn test_interest_rate_config() -> InterestRateConfig {
    InterestRateConfig {
        min_target_utilization: 75_000,
        max_target_utilization: 85_000,
        target_utilization: 87_500,
        min_full_utilization_rate: 1582470460,
        max_full_utilization_rate: 32150205761,
        zero_utilization_rate: 158247046,
        rate_half_life: 172_800,
        target_rate_percent: 20 * PERCENT,
    }
}

fn create_pool(
    extension: IDefaultExtensionDispatcher,
    config: TestConfig,
    creator: ContractAddress,
    interest_rate_config: Option<InterestRateConfig>,
) {
    let interest_rate_config = interest_rate_config.unwrap_or(test_interest_rate_config());

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
    let third_asset_params = AssetParams {
        asset: config.third_asset.contract_address,
        floor: SCALE / 10_000,
        initial_rate_accumulator: SCALE,
        initial_full_utilization_rate: (1582470460 + 32150205761) / 2,
        max_utilization: SCALE,
        is_legacy: false,
        fee_rate: 1 * PERCENT
    };

    let collateral_asset_oracle_params = PragmaOracleParams {
        pragma_key: 19514442401534788, timeout: 0, number_of_sources: 2
    };
    let debt_asset_oracle_params = PragmaOracleParams {
        pragma_key: 5500394072219931460, timeout: 0, number_of_sources: 2
    };
    let third_asset_oracle_params = PragmaOracleParams {
        pragma_key: 18669995996566340, timeout: 0, number_of_sources: 2
    };

    // create ltv config for collateral and borrow assets
    let max_position_ltv_params_0 = LTVParams {
        collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (80 * PERCENT).try_into().unwrap()
    };
    let max_position_ltv_params_1 = LTVParams {
        collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (80 * PERCENT).try_into().unwrap()
    };
    let max_position_ltv_params_2 = LTVParams {
        collateral_asset_index: 0, debt_asset_index: 2, max_ltv: (85 * PERCENT).try_into().unwrap()
    };
    let max_position_ltv_params_3 = LTVParams {
        collateral_asset_index: 2, debt_asset_index: 1, max_ltv: (85 * PERCENT).try_into().unwrap()
    };

    let collateral_asset_liquidation_params = LiquidationParams { liquidation_discount: 0 };
    let debt_asset_liquidation_params = LiquidationParams { liquidation_discount: 0 };
    let third_asset_liquidation_params = LiquidationParams { liquidation_discount: 0 };

    let shutdown_ltv_params_0 = LTVParams {
        collateral_asset_index: 1, debt_asset_index: 0, max_ltv: (75 * PERCENT).try_into().unwrap()
    };
    let shutdown_ltv_params_1 = LTVParams {
        collateral_asset_index: 0, debt_asset_index: 1, max_ltv: (75 * PERCENT).try_into().unwrap()
    };
    let shutdown_ltv_params_2 = LTVParams {
        collateral_asset_index: 0, debt_asset_index: 2, max_ltv: (75 * PERCENT).try_into().unwrap()
    };
    let shutdown_ltv_params_3 = LTVParams {
        collateral_asset_index: 2, debt_asset_index: 1, max_ltv: (75 * PERCENT).try_into().unwrap()
    };
    let shutdown_ltv_params = array![
        shutdown_ltv_params_0, shutdown_ltv_params_1, shutdown_ltv_params_2, shutdown_ltv_params_3
    ]
        .span();

    let asset_params = array![collateral_asset_params, debt_asset_params, third_asset_params].span();
    let max_position_ltv_params = array![
        max_position_ltv_params_0, max_position_ltv_params_1, max_position_ltv_params_2, max_position_ltv_params_3
    ]
        .span();
    let interest_rate_configs = array![interest_rate_config, interest_rate_config, interest_rate_config].span();
    let oracle_params = array![collateral_asset_oracle_params, debt_asset_oracle_params, third_asset_oracle_params]
        .span();
    let liquidation_params = array![
        collateral_asset_liquidation_params, debt_asset_liquidation_params, third_asset_liquidation_params
    ]
        .span();
    let shutdown_params = ShutdownParams {
        recovery_period: DAY_IN_SECONDS, subscription_period: DAY_IN_SECONDS, ltv_params: shutdown_ltv_params
    };

    start_prank(CheatTarget::One(extension.contract_address), creator);
    extension
        .create_pool(
            asset_params,
            max_position_ltv_params,
            interest_rate_configs,
            oracle_params,
            liquidation_params,
            shutdown_params,
            FeeParams { fee_recipient: creator },
            creator
        );
    stop_prank(CheatTarget::One(extension.contract_address));
}

fn setup_pool(
    oracle_address: ContractAddress,
    collateral_address: ContractAddress,
    debt_address: ContractAddress,
    third_address: ContractAddress,
    fund_borrower: bool,
    interest_rate_config: Option<InterestRateConfig>,
) -> (ISingletonDispatcher, IDefaultExtensionDispatcher, TestConfig, Users, LendingTerms) {
    let (singleton, extension, config, users) = setup_env(
        oracle_address, collateral_address, debt_address, third_address
    );

    create_pool(extension, config, users.creator, interest_rate_config);

    let TestConfig { pool_id, collateral_asset, debt_asset, collateral_scale, debt_scale, third_scale, .. } = config;

    // lending terms
    let liquidity_to_deposit = debt_scale;
    let liquidity_to_deposit_third = third_scale;
    let collateral_to_deposit = collateral_scale;
    let debt_to_draw = debt_scale / 2; // 50% LTV
    let rate_accumulator = singleton.asset_config(pool_id, debt_asset.contract_address).last_rate_accumulator;
    let nominal_debt_to_draw = singleton.calculate_nominal_debt(debt_to_draw.into(), rate_accumulator, debt_scale);

    let terms = LendingTerms {
        liquidity_to_deposit,
        collateral_to_deposit,
        debt_to_draw,
        rate_accumulator,
        nominal_debt_to_draw,
        liquidity_to_deposit_third
    };

    // fund borrower with collateral
    if fund_borrower {
        start_prank(CheatTarget::One(collateral_asset.contract_address), users.lender);
        collateral_asset.transfer(users.borrower, collateral_to_deposit * 2);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));
    }

    (singleton, extension, config, users, terms)
}

fn setup() -> (ISingletonDispatcher, IDefaultExtensionDispatcher, TestConfig, Users, LendingTerms) {
    setup_pool(Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), true, Option::None)
}
