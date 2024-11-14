use snforge_std::{
    declare, ContractClass, ContractClassTrait, start_prank, stop_prank, start_warp, stop_warp, CheatTarget, prank,
    CheatSpan, get_class_hash
};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};
use vesu::{
    units::{SCALE, SCALE_128, PERCENT, DAY_IN_SECONDS, INFLATION_FEE},
    singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
    data_model::{Amount, AmountDenomination, AmountType, ModifyPositionParams, AssetParams, LTVParams},
    extension::interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
    extension::default_extension_po::{
        IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait, InterestRateConfig, PragmaOracleParams,
        LiquidationParams, ShutdownParams, FeeParams, VTokenParams
    },
    extension::default_extension_cl::{
        IDefaultExtensionCLDispatcher, IDefaultExtensionCLDispatcherTrait, ChainlinkOracleParams
    },
    vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait}, math::{pow_10},
    vendor::pragma::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait},
    test::mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
    test::mock_chainlink_aggregator::{IMockChainlinkAggregatorDispatcher, IMockChainlinkAggregatorDispatcherTrait}
};

const COLL_PRAGMA_KEY: felt252 = 19514442401534788;
const DEBT_PRAGMA_KEY: felt252 = 5500394072219931460;
const THIRD_PRAGMA_KEY: felt252 = 18669995996566340;

#[derive(Copy, Drop, Serde)]
struct Users {
    creator: ContractAddress,
    lender: ContractAddress,
    borrower: ContractAddress,
    seeder: ContractAddress,
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
struct Env {
    singleton: ISingletonDispatcher,
    extension: IDefaultExtensionDispatcher,
    extension_v2: IDefaultExtensionCLDispatcher,
    config: TestConfig,
    users: Users
}

#[derive(Copy, Drop, Serde)]
struct TestConfig {
    pool_id: felt252,
    pool_id_v2: felt252,
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
    deploy_asset_with_decimals(class, recipient, 18)
}

fn deploy_asset_with_decimals(class: ContractClass, recipient: ContractAddress, decimals: u32) -> IERC20Dispatcher {
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
) -> Env {
    let singleton = ISingletonDispatcher { contract_address: deploy_contract("Singleton") };

    start_warp(CheatTarget::All, get_block_timestamp() + 1);

    let users = Users {
        creator: contract_address_const::<'creator'>(),
        lender: contract_address_const::<'lender'>(),
        borrower: contract_address_const::<'borrower'>(),
        seeder: contract_address_const::<'seeder'>(),
    };

    let mock_pragma_oracle = IMockPragmaOracleDispatcher {
        contract_address: if oracle_address.is_non_zero() {
            oracle_address
        } else {
            deploy_contract("MockPragmaOracle")
        }
    };

    let v_token_class_hash = declare("VToken").class_hash;

    let args = array![
        singleton.contract_address.into(), mock_pragma_oracle.contract_address.into(), v_token_class_hash.into()
    ];
    let extension = IDefaultExtensionDispatcher { contract_address: deploy_with_args("DefaultExtensionPO", args) };

    let args = array![singleton.contract_address.into(), v_token_class_hash.into()];
    let extension_v2 = IDefaultExtensionCLDispatcher { contract_address: deploy_with_args("DefaultExtensionCL", args) };

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

    // transfer 2x INFLATION_FEE to creator
    start_prank(CheatTarget::One(collateral_asset.contract_address), users.lender);
    collateral_asset.transfer(users.creator, INFLATION_FEE * 2);
    stop_prank(CheatTarget::One(collateral_asset.contract_address));
    start_prank(CheatTarget::One(debt_asset.contract_address), users.lender);
    debt_asset.transfer(users.creator, INFLATION_FEE * 2);
    stop_prank(CheatTarget::One(debt_asset.contract_address));
    start_prank(CheatTarget::One(third_asset.contract_address), users.lender);
    third_asset.transfer(users.creator, INFLATION_FEE * 2);
    stop_prank(CheatTarget::One(third_asset.contract_address));

    // approve Extension and ExtensionV2 to transfer assets on behalf of creator
    start_prank(CheatTarget::One(collateral_asset.contract_address), users.creator);
    collateral_asset.approve(extension.contract_address, integer::BoundedInt::max());
    collateral_asset.approve(extension_v2.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(collateral_asset.contract_address));
    start_prank(CheatTarget::One(debt_asset.contract_address), users.creator);
    debt_asset.approve(extension.contract_address, integer::BoundedInt::max());
    debt_asset.approve(extension_v2.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(debt_asset.contract_address));
    start_prank(CheatTarget::One(third_asset.contract_address), users.creator);
    third_asset.approve(extension.contract_address, integer::BoundedInt::max());
    third_asset.approve(extension_v2.contract_address, integer::BoundedInt::max());
    stop_prank(CheatTarget::One(third_asset.contract_address));

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
        mock_pragma_oracle.set_price(COLL_PRAGMA_KEY, SCALE_128);
        mock_pragma_oracle.set_price(DEBT_PRAGMA_KEY, SCALE_128);
        mock_pragma_oracle.set_price(THIRD_PRAGMA_KEY, SCALE_128);
    }

