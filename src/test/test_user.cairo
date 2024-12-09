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
        start_prank, stop_prank, CheatTarget, store, load, map_entry_address, declare, start_warp, replace_bytecode,
        get_class_hash
    };
    use starknet::{
        ClassHash, contract_address_const, get_caller_address, get_contract_address, ContractAddress,
        get_block_timestamp
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
            default_extension_po::{
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

    // block number: 952420
    #[test]
    #[available_gas(2000000)]
    #[fork("Mainnet")]
    fn test_user() {
        let singleton = ISingletonDispatcher {
            contract_address: contract_address_const::<
                0x2545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef
            >()
        };

        replace_bytecode(
            singleton.contract_address, // declare("Singleton").class_hash
             get_class_hash(singleton.contract_address)
        );

        let extension = IDefaultExtensionDispatcher {
            contract_address: contract_address_const::<
                0x2ded44e2c575671dedb6227ba8bfed340252f3cb0476982074567c0670442f7
            >()
        };

        replace_bytecode(
            extension.contract_address,
            declare("DefaultExtensionPO").class_hash // get_class_hash(extension.contract_address)
        );

        let pool_id = 3488439889760078773862061392337242708358978534574204613763925972476552399332;
        let collateral_asset = IERC20Dispatcher {
            contract_address: contract_address_const::<
                0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 // eth
            >()
        };
        let debt_asset = IERC20Dispatcher {
            contract_address: contract_address_const::<
                0x53c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8 // usdc
            >()
        };
        // let user = contract_address_const::<0x11b6e878cc575025b488b2e7af5f58f9df99b9f9aa03f22f932ae0b69a955f1>();
        let user = contract_address_const::<0x03d92A8137e51eeE44B8Fb450d90f2CdA085B2568562c1B8695cBF11c06f9c8d>();

        // let (position, _, _) = singleton
        //     .position(pool_id, collateral_asset.contract_address, debt_asset.contract_address, user);

        println!("balance: {}", collateral_asset.balance_of(user));

        start_prank(CheatTarget::One(collateral_asset.contract_address), user);
        collateral_asset.approve(singleton.contract_address, 100 * SCALE);
        stop_prank(CheatTarget::One(collateral_asset.contract_address));

        start_prank(CheatTarget::One(singleton.contract_address), user);
        singleton
            .modify_position(
                ModifyPositionParams {
                    pool_id,
                    collateral_asset: collateral_asset.contract_address,
                    debt_asset: debt_asset.contract_address,
                    user,
                    collateral: Amount { // 0.04 ETH
                        amount_type: AmountType::Delta,
                        denomination: AmountDenomination::Assets,
                        value: 40000000000000000.into(),
                    },
                    debt: Default::default(),
                    data: ArrayTrait::new().span(),
                }
            );
        singleton
            .modify_position(
                ModifyPositionParams {
                    pool_id,
                    collateral_asset: collateral_asset.contract_address,
                    debt_asset: debt_asset.contract_address,
                    user,
                    collateral: Default::default(),
                    debt: Amount { // 10 USDC
                        amount_type: AmountType::Delta,
                        denomination: AmountDenomination::Assets,
                        value: 10000000.into(),
                    },
                    data: ArrayTrait::new().span(),
                }
            );
        stop_prank(CheatTarget::One(singleton.contract_address));
    }
}
