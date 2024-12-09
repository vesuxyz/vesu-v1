// #[cfg(test)]
// mod TestIntegration {
//     use snforge_std::{
//         start_prank, stop_prank, CheatTarget, store, load, map_entry_address, declare, start_warp, prank, CheatSpan,
//         replace_bytecode, get_class_hash
//     };
//     use starknet::{ContractAddress, contract_address_const, get_contract_address, get_block_timestamp};
//     use vesu::{
//         singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
//         extension::default_extension_po::{IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait},
//         data_model::{Amount, AmountType, AmountDenomination, ModifyPositionParams}, units::SCALE,
//         test::test_forking::{IStarkgateERC20Dispatcher, IStarkgateERC20DispatcherTrait},
//         vendor::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait}
//     };

//     fn setup(pool_id: felt252) -> (ISingletonDispatcher, IDefaultExtensionDispatcher) {
//         let singleton = ISingletonDispatcher {
//             contract_address: contract_address_const::<
//                 0x2545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef
//             >()
//         };

//         // replace_bytecode(singleton.contract_address, declare("Singleton").class_hash);

//         let extension = IDefaultExtensionDispatcher { contract_address: singleton.extension(pool_id) };

//         // replace_bytecode(extension.contract_address, declare("DefaultExtensionPO").class_hash);

//         (singleton, extension)
//     }

//     fn setup_starkgate_erc20(token: ContractAddress, recipient: ContractAddress, amount: u256) -> ERC20ABIDispatcher {
//         let erc20 = ERC20ABIDispatcher { contract_address: token };
//         let loaded = load(token, selector!("permitted_minter"), 1);
//         let minter: ContractAddress = (*loaded[0]).try_into().unwrap();
//         if (amount != 0) {
//             start_prank(CheatTarget::One(token), minter);
//             IStarkgateERC20Dispatcher { contract_address: token }.permissioned_mint(recipient, amount);
//             stop_prank(CheatTarget::One(token));
//         }
//         erc20
//     }

//     fn supply(
//         singleton: ISingletonDispatcher,
//         pool_id: felt252,
//         collateral_asset: ERC20ABIDispatcher,
//         debt_asset: ERC20ABIDispatcher,
//         user: ContractAddress,
//         amount: u256
//     ) {
//         let params = ModifyPositionParams {
//             pool_id,
//             collateral_asset: collateral_asset.contract_address,
//             debt_asset: debt_asset.contract_address,
//             user,
//             collateral: Amount {
//                 amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: amount.into()
//             },
//             debt: Default::default(),
//             data: ArrayTrait::new().span()
//         };

//         start_prank(CheatTarget::One(collateral_asset.contract_address), user);
//         collateral_asset.approve(singleton.contract_address, amount);
//         stop_prank(CheatTarget::One(collateral_asset.contract_address));

//         start_prank(CheatTarget::One(singleton.contract_address), user);
//         singleton.modify_position(params);
//         stop_prank(CheatTarget::One(singleton.contract_address));
//     }

//     fn borrow(
//         singleton: ISingletonDispatcher,
//         pool_id: felt252,
//         collateral_asset: ERC20ABIDispatcher,
//         debt_asset: ERC20ABIDispatcher,
//         user: ContractAddress,
//         amount: u256
//     ) {
//         let params = ModifyPositionParams {
//             pool_id,
//             collateral_asset: collateral_asset.contract_address,
//             debt_asset: debt_asset.contract_address,
//             user,
//             collateral: Default::default(),
//             debt: Amount {
//                 amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: amount.into()
//             },
//             data: ArrayTrait::new().span()
//         };

//         start_prank(CheatTarget::One(singleton.contract_address), user);
//         singleton.modify_position(params);
//         stop_prank(CheatTarget::One(singleton.contract_address));
//     }

//     fn repay(
//         singleton: ISingletonDispatcher,
//         pool_id: felt252,
//         collateral_asset: ERC20ABIDispatcher,
//         debt_asset: ERC20ABIDispatcher,
//         user: ContractAddress
//     ) {
//         let params = ModifyPositionParams {
//             pool_id,
//             collateral_asset: collateral_asset.contract_address,
//             debt_asset: debt_asset.contract_address,
//             user,
//             collateral: Default::default(),
//             debt: Amount { amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into() },
//             data: ArrayTrait::new().span()
//         };

