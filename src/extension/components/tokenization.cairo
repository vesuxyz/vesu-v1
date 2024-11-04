#[starknet::component]
mod tokenization_component {
    use alexandria_math::i257::i257;
    use integer::BoundedInt;
    use starknet::{ContractAddress, get_contract_address, deploy_syscall};
    use vesu::{
        units::SCALE, data_model::Amount, singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
        extension::default_extension_po::IDefaultExtensionCallback, v_token::{IVTokenDispatcher, IVTokenDispatcherTrait}
    };

    #[storage]
    struct Storage {
        // class hash of the vToken contract
        v_token_class_hash: felt252,
        // tracks the collateral asset for each vToken in a pool
        // (pool_id, vToken) -> collateral_asset
        collateral_asset_for_v_token: LegacyMap::<(felt252, ContractAddress), ContractAddress>,
        // tracks the vToken for each collateral asset in a pool
        // (pool_id, collateral_asset) -> vToken
        v_token_for_collateral_asset: LegacyMap::<(felt252, ContractAddress), ContractAddress>
    }

    #[derive(Drop, starknet::Event)]
    struct CreateVToken {
        #[key]
        v_token: ContractAddress,
        #[key]
        pool_id: felt252,
        #[key]
        collateral_asset: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CreateVToken: CreateVToken,
    }

    #[generate_trait]
    impl TokenizationTrait<
        TContractState, +HasComponent<TContractState>, +IDefaultExtensionCallback<TContractState>
    > of Trait<TContractState> {
        /// Sets the class hash from which all vTokens are deployed.
        /// # Arguments
        /// * `v_token_class_hash` - The class hash of the vToken contract
        fn set_v_token_class_hash(ref self: ComponentState<TContractState>, v_token_class_hash: felt252) {
            assert!(self.v_token_class_hash.read() == Zeroable::zero(), "already-set");
            self.v_token_class_hash.write(v_token_class_hash);
        }

        /// Returns the address of the vToken contract for a given collateral asset.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// # Returns
        /// * address of the vToken contract
        fn v_token_for_collateral_asset(
            self: @ComponentState<TContractState>, pool_id: felt252, collateral_asset: ContractAddress
        ) -> ContractAddress {
            self.v_token_for_collateral_asset.read((pool_id, collateral_asset))
        }

        /// Returns the address of the collateral asset for a given vToken.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `v_token` - address of the vToken contract
        /// # Returns
        /// * address of the collateral asset
        fn collateral_asset_for_v_token(
            self: @ComponentState<TContractState>, pool_id: felt252, v_token: ContractAddress
        ) -> ContractAddress {
            self.collateral_asset_for_v_token.read((pool_id, v_token))
        }

        /// Creates a vToken contract for a given collateral asset.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `v_token_name` - name of the vToken
        /// * `v_token_symbol` - symbol of the vToken
        fn create_v_token(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            v_token_name: felt252,
            v_token_symbol: felt252
        ) {
            assert!(
                self.v_token_for_collateral_asset.read((pool_id, collateral_asset)) == Zeroable::zero(),
                "v-token-already-created"
            );

            let (v_token, _) = (deploy_syscall(
                self.v_token_class_hash.read().try_into().unwrap(),
                0,
                array![
                    v_token_name.into(),
                    v_token_symbol.into(),
                    18,
                    pool_id,
                    get_contract_address().into(),
                    collateral_asset.into()
                ]
                    .span(),
                false
            ))
                .unwrap();

            self.v_token_for_collateral_asset.write((pool_id, collateral_asset), v_token);
            self.collateral_asset_for_v_token.write((pool_id, v_token), collateral_asset);

            ISingletonDispatcher { contract_address: self.get_contract().singleton() }
                .modify_delegation(pool_id, v_token, true);

            self.emit(CreateVToken { v_token, pool_id, collateral_asset });
        }

        /// Mints or burns vTokens for a user for a given collateral asset.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `user` - address of the user
        /// * `amount` - amount of vTokens to mint or burn (positive for minting, negative for burning)
        fn mint_or_burn_v_token(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            user: ContractAddress,
            amount: i257
        ) {
            let v_token = self.v_token_for_collateral_asset.read((pool_id, collateral_asset));
            assert!(v_token != Zeroable::zero(), "unknown-collateral-asset");
            if amount > Zeroable::zero() {
                IVTokenDispatcher { contract_address: v_token }.mint_v_token(user, amount.abs);
            } else if amount < Zeroable::zero() {
                IVTokenDispatcher { contract_address: v_token }.burn_v_token(user, amount.abs);
            }
        }
    }
}
