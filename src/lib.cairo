mod common;
mod data_model;

mod math;
mod packing;
mod singleton_v2;
mod units;

mod v_token;

mod extension {
    mod default_extension_po_v2;
    mod interface;
    mod components {
        mod ekubo_oracle;
        mod fee_model;
        mod interest_rate_model;
        mod position_hooks;
        mod pragma_oracle;
        mod tokenization;
    }
}

mod vendor {
    mod ekubo;
    mod erc20;
    mod erc20_component;
    mod ownable;
    mod pragma;
}

mod test {
    mod mock_asset;
    mod mock_ekubo_core;
    mod mock_ekubo_oracle;
    mod mock_extension;
    mod mock_oracle;
    mod mock_singleton;
    mod mock_singleton_upgrade;
    mod setup_v2;
    mod test_asset_retrieval;
    mod test_common;
    mod test_default_extension_po_v2;
    mod test_fee_model;
    mod test_flash_loan;
    mod test_forking;
    mod test_interest_rate_model;
    mod test_liquidate_position;
    mod test_math;
    mod test_modify_position;
    mod test_packing;
    mod test_pool_donations;
    mod test_pragma_oracle;
    mod test_reentrancy;
    mod test_shutdown;
    mod test_singleton_v2;
    mod test_transfer_position;
    mod test_upgrade;
    mod test_v_token;
}
