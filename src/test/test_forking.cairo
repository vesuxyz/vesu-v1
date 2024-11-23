use starknet::{ContractAddress};
use vesu::units::{PERCENT};

#[starknet::interface]
trait IStarkgateERC20<TContractState> {
    fn permissioned_mint(ref self: TContractState, account: ContractAddress, amount: u256);
}

fn to_percent(value: u256) -> u64 {
    (value * PERCENT).try_into().unwrap()
}

#[cfg(test)]
mod TestForking {
    use snforge_std::{
        start_cheat_caller_address, stop_cheat_caller_address, store, load, map_entry_address, declare,
        start_cheat_block_timestamp_global, cheat_caller_address, CheatSpan, DeclareResultTrait, ContractClassTrait
    };
    use starknet::{
        contract_address_const, get_caller_address, get_contract_address, ContractAddress, get_block_timestamp,
        get_block_number
    };
    use super::{IStarkgateERC20Dispatcher, IStarkgateERC20DispatcherTrait, to_percent};
    use vesu::{
        test::{
            setup::{setup_pool, deploy_contract, deploy_with_args},
            mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait},
            mock_chainlink_aggregator::{IMockChainlinkAggregatorDispatcher, IMockChainlinkAggregatorDispatcherTrait}
        },
        vendor::{
            erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait},
            chainlink::{IChainlinkAggregatorDispatcher, IChainlinkAggregatorDispatcherTrait, Round},
            pragma::{AggregationMode}
        },
        extension::{
            interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
            default_extension_po::{
                IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait, PragmaOracleParams, InterestRateConfig,
                LiquidationParams, ShutdownParams, FeeParams, VTokenParams, ShutdownMode
            },
            default_extension_cl::{
                IDefaultExtensionCLDispatcher, IDefaultExtensionCLDispatcherTrait, ChainlinkOracleParams
            },
            components::position_hooks::LiquidationData
        },
        units::{SCALE, SCALE_128, PERCENT, DAY_IN_SECONDS, INFLATION_FEE},
        data_model::{
            AssetParams, LTVParams, ModifyPositionParams, Amount, AmountType, AmountDenomination, AssetPrice,
            DebtCapParams
        },
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait, LiquidatePositionParams},
    };

    struct SetupParams {
        singleton: ISingletonDispatcher,
        extension: IDefaultExtensionDispatcher,
        eth: ERC20ABIDispatcher,
        usdc: ERC20ABIDispatcher,
        supplier: ContractAddress,
        borrower: ContractAddress,
        liquidator: ContractAddress,
        supply_amount_eth: u256,
        supply_amount_usdc: u256,
        borrow_amount_eth: u256,
        borrow_amount_usdc: u256,
        pool_id: felt252
    }

    struct SetupParamsCL {
        singleton: ISingletonDispatcher,
        extension: IDefaultExtensionCLDispatcher,
        eth: ERC20ABIDispatcher,
        usdc: ERC20ABIDispatcher,
        supplier: ContractAddress,
        borrower: ContractAddress,
        liquidator: ContractAddress,
        supply_amount_eth: u256,
        supply_amount_usdc: u256,
        borrow_amount_eth: u256,
        borrow_amount_usdc: u256,
        pool_id: felt252
    }

    fn generate_ltvs_for_pairs(all_asset_params: Span<AssetParams>, default_max_ltv: u64) -> Span<LTVParams> {
        let mut pair_max_ltvs: Array<LTVParams> = array![];

        let mut i = 0;
        loop {
            match all_asset_params.get(i) {
                Option::Some(boxed_asset_params) => {
                    let mut asset_params = *boxed_asset_params.unbox();
                    let mut j = 0;
                    loop {
                        match all_asset_params.get(j) {
                            Option::Some(boxed_paired_asset_params) => {
                                let mut paired_asset_params = *boxed_paired_asset_params.unbox();
                                if asset_params.asset != paired_asset_params.asset {
                                    pair_max_ltvs
                                        .append(
                                            LTVParams {
                                                collateral_asset_index: i, debt_asset_index: j, max_ltv: default_max_ltv
                                            }
                                        );
                                }
                            },
                            Option::None(_) => { break; }
                        };
                        j += 1;
                    };
                },
                Option::None(_) => { break; }
            };
            i += 1;
        };

        pair_max_ltvs.span()
    }

    fn generate_interest_rate_configs(all_asset_params: Span<AssetParams>) -> Span<InterestRateConfig> {
        let mut interest_rate_configs: Array<InterestRateConfig> = array![];

        let mut i = 0;
        loop {
            match all_asset_params.get(i) {
                Option::Some(_) => {
                    interest_rate_configs
                        .append(
                            InterestRateConfig {
                                min_target_utilization: 78_000,
                                max_target_utilization: 82_000,
                                target_utilization: 80_000,
                                min_full_utilization_rate: 500,
                                max_full_utilization_rate: 100_000,
                                zero_utilization_rate: 100,
                                rate_half_life: 86400,
                                target_rate_percent: to_percent(20).into()
                            }
                        );
                },
                Option::None(_) => { break; }
            };
            i += 1;
        };

        interest_rate_configs.span()
    }

    fn generate_liquidation_params(
        all_asset_params: Span<AssetParams>, default_liquidation_factor: u64
    ) -> Span<LiquidationParams> {
        let mut liquidation_params: Array<LiquidationParams> = array![];

        let mut i = 0;
        loop {
            match all_asset_params.get(i) {
                Option::Some(boxed_asset_params) => {
                    let mut asset_params = *boxed_asset_params.unbox();
                    let mut j = 0;
                    loop {
                        match all_asset_params.get(j) {
                            Option::Some(boxed_paired_asset_params) => {
                                let mut paired_asset_params = *boxed_paired_asset_params.unbox();
                                if asset_params.asset != paired_asset_params.asset {
                                    liquidation_params
                                        .append(
                                            LiquidationParams {
                                                collateral_asset_index: i,
                                                debt_asset_index: j,
                                                liquidation_factor: default_liquidation_factor
                                            }
                                        );
                                }
                            },
                            Option::None(_) => { break; }
                        };
                        j += 1;
                    };
                },
                Option::None(_) => { break; }
            };
            i += 1;
        };

        liquidation_params.span()
    }

    fn generate_debt_caps_for_pairs(
        all_asset_params: Span<AssetParams>, default_debt_cap: u256
    ) -> Span<DebtCapParams> {
        let mut pair_debt_caps: Array<DebtCapParams> = array![];

        let mut i = 0;
        loop {
            match all_asset_params.get(i) {
                Option::Some(boxed_asset_params) => {
                    let mut asset_params = *boxed_asset_params.unbox();
                    let mut j = 0;
                    loop {
                        match all_asset_params.get(j) {
                            Option::Some(boxed_paired_asset_params) => {
                                let mut paired_asset_params = *boxed_paired_asset_params.unbox();
                                if asset_params.asset != paired_asset_params.asset {
                                    pair_debt_caps
                                        .append(
                                            DebtCapParams {
                                                collateral_asset_index: i,
                                                debt_asset_index: j,
                                                debt_cap: default_debt_cap
                                            }
                                        );
                                }
                            },
                            Option::None(_) => { break; }
                        };
                        j += 1;
                    };
                },
                Option::None(_) => { break; }
            };
            i += 1;
        };

        pair_debt_caps.span()
    }

    fn generate_shutdown_params(all_asset_params: Span<AssetParams>) -> ShutdownParams {
        let mut shutdown_params = ShutdownParams {
            recovery_period: DAY_IN_SECONDS * 30,
            subscription_period: DAY_IN_SECONDS * 30,
            ltv_params: generate_ltvs_for_pairs(all_asset_params, to_percent(95))
        };

        shutdown_params
    }

    fn setup() -> SetupParams {
        let pragma_oracle_address = contract_address_const::<
            0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b
        >();
        let summary_stats_address = contract_address_const::<
            0x049eefafae944d07744d07cc72a5bf14728a6fb463c3eae5bca13552f5d455fd
        >();

        let eth_asset_params = AssetParams {
            asset: contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
            floor: 10000000000000000, // 0.01
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let eth_asset_oracle_params = PragmaOracleParams {
            pragma_key: 'ETH/USD',
            timeout: 0,
            number_of_sources: 0,
            start_time_offset: 0,
            time_window: 0,
            aggregation_mode: AggregationMode::Median(())
        };

        let eth_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Ethereum', v_token_symbol: 'vETH' };

        let wbtc_asset_params = AssetParams {
            asset: contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>(),
            floor: 100000000000000, // 0.0001
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let wbtc_asset_oracle_params = PragmaOracleParams {
            pragma_key: 'WBTC/USD',
            timeout: 0,
            number_of_sources: 0,
            start_time_offset: 0,
            time_window: 0,
            aggregation_mode: AggregationMode::Median(())
        };

        let wbtc_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Wrapped Bitcoin', v_token_symbol: 'vWBTC' };

        let usdc_asset_params = AssetParams {
            asset: contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            floor: 1000000000000000000, // 1
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let usdc_asset_oracle_params = PragmaOracleParams {
            pragma_key: 'USDC/USD',
            timeout: 0,
            number_of_sources: 2,
            start_time_offset: 86400 * 7,
            time_window: 86400 * 6,
            aggregation_mode: AggregationMode::Median(())
        };

        let usdc_asset_v_token_params = VTokenParams { v_token_name: 'Vesu USD Coin', v_token_symbol: 'vUSDC' };

        let usdt_asset_params = AssetParams {
            asset: contract_address_const::<0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8>(),
            floor: 1000000000000000000, // 1
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let usdt_asset_oracle_params = PragmaOracleParams {
            pragma_key: 'USDT/USD',
            timeout: 0,
            number_of_sources: 0,
            start_time_offset: 0,
            time_window: 0,
            aggregation_mode: AggregationMode::Median(())
        };

        let usdt_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Tether', v_token_symbol: 'vUSDT' };

        let wsteth_asset_params = AssetParams {
            asset: contract_address_const::<0x042b8f0484674ca266ac5d08e4ac6a3fe65bd3129795def2dca5c34ecc5f96d2>(),
            floor: 10000000000000000, // 0.01
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let wsteth_asset_oracle_params = PragmaOracleParams {
            pragma_key: 'WSTETH/USD',
            timeout: 0,
            number_of_sources: 0,
            start_time_offset: 0,
            time_window: 0,
            aggregation_mode: AggregationMode::Median(())
        };

        let wsteth_asset_v_token_params = VTokenParams {
            v_token_name: 'Vesu Wrapped Staked Ether', v_token_symbol: 'vWSTETH'
        };

        let strk_asset_params = AssetParams {
            asset: contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
            floor: 1000000000000000000, // 1
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let strk_asset_oracle_params = PragmaOracleParams {
            pragma_key: 'STRK/USD',
            timeout: 0,
            number_of_sources: 0,
            start_time_offset: 0,
            time_window: 0,
            aggregation_mode: AggregationMode::Median(())
        };

        let strk_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Starknet', v_token_symbol: 'vSTRK' };

        let asset_params = array![
            eth_asset_params,
            wbtc_asset_params,
            usdc_asset_params,
            usdt_asset_params,
            wsteth_asset_params,
            strk_asset_params
        ]
            .span();

        let oracle_params = array![
            eth_asset_oracle_params,
            wbtc_asset_oracle_params,
            usdc_asset_oracle_params,
            usdt_asset_oracle_params,
            wsteth_asset_oracle_params,
            strk_asset_oracle_params
        ]
            .span();

        let v_token_params = array![
            eth_asset_v_token_params,
            wbtc_asset_v_token_params,
            usdc_asset_v_token_params,
            usdt_asset_v_token_params,
            wsteth_asset_v_token_params,
            strk_asset_v_token_params
        ]
            .span();

        let eth_wbtc_ltv_params = LTVParams { collateral_asset_index: 0, debt_asset_index: 1, max_ltv: to_percent(82) };
        let eth_usdc_ltv_params = LTVParams { collateral_asset_index: 0, debt_asset_index: 2, max_ltv: to_percent(74) };
        let eth_usdt_ltv_params = LTVParams { collateral_asset_index: 0, debt_asset_index: 3, max_ltv: to_percent(74) };
        let eth_wsteth_ltv_params = LTVParams {
            collateral_asset_index: 0, debt_asset_index: 4, max_ltv: to_percent(87)
        };
        let eth_strk_ltv_params = LTVParams { collateral_asset_index: 0, debt_asset_index: 5, max_ltv: to_percent(71) };
        let wbtc_eth_ltv_params = LTVParams { collateral_asset_index: 1, debt_asset_index: 0, max_ltv: to_percent(82) };
        let wbtc_usdc_ltv_params = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 2, max_ltv: to_percent(74)
        };
        let wbtc_usdt_ltv_params = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 3, max_ltv: to_percent(74)
        };
        let wbtc_wsteth_ltv_params = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 4, max_ltv: to_percent(75)
        };
        let wbtc_strk_ltv_params = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 5, max_ltv: to_percent(59)
        };
        let usdc_eth_ltv_params = LTVParams { collateral_asset_index: 2, debt_asset_index: 0, max_ltv: to_percent(68) };
        let usdc_wbtc_ltv_params = LTVParams {
            collateral_asset_index: 2, debt_asset_index: 1, max_ltv: to_percent(68)
        };
        let usdc_usdt_ltv_params = LTVParams {
            collateral_asset_index: 2, debt_asset_index: 3, max_ltv: to_percent(93)
        };
        let usdc_wsteth_ltv_params = LTVParams {
            collateral_asset_index: 2, debt_asset_index: 4, max_ltv: to_percent(72)
        };
        let usdc_strk_ltv_params = LTVParams {
            collateral_asset_index: 2, debt_asset_index: 5, max_ltv: to_percent(60)
        };
        let usdt_eth_ltv_params = LTVParams { collateral_asset_index: 3, debt_asset_index: 0, max_ltv: to_percent(66) };
        let usdt_wbtc_ltv_params = LTVParams {
            collateral_asset_index: 3, debt_asset_index: 1, max_ltv: to_percent(65)
        };
        let usdt_usdc_ltv_params = LTVParams {
            collateral_asset_index: 3, debt_asset_index: 2, max_ltv: to_percent(93)
        };
        let usdt_wsteth_ltv_params = LTVParams {
            collateral_asset_index: 3, debt_asset_index: 4, max_ltv: to_percent(63)
        };
        let usdt_strk_ltv_params = LTVParams {
            collateral_asset_index: 3, debt_asset_index: 5, max_ltv: to_percent(58)
        };
        let wsteth_eth_ltv_params = LTVParams {
            collateral_asset_index: 4, debt_asset_index: 0, max_ltv: to_percent(87)
        };
        let wsteth_wbtc_ltv_params = LTVParams {
            collateral_asset_index: 4, debt_asset_index: 1, max_ltv: to_percent(81)
        };
        let wsteth_usdc_ltv_params = LTVParams {
            collateral_asset_index: 4, debt_asset_index: 2, max_ltv: to_percent(71)
        };
        let wsteth_usdt_ltv_params = LTVParams {
            collateral_asset_index: 4, debt_asset_index: 3, max_ltv: to_percent(73)
        };
        let wsteth_strk_ltv_params = LTVParams {
            collateral_asset_index: 4, debt_asset_index: 5, max_ltv: to_percent(68)
        };
        let strk_eth_ltv_params = LTVParams { collateral_asset_index: 5, debt_asset_index: 0, max_ltv: to_percent(57) };
        let strk_wbtc_ltv_params = LTVParams {
            collateral_asset_index: 5, debt_asset_index: 1, max_ltv: to_percent(46)
        };
        let strk_usdc_ltv_params = LTVParams {
            collateral_asset_index: 5, debt_asset_index: 2, max_ltv: to_percent(59)
        };
        let strk_usdt_ltv_params = LTVParams {
            collateral_asset_index: 5, debt_asset_index: 3, max_ltv: to_percent(57)
        };
        let strk_wsteth_ltv_params = LTVParams {
            collateral_asset_index: 5, debt_asset_index: 4, max_ltv: to_percent(55)
        };

        let max_ltv_params = array![
            eth_wbtc_ltv_params,
            eth_usdc_ltv_params,
            eth_usdt_ltv_params,
            eth_wsteth_ltv_params,
            eth_strk_ltv_params,
            wbtc_eth_ltv_params,
            wbtc_usdc_ltv_params,
            wbtc_usdt_ltv_params,
            wbtc_wsteth_ltv_params,
            wbtc_strk_ltv_params,
            usdc_eth_ltv_params,
            usdc_wbtc_ltv_params,
            usdc_usdt_ltv_params,
            usdc_wsteth_ltv_params,
            usdc_strk_ltv_params,
            usdt_eth_ltv_params,
            usdt_wbtc_ltv_params,
            usdt_usdc_ltv_params,
            usdt_wsteth_ltv_params,
            usdt_strk_ltv_params,
            wsteth_eth_ltv_params,
            wsteth_wbtc_ltv_params,
            wsteth_usdc_ltv_params,
            wsteth_usdt_ltv_params,
            wsteth_strk_ltv_params,
            strk_eth_ltv_params,
            strk_wbtc_ltv_params,
            strk_usdc_ltv_params,
            strk_usdt_ltv_params,
            strk_wsteth_ltv_params
        ]
            .span();

        let interest_rate_configs = generate_interest_rate_configs(asset_params);
        let liquidation_params = generate_liquidation_params(asset_params, ((9 * SCALE) / 10).try_into().unwrap());
        let debt_caps_params = generate_debt_caps_for_pairs(asset_params, 0);
        let shutdown_params = generate_shutdown_params(asset_params);

        let singleton = ISingletonDispatcher { contract_address: deploy_contract("Singleton") };
        // let singleton = ISingletonDispatcher {
        //     contract_address: contract_address_const::<
        //         0x2545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef
        //     >()
        // };
        let v_token_class_hash: felt252 = (*declare("VToken").unwrap().contract_class().class_hash).try_into().unwrap();
        // let v_token_class_hash = 0x05c64c6cb528bdbffe4187ba3385ff3843b43e8375ad4c3ddd6c28c1d5193576;
        let extension = IDefaultExtensionDispatcher {
            contract_address: deploy_with_args(
                "DefaultExtensionPO",
                array![
                    singleton.contract_address.into(),
                    pragma_oracle_address.into(),
                    summary_stats_address.into(),
                    v_token_class_hash.into()
                ]
            )
        };

        // get funds
        let creator = contract_address_const::<'creator'>();
        let supplier = contract_address_const::<'supplier'>();
        let borrower = contract_address_const::<'borrower'>();
        let liquidator = contract_address_const::<'liquidator'>();
        let supply_amount_eth = 100000000 * SCALE;
        let supply_amount_usdc = 100_000_000__000_000;
        let borrow_amount_eth = 100 * SCALE;
        let borrow_amount_usdc = 600_000__000_000;

        let eth_asset_params: AssetParams = *asset_params[0];
        let eth = ERC20ABIDispatcher { contract_address: eth_asset_params.asset };
        let loaded = load(eth_asset_params.asset, selector!("permitted_minter"), 1);
        let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
        start_cheat_caller_address(eth_asset_params.asset, minter);
        IStarkgateERC20Dispatcher { contract_address: eth_asset_params.asset }
            .permissioned_mint(supplier, supply_amount_eth);
        IStarkgateERC20Dispatcher { contract_address: eth_asset_params.asset }
            .permissioned_mint(borrower, borrow_amount_eth * 2);
        IStarkgateERC20Dispatcher { contract_address: eth_asset_params.asset }
            .permissioned_mint(liquidator, borrow_amount_eth);
        IStarkgateERC20Dispatcher { contract_address: eth_asset_params.asset }
            .permissioned_mint(creator, INFLATION_FEE);
        stop_cheat_caller_address(eth_asset_params.asset);
        start_cheat_caller_address(eth.contract_address, creator);
        eth.approve(extension.contract_address, INFLATION_FEE);
        stop_cheat_caller_address(eth.contract_address);

        let btc_asset_params: AssetParams = *asset_params[1];
        let btc = ERC20ABIDispatcher { contract_address: btc_asset_params.asset };
        let loaded = load(btc_asset_params.asset, selector!("permitted_minter"), 1);
        let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
        start_cheat_caller_address(btc_asset_params.asset, minter);
        IStarkgateERC20Dispatcher { contract_address: btc_asset_params.asset }
            .permissioned_mint(creator, INFLATION_FEE);
        stop_cheat_caller_address(btc_asset_params.asset);
        start_cheat_caller_address(btc.contract_address, creator);
        btc.approve(extension.contract_address, INFLATION_FEE);
        stop_cheat_caller_address(btc.contract_address);

        let usdc_asset_params: AssetParams = *asset_params[2];
        let usdc = ERC20ABIDispatcher { contract_address: usdc_asset_params.asset };
        let loaded = load(usdc_asset_params.asset, selector!("permitted_minter"), 1);
        let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
        start_cheat_caller_address(usdc_asset_params.asset, minter);
        IStarkgateERC20Dispatcher { contract_address: usdc_asset_params.asset }
            .permissioned_mint(supplier, supply_amount_usdc);
        IStarkgateERC20Dispatcher { contract_address: usdc_asset_params.asset }
            .permissioned_mint(borrower, borrow_amount_usdc);
        IStarkgateERC20Dispatcher { contract_address: usdc_asset_params.asset }
            .permissioned_mint(creator, INFLATION_FEE);
        stop_cheat_caller_address(usdc_asset_params.asset);
        start_cheat_caller_address(usdc.contract_address, creator);
        usdc.approve(extension.contract_address, INFLATION_FEE);
        stop_cheat_caller_address(usdc.contract_address);

        let usdt_asset_params: AssetParams = *asset_params[3];
        let usdt = ERC20ABIDispatcher { contract_address: usdt_asset_params.asset };
        let loaded = load(usdt_asset_params.asset, selector!("permitted_minter"), 1);
        let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
        start_cheat_caller_address(usdt_asset_params.asset, minter);
        IStarkgateERC20Dispatcher { contract_address: usdt_asset_params.asset }
            .permissioned_mint(creator, INFLATION_FEE);
        stop_cheat_caller_address(usdt_asset_params.asset);
        start_cheat_caller_address(usdt.contract_address, creator);
        usdt.approve(extension.contract_address, INFLATION_FEE);
        stop_cheat_caller_address(usdt.contract_address);

        let strk_asset_params: AssetParams = *asset_params[4];
        let strk = ERC20ABIDispatcher { contract_address: strk_asset_params.asset };
        let loaded = load(strk_asset_params.asset, selector!("permitted_minter"), 1);
        let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
        start_cheat_caller_address(strk_asset_params.asset, minter);
        IStarkgateERC20Dispatcher { contract_address: strk_asset_params.asset }
            .permissioned_mint(creator, INFLATION_FEE);
        stop_cheat_caller_address(strk_asset_params.asset);
        start_cheat_caller_address(strk.contract_address, creator);
        strk.approve(extension.contract_address, INFLATION_FEE);
        stop_cheat_caller_address(strk.contract_address);

        let wsteth_asset_params: AssetParams = *asset_params[5];
        let wsteth = ERC20ABIDispatcher { contract_address: wsteth_asset_params.asset };
        let loaded = load(wsteth_asset_params.asset, selector!("permitted_minter"), 1);
        let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
        start_cheat_caller_address(wsteth_asset_params.asset, minter);
        IStarkgateERC20Dispatcher { contract_address: wsteth_asset_params.asset }
            .permissioned_mint(creator, INFLATION_FEE);
        stop_cheat_caller_address(wsteth_asset_params.asset);
        start_cheat_caller_address(wsteth.contract_address, creator);
        wsteth.approve(extension.contract_address, INFLATION_FEE);
        stop_cheat_caller_address(wsteth.contract_address);

        let pool_id = singleton.calculate_pool_id(extension.contract_address, 1);

        cheat_caller_address(extension.contract_address, creator, CheatSpan::TargetCalls(1));
        extension
            .create_pool(
                'DefaultExtensionPO',
                asset_params,
                v_token_params,
                max_ltv_params,
                interest_rate_configs,
                oracle_params,
                liquidation_params,
                debt_caps_params,
                shutdown_params,
                FeeParams { fee_recipient: creator },
                creator
            );
        stop_cheat_caller_address(extension.contract_address);

        let mut i = 0;
        loop {
            match asset_params.get(i) {
                Option::Some(boxed_asset_params) => {
                    let mut asset_params = *boxed_asset_params.unbox();
                    let price = IExtensionDispatcher { contract_address: extension.contract_address }
                        .price(pool_id, asset_params.asset);
                    assert!(price.value > 0, "No data");
                },
                Option::None(_) => { break; }
            };
            i += 1;
        };

        store(
            extension.contract_address,
            map_entry_address(selector!("oracle_configs"), array![pool_id, usdc.contract_address.into()].span(),),
            array!['USDC/USD', 0, 2, 0, 0, 1].span()
        );

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        SetupParams {
            singleton,
            extension,
            eth,
            usdc,
            supplier,
            borrower,
            liquidator,
            supply_amount_eth,
            supply_amount_usdc,
            borrow_amount_eth,
            borrow_amount_usdc,
            pool_id
        }
    }

    fn setup_cl() -> SetupParamsCL {
        let eth_asset_params = AssetParams {
            asset: contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
            floor: 10000000000000000, // 0.01
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let eth_asset_oracle_params = ChainlinkOracleParams {
            aggregator: contract_address_const::<0x6b2ef9b416ad0f996b2a8ac0dd771b1788196f51c96f5b000df2e47ac756d26>(),
            timeout: 0
        };

        let eth_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Ethereum', v_token_symbol: 'vETH' };

        let wbtc_asset_params = AssetParams {
            asset: contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>(),
            floor: 100000000000000, // 0.0001
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let wbtc_asset_oracle_params = ChainlinkOracleParams {
            aggregator: contract_address_const::<0x6275040a2913e2fe1a20bead3feb40694920a7fea98e956b042e082b9e1adad>(),
            timeout: 0
        };

        let wbtc_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Wrapped Bitcoin', v_token_symbol: 'vWBTC' };

        let usdc_asset_params = AssetParams {
            asset: contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            floor: 1000000000000000000, // 1
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let usdc_asset_oracle_params = ChainlinkOracleParams {
            aggregator: contract_address_const::<0x72495dbb867dd3c6373820694008f8a8bff7b41f7f7112245d687858b243470>(),
            timeout: 0
        };

        let usdc_asset_v_token_params = VTokenParams { v_token_name: 'Vesu USD Coin', v_token_symbol: 'vUSDC' };

        let usdt_asset_params = AssetParams {
            asset: contract_address_const::<0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8>(),
            floor: 1000000000000000000, // 1
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let usdt_asset_oracle_params = ChainlinkOracleParams {
            aggregator: contract_address_const::<0x1cafc789a9b48f816fe0969c22667ea2d669e56274c806fc83a85215d42e988>(),
            timeout: 0
        };

        let usdt_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Tether', v_token_symbol: 'vUSDT' };

        let strk_asset_params = AssetParams {
            asset: contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
            floor: 1000000000000000000, // 1
            initial_rate_accumulator: SCALE,
            initial_full_utilization_rate: to_percent(50).into(),
            max_utilization: to_percent(80).into(),
            is_legacy: false,
            fee_rate: 0
        };

        let strk_asset_oracle_params = ChainlinkOracleParams {
            aggregator: contract_address_const::<0x76a0254cdadb59b86da3b5960bf8d73779cac88edc5ae587cab3cedf03226ec>(),
            timeout: 0
        };

        let strk_asset_v_token_params = VTokenParams { v_token_name: 'Vesu Starknet', v_token_symbol: 'vSTRK' };

        let asset_params = array![
            eth_asset_params, wbtc_asset_params, usdc_asset_params, usdt_asset_params, strk_asset_params
        ]
            .span();

        let oracle_params = array![
            eth_asset_oracle_params,
            wbtc_asset_oracle_params,
            usdc_asset_oracle_params,
            usdt_asset_oracle_params,
            strk_asset_oracle_params
        ]
            .span();

        let v_token_params = array![
            eth_asset_v_token_params,
            wbtc_asset_v_token_params,
            usdc_asset_v_token_params,
            usdt_asset_v_token_params,
            strk_asset_v_token_params
        ]
            .span();

        let eth_wbtc_ltv_params = LTVParams { collateral_asset_index: 0, debt_asset_index: 1, max_ltv: to_percent(82) };
        let eth_usdc_ltv_params = LTVParams { collateral_asset_index: 0, debt_asset_index: 2, max_ltv: to_percent(74) };
        let eth_usdt_ltv_params = LTVParams { collateral_asset_index: 0, debt_asset_index: 3, max_ltv: to_percent(74) };
        let eth_strk_ltv_params = LTVParams { collateral_asset_index: 0, debt_asset_index: 4, max_ltv: to_percent(71) };
        let wbtc_eth_ltv_params = LTVParams { collateral_asset_index: 1, debt_asset_index: 0, max_ltv: to_percent(82) };
        let wbtc_usdc_ltv_params = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 2, max_ltv: to_percent(74)
        };
        let wbtc_usdt_ltv_params = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 3, max_ltv: to_percent(74)
        };
        let wbtc_strk_ltv_params = LTVParams {
            collateral_asset_index: 1, debt_asset_index: 4, max_ltv: to_percent(59)
        };
        let usdc_eth_ltv_params = LTVParams { collateral_asset_index: 2, debt_asset_index: 0, max_ltv: to_percent(68) };
        let usdc_wbtc_ltv_params = LTVParams {
            collateral_asset_index: 2, debt_asset_index: 1, max_ltv: to_percent(68)
        };
        let usdc_usdt_ltv_params = LTVParams {
            collateral_asset_index: 2, debt_asset_index: 3, max_ltv: to_percent(93)
        };
        let usdc_strk_ltv_params = LTVParams {
            collateral_asset_index: 2, debt_asset_index: 4, max_ltv: to_percent(60)
        };
        let usdt_eth_ltv_params = LTVParams { collateral_asset_index: 3, debt_asset_index: 0, max_ltv: to_percent(66) };
        let usdt_wbtc_ltv_params = LTVParams {
            collateral_asset_index: 3, debt_asset_index: 1, max_ltv: to_percent(65)
        };
        let usdt_usdc_ltv_params = LTVParams {
            collateral_asset_index: 3, debt_asset_index: 2, max_ltv: to_percent(93)
        };
        let usdt_strk_ltv_params = LTVParams {
            collateral_asset_index: 3, debt_asset_index: 4, max_ltv: to_percent(58)
        };
        let strk_eth_ltv_params = LTVParams { collateral_asset_index: 4, debt_asset_index: 0, max_ltv: to_percent(57) };
        let strk_wbtc_ltv_params = LTVParams {
            collateral_asset_index: 4, debt_asset_index: 1, max_ltv: to_percent(46)
        };
        let strk_usdc_ltv_params = LTVParams {
            collateral_asset_index: 4, debt_asset_index: 2, max_ltv: to_percent(59)
        };
        let strk_usdt_ltv_params = LTVParams {
            collateral_asset_index: 4, debt_asset_index: 3, max_ltv: to_percent(57)
        };

        let max_ltv_params = array![
            eth_wbtc_ltv_params,
            eth_usdc_ltv_params,
            eth_usdt_ltv_params,
            eth_strk_ltv_params,
            wbtc_eth_ltv_params,
            wbtc_usdc_ltv_params,
            wbtc_usdt_ltv_params,
            wbtc_strk_ltv_params,
            usdc_eth_ltv_params,
            usdc_wbtc_ltv_params,
            usdc_usdt_ltv_params,
            usdc_strk_ltv_params,
            usdt_eth_ltv_params,
            usdt_wbtc_ltv_params,
            usdt_usdc_ltv_params,
            usdt_strk_ltv_params,
            strk_eth_ltv_params,
            strk_wbtc_ltv_params,
            strk_usdc_ltv_params,
            strk_usdt_ltv_params
        ]
            .span();

        let interest_rate_configs = generate_interest_rate_configs(asset_params);
        let liquidation_params = generate_liquidation_params(asset_params, ((9 * SCALE) / 10).try_into().unwrap());
        let debt_caps_params = generate_debt_caps_for_pairs(asset_params, 0);
        let shutdown_params = generate_shutdown_params(asset_params);

        // let singleton = ISingletonDispatcher { contract_address: deploy_contract("Singleton") };
        let singleton = ISingletonDispatcher {
            contract_address: contract_address_const::<
                0x2545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef
            >()
        };
        // let v_token_class_hash = (*declare("VToken").unwrap().contract_class().class_hash).try_into().unwrap();
        let v_token_class_hash = 0x05c64c6cb528bdbffe4187ba3385ff3843b43e8375ad4c3ddd6c28c1d5193576;
        let extension = IDefaultExtensionCLDispatcher {
            contract_address: deploy_with_args(
                "DefaultExtensionCL", array![singleton.contract_address.into(), v_token_class_hash.into()]
            )
        };

        let creator = get_caller_address();
        let pool_id = singleton.calculate_pool_id(extension.contract_address, 1);

        extension
            .create_pool(
                'DefaultExtensionCL',
                asset_params,
                v_token_params,
                max_ltv_params,
                interest_rate_configs,
                oracle_params,
                liquidation_params,
                debt_caps_params,
                shutdown_params,
                FeeParams { fee_recipient: creator },
                creator
            );

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        let mut i = 0;
        loop {
            match asset_params.get(i) {
                Option::Some(boxed_asset_params) => {
                    let mut asset_params = *boxed_asset_params.unbox();
                    let price = IExtensionDispatcher { contract_address: extension.contract_address }
                        .price(pool_id, asset_params.asset);
                    assert!(price.value > 0, "No data");
                },
                Option::None(_) => { break; }
            };
            i += 1;
        };

        let supplier = contract_address_const::<'supplier'>();
        let borrower = contract_address_const::<'borrower'>();
        let liquidator = contract_address_const::<'liquidator'>();
        let supply_amount_eth = 100000000 * SCALE;
        let supply_amount_usdc = 100_000_000__000_000;
        let borrow_amount_eth = 100 * SCALE;
        let borrow_amount_usdc = 600_000__000_000;

        let eth_asset_params: AssetParams = *asset_params[0];
        let eth = ERC20ABIDispatcher { contract_address: eth_asset_params.asset };
        let loaded = load(eth_asset_params.asset, selector!("permitted_minter"), 1);
        let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
        start_cheat_caller_address(eth_asset_params.asset, minter);
        IStarkgateERC20Dispatcher { contract_address: eth_asset_params.asset }
            .permissioned_mint(supplier, supply_amount_eth);
        IStarkgateERC20Dispatcher { contract_address: eth_asset_params.asset }
            .permissioned_mint(borrower, borrow_amount_eth * 2);
        IStarkgateERC20Dispatcher { contract_address: eth_asset_params.asset }
            .permissioned_mint(liquidator, borrow_amount_eth);
        stop_cheat_caller_address(eth_asset_params.asset);

        let usdc_asset_params: AssetParams = *asset_params[2];
        let usdc = ERC20ABIDispatcher { contract_address: usdc_asset_params.asset };
        let loaded = load(usdc_asset_params.asset, selector!("permitted_minter"), 1);
        let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
        start_cheat_caller_address(usdc_asset_params.asset, minter);
        IStarkgateERC20Dispatcher { contract_address: usdc_asset_params.asset }
            .permissioned_mint(supplier, supply_amount_usdc);
        IStarkgateERC20Dispatcher { contract_address: usdc_asset_params.asset }
            .permissioned_mint(borrower, borrow_amount_usdc);
        stop_cheat_caller_address(usdc_asset_params.asset);

        SetupParamsCL {
            singleton,
            extension,
            eth,
            usdc,
            supplier,
            borrower,
            liquidator,
            supply_amount_eth,
            supply_amount_usdc,
            borrow_amount_eth,
            borrow_amount_usdc,
            pool_id
        }
    }

    #[test]
    #[available_gas(3000000)]
    #[fork("Mainnet")]
    fn test_fork_modify_position() {
        let params = setup();
        let SetupParams { singleton,
        eth,
        usdc,
        supplier,
        borrower,
        supply_amount_eth,
        supply_amount_usdc,
        borrow_amount_eth,
        borrow_amount_usdc,
        pool_id,
        .. } =
            params;

        // supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: eth.contract_address,
            debt_asset: usdc.contract_address,
            user: supplier,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: supply_amount_eth.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(eth.contract_address, supplier);
        eth.approve(singleton.contract_address, supply_amount_eth);
        stop_cheat_caller_address(eth.contract_address);

        start_cheat_caller_address(singleton.contract_address, supplier);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: supplier,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: supply_amount_usdc.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(usdc.contract_address, supplier);
        usdc.approve(singleton.contract_address, supply_amount_usdc);
        stop_cheat_caller_address(usdc.contract_address);

        start_cheat_caller_address(singleton.contract_address, supplier);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        // borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: borrow_amount_usdc.into()
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: borrow_amount_eth.into()
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(usdc.contract_address, borrower);
        usdc.approve(singleton.contract_address, borrow_amount_usdc);
        stop_cheat_caller_address(usdc.contract_address);

        start_cheat_caller_address(eth.contract_address, borrower);
        eth.approve(singleton.contract_address, borrow_amount_eth);
        stop_cheat_caller_address(eth.contract_address);

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        // repay partially

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(borrow_amount_usdc / 10).into()
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: -(borrow_amount_eth / 10).into()
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        // withdraw partially

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: supplier,
            collateral: Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: -1.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, supplier);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);
    }

    #[test]
    #[available_gas(2000000)]
    #[fork("Mainnet")]
    fn test_fork_liquidate_position() {
        let params = setup();
        let SetupParams { singleton,
        extension,
        eth,
        usdc,
        supplier,
        borrower,
        liquidator,
        supply_amount_eth,
        supply_amount_usdc,
        borrow_amount_eth,
        borrow_amount_usdc,
        pool_id } =
            params;

        // supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: eth.contract_address,
            debt_asset: usdc.contract_address,
            user: supplier,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: supply_amount_eth.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(eth.contract_address, supplier);
        eth.approve(singleton.contract_address, supply_amount_eth);
        stop_cheat_caller_address(eth.contract_address);

        start_cheat_caller_address(singleton.contract_address, supplier);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: supplier,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: supply_amount_usdc.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(usdc.contract_address, supplier);
        usdc.approve(singleton.contract_address, supply_amount_usdc);
        stop_cheat_caller_address(usdc.contract_address);

        start_cheat_caller_address(singleton.contract_address, supplier);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        // borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: borrow_amount_usdc.into()
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: borrow_amount_eth.into()
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(usdc.contract_address, borrower);
        usdc.approve(singleton.contract_address, borrow_amount_usdc);
        stop_cheat_caller_address(usdc.contract_address);

        start_cheat_caller_address(eth.contract_address, borrower);
        eth.approve(singleton.contract_address, borrow_amount_eth);
        stop_cheat_caller_address(eth.contract_address);

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        // liquidate

        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: deploy_contract("MockPragmaOracle") };
        mock_pragma_oracle.set_num_sources_aggregated('USDC/USD', 2);
        mock_pragma_oracle.set_price('USDC/USD', SCALE_128);
        let price = IExtensionDispatcher { contract_address: extension.contract_address }
            .price(pool_id, eth.contract_address);
        mock_pragma_oracle.set_price('ETH/USD', price.value.try_into().unwrap()); // 3717400000000000000000

        store(
            extension.contract_address,
            selector!("oracle_address"),
            array![mock_pragma_oracle.contract_address.into()].span()
        );

        // reduce oracle price

        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: extension.pragma_oracle() };
        mock_pragma_oracle.set_price('USDC/USD', SCALE_128 / 2);

        let mut liquidation_data: Array<felt252> = ArrayTrait::new();
        LiquidationData { min_collateral_to_receive: 0, debt_to_repay: borrow_amount_eth / 2 }
            .serialize(ref liquidation_data);

        let params = LiquidatePositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: borrower,
            receive_as_shares: false,
            data: liquidation_data.span()
        };

        start_cheat_caller_address(eth.contract_address, liquidator);
        eth.approve(singleton.contract_address, borrow_amount_eth);
        stop_cheat_caller_address(eth.contract_address);

        start_cheat_caller_address(singleton.contract_address, liquidator);
        singleton.liquidate_position(params);
        stop_cheat_caller_address(singleton.contract_address);
    }

    #[test]
    #[available_gas(2000000)]
    #[fork("Mainnet")]
    fn test_fork_shutdown() {
        let params = setup();
        let SetupParams { singleton,
        extension,
        eth,
        usdc,
        supplier,
        borrower,
        supply_amount_eth,
        supply_amount_usdc,
        borrow_amount_eth,
        borrow_amount_usdc,
        pool_id,
        .. } =
            params;

        // supply

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: eth.contract_address,
            debt_asset: usdc.contract_address,
            user: supplier,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: supply_amount_eth.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(eth.contract_address, supplier);
        eth.approve(singleton.contract_address, supply_amount_eth);
        stop_cheat_caller_address(eth.contract_address);

        start_cheat_caller_address(singleton.contract_address, supplier);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: supplier,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: supply_amount_usdc.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(usdc.contract_address, supplier);
        usdc.approve(singleton.contract_address, supply_amount_usdc);
        stop_cheat_caller_address(usdc.contract_address);

        start_cheat_caller_address(singleton.contract_address, supplier);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        // borrow

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: borrower,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: borrow_amount_usdc.into()
            },
            debt: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: borrow_amount_eth.into()
            },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(usdc.contract_address, borrower);
        usdc.approve(singleton.contract_address, borrow_amount_usdc);
        stop_cheat_caller_address(usdc.contract_address);

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        let mock_pragma_oracle = IMockPragmaOracleDispatcher { contract_address: deploy_contract("MockPragmaOracle") };
        mock_pragma_oracle.set_num_sources_aggregated('USDC/USD', 2);
        mock_pragma_oracle.set_price('USDC/USD', SCALE_128);
        let price = IExtensionDispatcher { contract_address: extension.contract_address }
            .price(pool_id, eth.contract_address);
        mock_pragma_oracle.set_price('ETH/USD', price.value.try_into().unwrap()); // 3717400000000000000000

        store(
            extension.contract_address,
            selector!("oracle_address"),
            array![mock_pragma_oracle.contract_address.into()].span()
        );

        // shutdown
        mock_pragma_oracle.set_price('USDC/USD', SCALE_128);
        mock_pragma_oracle.set_num_sources_aggregated('USDC/USD', 1);

        extension.update_shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
        let shutdown_status = extension.shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
        assert!(shutdown_status.shutdown_mode == ShutdownMode::Recovery, "Shutdown status is not recovery");
        assert!(shutdown_status.violating, "Shutdown status is not violating");

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        extension.update_shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
        let shutdown_status = extension.shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
        assert!(shutdown_status.shutdown_mode == ShutdownMode::Subscription, "Shutdown status is not subscription");
        assert!(!shutdown_status.violating, "Shutdown status is not violating");

        let (position, _, _) = singleton.position(pool_id, usdc.contract_address, eth.contract_address, borrower);
        assert!(position.collateral_shares != 0, "Collateral shares are zero");
        assert!(position.nominal_debt != 0, "Nominal debt is zero");

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: borrower,
            collateral: Default::default(),
            debt: Amount { amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into() },
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(eth.contract_address, borrower);
        eth.approve(singleton.contract_address, borrow_amount_eth * 2);
        stop_cheat_caller_address(eth.contract_address);

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

        extension.update_shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
        let shutdown_status = extension.shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
        assert!(shutdown_status.shutdown_mode == ShutdownMode::Redemption, "Shutdown status is not redemption");
        assert!(!shutdown_status.violating, "Shutdown status is not violating");

        let (position, _, _) = singleton.position(pool_id, usdc.contract_address, eth.contract_address, borrower);
        assert!(position.collateral_shares != 0, "Collateral shares are zero");
        assert!(position.nominal_debt == 0, "Nominal debt not zero");

        let params = ModifyPositionParams {
            pool_id,
            collateral_asset: usdc.contract_address,
            debt_asset: eth.contract_address,
            user: borrower,
            collateral: Amount {
                amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into()
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, borrower);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        let (position, _, _) = singleton.position(pool_id, usdc.contract_address, eth.contract_address, borrower);
        assert!(position.collateral_shares == 0, "Collateral shares not zero");
        assert!(position.nominal_debt == 0, "Nominal debt not zero");
    }
    // #[test]
