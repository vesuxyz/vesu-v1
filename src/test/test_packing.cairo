#[cfg(test)]
mod TestPacking {
    use vesu::{
        units::{SCALE, PERCENT}, singleton::{ISingletonDispatcherTrait}, data_model::{AssetConfig},
        packing::{AssetConfigPacking},
    };

    #[test]
    fn test_asset_config_packing() {
        let config = AssetConfig {
            total_collateral_shares: SCALE,
            total_nominal_debt: SCALE / 2,
            reserve: 50_000_000,
            max_utilization: 85 * PERCENT,
            floor: 1_000_000,
            scale: 100_000_000,
            is_legacy: true,
            last_updated: 1706553699,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 6517893350,
            fee_rate: 1 * PERCENT
        };

        let packed = AssetConfigPacking::pack(config);
        let unpacked = AssetConfigPacking::unpack(packed);

        assert!(config.total_collateral_shares == unpacked.total_collateral_shares, "total_collateral_shares err");
        assert!(config.total_nominal_debt == unpacked.total_nominal_debt, "total_nominal_debt err");
        assert!(config.reserve == unpacked.reserve, "reserve err");
        assert!(config.max_utilization == unpacked.max_utilization, "max_utilization err");
        assert!(config.floor == unpacked.floor, "floor err");
        assert!(config.scale == unpacked.scale, "scale err");
        assert!(config.is_legacy == unpacked.is_legacy, "is_legacy err");
        assert!(config.last_updated == unpacked.last_updated, "last_updated err");
        assert!(config.last_rate_accumulator == unpacked.last_rate_accumulator, "last_rate_accumulator err");
        assert!(
            config.last_full_utilization_rate == unpacked.last_full_utilization_rate, "last_full_utilization_rate err"
        );
        assert!(config.fee_rate == unpacked.fee_rate, "fee_rate err");

        let mut config = config;
        config.max_utilization = 85_1230004560000789;

        let packed = AssetConfigPacking::pack(config);
        let unpacked = AssetConfigPacking::unpack(packed);

        assert!(unpacked.max_utilization < config.max_utilization, "should loose precision");
    }
}
