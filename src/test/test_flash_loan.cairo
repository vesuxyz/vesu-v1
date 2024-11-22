#[starknet::interface]
trait IFlashLoanGeneric<TContractState> {
    fn flash_loan_amount(self: @TContractState) -> u256;
}

#[starknet::contract]
mod FlashLoanreceiver {
    use starknet::{get_block_timestamp, ContractAddress};
    use vesu::singleton::IFlashloanReceiver;

    #[storage]
    struct Storage {
        flash_loan_amount: u256,
    }

    #[abi(embed_v0)]
    impl FlashLoanReceiver of IFlashloanReceiver<ContractState> {
        fn on_flash_loan(
            ref self: ContractState, sender: ContractAddress, asset: ContractAddress, amount: u256, data: Span<felt252>
        ) {
            self.flash_loan_amount.write(amount);
        }
    }


    #[abi(embed_v0)]
    impl GenericTrait of super::IFlashLoanGeneric<ContractState> {
        fn flash_loan_amount(self: @ContractState) -> u256 {
            self.flash_loan_amount.read()
        }
    }
}

#[starknet::contract]
mod MaliciousFlashLoanReceiver {
    use starknet::{get_block_timestamp, ContractAddress, contract_address_const};
    use vesu::singleton::IFlashloanReceiver;
    use vesu::vendor::erc20::{ERC20ABIDispatcherTrait, ERC20ABIDispatcher};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl FlashLoanReceiver of IFlashloanReceiver<ContractState> {
        fn on_flash_loan(
            ref self: ContractState, sender: ContractAddress, asset: ContractAddress, amount: u256, data: Span<felt252>
        ) {
            ERC20ABIDispatcher { contract_address: asset }.transfer(contract_address_const::<'BadUser'>(), amount);
        }
    }
}

#[cfg(test)]
mod FlashLoans {
    use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
    use starknet::{contract_address};
    use super::{IFlashLoanGenericDispatcherTrait, IFlashLoanGenericDispatcher};
    use vesu::vendor::erc20::ERC20ABIDispatcherTrait;
    use vesu::{
        math::pow_10, test::setup::{setup, deploy_contract, TestConfig, LendingTerms},
        singleton::{
            ISingletonDispatcher, ISingletonDispatcherTrait, IFlashloanReceiverDispatcher,
            IFlashloanReceiverDispatcherTrait, ModifyPositionParams
        },
        data_model::{Amount, AmountType, AmountDenomination}
    };

    #[test]
    fn test_flash_loan_fractional_pool_amount() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

