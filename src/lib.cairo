mod common;
mod data_model;

mod map_list;
mod math;
mod packing;
mod singleton;
mod units;

mod v_token;

mod extension {
    mod default_extension_cl;
    mod default_extension_po;
    mod interface;
    mod components {
        mod chainlink_oracle;
        mod fee_model;
        mod interest_rate_model;
        mod position_hooks;
        mod pragma_oracle;
        mod tokenization;
    }
}

mod vendor {
    mod chainlink;
    mod erc20;
    mod erc20_component;
    mod pragma;
}

mod test {
    mod mock_asset;
    mod mock_chainlink_aggregator;
    mod mock_extension;
    mod mock_oracle;
    mod mock_singleton;
    mod setup;
    mod test_asset_retrieval;
    mod test_common;
    mod test_default_extension_cl;
    mod test_default_extension_po;
    mod test_flash_loan;
    mod test_forking;
    mod test_interest_rate_model;
    mod test_liquidate_position;
    mod test_map_list;
    mod test_math;
    mod test_modify_position;
    mod test_packing;
    mod test_pool_donations;
    mod test_pragma_oracle;
    mod test_reentrancy;
    mod test_shutdown;
    mod test_singleton;
    mod test_transfer_position;
    mod test_v_token;
}
