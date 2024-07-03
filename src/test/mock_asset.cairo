use starknet::ContractAddress;
#[starknet::interface]
trait IMintable<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
}
#[starknet::contract]
mod MockAsset {
    use starknet::ContractAddress;
    use vesu::vendor::erc20_component::ERC20Component;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        initial_supply: u256,
        recipient: ContractAddress,
    ) {
        self.erc20.initializer(name, symbol, decimals);
        self.erc20._mint(recipient, initial_supply);
    }

    #[abi(embed_v0)]
    impl Mintable of super::IMintable<ContractState> {
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.erc20._mint(recipient, amount);
            true
        }
    }
}

#[starknet::interface]
trait IReentrant<TContractState> {
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::contract]
mod MockAssetReentrant {
    use integer::BoundedInt;
    use starknet::{ContractAddress, get_caller_address, call_contract_syscall, get_contract_address};
    use vesu::vendor::erc20_component::ERC20Component;


    #[storage]
    struct Storage {
        ERC20_name: felt252,
        ERC20_symbol: felt252,
        ERC20_decimals: u8,
        ERC20_total_supply: u256,
        ERC20_balances: LegacyMap<ContractAddress, u256>,
        ERC20_allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
    }

    mod Errors {
        const APPROVE_FROM_ZERO: felt252 = 'ERC20: approve from 0';
        const APPROVE_TO_ZERO: felt252 = 'ERC20: approve to 0';
        const TRANSFER_FROM_ZERO: felt252 = 'ERC20: transfer from 0';
        const TRANSFER_TO_ZERO: felt252 = 'ERC20: transfer to 0';
        const BURN_FROM_ZERO: felt252 = 'ERC20: burn from 0';
        const MINT_TO_ZERO: felt252 = 'ERC20: mint to 0';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        initial_supply: u256,
        recipient: ContractAddress,
    ) {
        self.initializer(name, symbol, decimals);
        self._mint(recipient, initial_supply);
    }

    #[abi(embed_v0)]
    impl Reentrant of super::IReentrant<ContractState> {
        fn transfer_from(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let _ = get_caller_address();
            // call_contract_syscall(caller, selector!(""), array![].span());
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self._approve(caller, spender, amount);
            true
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn initializer(ref self: ContractState, name: felt252, symbol: felt252, decimals: u8) {
            self.ERC20_name.write(name);
            self.ERC20_symbol.write(symbol);
            self.ERC20_decimals.write(decimals);
        }


        fn _transfer(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
            assert(!sender.is_zero(), Errors::TRANSFER_FROM_ZERO);
            assert(!recipient.is_zero(), Errors::TRANSFER_TO_ZERO);
            self.ERC20_balances.write(sender, self.ERC20_balances.read(sender) - amount);
            self.ERC20_balances.write(recipient, self.ERC20_balances.read(recipient) + amount);
        }

        fn _approve(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
            assert(!owner.is_zero(), Errors::APPROVE_FROM_ZERO);
            assert(!spender.is_zero(), Errors::APPROVE_TO_ZERO);
            self.ERC20_allowances.write((owner, spender), amount);
        }

        fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            assert(!recipient.is_zero(), Errors::MINT_TO_ZERO);
            self.ERC20_total_supply.write(self.ERC20_total_supply.read() + amount);
            self.ERC20_balances.write(recipient, self.ERC20_balances.read(recipient) + amount);
        }
    }
}