    // create pool config
    let pool_id = singleton.calculate_pool_id(extension.contract_address, 1);
    let pool_id_v2 = singleton.calculate_pool_id(extension_v2.contract_address, 1);
    let collateral_scale = pow_10(collateral_asset.decimals().into());
    let debt_scale = pow_10(debt_asset.decimals().into());
    let third_scale = pow_10(third_asset.decimals().into());
    let config = TestConfig {
        pool_id, pool_id_v2, collateral_asset, debt_asset, collateral_scale, debt_scale, third_asset, third_scale
    };

    Env { singleton, extension, extension_v2, config, users }
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
        pragma_key: COLL_PRAGMA_KEY, timeout: 0, number_of_sources: 2
    };
    let debt_asset_oracle_params = PragmaOracleParams { pragma_key: DEBT_PRAGMA_KEY, timeout: 0, number_of_sources: 2 };
    let third_asset_oracle_params = PragmaOracleParams {
        pragma_key: THIRD_PRAGMA_KEY, timeout: 0, number_of_sources: 2
    };

    let collateral_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Collateral', v_token_symbol: 'vCOLL' };
    let debt_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Debt', v_token_symbol: 'vDEBT' };
    let third_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Third', v_token_symbol: 'vTHIRD' };

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

    let liquidation_params_0 = LiquidationParams {
        collateral_asset_index: 0, debt_asset_index: 1, liquidation_factor: 0
    };
    let liquidation_params_1 = LiquidationParams {
        collateral_asset_index: 1, debt_asset_index: 0, liquidation_factor: 0
    };
    let liquidation_params_2 = LiquidationParams {
        collateral_asset_index: 0, debt_asset_index: 2, liquidation_factor: 0
    };
    let liquidation_params_3 = LiquidationParams {
        collateral_asset_index: 2, debt_asset_index: 1, liquidation_factor: 0
    };

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
    let v_token_params = array![collateral_asset_v_token_params, debt_asset_v_token_params, third_asset_v_token_params]
        .span();
    let max_position_ltv_params = array![
        max_position_ltv_params_0, max_position_ltv_params_1, max_position_ltv_params_2, max_position_ltv_params_3
    ]
        .span();
    let interest_rate_configs = array![interest_rate_config, interest_rate_config, interest_rate_config].span();
    let oracle_params = array![collateral_asset_oracle_params, debt_asset_oracle_params, third_asset_oracle_params]
        .span();
    let liquidation_params = array![
        liquidation_params_0, liquidation_params_1, liquidation_params_2, liquidation_params_3
    ]
        .span();
    let shutdown_params = ShutdownParams {
        recovery_period: DAY_IN_SECONDS, subscription_period: DAY_IN_SECONDS, ltv_params: shutdown_ltv_params
    };

    prank(CheatTarget::One(extension.contract_address), creator, CheatSpan::TargetCalls(1));
    extension
        .create_pool(
            'DefaultExtensionPO',
            asset_params,
            v_token_params,
            max_position_ltv_params,
            interest_rate_configs,
            oracle_params,
            liquidation_params,
            shutdown_params,
            FeeParams { fee_recipient: creator },
            creator
        );
    stop_prank(CheatTarget::One(extension.contract_address));

    let coll_v_token = extension.v_token_for_collateral_asset(config.pool_id, config.collateral_asset.contract_address);
    let debt_v_token = extension.v_token_for_collateral_asset(config.pool_id, config.debt_asset.contract_address);
    let third_v_token = extension.v_token_for_collateral_asset(config.pool_id, config.third_asset.contract_address);

    assert!(coll_v_token != Zeroable::zero(), "vToken not set");
    assert!(debt_v_token != Zeroable::zero(), "vToken not set");
    assert!(third_v_token != Zeroable::zero(), "vToken not set");

    assert!(extension.collateral_asset_for_v_token(config.pool_id, coll_v_token) != Zeroable::zero(), "vToken not set");
    assert!(extension.collateral_asset_for_v_token(config.pool_id, debt_v_token) != Zeroable::zero(), "vToken not set");
    assert!(
        extension.collateral_asset_for_v_token(config.pool_id, third_v_token) != Zeroable::zero(), "vToken not set"
    );

    assert!(extension.pool_name(config.pool_id) == 'DefaultExtensionPO', "pool name not set");
}