// #[available_gas(2000000)]
// #[fork("Mainnet")]
// fn test_fork_cl_modify_position() {
//     let params = setup_cl();
//     let SetupParamsCL { singleton,
//     eth,
//     usdc,
//     supplier,
//     borrower,
//     supply_amount_eth,
//     supply_amount_usdc,
//     borrow_amount_eth,
//     borrow_amount_usdc,
//     pool_id,
//     .. } =
//         params;

    //     // supply

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: eth.contract_address,
//         debt_asset: usdc.contract_address,
//         user: supplier,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: supply_amount_eth.into()
//         },
//         debt: Default::default(),
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(eth.contract_address, supplier);
//     eth.approve(singleton.contract_address, supply_amount_eth);
//     stop_cheat_caller_address(eth.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, supplier);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: supplier,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: supply_amount_usdc.into()
//         },
//         debt: Default::default(),
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(usdc.contract_address, supplier);
//     usdc.approve(singleton.contract_address, supply_amount_usdc);
//     stop_cheat_caller_address(usdc.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, supplier);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     // borrow

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: borrower,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: borrow_amount_usdc.into()
//         },
//         debt: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: borrow_amount_eth.into()
//         },
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(usdc.contract_address, borrower);
//     usdc.approve(singleton.contract_address, borrow_amount_usdc);
//     stop_cheat_caller_address(usdc.contract_address);

    //     start_cheat_caller_address(eth.contract_address, borrower);
