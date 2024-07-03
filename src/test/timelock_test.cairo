use core::array::{Array, ArrayTrait, SpanTrait};
use starknet::{
    get_contract_address, syscalls::{deploy_syscall}, ClassHash, contract_address_const, ContractAddress,
    get_block_timestamp, testing::set_block_timestamp
};
use vesu::vendor::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use vesu::vendor::timelock::{ExecutionState};
use vesu::vendor::timelock::{ITimelockDispatcher, ITimelockDispatcherTrait, Timelock, Config};

#[starknet::contract]
pub(crate) mod TestToken {
    use core::num::traits::zero::{Zero};
    use starknet::{ContractAddress, get_caller_address};
    use vesu::vendor::erc20::{IERC20};

    #[storage]
    struct Storage {
        balances: LegacyMap<ContractAddress, u256>,
        allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
    }

    #[derive(starknet::Event, PartialEq, Debug, Drop)]
    pub(crate) struct Transfer {
        pub(crate) from: ContractAddress,
        pub(crate) to: ContractAddress,
        pub(crate) value: u256,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Transfer: Transfer,
    }

    #[constructor]
    fn constructor(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        self.balances.write(recipient, amount);
        self.emit(Transfer { from: Zero::zero(), to: recipient, value: amount })
    }

    #[abi(embed_v0)]
    impl IERC20Impl of IERC20<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account).into()
        }
        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.allowances.read((owner, spender)).into()
        }
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let balance = self.balances.read(get_caller_address());
            assert(balance >= amount, 'INSUFFICIENT_TRANSFER_BALANCE');
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.balances.write(get_caller_address(), balance - amount);
            self.emit(Transfer { from: get_caller_address(), to: recipient, value: amount });
            true
        }
        fn transfer_from(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let allowance = self.allowances.read((sender, get_caller_address()));
            assert(allowance >= amount, 'INSUFFICIENT_ALLOWANCE');
            let balance = self.balances.read(sender);
            assert(balance >= amount, 'INSUFFICIENT_TF_BALANCE');
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.balances.write(sender, balance - amount);
            self.allowances.write((sender, get_caller_address()), allowance - amount);
            self.emit(Transfer { from: sender, to: recipient, value: amount });
            true
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.allowances.write((get_caller_address(), spender), amount.try_into().unwrap());
            true
        }
        fn total_supply(self: @ContractState) -> u256 {
            0
        }
    }
}

#[cfg(test)]
mod TestTimelock {
    use snforge_std::{declare, start_warp, CheatTarget};
    use starknet::account::{Call};
    use starknet::{
        get_contract_address, syscalls::{deploy_syscall}, ClassHash, contract_address_const, ContractAddress,
        get_block_timestamp, testing::set_block_timestamp
    };
    use vesu::vendor::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use vesu::vendor::timelock::{ExecutionState};
    use vesu::vendor::timelock::{ITimelockDispatcher, ITimelockDispatcherTrait, Timelock, Config};

    fn deploy_token(owner: ContractAddress, amount: u256) -> IERC20Dispatcher {
        let mut constructor_args: Array<felt252> = ArrayTrait::new();
        Serde::serialize(@(owner, amount), ref constructor_args);

        let (address, _) = deploy_syscall(
            declare("TestToken").class_hash.try_into().unwrap(), 0, constructor_args.span(), true
        )
            .expect('DEPLOY_TOKEN_FAILED');
        IERC20Dispatcher { contract_address: address }
    }

    fn deploy(owner: ContractAddress, delay: u64, window: u64) -> ITimelockDispatcher {
        let mut constructor_args: Array<felt252> = ArrayTrait::new();
        Serde::serialize(@(owner, delay, window), ref constructor_args);

        let (address, _) = deploy_syscall(
            declare("Timelock").class_hash.try_into().unwrap(), 0, constructor_args.span(), true
        )
            .expect('DEPLOY_FAILED');
        return ITimelockDispatcher { contract_address: address };
    }

    fn transfer_call(token: IERC20Dispatcher, recipient: ContractAddress, amount: u256) -> Call {
        let mut calldata: Array<felt252> = ArrayTrait::new();
        Serde::serialize(@(recipient, amount), ref calldata);

        Call {
            to: token.contract_address,
            // transfer
            selector: 0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e,
            calldata: calldata.span()
        }
    }