fn create_pool_v2(
    extension: IDefaultExtensionCLDispatcher,
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

    let class = declare("MockChainlinkAggregator");
    let calldata = array![];
    let collateral_mock_oracle = IMockChainlinkAggregatorDispatcher {
        contract_address: class.deploy(@calldata).unwrap()
    };
    let debt_mock_oracle = IMockChainlinkAggregatorDispatcher { contract_address: class.deploy(@calldata).unwrap() };
    let third_mock_oracle = IMockChainlinkAggregatorDispatcher { contract_address: class.deploy(@calldata).unwrap() };

    let collateral_asset_oracle_params = ChainlinkOracleParams {
        aggregator: collateral_mock_oracle.contract_address, timeout: 0
    };
    let debt_asset_oracle_params = ChainlinkOracleParams { aggregator: debt_mock_oracle.contract_address, timeout: 0 };
    let third_asset_oracle_params = ChainlinkOracleParams {
        aggregator: third_mock_oracle.contract_address, timeout: 0
    };

    let collateral_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Collateral', v_token_symbol: 'vCOLL' };
    let debt_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Debt', v_token_symbol: 'vDEBT' };
    let third_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Third', v_token_symbol: 'vTHIRD' };

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

    let liquidation_params_0 = LiquidationParams {
        collateral_asset_index: 0, debt_asset_index: 1, liquidation_factor: 0
    };
    let liquidation_params_1 = LiquidationParams {
        collateral_asset_index: 1, debt_asset_index: 0, liquidation_factor: 0
    };
    let liquidation_params_2 = LiquidationParams {
        collateral_asset_index: 0, debt_asset_index: 2, liquidation_factor: 0
    };
    let liquidation_params_3 = LiquidationParams {
        collateral_asset_index: 2, debt_asset_index: 1, liquidation_factor: 0
    };

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
    let v_token_params = array![collateral_asset_v_token_params, debt_asset_v_token_params, third_asset_v_token_params]
        .span();
    let max_position_ltv_params = array![
        max_position_ltv_params_0, max_position_ltv_params_1, max_position_ltv_params_2, max_position_ltv_params_3
    ]
        .span();
    let interest_rate_configs = array![interest_rate_config, interest_rate_config, interest_rate_config].span();
    let chainlink_oracle_params = array![
        collateral_asset_oracle_params, debt_asset_oracle_params, third_asset_oracle_params
    ]
        .span();
    let liquidation_params = array![
        liquidation_params_0, liquidation_params_1, liquidation_params_2, liquidation_params_3
    ]
        .span();
    let shutdown_params = ShutdownParams {
        recovery_period: DAY_IN_SECONDS, subscription_period: DAY_IN_SECONDS, ltv_params: shutdown_ltv_params
    };

    prank(CheatTarget::One(extension.contract_address), creator, CheatSpan::TargetCalls(1));
    extension
        .create_pool(
            'DefaultExtensionCL',
            asset_params,
            v_token_params,
            max_position_ltv_params,
            interest_rate_configs,
            chainlink_oracle_params,
            liquidation_params,
            shutdown_params,
            FeeParams { fee_recipient: creator },
            creator
        );
    stop_prank(CheatTarget::One(extension.contract_address));

    let coll_v_token = extension
        .v_token_for_collateral_asset(config.pool_id_v2, config.collateral_asset.contract_address);
    let debt_v_token = extension.v_token_for_collateral_asset(config.pool_id_v2, config.debt_asset.contract_address);
    let third_v_token = extension.v_token_for_collateral_asset(config.pool_id_v2, config.third_asset.contract_address);

    assert!(coll_v_token != Zeroable::zero(), "vToken not set");
    assert!(debt_v_token != Zeroable::zero(), "vToken not set");
    assert!(third_v_token != Zeroable::zero(), "vToken not set");

    assert!(
        extension.collateral_asset_for_v_token(config.pool_id_v2, coll_v_token) != Zeroable::zero(), "vToken not set"
    );
    assert!(
        extension.collateral_asset_for_v_token(config.pool_id_v2, debt_v_token) != Zeroable::zero(), "vToken not set"
    );
    assert!(
        extension.collateral_asset_for_v_token(config.pool_id_v2, third_v_token) != Zeroable::zero(), "vToken not set"
    );

    assert!(extension.pool_name(config.pool_id_v2) == 'DefaultExtensionCL', "pool name not set");
}