//         let (_, _, debt) = singleton
//             .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, user);

//         start_prank(CheatTarget::One(debt_asset.contract_address), user);
//         debt_asset.approve(singleton.contract_address, debt);
//         stop_prank(CheatTarget::One(debt_asset.contract_address));

//         start_prank(CheatTarget::One(singleton.contract_address), user);
//         singleton.modify_position(params);
//         stop_prank(CheatTarget::One(singleton.contract_address));
//     }

//     fn withdraw(
//         singleton: ISingletonDispatcher,
//         pool_id: felt252,
//         collateral_asset: ERC20ABIDispatcher,
//         debt_asset: ERC20ABIDispatcher,
//         user: ContractAddress
//     ) {
//         let params = ModifyPositionParams {
//             pool_id,
//             collateral_asset: collateral_asset.contract_address,
//             debt_asset: debt_asset.contract_address,
//             user,
//             collateral: Amount {
//                 amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into()
//             },
//             debt: Default::default(),
//             data: ArrayTrait::new().span()
//         };

//         start_prank(CheatTarget::One(singleton.contract_address), user);
//         singleton.modify_position(params);
//         stop_prank(CheatTarget::One(singleton.contract_address));
//     }

//     // 957600
//     #[test]
//     #[fork("Mainnet")]
//     fn test_integration_genesis_pool() {
//         let pool_id = 2198503327643286920898110335698706244522220458610657370981979460625005526824;
//         let eth = setup_starkgate_erc20(
//             contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
//             get_contract_address(),
//             1000 * SCALE
//         );
//         let wbtc = setup_starkgate_erc20(
//             contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>(),
//             get_contract_address(),
//             10 * 1_00_000_000
//         );
//         let usdc = setup_starkgate_erc20(
//             contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
//             get_contract_address(),
//             10000000 * 1_000_000
//         );
//         let usdt = setup_starkgate_erc20(
//             contract_address_const::<0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8>(),
//             get_contract_address(),
//             10000000 * 1_000_000
//         );
//         let wsteth = setup_starkgate_erc20(
//             contract_address_const::<0x042b8f0484674ca266ac5d08e4ac6a3fe65bd3129795def2dca5c34ecc5f96d2>(),
//             get_contract_address(),
//             1000 * SCALE
//         );
//         let strk = setup_starkgate_erc20(
//             contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
//             get_contract_address(),
//             10000000 * SCALE
//         );

//         let (singleton, extension) = setup(pool_id);

//         supply(singleton, pool_id, eth, wbtc, get_contract_address(), 100 * SCALE);
//         supply(singleton, pool_id, eth, usdc, get_contract_address(), 1 * SCALE);
//         supply(singleton, pool_id, eth, usdt, get_contract_address(), 1 * SCALE);
//         supply(singleton, pool_id, eth, wsteth, get_contract_address(), 2 * SCALE);
//         supply(singleton, pool_id, eth, strk, get_contract_address(), 1 * SCALE);

//         supply(singleton, pool_id, wbtc, eth, get_contract_address(), 1 * 1_00_000_000);
//         supply(singleton, pool_id, wbtc, usdc, get_contract_address(), 1 * 1_00_000_000);
//         supply(singleton, pool_id, wbtc, usdt, get_contract_address(), 1 * 1_00_000_000);
//         supply(singleton, pool_id, wbtc, wsteth, get_contract_address(), 1 * 1_00_000_000);
//         supply(singleton, pool_id, wbtc, strk, get_contract_address(), 1 * 1_00_000_000);

//         supply(singleton, pool_id, usdc, eth, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdc, wbtc, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdc, usdt, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdc, wsteth, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdc, strk, get_contract_address(), 200000 * 1_000_000);

//         supply(singleton, pool_id, usdt, eth, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdt, wbtc, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdt, usdc, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdt, wsteth, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdt, strk, get_contract_address(), 200000 * 1_000_000);