//     eth.approve(singleton.contract_address, borrow_amount_eth);
//     stop_cheat_caller_address(eth.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, borrower);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     // repay partially

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: borrower,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: -(borrow_amount_usdc / 10).into()
//         },
//         debt: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: -(borrow_amount_eth / 10).into()
//         },
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(singleton.contract_address, borrower);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     // withdraw partially

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: supplier,
//         collateral: Amount {
//             amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: -1.into()
//         },
//         debt: Default::default(),
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(singleton.contract_address, supplier);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);
// }
// #[test]
// #[available_gas(2000000)]
// #[fork("Mainnet")]
// fn test_fork_cl_liquidate_position() {
//     let params = setup_cl();
//     let SetupParamsCL { singleton,
//     extension,
//     eth,
//     usdc,
//     supplier,
//     borrower,
//     liquidator,
//     supply_amount_eth,
//     supply_amount_usdc,
//     borrow_amount_eth,
//     borrow_amount_usdc,
//     pool_id,
//     .. } =
//         params;

    //     // supply

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: eth.contract_address,
//         debt_asset: usdc.contract_address,
//         user: supplier,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: supply_amount_eth.into()
//         },
//         debt: Default::default(),
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(eth.contract_address, supplier);
//     eth.approve(singleton.contract_address, supply_amount_eth);
//     stop_cheat_caller_address(eth.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, supplier);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: supplier,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: supply_amount_usdc.into()
//         },
//         debt: Default::default(),
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(usdc.contract_address, supplier);
//     usdc.approve(singleton.contract_address, supply_amount_usdc);
//     stop_cheat_caller_address(usdc.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, supplier);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     // borrow

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: borrower,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: borrow_amount_usdc.into()
//         },
//         debt: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: borrow_amount_eth.into()
//         },
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(usdc.contract_address, borrower);
//     usdc.approve(singleton.contract_address, borrow_amount_usdc);
//     stop_cheat_caller_address(usdc.contract_address);

    //     start_cheat_caller_address(eth.contract_address, borrower);
