use core::hash::{LegacyHash, HashStateTrait, HashStateExTrait, Hash};
use core::option::OptionTrait;
use core::result::ResultTrait;
use core::traits::TryInto;
use starknet::account::{Call};
use starknet::class_hash::{ClassHash};
use starknet::contract_address::{ContractAddress};
use starknet::storage_access::{StorePacking};
use starknet::{SyscallResult, syscalls::call_contract_syscall};

const TWO_POW_64: u128 = 0x10000000000000000;
const TWO_POW_64_DIVISOR: NonZero<u128> = 0x10000000000000000;

pub(crate) impl TwoU64TupleStorePacking of StorePacking<(u64, u64), u128> {
    fn pack(value: (u64, u64)) -> u128 {
        let (a, b) = value;
        a.into() + (b.into() * TWO_POW_64)
    }

    fn unpack(value: u128) -> (u64, u64) {
        let (q, r) = DivRem::div_rem(value, TWO_POW_64_DIVISOR);
        (r.try_into().unwrap(), q.try_into().unwrap())
    }
}

#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct ExecutionState {
    pub created: u64,
    pub executed: u64,
    pub canceled: u64
}

pub(crate) impl ExecutionStateStorePacking of StorePacking<ExecutionState, felt252> {
    fn pack(value: ExecutionState) -> felt252 {
        u256 { low: TwoU64TupleStorePacking::pack((value.created, value.executed)), high: value.canceled.into() }
            .try_into()
            .unwrap()
    }

    fn unpack(value: felt252) -> ExecutionState {
        let u256_value: u256 = value.into();
        let (created, executed) = TwoU64TupleStorePacking::unpack(u256_value.low);
        ExecutionState { created, executed, canceled: (u256_value.high).try_into().unwrap() }
    }
}

pub impl HashCall<S, +HashStateTrait<S>, +Drop<S>, +Copy<S>> of Hash<@Call, S> {
    fn update_state(state: S, value: @Call) -> S {
        let mut s = state.update_with((*value.to)).update_with(*value.selector);

        let mut data_span: Span<felt252> = *value.calldata;
        while let Option::Some(word) = data_span.pop_front() {
            s = s.update(*word);
        };

        s
    }
}

#[generate_trait]
pub impl CallTraitImpl of CallTrait {
    fn execute(self: @Call) -> Span<felt252> {
        let result = call_contract_syscall(*self.to, *self.selector, *self.calldata);

        if (result.is_err()) {
            panic(result.unwrap_err());
        }

        result.unwrap()
    }
}

#[derive(Copy, Drop, Serde)]
pub struct Config {
    pub delay: u64,
    pub window: u64,
}

pub(crate) impl ConfigStorePacking of StorePacking<Config, u128> {
    fn pack(value: Config) -> u128 {
        TwoU64TupleStorePacking::pack((value.delay, value.window))
    }

    fn unpack(value: u128) -> Config {
        let (delay, window) = TwoU64TupleStorePacking::unpack(value);
        Config { delay, window }
    }
}

#[starknet::interface]
pub trait ITimelock<TContractState> {
    // Queue a list of calls to be executed after the delay. Only the owner may call this.
    fn queue(ref self: TContractState, calls: Span<Call>) -> felt252;

    // Cancel a queued proposal before it is executed. Only the owner may call this.
    fn cancel(ref self: TContractState, id: felt252);

    // Execute a list of calls that have previously been queued. Anyone may call this.
    fn execute(ref self: TContractState, calls: Span<Call>) -> Array<Span<felt252>>;

    // Return the execution window, i.e. the start and end timestamp in which the call can be executed
    fn get_execution_window(self: @TContractState, id: felt252) -> ExecutionWindow;

    // Get the current owner
    fn get_owner(self: @TContractState) -> ContractAddress;

    // Returns the delay and the window for call execution
    fn get_config(self: @TContractState) -> Config;

    // Transfer ownership, i.e. the address that can queue and cancel calls. This must be self-called via #queue.
    fn transfer(ref self: TContractState, to: ContractAddress);

    // Configure the delay and the window for call execution. This must be self-called via #queue.
    fn configure(ref self: TContractState, config: Config);

    // Replace the code at this address. This must be self-called via #queue.
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[derive(Copy, Drop, Serde)]
pub struct ExecutionWindow {
    pub earliest: u64,
    pub latest: u64
}

#[starknet::contract]
pub mod Timelock {
    use core::hash::LegacyHash;
    use core::result::ResultTrait;
    use starknet::{
        get_caller_address, get_contract_address, SyscallResult,
        syscalls::{call_contract_syscall, replace_class_syscall}, get_block_timestamp
    };
    use super::{
        ClassHash, ITimelock, ContractAddress, Call, Config, ExecutionState, ConfigStorePacking, ExecutionWindow,
        CallTrait, HashCall
    };


