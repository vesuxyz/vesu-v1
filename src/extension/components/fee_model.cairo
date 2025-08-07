use starknet::ContractAddress;

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
pub struct FeeConfig {
    pub fee_recipient: ContractAddress,
}

#[starknet::component]
pub mod fee_model_component {
    use alexandria_math::i257::I257Trait;
    use core::num::traits::Zero;
    use openzeppelin::token::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    #[feature("deprecated-starknet-consts")]
    use starknet::{ContractAddress, contract_address_const, get_contract_address};
    use vesu::data_model::{Amount, AmountDenomination, AmountType, ModifyPositionParams, UpdatePositionResponse};
    use vesu::extension::components::fee_model::FeeConfig;
    use vesu::extension::default_extension_po_v2::{IDefaultExtensionCallback, ITokenizationCallback};
    use vesu::singleton_v2::{ISingletonV2Dispatcher, ISingletonV2DispatcherTrait};
    use vesu::v_token_v2::{IVTokenV2SafeDispatcher, IVTokenV2SafeDispatcherTrait};


    #[storage]
    pub struct Storage {
        // pool_id -> fee configuration
        pub fee_configs: Map<felt252, FeeConfig>,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SetFeeConfig {
        #[key]
        pool_id: felt252,
        #[key]
        fee_config: FeeConfig,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ClaimFees {
        #[key]
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SetFeeConfig: SetFeeConfig,
        ClaimFees: ClaimFees,
    }

    fn _is_v1_pool(pool_id: felt252) -> bool {
        pool_id == 0x4dc4f0ca6ea4961e4c8373265bfd5317678f4fe374d76f3fd7135f57763bf28
            || pool_id == 0x3de03fafe6120a3d21dc77e101de62e165b2cdfe84d12540853bd962b970f99
            || pool_id == 0x52fb52363939c3aa848f8f4ac28f0a51379f8d1b971d8444de25fbd77d8f161
            || pool_id == 0x2e06b705191dbe90a3fbaad18bb005587548048b725116bff3104ca501673c1
            || pool_id == 0x6febb313566c48e30614ddab092856a9ab35b80f359868ca69b2649ca5d148d
            || pool_id == 0x59ae5a41c9ae05eae8d136ad3d7dc48e5a0947c10942b00091aeb7f42efabb7
            || pool_id == 0x43f475012ed51ff6967041fcb9bf28672c96541ab161253fc26105f4c3b2afe
            || pool_id == 0x7bafdbd2939cc3f3526c587cb0092c0d9a93b07b9ced517873f7f6bf6c65563
            || pool_id == 0x7f135b4df21183991e9ff88380c2686dd8634fd4b09bb2b5b14415ac006fe1d
            || pool_id == 0x27f2bb7fb0e232befc5aa865ee27ef82839d5fad3e6ec1de598d0fab438cb56
            || pool_id == 0x5c678347b60b99b72f245399ba27900b5fc126af11f6637c04a193d508dda26
            || pool_id == 0x2906e07881acceff9e4ae4d9dacbcd4239217e5114001844529176e1f0982ec
    }

    #[generate_trait]
    pub impl FeeModelTrait<
        TContractState,
        +HasComponent<TContractState>,
        +IDefaultExtensionCallback<TContractState>,
        +ITokenizationCallback<TContractState>,
    > of Trait<TContractState> {
        /// Sets the fee configuration for a pool
        /// # Arguments
        /// * `pool_id` - The pool id
        /// * `fee_config` - The fee configuration
        fn set_fee_config(ref self: ComponentState<TContractState>, pool_id: felt252, fee_config: FeeConfig) {
            self.fee_configs.write(pool_id, fee_config);
            self.emit(SetFeeConfig { pool_id, fee_config });
        }

        /// Claims the fees accrued in the extension for a given asset in a pool and sends them to the fee recipient
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        fn claim_fees(ref self: ComponentState<TContractState>, pool_id: felt252, collateral_asset: ContractAddress) {
            let singleton = self.get_contract().singleton();

            let (position, _, _) = ISingletonV2Dispatcher { contract_address: singleton }
                .position(pool_id, collateral_asset, Zero::zero(), get_contract_address());

            let v_token = IERC20Dispatcher {
                contract_address: self.get_contract().v_token_for_collateral_asset(pool_id, collateral_asset),
            };

            let unmigrated = if _is_v1_pool(pool_id) {
                #[feature("safe_dispatcher")]
                let response = IVTokenV2SafeDispatcher { contract_address: v_token.contract_address }.v_token_v1();
                match response {
                    Result::Ok(v_token_v1) => {
                        let v_token_v1 = IERC20Dispatcher { contract_address: v_token_v1 };
                        v_token_v1.total_supply() - v_token_v1.balance_of(contract_address_const::<'0x0'>())
                    },
                    Result::Err(_) => 0,
                }
            } else {
                0
            };

            let amount = position.collateral_shares - (v_token.total_supply() + unmigrated);

            let UpdatePositionResponse {
                collateral_delta, ..,
            } =
                ISingletonV2Dispatcher { contract_address: singleton }
                    .modify_position(
                        ModifyPositionParams {
                            pool_id,
                            collateral_asset,
                            debt_asset: Zero::zero(),
                            user: get_contract_address(),
                            collateral: Amount {
                                amount_type: AmountType::Delta,
                                denomination: AmountDenomination::Native,
                                value: I257Trait::new(amount, true),
                            },
                            debt: Default::default(),
                            data: ArrayTrait::new().span(),
                        },
                    );

            let fee_config = self.fee_configs.read(pool_id);
            let amount = collateral_delta.abs();

            IERC20Dispatcher { contract_address: collateral_asset }.transfer(fee_config.fee_recipient, amount);

            self
                .emit(
                    ClaimFees {
                        pool_id,
                        collateral_asset,
                        debt_asset: Zero::zero(),
                        recipient: fee_config.fee_recipient,
                        amount,
                    },
                );
        }
    }
}