//         supply(singleton, pool_id, wsteth, eth, get_contract_address(), 2 * SCALE);
//         supply(singleton, pool_id, wsteth, wbtc, get_contract_address(), 100 * SCALE);
//         supply(singleton, pool_id, wsteth, usdc, get_contract_address(), 1 * SCALE);
//         supply(singleton, pool_id, wsteth, usdt, get_contract_address(), 1 * SCALE);
//         supply(singleton, pool_id, wsteth, strk, get_contract_address(), 1 * SCALE);

//         supply(singleton, pool_id, strk, eth, get_contract_address(), 10000 * SCALE);
//         supply(singleton, pool_id, strk, wbtc, get_contract_address(), 1000000 * SCALE);
//         supply(singleton, pool_id, strk, usdc, get_contract_address(), 1000 * SCALE);
//         supply(singleton, pool_id, strk, usdt, get_contract_address(), 1000 * SCALE);
//         supply(singleton, pool_id, strk, wsteth, get_contract_address(), 10000 * SCALE);

//         borrow(singleton, pool_id, eth, wbtc, get_contract_address(), 1 * 1_00_000_000);
//         borrow(singleton, pool_id, eth, usdc, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, eth, usdt, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, eth, wsteth, get_contract_address(), 1 * SCALE);
//         borrow(singleton, pool_id, eth, strk, get_contract_address(), 500 * SCALE);

//         borrow(singleton, pool_id, wbtc, eth, get_contract_address(), 10 * SCALE);
//         borrow(singleton, pool_id, wbtc, usdc, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, wbtc, usdt, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, wbtc, wsteth, get_contract_address(), 10 * SCALE);
//         borrow(singleton, pool_id, wbtc, strk, get_contract_address(), 500 * SCALE);

//         borrow(singleton, pool_id, usdc, eth, get_contract_address(), 10 * SCALE);
//         borrow(singleton, pool_id, usdc, wbtc, get_contract_address(), 1 * 1_00_000_000);
//         borrow(singleton, pool_id, usdc, usdt, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, usdc, wsteth, get_contract_address(), 10 * SCALE);
//         borrow(singleton, pool_id, usdc, strk, get_contract_address(), 500 * SCALE);

//         borrow(singleton, pool_id, usdt, eth, get_contract_address(), 10 * SCALE);
//         borrow(singleton, pool_id, usdt, wbtc, get_contract_address(), 1 * 1_00_000_000);
//         borrow(singleton, pool_id, usdt, usdc, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, usdt, wsteth, get_contract_address(), 10 * SCALE);
//         borrow(singleton, pool_id, usdt, strk, get_contract_address(), 500 * SCALE);

//         borrow(singleton, pool_id, wsteth, eth, get_contract_address(), 1 * SCALE);
//         borrow(singleton, pool_id, wsteth, wbtc, get_contract_address(), 1 * 1_00_000_000);
//         borrow(singleton, pool_id, wsteth, usdc, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, wsteth, usdt, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, wsteth, strk, get_contract_address(), 500 * SCALE);

//         borrow(singleton, pool_id, strk, eth, get_contract_address(), 1 * SCALE);
//         borrow(singleton, pool_id, strk, wbtc, get_contract_address(), 1 * 1_00_000_000);
//         borrow(singleton, pool_id, strk, usdc, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, strk, usdt, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, strk, wsteth, get_contract_address(), 1 * SCALE);

//         start_prank(CheatTarget::One(extension.contract_address), extension.pool_owner(pool_id));
//         extension.set_oracle_parameter(pool_id, eth.contract_address, 'timeout', 0);
//         extension.set_oracle_parameter(pool_id, wbtc.contract_address, 'timeout', 0);
//         extension.set_oracle_parameter(pool_id, usdc.contract_address, 'timeout', 0);
//         extension.set_oracle_parameter(pool_id, usdt.contract_address, 'timeout', 0);
//         extension.set_oracle_parameter(pool_id, wsteth.contract_address, 'timeout', 0);
//         extension.set_oracle_parameter(pool_id, strk.contract_address, 'timeout', 0);
//         stop_prank(CheatTarget::One(extension.contract_address));

