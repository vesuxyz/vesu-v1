#[cfg(test)]
mod TestForking {
    use snforge_std::{start_prank, stop_prank, CheatTarget};
    use starknet::{contract_address_const};
    use vesu::{test::setup::{setup_pool}, extension::interface::{IExtensionDispatcher, IExtensionDispatcherTrait}};

    #[test]
    #[fork("Mainnet")]
    fn test_forking() {
        let (_, extension, config, _, _) = setup_pool(
            contract_address_const::<0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b>(),
            contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>(),
            contract_address_const::<0x070a76fd48ca0ef910631754d77dd822147fe98a569b826ec85e3c33fde586ac>(),
            contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>(),
            false,
            Option::None,
        );

        let price = IExtensionDispatcher { contract_address: extension.contract_address }
            .price(config.pool_id, config.collateral_asset.contract_address);

        assert!(price.value > 0, "No data");
    }
}
