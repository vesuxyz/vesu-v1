#[cfg(test)]
mod TestInterestRateModel {
    use starknet::{get_block_timestamp};
    use vesu::{
        units::{SCALE, PERCENT, FRACTION, YEAR_IN_SECONDS, DAY_IN_SECONDS}, math::{pow_scale},
        common::{calculate_utilization, calculate_debt, calculate_nominal_debt}, singleton::AssetConfig,
        extension::components::interest_rate_model::{
            interest_rate_model_component::calculate_interest_rate, InterestRateConfig, InterestRateConfigPacking
        },
    };

    fn interest_rate_config() -> InterestRateConfig {
        InterestRateConfig {
            min_target_utilization: 75_000,
            max_target_utilization: 85_000,
            target_utilization: 87_500,
            min_full_utilization_rate: 1582470460,
            max_full_utilization_rate: 32150205761,
            zero_utilization_rate: 158247046,
            rate_half_life: 172_800,
            target_rate_percent: 20 * PERCENT,
        }
    }

    fn random_interest_rate_config(seed_1: u32, seed_2: u32) -> InterestRateConfig {
        let min_target = randrange(00_100, 99_000, seed_1);
        let max_target = randrange(min_target, 99_000, seed_2);

        let mut interest_rate_config = interest_rate_config();
        interest_rate_config.min_target_utilization = min_target;
        interest_rate_config.max_target_utilization = max_target;
        interest_rate_config.target_utilization = (min_target + max_target) / 2;

        interest_rate_config
    }

    #[test]
    fn test_model_from_asset_config() {
        let interest_rate_config = interest_rate_config();

        let asset_config = AssetConfig {
            total_collateral_shares: SCALE,
            total_nominal_debt: SCALE / 2,
            reserve: 50_000_000,
            max_utilization: SCALE,
            floor: 100000000000000,
            scale: 100_000_000,
            is_legacy: true,
            last_updated: 0,
            last_rate_accumulator: SCALE,
            last_full_utilization_rate: 6517893350,
            fee_rate: 0
        };

        let AssetConfig { total_nominal_debt, reserve, scale, .. } = asset_config;
        let AssetConfig { last_updated, last_rate_accumulator, last_full_utilization_rate, .. } = asset_config;

        let total_debt = calculate_debt(total_nominal_debt, last_rate_accumulator, scale, false);
        let utilization = calculate_utilization(reserve, total_debt);
        let time_delta = DAY_IN_SECONDS - last_updated;

        let (rate, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );

        let borrow_apr = rate * YEAR_IN_SECONDS;
        let borrow_apy = pow_scale(SCALE + rate, YEAR_IN_SECONDS, false) - SCALE;
        let total_borrowed = (total_nominal_debt * last_rate_accumulator) / SCALE;
        let reserve_scale = (reserve * SCALE) / scale;
        let supply_apy = borrow_apy * total_borrowed / (reserve_scale + total_borrowed);

        assert!(rate == 778649180, "invalid rate");
        assert!(next_full_utilization_rate < last_full_utilization_rate, "invalid next_full_utilization_rate");
        assert!(borrow_apr == 24219104094720000, "invalid borrow_apr"); // 2.42%
        assert!(supply_apy == 12257384326832902, "invalid supply_apy"); // 1.22%
    }

