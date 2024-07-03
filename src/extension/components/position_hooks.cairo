use vesu::{units::{SCALE, DAY_IN_SECONDS}, packing::{into_u123, SHIFT_128, split_128}, data_model::{LTVParams}};

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct ShutdownConfig {
    recovery_period: u64, // [seconds]
    subscription_period: u64, // [seconds]
}

#[inline(always)]
fn assert_shutdown_config(shutdown_config: ShutdownConfig) {
    assert!(
        (shutdown_config.recovery_period == 0 && shutdown_config.subscription_period == 0)
            || (shutdown_config.subscription_period >= DAY_IN_SECONDS),
        "invalid-shutdown-config"
    );
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct LiquidationConfig {
    liquidation_discount: u64 // [SCALE]
}

#[inline(always)]
fn assert_liquidation_config(liquidation_config: LiquidationConfig) {
    assert!(liquidation_config.liquidation_discount.into() < SCALE, "invalid-liquidation-discount");
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::StorePacking)]
struct Pair {
    total_collateral_shares: u256, // packed as u128 [SCALE] 
    total_nominal_debt: u256 // packed as u123 [SCALE]
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

impl PairPacking of starknet::StorePacking<Pair, felt252> {
    fn pack(value: Pair) -> felt252 {
        let total_collateral_shares: u128 = value
            .total_collateral_shares
            .try_into()
            .expect('pack-total_collateral-shares');
        let total_nominal_debt: u128 = value.total_nominal_debt.try_into().expect('pack-total_nominal-debt');
        let total_nominal_debt = into_u123(total_nominal_debt, 'pack-total_nominal-debt-u123');
        total_collateral_shares.into() + total_nominal_debt * SHIFT_128
    }

