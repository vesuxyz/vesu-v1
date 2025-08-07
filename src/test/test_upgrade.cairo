#[cfg(test)]
mod TestUpgrade {
    use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
    use snforge_std::{
        DeclareResultTrait, declare, get_class_hash, start_cheat_caller_address, stop_cheat_caller_address,
    };
    #[feature("deprecated-starknet-consts")]
    use starknet::contract_address_const;
    use vesu::extension::default_extension_po_v2::{
        IDefaultExtensionPOV2Dispatcher, IDefaultExtensionPOV2DispatcherTrait,
    };
    use vesu::singleton_v2::{ISingletonV2Dispatcher, ISingletonV2DispatcherTrait};

    fn setup(pool_id: felt252) -> (ISingletonV2Dispatcher, IDefaultExtensionPOV2Dispatcher) {
        let singleton = ISingletonV2Dispatcher {
            contract_address: contract_address_const::<
                0x000d8d6dfec4d33bfb6895de9f3852143a17c6f92fd2a21da3d6924d34870160,
            >(),
        };
        let extension = IDefaultExtensionPOV2Dispatcher { contract_address: singleton.extension(pool_id) };
        (singleton, extension)
    }

    #[test]
    #[fork("Mainnet")]
    fn test_upgrade() {
        let pool_id = 0x4dc4f0ca6ea4961e4c8373265bfd5317678f4fe374d76f3fd7135f57763bf28;
        let (singleton, extension) = setup(pool_id);

        let owner = IOwnableDispatcher { contract_address: singleton.contract_address }.owner();
        let singleton_v1_class_hash = get_class_hash(singleton.contract_address);
        let singleton_v2_class_hash = *declare("SingletonV2").unwrap().contract_class().class_hash;
        let extension_v1_class_hash = get_class_hash(extension.contract_address);
        let extension_v2_class_hash = *declare("DefaultExtensionPOV2").unwrap().contract_class().class_hash;

        let pool_ids = array![
            0x4dc4f0ca6ea4961e4c8373265bfd5317678f4fe374d76f3fd7135f57763bf28 // 0x3de03fafe6120a3d21dc77e101de62e165b2cdfe84d12540853bd962b970f99,
            // 0x52fb52363939c3aa848f8f4ac28f0a51379f8d1b971d8444de25fbd77d8f161,
        // 0x2e06b705191dbe90a3fbaad18bb005587548048b725116bff3104ca501673c1,
        // 0x6febb313566c48e30614ddab092856a9ab35b80f359868ca69b2649ca5d148d,
        // 0x59ae5a41c9ae05eae8d136ad3d7dc48e5a0947c10942b00091aeb7f42efabb7,
        // 0x43f475012ed51ff6967041fcb9bf28672c96541ab161253fc26105f4c3b2afe,
        // 0x7bafdbd2939cc3f3526c587cb0092c0d9a93b07b9ced517873f7f6bf6c65563,
        // 0x7f135b4df21183991e9ff88380c2686dd8634fd4b09bb2b5b14415ac006fe1d,
        // 0x27f2bb7fb0e232befc5aa865ee27ef82839d5fad3e6ec1de598d0fab438cb56,
        // 0x5c678347b60b99b72f245399ba27900b5fc126af11f6637c04a193d508dda26,
        // 0x2906e07881acceff9e4ae4d9dacbcd4239217e5114001844529176e1f0982ec
        ];

        let assets = array![
            contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
            contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>(),
            contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            contract_address_const::<0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8>(),
            contract_address_const::<0x042b8f0484674ca266ac5d08e4ac6a3fe65bd3129795def2dca5c34ecc5f96d2>(),
            contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
            contract_address_const::<0x0057912720381af14b0e5c87aa4718ed5e527eab60b3801ebf702ab09139e38b>(),
            contract_address_const::<0x075afe6402ad5a5c20dd25e10ec3b3986acaa647b77e4ae24b0cbc9a54a27a87>(),
            contract_address_const::<0x028d709c875c0ceac3dce7065bec5328186dc89fe254527084d1689910954b0a>(),
            contract_address_const::<0x0356f304b154d29d2A8fe22F1CB9107A9B564A733Cf6b4CC47fd121Ac1af90C9>(),
            contract_address_const::<0x2019e47a0bc54ea6b4853c6123ffc8158ea3ae2af4166928b0de6e89f06de6c>(),
            contract_address_const::<0x498edfaf50ca5855666a700c25dd629d577eb9afccdf3b5977aec79aee55ada>(),
        ];

        let users = array![
            [
                contract_address_const::<0x0000ca90c16bae26ef5bccf692401618c18b47ad3250ef10c804111da5eaebbc>(),
                contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
                contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            ],
            [
                contract_address_const::<0x0007e17ab90d2abf29b1a2b418567067d7f1ce49602feb29ac11901e35fb965e>(),
                contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
                contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            ],
            [
                contract_address_const::<0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233>(),
                contract_address_const::<0x0057912720381af14b0e5c87aa4718ed5e527eab60b3801ebf702ab09139e38b>(),
                contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
            ],
            [
                contract_address_const::<0x0013c4989c2e1317a8380c9bb8e2f6c978a325fd9cad3346eebcf7d9fcd032bb>(),
                contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
                contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            ],
            [
                contract_address_const::<0x0040859b1e46605a971537d20687e04c01b782f5878709ab308a0edef84bf551>(),
                contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
                contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
            ],
            [
                contract_address_const::<0x00474be27117d9f436591266e7ad2ed84e04c086824a322b46364e7b7305f66a>(),
                contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
                contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            ],
            [
                contract_address_const::<0x004b39b8c5038b7740fcd63341d89df4d1880b5e4ee7479858ea85ded39af76f>(),
                contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
                contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            ],
            [
                contract_address_const::<0x0051e7e265f8973c867997df832f4e12a1eb1ef0e4cf6b22c5c3ecb412113718>(),
                contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
                contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
            ],
            [
                contract_address_const::<0x0055741fd3ec832f7b9500e24a885b8729f213357be4a8e209c4bca1f3b909ae>(),
                contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>(),
                contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
            ],
            [
                contract_address_const::<0x006068a9adb468aca6f9d52971e2f0d96f25383afe37441f6b72a8d5f3631689>(),
                contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>(),
                contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>(),
            ],
        ];

        start_cheat_caller_address(singleton.contract_address, owner);

        let mut i = 0;
        while i < pool_ids.len() {
            let pool_id = *pool_ids.at(i);

            singleton.upgrade(singleton_v1_class_hash);
            let extension = singleton.extension(pool_id);
            let creator_nonce = singleton.creator_nonce(extension);
            singleton.upgrade(singleton_v2_class_hash);
            assert!(extension == singleton.extension(pool_id));
            assert!(creator_nonce == singleton.creator_nonce(extension));

            let assets_copy = assets.clone();
            let mut j = 0;
            while j < assets_copy.len() {
                let collateral_asset = *assets_copy.at(j);

                singleton.upgrade(singleton_v1_class_hash);
                let asset_config = singleton.asset_config(pool_id, collateral_asset);
                singleton.upgrade(singleton_v2_class_hash);
                assert!(asset_config == singleton.asset_config(pool_id, collateral_asset));

                let assets_copy = assets_copy.clone();
                let mut k = 0;
                while k < assets_copy.len() {
                    let debt_asset = *assets_copy.at(k);

                    singleton.upgrade(singleton_v1_class_hash);
                    let ltv_config = singleton.ltv_config(pool_id, collateral_asset, debt_asset);
                    singleton.upgrade(singleton_v2_class_hash);
                    assert!(ltv_config == singleton.ltv_config(pool_id, collateral_asset, debt_asset));

                    k += 1;
                }

                j += 1;
            }

            i += 1;
        }

        let mut i = 0;
        while i < users.len() {
            let [user, collateral_asset, debt_asset] = *users.at(i);

            singleton.upgrade(singleton_v1_class_hash);
            let position = singleton.position(pool_id, collateral_asset, debt_asset, user);
            singleton.upgrade(singleton_v2_class_hash);
            assert!(position == singleton.position(pool_id, collateral_asset, debt_asset, user));

            i += 1;
        }

        start_cheat_caller_address(extension.contract_address, owner);

        let mut i = 0;
        while i < pool_ids.len() {
            let pool_id = *pool_ids.at(i);

            extension.upgrade(extension_v1_class_hash);
            let pool_name = extension.pool_name(pool_id);
            let pool_owner = extension.pool_owner(pool_id);
            let shutdown_mode_agent = extension.shutdown_mode_agent(pool_id);
            let fee_config = extension.fee_config(pool_id);
            let shutdown_config = extension.shutdown_config(pool_id);
            extension.upgrade(extension_v2_class_hash);
            assert!(pool_name == extension.pool_name(pool_id));
            assert!(pool_owner == extension.pool_owner(pool_id));
            assert!(shutdown_mode_agent == extension.shutdown_mode_agent(pool_id));
            assert!(fee_config == extension.fee_config(pool_id));
            assert!(shutdown_config == extension.shutdown_config(pool_id));

            let assets_copy = assets.clone();
            let mut j = 0;
            while j < assets_copy.len() {
                let collateral_asset = *assets_copy.at(j);

                extension.upgrade(extension_v1_class_hash);
                let oracle_config = extension.oracle_config(pool_id, collateral_asset);
                let interest_rate_config = extension.interest_rate_config(pool_id, collateral_asset);
                let v_token_for_collateral_asset = extension.v_token_for_collateral_asset(pool_id, collateral_asset);
                let collateral_asset_for_v_token = extension
                    .collateral_asset_for_v_token(pool_id, v_token_for_collateral_asset);
                extension.upgrade(extension_v2_class_hash);
                assert!(oracle_config == extension.oracle_config(pool_id, collateral_asset));
                assert!(interest_rate_config == extension.interest_rate_config(pool_id, collateral_asset));
                assert!(
                    v_token_for_collateral_asset == extension.v_token_for_collateral_asset(pool_id, collateral_asset),
                );
                assert!(
                    collateral_asset_for_v_token == extension
                        .collateral_asset_for_v_token(pool_id, v_token_for_collateral_asset),
                );

                let assets_copy = assets_copy.clone();
                let mut k = 0;
                while k < assets_copy.len() {
                    let debt_asset = *assets_copy.at(k);

                    extension.upgrade(extension_v1_class_hash);
                    let debt_cap = extension.debt_caps(pool_id, collateral_asset, debt_asset);
                    let liquidation_config = extension.liquidation_config(pool_id, collateral_asset, debt_asset);
                    let shutdown_ltv_config = extension.shutdown_ltv_config(pool_id, collateral_asset, debt_asset);
                    let pairs = extension.pairs(pool_id, collateral_asset, debt_asset);
                    // let shutdown_status = extension.shutdown_status(pool_id, collateral_asset, debt_asset);
                    extension.upgrade(extension_v2_class_hash);
                    assert!(debt_cap == extension.debt_caps(pool_id, collateral_asset, debt_asset));
                    assert!(liquidation_config == extension.liquidation_config(pool_id, collateral_asset, debt_asset));
                    assert!(
                        shutdown_ltv_config == extension.shutdown_ltv_config(pool_id, collateral_asset, debt_asset),
                    );
                    // assert!(shutdown_status == extension.shutdown_status(pool_id, collateral_asset, debt_asset));
                    assert!(pairs == extension.pairs(pool_id, collateral_asset, debt_asset));

                    k += 1;
                }

                j += 1;
            }

            i += 1;
        }
        stop_cheat_caller_address(extension.contract_address);
    }
}