    #[test]
    fn test_utilization() {
        let interest_rate_config = interest_rate_config();

        let time_delta = DAY_IN_SECONDS;
        let last_full_utilization_rate = from_apr(20_000); // 20%

        // below target
        let utilization = 50 * PERCENT;
        let (rate, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(to_apr(rate) == 02_395, "invalid rate"); // 2.395%
        assert!(to_apr(next_full_utilization_rate) == 17_142, "invalid next_full_utilization_rate"); // 17.142%

        // in range
        let utilization = 80 * PERCENT;
        let (rate, _) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(to_apr(rate) == 04_059, "invalid rate");

        // above target
        let utilization = 90 * PERCENT;
        let (rate, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(to_apr(rate) == 05_060, "invalid rate");
        assert!(to_apr(next_full_utilization_rate) == 23_333, "invalid next_full_utilization_rate");
    }

    #[test]
    #[fuzzer(runs: 256, seed: 0)]
    fn test_next_full_utilization_vs_last(seed_1: u32, seed_2: u32) {
        let interest_rate_config = random_interest_rate_config(seed_1, seed_2);

        let time_delta = DAY_IN_SECONDS;
        let last_full_utilization_rate = from_apr(20_000);

        // below target
        let utilization = (interest_rate_config.min_target_utilization / 2) * FRACTION;
        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate < last_full_utilization_rate, "invalid below");

        // in range
        let utilization = interest_rate_config.target_utilization * FRACTION;
        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate == last_full_utilization_rate, "invalid in range");

        // above target
        let utilization = ((interest_rate_config.max_target_utilization + 100_000) / 2) * FRACTION;
        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate > last_full_utilization_rate, "invalid above");
    }

    #[test]
    #[fuzzer(runs: 256, seed: 0)]
    fn test_full_utilization_bounds(
        seed_1: u32, seed_2: u32, seed_3: u32, seed_4: u32, seed_5: u32, seed_6: u32, seed_7: u32, seed_8: u32
    ) {
        let mut interest_rate_config = random_interest_rate_config(seed_1, seed_2);
        interest_rate_config.zero_utilization_rate = from_apr(random_fraction(seed_3));
        interest_rate_config
            .min_full_utilization_rate = randrange(interest_rate_config.zero_utilization_rate, SCALE, seed_4);
        interest_rate_config
            .max_full_utilization_rate = randrange(interest_rate_config.min_full_utilization_rate, SCALE, seed_5);

        let utilization = random_fraction(seed_6) * FRACTION; // [0%, 100%]
        let time_delta = seed_7.into() / 10; // [0, ~10 years]
        let last_full_utilization_rate = from_apr(random_fraction(seed_8));

        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate >= interest_rate_config.min_full_utilization_rate, "below bound");
        assert!(next_full_utilization_rate <= interest_rate_config.max_full_utilization_rate, "above bound");
    }

    #[test]
    fn test_full_utilization_extremes(seed_1: u32, seed_2: u32) {
        let mut interest_rate_config = random_interest_rate_config(seed_1, seed_2);

        let utilization = (interest_rate_config.min_target_utilization / 2) * FRACTION;
        let last_full_utilization_rate = from_apr(20_000);

        let time_delta = 0;
        interest_rate_config.zero_utilization_rate = 00_000;
        interest_rate_config.min_full_utilization_rate = 00_000;
        interest_rate_config.max_full_utilization_rate = 00_000;
        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate >= interest_rate_config.min_full_utilization_rate, "below bound");
        assert!(next_full_utilization_rate <= interest_rate_config.max_full_utilization_rate, "above bound");

        let time_delta = DAY_IN_SECONDS * 360 * 10;
        interest_rate_config.zero_utilization_rate = 100_000;
        interest_rate_config.min_full_utilization_rate = 100_000;
        interest_rate_config.max_full_utilization_rate = 100_000;
        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate >= interest_rate_config.min_full_utilization_rate, "below bound");
        assert!(next_full_utilization_rate <= interest_rate_config.max_full_utilization_rate, "above bound");

        interest_rate_config.zero_utilization_rate = 1_000_000_000;
        interest_rate_config.min_full_utilization_rate = 1_000_000_000;
        interest_rate_config.max_full_utilization_rate = 1_000_000_000;
        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate >= interest_rate_config.min_full_utilization_rate, "below bound");
        assert!(next_full_utilization_rate <= interest_rate_config.max_full_utilization_rate, "above bound");
    }

    #[test]
    fn test_next_full_utilization_vs_half_life() {
        let interest_rate_config = interest_rate_config();

        let time_delta = interest_rate_config.rate_half_life.try_into().unwrap();
        let last_full_utilization_rate = from_apr(20_000);

        let utilization = 0;
        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate == last_full_utilization_rate / 2, "invalid next_full_utilization_rate");

        let utilization = 100_000 * FRACTION;
        let (_, next_full_utilization_rate) = calculate_interest_rate(
            interest_rate_config, utilization, time_delta, last_full_utilization_rate
        );
        assert!(next_full_utilization_rate == last_full_utilization_rate * 2, "invalid next_full_utilization_rate");
    }

    fn from_apr(apr: u256) -> u256 {
        (apr * FRACTION) / YEAR_IN_SECONDS
    }

    fn to_apr(rate: u256) -> u256 {
        (rate * YEAR_IN_SECONDS) / FRACTION
    }

    fn random_fraction(seed: u32) -> u256 {
        (100_000 * seed.into()) / integer::BoundedInt::<u32>::max().into()
    }

    fn randrange(min: u256, max: u256, seed: u32) -> u256 {
        min + ((max - min) * seed.into()) / integer::BoundedInt::<u32>::max().into()
    }

    #[test]
    fn test_interest_rate_config_packing() {
        let config = InterestRateConfig {
            min_target_utilization: 75_000,
            max_target_utilization: 85_000,
            target_utilization: 87_500,
            min_full_utilization_rate: 1582470460,
            max_full_utilization_rate: 32150205761,
            zero_utilization_rate: 158247046,
            rate_half_life: 172_800,
            target_rate_percent: 20 * PERCENT,
        };

        let packed = InterestRateConfigPacking::pack(config);
        let unpacked = InterestRateConfigPacking::unpack(packed);

        assert!(config.min_target_utilization == unpacked.min_target_utilization, "min_target_utilization err");
        assert!(config.max_target_utilization == unpacked.max_target_utilization, "max_target_utilization err");
        assert!(config.target_utilization == unpacked.target_utilization, "target_utilization err");
        assert!(
            config.min_full_utilization_rate == unpacked.min_full_utilization_rate, "min_full_utilization_rate err"
        );
        assert!(
            config.max_full_utilization_rate == unpacked.max_full_utilization_rate, "max_full_utilization_rate err"
        );
        assert!(config.zero_utilization_rate == unpacked.zero_utilization_rate, "zero_utilization_rate err");
        assert!(config.rate_half_life == unpacked.rate_half_life, "rate_half_life err");
        assert!(config.target_rate_percent == unpacked.target_rate_percent, "target_rate_percent err");
    }
}
