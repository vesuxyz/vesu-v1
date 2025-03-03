#[cfg(test)]
mod TestEkuboOracle {
    use snforge_std::{declare, ContractClass, ContractClassTrait};
    use starknet::{ContractAddress, contract_address_const};
    use vesu::{
        singleton::{ISingletonDispatcherTrait, ISingletonDispatcher},
        test::{
            setup::{create_pool_v3, deploy_asset_with_decimals, setup_env_v3, TestConfigV3, EnvV3},
            mock_ekubo_oracle::{IMockEkuboOracleDispatcher, IMockEkuboOracleDispatcherTrait}
        },
        extension::{
            interface::{IExtensionDispatcher, IExtensionDispatcherTrait},
            default_extension_ek::{IDefaultExtensionEKDispatcherTrait, IDefaultExtensionEKDispatcher,}
        },
        math::pow_10, vendor::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait},
    };

    fn setup_env_v3_with_asset_decimals(
        collateral_asset_decimals: u32, debt_asset_decimals: u32, third_asset_decimals: u32, quote_asset_decimals: u32
    ) -> EnvV3 {
        let class = declare("MockAsset");
        let lender = contract_address_const::<'lender'>();

        let decimals = collateral_asset_decimals;
        let supply = 100 * pow_10(decimals);
        let calldata = array![
            'Collateral', 'COLL', collateral_asset_decimals.into(), supply.low.into(), supply.high.into(), lender.into()
        ];
        let collateral_asset = IERC20Dispatcher { contract_address: class.deploy(@calldata).unwrap() };

        let decimals = debt_asset_decimals;
        let supply = 100 * pow_10(decimals);
        let calldata = array![
            'Debt', 'DEBT', debt_asset_decimals.into(), supply.low.into(), supply.high.into(), lender.into()
        ];
        let debt_asset = IERC20Dispatcher { contract_address: class.deploy(@calldata).unwrap() };

        let decimals = third_asset_decimals;
        let supply = 100 * pow_10(decimals);
        let calldata = array![
            'Third', 'THIRD', third_asset_decimals.into(), supply.low.into(), supply.high.into(), lender.into()
        ];
        let third_asset = IERC20Dispatcher { contract_address: class.deploy(@calldata).unwrap() };

        let decimals = quote_asset_decimals;
        let supply = 100 * pow_10(decimals);
        let calldata = array![
            'Quote', 'QUOTE', quote_asset_decimals.into(), supply.low.into(), supply.high.into(), lender.into()
        ];
        let quote_asset = IERC20Dispatcher { contract_address: class.deploy(@calldata).unwrap() };

        setup_env_v3(
            Zeroable::zero(),
            collateral_asset.contract_address,
            debt_asset.contract_address,
            third_asset.contract_address,
            quote_asset.contract_address,
            Zeroable::zero(),
            Zeroable::zero(),
        )
    }

    // Test Ekubo price calculation in the case where quote token has less decimals than assets
    // with actual values from Ekubo's oracle extension.
    // - collateral_asset (18 decimals): ETH
    // - third_asset (8 decimals): WBTC
    // - quote_asset (6 decimals): USDC
    #[test]
    fn test_get_ekubo_price_quote_asset_less_decimals() {
        let collateral_asset_decimals = 6;
        let debt_asset_decimals = 8;
        let third_asset_decimals = 18;
        let quote_asset_decimals = 6;

        let EnvV3 { extension_v3, config, users, .. } = setup_env_v3_with_asset_decimals(
            collateral_asset_decimals, debt_asset_decimals, third_asset_decimals, quote_asset_decimals
        );
        let TestConfigV3 { collateral_asset, debt_asset, third_asset, quote_asset, .. } = config;
        let default_extension_ek = extension_v3;

        create_pool_v3(extension_v3, config, users.creator, Option::None);
        let TestConfigV3 { pool_id_v3, .. } = config;

        let extension_dispatcher = IExtensionDispatcher { contract_address: default_extension_ek.contract_address };

        let ekubo_oracle = IMockEkuboOracleDispatcher { contract_address: default_extension_ek.ekubo_oracle() };

        // Collateral asset has 6 decimals
        let collateral_asset_x128_price: u256 = 340494428779909422801741109997065403040;
        ekubo_oracle
            .set_price_x128(
                collateral_asset.contract_address, quote_asset.contract_address, collateral_asset_x128_price
            );

        // Compare with expected python value in Decimal
        // (Decimal(x128_price) * 10 ** (6 - 6) / 2 ** 128) * 10 ** 18
        let expected_collateral_asset_price: u256 = 1000623193793113088; // USDT/USDC price: 1.0006..
        let collateral_asset_price = extension_dispatcher.price(pool_id_v3, collateral_asset.contract_address);
        assert!(collateral_asset_price.value == expected_collateral_asset_price, "Collateral price incorrect");

        // Debt asset has 8 decimals
        let debt_asset_x128_price: u256 = 352091474990938760796322068375316664912385;
        ekubo_oracle.set_price_x128(debt_asset.contract_address, quote_asset.contract_address, debt_asset_x128_price);

        // Compare with expected python value in Decimal
        // (Decimal(x128_price) * 10 ** (8 - 6) / 2 ** 128) * 10 ** 18
        let expected_debt_asset_price: u256 = 103470384956133809014853; // WBTC/USDC price: 103_470.38...
        let debt_asset_price = extension_dispatcher.price(pool_id_v3, debt_asset.contract_address);
        assert!(debt_asset_price.value == expected_debt_asset_price, "Debt price incorrect");

        // Third asset has 18 decimals
        let third_asset_x128_price: u256 = 1302125608316082645435784522106;
        ekubo_oracle.set_price_x128(third_asset.contract_address, quote_asset.contract_address, third_asset_x128_price);

        // Compare with expected python value in Decimal
        // (Decimal(x128_price) * 10 ** (18 - 6) / 2 ** 128) * 10 ** 18
        let expected_third_asset_price: u256 = 3826603241591474463418; // ETH/USDC price: 3_826.60...
        let third_asset_price = extension_dispatcher.price(pool_id_v3, third_asset.contract_address);
        assert!(third_asset_price.value == expected_third_asset_price, "Third asset price incorrect");
    }

    // Test Ekubo price calculation in the case where quote token has more decimals than assets
    // with actual values from Ekubo's oracle extension.
    // - collateral_asset (6 decimals): USDC
    // - third_asset (8 decimals): WBTC
    // - quote_asset (18 decimals): ETH
    #[test]
    fn test_get_ekubo_price_quote_asset_more_decimals() {
        let collateral_asset_decimals = 6;
        let debt_asset_decimals = 8;
        let third_asset_decimals = 18;
        let quote_asset_decimals = 18;

        let EnvV3 { extension_v3, config, users, .. } = setup_env_v3_with_asset_decimals(
            collateral_asset_decimals, debt_asset_decimals, third_asset_decimals, quote_asset_decimals
        );
        let TestConfigV3 { collateral_asset, debt_asset, third_asset, quote_asset, .. } = config;
        let default_extension_ek = extension_v3;

        create_pool_v3(extension_v3, config, users.creator, Option::None);
        let TestConfigV3 { pool_id_v3, .. } = config;

        let extension_dispatcher = IExtensionDispatcher { contract_address: default_extension_ek.contract_address };

        let ekubo_oracle = IMockEkuboOracleDispatcher { contract_address: default_extension_ek.ekubo_oracle() };

        // Collateral asset has 6 decimals
        let collateral_asset_x128_price: u256 = 88397018286004152788406389410990271944458724276;
        ekubo_oracle
            .set_price_x128(
                collateral_asset.contract_address, quote_asset.contract_address, collateral_asset_x128_price
            );

        // Compare with expected python value in Decimal
        // (Decimal(x128_price) / 10 ** (18 - 6) / 2 ** 128) * 10 ** 18
        let expected_collateral_asset_price: u256 = 259775489061830; // USDC/ETH price: 0.00025...
        let collateral_asset_price = extension_dispatcher.price(pool_id_v3, collateral_asset.contract_address);
        assert!(collateral_asset_price.value == expected_collateral_asset_price, "Collateral price incorrect");

        // Debt asset has 8 decimals
        let debt_asset_x128_price: u256 = 91518349125612368443571711893252661971104731310540;
        ekubo_oracle.set_price_x128(debt_asset.contract_address, quote_asset.contract_address, debt_asset_x128_price);

        // Compare with expected python value in Decimal
        // (Decimal(x128_price) / 10 ** (18 - 8) / 2 ** 128) * 10 ** 18
        let expected_debt_asset_price: u256 = 26894825598434793657; // WBTC/ETH price: 26.89...
        let debt_asset_price = extension_dispatcher.price(pool_id_v3, debt_asset.contract_address);
        assert!(debt_asset_price.value == expected_debt_asset_price, "Debt asset price incorrect");

        // Third asset has 18 decimals
        let third_asset_x128_price: u256 = 50675139689807561015903026885413648;
        ekubo_oracle.set_price_x128(third_asset.contract_address, quote_asset.contract_address, third_asset_x128_price);

        // Compare with expected python value in Decimal
        // (Decimal(x128_price) * 10 ** (18 - 18) / 2 ** 128) * 10 ** 18
        let expected_third_asset_price: u256 = 148920851081247; // STRK/ETH price: 0.00014...
        let third_asset_price = extension_dispatcher.price(pool_id_v3, third_asset.contract_address);
        assert!(third_asset_price.value == expected_third_asset_price, "Third asset price incorrect");
    }
}