    fn single_call(call: Call) -> Span<Call> {
        return array![call].span();
    }

    #[test]
    fn test_deploy() {
        let timelock = deploy(contract_address_const::<2300>(), 10239, 3600);

        let configuration = timelock.get_config();
        assert(configuration.delay == 10239, 'delay');
        assert(configuration.window == 3600, 'window');
        let owner = timelock.get_owner();
        assert(owner == contract_address_const::<2300>(), 'owner');
    }

    #[test]
    fn test_queue_execute() {
        // set_block_timestamp(1);
        start_warp(CheatTarget::All, 1);
        let timelock = deploy(get_contract_address(), 86400, 3600);

        let token = deploy_token(get_contract_address(), 12345);
        token.transfer(timelock.contract_address, 12345);

        let recipient = contract_address_const::<12345>();

        let id = timelock.queue(single_call(transfer_call(token, recipient, 500_u256)));

        let execution_window = timelock.get_execution_window(id);
        assert(execution_window.earliest == 86401, 'earliest');
        assert(execution_window.latest == 90001, 'latest');

        // set_block_timestamp(86401);
        start_warp(CheatTarget::All, 86401);

        timelock.execute(single_call(transfer_call(token, recipient, 500_u256)));
        assert(token.balance_of(recipient) == 500_u256, 'balance');
    }

    #[test]
    #[should_panic(expected: 'HAS_BEEN_CANCELED')]
    fn test_queue_cancel() {
        // set_block_timestamp(1);
        start_warp(CheatTarget::All, 1);
        let timelock = deploy(get_contract_address(), 86400, 3600);

        let token = deploy_token(get_contract_address(), 12345);
        token.transfer(timelock.contract_address, 12345);

        let recipient = contract_address_const::<12345>();

        let id = timelock.queue(single_call(transfer_call(token, recipient, 500_u256)));

        // set_block_timestamp(86401);
        start_warp(CheatTarget::All, 86401);

        timelock.cancel(id);

        timelock.execute(single_call(transfer_call(token, recipient, 500_u256)));
    }

    #[test]
    #[should_panic(expected: 'ALREADY_EXECUTED')]
    fn test_queue_execute_twice() {
        // set_block_timestamp(1);
        start_warp(CheatTarget::All, 1);
        let timelock = deploy(get_contract_address(), 86400, 3600);

        let token = deploy_token(get_contract_address(), 12345);
        token.transfer(timelock.contract_address, 12345);

        let recipient = contract_address_const::<12345>();

        timelock.queue(single_call(transfer_call(token, recipient, 500_u256)));

        // set_block_timestamp(86401);
        start_warp(CheatTarget::All, 86401);

        timelock.execute(single_call(transfer_call(token, recipient, 500_u256)));
        timelock.execute(single_call(transfer_call(token, recipient, 500_u256)));
    }

    #[test]
    #[should_panic(expected: 'TOO_EARLY')]
    fn test_queue_executed_too_early() {
        // set_block_timestamp(1);
        start_warp(CheatTarget::All, 1);
        let timelock = deploy(get_contract_address(), 86400, 3600);

        let token = deploy_token(get_contract_address(), 12345);
        token.transfer(timelock.contract_address, 12345);

        let recipient = contract_address_const::<12345>();

        let id = timelock.queue(single_call(transfer_call(token, recipient, 500_u256)));

        let execution_window = timelock.get_execution_window(id);
        // set_block_timestamp(execution_window.earliest - 1);
        start_warp(CheatTarget::All, execution_window.earliest - 1);
        timelock.execute(single_call(transfer_call(token, recipient, 500_u256)));
    }

    #[test]
    #[should_panic(expected: 'TOO_LATE')]
    fn test_queue_executed_too_late() {
        // set_block_timestamp(1);
        start_warp(CheatTarget::All, 1);
        let timelock = deploy(get_contract_address(), 86400, 3600);

        let token = deploy_token(get_contract_address(), 12345);
        token.transfer(timelock.contract_address, 12345);

        let recipient = contract_address_const::<12345>();

        let id = timelock.queue(single_call(transfer_call(token, recipient, 500_u256)));

        let execution_window = timelock.get_execution_window(id);
        // set_block_timestamp(execution_window.latest);
        start_warp(CheatTarget::All, execution_window.latest);
        timelock.execute(single_call(transfer_call(token, recipient, 500_u256)));
    }
}
