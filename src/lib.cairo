mod common;
mod data_model;

mod map_list;
mod math;
mod packing;
mod singleton;
mod units;

mod extension {
    mod default_extension;
    mod interface;
    mod components {
        mod fee_model;
        mod interest_rate_model;
        mod position_hooks;
        mod pragma_oracle;
    }
}

mod vendor {
    mod erc20;
    mod erc20_component;
    mod pragma;
}

mod test {
    mod mock_asset;
    mod mock_oracle;
    mod setup;
    mod test_asset_retrieval;
    mod test_common;
    mod test_create_pool;
    mod test_flash_loan;
    mod test_forking;
    mod test_interest_rate_model;
    mod test_liquidate_position;
    mod test_map_list;
    mod test_math;
    mod test_modify_position;
    mod test_oracle;
    mod test_packing;
    mod test_pool_donations;
    mod test_shutdown;
    mod test_transfer_position;
}