    #[derive(starknet::Event, Drop)]
    pub struct Queued {
        pub id: felt252,
        pub calls: Span<Call>,
    }

    #[derive(starknet::Event, Drop)]
    pub struct Canceled {
        pub id: felt252,
    }

    #[derive(starknet::Event, Drop)]
    pub struct Executed {
        pub id: felt252,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Queued: Queued,
        Canceled: Canceled,
        Executed: Executed,
    }

    #[storage]
    struct Storage {
        owner: ContractAddress,
        config: Config,
        execution_state: LegacyMap<felt252, ExecutionState>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, config: Config) {
        self.owner.write(owner);
        self.config.write(config);
    }

    // Take a list of calls and convert it to a unique identifier for the execution
    // Two lists of calls will always have the same ID if they are equivalent
    // A list of calls can only be queued and executed once. To make 2 different calls, add an empty call.
    pub(crate) fn to_id(mut calls: Span<Call>) -> felt252 {
        let mut state = selector!("ekubo::governance::Timelock::to_id");
        while let Option::Some(call) = calls.pop_front() {
            state = LegacyHash::hash(state, call);
        };
        state
    }

    #[generate_trait]
    impl TimelockInternal of TimelockInternalTrait {
        fn check_owner(self: @ContractState) {
            assert(get_caller_address() == self.owner.read(), 'OWNER_ONLY');
        }

        fn check_self_call(self: @ContractState) {
            assert(get_caller_address() == get_contract_address(), 'SELF_CALL_ONLY');
        }
    }

    #[abi(embed_v0)]
    impl TimelockImpl of ITimelock<ContractState> {
        fn queue(ref self: ContractState, calls: Span<Call>) -> felt252 {
            self.check_owner();

            let id = to_id(calls);
            let execution_state = self.execution_state.read(id);

            assert(execution_state.canceled.is_zero(), 'HAS_BEEN_CANCELED');
            assert(execution_state.created.is_zero(), 'ALREADY_QUEUED');

            self.execution_state.write(id, ExecutionState { created: get_block_timestamp(), executed: 0, canceled: 0 });

            self.emit(Queued { id, calls });

            id
        }

        fn cancel(ref self: ContractState, id: felt252) {
            self.check_owner();

            let execution_state = self.execution_state.read(id);
            assert(execution_state.created.is_non_zero(), 'DOES_NOT_EXIST');
            assert(execution_state.executed.is_zero(), 'ALREADY_EXECUTED');

            self
                .execution_state
                .write(
                    id,
                    ExecutionState {
                        created: execution_state.created,
                        executed: execution_state.executed,
                        canceled: get_block_timestamp()
                    }
                );

            self.emit(Canceled { id });
        }

        fn execute(ref self: ContractState, mut calls: Span<Call>) -> Array<Span<felt252>> {
            let id = to_id(calls);

            let execution_state = self.execution_state.read(id);

            assert(execution_state.executed.is_zero(), 'ALREADY_EXECUTED');
            assert(execution_state.canceled.is_zero(), 'HAS_BEEN_CANCELED');

            let execution_window = self.get_execution_window(id);
            let time_current = get_block_timestamp();

            assert(time_current >= execution_window.earliest, 'TOO_EARLY');
            assert(time_current < execution_window.latest, 'TOO_LATE');

            self
                .execution_state
                .write(
                    id,
                    ExecutionState {
                        created: execution_state.created, executed: time_current, canceled: execution_state.canceled
                    }
                );

            let mut results: Array<Span<felt252>> = ArrayTrait::new();

            while let Option::Some(call) = calls.pop_front() {
                results.append(call.execute());
            };

            self.emit(Executed { id });

            results
        }

        fn get_execution_window(self: @ContractState, id: felt252) -> ExecutionWindow {
            let created = self.execution_state.read(id).created;

            // this prevents the 0 timestamp for created from being considered valid and also executed
            assert(created.is_non_zero(), 'DOES_NOT_EXIST');

            let config = self.get_config();

            let earliest = created + config.delay;

            let latest = earliest + config.window;

            ExecutionWindow { earliest, latest }
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn get_config(self: @ContractState) -> Config {
            self.config.read()
        }

        fn transfer(ref self: ContractState, to: ContractAddress) {
            self.check_self_call();

            self.owner.write(to);
        }

        fn configure(ref self: ContractState, config: Config) {
            self.check_self_call();

            self.config.write(config);
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            self.check_self_call();

            replace_class_syscall(class_hash).unwrap();
        }
    }
}
