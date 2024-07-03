#[starknet::component]
mod map_list_component {
    #[storage]
    struct Storage {
        lists: LegacyMap<(felt252, u64), u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[generate_trait]
    impl MapListTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        // Constant computation cost if `item` is in fact in the list AND it's not the last one.
        // Otherwise cost increases with the list size
        fn contains(self: @ComponentState<TContractState>, list_id: felt252, item: u64) -> bool {
            if item == 0 {
                return false;
            }
            let next_item = self.lists.read((list_id, item));
            if next_item != 0 {
                return true;
            }
            // check if its the last
            let last_item = self.last(list_id);

            last_item == item
        }

        fn next(self: @ComponentState<TContractState>, list_id: felt252, item: u64) -> u64 {
            self.lists.read((list_id, item))
        }

        fn previous(self: @ComponentState<TContractState>, list_id: felt252, item: u64) -> u64 {
            self.find_item_before(list_id, item)
        }

        fn push_front(ref self: ComponentState<TContractState>, list_id: felt252, item_to_add: u64,) {
            assert!(item_to_add != 0, "cannot-push-zero");
            let first = self.first(list_id);
            if first != 0 {
                self.lists.write((list_id, item_to_add), first);
            }
            self.lists.write((list_id, 0), item_to_add);
        }

        fn remove(ref self: ComponentState<TContractState>, list_id: felt252, item: u64) {
            assert!(item != 0, "cannot-remove-zero");
            // item pointer set to 0, Previous pointer set to the next in the list
            let previous_item = self.find_item_before(list_id, item);
            let next_item = self.lists.read((list_id, item));

            self.lists.write((list_id, previous_item), next_item);

            if next_item != 0 {
                // Removing an item in the middle
                self.lists.write((list_id, item), 0);
            }
        }

        fn first(self: @ComponentState<TContractState>, list_id: felt252) -> u64 {
            self.lists.read((list_id, 0))
        }

        // Return the last item or zero if no items. Cost increases with the list size
        fn last(self: @ComponentState<TContractState>, list_id: felt252) -> u64 {
            let mut current_item = self.lists.read((list_id, 0));
            loop {
                let next_item = self.lists.read((list_id, current_item));
                if next_item == 0 {
                    break current_item;
                }
                current_item = next_item;
            }
        }

        fn all(self: @ComponentState<TContractState>, list_id: felt252) -> Array<u64> {
            let mut current_item = self.lists.read((list_id, 0));
            let mut items = array![];
            while current_item != 0 {
                items.append(current_item);
                current_item = self.lists.read((list_id, current_item));
            };
            items
        }
    }

    #[generate_trait]
    impl Private<TContractState, +HasComponent<TContractState>> of PrivateTrait<TContractState> {
        // Returns the item before `item_after` or 0 if the item is the first one. 
        // Reverts if `item_after` is not found
        // Cost increases with the list size
        fn find_item_before(self: @ComponentState<TContractState>, list_id: felt252, item_after: u64) -> u64 {
            let mut current_item = 0;
            loop {
                let next_item = self.lists.read((list_id, current_item));
                assert!(next_item != 0, "cannot-find-item-before");

                if next_item == item_after {
                    break current_item;
                }
                current_item = next_item;
            }
        }
    }
}
