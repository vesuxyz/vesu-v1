#[cfg(test)]
mod TestFeeModel {
    use openzeppelin::token::erc20::{ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait};
    use snforge_std::{CheatSpan, DeclareResultTrait, cheat_caller_address, declare, replace_bytecode};
    #[feature("deprecated-starknet-consts")]
    use starknet::contract_address_const;
    use vesu::extension::default_extension_po_v2::{
        IDefaultExtensionPOV2Dispatcher, IDefaultExtensionPOV2DispatcherTrait,
    };
    use vesu::singleton_v2::{ISingletonV2Dispatcher, ISingletonV2DispatcherTrait};
    use vesu::units::SCALE;

    fn setup(pool_id: felt252) -> (ISingletonV2Dispatcher, IDefaultExtensionPOV2Dispatcher) {
        let singleton = ISingletonV2Dispatcher {
            contract_address: contract_address_const::<
                0x000d8d6dfec4d33bfb6895de9f3852143a17c6f92fd2a21da3d6924d34870160,
            >(),
        };

        let extension = IDefaultExtensionPOV2Dispatcher { contract_address: singleton.extension(pool_id) };
        replace_bytecode(
            extension.contract_address, *declare("DefaultExtensionPOV2").unwrap().contract_class().class_hash,
        )
            .unwrap();

        (singleton, extension)
    }

    #[test]
    #[fork("Mainnet")]
    fn test_claim_fees() {
        let pool_id = 0x6febb313566c48e30614ddab092856a9ab35b80f359868ca69b2649ca5d148d;
        let (_, extension) = setup(pool_id);
        let asset = IERC20Dispatcher {
            contract_address: contract_address_const::<
                0x075afe6402ad5a5c20dd25e10ec3b3986acaa647b77e4ae24b0cbc9a54a27a87,
            >(),
        };

        let owner = extension.pool_owner(pool_id);
        let fee_recipient = extension.fee_config(pool_id).fee_recipient;
        let initial_balance = asset.balance_of(fee_recipient);

        cheat_caller_address(extension.contract_address, owner, CheatSpan::TargetCalls(1));
        extension.claim_fees(pool_id, asset.contract_address);

        assert!(asset.balance_of(fee_recipient) > initial_balance);
        assert!(asset.balance_of(fee_recipient) - initial_balance < SCALE);
    }
}
