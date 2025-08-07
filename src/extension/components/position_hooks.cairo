use starknet::storage_access::StorePacking;
use vesu::packing::{SHIFT_128, into_u123, split_128};
use vesu::units::SCALE;

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
pub struct ShutdownConfig {
    pub recovery_period: u64, // [seconds]
    pub subscription_period: u64 // [seconds]
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
pub struct LiquidationConfig {
    pub liquidation_factor: u64 // [SCALE]
}

pub fn assert_liquidation_config(liquidation_config: LiquidationConfig) {
    assert!(liquidation_config.liquidation_factor.into() <= SCALE, "invalid-liquidation-config");
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct Pair {
    pub total_collateral_shares: u256, // packed as u128 [SCALE] 
    pub total_nominal_debt: u256 // packed as u123 [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde, Default, starknet::Store)]
pub enum ShutdownMode {
    #[default]
    None,
    Recovery,
    Subscription,
    Redemption,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct ShutdownStatus {
    pub shutdown_mode: ShutdownMode,
    pub violating: bool,
}

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
pub struct ShutdownState {
    // current set shutdown mode (overwrites the inferred shutdown mode)
    pub shutdown_mode: ShutdownMode,
    // timestamp at which the shutdown mode was last updated
    pub last_updated: u64,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct LiquidationData {
    pub min_collateral_to_receive: u256,
    pub debt_to_repay: u256,
}

impl PairPacking of StorePacking<Pair, felt252> {
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
pub mod position_hooks_component {
    use alexandria_math::i257::{I257Trait, i257};
    use core::num::traits::Zero;
    use openzeppelin::utils::math::{Rounding, u256_mul_div};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address};
    use vesu::common::{calculate_collateral_and_debt_value, calculate_debt, is_collateralized};
    use vesu::data_model::{Context, LTVConfig, Position, UnsignedAmount, assert_ltv_config};
    use vesu::extension::components::position_hooks::{
        LiquidationConfig, LiquidationData, Pair, ShutdownConfig, ShutdownMode, ShutdownState, ShutdownStatus,
        assert_liquidation_config,
    };
    use vesu::extension::default_extension_po_v2::{IDefaultExtensionCallback, ITokenizationCallback};
    use vesu::singleton_v2::{ISingletonV2Dispatcher, ISingletonV2DispatcherTrait};
    use vesu::units::SCALE;

    #[storage]
    pub struct Storage {
        // contains the shutdown configuration for each pool
        // pool_id -> shutdown configuration
        pub shutdown_configs: Map<felt252, ShutdownConfig>,
        // specifies the ltv configuration for each pair at which the recovery mode for a pool is triggered
        // (pool_id, collateral_asset, debt_asset) -> shutdown ltv configuration
        pub shutdown_ltv_configs: Map<(felt252, ContractAddress, ContractAddress), LTVConfig>,
        // contains the current shutdown mode for a pool
        // pool_id -> shutdown mode
        pub fixed_shutdown_mode: Map<felt252, ShutdownState>,
        // contains the liquidation configuration for each pair in a pool
        // (pool_id, collateral_asset, debt_asset) -> liquidation configuration
        pub liquidation_configs: Map<(felt252, ContractAddress, ContractAddress), LiquidationConfig>,
        // tracks the total collateral shares and the total nominal debt for each pair
        // (pool_id, collateral asset, debt asset) -> pair configuration
        pub pairs: Map<(felt252, ContractAddress, ContractAddress), Pair>,
        // tracks the debt caps for each asset
        pub debt_caps: Map<(felt252, ContractAddress, ContractAddress), u256>,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SetLiquidationConfig {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        liquidation_config: LiquidationConfig,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SetShutdownConfig {
        #[key]
        pool_id: felt252,
        shutdown_config: ShutdownConfig,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SetShutdownLTVConfig {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        shutdown_ltv_config: LTVConfig,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SetShutdownMode {
        #[key]
        pool_id: felt252,
        shutdown_mode: ShutdownMode,
        last_updated: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SetDebtCap {
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
    pub enum Event {
        SetLiquidationConfig: SetLiquidationConfig,
        SetShutdownConfig: SetShutdownConfig,
        SetShutdownLTVConfig: SetShutdownLTVConfig,
        SetShutdownMode: SetShutdownMode,
        SetDebtCap: SetDebtCap,
    }

    #[generate_trait]
    pub impl PositionHooksTrait<
        TContractState,
        +HasComponent<TContractState>,
        +IDefaultExtensionCallback<TContractState>,
        +ITokenizationCallback<TContractState>,
        +Drop<TContractState>,
    > of Trait<TContractState> {
        /// Checks if a pair is collateralized based on the current oracle prices and the shutdown ltv configuration.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// # Returns
        /// * `bool` - true if the pair is collateralized, false otherwise
        fn is_pair_collateralized(self: @ComponentState<TContractState>, ref context: Context) -> bool {
            let Pair {
                total_collateral_shares, total_nominal_debt,
            } = self.pairs.read((context.pool_id, context.collateral_asset, context.debt_asset));
            let (_, collateral_value, _, debt_value) = calculate_collateral_and_debt_value(
                context, Position { collateral_shares: total_collateral_shares, nominal_debt: total_nominal_debt },
            );
            let LTVConfig {
                max_ltv,
            } = self.shutdown_ltv_configs.read((context.pool_id, context.collateral_asset, context.debt_asset));
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
            debt_cap: u256,
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
            liquidation_config: LiquidationConfig,
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
                        },
                    },
                );

            self.emit(SetLiquidationConfig { pool_id, collateral_asset, debt_asset, liquidation_config });
        }

        /// Sets the shutdown configuration for a pool.
        /// # Arguments
        /// * `pool_id` - pool identifier
        /// * `shutdown_config` - shutdown configuration
        fn set_shutdown_config(
            ref self: ComponentState<TContractState>, pool_id: felt252, shutdown_config: ShutdownConfig,
        ) {
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
            // if pool is in either subscription period, redemption period, then return mode
            let ShutdownState { mut shutdown_mode, .. } = self.fixed_shutdown_mode.read(context.pool_id);

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

            // set shutdown mode to recovery if there is a violation and the shutdown mode is not set already
            if shutdown_mode == ShutdownMode::None && violating {
                shutdown_mode = ShutdownMode::Recovery;
            }

            ShutdownStatus { shutdown_mode, violating }
        }

        /// Transitions the pool into recovery mode if a pair is violating the constraints
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// # Returns
        /// * `shutdown_mode` - the shutdown mode of the pool
        fn update_shutdown_status(ref self: ComponentState<TContractState>, ref context: Context) -> ShutdownMode {
            let Context { pool_id, collateral_asset, collateral_asset_config, .. } = context;

            // check if the shutdown mode has been overwritten
            let ShutdownState { shutdown_mode, .. } = self.fixed_shutdown_mode.read(pool_id);

            if shutdown_mode == ShutdownMode::Redemption {
                // set max_utilization to 100% if it's not already set
                if collateral_asset_config.max_utilization != SCALE {
                    ISingletonV2Dispatcher { contract_address: self.get_contract().singleton() }
                        .set_asset_parameter(pool_id, collateral_asset, 'max_utilization', SCALE);
                }
            }

            // check if the shutdown mode has been set to a non-none value
            if shutdown_mode != ShutdownMode::None {
                return shutdown_mode;
            }

            let ShutdownStatus { shutdown_mode, violating } = self.shutdown_status(ref context);

            // if there is a current violation and no timestamp exists for the pair, then set the it (recovery)
            if violating {
                self
                    .fixed_shutdown_mode
                    .write(pool_id, ShutdownState { shutdown_mode, last_updated: get_block_timestamp() });
            }

            shutdown_mode
        }

        /// Sets the shutdown mode for a pool which overwrites the inferred shutdown mode.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `shutdown_mode` - shutdown mode
        fn set_shutdown_mode(
            ref self: ComponentState<TContractState>, pool_id: felt252, new_shutdown_mode: ShutdownMode,
        ) {
            let ShutdownState { shutdown_mode, last_updated, .. } = self.fixed_shutdown_mode.read(pool_id);

            // can only transition to recovery mode if the shutdown mode is in normal mode
            assert!(
                shutdown_mode != ShutdownMode::None || new_shutdown_mode == ShutdownMode::Recovery,
                "shutdown-mode-not-none",
            );
            // can only transition back to normal mode or subscription mode if the shutdown mode is in recovery mode
            assert!(
                shutdown_mode != ShutdownMode::Recovery
                    || (new_shutdown_mode == ShutdownMode::None || new_shutdown_mode == ShutdownMode::Subscription),
                "shutdown-mode-not-recovery",
            );
            // can only transition to redemption mode if the shutdown mode is in subscription mode
            assert!(
                shutdown_mode != ShutdownMode::Subscription || new_shutdown_mode == ShutdownMode::Redemption,
                "shutdown-mode-not-subscription",
            );
            // can not transition into any shutdown mode if the shutdown mode is in redemption mode
            assert!(shutdown_mode != ShutdownMode::Redemption, "shutdown-mode-in-redemption");

            let ShutdownConfig { recovery_period, subscription_period } = self.shutdown_configs.read(pool_id);

            // can only transition to subscription mode if the recovery period has passed
            assert!(
                new_shutdown_mode != ShutdownMode::Subscription || last_updated
                    + recovery_period < get_block_timestamp(),
                "shutdown-mode-recovery-period",
            );

            // can only transition to redemption mode if the subscription period has passed
            assert!(
                new_shutdown_mode != ShutdownMode::Redemption || last_updated
                    + subscription_period < get_block_timestamp(),
                "shutdown-mode-subscription-period",
            );

            let shutdown_state = ShutdownState {
                shutdown_mode: new_shutdown_mode, last_updated: get_block_timestamp(),
            };
            self.fixed_shutdown_mode.write(pool_id, shutdown_state);

            self.emit(SetShutdownMode { pool_id, shutdown_mode, last_updated: shutdown_state.last_updated });
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
            nominal_debt_delta: i257,
        ) {
            // skip updating the pairs if the debt asset is zero as the pair's ltv is always 100%
            if context.debt_asset == Zero::zero() {
                return;
            }

            // update the balances of the pair of the modified position
            let Pair {
                mut total_collateral_shares, mut total_nominal_debt,
            } = self.pairs.read((context.pool_id, context.collateral_asset, context.debt_asset));
            if collateral_shares_delta > Zero::zero() {
                total_collateral_shares = total_collateral_shares + collateral_shares_delta.abs();
            } else if collateral_shares_delta < Zero::zero() {
                total_collateral_shares = total_collateral_shares - collateral_shares_delta.abs();
            }
            if nominal_debt_delta > Zero::zero() {
                total_nominal_debt = total_nominal_debt + nominal_debt_delta.abs();
                let debt_cap = self.debt_caps.read((context.pool_id, context.collateral_asset, context.debt_asset));
                if debt_cap != 0 {
                    let total_debt = calculate_debt(
                        total_nominal_debt,
                        context.debt_asset_config.last_rate_accumulator,
                        context.debt_asset_config.scale,
                        true,
                    );
                    assert!(total_debt <= debt_cap, "debt-cap-exceeded");
                }
            } else if nominal_debt_delta < Zero::zero() {
                total_nominal_debt = total_nominal_debt - nominal_debt_delta.abs();
            }
            self
                .pairs
                .write(
                    (context.pool_id, context.collateral_asset, context.debt_asset),
                    Pair { total_collateral_shares, total_nominal_debt },
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
            caller: ContractAddress,
        ) -> bool {
            self.update_pair(ref context, collateral_shares_delta, nominal_debt_delta);

            let shutdown_mode = self.update_shutdown_status(ref context);

            // check invariants for collateral and debt amounts
            if shutdown_mode == ShutdownMode::Recovery {
                let decreasing_collateral = collateral_delta < Zero::zero();
                let increasing_debt = debt_delta > Zero::zero();
                assert!(!(decreasing_collateral || increasing_debt), "in-recovery");
            } else if shutdown_mode == ShutdownMode::Subscription {
                let modifying_collateral = collateral_delta != Zero::zero();
                let increasing_debt = debt_delta > Zero::zero();
                assert!(!(modifying_collateral || increasing_debt), "in-subscription");
            } else if shutdown_mode == ShutdownMode::Redemption {
                let increasing_collateral = collateral_delta > Zero::zero();
                let modifying_debt = debt_delta != Zero::zero();
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
            caller: ContractAddress,
        ) -> (UnsignedAmount, UnsignedAmount) {
            if from_context.debt_asset == Zero::zero() && from_context.user == get_contract_address() {
                ISingletonV2Dispatcher { contract_address: self.get_contract().singleton() }
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
            caller: ContractAddress,
        ) -> bool {
            // skip shutdown mode evaluation and updating the pairs collateral shares and nominal debt balances
            // if the pairs are the same
            let (from_shutdown_mode, to_shutdown_mode) = if (from_context.pool_id == to_context.pool_id
                && from_context.collateral_asset == to_context.collateral_asset
                && from_context.debt_asset == to_context.debt_asset) {
                let from_shutdown_mode = self.update_shutdown_status(ref from_context);
                (from_shutdown_mode, from_shutdown_mode)
            } else {
                // either the collateral asset or the debt asset has to match
                assert!(
                    from_context.collateral_asset == to_context.collateral_asset
                        || from_context.debt_asset == to_context.debt_asset,
                    "asset-mismatch",
                );
                self
                    .update_pair(
                        ref from_context,
                        I257Trait::new(collateral_shares_delta, true),
                        I257Trait::new(nominal_debt_delta, true),
                    );
                self
                    .update_pair(
                        ref to_context,
                        I257Trait::new(collateral_shares_delta, false),
                        I257Trait::new(nominal_debt_delta, false),
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
                    "shutdown-pair-mismatch",
                );
            }

            // mint vTokens if collateral shares are transferred to the corresponding vToken pairing
            if to_context.debt_asset == Zero::zero() && to_context.user == get_contract_address() {
                assert!(from_context.collateral_asset == to_context.collateral_asset, "v-token-to-asset-mismatch");
                let mut tokenization = self.get_contract_mut();
                tokenization
                    .mint_or_burn_v_token(
                        to_context.pool_id,
                        to_context.collateral_asset,
                        caller,
                        I257Trait::new(collateral_shares_delta, false),
                    );
            }

            // burn vTokens if collateral shares are transferred from the corresponding vToken pairing
            if from_context.debt_asset == Zero::zero() && from_context.user == get_contract_address() {
                assert!(from_context.collateral_asset == to_context.collateral_asset, "v-token-from-asset-mismatch");
                ISingletonV2Dispatcher { contract_address: self.get_contract().singleton() }
                    .modify_delegation(from_context.pool_id, caller, false);
                let mut tokenization = self.get_contract_mut();
                tokenization
                    .mint_or_burn_v_token(
                        to_context.pool_id,
                        to_context.collateral_asset,
                        caller,
                        I257Trait::new(collateral_shares_delta, true),
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
            caller: ContractAddress,
        ) -> (u256, u256, u256) {
            // don't allow for liquidations if the pool is not in normal or recovery mode
            let shutdown_mode = self.update_shutdown_status(ref context);
            assert!(
                (shutdown_mode == ShutdownMode::None || shutdown_mode == ShutdownMode::Recovery)
                    && context.collateral_asset_price.is_valid
                    && context.debt_asset_price.is_valid,
                "emergency-mode",
            );

            let LiquidationData {
                min_collateral_to_receive, mut debt_to_repay,
            } = Serde::deserialize(ref data).expect('invalid-liquidation-data');

            // compute the collateral and debt value of the position
            let (collateral, mut collateral_value, debt, debt_value) = calculate_collateral_and_debt_value(
                context, context.position,
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
            let collateral_value_to_receive = u256_mul_div(
                debt_to_repay, context.debt_asset_price.value, context.debt_asset_config.scale, Rounding::Floor,
            );
            let mut collateral_to_receive = u256_mul_div(
                u256_mul_div(collateral_value_to_receive, SCALE, context.collateral_asset_price.value, Rounding::Floor),
                context.collateral_asset_config.scale,
                liquidation_factor,
                Rounding::Floor,
            );

            // limit collateral to receive by the position's remaining collateral balance
            collateral_to_receive = if collateral_to_receive > collateral {
                collateral
            } else {
                collateral_to_receive
            };

            // apply liquidation factor to collateral value
            collateral_value = u256_mul_div(collateral_value, liquidation_factor, SCALE, Rounding::Floor);

            // check that a min. amount of collateral is released
            assert!(collateral_to_receive >= min_collateral_to_receive, "less-than-min-collateral");

            // account for bad debt if there isn't enough collateral to cover the debt
            let mut bad_debt = 0;
            if collateral_value < debt_value {
                // limit the bad debt by the outstanding collateral and debt values (in usd)
                if collateral_value < u256_mul_div(
                    debt_to_repay, context.debt_asset_price.value, context.debt_asset_config.scale, Rounding::Ceil,
                ) {
                    bad_debt =
                        u256_mul_div(
                            debt_value - collateral_value,
                            context.debt_asset_config.scale,
                            context.debt_asset_price.value,
                            Rounding::Floor,
                        );
                    debt_to_repay = debt;
                } else {
                    // derive the bad debt proportionally to the debt repaid
                    bad_debt =
                        u256_mul_div(debt_to_repay, debt_value - collateral_value, collateral_value, Rounding::Ceil);
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
            caller: ContractAddress,
        ) -> bool {
            self.update_pair(ref context, collateral_shares_delta, nominal_debt_delta);
            self.update_shutdown_status(ref context);
            true
        }
    }
}
