use starknet::{ContractAddress};

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct FeeConfig {
    fee_recipient: ContractAddress
}

#[starknet::component]
mod fee_model_component {
    use starknet::{ContractAddress, get_contract_address};
    use vesu::{
        units::{SCALE},
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait, ModifyPositionParams, UpdatePositionResponse},
        data_model::{Amount, AmountDenomination, AmountType},
        vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait},
        extension::components::fee_model::FeeConfig
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
    impl FeeModelTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        /// Sets the fee configuration for a pool
        /// # Arguments
        /// * `pool_id` - The pool id
        /// * `fee_config` - The fee configuration
        fn set_fee_config(ref self: ComponentState<TContractState>, pool_id: felt252, fee_config: FeeConfig) {
            self.fee_configs.write(pool_id, fee_config);
            self.emit(SetFeeConfig { pool_id, fee_config });
        }

        /// Claims the fees accrued in the extension for a given pool a sends them to the fee recipient
        /// # Arguments
        /// * `singleton` - The singleton contract address
        /// * `pool_id` - The pool id
        /// * `collateral_asset` - The collateral asset
        /// * `debt_asset` - The debt asset
        fn claim_fees(
            ref self: ComponentState<TContractState>,
            singleton: ContractAddress,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress
        ) {
            let UpdatePositionResponse { collateral_delta, .. } = ISingletonDispatcher { contract_address: singleton }
                .modify_position(
                    ModifyPositionParams {
                        pool_id,
                        collateral_asset,
                        debt_asset,
                        user: get_contract_address(),
                        collateral: Amount {
                            amount_type: AmountType::Target, denomination: AmountDenomination::Native, value: 0.into(),
                        },
                        debt: Default::default(),
                        data: ArrayTrait::new().span()
                    }
                );

            let fee_config = self.fee_configs.read(pool_id);
            let amount = collateral_delta.abs;

            IERC20Dispatcher { contract_address: collateral_asset }.transfer(fee_config.fee_recipient, amount);

            self.emit(ClaimFees { pool_id, collateral_asset, debt_asset, recipient: fee_config.fee_recipient, amount });
        }
    }
}
