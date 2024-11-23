use starknet::ContractAddress;

#[starknet::interface]
trait IERC4626<TContractState> {
    fn asset(self: @TContractState) -> ContractAddress;
    fn total_assets(self: @TContractState) -> u256;
    fn convert_to_shares(self: @TContractState, assets: u256) -> u256;
    fn convert_to_assets(self: @TContractState, shares: u256) -> u256;
    fn max_deposit(self: @TContractState, receiver: ContractAddress) -> u256;
    fn preview_deposit(self: @TContractState, assets: u256) -> u256;
    fn deposit(ref self: TContractState, assets: u256, receiver: ContractAddress) -> u256;
    fn max_mint(self: @TContractState, receiver: ContractAddress) -> u256;
    fn preview_mint(self: @TContractState, shares: u256) -> u256;
    fn mint(ref self: TContractState, shares: u256, receiver: ContractAddress) -> u256;
    fn max_withdraw(self: @TContractState, owner: ContractAddress) -> u256;
    fn preview_withdraw(self: @TContractState, assets: u256) -> u256;
    fn withdraw(ref self: TContractState, assets: u256, receiver: ContractAddress, owner: ContractAddress) -> u256;
    fn max_redeem(self: @TContractState, owner: ContractAddress) -> u256;
    fn preview_redeem(self: @TContractState, shares: u256) -> u256;
    fn redeem(ref self: TContractState, shares: u256, receiver: ContractAddress, owner: ContractAddress) -> u256;
}

