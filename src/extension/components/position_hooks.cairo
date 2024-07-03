#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct ShutdownConfig {
    recovery_period: u64, // [seconds]
    subscription_period: u64, // [seconds]
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct LiquidationConfig {
    liquidation_discount: u256 // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
enum ShutdownMode {
    None,
    Recovery,
    Subscription,
    Redemption
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct ShutdownStatus {
    shutdown_mode: ShutdownMode,
    violating: bool,
    previous_violation_timestamp: u64,
    count_at_violation_timestamp: u128,
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct LiquidationData {
    min_collateral_to_receive: u256,
    debt_to_repay: u256,
}

#[starknet::component]
mod position_hooks_component {
    use alexandria_math::i257::i257;
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address};
    use vesu::vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait};
    use vesu::{
        units::{SCALE, DAY_IN_SECONDS}, math::{pow_10},
        data_model::{Amount, AmountType, AmountDenomination, AssetParams, LTVParams, ModifyPositionParams, Context},
        singleton::{ISingletonDispatcherTrait},
        common::{
            calculate_collateral, calculate_debt, is_collateralized, apply_position_update_to_context,
            calculate_collateral_and_debt_value
        },
        extension::{
            default_extension::{ITimestampManagerCallback},
            components::position_hooks::{
                ShutdownMode, ShutdownStatus, ShutdownConfig, LiquidationConfig, LiquidationData
            }
        }
    };

    #[storage]
    struct Storage {
        // contais the shutdown configuration for each pool
        // pool_id -> shutdown configuration
        shutdown_config: LegacyMap::<felt252, ShutdownConfig>,
        // specifies the max. ltv ratio for each pair at which the recovery mode for a pool is triggered
        // (pool_id, collateral_asset, debt_asset) -> shutdown ltv ratio
        shutdown_ltvs: LegacyMap::<(felt252, ContractAddress, ContractAddress), u256>,
        // contains the liquidation configuration for each asset in a pool
        // (pool_id, asset) -> liquidation configuration
        liquidation_configs: LegacyMap::<(felt252, ContractAddress), LiquidationConfig>,
        // contains the timestamp for each pair at which the pair first caused violation (triggered recovery mode)
        // (pool_id, collateral asset, debt asset) -> timestamp
        timestamps: LegacyMap::<(felt252, ContractAddress, ContractAddress), u64>,
        // contains the number of pairs that caused a violation at each timestamp
        // timestamp -> number of items
        timestamp_counts: LegacyMap::<(felt252, u64), u128>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    fn infer_shutdown_mode_from_timestamp(shutdown_config: ShutdownConfig, entered_timestamp: u64) -> ShutdownMode {
        let ShutdownConfig{recovery_period, subscription_period } = shutdown_config;
        let current_time = get_block_timestamp();
        if entered_timestamp == 0 || (recovery_period == 0 && subscription_period == 0) {
            ShutdownMode::None
        } else if current_time - entered_timestamp < recovery_period {
            ShutdownMode::Recovery
        } else if current_time - entered_timestamp < recovery_period + subscription_period {
            ShutdownMode::Subscription
        } else {
            ShutdownMode::Redemption
        }
    }

    fn is_pair_collateralized(ref context: Context, shutdown_ltv: u256) -> bool {
        let Context{collateral_asset_config, debt_asset_config, .. } = context;
        let collateral = calculate_collateral(collateral_asset_config.total_collateral_shares, collateral_asset_config);
        let debt = calculate_debt(
            debt_asset_config.total_nominal_debt, debt_asset_config.last_rate_accumulator, debt_asset_config.scale
        );
        is_collateralized(
            collateral * context.collateral_asset_price.value / collateral_asset_config.scale,
            debt * context.debt_asset_price.value / debt_asset_config.scale,
            shutdown_ltv
        )
    }

    #[generate_trait]
    impl PositionHooksTrait<
        TContractState, +HasComponent<TContractState>, +ITimestampManagerCallback<TContractState>, +Drop<TContractState>
    > of Trait<TContractState> {
        fn set_liquidation_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            liquidation_discount: u256,
        ) {
            assert(liquidation_discount < SCALE, 'invalid-liquidation-discount');
            self
                .liquidation_configs
                .write(
                    (pool_id, asset),
                    LiquidationConfig {
                        liquidation_discount: if liquidation_discount == 0 {
                            SCALE
                        } else {
                            liquidation_discount
                        }
                    }
                );
        }

        fn set_shutdown_config(
            ref self: ComponentState<TContractState>, pool_id: felt252, recovery_period: u64, subscription_period: u64,
        ) {
            assert(
                (recovery_period == 0 && subscription_period == 0) || (subscription_period >= DAY_IN_SECONDS),
                'invalid-shutdown-config'
            );
            let config = ShutdownConfig { recovery_period, subscription_period };
            self.shutdown_config.write(pool_id, config);
        }

        fn set_shutdown_ltv(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            shutdown_ltv: u256,
        ) {
            self.shutdown_ltvs.write((pool_id, collateral_asset, debt_asset), shutdown_ltv);
        }

        /// Note: In order to get the shutdown status for the entire pool, this function needs to be called on all
        /// pairs associated with the pool.
        /// The furthest progressed shutdown mode for a pair is the shutdown mode of the pool.
        fn shutdown_status(self: @ComponentState<TContractState>, ref context: Context) -> ShutdownStatus {
            let mut oldest_violating_timestamp = self.get_contract().last(context.pool_id);

            // if pool is in either subscription period, redemption period, then return mode
            let shutdown_config = self.shutdown_config.read(context.pool_id);
            let shutdown_mode = infer_shutdown_mode_from_timestamp(shutdown_config, oldest_violating_timestamp);
            if shutdown_mode != ShutdownMode::None && shutdown_mode != ShutdownMode::Recovery {
                return ShutdownStatus {
                    shutdown_mode, violating: false, previous_violation_timestamp: 0, count_at_violation_timestamp: 0
                };
            }

            // check oracle status
            let invalid_oracle = !context.collateral_asset_price.is_valid || !context.debt_asset_price.is_valid;

            // check if pair is collateralized
            let key = (context.pool_id, context.collateral_asset, context.debt_asset);
            let collateralized = is_pair_collateralized(ref context, self.shutdown_ltvs.read(key));

            // check rate accumulator values
            let collateral_accumulator = context.collateral_asset_config.last_rate_accumulator;
            let debt_accumulator = context.debt_asset_config.last_rate_accumulator;
            let safe_rate_accumulator = collateral_accumulator < 18 * SCALE && debt_accumulator < 18 * SCALE;

            // either the oracle price is invalid or the pair is not collateralized or unsafe rate accumulator
            let violating = invalid_oracle || !collateralized || !safe_rate_accumulator;

            let previous_violation_timestamp = self.timestamps.read(key);
            let count_at_violation_timestamp = self
                .timestamp_counts
                .read((context.pool_id, previous_violation_timestamp));

            oldest_violating_timestamp =
                // first violation timestamp added to an empty list (previous_violation_timestamp has to be 0 as well)
                if violating && oldest_violating_timestamp == 0 {
                    get_block_timestamp()
                // last violation timestamp removed from the list (list is empty now)
                } else if !violating
                    && oldest_violating_timestamp == previous_violation_timestamp
                    && count_at_violation_timestamp == 1 { // only one entry for that timestamp remaining in the list
                    0_u64
                // neither the first or the last violation timestamp of the list
                } else {
                    oldest_violating_timestamp
                };

            // infer shutdown mode from the oldest violating timestamp
            let shutdown_mode = infer_shutdown_mode_from_timestamp(shutdown_config, oldest_violating_timestamp);

            ShutdownStatus { shutdown_mode, violating, previous_violation_timestamp, count_at_violation_timestamp }
        }

        /// Note: In a scenario where there are pairs associated with the oldest timestamp which are not causing
        /// a violation anymore and if no other pairs (incl. current pair) are also not causing a violation anymore,
        /// then `update_shutdown_status` needs to be manually called on the pairs associated with the oldest
        /// timestamp to transition the pool back from recovery mode to normal mode.
        fn update_shutdown_status(ref self: ComponentState<TContractState>, ref context: Context) -> ShutdownMode {
            let mut timestamp_manager = self.get_contract_mut();

            let ShutdownStatus{shutdown_mode, violating, previous_violation_timestamp, count_at_violation_timestamp } =
                self
                .shutdown_status(ref context);

            let Context{pool_id, collateral_asset, debt_asset, .. } = context;
            // if there is no current violation and a timestamp exists, then remove it for the pair (recovered)
            if !violating && previous_violation_timestamp != 0 { // implies count_at_violation_timestamp > 0
                self.timestamp_counts.write((pool_id, previous_violation_timestamp), count_at_violation_timestamp - 1);
                self.timestamps.write((pool_id, collateral_asset, debt_asset), 0);
                // remove the violation timestamp from the list if it's the last one
                if count_at_violation_timestamp == 1 {
                    timestamp_manager.remove(pool_id, previous_violation_timestamp);
                }
            }

            // if there is a current violation and no timestamp exists for the pair, then set the it (recovery)
            if violating && previous_violation_timestamp == 0 {
                let count_at_current_violation_timestamp = self.timestamp_counts.read((pool_id, get_block_timestamp()));
                self.timestamp_counts.write((pool_id, get_block_timestamp()), count_at_current_violation_timestamp + 1);
                self.timestamps.write((pool_id, collateral_asset, debt_asset), get_block_timestamp());
                // add the violation timestamp to the list if it's the first entry for that timestamp
                if count_at_current_violation_timestamp == 0 {
                    timestamp_manager.insert_before(pool_id, timestamp_manager.first(pool_id), get_block_timestamp());
                }
            }

            shutdown_mode
        }

        /// Implements position accounting based on the current shutdown mode of a pool.
        /// Each shutdown mode has different constraints on the collateral and debt amounts:
        /// - Normal Mode: collateral and debt amounts are allowed to be modified in any way
        /// - Recovery Mode: collateral can only be added, debt can only be repaid
        /// - Subscription Mode: collateral balance can not be modified, debt can only be repaid
        /// - Redemption Mode: collateral can only be withdrawn, debt balance can not be modified
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `data` - modify position data
        /// # Returns
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        fn after_modify_position(
            ref self: ComponentState<TContractState>,
            mut context: Context,
            collateral_delta: i257,
            debt_delta: i257,
            data: Span<felt252>
        ) -> bool {
            let shutdown_mode = self.update_shutdown_status(ref context);

            // check invariants for collateral and debt amounts
            if shutdown_mode == ShutdownMode::Recovery {
                let decreasing_collateral = collateral_delta < Zeroable::zero();
                let increasing_debt = debt_delta > Zeroable::zero();
                assert(!(decreasing_collateral || increasing_debt), 'in-recovery');
            } else if shutdown_mode == ShutdownMode::Subscription {
                let modifying_collateral = collateral_delta != Zeroable::zero();
                let increasing_debt = debt_delta > Zeroable::zero();
                assert(!(modifying_collateral || increasing_debt), 'in-subscription');
            } else if shutdown_mode == ShutdownMode::Redemption {
                let increasing_collateral = collateral_delta > Zeroable::zero();
                let modifying_debt = debt_delta != Zeroable::zero();
                assert(!(increasing_collateral || modifying_debt), 'in-redemption');
            }

            true
        }

        /// Implements position accounting based for liquidations.
        /// Liquidations are only allowed in normal and recovery mode. The liquidator has to be specify how much
        /// debt to repay and the minimum amount of collateral to receive in exchange. The value of the collateral
        /// is discounted by the liquidation discount in comparison to the current price (according to the oracle).
        /// In an event where there's not enough collateral to cover the debt, the liquidation will result in bad debt.
        /// The bad debt is attributed to the pool and distributed amongst the lenders of the corresponding
        /// collateral asset. The liquidator receives all the collateral but only has to repay the proportioned
        /// debt value. 
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `data` - liquidation data
        /// # Returns
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        fn before_liquidate_position(
            ref self: ComponentState<TContractState>, mut context: Context, mut data: Span<felt252>
        ) -> (Amount, Amount, u256) {
            // don't allow for liquidations if the pool is not in normal or recovery mode
            let shutdown_mode = self.update_shutdown_status(ref context);
            assert(shutdown_mode == ShutdownMode::None || shutdown_mode == ShutdownMode::Recovery, 'emergency-mode');

            let LiquidationData{min_collateral_to_receive, mut debt_to_repay } = Serde::deserialize(ref data)
                .expect('invalid-liquidation-data');

            // compute the collateral and debt value
            let (collateral, mut collateral_value, debt, debt_value) = calculate_collateral_and_debt_value(context);

            // apply liquidation discount to collateral value
            let liquidation_config: LiquidationConfig = self
                .liquidation_configs
                .read((context.pool_id, context.collateral_asset));
            collateral_value = collateral_value * liquidation_config.liquidation_discount / SCALE;

            // limit debt to repay by the position's outstanding debt
            debt_to_repay = if debt_to_repay > debt {
                debt
            } else {
                debt_to_repay
            };

            // apply liquidation discount to debt value to get the collateral amount to release
            let collateral_value_to_receive = debt_to_repay
                * context.debt_asset_price.value
                / context.debt_asset_config.scale;
            let mut collateral_to_receive = (collateral_value_to_receive * SCALE / context.collateral_asset_price.value)
                * context.collateral_asset_config.scale
                / liquidation_config.liquidation_discount;
            collateral_to_receive = if collateral_to_receive > collateral {
                collateral
            } else {
                collateral_to_receive
            };

            // check that a min. amount of collateral is released
            assert(collateral_to_receive >= min_collateral_to_receive, 'less-than-min-collateral');

            // account for bad debt if the entire position is liquidated and there's not enough collateral to cover the debt
            let bad_debt = if collateral_to_receive == collateral && collateral_value >= debt_value {
                0
            } else {
                // only the part of the debt that is covered by the collateral is liquidated
                (debt_value - collateral_value) * context.debt_asset_config.scale / context.debt_asset_price.value
            };

            (
                Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: -collateral_to_receive.into()
                },
                Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: -debt_to_repay.into()
                },
                bad_debt
            )
        }
    }
}