//     eth.approve(singleton.contract_address, borrow_amount_eth);
//     stop_cheat_caller_address(eth.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, borrower);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     // liquidate

    //     let mock_chainlink_aggregator = IMockChainlinkAggregatorDispatcher {
//         contract_address: deploy_contract("MockChainlinkAggregator")
//     };
//     mock_chainlink_aggregator
//         .set_round(
//             Round {
//                 round_id: 1,
//                 answer: 1_00000000,
//                 block_num: get_block_number(),
//                 started_at: get_block_timestamp(),
//                 updated_at: get_block_timestamp()
//             }
//         );

    //     store(
//         extension.contract_address,
//         map_entry_address(
//             selector!("chainlink_oracle_configs"), array![pool_id, usdc.contract_address.into()].span(),
//         ),
//         array![mock_chainlink_aggregator.contract_address.into()].span()
//     );

    //     let config = extension.chainlink_oracle_config(pool_id, usdc.contract_address);
//     assert!(config.aggregator == mock_chainlink_aggregator.contract_address, "Oracle address is not set");

    //     // reduce oracle price
//     mock_chainlink_aggregator
//         .set_round(
//             Round {
//                 round_id: 1,
//                 answer: 50000000,
//                 block_num: get_block_number(),
//                 started_at: get_block_timestamp(),
//                 updated_at: get_block_timestamp()
//             }
//         );

    //     let mut liquidation_data: Array<felt252> = ArrayTrait::new();