fn setup_pool(
    oracle_address: ContractAddress,
    collateral_address: ContractAddress,
    debt_address: ContractAddress,
    third_address: ContractAddress,
    fund_borrower: bool,
    interest_rate_config: Option<InterestRateConfig>,
) -> (ISingletonDispatcher, IDefaultExtensionDispatcher, TestConfig, Users, LendingTerms) {
    let Env { singleton, extension, config, users, .. } = setup_env(
        oracle_address, collateral_address, debt_address, third_address
    );

    create_pool(extension, config, users.creator, interest_rate_config);

    let TestConfig { pool_id,
    collateral_asset,
    debt_asset,
    third_asset,
    collateral_scale,
    debt_scale,
    third_scale,
    .. } =
        config;

    // lending terms
    let liquidity_to_deposit = debt_scale;
    let liquidity_to_deposit_third = third_scale;
    let collateral_to_deposit = collateral_scale;
    let debt_to_draw = debt_scale / 2; // 50% LTV
    let (asset_config, _) = singleton.asset_config_unsafe(pool_id, debt_asset.contract_address);
    let rate_accumulator = asset_config.last_rate_accumulator;
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

    start_prank(CheatTarget::One(extension.contract_address), users.creator);
    extension.set_asset_parameter(pool_id, collateral_asset.contract_address, 'floor', 0);
    extension.set_asset_parameter(pool_id, debt_asset.contract_address, 'floor', 0);
    extension.set_asset_parameter(pool_id, third_asset.contract_address, 'floor', 0);
    stop_prank(CheatTarget::One(extension.contract_address));

    start_prank(CheatTarget::One(extension.contract_address), users.creator);
    extension.set_asset_parameter(pool_id, collateral_asset.contract_address, 'floor', SCALE / 10_000);
    extension.set_asset_parameter(pool_id, debt_asset.contract_address, 'floor', SCALE / 10_000);
    extension.set_asset_parameter(pool_id, third_asset.contract_address, 'floor', SCALE / 10_000);
    stop_prank(CheatTarget::One(extension.contract_address));

    (singleton, extension, config, users, terms)
}

fn setup() -> (ISingletonDispatcher, IDefaultExtensionDispatcher, TestConfig, Users, LendingTerms) {
    setup_pool(Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), Zeroable::zero(), true, Option::None)
}