//         // warp
//         start_warp(CheatTarget::All, get_block_timestamp() + 94608000);

//         repay(singleton, pool_id, eth, wbtc, get_contract_address());
//         repay(singleton, pool_id, eth, usdc, get_contract_address());
//         repay(singleton, pool_id, eth, usdt, get_contract_address());
//         repay(singleton, pool_id, eth, wsteth, get_contract_address());
//         repay(singleton, pool_id, eth, strk, get_contract_address());

//         repay(singleton, pool_id, wbtc, eth, get_contract_address());
//         repay(singleton, pool_id, wbtc, usdc, get_contract_address());
//         repay(singleton, pool_id, wbtc, usdt, get_contract_address());
//         repay(singleton, pool_id, wbtc, wsteth, get_contract_address());
//         repay(singleton, pool_id, wbtc, strk, get_contract_address());

//         repay(singleton, pool_id, usdc, eth, get_contract_address());
//         repay(singleton, pool_id, usdc, wbtc, get_contract_address());
//         repay(singleton, pool_id, usdc, usdt, get_contract_address());
//         repay(singleton, pool_id, usdc, wsteth, get_contract_address());
//         repay(singleton, pool_id, usdc, strk, get_contract_address());

//         repay(singleton, pool_id, usdt, eth, get_contract_address());
//         repay(singleton, pool_id, usdt, wbtc, get_contract_address());
//         repay(singleton, pool_id, usdt, usdc, get_contract_address());
//         repay(singleton, pool_id, usdt, wsteth, get_contract_address());
//         repay(singleton, pool_id, usdt, strk, get_contract_address());

//         repay(singleton, pool_id, wsteth, eth, get_contract_address());
//         repay(singleton, pool_id, wsteth, wbtc, get_contract_address());
//         repay(singleton, pool_id, wsteth, usdc, get_contract_address());
//         repay(singleton, pool_id, wsteth, usdt, get_contract_address());
//         repay(singleton, pool_id, wsteth, strk, get_contract_address());

//         repay(singleton, pool_id, strk, eth, get_contract_address());
//         repay(singleton, pool_id, strk, wbtc, get_contract_address());
//         repay(singleton, pool_id, strk, usdc, get_contract_address());
//         repay(singleton, pool_id, strk, usdt, get_contract_address());
//         repay(singleton, pool_id, strk, wsteth, get_contract_address());

//         withdraw(singleton, pool_id, eth, wbtc, get_contract_address());
//         withdraw(singleton, pool_id, eth, usdc, get_contract_address());
//         withdraw(singleton, pool_id, eth, usdt, get_contract_address());
//         withdraw(singleton, pool_id, eth, wsteth, get_contract_address());
//         withdraw(singleton, pool_id, eth, strk, get_contract_address());

//         withdraw(singleton, pool_id, wbtc, eth, get_contract_address());
//         withdraw(singleton, pool_id, wbtc, usdc, get_contract_address());
//         withdraw(singleton, pool_id, wbtc, usdt, get_contract_address());
//         withdraw(singleton, pool_id, wbtc, wsteth, get_contract_address());
//         withdraw(singleton, pool_id, wbtc, strk, get_contract_address());

//         withdraw(singleton, pool_id, usdc, eth, get_contract_address());
//         withdraw(singleton, pool_id, usdc, wbtc, get_contract_address());
//         withdraw(singleton, pool_id, usdc, usdt, get_contract_address());
//         withdraw(singleton, pool_id, usdc, wsteth, get_contract_address());
//         withdraw(singleton, pool_id, usdc, strk, get_contract_address());

//         withdraw(singleton, pool_id, usdt, eth, get_contract_address());
//         withdraw(singleton, pool_id, usdt, wbtc, get_contract_address());
//         withdraw(singleton, pool_id, usdt, usdc, get_contract_address());
//         withdraw(singleton, pool_id, usdt, wsteth, get_contract_address());
//         withdraw(singleton, pool_id, usdt, strk, get_contract_address());