//     LiquidationData { min_collateral_to_receive: 0, debt_to_repay: borrow_amount_eth / 2 }
//         .serialize(ref liquidation_data);

    //     let params = LiquidatePositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: borrower,
//         receive_as_shares: false,
//         data: liquidation_data.span()
//     };

    //     start_cheat_caller_address(eth.contract_address, liquidator);
//     eth.approve(singleton.contract_address, borrow_amount_eth);
//     stop_cheat_caller_address(eth.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, liquidator);
//     singleton.liquidate_position(params);
//     stop_cheat_caller_address(singleton.contract_address);
// }

    // #[test]
// #[available_gas(2000000)]
// #[fork("Mainnet")]
// fn test_fork_cl_shutdown() {
//     let params = setup_cl();
//     let SetupParamsCL { singleton,
//     extension,
//     eth,
//     usdc,
//     supplier,
//     borrower,
//     supply_amount_eth,
//     supply_amount_usdc,
//     borrow_amount_eth,
//     borrow_amount_usdc,
//     pool_id,
//     .. } =
//         params;

    //     // supply

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: eth.contract_address,
//         debt_asset: usdc.contract_address,
//         user: supplier,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: supply_amount_eth.into()
//         },
//         debt: Default::default(),
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(eth.contract_address, supplier);
//     eth.approve(singleton.contract_address, supply_amount_eth);
//     stop_cheat_caller_address(eth.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, supplier);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: supplier,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: supply_amount_usdc.into()
//         },
//         debt: Default::default(),
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(usdc.contract_address, supplier);
//     usdc.approve(singleton.contract_address, supply_amount_usdc);
//     stop_cheat_caller_address(usdc.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, supplier);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     // borrow

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: borrower,
//         collateral: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: borrow_amount_usdc.into()
//         },
//         debt: Amount {
//             amount_type: AmountType::Delta,
//             denomination: AmountDenomination::Assets,
//             value: borrow_amount_eth.into()
//         },
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(usdc.contract_address, borrower);
//     usdc.approve(singleton.contract_address, borrow_amount_usdc);
//     stop_cheat_caller_address(usdc.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, borrower);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     let mock_chainlink_aggregator = IMockChainlinkAggregatorDispatcher {
//         contract_address: deploy_contract("MockChainlinkAggregator")
//     };
//     mock_chainlink_aggregator
//         .set_round(
//             Round {
//                 round_id: 1,
//                 answer: 1_00000000,
//                 block_num: get_block_number(),
//                 started_at: get_block_timestamp(),
//                 updated_at: get_block_timestamp()
//             }
//         );

    //     store(
