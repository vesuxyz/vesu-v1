use vesu::{units::SCALE, packing::{SHIFT_32, SHIFT_64, split_32, split_64}};

const UTILIZATION_SCALE: u256 = 100_000; // 1e5
const UTILIZATION_SCALE_TO_SCALE: u256 = 10_000_000_000_000; // 1e13

#[derive(PartialEq, Copy, Drop, Serde, starknet::StorePacking)]
struct InterestRateConfig {
    min_target_utilization: u256, // [utilization-scale]
    max_target_utilization: u256, // [utilization-scale]
    target_utilization: u256, // [utilization-scale]
    min_full_utilization_rate: u256, // [SCALE]
    max_full_utilization_rate: u256, // [SCALE]
    zero_utilization_rate: u256, // [SCALE]
    rate_half_life: u256, // [seconds]
    target_rate_percent: u256, // [SCALE]
}

impl InterestRateConfigPacking of starknet::StorePacking<InterestRateConfig, (felt252, felt252)> {
    fn pack(value: InterestRateConfig) -> (felt252, felt252) {
        let min_target_utilization: u32 = value.min_target_utilization.try_into().expect('pack-min-target-utilization');
        let max_target_utilization: u32 = value.max_target_utilization.try_into().expect('pack-max-target-utilization');
        let target_utilization: u32 = value.target_utilization.try_into().expect('pack-target-utilization');
        let min_full_utilization_rate: u64 = value
            .min_full_utilization_rate
            .try_into()
            .expect('pack-min-full-utilization-rate');

        let slot1 = min_target_utilization.into()
            + max_target_utilization.into() * SHIFT_32
            + target_utilization.into() * SHIFT_32 * SHIFT_32
            + min_full_utilization_rate.into() * SHIFT_32 * SHIFT_32 * SHIFT_32;

        let max_full_utilization_rate: u64 = value
            .max_full_utilization_rate
            .try_into()
            .expect('pack-max-full-utilization-rate');
        let zero_utilization_rate: u64 = value.zero_utilization_rate.try_into().expect('pack-zero-utilization-rate');
        let rate_half_life: u32 = value.rate_half_life.try_into().expect('pack-rate-half-life');
        let target_rate_percent: u64 = value.target_rate_percent.try_into().expect('pack-target-rate-percent');

        let slot2 = max_full_utilization_rate.into()
            + zero_utilization_rate.into() * SHIFT_64
            + rate_half_life.into() * SHIFT_64 * SHIFT_64
            + target_rate_percent.into() * SHIFT_64 * SHIFT_64 * SHIFT_32;

        (slot1, slot2)
    }

    fn unpack(value: (felt252, felt252)) -> InterestRateConfig {
        let (slot1, slot2) = value;

        let (rest, min_target_utilization) = split_32(slot1.into());
        let (rest, max_target_utilization) = split_32(rest);
        let (rest, target_utilization) = split_32(rest);
        let (rest, min_full_utilization_rate) = split_64(rest.into());
        assert!(rest == 0, "interst-rate-config-slot-1-excess-data");

        let (rest, max_full_utilization_rate) = split_64(slot2.into());
        let (rest, zero_utilization_rate) = split_64(rest);
        let (rest, rate_half_life) = split_32(rest);
        let (rest, target_rate_percent) = split_64(rest);
        assert!(rest == 0, "interst-rate-config-slot-2-excess-data");

        InterestRateConfig {
            min_target_utilization: min_target_utilization.into(),
            max_target_utilization: max_target_utilization.into(),
            target_utilization: target_utilization.into(),
            min_full_utilization_rate: min_full_utilization_rate.into(),
            max_full_utilization_rate: max_full_utilization_rate.into(),
            zero_utilization_rate: zero_utilization_rate.into(),
            rate_half_life: rate_half_life.into(),
            target_rate_percent: target_rate_percent.into(),
        }
    }
}

#[inline(always)]
fn assert_interest_rate_config(interest_rate_config: InterestRateConfig) {
    let InterestRateConfig { min_target_utilization,
    max_target_utilization,
    ..,
    min_full_utilization_rate,
    max_full_utilization_rate,
    zero_utilization_rate,
    rate_half_life,
    target_rate_percent } =
        interest_rate_config;
    assert!(min_target_utilization <= max_target_utilization, "min-target-utilization-gt-max-target-utilization");
    assert!(max_target_utilization <= UTILIZATION_SCALE, "max-target-utilization-gt-100%");
    assert!(max_target_utilization != 0, "max-target-utilization-eq-0");
    assert!(zero_utilization_rate <= min_full_utilization_rate, "zero-utilization-rate-gt-min-full-utilization-rate");
    assert!(
        min_full_utilization_rate <= max_full_utilization_rate, "min-full-utilization-rate-gt-max-full-utilization-rate"
    );
    assert!(rate_half_life != 0, "rate-half-life-eq-0");
    assert!(target_rate_percent <= SCALE, "target-rate-percent-gt-100%");
    assert!(target_rate_percent != 0, "target-rate-percent-eq-0");
}