//         withdraw(singleton, pool_id, wsteth, eth, get_contract_address());
//         withdraw(singleton, pool_id, wsteth, wbtc, get_contract_address());
//         withdraw(singleton, pool_id, wsteth, usdc, get_contract_address());
//         withdraw(singleton, pool_id, wsteth, usdt, get_contract_address());
//         withdraw(singleton, pool_id, wsteth, strk, get_contract_address());

//         withdraw(singleton, pool_id, strk, eth, get_contract_address());
//         withdraw(singleton, pool_id, strk, wbtc, get_contract_address());
//         withdraw(singleton, pool_id, strk, usdc, get_contract_address());
//         withdraw(singleton, pool_id, strk, usdt, get_contract_address());
//         withdraw(singleton, pool_id, strk, wsteth, get_contract_address());
//     }

//     // 968900
//     #[test]
//     #[fork("Mainnet")]
//     fn test_integration_re7_usdc_pool() {
//         let pool_id = 3592370751539490711610556844458488648008775713878064059760995781404350938653;
//         let eth = setup_starkgate_erc20(
//             contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
//             get_contract_address(),
//             1000 * SCALE
//         );
//         let wbtc = setup_starkgate_erc20(
//             contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>(),
//             get_contract_address(),
//             10 * 1_00_000_000
//         );
//         let usdc = setup_starkgate_erc20(
//             contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
//             get_contract_address(),
//             10000000 * 1_000_000
//         );
//         let wsteth = setup_starkgate_erc20(
//             contract_address_const::<0x042b8f0484674ca266ac5d08e4ac6a3fe65bd3129795def2dca5c34ecc5f96d2>(),
//             get_contract_address(),
//             1000 * SCALE
//         );
//         let strk = setup_starkgate_erc20(
//             contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
//             get_contract_address(),
//             10000000 * SCALE
//         );

//         let (singleton, _) = setup(pool_id);

//         supply(singleton, pool_id, eth, wbtc, get_contract_address(), 100 * SCALE);
//         supply(singleton, pool_id, eth, usdc, get_contract_address(), 1 * SCALE);
//         supply(singleton, pool_id, eth, wsteth, get_contract_address(), 2 * SCALE);
//         supply(singleton, pool_id, eth, strk, get_contract_address(), 1 * SCALE);

//         supply(singleton, pool_id, wbtc, eth, get_contract_address(), 1 * 1_00_000_000);
//         supply(singleton, pool_id, wbtc, usdc, get_contract_address(), 1 * 1_00_000_000);
//         supply(singleton, pool_id, wbtc, wsteth, get_contract_address(), 1 * 1_00_000_000);
//         supply(singleton, pool_id, wbtc, strk, get_contract_address(), 1 * 1_00_000_000);

//         supply(singleton, pool_id, usdc, eth, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdc, wbtc, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdc, wsteth, get_contract_address(), 200000 * 1_000_000);
//         supply(singleton, pool_id, usdc, strk, get_contract_address(), 200000 * 1_000_000);

//         supply(singleton, pool_id, wsteth, eth, get_contract_address(), 2 * SCALE);
//         supply(singleton, pool_id, wsteth, wbtc, get_contract_address(), 100 * SCALE);
//         supply(singleton, pool_id, wsteth, usdc, get_contract_address(), 1 * SCALE);
//         supply(singleton, pool_id, wsteth, strk, get_contract_address(), 1 * SCALE);

//         supply(singleton, pool_id, strk, eth, get_contract_address(), 10000 * SCALE);
//         supply(singleton, pool_id, strk, wbtc, get_contract_address(), 1000000 * SCALE);
//         supply(singleton, pool_id, strk, usdc, get_contract_address(), 1000 * SCALE);
//         supply(singleton, pool_id, strk, wsteth, get_contract_address(), 10000 * SCALE);

//         borrow(singleton, pool_id, eth, usdc, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, wsteth, usdc, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, wbtc, usdc, get_contract_address(), 200 * 1_000_000);
//         borrow(singleton, pool_id, strk, usdc, get_contract_address(), 200 * 1_000_000);

//         // warp
//         start_warp(CheatTarget::All, get_block_timestamp() + 94608000);