        let flash_loan_receiver_add = deploy_contract("FlashLoanreceiver");
        let flashloan_receiver = IFlashloanReceiverDispatcher { contract_address: flash_loan_receiver_add };
        let flashloan_receiver_view = IFlashLoanGenericDispatcher { contract_address: flash_loan_receiver_add };

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);
        let pre_deposit_balance = debt_asset.balance_of(singleton.contract_address);
        // deposit debt asset that will be used in flash loan
        let params = ModifyPositionParams {
            pool_id,
            debt_asset: collateral_asset.contract_address,
            collateral_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: liquidity_to_deposit.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // check that liquidity has been deposited
        let balance = debt_asset.balance_of(users.lender);
        assert!(balance == initial_lender_debt_asset_balance - liquidity_to_deposit, "Not transferred from Lender");

        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(balance == pre_deposit_balance + liquidity_to_deposit, "Not transferred to Singleton");

        let flash_loan_amount = (balance / 2);

        start_cheat_caller_address(debt_asset.contract_address, flashloan_receiver.contract_address);
        debt_asset.approve(singleton.contract_address, flash_loan_amount);
        stop_cheat_caller_address(debt_asset.contract_address);

        assert!(
            debt_asset.balance_of(flashloan_receiver.contract_address) == 0, "Flash loan receiver should have 0 balance"
        );

        start_cheat_caller_address(singleton.contract_address, flashloan_receiver.contract_address);
        singleton
            .flash_loan(
                flashloan_receiver.contract_address,
                debt_asset.contract_address,
                flash_loan_amount,
                false,
                array![].span()
            );

        assert!(
            flashloan_receiver_view.flash_loan_amount() == flash_loan_amount,
            "Flash loan correctly sent to flash loan receiver"
        );
        stop_cheat_caller_address(singleton.contract_address);

        assert!(
            debt_asset.balance_of(flashloan_receiver.contract_address) == 0, "Flash loan receiver should have 0 balance"
        );
        assert!(
            debt_asset.balance_of(singleton.contract_address) == balance, "Singleton should have maintained balance"
        );
    }


    #[test]
    fn test_flash_loan_entire_pool() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

        let flash_loan_receiver_add = deploy_contract("FlashLoanreceiver");
        let flashloan_receiver = IFlashloanReceiverDispatcher { contract_address: flash_loan_receiver_add };
        let flashloan_receiver_view = IFlashLoanGenericDispatcher { contract_address: flash_loan_receiver_add };

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);
        let pre_deposit_balance = debt_asset.balance_of(singleton.contract_address);
        // deposit debt asset that will be used in flash loan
        let params = ModifyPositionParams {
            pool_id,
            debt_asset: collateral_asset.contract_address,
            collateral_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: liquidity_to_deposit.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // check that liquidity has been deposited
        let balance = debt_asset.balance_of(users.lender);
        assert!(balance == initial_lender_debt_asset_balance - liquidity_to_deposit, "Not transferred from Lender");

        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(balance == pre_deposit_balance + liquidity_to_deposit, "Not transferred to Singleton");

        // entire balance of the pool
        let flash_loan_amount = balance;
        start_cheat_caller_address(debt_asset.contract_address, flashloan_receiver.contract_address);
        debt_asset.approve(singleton.contract_address, flash_loan_amount);
        stop_cheat_caller_address(debt_asset.contract_address);
        start_cheat_caller_address(singleton.contract_address, flashloan_receiver.contract_address);
        singleton
            .flash_loan(
                flashloan_receiver.contract_address,
                debt_asset.contract_address,
                flash_loan_amount,
                false,
                array![].span()
            );

        assert!(
            flashloan_receiver_view.flash_loan_amount() == flash_loan_amount,
            "Flash loan correctly sent to flash loan receiver"
        );
        stop_cheat_caller_address(singleton.contract_address);

        assert!(
            debt_asset.balance_of(flashloan_receiver.contract_address) == 0, "Flash loan receiver should have 0 balance"
        );
        assert!(
            debt_asset.balance_of(singleton.contract_address) == balance, "Singleton should have maintained balance"
        );
    }

    #[test]
    #[should_panic(expected: ('u256_sub Overflow',))]
    fn test_flash_loan_malicious_user() {
        let (singleton, _, config, users, terms) = setup();
        let TestConfig { pool_id, collateral_asset, debt_asset, .. } = config;
        let LendingTerms { liquidity_to_deposit, .. } = terms;

        let malicious_flash_loan_receiver_add = deploy_contract("MaliciousFlashLoanReceiver");
        let malicious_flashloan_receiver = IFlashloanReceiverDispatcher {
            contract_address: malicious_flash_loan_receiver_add
        };

        let initial_lender_debt_asset_balance = debt_asset.balance_of(users.lender);
        let pre_deposit_balance = debt_asset.balance_of(singleton.contract_address);
        // deposit debt asset that will be used in flash loan
        let params = ModifyPositionParams {
            pool_id,
            debt_asset: collateral_asset.contract_address,
            collateral_asset: debt_asset.contract_address,
            user: users.lender,
            collateral: Amount {
                amount_type: AmountType::Delta,
                denomination: AmountDenomination::Assets,
                value: liquidity_to_deposit.into(),
            },
            debt: Default::default(),
            data: ArrayTrait::new().span()
        };

        start_cheat_caller_address(singleton.contract_address, users.lender);
        singleton.modify_position(params);
        stop_cheat_caller_address(singleton.contract_address);

        // check that liquidity has been deposited
        let balance = debt_asset.balance_of(users.lender);
        assert!(balance == initial_lender_debt_asset_balance - liquidity_to_deposit, "Not transferred from Lender");

        let balance = debt_asset.balance_of(singleton.contract_address);
        assert!(balance == pre_deposit_balance + liquidity_to_deposit, "Not transferred to Singleton");

        // entire balance of the pool
        let flash_loan_amount = balance;
        start_cheat_caller_address(debt_asset.contract_address, malicious_flashloan_receiver.contract_address);
        debt_asset.approve(singleton.contract_address, flash_loan_amount);
        stop_cheat_caller_address(debt_asset.contract_address);
        start_cheat_caller_address(singleton.contract_address, malicious_flashloan_receiver.contract_address);
        singleton
            .flash_loan(
                malicious_flashloan_receiver.contract_address,
                debt_asset.contract_address,
                flash_loan_amount,
                false,
                array![].span()
            );
        stop_cheat_caller_address(singleton.contract_address);
    }
}
