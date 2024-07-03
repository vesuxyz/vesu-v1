use starknet::ContractAddress;

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct FeeConfig {
    fee_recipient: ContractAddress
}

#[starknet::component]
mod fee_model_component {
    use alexandria_math::i257::{i257, i257_new};
    use starknet::{ContractAddress, get_contract_address};
    use vesu::{
        units::SCALE,
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait, ModifyPositionParams, UpdatePositionResponse},
        data_model::{Amount, AmountDenomination, AmountType},
        extension::{
            components::fee_model::FeeConfig, default_extension::{IDefaultExtensionCallback, ITokenizationCallback}
        },
        vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait}
    };

    #[storage]
    struct Storage {
        // pool_id -> fee configuration
        fee_configs: LegacyMap::<felt252, FeeConfig>,
    }

    #[derive(Drop, starknet::Event)]
    struct SetFeeConfig {
        #[key]
        pool_id: felt252,
        #[key]
        fee_config: FeeConfig
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimFees {
        #[key]
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetFeeConfig: SetFeeConfig,
        ClaimFees: ClaimFees
    }

    #[generate_trait]
    impl FeeModelTrait<
        TContractState,
        +HasComponent<TContractState>,
        +IDefaultExtensionCallback<TContractState>,
        +ITokenizationCallback<TContractState>
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

            let (position, _, _) = ISingletonDispatcher { contract_address: singleton }
                .position(pool_id, collateral_asset, Zeroable::zero(), get_contract_address());
            let total_supply = IERC20Dispatcher {
                contract_address: self.get_contract().v_token_for_collateral_asset(pool_id, collateral_asset)
            }
                .total_supply();

            let amount = position.collateral_shares - total_supply;

            let UpdatePositionResponse { collateral_delta, .. } = ISingletonDispatcher { contract_address: singleton }
                .modify_position(
                    ModifyPositionParams {
                        pool_id,
                        collateral_asset,
                        debt_asset: Zeroable::zero(),
                        user: get_contract_address(),
                        collateral: Amount {
                            amount_type: AmountType::Delta,
                            denomination: AmountDenomination::Native,
                            value: i257_new(amount, true),
                        },
                        debt: Default::default(),
                        data: ArrayTrait::new().span()
                    }
                );

            let fee_config = self.fee_configs.read(pool_id);
            let amount = collateral_delta.abs;

            IERC20Dispatcher { contract_address: collateral_asset }.transfer(fee_config.fee_recipient, amount);

            self
                .emit(
                    ClaimFees {
                        pool_id,
                        collateral_asset,
                        debt_asset: Zeroable::zero(),
                        recipient: fee_config.fee_recipient,
                        amount
                    }
                );
        }
    }
}
