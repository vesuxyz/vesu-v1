#[starknet::contract]
mod ListContract {
    use vesu::{
        extension::default_extension::{ITimestampManagerCallback},
        map_list::{map_list_component, map_list_component::MapListTrait},
    };

    component!(path: map_list_component, storage: lists, event: MapListEvents);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        lists: map_list_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MapListEvents: map_list_component::Event,
    }

    #[abi(embed_v0)]
    impl TimestampManagerCallbackImpl of ITimestampManagerCallback<ContractState> {
        fn contains(self: @ContractState, pool_id: felt252, item: u64) -> bool {
            self.lists.contains(pool_id, item)
        }
        fn push_front(ref self: ContractState, pool_id: felt252, item: u64) {
            self.lists.push_front(pool_id, item)
        }
        fn remove(ref self: ContractState, pool_id: felt252, item: u64) {
            self.lists.remove(pool_id, item)
        }
        fn first(self: @ContractState, pool_id: felt252) -> u64 {
            self.lists.first(pool_id)
        }
        fn last(self: @ContractState, pool_id: felt252) -> u64 {
            self.lists.last(pool_id)
        }
        fn previous(self: @ContractState, pool_id: felt252, item: u64) -> u64 {
            self.lists.previous(pool_id, item)
        }
        fn all(self: @ContractState, pool_id: felt252) -> Array<u64> {
            self.lists.all(pool_id)
        }
    }
}

#[cfg(test)]
mod TestMapList {
    use snforge_std::{declare, ContractClassTrait};
    use vesu::extension::default_extension::{
        ITimestampManagerCallback, ITimestampManagerCallbackDispatcher, ITimestampManagerCallbackDispatcherTrait,
        ITimestampManagerCallbackSafeDispatcher, ITimestampManagerCallbackSafeDispatcherTrait
    };

    const id: felt252 = 42;

    fn setup_contract() -> ITimestampManagerCallbackDispatcher {
        let contract_address = declare("ListContract").deploy(@array![]).unwrap();
        ITimestampManagerCallbackDispatcher { contract_address }
    }

    fn setup() -> ITimestampManagerCallbackDispatcher {
        let contract = setup_contract();
        contract.push_front(id, 13);
        contract.push_front(id, 12);
        contract.push_front(id, 11);
        contract.push_front(id, 10);
        contract
    }

    fn safe(contract: ITimestampManagerCallbackDispatcher) -> ITimestampManagerCallbackSafeDispatcher {
        ITimestampManagerCallbackSafeDispatcher { contract_address: contract.contract_address }
    }

    #[test]
    fn test_list_creation() {
        let contract = setup_contract();
        contract.push_front(id, 13);
        assert!(contract.all(id) == array![13], "err");
        contract.push_front(id, 12);
        contract.push_front(id, 11);
        contract.push_front(id, 10);
        assert!(contract.all(id) == array![10, 11, 12, 13], "err 2");
    }

    #[test]
    #[should_panic(expected: "cannot-push-zero")]
    fn test_insert_zero() {
        let contract = setup();
        contract.push_front(id, 0);
    }

    #[test]
    fn test_remove() {
        let contract = setup();
        contract.remove(id, 12);
        assert!(contract.all(id) == array![10, 11, 13], "err");
    }

    #[test]
    #[should_panic(expected: "cannot-remove-zero")]
    fn test_remove_zero() {
        let contract = setup();
        contract.remove(id, 0);
    }

    #[test]
    #[should_panic(expected: "cannot-find-item-before")]
    fn test_remove_nonexistent() {
        let contract = setup();
        contract.remove(id, 14);
    }
}

