use vesu::{units::{SCALE, DAY_IN_SECONDS}, packing::{into_u123, SHIFT_128, split_128}};

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
    liquidation_factor: u64 // [SCALE]
}

#[inline(always)]
fn assert_liquidation_config(liquidation_config: LiquidationConfig) {
    assert!(liquidation_config.liquidation_factor.into() <= SCALE, "invalid-liquidation-config");
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::StorePacking)]
struct Pair {
    total_collateral_shares: u256, // packed as u128 [SCALE] 
    total_nominal_debt: u256 // packed as u123 [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde, Default, starknet::Store)]
enum ShutdownMode {
    #[default]
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

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct FixedShutdownMode {
    // fixed shutdown mode (overwrites the inferred shutdown mode)
    fixed_shutdown_mode: ShutdownMode,
    // timestamp at which the fixed shutdown mode was last updated
    last_fixed_timestamp: u64,
    // contains the cumulative time of how long the shutdown mode was overwritten for each pool
    fixed_offset: u64,
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
    use alexandria_math::i257::{i257, i257_new};
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address};
    use vesu::{
        units::SCALE, math::pow_10,
        data_model::{Amount, Context, Position, LTVConfig, assert_ltv_config, UnsignedAmount},
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
        common::{calculate_collateral, is_collateralized, calculate_collateral_and_debt_value, calculate_debt},
        extension::{
            default_extension_po::{IDefaultExtensionCallback, ITimestampManagerCallback, ITokenizationCallback},
            components::position_hooks::{
                ShutdownMode, ShutdownStatus, ShutdownConfig, LiquidationConfig, LiquidationData, Pair,
                assert_shutdown_config, assert_liquidation_config, FixedShutdownMode
            }
        }
    };

    #[storage]
    struct Storage {
        // contains the shutdown configuration for each pool
        // pool_id -> shutdown configuration
        shutdown_configs: LegacyMap::<felt252, ShutdownConfig>,
        // specifies the ltv configuration for each pair at which the recovery mode for a pool is triggered
        // (pool_id, collateral_asset, debt_asset) -> shutdown ltv configuration
        shutdown_ltv_configs: LegacyMap::<(felt252, ContractAddress, ContractAddress), LTVConfig>,
        // contains the fixed (overwritten) shutdown mode state for a pool
        // pool_id -> fixed shutdown mode
        fixed_shutdown_mode: LegacyMap::<felt252, FixedShutdownMode>,
        // contains the liquidation configuration for each pair in a pool
        // (pool_id, collateral_asset, debt_asset) -> liquidation configuration
        liquidation_configs: LegacyMap::<(felt252, ContractAddress, ContractAddress), LiquidationConfig>,
        // contains the timestamp for each pair at which the pair first caused violation (triggered recovery mode)
        // (pool_id, collateral asset, debt asset) -> timestamp
        violation_timestamps: LegacyMap::<(felt252, ContractAddress, ContractAddress), u64>,
        // contains the number of pairs that caused a violation at each timestamp
        // timestamp -> number of items
        violation_timestamp_counts: LegacyMap::<(felt252, u64), u128>,
        // tracks the total collateral shares and the total nominal debt for each pair
        // (pool_id, collateral asset, debt asset) -> pair configuration
        pairs: LegacyMap::<(felt252, ContractAddress, ContractAddress), Pair>,
        // tracks the debt caps for each asset
        debt_caps: LegacyMap::<(felt252, ContractAddress, ContractAddress), u256>
    }

    #[derive(Drop, starknet::Event)]
    struct SetLiquidationConfig {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        liquidation_config: LiquidationConfig,
    }

    #[derive(Drop, starknet::Event)]
    struct SetShutdownConfig {
        #[key]
        pool_id: felt252,
        shutdown_config: ShutdownConfig
    }

    #[derive(Drop, starknet::Event)]
    struct SetShutdownLTVConfig {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        shutdown_ltv_config: LTVConfig,
    }

    #[derive(Drop, starknet::Event)]
    struct SetDebtCap {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        debt_cap: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetLiquidationConfig: SetLiquidationConfig,
        SetShutdownConfig: SetShutdownConfig,
        SetShutdownLTVConfig: SetShutdownLTVConfig,
        SetDebtCap: SetDebtCap
    }