#[starknet::interface]
trait IVToken<TContractState> {
    fn extension(self: @TContractState) -> ContractAddress;
    fn pool_id(self: @TContractState) -> felt252;
    fn approve_extension(ref self: TContractState);
    fn mint_v_token(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn burn_v_token(ref self: TContractState, from: ContractAddress, amount: u256) -> bool;
}
#[starknet::contract]
mod VToken {
    use alexandria_math::i257::{i257, i257_new};
    use core::num::traits::Bounded;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, event::EventEmitter};
    use vesu::{
        data_model::{ModifyPositionParams, Amount, AmountType, AmountDenomination, AssetConfig}, units::SCALE,
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
        extension::{
            interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
            default_extension_po::{IDefaultExtensionDispatcher, IDefaultExtensionDispatcherTrait, ShutdownMode},
        },
        v_token::IVToken,
        vendor::{
            erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait}, erc20_component::ERC20Component
        },
    };

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        // The id of the pool in which the vToken's underlying asset is deposited into
        pool_id: felt252,
        // The extension of the pool
        extension: ContractAddress,
        // The underlying asset of the vToken
        asset: ContractAddress,
        // Flag indicating whether the asset is a legacy ERC20 token using camelCase or snake_case
        is_legacy: bool
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        sender: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        sender: ContractAddress,
        #[key]
        receiver: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        Deposit: Deposit,
        Withdraw: Withdraw
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        pool_id: felt252,
        extension: ContractAddress,
        asset: ContractAddress
    ) {
        self.erc20.initializer(name, symbol, decimals);
        self.pool_id.write(pool_id);
        self.extension.write(extension);
        self.asset.write(asset);
        self.erc20._approve(get_contract_address(), extension, Bounded::<u256>::MAX);
        IERC20Dispatcher { contract_address: asset }.approve(self.singleton().contract_address, Bounded::<u256>::MAX);
        let (asset_config, _) = self.singleton().asset_config(pool_id, asset);
        self.is_legacy.write(asset_config.is_legacy);
    }

    /// Calculate the amount of assets that can be withdrawn from the pool by taking the current utilization
    /// of the asset into account
    /// # Arguments
    /// * `asset_config` - Configuration of the asset
    /// * `total_debt` - Total amount outstanding of the asset [asset scale]
    /// # Returns
    /// * The amount of assets that can be withdrawn [asset scale]
    fn calculate_withdrawable_assets(asset_config: AssetConfig, total_debt: u256) -> u256 {
        let scale = asset_config.scale;
        let utilization = total_debt * SCALE / (asset_config.reserve + total_debt);
        if utilization > asset_config.max_utilization {
            return 0;
        }
        (asset_config.reserve + total_debt) - (total_debt * ((SCALE * scale) / asset_config.max_utilization)) / scale
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// Returns the address of the singleton
        fn singleton(self: @ContractState) -> ISingletonDispatcher {
            ISingletonDispatcher {
                contract_address: IExtensionDispatcher { contract_address: self.extension.read() }.singleton()
            }
        }

        /// Returns true if the pool accepts deposits
        fn can_deposit(self: @ContractState) -> bool {
            let shutdown_status = IDefaultExtensionDispatcher { contract_address: self.extension.read() }
                .shutdown_status(self.pool_id.read(), self.asset.read(), Zeroable::zero());
            !(shutdown_status.shutdown_mode == ShutdownMode::Subscription
                || shutdown_status.shutdown_mode == ShutdownMode::Redemption)
        }

        /// Returns true if the pool allows for withdrawals
        fn can_withdraw(self: @ContractState) -> bool {
            let shutdown_status = IDefaultExtensionDispatcher { contract_address: self.extension.read() }
                .shutdown_status(self.pool_id.read(), self.asset.read(), Zeroable::zero());
            !(shutdown_status.shutdown_mode == ShutdownMode::Recovery
                || shutdown_status.shutdown_mode == ShutdownMode::Subscription)
        }

        /// See the `calculate_withdrawable_assets`.
        fn calculate_withdrawable_assets(self: @ContractState, asset_config: AssetConfig) -> u256 {
            let total_debt = self
                .singleton()
                .calculate_debt(
                    i257_new(asset_config.total_nominal_debt, false),
                    asset_config.last_rate_accumulator,
                    asset_config.scale
                );
            calculate_withdrawable_assets(asset_config, total_debt)
        }

        /// Transfers an amount of assets from sender to receiver
        fn transfer_asset(self: @ContractState, sender: ContractAddress, to: ContractAddress, amount: u256) {
            let asset = self.asset.read();
            let is_legacy = self.is_legacy.read();
            let erc20 = IERC20Dispatcher { contract_address: asset };
            if sender == get_contract_address() {
                assert!(erc20.transfer(to, amount), "transfer-failed");
            } else if is_legacy {
                assert!(erc20.transferFrom(sender, to, amount), "transferFrom-failed");
            } else {
                assert!(erc20.transfer_from(sender, to, amount), "transfer-from-failed");
            }
        }
    }

    #[abi(embed_v0)]
    impl VToken of super::IVToken<ContractState> {
        /// Returns the address of the extension associated with the vToken
        /// # Returns
        /// * address of the extension
        fn extension(self: @ContractState) -> ContractAddress {
            self.extension.read()
        }

        /// Returns the id of the pool in which the vToken's underlying asset is deposited into
        /// # Returns
        /// * id of the pool
        fn pool_id(self: @ContractState) -> felt252 {
            self.pool_id.read()
        }

        /// Re-approves the vToken to be spendable by the extension
        fn approve_extension(ref self: ContractState) {
            self.erc20._approve(get_contract_address(), self.extension.read(), Bounded::<u256>::MAX);
        }

        /// Permissioned minting of vTokens. Can only be called by the associated extension.
        /// # Arguments
        /// * `recipient` - address to mint the vToken to
        /// * `amount` - amount of vToken to mint [SCALE]
        /// # Returns
        /// * true if the minting was successful
        fn mint_v_token(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            assert!(get_caller_address() == self.extension.read(), "caller-not-extension");
            self.erc20._mint(recipient, amount);
            true
        }

        /// Permissioned burning of vTokens. Can only be called by the associated extension.
        /// `from` needs to approve the extension to burn the vToken.
        /// # Arguments
        /// * `from` - address to burn the vToken from
        /// * `amount` - amount of vToken to burn [SCALE]
        /// # Returns
        /// * true if the burning was successful
        fn burn_v_token(ref self: ContractState, from: ContractAddress, amount: u256) -> bool {
            assert!(get_caller_address() == self.extension.read(), "caller-not-extension");
            self.erc20._spend_allowance(from, get_caller_address(), amount);
            self.erc20._burn(from, amount);
            true
        }
    }

    #[abi(embed_v0)]
    impl IERC4626 of super::IERC4626<ContractState> {
        /// Returns the address of the underlying asset of the vToken
        /// # Returns
        /// * address of the asset
        fn asset(self: @ContractState) -> ContractAddress {
            self.asset.read()
        }

        /// Returns the total amount of underlying assets deposited via the vToken
        /// # Returns
        /// * total amount of assets [asset scale]
        fn total_assets(self: @ContractState) -> u256 {
            self
                .singleton()
                .calculate_collateral_unsafe(
                    self.pool_id.read(), self.asset.read(), i257_new(self.erc20.total_supply(), true)
                )
        }

        /// Converts an amount of assets to the equivalent amount of vToken shares
        /// # Arguments
        /// * `assets` - amount of assets to convert [asset scale]
        /// # Returns
        /// * amount of vToken shares [SCALE]
        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            self
                .singleton()
                .calculate_collateral_shares_unsafe(self.pool_id.read(), self.asset.read(), i257_new(assets, false))
        }

        /// Converts an amount of vToken shares to the equivalent amount of assets
        /// # Arguments
        /// * `shares` - amount of vToken shares to convert [SCALE]
        /// # Returns
        /// * amount of assets [asset scale]
        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            self.singleton().calculate_collateral_unsafe(self.pool_id.read(), self.asset.read(), i257_new(shares, true))
        }

        /// Returns the maximum amount of assets that can be deposited via the vToken
        /// # Arguments
        /// * `receiver` - address to receive the vToken shares
        /// # Returns
        /// * maximum amount of assets [asset scale]
        fn max_deposit(self: @ContractState, receiver: ContractAddress) -> u256 {
            if !self.can_deposit() {
                return 0;
            }
            let (asset_config, _) = self.singleton().asset_config_unsafe(self.pool_id.read(), self.asset.read());
            let room = integer::BoundedU128::max().into() - asset_config.total_collateral_shares;
            self.singleton().calculate_collateral_unsafe(self.pool_id.read(), self.asset.read(), i257_new(room, false))
        }

        /// Returns the amount of vToken shares that will be minted for the given amount of deposited assets
        /// # Arguments
        /// * `assets` - amount of assets to deposit [asset scale]
        /// # Returns
        /// * amount of vToken shares minted [SCALE]
        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            if !self.can_deposit() {
                return 0;
            }
            self
                .singleton()
                .calculate_collateral_shares_unsafe(self.pool_id.read(), self.asset.read(), i257_new(assets, false))
        }

        /// Deposits assets into the pool and mints vTokens (shares) to the receiver
        /// # Arguments
        /// * `assets` - amount of assets to deposit [asset scale]
        /// * `receiver` - address to receive the vToken shares
        /// # Returns
        /// * amount of vToken shares minted [SCALE]
        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            self.transfer_asset(get_caller_address(), get_contract_address(), assets);

            let params = ModifyPositionParams {
                pool_id: self.pool_id.read(),
                collateral_asset: self.asset.read(),
                debt_asset: Zeroable::zero(),
                user: self.extension.read(),
                collateral: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257_new(assets, false),
                },
                debt: Default::default(),
                data: ArrayTrait::new().span()
            };

            let shares = self.singleton().modify_position(params).collateral_shares_delta.abs;

            self.erc20._mint(receiver, shares);

            self.emit(Deposit { sender: get_caller_address(), owner: receiver, assets, shares });

            shares
        }

        /// Returns the maximum amount of vToken shares that can be minted
        /// # Arguments
        /// * `receiver` - address to receive the vToken shares
        /// # Returns
        /// * maximum amount of vToken shares minted [SCALE]
        fn max_mint(self: @ContractState, receiver: ContractAddress) -> u256 {
            if !self.can_deposit() {
                return 0;
            }
            let (asset_config, _) = self.singleton().asset_config_unsafe(self.pool_id.read(), self.asset.read());
            integer::BoundedU128::max().into() - asset_config.total_collateral_shares
        }

        /// Returns the amount of assets that will be deposited for a given amount of minted vToken shares
        /// # Arguments
        /// * `shares` - amount of vToken shares to mint [SCALE]
        /// # Returns
        /// * amount of assets deposited [asset scale]
        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            if !self.can_deposit() {
                return 0;
            }
            self
                .singleton()
                .calculate_collateral_unsafe(self.pool_id.read(), self.asset.read(), i257_new(shares, false))
        }

        /// Mints vToken shares to the receiver by depositing assets into the pool
        /// # Arguments
        /// * `shares` - amount of vToken shares to mint [SCALE]
        /// * `receiver` - address to receive the vToken shares
        /// # Returns
        /// * amount of assets deposited [asset scale]
        fn mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            let assets_estimate = self
                .singleton()
                .calculate_collateral(self.pool_id.read(), self.asset.read(), i257_new(shares, false));

            // transfer an estimated amount of assets to the contract first to ensure that minting of vTokens
            // happens after the deposit
            self.transfer_asset(get_caller_address(), get_contract_address(), assets_estimate);

            let params = ModifyPositionParams {
                pool_id: self.pool_id.read(),
                collateral_asset: self.asset.read(),
                debt_asset: Zeroable::zero(),
                user: self.extension.read(),
                collateral: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Native,
                    value: i257_new(shares, false),
                },
                debt: Default::default(),
                data: ArrayTrait::new().span()
            };

            let response = self.singleton().modify_position(params);
            let assets = response.collateral_delta.abs;
            // take inflation fee into account for the first deposit
            let shares = response.collateral_shares_delta.abs;

            self.erc20._mint(receiver, shares);

            // refund the difference between the estimated and actual amount of assets
            self.transfer_asset(get_contract_address(), get_caller_address(), assets_estimate - assets);

            self.emit(Deposit { sender: get_caller_address(), owner: receiver, assets, shares });

            assets
        }

        /// Returns the maximum amount of assets that can be withdrawn by the owner of the vToken shares
        /// # Arguments
        /// * `owner` - address of the owner of the vToken shares
        /// # Returns
        /// * maximum amount of assets [asset scale]
        fn max_withdraw(self: @ContractState, owner: ContractAddress) -> u256 {
            if !self.can_withdraw() {
                return 0;
            }
            let (asset_config, _) = self.singleton().asset_config_unsafe(self.pool_id.read(), self.asset.read());

            let room = self.calculate_withdrawable_assets(asset_config);
            let assets = self
                .singleton()
                .calculate_collateral_unsafe(
                    self.pool_id.read(), self.asset.read(), i257_new(self.erc20.balance_of(owner), true)
                );

            if assets > room {
                room
            } else {
                assets
            }
        }

        /// Returns the amount of vToken shares that will be burned for a given amount of withdrawn assets
        /// # Arguments
        /// * `assets` - amount of assets to withdraw [asset scale]
        /// # Returns
        /// * amount of vToken shares burned [SCALE]
        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            if !self.can_withdraw() {
                return 0;
            }
            self
                .singleton()
                .calculate_collateral_shares_unsafe(self.pool_id.read(), self.asset.read(), i257_new(assets, true))
        }

        /// Withdraws assets from the pool and burns vTokens (shares) from the owner of the vTokens
        /// # Arguments
        /// * `assets` - amount of assets to withdraw [asset scale]
        /// * `receiver` - address to receive the withdrawn assets
        /// * `owner` - address of the owner of the vToken shares
        /// # Returns
        /// * amount of vTokens (shares) burned [SCALE]
        fn withdraw(ref self: ContractState, assets: u256, receiver: ContractAddress, owner: ContractAddress) -> u256 {
            let params = ModifyPositionParams {
                pool_id: self.pool_id.read(),
                collateral_asset: self.asset.read(),
                debt_asset: Zeroable::zero(),
                user: self.extension.read(),
                collateral: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Assets,
                    value: i257_new(assets, true),
                },
                debt: Default::default(),
                data: ArrayTrait::new().span()
            };

            let shares = self.singleton().modify_position(params).collateral_shares_delta.abs;

            if get_caller_address() != owner {
                self.erc20._spend_allowance(owner, get_caller_address(), shares);
            }
            self.erc20._burn(owner, shares);

            self.transfer_asset(get_contract_address(), receiver, assets);

            self.emit(Withdraw { sender: get_caller_address(), receiver, owner, assets, shares });

            shares
        }

        /// Returns the maximum amount of vToken shares that can be redeemed by the owner of the vTokens (shares)
        /// # Arguments
        /// * `owner` - address of the owner
        /// # Returns
        /// * maximum amount of vToken shares [SCALE]
        fn max_redeem(self: @ContractState, owner: ContractAddress) -> u256 {
            if !self.can_withdraw() {
                return 0;
            }
            let (asset_config, _) = self.singleton().asset_config_unsafe(self.pool_id.read(), self.asset.read());
            let room = self
                .singleton()
                .calculate_collateral_shares_unsafe(
                    self.pool_id.read(),
                    self.asset.read(),
                    i257_new(self.calculate_withdrawable_assets(asset_config), true)
                );
            let shares = self.erc20.balance_of(owner);

            if shares > room {
                room
            } else {
                shares
            }
        }

        /// Returns the amount of assets that will be withdrawn for a given amount of redeemed / burned vTokens (shares)
        /// # Arguments
        /// * `shares` - amount of vToken shares to redeem [SCALE]
        /// # Returns
        /// * amount of assets withdrawn [asset scale]
        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            if !self.can_withdraw() {
                return 0;
            }
            self.singleton().calculate_collateral_unsafe(self.pool_id.read(), self.asset.read(), i257_new(shares, true))
        }

        /// Redeems / burns vTokens (shares) from the owner and withdraws assets from the pool
        /// # Arguments
        /// * `shares` - amount of vToken shares to redeem [SCALE]
        /// * `receiver` - address to receive the withdrawn assets
        /// * `owner` - address of the owner of the vToken shares
        /// # Returns
        /// * amount of assets withdrawn [asset scale]
        fn redeem(ref self: ContractState, shares: u256, receiver: ContractAddress, owner: ContractAddress) -> u256 {
            if get_caller_address() != owner {
                self.erc20._spend_allowance(owner, get_caller_address(), shares);
            }
            self.erc20._burn(owner, shares);

            let params = ModifyPositionParams {
                pool_id: self.pool_id.read(),
                collateral_asset: self.asset.read(),
                debt_asset: Zeroable::zero(),
                user: self.extension.read(),
                collateral: Amount {
                    amount_type: AmountType::Delta,
                    denomination: AmountDenomination::Native,
                    value: i257_new(shares, true),
                },
                debt: Default::default(),
                data: ArrayTrait::new().span()
            };

            let assets = self.singleton().modify_position(params).collateral_delta.abs;

            self.transfer_asset(get_contract_address(), receiver, assets);

            self.emit(Withdraw { sender: get_caller_address(), receiver, owner, assets, shares });

            assets
        }
    }
}