//         extension.contract_address,
//         map_entry_address(
//             selector!("chainlink_oracle_configs"), array![pool_id, usdc.contract_address.into()].span(),
//         ),
//         array![mock_chainlink_aggregator.contract_address.into()].span()
//     );

    //     let config = extension.chainlink_oracle_config(pool_id, usdc.contract_address);
//     assert!(config.aggregator == mock_chainlink_aggregator.contract_address, "Oracle address is not set");

    //     // reduce oracle price
//     mock_chainlink_aggregator
//         .set_round(
//             Round {
//                 round_id: 1,
//                 answer: 1,
//                 block_num: get_block_number(),
//                 started_at: get_block_timestamp(),
//                 updated_at: get_block_timestamp()
//             }
//         );

    //     extension.update_shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
//     let shutdown_status = extension.shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
//     assert!(shutdown_status.shutdown_mode == ShutdownMode::Recovery, "Shutdown status is not recovery");
//     assert!(shutdown_status.violating, "Shutdown status is not violating");

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     extension.update_shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
//     let shutdown_status = extension.shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
//     assert!(shutdown_status.shutdown_mode == ShutdownMode::Subscription, "Shutdown status is not subscription");
//     assert!(!shutdown_status.violating, "Shutdown status is not violating");

    //     let (position, _, _) = singleton.position(pool_id, usdc.contract_address, eth.contract_address, borrower);