    // Infers the shutdown_config from the timestamp at which the violation occurred and the current time
    fn infer_shutdown_mode_from_timestamp(
        shutdown_config: ShutdownConfig, mut entered_timestamp: u64, overwritten_time_offset: u64
    ) -> ShutdownMode {
        let ShutdownConfig { recovery_period, subscription_period } = shutdown_config;
        let current_timestamp = get_block_timestamp();
        entered_timestamp =
            if entered_timestamp + overwritten_time_offset <= current_timestamp {
                entered_timestamp + overwritten_time_offset
            } else {
                entered_timestamp
            };
        if entered_timestamp == 0 || (recovery_period == 0 && subscription_period == 0) {
            ShutdownMode::None
        } else if current_timestamp - entered_timestamp < recovery_period {
            ShutdownMode::Recovery
        } else if current_timestamp - entered_timestamp < recovery_period + subscription_period {
            ShutdownMode::Subscription
        } else {
            ShutdownMode::Redemption
        }
    }

    #[generate_trait]
    impl PositionHooksTrait<
        TContractState,
        +HasComponent<TContractState>,
        +IDefaultExtensionCallback<TContractState>,
        +ITimestampManagerCallback<TContractState>,
        +ITokenizationCallback<TContractState>,
        +Drop<TContractState>
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
            if max_ltv != 0 {
                is_collateralized(collateral_value, debt_value, max_ltv.into())
            } else {
                true
            }
        }

        /// Sets the debt cap for an asset in a pool.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `debt_cap` - debt cap
        fn set_debt_cap(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            debt_cap: u256
        ) {
            self.debt_caps.write((pool_id, collateral_asset, debt_asset), debt_cap);
            self.emit(SetDebtCap { pool_id, collateral_asset, debt_asset, debt_cap });
        }