//         repay(singleton, pool_id, eth, usdc, get_contract_address());
//         repay(singleton, pool_id, wsteth, usdc, get_contract_address());
//         repay(singleton, pool_id, wbtc, usdc, get_contract_address());
//         repay(singleton, pool_id, strk, usdc, get_contract_address());

//         withdraw(singleton, pool_id, eth, usdc, get_contract_address());
//         withdraw(singleton, pool_id, wsteth, usdc, get_contract_address());
//         withdraw(singleton, pool_id, wbtc, usdc, get_contract_address());
//         withdraw(singleton, pool_id, strk, usdc, get_contract_address());
//     }

//     // 968900
//     #[test]
//     #[fork("Mainnet")]
//     fn test_integration_re7_sstrk_pool() {
//         let pool_id = 1301140954640322725373945719229815062445705809076381949099585786202465661889;
//         let strk = setup_starkgate_erc20(
//             contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
//             get_contract_address(),
//             10000000 * SCALE
//         );
//         let sstrk = setup_starkgate_erc20(
//             contract_address_const::<0x0356f304b154d29d2a8fe22f1cb9107a9b564a733cf6b4cc47fd121ac1af90c9>(),
//             get_contract_address(),
//             10000000 * SCALE
//         );

//         let (singleton, extension) = setup(pool_id);

//         start_prank(CheatTarget::One(extension.contract_address), extension.pool_owner(pool_id));
//         extension.set_debt_cap(pool_id, sstrk.contract_address, strk.contract_address, 1000000 * SCALE);
//         stop_prank(CheatTarget::One(extension.contract_address));
//         supply(singleton, pool_id, strk, sstrk, get_contract_address(), 100000 * SCALE);
//         supply(singleton, pool_id, sstrk, strk, get_contract_address(), 100000 * SCALE);

//         borrow(singleton, pool_id, sstrk, strk, get_contract_address(), 10000 * SCALE);

//         // warp
//         start_warp(CheatTarget::All, get_block_timestamp() + 94608000);

//         repay(singleton, pool_id, strk, sstrk, get_contract_address());
//         repay(singleton, pool_id, sstrk, strk, get_contract_address());

//         withdraw(singleton, pool_id, strk, sstrk, get_contract_address());
//         withdraw(singleton, pool_id, sstrk, strk, get_contract_address());
//     }

//     // 968900
//     #[test]
//     #[fork("Mainnet")]
//     fn test_integration_re7_xstrk_pool() {
//         let pool_id = 2345856225134458665876812536882617294246962319062565703131100435311373119841;
//         let strk = setup_starkgate_erc20(
//             contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
//             get_contract_address(),
//             10000000 * SCALE
//         );
//         let xstrk = setup_starkgate_erc20(
//             contract_address_const::<0x028d709c875c0ceac3dce7065bec5328186dc89fe254527084d1689910954b0a>(),
//             get_contract_address(),
//             0
//         );

//         store(
//             xstrk.contract_address,
//             map_entry_address(selector!("ERC20_balances"), array![get_contract_address().into()].span(),),
//             array![(10000000 * SCALE).try_into().unwrap()].span()
//         );

//         let (singleton, extension) = setup(pool_id);

//         start_prank(CheatTarget::One(extension.contract_address), extension.pool_owner(pool_id));
//         extension.set_debt_cap(pool_id, xstrk.contract_address, strk.contract_address, 1000000 * SCALE);
//         stop_prank(CheatTarget::One(extension.contract_address));

//         supply(singleton, pool_id, strk, xstrk, get_contract_address(), 100000 * SCALE);
//         supply(singleton, pool_id, xstrk, strk, get_contract_address(), 100000 * SCALE);

//         borrow(singleton, pool_id, xstrk, strk, get_contract_address(), 10000 * SCALE);

//         // warp
//         start_warp(CheatTarget::All, get_block_timestamp() + 94608000);

//         repay(singleton, pool_id, strk, xstrk, get_contract_address());
//         repay(singleton, pool_id, xstrk, strk, get_contract_address());

//         withdraw(singleton, pool_id, strk, xstrk, get_contract_address());
//         withdraw(singleton, pool_id, xstrk, strk, get_contract_address());
//     }
// }