    fn unpack(value: felt252) -> Pair {
        let (total_nominal_debt, total_collateral_shares) = split_128(value.into());
        Pair { total_collateral_shares: total_collateral_shares.into(), total_nominal_debt: total_nominal_debt.into() }
    }
}

#[starknet::component]
mod position_hooks_component {
    use alexandria_math::i257::i257;
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address};
    use vesu::vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait};
    use vesu::{
        units::{SCALE, DAY_IN_SECONDS}, math::{pow_10},
        data_model::{
            Amount, AmountType, AmountDenomination, AssetParams, LTVParams, ModifyPositionParams, Context, Position,
            LTVConfig, assert_ltv_config
        },
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
        common::{
            calculate_collateral, calculate_debt, is_collateralized, apply_position_update_to_context,
            calculate_collateral_and_debt_value
        },
        extension::{
            default_extension::{ITimestampManagerCallback},
            components::position_hooks::{
                ShutdownMode, ShutdownStatus, ShutdownConfig, LiquidationConfig, LiquidationData, Pair,
                assert_shutdown_config, assert_liquidation_config
            }
        },
    };

    #[storage]
    struct Storage {
        // contains the shutdown configuration for each pool
        // pool_id -> shutdown configuration
        shutdown_configs: LegacyMap::<felt252, ShutdownConfig>,
        // specifies the ltv configuration for each pair at which the recovery mode for a pool is triggered
        // (pool_id, collateral_asset, debt_asset) -> shutdown ltv configuration
        shutdown_ltv_configs: LegacyMap::<(felt252, ContractAddress, ContractAddress), LTVConfig>,
        // contains the liquidation configuration for each asset in a pool
        // (pool_id, asset) -> liquidation configuration
        liquidation_configs: LegacyMap::<(felt252, ContractAddress), LiquidationConfig>,
        // contains the timestamp for each pair at which the pair first caused violation (triggered recovery mode)
        // (pool_id, collateral asset, debt asset) -> timestamp
        violation_timestamps: LegacyMap::<(felt252, ContractAddress, ContractAddress), u64>,
        // contains the number of pairs that caused a violation at each timestamp
        // timestamp -> number of items
        violation_timestamp_counts: LegacyMap::<(felt252, u64), u128>,
        // tracks the total collateral shares and the total nominal debt for each pair
        // (pool_id, collateral asset, debt asset) -> pair configuration
        pairs: LegacyMap::<(felt252, ContractAddress, ContractAddress), Pair>
    }

    #[derive(Drop, starknet::Event)]
    struct SetLiquidationConfig {
        pool_id: felt252,
        asset: ContractAddress,
        liquidation_config: LiquidationConfig,
    }

    #[derive(Drop, starknet::Event)]
    struct SetShutdownConfig {
        pool_id: felt252,
        shutdown_config: ShutdownConfig
    }

    #[derive(Drop, starknet::Event)]
    struct SetShutdownLTVConfig {
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        shutdown_ltv_config: LTVConfig,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetLiquidationConfig: SetLiquidationConfig,
        SetShutdownConfig: SetShutdownConfig,
        SetShutdownLTVConfig: SetShutdownLTVConfig
    }

    // Infers the shutdown_config from the timestamp at which the violation occured and the current time
    fn infer_shutdown_mode_from_timestamp(shutdown_config: ShutdownConfig, entered_timestamp: u64) -> ShutdownMode {
        let ShutdownConfig { recovery_period, subscription_period } = shutdown_config;
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

    #[generate_trait]
    impl PositionHooksTrait<
        TContractState, +HasComponent<TContractState>, +ITimestampManagerCallback<TContractState>, +Drop<TContractState>
    > of Trait<TContractState> {
        /// Checks if a pair is collateralized based on the current oracle prices and the shutdown ltv configuration.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// # Returns
        /// * `bool` - true if the pair is collateralized, false otherwise
        fn is_pair_collateralized(self: @ComponentState<TContractState>, ref context: Context) -> bool {
            let Pair { total_collateral_shares, total_nominal_debt } = self
                .pairs
                .read((context.pool_id, context.collateral_asset, context.debt_asset));
            let (_, collateral_value, _, debt_value) = calculate_collateral_and_debt_value(
                context, Position { collateral_shares: total_collateral_shares, nominal_debt: total_nominal_debt }
            );
            let LTVConfig { max_ltv } = self
                .shutdown_ltv_configs
                .read((context.pool_id, context.collateral_asset, context.debt_asset));
            is_collateralized(collateral_value, debt_value, max_ltv.into())
        }

        /// Sets the liquidation configuration for an asset in a pool.
        /// # Arguments
        /// * `pool_id` - pool identifier
        /// * `asset` - asset identifier
        /// * `liquidation_config` - liquidation configuration
        fn set_liquidation_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            liquidation_config: LiquidationConfig
        ) {
            assert_liquidation_config(liquidation_config);

            self
                .liquidation_configs
                .write(
                    (pool_id, asset),
                    LiquidationConfig {
                        liquidation_discount: if liquidation_config.liquidation_discount == 0 {
                            SCALE.try_into().unwrap()
                        } else {
                            liquidation_config.liquidation_discount
                        }
                    }
                );

            self.emit(SetLiquidationConfig { pool_id, asset, liquidation_config });
        }

        /// Sets the shutdown configuration for a pool.
        /// # Arguments
        /// * `pool_id` - pool identifier
        /// * `shutdown_config` - shutdown configuration
        fn set_shutdown_config(
            ref self: ComponentState<TContractState>, pool_id: felt252, shutdown_config: ShutdownConfig
        ) {
            assert_shutdown_config(shutdown_config);

            self.shutdown_configs.write(pool_id, shutdown_config);

            self.emit(SetShutdownConfig { pool_id, shutdown_config });
        }

        /// Sets the shutdown ltv configuration for a pair in a pool.
        /// # Arguments
        /// * `pool_id` - pool identifier
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `shutdown_ltv_config` - shutdown ltv configuration
        fn set_shutdown_ltv_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            shutdown_ltv_config: LTVConfig,
        ) {
            assert_ltv_config(shutdown_ltv_config);

            self.shutdown_ltv_configs.write((pool_id, collateral_asset, debt_asset), shutdown_ltv_config);

            self.emit(SetShutdownLTVConfig { pool_id, collateral_asset, debt_asset, shutdown_ltv_config });
        }

        /// Note: In order to get the shutdown status for the entire pool, this function needs to be called on all
        /// pairs associated with the pool.
        /// The furthest progressed shutdown mode for a pair is the shutdown mode of the pool.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// # Returns
        /// * `shutdown_status` - shutdown status of the pool
        fn shutdown_status(self: @ComponentState<TContractState>, ref context: Context) -> ShutdownStatus {
            let violation_timestamp_manager = self.get_contract();
            let mut oldest_violating_timestamp = violation_timestamp_manager.last(context.pool_id);

            // if pool is in either subscription period, redemption period, then return mode
            let shutdown_config = self.shutdown_configs.read(context.pool_id);
            let shutdown_mode = infer_shutdown_mode_from_timestamp(shutdown_config, oldest_violating_timestamp);
            if shutdown_mode != ShutdownMode::None && shutdown_mode != ShutdownMode::Recovery {
                return ShutdownStatus {
                    shutdown_mode, violating: false, previous_violation_timestamp: 0, count_at_violation_timestamp: 0
                };
            }

            // check oracle status
            let invalid_oracle = !context.collateral_asset_price.is_valid || !context.debt_asset_price.is_valid;

            // check if pair is collateralized
            let collateralized = self.is_pair_collateralized(ref context);

            // check rate accumulator values
            let collateral_accumulator = context.collateral_asset_config.last_rate_accumulator;
            let debt_accumulator = context.debt_asset_config.last_rate_accumulator;
            let safe_rate_accumulator = collateral_accumulator < 18 * SCALE && debt_accumulator < 18 * SCALE;

            // either the oracle price is invalid or the pair is not collateralized or unsafe rate accumulator
            let violating = invalid_oracle || !collateralized || !safe_rate_accumulator;

            let previous_violation_timestamp = self
                .violation_timestamps
                .read((context.pool_id, context.collateral_asset, context.debt_asset));
            let count_at_violation_timestamp = self
                .violation_timestamp_counts
                .read((context.pool_id, previous_violation_timestamp));

            oldest_violating_timestamp =
                // first violation timestamp added to an empty list (previous_violation_timestamp has to be 0 as well)
                if violating && oldest_violating_timestamp == 0 {
                    get_block_timestamp()
                // oldest violation timestamp removed from the list (move to the next oldest violation timestamp)
                } else if !violating
                    && oldest_violating_timestamp == previous_violation_timestamp
                    && count_at_violation_timestamp == 1 { // only one entry for that timestamp remaining in the list
                    violation_timestamp_manager
                        .previous(context.pool_id, oldest_violating_timestamp) // get next oldest one
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
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// # Returns
        /// * `shutdown_mode` - the shutdown mode of the pool
        fn update_shutdown_status(ref self: ComponentState<TContractState>, ref context: Context) -> ShutdownMode {
            let mut violation_timestamp_manager = self.get_contract_mut();

            let ShutdownStatus { shutdown_mode,
            violating,
            previous_violation_timestamp,
            count_at_violation_timestamp } =
                self
                .shutdown_status(ref context);

            let Context { pool_id, collateral_asset, debt_asset, .. } = context;
            // if there is no current violation and a timestamp exists, then remove it for the pair (recovered)
            if !violating && previous_violation_timestamp != 0 { // implies count_at_violation_timestamp > 0
                self
                    .violation_timestamp_counts
                    .write((pool_id, previous_violation_timestamp), count_at_violation_timestamp - 1);
                self.violation_timestamps.write((pool_id, collateral_asset, debt_asset), 0);
                // remove the violation timestamp from the list if it's the last one
                if count_at_violation_timestamp == 1 {
                    violation_timestamp_manager.remove(pool_id, previous_violation_timestamp);
                }
            }

            // if there is a current violation and no timestamp exists for the pair, then set the it (recovery)
            if violating && previous_violation_timestamp == 0 {
                let count_at_current_violation_timestamp = self
                    .violation_timestamp_counts
                    .read((pool_id, get_block_timestamp()));
                self
                    .violation_timestamp_counts
                    .write((pool_id, get_block_timestamp()), count_at_current_violation_timestamp + 1);
                self.violation_timestamps.write((pool_id, collateral_asset, debt_asset), get_block_timestamp());
                // add the violation timestamp to the list if it's the first entry for that timestamp
                if count_at_current_violation_timestamp == 0 {
                    violation_timestamp_manager.push_front(pool_id, get_block_timestamp());
                }
            }

            shutdown_mode
        }

        /// Updates the tracked total collateral shares and the total nominal debt assigned to a specific pair.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_shares_delta` - collateral shares balance delta of the position
        /// * `nominal_debt_delta` - nominal debt balance delta of the position
        fn update_pair(
            ref self: ComponentState<TContractState>,
            ref context: Context,
            collateral_shares_delta: i257,
            nominal_debt_delta: i257
        ) {
            let Pair { mut total_collateral_shares, mut total_nominal_debt } = self
                .pairs
                .read((context.pool_id, context.collateral_asset, context.debt_asset));

            if collateral_shares_delta > Zeroable::zero() {
                total_collateral_shares = total_collateral_shares + collateral_shares_delta.abs;
            } else if collateral_shares_delta < Zeroable::zero() {
                total_collateral_shares = total_collateral_shares - collateral_shares_delta.abs;
            }

            if nominal_debt_delta > Zeroable::zero() {
                total_nominal_debt = total_nominal_debt + nominal_debt_delta.abs;
            } else if nominal_debt_delta < Zeroable::zero() {
                total_nominal_debt = total_nominal_debt - nominal_debt_delta.abs;
            }

            self
                .pairs
                .write(
                    (context.pool_id, context.collateral_asset, context.debt_asset),
                    Pair { total_collateral_shares, total_nominal_debt }
                );
        }

        /// Implements position accounting based on the current shutdown mode of a pool.
        /// Each shutdown mode has different constraints on the collateral and debt amounts:
        /// - Normal Mode: collateral and debt amounts are allowed to be modified in any way
        /// - Recovery Mode: collateral can only be added, debt can only be repaid
        /// - Subscription Mode: collateral balance can not be modified, debt can only be repaid
        /// - Redemption Mode: collateral can only be withdrawn, debt balance can not be modified
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `collateral_shares_delta` - collateral shares balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `nominal_debt_delta` - nominal debt balance delta of the position
        /// * `data` - modify position data
        /// # Returns
        /// * `bool` - true if it was successful, false otherwise
        fn after_modify_position(
            ref self: ComponentState<TContractState>,
            mut context: Context,
            collateral_delta: i257,
            collateral_shares_delta: i257,
            debt_delta: i257,
            nominal_debt_delta: i257,
            data: Span<felt252>,
            singleton: ContractAddress
        ) -> bool {
            self.update_pair(ref context, collateral_shares_delta, nominal_debt_delta);

            let shutdown_mode = self.update_shutdown_status(ref context);

            // check invariants for collateral and debt amounts
            if shutdown_mode == ShutdownMode::Recovery {
                let decreasing_collateral = collateral_delta < Zeroable::zero();
                let increasing_debt = debt_delta > Zeroable::zero();
                assert!(!(decreasing_collateral || increasing_debt), "in-recovery");
            } else if shutdown_mode == ShutdownMode::Subscription {
                let modifying_collateral = collateral_delta != Zeroable::zero();
                let increasing_debt = debt_delta > Zeroable::zero();
                assert!(!(modifying_collateral || increasing_debt), "in-subscription");
                // set max_utilization to 100% if it's not already set
                if context.collateral_asset_config.max_utilization != SCALE {
                    ISingletonDispatcher { contract_address: singleton }
                        .set_asset_parameter(context.pool_id, context.collateral_asset, 'max_utilization', SCALE);
                }
            } else if shutdown_mode == ShutdownMode::Redemption {
                let increasing_collateral = collateral_delta > Zeroable::zero();
                let modifying_debt = debt_delta != Zeroable::zero();
                assert!(!(increasing_collateral || modifying_debt), "in-redemption");
                assert!(context.position.nominal_debt == 0, "non-zero-debt");
                assert!(context.position.collateral_shares == 0, "non-zero-collateral-shares");
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
        /// * `data` - liquidation data
        /// # Returns
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `bad_debt` - amount of bad debt accrued during the liquidation
        fn before_liquidate_position(
            ref self: ComponentState<TContractState>, mut context: Context, mut data: Span<felt252>
        ) -> (Amount, Amount, u256) {
            // don't allow for liquidations if the pool is not in normal or recovery mode
            let shutdown_mode = self.update_shutdown_status(ref context);
            assert!(
                shutdown_mode == ShutdownMode::None || shutdown_mode == ShutdownMode::Recovery
                    && context.collateral_asset_price.is_valid
                    && context.debt_asset_price.is_valid,
                "emergency-mode"
            );

            let LiquidationData { min_collateral_to_receive, mut debt_to_repay } = Serde::deserialize(ref data)
                .expect('invalid-liquidation-data');

            // compute the collateral and debt value
            let (collateral, mut collateral_value, debt, debt_value) = calculate_collateral_and_debt_value(
                context, context.position
            );

            // apply liquidation discount to collateral value
            let liquidation_config: LiquidationConfig = self
                .liquidation_configs
                .read((context.pool_id, context.collateral_asset));
            collateral_value = collateral_value * liquidation_config.liquidation_discount.into() / SCALE;

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
                / liquidation_config.liquidation_discount.into();
            collateral_to_receive = if collateral_to_receive > collateral {
                collateral
            } else {
                collateral_to_receive
            };

            // check that a min. amount of collateral is released
            assert!(collateral_to_receive >= min_collateral_to_receive, "less-than-min-collateral");

            // account for bad debt in proportion to the (partial) liquidation amount
            let bad_debt = if collateral_value < debt_value {
                // only the part of the debt that is covered by the collateral is recovered
                // bad_debt is derived from the shortfall in usd terms as a portion to the amount of debt to repay
                // for readability the following formula is equivalent to:
                //   (debt_to_repay * context.debt_asset_config.scale / debt) * (debt_value - collateral_value)
                //   / SCALE * context.debt_asset_config.scale / context.debt_asset_price.value
                debt_to_repay
                    * (debt_value - collateral_value)
                    / debt
                    * context.debt_asset_config.scale
                    / context.debt_asset_price.value
            } else {
                0
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

        /// Implements position accounting based for liquidations.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `collateral_shares_delta` - collateral shares balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `nominal_debt_delta` - nominal debt balance delta of the position
        /// * `bad_debt` - amount of bad debt accrued during the liquidation
        /// * `data` - liquidation data
        /// # Returns
        /// * `bool` - true if it was successful, false otherwise
        fn after_liquidate_position(
            ref self: ComponentState<TContractState>,
            mut context: Context,
            collateral_delta: i257,
            collateral_shares_delta: i257,
            debt_delta: i257,
            nominal_debt_delta: i257,
            bad_debt: u256,
            data: Span<felt252>,
        ) -> bool {
            self.update_pair(ref context, collateral_shares_delta, nominal_debt_delta);
            true
        }
    }
}
