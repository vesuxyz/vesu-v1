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
mod TestUser {
    use alexandria_math::i257::{i257, i257_new};
    use snforge_std::{
        start_prank, stop_prank, CheatTarget, store, load, map_entry_address, declare, start_warp, replace_bytecode
    };
    use starknet::{
        contract_address_const, get_caller_address, get_contract_address, ContractAddress, get_block_timestamp
    };
    use super::{IStarkgateERC20Dispatcher, IStarkgateERC20DispatcherTrait, to_percent};
    use vesu::{
        test::{
            setup::{setup_pool, deploy_contract, deploy_with_args},
            mock_oracle::{IMockPragmaOracleDispatcher, IMockPragmaOracleDispatcherTrait}
        },
        vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait},
        extension::{
            interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
            default_extension::{
                IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait, PragmaOracleParams, InterestRateConfig,
                LiquidationParams, ShutdownParams, FeeParams, VTokenParams, ShutdownMode
            },
            components::position_hooks::LiquidationData
        },
        units::{SCALE, SCALE_128, PERCENT, DAY_IN_SECONDS},
        data_model::{
            AssetParams, LTVParams, ModifyPositionParams, Amount, AmountType, AmountDenomination, UnsignedAmount,
            AssetPrice, TransferPositionParams
        },
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait, LiquidatePositionParams},
    };

    #[test]
    #[available_gas(2000000)]
    #[fork("Mainnet")]
    fn test_user() {
        let singleton = ISingletonDispatcher {
            contract_address: contract_address_const::<
                0x297ef4c12810695c5d91e28b8ee5c5af430076fa8c40a45d31b48da54de372e
            >()
        };

        replace_bytecode(singleton.contract_address, declare("Singleton").class_hash);

        let extension = IDefaultExtensionDispatcher {
            contract_address: contract_address_const::<
                0x1008cf6e9f48c6b23121b340e2e84c5a6df0ab3a46d4886df71bdd6d16fcf69
            >()
        };

        replace_bytecode(extension.contract_address, declare("DefaultExtension").class_hash);

        let pool_id = 3601893553453722691657585476026095435475878278287859441667450345178654480585;
        let collateral_asset = IERC20Dispatcher {
            contract_address: contract_address_const::<
                0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8
            >()
        };
        let debt_asset = IERC20Dispatcher {
            contract_address: contract_address_const::<
                0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac
            >()
        };
        let user = contract_address_const::<0x075324D453cF0B57D1242602D349040A6D5E0D8a6b118953afA7C1bf17ba53F8>();

        let (position, _, _) = singleton
            .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, user);

        // println!("position.collateral_shares: {}", position.collateral_shares);
        // println!("position.nominal_debt: {}", position.nominal_debt);

        // let context = singleton.context(pool_id, collateral_asset.contract_address, debt_asset.contract_address, user);
        // println!(
        //     "context.collateral_asset_config.total_collateral_shares: {}",
        //     context.collateral_asset_config.total_collateral_shares
        // );
        // println!("context.collateral_asset_config.reserve: {}", context.collateral_asset_config.reserve);

        start_prank(CheatTarget::One(singleton.contract_address), user);
        singleton
            .transfer_position(
                TransferPositionParams {
                    pool_id,
                    from_collateral_asset: collateral_asset.contract_address,
                    from_debt_asset: debt_asset.contract_address,
                    to_collateral_asset: collateral_asset.contract_address,
                    to_debt_asset: Zeroable::zero(),
                    from_user: user,
                    to_user: extension.contract_address,
                    collateral: UnsignedAmount {
                        amount_type: AmountType::Delta,
                        denomination: AmountDenomination::Native,
                        value: position.collateral_shares,
                    },
                    debt: Default::default(),
                    from_data: ArrayTrait::new().span(),
                    to_data: ArrayTrait::new().span(),
                }
            );
        stop_prank(CheatTarget::One(singleton.contract_address));
    // let wbtc = contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>();

    // let collateral_shares = singleton.calculate_collateral_shares(
    //     pool_id, wbtc, i257_new(270738, false)
    // );

    // println!("collateral:        {}", 270738);
    // println!("collateral_shares: {}", collateral_shares);
    }
}