#[starknet::component]
mod interest_rate_model_component {
    use starknet::{ContractAddress, get_block_timestamp};
    use vesu::{
        units::SCALE, common::calculate_rate_accumulator,
        extension::components::interest_rate_model::{
            InterestRateConfig, assert_interest_rate_config, UTILIZATION_SCALE, UTILIZATION_SCALE_TO_SCALE
        }
    };

    #[storage]
    struct Storage {
        // (pool_id, asset) -> interest rate configuration
        interest_rate_configs: LegacyMap::<(felt252, ContractAddress), InterestRateConfig>,
    }

    #[derive(Drop, starknet::Event)]
    struct SetInterestRateConfig {
        pool_id: felt252,
        asset: ContractAddress,
        interest_rate_config: InterestRateConfig,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SetInterestRateConfig: SetInterestRateConfig
    }

    #[generate_trait]
    impl InterestRateModelTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        /// Sets the interest rate configuration for a specific pool and asset
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `interest_rate_config` - interest rate configuration
        fn set_interest_rate_config(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            interest_rate_config: InterestRateConfig
        ) {
            let current_interest_rate_config: InterestRateConfig = self.interest_rate_configs.read((pool_id, asset));
            assert!(current_interest_rate_config.max_target_utilization == 0, "interest-rate-config-already-set");
            assert_interest_rate_config(interest_rate_config);

            self.interest_rate_configs.write((pool_id, asset), interest_rate_config);

            self.emit(SetInterestRateConfig { pool_id, asset, interest_rate_config });
        }