        /// Sets the liquidation configuration for an asset pairing in a pool.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `liquidation_config` - liquidation configuration
        fn set_liquidation_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            liquidation_config: LiquidationConfig
        ) {
            assert_liquidation_config(liquidation_config);

            self
                .liquidation_configs
                .write(
                    (pool_id, collateral_asset, debt_asset),
                    LiquidationConfig {
                        liquidation_factor: if liquidation_config.liquidation_factor == 0 {
                            SCALE.try_into().unwrap()
                        } else {
                            liquidation_config.liquidation_factor
                        }
                    }
                );

            self.emit(SetLiquidationConfig { pool_id, collateral_asset, debt_asset, liquidation_config });
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
            let FixedShutdownMode { fixed_shutdown_mode, fixed_offset, .. } = self
                .fixed_shutdown_mode
                .read(context.pool_id);
            let mut shutdown_mode = infer_shutdown_mode_from_timestamp(
                shutdown_config, oldest_violating_timestamp, fixed_offset
            );

            // skip the violation checks if the shutdown mode has been fixed
            if fixed_shutdown_mode != ShutdownMode::None {
                return ShutdownStatus {
                    shutdown_mode: fixed_shutdown_mode,
                    violating: false,
                    previous_violation_timestamp: 0,
                    count_at_violation_timestamp: 0
                };
            }

            // skip the violation checks if the shutdown process has progressed beyond the recovery period
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
            shutdown_mode =
                infer_shutdown_mode_from_timestamp(shutdown_config, oldest_violating_timestamp, fixed_offset);

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

            // check if the shutdown mode has been overwritten
            let FixedShutdownMode { fixed_shutdown_mode, .. } = self.fixed_shutdown_mode.read(context.pool_id);
            if fixed_shutdown_mode != ShutdownMode::None {
                return fixed_shutdown_mode;
            }

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

            if shutdown_mode == ShutdownMode::Redemption {
                // set max_utilization to 100% if it's not already set
                if context.collateral_asset_config.max_utilization != SCALE {
                    ISingletonDispatcher { contract_address: self.get_contract().singleton() }
                        .set_asset_parameter(context.pool_id, context.collateral_asset, 'max_utilization', SCALE);
                }
            }

            shutdown_mode
        }

        /// Sets the shutdown mode for a pool which overwrites the inferred shutdown mode.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `shutdown_mode` - shutdown mode
        fn set_shutdown_mode(
            ref self: ComponentState<TContractState>, pool_id: felt252, new_fixed_shutdown_mode: ShutdownMode
        ) {
            // track for how many seconds the shutdown state was overwritten
            let FixedShutdownMode { fixed_shutdown_mode, last_fixed_timestamp, fixed_offset, .. } = self
                .fixed_shutdown_mode
                .read(pool_id);

            // can only transition to recovery mode if the shutdown mode is in normal mode
            assert!(
                fixed_shutdown_mode != ShutdownMode::None || new_fixed_shutdown_mode == ShutdownMode::Recovery,
                "fixed-shutdown-mode-not-none-or-recovery"
            );
            // can only transition back to normal mode or subscription mode if the shutdown mode is in recovery mode
            assert!(
                fixed_shutdown_mode != ShutdownMode::Recovery
                    || (new_fixed_shutdown_mode == ShutdownMode::None
                        || new_fixed_shutdown_mode == ShutdownMode::Subscription),
                "fixed-shutdown-mode-not-none-or-subscription"
            );
            // can only transition to redemption mode if the shutdown mode is in subscription mode
            assert!(
                fixed_shutdown_mode != ShutdownMode::Subscription
                    || new_fixed_shutdown_mode == ShutdownMode::Redemption,
                "fixed-shutdown-mode-not-redemption"
            );
            // can not transition into any shutdown mode if the shutdown mode is in redemption mode
            assert!(fixed_shutdown_mode != ShutdownMode::Redemption, "fixed-shutdown-mode-in-redemption");

            self
                .fixed_shutdown_mode
                .write(
                    pool_id,
                    FixedShutdownMode {
                        // update when moving from non fixed to fixed
                        last_fixed_timestamp: if fixed_shutdown_mode == ShutdownMode::None
                            && new_fixed_shutdown_mode != ShutdownMode::None {
                            get_block_timestamp()
                        } else {
                            last_fixed_timestamp
                        },
                        // update when moving from fixed to non fixed
                        fixed_offset: if fixed_shutdown_mode != ShutdownMode::None
                            && new_fixed_shutdown_mode == ShutdownMode::None {
                            fixed_offset + get_block_timestamp() - last_fixed_timestamp
                        } else {
                            fixed_offset
                        },
                        fixed_shutdown_mode: new_fixed_shutdown_mode,
                    }
                );
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
            // skip updating the pairs if the debt asset is zero as the pair's ltv is always 100% 
            if context.debt_asset == Zeroable::zero() {
                return;
            }

            // update the balances of the pair of the modified position
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
                let debt_cap = self.debt_caps.read((context.pool_id, context.collateral_asset, context.debt_asset));
                if debt_cap != 0 {
                    let total_debt = calculate_debt(
                        total_nominal_debt,
                        context.debt_asset_config.last_rate_accumulator,
                        context.debt_asset_config.scale,
                        true
                    );
                    assert!(total_debt <= debt_cap, "debt-cap-exceeded");
                }
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
        /// * `data` - modify position data (optional)
        /// * `caller` - address of the caller
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
            caller: ContractAddress
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
            } else if shutdown_mode == ShutdownMode::Redemption {
                let increasing_collateral = collateral_delta > Zeroable::zero();
                let modifying_debt = debt_delta != Zeroable::zero();
                assert!(!(increasing_collateral || modifying_debt), "in-redemption");
                assert!(context.position.nominal_debt == 0, "non-zero-debt");
            }

            true
        }

        /// Implements logic to execute before a transfer of collateral or debt from one position to another.
        /// Grants the caller the delegate to modify the position owned by the extension itself.
        /// # Arguments
        /// * `from_context` - contextual state of the `from` position owner
        /// * `to_context` - contextual state of the `to` position owner
        /// * `collateral` - amount of collateral to be transferred
        /// * `debt` - amount of debt to be transferred
        /// * `data` - transfer data (optional)
        /// * `caller` - address of the caller that called `transfer_position`
        /// # Returns
        /// * `collateral` - amount of collateral to be transferred
        /// * `debt` - amount of debt to be transferred
        fn before_transfer_position(
            ref self: ComponentState<TContractState>,
            from_context: Context,
            to_context: Context,
            collateral: UnsignedAmount,
            debt: UnsignedAmount,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> (UnsignedAmount, UnsignedAmount) {
            if from_context.debt_asset == Zeroable::zero() && from_context.user == get_contract_address() {
                ISingletonDispatcher { contract_address: self.get_contract().singleton() }
                    .modify_delegation(from_context.pool_id, caller, true);
            }
            (collateral, debt)
        }

        /// Implements logic to execute after a transfer of collateral or debt from one position to another.
        /// Revokes the caller's delegate to modify the position owned by the extension itself.
        /// # Arguments
        /// * `from_context` - contextual state of the `from` position owner
        /// * `to_context` - contextual state of the `to` position owner
        /// * `collateral_delta` - collateral balance delta that was transferred
        /// * `collateral_shares_delta` - collateral shares balance delta that was transferred
        /// * `debt_delta` - debt balance delta that was transferred
        /// * `nominal_debt_delta` - nominal debt balance delta that was transferred
        /// * `data` - transfer data (optional)
        /// * `caller` - address of the caller that called `transfer_position`
        /// # Returns
        /// * `bool` - true if it was successful, false otherwise
        fn after_transfer_position(
            ref self: ComponentState<TContractState>,
            mut from_context: Context,
            mut to_context: Context,
            collateral_delta: u256,
            collateral_shares_delta: u256,
            debt_delta: u256,
            nominal_debt_delta: u256,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            // skip shutdown mode evaluation and updating the pairs collateral shares and nominal debt balances
            // if the pairs are the same
            let (from_shutdown_mode, to_shutdown_mode) = if (from_context.pool_id == to_context.pool_id
                && from_context.collateral_asset == to_context.collateral_asset
                && from_context.debt_asset == to_context.debt_asset) {
                let from_shutdown_mode = self.update_shutdown_status(ref from_context);
                (from_shutdown_mode, from_shutdown_mode)
            } else {
                // either the collateral asset or the debt asset has to match (also enforced by the singleton)
                assert!(
                    from_context.collateral_asset == to_context.collateral_asset
                        || from_context.debt_asset == to_context.debt_asset,
                    "asset-mismatch"
                );
                self
                    .update_pair(
                        ref from_context, i257_new(collateral_shares_delta, true), i257_new(nominal_debt_delta, true)
                    );
                self
                    .update_pair(
                        ref to_context, i257_new(collateral_shares_delta, false), i257_new(nominal_debt_delta, false)
                    );
                (self.update_shutdown_status(ref from_context), self.update_shutdown_status(ref to_context))
            };

            // if shutdown mode has been triggered then the 'from' position should have no debt and only
            // transfers within the same pairing are allowed
            if from_shutdown_mode != ShutdownMode::None || to_shutdown_mode != ShutdownMode::None {
                assert!(from_context.position.nominal_debt == 0, "shutdown-non-zero-debt");
                assert!(
                    from_context.collateral_asset == to_context.collateral_asset
                        && from_context.debt_asset == to_context.debt_asset,
                    "shutdown-pair-mismatch"
                );
            }

            // mint vTokens if collateral shares are transferred to the corresponding vToken pairing
            if to_context.debt_asset == Zeroable::zero() && to_context.user == get_contract_address() {
                assert!(from_context.collateral_asset == to_context.collateral_asset, "v-token-to-asset-mismatch");
                let mut tokenization = self.get_contract_mut();
                tokenization
                    .mint_or_burn_v_token(
                        to_context.pool_id,
                        to_context.collateral_asset,
                        caller,
                        i257_new(collateral_shares_delta, false)
                    );
            }

            // burn vTokens if collateral shares are transferred from the corresponding vToken pairing
            if from_context.debt_asset == Zeroable::zero() && from_context.user == get_contract_address() {
                assert!(from_context.collateral_asset == to_context.collateral_asset, "v-token-from-asset-mismatch");
                ISingletonDispatcher { contract_address: self.get_contract().singleton() }
                    .modify_delegation(from_context.pool_id, caller, false);
                let mut tokenization = self.get_contract_mut();
                tokenization
                    .mint_or_burn_v_token(
                        to_context.pool_id, to_context.collateral_asset, caller, i257_new(collateral_shares_delta, true)
                    );
            }

            true
        }

        /// Implements logic to execute before a position gets liquidated.
        /// Liquidations are only allowed in normal and recovery mode. The liquidator has to be specify how much
        /// debt to repay and the minimum amount of collateral to receive in exchange. The value of the collateral
        /// is discounted by the liquidation factor in comparison to the current price (according to the oracle).
        /// In an event where there's not enough collateral to cover the debt, the liquidation will result in bad debt.
        /// The bad debt is attributed to the pool and distributed amongst the lenders of the corresponding
        /// collateral asset. The liquidator receives all the collateral but only has to repay the proportioned
        /// debt value. 
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `data` - liquidation data (optional)
        /// * `caller` - address of the caller
        /// # Returns
        /// * `collateral` - amount of collateral to be removed
        /// * `debt` - amount of debt to be removed
        /// * `bad_debt` - amount of bad debt accrued during the liquidation
        fn before_liquidate_position(
            ref self: ComponentState<TContractState>,
            mut context: Context,
            mut data: Span<felt252>,
            caller: ContractAddress
        ) -> (u256, u256, u256) {
            // don't allow for liquidations if the pool is not in normal or recovery mode
            let shutdown_mode = self.update_shutdown_status(ref context);
            assert!(
                (shutdown_mode == ShutdownMode::None || shutdown_mode == ShutdownMode::Recovery)
                    && context.collateral_asset_price.is_valid
                    && context.debt_asset_price.is_valid,
                "emergency-mode"
            );

            let LiquidationData { min_collateral_to_receive, mut debt_to_repay } = Serde::deserialize(ref data)
                .expect('invalid-liquidation-data');

            // compute the collateral and debt value of the position
            let (collateral, mut collateral_value, debt, debt_value) = calculate_collateral_and_debt_value(
                context, context.position
            );

            // if the liquidation factor is not set, then set it to 100%
            let liquidation_config: LiquidationConfig = self
                .liquidation_configs
                .read((context.pool_id, context.collateral_asset, context.debt_asset));
            let liquidation_factor = if liquidation_config.liquidation_factor == 0 {
                SCALE
            } else {
                liquidation_config.liquidation_factor.into()
            };

            // limit debt to repay by the position's outstanding debt
            debt_to_repay = if debt_to_repay > debt {
                debt
            } else {
                debt_to_repay
            };

            // apply liquidation factor to debt value to get the collateral amount to release
            let collateral_value_to_receive = debt_to_repay
                * context.debt_asset_price.value
                / context.debt_asset_config.scale;
            let mut collateral_to_receive = (collateral_value_to_receive * SCALE / context.collateral_asset_price.value)
                * context.collateral_asset_config.scale
                / liquidation_factor;

            // limit collateral to receive by the position's remaining collateral balance
            collateral_to_receive = if collateral_to_receive > collateral {
                collateral
            } else {
                collateral_to_receive
            };

            // apply liquidation factor to collateral value
            collateral_value = collateral_value * liquidation_factor / SCALE;

            // check that a min. amount of collateral is released
            assert!(collateral_to_receive >= min_collateral_to_receive, "less-than-min-collateral");

            // account for bad debt if there isn't enough collateral to cover the debt
            let mut bad_debt = 0;
            if collateral_value < debt_value {
                // limit the bad debt by the outstanding collateral and debt values (in usd)
                if collateral_value < debt_to_repay * context.debt_asset_price.value / context.debt_asset_config.scale {
                    bad_debt = (debt_value - collateral_value)
                        * context.debt_asset_config.scale
                        / context.debt_asset_price.value;
                    debt_to_repay = debt;
                } else {
                    // derive the bad debt proportionally to the debt repaid
                    bad_debt = debt_to_repay * (debt_value - collateral_value) / collateral_value;
                    debt_to_repay = debt_to_repay + bad_debt;
                }
            }

            (collateral_to_receive, debt_to_repay, bad_debt)
        }

        /// Implements logic to execute after a position gets liquidated.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `collateral_shares_delta` - collateral shares balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `nominal_debt_delta` - nominal debt balance delta of the position
        /// * `bad_debt` - amount of bad debt accrued during the liquidation
        /// * `data` - liquidation data (optional)
        /// * `caller` - address of the caller
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
            caller: ContractAddress
        ) -> bool {
            self.update_pair(ref context, collateral_shares_delta, nominal_debt_delta);
            self.update_shutdown_status(ref context);
            true
        }
    }
}
