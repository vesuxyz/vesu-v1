use vesu::units::{SCALE};

const UTILIZATION_SCALE: u256 = 100_000; // 1e5
const UTILIZATION_SCALE_TO_SCALE: u256 = 10_000_000_000_000; // 1e13

#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct InterestRateConfig {
    min_target_utilization: u256,
    max_target_utilization: u256,
    target_utilization: u256,
    min_full_utilization_rate: u256,
    max_full_utilization_rate: u256,
    zero_utilization_rate: u256,
    rate_half_life: u256,
    target_rate_percent: u256,
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
    assert!(
        min_full_utilization_rate <= max_full_utilization_rate, "min-full-utilization-rate-gt-max-full-utilization-rate"
    );
    assert!(zero_utilization_rate <= min_full_utilization_rate, "zero-utilization-rate-gt-min-full-utilization-rate");
    assert!(rate_half_life > 0, "rate-half-life-lte-0");
    assert!(target_rate_percent <= SCALE, "target-rate-percent-gt-100%");
    assert!(target_rate_percent > 0, "target-rate-percent-lte-0");
}

#[starknet::component]
mod interest_rate_model_component {
    use starknet::{ContractAddress, get_block_timestamp};
    use vesu::{
        units::{SCALE}, common::calculate_rate_accumulator,
        extension::components::interest_rate_model::{
            InterestRateConfig, assert_interest_rate_config, UTILIZATION_SCALE, UTILIZATION_SCALE_TO_SCALE
        },
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
    /// * `time_delta` - elapsed time since last update given in seconds
    /// * `utilization` - utilization (% 5 decimals of precision)
    /// * `full_utilization_rate` - interest value when utilization is 100%, given with 18 decimals of precision
    /// # Returns
    /// * `full_utilization_rate` - new interest rate at full utilization
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
        let half_life_scale = rate_half_life * SCALE;

        let next_full_utilization_rate = if utilization < min_target_utilization {
            let utilization_delta = ((min_target_utilization - utilization) * SCALE) / min_target_utilization;
            let decay = half_life_scale + (utilization_delta * time_delta);
            (full_utilization_rate * half_life_scale) / decay
        } else if utilization > max_target_utilization {
            let utilization_delta = ((utilization - max_target_utilization) * SCALE)
                / (UTILIZATION_SCALE - max_target_utilization);
            let growth = half_life_scale + (utilization_delta * time_delta);
            (full_utilization_rate * growth) / half_life_scale
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