        /// Sets a parameter for a given interest rate configuration for an asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_interest_rate_parameter(
            ref self: ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            parameter: felt252,
            value: u256,
        ) {
            let mut interest_rate_config: InterestRateConfig = self.interest_rate_configs.read((pool_id, asset));
            assert!(interest_rate_config.max_target_utilization != 0, "interest-rate-config-not-set");

            if parameter == 'min_target_utilization' {
                interest_rate_config.min_target_utilization = value;
            } else if parameter == 'max_target_utilization' {
                interest_rate_config.max_target_utilization = value;
            } else if parameter == 'target_utilization' {
                interest_rate_config.target_utilization = value;
            } else if parameter == 'min_full_utilization_rate' {
                interest_rate_config.min_full_utilization_rate = value;
            } else if parameter == 'max_full_utilization_rate' {
                interest_rate_config.max_full_utilization_rate = value;
            } else if parameter == 'zero_utilization_rate' {
                interest_rate_config.zero_utilization_rate = value;
            } else if parameter == 'rate_half_life' {
                interest_rate_config.rate_half_life = value;
            } else if parameter == 'target_rate_percent' {
                interest_rate_config.target_rate_percent = value;
            } else {
                assert!(false, "invalid-interest-rate-parameter");
            }

            assert_interest_rate_config(interest_rate_config);
            self.interest_rate_configs.write((pool_id, asset), interest_rate_config);
        }

        /// Returns the utilization based interest rate and the interest rate at full utilization
        /// for a specific asset in a pool.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `utilization` - utilization [SCALE]
        /// * `last_updated` - last point in time when the model was updated [seconds]
        /// * `last_full_utilization_rate` - interest value when utilization is 100% [SCALE]
        /// # Returns
        /// * `interest_rate` - new interest rate [SCALE]
        /// * `full_utilization_rate` - new interest rate at full utilization [SCALE]
        fn interest_rate(
            self: @ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_full_utilization_rate: u256,
        ) -> (u256, u256) {
            let model = self.interest_rate_configs.read((pool_id, asset));
            let time_delta = get_block_timestamp() - last_updated;
            calculate_interest_rate(model, utilization, time_delta, last_full_utilization_rate)
        }

        /// Returns the interest rate accumulator and the interest rate at full utilization
        /// for a specific asset in a pool.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `utilization` - current utilization [SCALE]
        /// * `last_updated` - last point in time when the model was updated [seconds]
        /// * `last_rate_accumulator` - previous interest rate accumulator [SCALE]
        /// * `last_full_utilization_rate` - interest rate at full utilization [SCALE]
        /// # Returns
        /// * `rate_accumulator` - new interest rate accumulator [SCALE]
        /// * `full_utilization_rate` - new interest rate at full utilization [SCALE]
        #[inline(always)]
        fn rate_accumulator(
            self: @ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_rate_accumulator: u256,
            last_full_utilization_rate: u256,
        ) -> (u256, u256) {
            // calculate utilization based on previous rate accumulator
            let (interest_rate, next_full_utilization_rate) = self
                .interest_rate(pool_id, asset, utilization, last_updated, last_full_utilization_rate);
            // calculate interest rate accumulator
            let rate_accumulator = calculate_rate_accumulator(last_updated, last_rate_accumulator, interest_rate);
            (rate_accumulator, next_full_utilization_rate)
        }
    }

    /// Calculates the interest rate based on the interest rate configuration and the current utilization
    /// # Arguments
    /// * `interest_rate_config` - interest rate configuration
    /// * `utilization` - current utilization [SCALE]
    /// * `time_delta` - elapsed time since last update [seconds]
    /// * `last_full_utilization_rate` - The interest value when utilization is 100% [SCALE]
    /// # Returns
    /// * `interest_rate` - new interest rate [SCALE]
    /// * `full_utilization_rate` - new full utilization interest rate [SCALE]
    fn calculate_interest_rate(
        interest_rate_config: InterestRateConfig, utilization: u256, time_delta: u64, last_full_utilization_rate: u256,
    ) -> (u256, u256) {
        let utilization = utilization / UTILIZATION_SCALE_TO_SCALE;
        let InterestRateConfig { target_utilization, zero_utilization_rate, target_rate_percent, .. } =
            interest_rate_config;

        // calculate interest rate based on utilization
        let next_full_utilization_rate = full_utilization_rate(
            interest_rate_config, time_delta.into(), utilization, last_full_utilization_rate
        );

        let target_rate = (((next_full_utilization_rate - zero_utilization_rate) * target_rate_percent) / SCALE)
            + zero_utilization_rate;

        let new_rate_per_second = if utilization < target_utilization {
            // For readability, the following formula is equivalent to:
            // let slope = ((target_rate - zero_utilization_rate) * UTILIZATION_SCALE) / target_utilization;
            // zero_utilization_rate + ((utilization * slope) / UTILIZATION_SCALE)
            zero_utilization_rate + (utilization * (target_rate - zero_utilization_rate)) / target_utilization
        } else {
            // For readability, the following formula is equivalent to:
            // let slope = (((next_full_utilization_rate - target_rate) * UTILIZATION_SCALE) / (UTILIZATION_SCALE - target_utilization));
            // target_rate + ((utilization - target_utilization) * slope) / UTILIZATION_SCALE

            target_rate
                + ((utilization - target_utilization) * (next_full_utilization_rate - target_rate))
                    / (SCALE - target_utilization)
        };

        (new_rate_per_second, next_full_utilization_rate)
    }

    /// Calculates the interest rate at full utilization based on the interest rate configuration
    /// and the current utilization
    /// # Arguments
    /// * `interest_rate_config` - interest rate configuration
    /// * `time_delta` - elapsed time since last update given in seconds [seconds]
    /// * `utilization` - utilization (% 5 decimals of precision) [utilization-scale] 
    /// * `full_utilization_rate` - interest value when utilization is 100%, given with 18 decimals of precision [SCALE]
    /// # Returns
    /// * `full_utilization_rate` - new interest rate at full utilization [SCALE]
    fn full_utilization_rate(
        interest_rate_config: InterestRateConfig, time_delta: u256, utilization: u256, full_utilization_rate: u256,
    ) -> u256 {
        let InterestRateConfig { min_target_utilization,
        max_target_utilization,
        rate_half_life,
        min_full_utilization_rate,
        max_full_utilization_rate,
        .. } =
            interest_rate_config;
        let half_life_scaled = rate_half_life * SCALE;

        let next_full_utilization_rate = if utilization < min_target_utilization {
            let utilization_delta = ((min_target_utilization - utilization) * SCALE) / min_target_utilization;
            let decay = half_life_scaled + (utilization_delta * time_delta);
            (full_utilization_rate * half_life_scaled) / decay
        } else if utilization > max_target_utilization {
            let utilization_delta = ((utilization - max_target_utilization) * SCALE)
                / (UTILIZATION_SCALE - max_target_utilization);
            let growth = half_life_scaled + (utilization_delta * time_delta);
            (full_utilization_rate * growth) / half_life_scaled
        } else {
            full_utilization_rate
        };

        if next_full_utilization_rate > max_full_utilization_rate {
            max_full_utilization_rate
        } else if next_full_utilization_rate < min_full_utilization_rate {
            min_full_utilization_rate
        } else {
            next_full_utilization_rate
        }
    }
}
