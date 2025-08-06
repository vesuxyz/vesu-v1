use alexandria_math::i257::i257;
use starknet::{ContractAddress, ClassHash};
use vesu::{
    data_model::{AssetParams, LTVParams, LTVConfig, DebtCapParams},
    extension::{
        components::{
            interest_rate_model::InterestRateConfig,
            position_hooks::{ShutdownMode, ShutdownStatus, ShutdownConfig, LiquidationConfig, Pair},
            fee_model::FeeConfig, pragma_oracle::OracleConfig,
        }
    },
    vendor::pragma::AggregationMode
};

#[derive(PartialEq, Copy, Drop, Serde)]
struct VTokenParams {
    v_token_name: felt252,
    v_token_symbol: felt252
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct PragmaOracleParams {
    pragma_key: felt252,
    timeout: u64, // [seconds]
    number_of_sources: u32,
    start_time_offset: u64, // [seconds]
    time_window: u64, // [seconds]
    aggregation_mode: AggregationMode
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct ShutdownParams {
    recovery_period: u64, // [seconds]
    subscription_period: u64, // [seconds]
    ltv_params: Span<LTVParams>,
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct LiquidationParams {
    collateral_asset_index: usize,
    debt_asset_index: usize,
    liquidation_factor: u64 // [SCALE]
}

#[derive(PartialEq, Copy, Drop, Serde)]
struct FeeParams {
    fee_recipient: ContractAddress
}

#[starknet::interface]
trait IDefaultExtensionCallback<TContractState> {
    fn singleton(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
trait ITokenizationCallback<TContractState> {
    fn v_token_for_collateral_asset(
        self: @TContractState, collateral_asset: ContractAddress
    ) -> ContractAddress;
    fn mint_or_burn_v_token(
        ref self: TContractState,
        collateral_asset: ContractAddress,
        user: ContractAddress,
        amount: i257
    );
}

#[starknet::interface]
trait IDefaultExtensionPOV2<TContractState> {
    fn pool_name(self: @TContractState) -> felt252;
    fn pool_owner(self: @TContractState) -> ContractAddress;
    fn shutdown_mode_agent(self: @TContractState) -> ContractAddress;
    fn pragma_oracle(self: @TContractState) -> ContractAddress;
    fn pragma_summary(self: @TContractState) -> ContractAddress;
    fn oracle_config(self: @TContractState, asset: ContractAddress) -> OracleConfig;
    fn fee_config(self: @TContractState) -> FeeConfig;
    fn debt_caps(
        self: @TContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> u256;
    fn interest_rate_config(self: @TContractState, asset: ContractAddress) -> InterestRateConfig;
    fn liquidation_config(
        self: @TContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> LiquidationConfig;
    fn shutdown_config(self: @TContractState) -> ShutdownConfig;
    fn shutdown_ltv_config(
        self: @TContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> LTVConfig;
    fn shutdown_status(
        self: @TContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> ShutdownStatus;
    fn pairs(
        self: @TContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> Pair;
    fn v_token_for_collateral_asset(
        self: @TContractState, collateral_asset: ContractAddress
    ) -> ContractAddress;
    fn collateral_asset_for_v_token(
        self: @TContractState, v_token: ContractAddress
    ) -> ContractAddress;
    fn create_pool(
        ref self: TContractState,
        name: felt252,
        asset_params: Span<AssetParams>,
        v_token_params: Span<VTokenParams>,
        ltv_params: Span<LTVParams>,
        interest_rate_configs: Span<InterestRateConfig>,
        pragma_oracle_params: Span<PragmaOracleParams>,
        liquidation_params: Span<LiquidationParams>,
        debt_caps: Span<DebtCapParams>,
        shutdown_params: ShutdownParams,
        fee_params: FeeParams,
        owner: ContractAddress
    ) -> felt252;
    fn add_asset(
        ref self: TContractState,
        asset_params: AssetParams,
        v_token_params: VTokenParams,
        interest_rate_config: InterestRateConfig,
        pragma_oracle_params: PragmaOracleParams
    );
    fn set_asset_parameter(
        ref self: TContractState, asset: ContractAddress, parameter: felt252, value: u256
    );
    fn set_debt_cap(
        ref self: TContractState,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        debt_cap: u256
    );
    fn set_interest_rate_parameter(
        ref self: TContractState, asset: ContractAddress, parameter: felt252, value: u256
    );
    fn set_oracle_parameter(
        ref self: TContractState, asset: ContractAddress, parameter: felt252, value: felt252
    );
    fn set_liquidation_config(
        ref self: TContractState,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        liquidation_config: LiquidationConfig
    );
    fn set_ltv_config(
        ref self: TContractState,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        ltv_config: LTVConfig
    );
    fn set_shutdown_config(ref self: TContractState, shutdown_config: ShutdownConfig);
    fn set_shutdown_ltv_config(
        ref self: TContractState,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        shutdown_ltv_config: LTVConfig
    );
    fn set_shutdown_mode(ref self: TContractState, shutdown_mode: ShutdownMode);
    fn set_pool_owner(ref self: TContractState, owner: ContractAddress);
    fn set_shutdown_mode_agent(ref self: TContractState, shutdown_mode_agent: ContractAddress);
    fn update_shutdown_status(
        ref self: TContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
    ) -> ShutdownMode;
    fn set_fee_config(ref self: TContractState, fee_config: FeeConfig);
    fn claim_fees(ref self: TContractState, collateral_asset: ContractAddress);

    // Upgrade
    fn upgrade_name(self: @TContractState) -> felt252;
    fn upgrade(ref self: TContractState, new_implementation: ClassHash);
}

#[starknet::contract]
mod DefaultExtensionPOV2 {
    use alexandria_math::i257::{i257, i257_new};
    use starknet::{
        ClassHash, ContractAddress, get_contract_address, get_caller_address, event::EventEmitter,
        contract_address_const, deploy_syscall, syscalls::{replace_class_syscall, call_contract_syscall}
    };
    use vesu::{
        units::INFLATION_FEE,
        data_model::{
            Amount, UnsignedAmount, AssetParams, AssetPrice, LTVParams, Context, LTVConfig, ModifyPositionParams,
            AmountDenomination, AmountType, DebtCapParams
        },
        singleton_v2::{ISingletonV2Dispatcher, ISingletonV2DispatcherTrait},
        vendor::{
            erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait},
            ownable::{IOwnableDispatcher, IOwnableDispatcherTrait},
        },
        extension::{
            interface::IExtension,
            components::{
                interest_rate_model::{
                    InterestRateConfig, interest_rate_model_component,
                    interest_rate_model_component::InterestRateModelTrait
                },
                position_hooks::{
                    position_hooks_component, position_hooks_component::PositionHooksTrait, ShutdownStatus,
                    ShutdownMode, ShutdownConfig, LiquidationConfig, Pair
                },
                pragma_oracle::{pragma_oracle_component, pragma_oracle_component::PragmaOracleTrait, OracleConfig},
                fee_model::{fee_model_component, fee_model_component::FeeModelTrait, FeeConfig},
                tokenization::{tokenization_component, tokenization_component::TokenizationTrait}
            },
            default_extension_po_v2::{
                LiquidationParams, ShutdownParams, PragmaOracleParams, FeeParams, VTokenParams,
                IDefaultExtensionCallback, ITokenizationCallback, IDefaultExtensionPOV2,
                IDefaultExtensionPOV2Dispatcher, IDefaultExtensionPOV2DispatcherTrait
            },
        },
    };

    component!(path: position_hooks_component, storage: position_hooks, event: PositionHooksEvents);
    component!(path: interest_rate_model_component, storage: interest_rate_model, event: InterestRateModelEvents);
    component!(path: pragma_oracle_component, storage: pragma_oracle, event: PragmaOracleEvents);
    component!(path: fee_model_component, storage: fee_model, event: FeeModelEvents);
    component!(path: tokenization_component, storage: tokenization, event: TokenizationEvents);


    #[storage]
    struct Storage {
        // address of the singleton contract
        singleton: ContractAddress,
        // tracks the owner for each pool
        owner: LegacyMap::<felt252, ContractAddress>,
        // tracks the name for each pool
        pool_names: LegacyMap::<felt252, felt252>,
        // storage for the position hooks component
        #[substorage(v0)]
        position_hooks: position_hooks_component::Storage,
        // storage for the interest rate model component
        #[substorage(v0)]
        interest_rate_model: interest_rate_model_component::Storage,
        // storage for the pragma oracle component
        #[substorage(v0)]
        pragma_oracle: pragma_oracle_component::Storage,
        // storage for the fee model component
        #[substorage(v0)]
        fee_model: fee_model_component::Storage,
        // storage for the tokenization component
        #[substorage(v0)]
        tokenization: tokenization_component::Storage,
        // tracks the address that can transition the shutdown mode of a pool
        shutdown_mode_agent: LegacyMap::<felt252, ContractAddress>,
    }

    #[derive(Drop, starknet::Event)]
    struct SetAssetParameter {
        #[key]
        asset: ContractAddress,
        #[key]
        parameter: felt252,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct SetPoolOwner {
        #[key]
        owner: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ContractUpgraded {
        new_implementation: ClassHash,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PositionHooksEvents: position_hooks_component::Event,
        InterestRateModelEvents: interest_rate_model_component::Event,
        PragmaOracleEvents: pragma_oracle_component::Event,
        FeeModelEvents: fee_model_component::Event,
        TokenizationEvents: tokenization_component::Event,
        SetAssetParameter: SetAssetParameter,
        SetPoolOwner: SetPoolOwner,
        ContractUpgraded: ContractUpgraded,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        singleton: ContractAddress,
        oracle_address: ContractAddress,
        summary_address: ContractAddress,
        v_token_class_hash: felt252
    ) {
        self.singleton.write(singleton);
        self.pragma_oracle.set_oracle(oracle_address);
        self.pragma_oracle.set_summary_address(summary_address);
        self.tokenization.set_v_token_class_hash(v_token_class_hash);
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
        fn assert_singleton_owner(ref self: ContractState) {
            let owner = IOwnableDispatcher { contract_address: self.singleton.read() }.owner();
            assert!(get_caller_address() == owner, "caller-not-singleton-owner");
        }

        fn burn_inflation_fee(ref self: ContractState, asset: ContractAddress, is_legacy: bool) {
            let singleton = ISingletonV2Dispatcher { contract_address: self.singleton.read() };

            // burn inflation fee
            let asset = IERC20Dispatcher { contract_address: asset };
            transfer_asset(
                asset.contract_address, get_caller_address(), get_contract_address(), INFLATION_FEE, is_legacy
            );
            assert!(asset.approve(singleton.contract_address, INFLATION_FEE), "approve-failed");
            singleton
                .modify_position(
                    ModifyPositionParams {
                        collateral_asset: asset.contract_address,
                        debt_asset: Zeroable::zero(),
                        user: contract_address_const::<'ZERO'>(),
                        collateral: Amount {
                            amount_type: AmountType::Delta,
                            denomination: AmountDenomination::Assets,
                            value: i257_new(INFLATION_FEE, false),
                        },
                        debt: Default::default(),
                        data: ArrayTrait::new().span()
                    }
                );
        }
    }

    impl DefaultExtensionCallbackImpl of IDefaultExtensionCallback<ContractState> {
        fn singleton(self: @ContractState) -> ContractAddress {
            self.singleton.read()
        }
    }

    impl TokenizationCallbackImpl of ITokenizationCallback<ContractState> {
        /// See tokenization.v_token_for_collateral_asset()
        fn v_token_for_collateral_asset(
            self: @ContractState, collateral_asset: ContractAddress
        ) -> ContractAddress {
            self.tokenization.v_token_for_collateral_asset(collateral_asset)
        }
        /// See tokenization.mint_or_burn_v_token()
        fn mint_or_burn_v_token(
            ref self: ContractState,
            collateral_asset: ContractAddress,
            user: ContractAddress,
            amount: i257
        ) {
            self.tokenization.mint_or_burn_v_token(collateral_asset, user, amount)
        }
    }

    #[abi(embed_v0)]
    impl DefaultExtensionPOV2Impl of IDefaultExtensionPOV2<ContractState> {
        /// Returns the address of the shutdown mode agent for a given pool
        /// # Returns
        /// * `shutdown_mode_agent` - address of the shutdown mode agent
        fn shutdown_mode_agent(self: @ContractState) -> ContractAddress {
            self.shutdown_mode_agent.read()
        }

        /// Returns the address of the pragma oracle contract
        /// # Returns
        /// * `oracle_address` - address of the pragma oracle contract
        fn pragma_oracle(self: @ContractState) -> ContractAddress {
            self.pragma_oracle.oracle_address()
        }

        /// Returns the address of the pragma summary contract
        /// # Returns
        /// * `summary_address` - address of the pragma summary contract
        fn pragma_summary(self: @ContractState) -> ContractAddress {
            self.pragma_oracle.summary_address()
        }

        /// Returns the oracle configuration for a given pool and asset
        /// # Arguments
        /// * `asset` - address of the asset
        /// # Returns
        /// * `oracle_config` - oracle configuration
        fn oracle_config(self: @ContractState, asset: ContractAddress) -> OracleConfig {
            self.pragma_oracle.oracle_configs.read(asset)
        }

        /// Returns the fee configuration for a given pool
        /// # Returns
        /// * `fee_config` - fee configuration
        fn fee_config(self: @ContractState) -> FeeConfig {
            self.fee_model.fee_configs.read()
        }

        /// Returns the debt cap for a given asset in a pool
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `debt_cap` - debt cap
        fn debt_caps(
            self: @ContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> u256 {
            self.position_hooks.debt_caps.read((collateral_asset, debt_asset))
        }

        /// Returns the interest rate configuration for a given pool and asset
        /// # Arguments
        /// * `asset` - address of the asset
        /// # Returns
        /// * `interest_rate_config` - interest rate configuration
        fn interest_rate_config(self: @ContractState, asset: ContractAddress) -> InterestRateConfig {
            self.interest_rate_model.interest_rate_configs.read(asset)
        }

        /// Returns the liquidation configuration for a given pool and pairing of assets
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `liquidation_config` - liquidation configuration
        fn liquidation_config(
            self: @ContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> LiquidationConfig {
            self.position_hooks.liquidation_configs.read((collateral_asset, debt_asset))
        }

        /// Returns the shutdown configuration for a given pool
        /// # Returns
        /// * `recovery_period` - recovery period
        /// * `subscription_period` - subscription period
        fn shutdown_config(self: @ContractState) -> ShutdownConfig {
            self.position_hooks.shutdown_configs.read()
        }

        /// Returns the shutdown LTV configuration for a given pair in a given pool
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `shutdown_ltv_config` - shutdown LTV configuration
        fn shutdown_ltv_config(
            self: @ContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> LTVConfig {
            self.position_hooks.shutdown_ltv_configs.read((collateral_asset, debt_asset))
        }

        /// Returns the total (sum of all positions) collateral shares and nominal debt balances for a given pair
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `total_collateral_shares` - total collateral shares
        /// * `total_nominal_debt` - total nominal debt
        fn pairs(
            self: @ContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> Pair {
            self.position_hooks.pairs.read((collateral_asset, debt_asset))
        }

        /// Returns the address of the vToken deployed for the collateral asset for a given pool
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// # Returns
        /// * `v_token` - address of the vToken
        fn v_token_for_collateral_asset(
            self: @ContractState, collateral_asset: ContractAddress
        ) -> ContractAddress {
            self.tokenization.v_token_for_collateral_asset(collateral_asset)
        }

        /// Returns the default pairing (collateral asset, debt asset) used for 
        /// # Arguments
        /// * `v_token` - address of the vToken
        /// # Returns
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        fn collateral_asset_for_v_token(
            self: @ContractState, v_token: ContractAddress
        ) -> ContractAddress {
            self.tokenization.collateral_asset_for_v_token(v_token)
        }

        /// Creates a new pool
        /// # Arguments
        /// * `name` - name of the pool
        /// * `asset_params` - asset parameters
        /// * `v_token_params` - vToken parameters
        /// * `ltv_params` - loan-to-value parameters
        /// * `interest_rate_params` - interest rate model parameters
        /// * `pragma_oracle_params` - pragma oracle parameters
        /// * `liquidation_params` - liquidation parameters
        /// * `debt_caps` - debt caps
        /// * `shutdown_params` - shutdown parameters
        /// * `fee_params` - fee model parameters
        fn create_pool(
            ref self: ContractState,
            name: felt252,
            mut asset_params: Span<AssetParams>,
            mut v_token_params: Span<VTokenParams>,
            mut ltv_params: Span<LTVParams>,
            mut interest_rate_configs: Span<InterestRateConfig>,
            mut pragma_oracle_params: Span<PragmaOracleParams>,
            mut liquidation_params: Span<LiquidationParams>,
            mut debt_caps: Span<DebtCapParams>,
            shutdown_params: ShutdownParams,
            fee_params: FeeParams,
            owner: ContractAddress
        ) -> felt252 {
            assert!(asset_params.len() > 0, "empty-asset-params");
            // assert that all arrays have equal length
            assert!(asset_params.len() == interest_rate_configs.len(), "interest-rate-params-mismatch");
            assert!(asset_params.len() == pragma_oracle_params.len(), "pragma-oracle-params-mismatch");
            assert!(asset_params.len() == v_token_params.len(), "v-token-params-mismatch");

            // create the pool in the singleton
            let singleton = ISingletonV2Dispatcher { contract_address: self.singleton.read() };
            let pool_id = singleton.create_pool(asset_params, ltv_params, get_contract_address());

            // set the pool name
            self.pool_names.write(pool_id, name);

            // set the pool owner
            self.owner.write(pool_id, owner);

            let mut asset_params_copy = asset_params;
            let mut i = 0;
            while !asset_params_copy
                .is_empty() {
                    let asset_params = *asset_params_copy.pop_front().unwrap();
                    let asset = asset_params.asset;

                    // set the oracle config
                    let params = *pragma_oracle_params.pop_front().unwrap();
                    let PragmaOracleParams { pragma_key,
                    timeout,
                    number_of_sources,
                    start_time_offset,
                    time_window,
                    aggregation_mode } =
                        params;
                    self
                        .pragma_oracle
                        .set_oracle_config(
                            pool_id,
                            asset,
                            OracleConfig {
                                pragma_key, timeout, number_of_sources, start_time_offset, time_window, aggregation_mode
                            }
                        );

                    // set the interest rate model configuration
                    let interest_rate_config = *interest_rate_configs.pop_front().unwrap();
                    self.interest_rate_model.set_interest_rate_config(pool_id, asset, interest_rate_config);

                    let v_token_config = *v_token_params.at(i);
                    let VTokenParams { v_token_name, v_token_symbol } = v_token_config;

                    // deploy the vToken for the the collateral asset
                    self.tokenization.create_v_token(pool_id, asset, v_token_name, v_token_symbol);

                    // burn inflation fee
                    self.burn_inflation_fee(pool_id, asset, asset_params.is_legacy);

                    i += 1;
                };

            // set the liquidation config for each pair
            let mut liquidation_params = liquidation_params;
            while !liquidation_params
                .is_empty() {
                    let params = *liquidation_params.pop_front().unwrap();
                    let collateral_asset = *asset_params.at(params.collateral_asset_index).asset;
                    let debt_asset = *asset_params.at(params.debt_asset_index).asset;
                    self
                        .position_hooks
                        .set_liquidation_config(
                            pool_id,
                            collateral_asset,
                            debt_asset,
                            LiquidationConfig { liquidation_factor: params.liquidation_factor }
                        );
                };

            // set the debt caps for each pair
            let mut debt_caps = debt_caps;
            while !debt_caps
                .is_empty() {
                    let params = *debt_caps.pop_front().unwrap();
                    let collateral_asset = *asset_params.at(params.collateral_asset_index).asset;
                    let debt_asset = *asset_params.at(params.debt_asset_index).asset;
                    self.position_hooks.set_debt_cap(pool_id, collateral_asset, debt_asset, params.debt_cap);
                };

            // set the max shutdown LTVs for each pair
            let mut shutdown_ltv_params = shutdown_params.ltv_params;
            while !shutdown_ltv_params
                .is_empty() {
                    let params = *shutdown_ltv_params.pop_front().unwrap();
                    let collateral_asset = *asset_params.at(params.collateral_asset_index).asset;
                    let debt_asset = *asset_params.at(params.debt_asset_index).asset;
                    self
                        .position_hooks
                        .set_shutdown_ltv_config(
                            pool_id, collateral_asset, debt_asset, LTVConfig { max_ltv: params.max_ltv }
                        );
                };

            // set the shutdown config
            let ShutdownParams { recovery_period, subscription_period, .. } = shutdown_params;
            self.position_hooks.set_shutdown_config(pool_id, ShutdownConfig { recovery_period, subscription_period });

            // set the fee config
            self.fee_model.set_fee_config(pool_id, FeeConfig { fee_recipient: fee_params.fee_recipient });

            pool_id
        }

        /// Adds an asset to a pool
        /// # Arguments
        /// * `asset_params` - asset parameters
        /// * `v_token_params` - vToken parameters
        /// * `interest_rate_model` - interest rate model
        /// * `pragma_oracle_params` - pragma oracle parameters
        fn add_asset(
            ref self: ContractState,
            asset_params: AssetParams,
            v_token_params: VTokenParams,
            interest_rate_config: InterestRateConfig,
            pragma_oracle_params: PragmaOracleParams
        ) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            let asset = asset_params.asset;

            // set the oracle config
            self
                .pragma_oracle
                .set_oracle_config(
                    asset,
                    OracleConfig {
                        pragma_key: pragma_oracle_params.pragma_key,
                        timeout: pragma_oracle_params.timeout,
                        number_of_sources: pragma_oracle_params.number_of_sources,
                        start_time_offset: pragma_oracle_params.start_time_offset,
                        time_window: pragma_oracle_params.time_window,
                        aggregation_mode: pragma_oracle_params.aggregation_mode
                    }
                );

            // set the interest rate model configuration
            self.interest_rate_model.set_interest_rate_config(asset, interest_rate_config);

            // deploy the vToken for the the collateral asset
            let VTokenParams { v_token_name, v_token_symbol } = v_token_params;
            self.tokenization.create_v_token(asset, v_token_name, v_token_symbol);

            let singleton = ISingletonV2Dispatcher { contract_address: self.singleton.read() };
            singleton.set_asset_config(asset_params);

            // burn inflation fee
            self.burn_inflation_fee(asset, asset_params.is_legacy);
        }

        /// Sets the debt cap for a given asset in a pool
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `debt_cap` - debt cap
        fn set_debt_cap(
            ref self: ContractState,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            debt_cap: u256
        ) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.position_hooks.set_debt_cap(collateral_asset, debt_asset, debt_cap);
        }

        /// Sets a parameter for a given interest rate configuration for an asset in a pool
        /// # Arguments
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_interest_rate_parameter(
            ref self: ContractState, asset: ContractAddress, parameter: felt252, value: u256
        ) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.interest_rate_model.set_interest_rate_parameter(asset, parameter, value);
        }

        /// Sets a parameter for a given oracle configuration of an asset in a pool
        /// # Arguments
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_oracle_parameter(
            ref self: ContractState, asset: ContractAddress, parameter: felt252, value: felt252
        ) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.pragma_oracle.set_oracle_parameter(asset, parameter, value);
        }

        /// Sets the loan-to-value configuration between two assets (pair) in the pool in the singleton
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `ltv_config` - ltv configuration
        fn set_ltv_config(
            ref self: ContractState,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            ltv_config: LTVConfig
        ) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            ISingletonV2Dispatcher { contract_address: self.singleton.read() }
                .set_ltv_config(collateral_asset, debt_asset, ltv_config);
        }

        /// Sets the liquidation config for a given pair in the pool
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `liquidation_config` - liquidation config
        fn set_liquidation_config(
            ref self: ContractState,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            liquidation_config: LiquidationConfig
        ) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.position_hooks.set_liquidation_config(collateral_asset, debt_asset, liquidation_config);
        }

        /// Sets a parameter of an asset for a given pool
        /// # Arguments
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter 
        fn set_asset_parameter(
            ref self: ContractState, asset: ContractAddress, parameter: felt252, value: u256
        ) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            ISingletonV2Dispatcher { contract_address: self.singleton.read() }
                .set_asset_parameter(asset, parameter, value);
        }

        /// Sets the shutdown config for a given pool
        /// # Arguments
        /// * `shutdown_config` - shutdown config
        fn set_shutdown_config(ref self: ContractState, shutdown_config: ShutdownConfig) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.position_hooks.set_shutdown_config(shutdown_config);
        }

        /// Sets the shutdown LTV config for a given pair in the pool
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `shutdown_ltv_config` - shutdown LTV config
        fn set_shutdown_ltv_config(
            ref self: ContractState,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            shutdown_ltv_config: LTVConfig
        ) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.position_hooks.set_shutdown_ltv_config(collateral_asset, debt_asset, shutdown_ltv_config);
        }

        /// Sets the owner of a pool
        /// # Arguments
        /// * `owner` - address of the new owner
        fn set_pool_owner(ref self: ContractState, owner: ContractAddress) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.owner.write(owner);
            self.emit(SetPoolOwner { owner });
        }

        /// Sets the shutdown mode agent for a specific pool
        /// # Arguments
        /// * `shutdown_mode_agent` - address of the shutdown mode agent
        fn set_shutdown_mode_agent(ref self: ContractState, shutdown_mode_agent: ContractAddress) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.shutdown_mode_agent.write(shutdown_mode_agent);
        }

        /// Sets the shutdown mode for a given pool and overwrites the inferred shutdown mode
        /// # Arguments
        /// * `shutdown_mode` - shutdown mode
        fn set_shutdown_mode(ref self: ContractState, shutdown_mode: ShutdownMode) {
            let shutdown_mode_agent = self.shutdown_mode_agent.read();
            assert!(
                get_caller_address() == self.owner.read() || get_caller_address() == shutdown_mode_agent,
                "caller-not-owner-or-agent"
            );
            assert!(
                get_caller_address() != shutdown_mode_agent || shutdown_mode == ShutdownMode::Recovery,
                "shutdown-mode-not-recovery"
            );
            self.position_hooks.set_shutdown_mode(shutdown_mode);
        }

        /// Returns the shutdown mode for a specific pair in a pool.
        /// To check the shutdown status of the pool, the shutdown mode for all pairs must be checked.
        /// See `shutdown_status` in `position_hooks.cairo`.
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `shutdown_mode` - shutdown mode
        /// * `violation` - whether the pair currently violates any of the invariants (transitioned to recovery mode)
        /// * `previous_violation_timestamp` - timestamp at which the pair previously violated the invariants (transitioned to recovery mode)
        /// * `count_at_violation_timestamp_timestamp` - count of how many pairs violated the invariants at that timestamp
        fn shutdown_status(
            self: @ContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> ShutdownStatus {
            let singleton = ISingletonV2Dispatcher { contract_address: self.singleton.read() };
            let mut context = singleton.context_unsafe(collateral_asset, debt_asset, Zeroable::zero());
            self.position_hooks.shutdown_status(ref context)
        }

        /// Updates the shutdown mode for a specific pair in a pool.
        /// See `update_shutdown_status` in `position_hooks.cairo`.
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `shutdown_mode` - shutdown mode
        fn update_shutdown_status(
            ref self: ContractState, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> ShutdownMode {
            let singleton = ISingletonV2Dispatcher { contract_address: self.singleton.read() };
            let mut context = singleton.context(collateral_asset, debt_asset, Zeroable::zero());
            self.position_hooks.update_shutdown_status(ref context)
        }

        /// Sets the fee configuration for a specific pool.
        /// # Arguments
        /// * `fee_config` - new fee configuration parameters
        fn set_fee_config(ref self: ContractState, fee_config: FeeConfig) {
            assert!(get_caller_address() == self.owner.read(), "caller-not-owner");
            self.fee_model.set_fee_config(fee_config);
        }

        /// Claims the fees for a specific pair in a pool.
        /// See `claim_fees` in `fee_model.cairo`.
        /// # Arguments
        /// * `collateral_asset` - address of the collateral asset
        fn claim_fees(ref self: ContractState, collateral_asset: ContractAddress) {
            self.fee_model.claim_fees(collateral_asset);
        }

        /// Returns the name of the contract
        /// # Returns
        /// * `name` - the name of the contract
        fn upgrade_name(self: @ContractState) -> felt252 {
            'Vesu default extension po v2'
        }

        /// Upgrades the contract to a new implementation
        /// # Arguments
        /// * `new_implementation` - the new implementation class hash
        fn upgrade(ref self: ContractState, new_implementation: ClassHash) {
            self.assert_singleton_owner();
            replace_class_syscall(new_implementation).unwrap();
            // Check to prevent mistakes when upgrading the contract
            let new_name = IDefaultExtensionPOV2Dispatcher { contract_address: get_contract_address() }.upgrade_name();
            assert!(new_name == self.upgrade_name(), "invalid-upgrade-name");
            self.emit(ContractUpgraded { new_implementation });
        }
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        /// Returns the address of the singleton contract
        /// # Returns
        /// * `singleton` - address of the singleton contract
        fn singleton(self: @ContractState) -> ContractAddress {
            self.singleton.read()
        }

        /// Returns the price for a given asset in a given pool
        /// # Arguments
        /// * `asset` - address of the asset
        /// # Returns
        /// * `AssetPrice` - latest price of the asset and its validity
        fn price(self: @ContractState, asset: ContractAddress) -> AssetPrice {
            let (value, is_valid) = self.pragma_oracle.price(asset);
            AssetPrice { value, is_valid }
        }

        /// Returns the current interest rate for a given asset in a given pool, given it's utilization
        /// # Arguments
        /// * `asset` - address of the asset
        /// * `utilization` - utilization of the asset
        /// * `last_updated` - last time the interest rate was updated
        /// * `last_full_utilization_rate` - The interest value when utilization is 100% [SCALE]
        /// # Returns
        /// * `interest_rate` - current interest rate
        fn interest_rate(
            self: @ContractState,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_full_utilization_rate: u256,
        ) -> u256 {
            let (interest_rate, _) = self
                .interest_rate_model
                .interest_rate(asset, utilization, last_updated, last_full_utilization_rate);
            interest_rate
        }

        /// Returns the current rate accumulator for a given asset in a given pool, given it's utilization
        /// # Arguments
        /// * `asset` - address of the asset
        /// * `utilization` - utilization of the asset
        /// * `last_updated` - last time the interest rate was updated
        /// * `last_rate_accumulator` - last rate accumulator
        /// * `last_full_utilization_rate` - the interest value when utilization is 100% [SCALE]
        /// # Returns
        /// * `rate_accumulator` - current rate accumulator
        /// * `last_full_utilization_rate` - the interest value when utilization is 100% [SCALE]
        fn rate_accumulator(
            self: @ContractState,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_rate_accumulator: u256,
            last_full_utilization_rate: u256,
        ) -> (u256, u256) {
            self
                .interest_rate_model
                .rate_accumulator(
                    asset, utilization, last_updated, last_rate_accumulator, last_full_utilization_rate
                )
        }

        /// Modify position callback. Called by the Singleton contract before updating the position.
        /// See `before_modify_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `data` - modify position data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        fn before_modify_position(
            ref self: ContractState,
            context: Context,
            collateral: Amount,
            debt: Amount,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> (Amount, Amount) {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            (collateral, debt)
        }

        /// Modify position callback. Called by the Singleton contract after updating the position.
        /// See `after_modify_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `collateral_shares_delta` - collateral shares balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `nominal_debt_delta` - nominal debt balance delta of the position
        /// * `data` - modify position data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `bool` - true if the callback was successful
        fn after_modify_position(
            ref self: ContractState,
            context: Context,
            collateral_delta: i257,
            collateral_shares_delta: i257,
            debt_delta: i257,
            nominal_debt_delta: i257,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self
                .position_hooks
                .after_modify_position(
                    context, collateral_delta, collateral_shares_delta, debt_delta, nominal_debt_delta, data, caller
                )
        }

        /// Transfer position callback. Called by the Singleton contract before transferring collateral / debt
        /// between position.
        // / See `before_transfer_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `from_context` - contextual state of the user (position owner) from which to transfer collateral / debt
        /// * `to_context` - contextual state of the user (position owner) to which to transfer collateral / debt
        /// * `collateral` - amount of collateral to be transferred
        /// * `debt` - amount of debt to be transferred
        /// * `data` - modify position data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `collateral` - amount of collateral to be transferred
        /// * `debt` - amount of debt to be transferred
        fn before_transfer_position(
            ref self: ContractState,
            from_context: Context,
            to_context: Context,
            collateral: UnsignedAmount,
            debt: UnsignedAmount,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> (UnsignedAmount, UnsignedAmount) {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self.position_hooks.before_transfer_position(from_context, to_context, collateral, debt, data, caller)
        }

        /// Transfer position callback. Called by the Singleton contract after transferring collateral / debt
        /// See `after_transfer_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `from_context` - contextual state of the user (position owner) from which to transfer collateral / debt
        /// * `to_context` - contextual state of the user (position owner) to which to transfer collateral / debt
        /// * `collateral_delta` - collateral balance delta that was transferred
        /// * `collateral_shares_delta` - collateral shares balance delta that was transferred
        /// * `debt_delta` - debt balance delta that was transferred
        /// * `nominal_debt_delta` - nominal debt balance delta that was transferred
        /// * `data` - modify position data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `bool` - true if the callback was successful
        fn after_transfer_position(
            ref self: ContractState,
            from_context: Context,
            to_context: Context,
            collateral_delta: u256,
            collateral_shares_delta: u256,
            debt_delta: u256,
            nominal_debt_delta: u256,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self
                .position_hooks
                .after_transfer_position(
                    from_context,
                    to_context,
                    collateral_delta,
                    collateral_shares_delta,
                    debt_delta,
                    nominal_debt_delta,
                    data,
                    caller
                )
        }

        /// Liquidate position callback. Called by the Singleton contract before liquidating the position.
        /// See `before_liquidate_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `data` - liquidation data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `collateral` - amount of collateral to be removed
        /// * `debt` - amount of debt to be removed
        /// * `bad_debt` - amount of bad debt accrued during the liquidation
        fn before_liquidate_position(
            ref self: ContractState, context: Context, data: Span<felt252>, caller: ContractAddress
        ) -> (u256, u256, u256) {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self.position_hooks.before_liquidate_position(context, data, caller)
        }

        /// Liquidate position callback. Called by the Singleton contract after liquidating the position.
        /// See `before_liquidate_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `collateral_shares_delta` - collateral shares balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `nominal_debt_delta` - nominal debt balance delta of the position
        /// * `bad_debt` - accrued bad debt from the liquidation
        /// * `data` - liquidation data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `bool` - true if the callback was successful
        fn after_liquidate_position(
            ref self: ContractState,
            context: Context,
            collateral_delta: i257,
            collateral_shares_delta: i257,
            debt_delta: i257,
            nominal_debt_delta: i257,
            bad_debt: u256,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self
                .position_hooks
                .after_liquidate_position(
                    context,
                    collateral_delta,
                    collateral_shares_delta,
                    debt_delta,
                    nominal_debt_delta,
                    bad_debt,
                    data,
                    caller
                )
        }
    }
}