//     assert!(position.collateral_shares != 0, "Collateral shares are zero");
//     assert!(position.nominal_debt != 0, "Nominal debt is zero");

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: borrower,
//         collateral: Default::default(),
//         debt: Amount { amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into()
//         }, data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(eth.contract_address, borrower);
//     eth.approve(singleton.contract_address, borrow_amount_eth * 2);
//     stop_cheat_caller_address(eth.contract_address);

    //     start_cheat_caller_address(singleton.contract_address, borrower);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     start_cheat_block_timestamp_global(get_block_timestamp() + DAY_IN_SECONDS * 30);

    //     extension.update_shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
//     let shutdown_status = extension.shutdown_status(pool_id, usdc.contract_address, eth.contract_address);
//     assert!(shutdown_status.shutdown_mode == ShutdownMode::Redemption, "Shutdown status is not redemption");
//     assert!(!shutdown_status.violating, "Shutdown status is not violating");

    //     let (position, _, _) = singleton.position(pool_id, usdc.contract_address, eth.contract_address, borrower);
//     assert!(position.collateral_shares != 0, "Collateral shares are zero");
//     assert!(position.nominal_debt == 0, "Nominal debt not zero");

    //     let params = ModifyPositionParams {
//         pool_id,
//         collateral_asset: usdc.contract_address,
//         debt_asset: eth.contract_address,
//         user: borrower,
//         collateral: Amount {
//             amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into()
//         },
//         debt: Default::default(),
//         data: ArrayTrait::new().span()
//     };

    //     start_cheat_caller_address(singleton.contract_address, borrower);
//     singleton.modify_position(params);
//     stop_cheat_caller_address(singleton.contract_address);

    //     let (position, _, _) = singleton.position(pool_id, usdc.contract_address, eth.contract_address, borrower);
//     assert!(position.collateral_shares == 0, "Collateral shares not zero");
//     assert!(position.nominal_debt == 0, "Nominal debt not zero");
// }
}
