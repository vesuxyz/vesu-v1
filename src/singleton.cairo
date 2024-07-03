use alexandria_math::i257::i257;
use starknet::{ContractAddress};
use vesu::{
    data_model::{
        Context, AssetConfig, Position, LTVParams, LTVConfig, assert_ltv_config, Amount, AssetParams,
        AmountDenomination, UpdatePositionResponse, ModifyPositionParams, LiquidatePositionParams,
        TransferPositionParams
    },
};

#[starknet::interface]
trait IFlashloanReceiver<TContractState> {
    fn on_flash_loan(
        ref self: TContractState, sender: ContractAddress, asset: ContractAddress, amount: u256, data: Span<felt252>
    );
}

#[starknet::interface]
trait ISingleton<TContractState> {
    fn creator_nonce(self: @TContractState, creator: ContractAddress) -> felt252;
    fn extension(self: @TContractState, pool_id: felt252) -> ContractAddress;
    fn asset_config_unsafe(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> (AssetConfig, u256);
    fn asset_config(ref self: TContractState, pool_id: felt252, asset: ContractAddress) -> (AssetConfig, u256);
    fn ltv_config(
        self: @TContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> LTVConfig;
    fn position(
        self: @TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress
    ) -> (Position, u256, u256);
    fn rate_accumulator(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> u256;
    fn utilization(self: @TContractState, pool_id: felt252, asset: ContractAddress) -> u256;
    fn delegation(
        ref self: TContractState, pool_id: felt252, delegator: ContractAddress, delegatee: ContractAddress
    ) -> bool;
    fn calculate_pool_id(self: @TContractState, caller_address: ContractAddress, nonce: felt252) -> felt252;
    fn calculate_debt(self: @TContractState, nominal_debt: i257, rate_accumulator: u256, asset_scale: u256) -> u256;
    fn calculate_nominal_debt(self: @TContractState, debt: i257, rate_accumulator: u256, asset_scale: u256) -> u256;
    fn calculate_collateral_shares(
        self: @TContractState, pool_id: felt252, asset: ContractAddress, collateral: i257
    ) -> u256;
    fn calculate_collateral(
        self: @TContractState, pool_id: felt252, asset: ContractAddress, collateral_shares: i257
    ) -> u256;
    fn deconstruct_collateral_amount(
        self: @TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
        collateral: Amount,
    ) -> (i257, i257);
    fn deconstruct_debt_amount(
        self: @TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
        debt: Amount,
    ) -> (i257, i257);
    fn context_unsafe(
        self: @TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
    ) -> Context;
    fn context(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
    ) -> Context;
    fn create_pool(
        ref self: TContractState,
        asset_params: Span<AssetParams>,
        ltv_params: Span<LTVParams>,
        extension: ContractAddress
    ) -> felt252;
    fn modify_position(ref self: TContractState, params: ModifyPositionParams) -> UpdatePositionResponse;
    fn transfer_position(ref self: TContractState, params: TransferPositionParams);
    fn liquidate_position(ref self: TContractState, params: LiquidatePositionParams) -> UpdatePositionResponse;
    fn flash_loan(
        ref self: TContractState,
        receiver: ContractAddress,
        asset: ContractAddress,
        amount: u256,
        is_legacy: bool,
        data: Span<felt252>
    );
    fn modify_delegation(ref self: TContractState, pool_id: felt252, delegatee: ContractAddress, delegation: bool);
    fn donate_to_reserve(ref self: TContractState, pool_id: felt252, asset: ContractAddress, amount: u256);
    fn retrieve_from_reserve(
        ref self: TContractState, pool_id: felt252, asset: ContractAddress, receiver: ContractAddress, amount: u256
    );
    fn set_asset_config(ref self: TContractState, pool_id: felt252, params: AssetParams);
    fn set_ltv_config(
        ref self: TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        ltv_config: LTVConfig
    );
    fn set_asset_parameter(
        ref self: TContractState, pool_id: felt252, asset: ContractAddress, parameter: felt252, value: u256
    );
    fn set_extension(ref self: TContractState, pool_id: felt252, extension: ContractAddress);
}

#[starknet::contract]
mod Singleton {
    use alexandria_math::i257::{i257, i257_new};
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use vesu::{
        math::pow_10, units::SCALE,
        common::{
            calculate_nominal_debt, calculate_debt, calculate_utilization, calculate_collateral_shares,
            calculate_collateral, deconstruct_collateral_amount, deconstruct_debt_amount, is_collateralized,
            apply_position_update_to_context, calculate_collateral_and_debt_value, calculate_fee_shares
        },
        data_model::{
            Position, AssetConfig, AmountType, AmountDenomination, Amount, AssetPrice, AssetParams, LTVParams, Context,
            assert_config_exists, LTVConfig, assert_ltv_config, assert_asset_config, UpdatePositionResponse,
            ModifyPositionParams, LiquidatePositionParams, TransferPositionParams
        },
        packing::{PositionPacking, AssetConfigPacking, assert_storable_asset_config},
        singleton::{ISingleton, IFlashloanReceiverDispatcher, IFlashloanReceiverDispatcherTrait},
        extension::interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
        vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait}
    };

    #[storage]
    struct Storage {
        // tracks a nonce for each creator of a pool to deterministically derive the pool_id from it
        // creator -> nonce
        creator_nonce: LegacyMap::<ContractAddress, felt252>,
        // tracks the address of the extension contract for each pool
        // pool_id -> extension
        extensions: LegacyMap::<felt252, ContractAddress>,
        // tracks the configuration / state of each asset in each pool
        // (pool_id, asset) -> asset configuration
        asset_configs: LegacyMap::<(felt252, ContractAddress), AssetConfig>,
        // tracks the max. allowed loan-to-value ratio for each asset pairing in each pool
        // (pool_id, collateral_asset, debt_asset) -> ltv configuration 
        ltv_configs: LegacyMap::<(felt252, ContractAddress, ContractAddress), LTVConfig>,
        // tracks the state of each position in each pool
        // (pool_id, collateral_asset, debt_asset, user) -> position
        positions: LegacyMap::<(felt252, ContractAddress, ContractAddress, ContractAddress), Position>,
        // tracks the delegation status for each delegator to a delegatee for a specific pool
        // (pool_id, delegator, delegatee) -> delegation
        delegations: LegacyMap::<(felt252, ContractAddress, ContractAddress), bool>,
        // tracks the reentrancy lock status to prohibit reentrancy when loading the context or the asset config
        lock: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct CreatePool {
        #[key]
        pool_id: felt252,
        #[key]
        extension: ContractAddress,
        #[key]
        creator: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct ModifyPosition {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        #[key]
        user: ContractAddress,
        collateral_delta: i257,
        collateral_shares_delta: i257,
        debt_delta: i257,
        nominal_debt_delta: i257
    }

    #[derive(Drop, starknet::Event)]
    struct TransferPosition {
        #[key]
        pool_id: felt252,
        #[key]
        from_collateral_asset: ContractAddress,
        #[key]
        from_debt_asset: ContractAddress,
        #[key]
        to_collateral_asset: ContractAddress,
        #[key]
        to_debt_asset: ContractAddress,
        #[key]
        from_user: ContractAddress,
        #[key]
        to_user: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct LiquidatePosition {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        #[key]
        user: ContractAddress,
        #[key]
        liquidator: ContractAddress,
        collateral_delta: i257,
        collateral_shares_delta: i257,
        debt_delta: i257,
        nominal_debt_delta: i257,
        bad_debt: u256
    }

    #[derive(Drop, starknet::Event)]
    struct AccrueFees {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        #[key]
        recipient: ContractAddress,
        collateral_asset_fee_shares: u256,
        debt_asset_fee_shares: u256
    }

    #[derive(Drop, starknet::Event)]
    struct UpdateContext {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        collateral_asset_config: AssetConfig,
        debt_asset_config: AssetConfig,
        collateral_asset_price: AssetPrice,
        debt_asset_price: AssetPrice,
    }

    #[derive(Drop, starknet::Event)]
    struct Flashloan {
        #[key]
        sender: ContractAddress,
        #[key]
        receiver: ContractAddress,
        #[key]
        asset: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct ModifyDelegation {
        #[key]
        pool_id: felt252,
        #[key]
        delegator: ContractAddress,
        #[key]
        delegatee: ContractAddress,
        delegation: bool
    }

    #[derive(Drop, starknet::Event)]
    struct Donate {
        #[key]
        pool_id: felt252,
        #[key]
        asset: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct RetrieveReserve {
        #[key]
        pool_id: felt252,
        #[key]
        asset: ContractAddress,
        #[key]
        receiver: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct SetLTVConfig {
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
        #[key]
        debt_asset: ContractAddress,
        ltv_config: LTVConfig
    }

    #[derive(Drop, starknet::Event)]
    struct SetAssetConfig {
        #[key]
        pool_id: felt252,
        #[key]
        asset: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct SetAssetParameter {
        #[key]
        pool_id: felt252,
        #[key]
        asset: ContractAddress,
        #[key]
        parameter: felt252,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct SetExtension {
        #[key]
        pool_id: felt252,
        #[key]
        extension: ContractAddress
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CreatePool: CreatePool,
        ModifyPosition: ModifyPosition,
        TransferPosition: TransferPosition,
        LiquidatePosition: LiquidatePosition,
        AccrueFees: AccrueFees,
        UpdateContext: UpdateContext,
        Flashloan: Flashloan,
        ModifyDelegation: ModifyDelegation,
        Donate: Donate,
        RetrieveReserve: RetrieveReserve,
        SetLTVConfig: SetLTVConfig,
        SetAssetConfig: SetAssetConfig,
        SetAssetParameter: SetAssetParameter,
        SetExtension: SetExtension,
    }

    /// Computes the new rate accumulator and the interest rate at full utilization for a given asset in a pool
    /// # Arguments
    /// * `pool_id` - id of the pool
    /// * `extension` - address of the pools extension contract
    /// * `asset` - address of the asset
    /// # Returns
    /// * `rate_accumulator` - new rate accumulator [SCALE]
    /// * `full_utilization_rate` - new interest rate at full utilization [SCALE]
    fn rate_accumulator(
        pool_id: felt252, extension: ContractAddress, asset: ContractAddress, mut asset_config: AssetConfig
    ) -> AssetConfig {
        let AssetConfig { total_nominal_debt, scale, .. } = asset_config;
        let AssetConfig { last_rate_accumulator, last_full_utilization_rate, last_updated, .. } = asset_config;
        let total_debt = calculate_debt(total_nominal_debt, last_rate_accumulator, scale, false);
        // calculate utilization based on previous rate accumulator
        let utilization = calculate_utilization(asset_config.reserve, total_debt);
        // calculate the new rate accumulator
        let (rate_accumulator, full_utilization_rate) = IExtensionDispatcher { contract_address: extension }
            .rate_accumulator(
                pool_id, asset, utilization, last_updated, last_rate_accumulator, last_full_utilization_rate,
            );

        asset_config.last_rate_accumulator = rate_accumulator;
        asset_config.last_full_utilization_rate = full_utilization_rate;
        asset_config.last_updated = get_block_timestamp();

        asset_config
    }

    /// Computes the current utilization of an asset in a pool
    /// # Arguments
    /// * `asset_config` - asset configuration
    /// # Returns
    /// * `utilization` - current utilization [SCALE]
    fn utilization(asset_config: AssetConfig) -> u256 {
        let total_debt = calculate_debt(
            asset_config.total_nominal_debt, asset_config.last_rate_accumulator, asset_config.scale, false
        );
        calculate_utilization(asset_config.reserve, total_debt)
    }

    /// Helper method for transferring an amount of an asset from one address to another. Reverts if the transfer fails.
    /// # Arguments
    /// * `asset` - address of the asset
    /// * `sender` - address of the sender of the assets
    /// * `to` - address of the receiver of the assets
    /// * `amount` - amount of assets to transfer [asset scale]
    /// * `is_legacy` - whether the asset is a legacy ERC20 (only supporting camelCase instead of snake_case)
    fn transfer_asset(
        asset: ContractAddress, sender: ContractAddress, to: ContractAddress, amount: u256, is_legacy: bool
    ) {
        let erc20 = IERC20Dispatcher { contract_address: asset };
        if sender == get_contract_address() {
            assert!(erc20.transfer(to, amount), "transfer-failed");
        } else if is_legacy {
            assert!(erc20.transferFrom(sender, to, amount), "transferFrom-failed");
        } else {
            assert!(erc20.transfer_from(sender, to, amount), "transfer-from-failed");
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// Asserts that the delegatee has the delegate of the delegator for a specific pool
        fn assert_ownership(
            ref self: ContractState, pool_id: felt252, extension: ContractAddress, delegator: ContractAddress
        ) {
            let has_delegation = self.delegations.read((pool_id, delegator, get_caller_address()));
            assert!(
                delegator == get_caller_address() || extension == get_caller_address() || has_delegation,
                "no-delegation"
            );
        }

        /// Asserts that the current utilization of an asset is below the max. allowed utilization
        fn assert_max_utilization(ref self: ContractState, asset_config: AssetConfig) {
            assert!(utilization(asset_config) <= asset_config.max_utilization, "utilization-exceeded")
        }

        /// Asserts that the collateralization of a position is not above the max. loan-to-value ratio
        fn assert_collateralization(
            ref self: ContractState, collateral_value: u256, debt_value: u256, max_ltv_ratio: u256
        ) {
            assert!(is_collateralized(collateral_value, debt_value, max_ltv_ratio), "not-collateralized");
        }

        /// Asserts invariants a position has to fulfill at all times (excluding liquidations)
        fn assert_position_invariants(
            ref self: ContractState, context: Context, collateral_delta: i257, debt_delta: i257
        ) {
            if collateral_delta < Zeroable::zero() || debt_delta > Zeroable::zero() {
                // position is collateralized
                let (_, collateral_value, _, debt_value) = calculate_collateral_and_debt_value(
                    context, context.position
                );
                self.assert_collateralization(collateral_value, debt_value, context.max_ltv.into());
                // caller owns the position or has a delegate for modifying it
                self.assert_ownership(context.pool_id, context.extension, context.user);
                if collateral_delta < Zeroable::zero() {
                    // max. utilization of the collateral is not exceed
                    self.assert_max_utilization(context.collateral_asset_config);
                }
                if debt_delta > Zeroable::zero() {
                    // max. utilization of the collateral is not exceed
                    self.assert_max_utilization(context.debt_asset_config);
                }
            }
        }

        /// Sets the pool's extension address.
        fn _set_extension(ref self: ContractState, pool_id: felt252, extension: ContractAddress) {
            assert!(extension.is_non_zero(), "extension-is-zero");

            self.extensions.write(pool_id, extension);

            self.emit(SetExtension { pool_id, extension });
        }

        /// Settles all intermediate outstanding collateral and debt deltas for a position / user
        fn settle_position(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            collateral_delta: i257,
            debt_asset: ContractAddress,
            debt_delta: i257,
            bad_debt: u256
        ) {
            let (contract, caller) = (get_contract_address(), get_caller_address());

            if collateral_delta < Zeroable::zero() {
                let (asset_config, _) = self.asset_config(pool_id, collateral_asset);
                transfer_asset(collateral_asset, contract, caller, collateral_delta.abs, asset_config.is_legacy);
            } else if collateral_delta > Zeroable::zero() {
                let (asset_config, _) = self.asset_config(pool_id, collateral_asset);
                transfer_asset(collateral_asset, caller, contract, collateral_delta.abs, asset_config.is_legacy);
            }

            if debt_delta < Zeroable::zero() {
                let (asset_config, _) = self.asset_config(pool_id, debt_asset);
                transfer_asset(debt_asset, caller, contract, debt_delta.abs - bad_debt, asset_config.is_legacy);
            } else if debt_delta > Zeroable::zero() {
                let (asset_config, _) = self.asset_config(pool_id, debt_asset);
                transfer_asset(debt_asset, contract, caller, debt_delta.abs, asset_config.is_legacy);
            }
        }

        /// Updates the state of a position and the corresponding collateral and debt asset
        fn update_position(
            ref self: ContractState, ref context: Context, collateral: Amount, debt: Amount, bad_debt: u256
        ) -> UpdatePositionResponse {
            // apply the position modification to the context
            let (collateral_delta, mut collateral_shares_delta, debt_delta, nominal_debt_delta) =
                apply_position_update_to_context(
                ref context, collateral, debt, bad_debt
            );

            let Context { pool_id, collateral_asset, debt_asset, user, .. } = context;

            // charge the inflation fee for the first depositor for that asset in the pool
            let inflation_fee = if context.collateral_asset_config.total_collateral_shares == 0
                && !collateral_shares_delta.is_negative {
                let inflation_fee = 1000;
                self
                    .positions
                    .write(
                        (pool_id, collateral_asset, debt_asset, Zeroable::zero()),
                        Position { collateral_shares: inflation_fee, nominal_debt: 0 }
                    );
                context.position.collateral_shares -= inflation_fee;
                inflation_fee
            } else {
                0
            };

            // store updated context
            self.positions.write((pool_id, collateral_asset, debt_asset, user), context.position);
            self.asset_configs.write((pool_id, collateral_asset), context.collateral_asset_config);
            self.asset_configs.write((pool_id, debt_asset), context.debt_asset_config);

            self
                .emit(
                    UpdateContext {
                        pool_id,
                        collateral_asset,
                        debt_asset,
                        collateral_asset_config: context.collateral_asset_config,
                        debt_asset_config: context.debt_asset_config,
                        collateral_asset_price: context.collateral_asset_price,
                        debt_asset_price: context.debt_asset_price,
                    }
                );

            // mint fee shares to the recipient
            if context.collateral_asset_fee_shares != 0 {
                let mut position = self
                    .positions
                    .read((pool_id, collateral_asset, Zeroable::zero(), context.extension));
                position.collateral_shares += context.collateral_asset_fee_shares;
                self.positions.write((pool_id, collateral_asset, Zeroable::zero(), context.extension), position);
            }
            if context.debt_asset_fee_shares != 0 {
                let mut position = self.positions.read((pool_id, debt_asset, Zeroable::zero(), context.extension));
                position.collateral_shares += context.debt_asset_fee_shares;
                self.positions.write((pool_id, debt_asset, Zeroable::zero(), context.extension), position);
            }

            self
                .emit(
                    AccrueFees {
                        pool_id,
                        collateral_asset,
                        debt_asset,
                        recipient: context.extension,
                        collateral_asset_fee_shares: context.collateral_asset_fee_shares,
                        debt_asset_fee_shares: context.debt_asset_fee_shares
                    }
                );

            let (_, collateral_value, _, debt_value) = calculate_collateral_and_debt_value(context, context.position);

            // verify invariants:
            // collateral shares delta has to be non-zero if the collateral delta is non-zero
            assert!(
                collateral_delta.abs == 0
                    && collateral_shares_delta.abs == 0 || collateral_delta.abs != 0
                    && collateral_shares_delta.abs != 0,
                "zero-collateral"
            );
            // nominal debt delta has to be non-zero if the debt delta is non-zero
            assert!(
                debt_delta.abs == 0
                    && nominal_debt_delta.abs == 0 || debt_delta.abs != 0
                    && nominal_debt_delta.abs != 0,
                "zero-debt"
            );

            if collateral_delta.is_non_zero() {
                // value of the collateral is either zero or above the floor
                assert!(
                    collateral_value == 0 || collateral_value > context.collateral_asset_config.floor,
                    "dusty-collateral-balance"
                );
            }
            if debt_delta.is_non_zero() {
                // value of the outstanding debt is either zero or above the floor
                assert!(debt_value == 0 || debt_value > context.debt_asset_config.floor, "dusty-debt-balance");
            }

            // deduct inflation fee from the collateral shares delta
            assert!(collateral_shares_delta.abs >= inflation_fee, "inflation-fee-gt-collateral-shares-delta");
            collateral_shares_delta =
                i257_new(collateral_shares_delta.abs - inflation_fee, collateral_shares_delta.is_negative);

            UpdatePositionResponse {
                collateral_delta, collateral_shares_delta, debt_delta, nominal_debt_delta, bad_debt
            }
        }
    }

    #[abi(embed_v0)]
    impl SingletonImpl of super::ISingleton<ContractState> {
        /// Returns the nonce of the creator of the previously created pool
        /// # Arguments
        /// * `creator` - address of the pool creator
        /// # Returns
        /// * `nonce` - nonce of the creator
        fn creator_nonce(self: @ContractState, creator: ContractAddress) -> felt252 {
            self.creator_nonce.read(creator)
        }

        /// Returns the pool's extension address
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// # Returns
        /// * `extension` - address of the extension contract
        fn extension(self: @ContractState, pool_id: felt252) -> ContractAddress {
            self.extensions.read(pool_id)
        }

        /// Returns the configuration / state of an asset for a given pool
        /// This method does not prevent reentrancy which may result in asset_config being out of date.
        /// For contract to contract interactions asset_config() should be used instead.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `asset_config` - asset configuration
        /// * `fee_shares` - accrued fee shares minted to the fee recipient
        fn asset_config_unsafe(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> (AssetConfig, u256) {
            let extension = self.extensions.read(pool_id);
            assert!(extension.is_non_zero(), "unknown-pool");

            let mut asset_config = self.asset_configs.read((pool_id, asset));
            let mut fee_shares = 0;

            if asset_config.last_updated != get_block_timestamp() && asset != Zeroable::zero() {
                let new_asset_config = rate_accumulator(pool_id, extension, asset, asset_config);
                fee_shares = calculate_fee_shares(asset_config, new_asset_config.last_rate_accumulator);
                asset_config = new_asset_config;
                asset_config.total_collateral_shares += fee_shares;
            }

            (asset_config, fee_shares)
        }

        /// Wrapper around asset_config() that prevents reentrancy
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `asset_config` - asset configuration
        /// * `fee_shares` - accrued fee shares minted to the fee recipient
        fn asset_config(ref self: ContractState, pool_id: felt252, asset: ContractAddress) -> (AssetConfig, u256) {
            assert!(!self.lock.read(), "asset-config-reentrancy");
            self.lock.write(true);
            let (asset_config, fee_shares) = self.asset_config_unsafe(pool_id, asset);
            self.lock.write(false);
            (asset_config, fee_shares)
        }

        /// Returns the loan-to-value configuration between two assets (pair) in the pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `ltv_config` - ltv configuration
        fn ltv_config(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> LTVConfig {
            self.ltv_configs.read((pool_id, collateral_asset, debt_asset))
        }

        /// Returns the current state of a position
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `user` - address of the position's owner
        /// # Returns
        /// * `position` - position state
        /// * `collateral` - amount of collateral (computed from position.collateral_shares) [asset scale]
        /// * `collateral_value` - value of the collateral [SCALE]
        /// * `debt` - amount of debt (computed from position.nominal_debt) [asset scale]
        /// * `debt_value` - value of the debt [SCALE]
        fn position(
            self: @ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            user: ContractAddress
        ) -> (Position, u256, u256) {
            let context = self.context_unsafe(pool_id, collateral_asset, debt_asset, user);
            let (collateral, _, debt, _) = calculate_collateral_and_debt_value(context, context.position);
            (context.position, collateral, debt)
        }

        /// Calculates the current (using the current block's timestamp) rate accumulator for a given asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `rate_accumulator` - computed rate accumulator [SCALE]
        fn rate_accumulator(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> u256 {
            let (asset_config, _) = self.asset_config_unsafe(pool_id, asset);
            asset_config.last_rate_accumulator
        }

        /// Calculates the current utilization of an asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `utilization` - computed utilization [SCALE]
        fn utilization(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> u256 {
            let (asset_config, _) = self.asset_config_unsafe(pool_id, asset);
            utilization(asset_config)
        }

        /// Returns the delegation status of a delegator to a delegatee for a specific pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `delegator` - address of the delegator
        /// * `delegatee` - address of the delegatee
        /// # Returns
        /// * `delegation` - delegation status (true = delegate, false = undelegate)
        fn delegation(
            ref self: ContractState, pool_id: felt252, delegator: ContractAddress, delegatee: ContractAddress
        ) -> bool {
            self.delegations.read((pool_id, delegator, delegatee))
        }

        /// Derives the pool_id for a given creator and nonce
        /// # Arguments
        /// * `caller_address` - address of the creator
        /// * `nonce` - nonce of the creator (creator_nonce() + 1 to derive the pool_id of the next pool)
        /// # Returns
        /// * `pool_id` - id of the pool
        fn calculate_pool_id(self: @ContractState, caller_address: ContractAddress, nonce: felt252) -> felt252 {
            let (s0, _, _) = poseidon::hades_permutation(caller_address.into(), nonce, 2);
            s0
        }

        /// Calculates the debt for a given amount of nominal debt, the current rate accumulator and debt asset's scale
        /// # Arguments
        /// * `nominal_debt` - amount of nominal debt [asset scale]
        /// * `rate_accumulator` - current rate accumulator [SCALE]
        /// * `asset_scale` - debt asset's scale
        /// # Returns
        /// * `debt` - computed debt [asset scale]
        fn calculate_debt(self: @ContractState, nominal_debt: i257, rate_accumulator: u256, asset_scale: u256) -> u256 {
            calculate_debt(nominal_debt.abs, rate_accumulator, asset_scale, nominal_debt.is_negative)
        }

        /// Calculates the nominal debt for a given amount of debt, the current rate accumulator and debt asset's scale
        /// # Arguments
        /// * `debt` - amount of debt [asset scale]
        /// * `rate_accumulator` - current rate accumulator [SCALE]
        /// * `asset_scale` - debt asset's scale
        /// # Returns
        /// * `nominal_debt` - computed nominal debt [asset scale]
        fn calculate_nominal_debt(self: @ContractState, debt: i257, rate_accumulator: u256, asset_scale: u256) -> u256 {
            calculate_nominal_debt(debt.abs, rate_accumulator, asset_scale, !debt.is_negative)
        }

        /// Calculates the number of collateral shares (that would be e.g. minted) for a given amount of collateral assets
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `collateral` - amount of collateral [asset scale]
        /// # Returns
        /// * `collateral_shares` - computed collateral shares [SCALE]
        fn calculate_collateral_shares(
            self: @ContractState, pool_id: felt252, asset: ContractAddress, collateral: i257
        ) -> u256 {
            let (asset_config, _) = self.asset_config_unsafe(pool_id, asset);
            calculate_collateral_shares(collateral.abs, asset_config, collateral.is_negative)
        }

        /// Calculates the amount of collateral assets (that can e.g. be redeemed)  for a given amount of collateral shares
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `collateral_shares` - amount of collateral shares
        /// # Returns
        /// * `collateral` - computed collateral [asset scale]
        fn calculate_collateral(
            self: @ContractState, pool_id: felt252, asset: ContractAddress, collateral_shares: i257
        ) -> u256 {
            let (asset_config, _) = self.asset_config_unsafe(pool_id, asset);
            calculate_collateral(collateral_shares.abs, asset_config, !collateral_shares.is_negative)
        }

        /// Deconstructs the collateral amount into collateral delta, collateral shares delta and it's sign
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `user` - address of the position's owner
        /// * `collateral` - amount of collateral
        /// # Returns
        /// * `collateral_delta` - computed collateral delta [asset scale]
        /// * `collateral_shares_delta` - computed collateral shares delta [SCALE]
        fn deconstruct_collateral_amount(
            self: @ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            user: ContractAddress,
            collateral: Amount,
        ) -> (i257, i257) {
            let context = self.context_unsafe(pool_id, collateral_asset, debt_asset, user);
            deconstruct_collateral_amount(collateral, context.position, context.collateral_asset_config)
        }

        /// Deconstructs the debt amount into debt delta, nominal debt delta and it's sign
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `user` - address of the position's owner
        /// * `debt` - amount of debt
        /// # Returns
        /// * `debt_delta` - computed debt delta [asset scale]
        /// * `nominal_debt_delta` - computed nominal debt delta [SCALE]
        fn deconstruct_debt_amount(
            self: @ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            user: ContractAddress,
            debt: Amount,
        ) -> (i257, i257) {
            let context = self.context_unsafe(pool_id, collateral_asset, debt_asset, user);
            deconstruct_debt_amount(
                debt, context.position, context.debt_asset_config.last_rate_accumulator, context.debt_asset_config.scale
            )
        }

        /// Loads the contextual state for a given user. This includes the pools extension address, the state of the
        /// collateral and debt assets, loan-to-value configurations and the state of the position.
        /// This method does not prevent reentrancy which may result in context being out of date.
        /// For contract to contract interactions context() should be used instead.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `user` - address of the position's owner
        /// # Returns
        /// * `context` - contextual state
        fn context_unsafe(
            self: @ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            user: ContractAddress,
        ) -> Context {
            assert!(collateral_asset != debt_asset, "identical-assets");

            let extension = IExtensionDispatcher { contract_address: self.extensions.read(pool_id) };
            assert!(extension.contract_address.is_non_zero(), "unknown-pool");

            let (collateral_asset_config, mut collateral_asset_fee_shares) = self
                .asset_config_unsafe(pool_id, collateral_asset);
            let (debt_asset_config, mut debt_asset_fee_shares) = self.asset_config_unsafe(pool_id, debt_asset);

            let mut context = Context {
                pool_id,
                extension: extension.contract_address,
                collateral_asset,
                debt_asset,
                collateral_asset_config: collateral_asset_config,
                debt_asset_config: debt_asset_config,
                collateral_asset_price: if collateral_asset == Zeroable::zero() {
                    AssetPrice { value: 0, is_valid: true }
                } else {
                    extension.price(pool_id, collateral_asset)
                },
                debt_asset_price: if debt_asset == Zeroable::zero() {
                    AssetPrice { value: 0, is_valid: true }
                } else {
                    extension.price(pool_id, debt_asset)
                },
                collateral_asset_fee_shares: collateral_asset_fee_shares,
                debt_asset_fee_shares: debt_asset_fee_shares,
                max_ltv: self.ltv_configs.read((pool_id, collateral_asset, debt_asset)).max_ltv,
                user,
                position: self.positions.read((pool_id, collateral_asset, debt_asset, user)),
            };

            context
        }

        /// Wrapper around context() that prevents reentrancy
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `user` - address of the position's owner
        /// # Returns
        /// * `context` - contextual state
        fn context(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            user: ContractAddress,
        ) -> Context {
            assert!(!self.lock.read(), "context-reentrancy");
            self.lock.write(true);
            let context = self.context_unsafe(pool_id, collateral_asset, debt_asset, user);
            self.lock.write(false);
            context
        }

        /// Creates a new pool
        /// # Arguments
        /// * `asset_params` - array of asset parameters
        /// * `ltv_params` - array of loan-to-value parameters
        /// * `extension` - address of the extension contract
        /// # Returns
        /// * `pool_id` - id of the pool
        fn create_pool(
            ref self: ContractState,
            asset_params: Span<AssetParams>,
            mut ltv_params: Span<LTVParams>,
            extension: ContractAddress
        ) -> felt252 {
            // derive pool id from the address of the creator and the creator's nonce
            let mut nonce = self.creator_nonce.read(get_caller_address());
            nonce += 1;
            self.creator_nonce.write(get_caller_address(), nonce);
            let pool_id = self.calculate_pool_id(get_caller_address(), nonce);

            // link the extension to the pool
            self._set_extension(pool_id, extension);

            // store all asset configurations
            let mut asset_params_copy = asset_params;
            while !asset_params_copy
                .is_empty() {
                    let params = *asset_params_copy.pop_front().unwrap();
                    self.set_asset_config(pool_id, params);
                };

            // store all loan-to-value configurations for each asset pair
            while !ltv_params
                .is_empty() {
                    let params = *ltv_params.pop_front().unwrap();
                    assert!(params.collateral_asset_index != params.debt_asset_index, "identical-assets");
                    let collateral_asset = *asset_params.at(params.collateral_asset_index).asset;
                    let debt_asset = *asset_params.at(params.debt_asset_index).asset;
                    self.set_ltv_config(pool_id, collateral_asset, debt_asset, LTVConfig { max_ltv: params.max_ltv });
                };

            self.emit(CreatePool { pool_id, extension, creator: get_caller_address() });

            pool_id
        }

        /// Adjusts a positions collateral and debt balances
        /// # Arguments
        /// * `params` - see ModifyPositionParams
        /// # Returns
        /// * `response` - see UpdatePositionResponse
        fn modify_position(ref self: ContractState, params: ModifyPositionParams) -> UpdatePositionResponse {
            let ModifyPositionParams { pool_id, collateral_asset, debt_asset, user, collateral, debt, data } = params;

            let context = self.context(pool_id, collateral_asset, debt_asset, user);

            // call before-hook of the extension
            let extension = IExtensionDispatcher { contract_address: context.extension };
            let (collateral, debt) = extension
                .before_modify_position(context, collateral, debt, data, get_caller_address());

            // reload context since the storage might have changed by a reentered call
            let mut context = self.context(pool_id, collateral_asset, debt_asset, user);

            // update the position
            let response = self.update_position(ref context, collateral, debt, 0);
            let UpdatePositionResponse { collateral_delta,
            collateral_shares_delta,
            debt_delta,
            nominal_debt_delta,
            .. } =
                response;

            // verify invariants
            self.assert_position_invariants(context, collateral_delta, debt_delta);

            // call after-hook of the extension (assets are not settled yet, only the internal state has been updated)
            assert!(
                extension
                    .after_modify_position(
                        context,
                        collateral_delta,
                        collateral_shares_delta,
                        debt_delta,
                        nominal_debt_delta,
                        data,
                        get_caller_address()
                    ),
                "after-modify-position-failed"
            );

            self
                .emit(
                    ModifyPosition {
                        pool_id,
                        collateral_asset,
                        debt_asset,
                        user,
                        collateral_delta,
                        collateral_shares_delta,
                        debt_delta,
                        nominal_debt_delta
                    }
                );

            // settle collateral and debt balances
            self
                .settle_position(
                    params.pool_id, params.collateral_asset, collateral_delta, params.debt_asset, debt_delta, 0
                );

            response
        }

        /// Transfers a position's collateral and or debt balances to another position in the same pool.
        /// Either the collateral or debt asset addresses match. For transfers to the same position
        /// `modify_position` should be used instead.
        /// # Arguments
        /// * `params` - see TransferPositionParams
        fn transfer_position(ref self: ContractState, params: TransferPositionParams) {
            let TransferPositionParams { pool_id,
            from_collateral_asset,
            from_debt_asset,
            to_collateral_asset,
            to_debt_asset,
            from_user,
            to_user,
            collateral,
            debt,
            from_data,
            to_data } =
                params;

            // ensure that it is not a transfer to the same position
            assert!(
                !(from_collateral_asset == to_collateral_asset
                    && from_debt_asset == to_debt_asset
                    && from_user == to_user),
                "same-position"
            );

            let from_context = self.context(pool_id, from_collateral_asset, from_debt_asset, from_user);
            let to_context = self.context(pool_id, to_collateral_asset, to_debt_asset, to_user);

            let from_collateral_asset_reserve = from_context.collateral_asset_config.reserve;
            let from_debt_asset_reserve = from_context.debt_asset_config.reserve;
            let to_collateral_asset_reserve = to_context.collateral_asset_config.reserve;
            let to_debt_asset_reserve = to_context.debt_asset_config.reserve;

            // call before-hook of the extension
            let extension = IExtensionDispatcher { contract_address: from_context.extension };
            let (collateral, debt) = extension
                .before_transfer_position(from_context, to_context, collateral, debt, from_data, get_caller_address());

            // ensure that the assets match if the transfer amount is non-zero
            if collateral.amount_type == AmountType::Target || collateral.value != 0 {
                assert!(from_collateral_asset == to_collateral_asset, "collateral-asset-mismatch");
            }
            if debt.amount_type == AmountType::Target || debt.value != 0 {
                assert!(from_debt_asset == to_debt_asset, "debt-asset-mismatch");
            }

            // reload context since the storage might have changed by a reentered call
            let mut from_context = self.context(pool_id, from_collateral_asset, from_debt_asset, from_user);

            let response = self
                .update_position(
                    ref from_context,
                    Amount {
                        amount_type: collateral.amount_type,
                        denomination: collateral.denomination,
                        value: -(collateral.value.into()),
                    },
                    Amount {
                        amount_type: debt.amount_type, denomination: debt.denomination, value: -(debt.value.into()),
                    },
                    0
                );
            let UpdatePositionResponse { collateral_delta, debt_delta, .. } = response;

            // verify invariants of the 'from' position
            self.assert_position_invariants(from_context, collateral_delta, debt_delta);

            // reload context since 'from' and 'to' context might referencing be the same storage vars
            let mut to_context = self.context(pool_id, to_collateral_asset, to_debt_asset, to_user);

            let response = self
                .update_position(
                    ref to_context,
                    Amount {
                        amount_type: AmountType::Delta,
                        denomination: AmountDenomination::Assets,
                        value: -response.collateral_delta,
                    },
                    Amount {
                        amount_type: AmountType::Delta,
                        denomination: AmountDenomination::Assets,
                        value: -response.debt_delta,
                    },
                    0
                );
            let UpdatePositionResponse { collateral_delta,
            collateral_shares_delta,
            debt_delta,
            nominal_debt_delta,
            .. } =
                response;

            // verify invariants of the 'to' position
            self.assert_position_invariants(to_context, collateral_delta, debt_delta);

            // reload context since 'from' and 'to' context might referencing be the same storage vars
            let from_context = self.context_unsafe(pool_id, from_collateral_asset, from_debt_asset, from_user);

            // verify that reserve are unchanged for the transferred asset
            assert!(
                from_collateral_asset_reserve == from_context.collateral_asset_config.reserve
                    && from_debt_asset_reserve == from_context.debt_asset_config.reserve
                    && to_collateral_asset_reserve == to_context.collateral_asset_config.reserve
                    && to_debt_asset_reserve == to_context.debt_asset_config.reserve,
                "reserve-changed"
            );

            // call after-hook of the extension
            assert!(
                extension
                    .after_transfer_position(
                        from_context,
                        to_context,
                        collateral_delta.abs,
                        collateral_shares_delta.abs,
                        debt_delta.abs,
                        nominal_debt_delta.abs,
                        to_data,
                        get_caller_address()
                    ),
                "after-transfer-position-failed"
            );

            self
                .emit(
                    TransferPosition {
                        pool_id,
                        from_collateral_asset,
                        from_debt_asset,
                        to_collateral_asset,
                        to_debt_asset,
                        from_user,
                        to_user
                    }
                );
        }

        /// Liquidates a position
        /// # Arguments
        /// * `params` - see LiquidatePositionParams
        /// # Returns
        /// * `response` - see UpdatePositionResponse
        fn liquidate_position(ref self: ContractState, params: LiquidatePositionParams) -> UpdatePositionResponse {
            let LiquidatePositionParams { pool_id, collateral_asset, debt_asset, user, receive_as_shares, data } =
                params;
            let context = self.context(pool_id, collateral_asset, debt_asset, user);

            // call before-hook of the extension
            let extension = IExtensionDispatcher { contract_address: context.extension };
            let (collateral, debt, bad_debt) = extension.before_liquidate_position(context, data, get_caller_address());

            // convert unsigned amounts to signed amounts
            let collateral = Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: -collateral.into(),
            };
            let debt = Amount {
                amount_type: AmountType::Delta, denomination: AmountDenomination::Assets, value: -debt.into(),
            };

            // reload context since it might have changed by a reentered call
            let mut context = self.context(pool_id, collateral_asset, debt_asset, user);

            // only allow for liquidation of undercollateralized positions
            let (_, collateral_value, _, debt_value) = calculate_collateral_and_debt_value(context, context.position);
            assert!(
                !is_collateralized(collateral_value, debt_value, context.max_ltv.into()), "not-undercollateralized"
            );

            // update the position
            let response = self.update_position(ref context, collateral, debt, bad_debt);
            let UpdatePositionResponse { mut collateral_delta,
            mut collateral_shares_delta,
            debt_delta,
            nominal_debt_delta,
            bad_debt } =
                response;

            if receive_as_shares {
                // update context for the liquidator
                context.user = get_caller_address();
                context.position = self.positions.read((pool_id, collateral_asset, debt_asset, context.user));
                // attribute shares to the liquidator
                self
                    .update_position(
                        ref context,
                        Amount {
                            amount_type: AmountType::Delta,
                            denomination: AmountDenomination::Native,
                            value: -collateral_shares_delta,
                        },
                        Default::default(),
                        0
                    );
                // reset the collateral / share deltas since the liquidator received shares
                collateral_delta = Zeroable::zero();
                collateral_shares_delta = Zeroable::zero();
            }

            // call after-hook of the extension (assets are not settled yet, only the internal state has been updated)
            assert!(
                extension
                    .after_liquidate_position(
                        context,
                        collateral_delta,
                        collateral_shares_delta,
                        debt_delta,
                        nominal_debt_delta,
                        bad_debt,
                        data,
                        get_caller_address()
                    ),
                "after-liquidate-position-failed"
            );

            self
                .emit(
                    LiquidatePosition {
                        pool_id,
                        collateral_asset,
                        debt_asset,
                        user,
                        liquidator: get_caller_address(),
                        collateral_delta,
                        collateral_shares_delta,
                        debt_delta,
                        nominal_debt_delta,
                        bad_debt
                    }
                );

            // settle collateral and debt balances
            self.settle_position(pool_id, collateral_asset, collateral_delta, debt_asset, debt_delta, bad_debt);

            response
        }

        /// Executes a flash loan
        /// # Arguments
        /// * `receiver` - address of the flash loan receiver
        /// * `asset` - address of the asset
        /// * `amount` - amount of the asset to loan
        /// * `data` - data to pass to the flash loan receiver
        fn flash_loan(
            ref self: ContractState,
            receiver: ContractAddress,
            asset: ContractAddress,
            amount: u256,
            is_legacy: bool,
            data: Span<felt252>
        ) {
            transfer_asset(asset, get_contract_address(), receiver, amount, is_legacy);
            IFlashloanReceiverDispatcher { contract_address: receiver }
                .on_flash_loan(get_caller_address(), asset, amount, data);
            transfer_asset(asset, receiver, get_contract_address(), amount, is_legacy);

            self.emit(Flashloan { sender: get_caller_address(), receiver, asset, amount });
        }

        /// Modifies the delegation status of a delegator to a delegatee for a specific pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `delegatee` - address of the delegatee
        /// * `delegation` - delegation status (true = delegate, false = undelegate)
        fn modify_delegation(ref self: ContractState, pool_id: felt252, delegatee: ContractAddress, delegation: bool) {
            self.delegations.write((pool_id, get_caller_address(), delegatee), delegation);

            self.emit(ModifyDelegation { pool_id, delegator: get_caller_address(), delegatee, delegation });
        }

        /// Donates an amount of an asset to the pool's reserve
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `amount` - amount to donate [asset scale]
        fn donate_to_reserve(ref self: ContractState, pool_id: felt252, asset: ContractAddress, amount: u256) {
            let (mut asset_config, _) = self.asset_config(pool_id, asset);
            assert!(assert_config_exists(asset_config), "asset-config-nonexistent");
            // account for the interest that has already accrued before updating the reserve (utilization)
            if asset_config.last_updated != get_block_timestamp() {
                asset_config = rate_accumulator(pool_id, self.extensions.read(pool_id), asset, asset_config);
            }
            // donate amount to the reserve
            asset_config.reserve += amount;
            self.asset_configs.write((pool_id, asset), asset_config);
            transfer_asset(asset, get_caller_address(), get_contract_address(), amount, asset_config.is_legacy);

            self.emit(Donate { pool_id, asset, amount });
        }

        /// Retrieves an amount of an asset from the pool's reserve. Can only be called by the pool's extension
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `receiver` - address of the receiver
        /// * `amount` - amount to retrieve [asset scale]
        fn retrieve_from_reserve(
            ref self: ContractState, pool_id: felt252, asset: ContractAddress, receiver: ContractAddress, amount: u256
        ) {
            let extension = self.extensions.read(pool_id);
            assert!(extension == get_caller_address(), "caller-not-extension");
            let (mut asset_config, _) = self.asset_config(pool_id, asset);
            assert!(assert_config_exists(asset_config), "asset-config-nonexistent");
            // account for the interest that has already accrued before updating the reserve (utilization)
            if asset_config.last_updated != get_block_timestamp() {
                asset_config = rate_accumulator(pool_id, extension, asset, asset_config);
            }
            // retrieve amount from the reserve
            asset_config.reserve -= amount;
            self.asset_configs.write((pool_id, asset), asset_config);
            transfer_asset(asset, get_contract_address(), receiver, amount, asset_config.is_legacy);

            self.emit(RetrieveReserve { pool_id, asset, receiver });
        }

        /// Sets the loan-to-value configuration between two assets (pair) in the pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `ltv_config` - ltv configuration
        fn set_ltv_config(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            ltv_config: LTVConfig
        ) {
            assert!(!self.lock.read(), "set-ltv-config-reentrancy");
            assert!(get_caller_address() == self.extensions.read(pool_id), "caller-not-extension");
            assert_ltv_config(ltv_config);

            self.ltv_configs.write((pool_id, collateral_asset, debt_asset), ltv_config);

            self.emit(SetLTVConfig { pool_id, collateral_asset, debt_asset, ltv_config });
        }

        /// Sets the configuration / initial state of an asset for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `params` - see AssetParams
        fn set_asset_config(ref self: ContractState, pool_id: felt252, params: AssetParams) {
            assert!(get_caller_address() == self.extensions.read(pool_id), "caller-not-extension");

            let already_exists = assert_config_exists(self.asset_configs.read((pool_id, params.asset)));
            assert!(!already_exists, "asset-config-already-exists");

            let asset_config = AssetConfig {
                total_collateral_shares: 0,
                total_nominal_debt: 0,
                reserve: 0,
                max_utilization: params.max_utilization,
                floor: params.floor,
                scale: pow_10(IERC20Dispatcher { contract_address: params.asset }.decimals().into()),
                is_legacy: params.is_legacy,
                last_updated: get_block_timestamp(),
                last_rate_accumulator: params.initial_rate_accumulator,
                last_full_utilization_rate: params.initial_full_utilization_rate,
                fee_rate: params.fee_rate,
            };

            assert_asset_config(asset_config);
            assert_storable_asset_config(asset_config);
            self.asset_configs.write((pool_id, params.asset), asset_config);

            self.emit(SetAssetConfig { pool_id, asset: params.asset });
        }

        /// Sets a parameter of an asset for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_asset_parameter(
            ref self: ContractState, pool_id: felt252, asset: ContractAddress, parameter: felt252, value: u256
        ) {
            assert!(!self.lock.read(), "set-asset-parameter-reentrancy");
            assert!(get_caller_address() == self.extensions.read(pool_id), "caller-not-extension");
            let (mut asset_config, _) = self.asset_config(pool_id, asset);
            if parameter == 'max_utilization' {
                asset_config.max_utilization = value;
            } else if parameter == 'floor' {
                asset_config.floor = value;
            } else if parameter == 'fee_rate' {
                asset_config.fee_rate = value;
            } else {
                panic!("invalid-asset-parameter");
            }

            assert_asset_config(asset_config);
            assert_storable_asset_config(asset_config);
            self.asset_configs.write((pool_id, asset), asset_config);

            self.emit(SetAssetParameter { pool_id, asset, parameter, value });
        }

        /// Sets the pool's extension address.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `extension` - address of the extension contract
        fn set_extension(ref self: ContractState, pool_id: felt252, extension: ContractAddress) {
            assert!(get_caller_address() == self.extensions.read(pool_id), "caller-not-extension");
            assert!(extension != Zeroable::zero(), "extension-not-set");
            self._set_extension(pool_id, extension);
        }
    }
}
