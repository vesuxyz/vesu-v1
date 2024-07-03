#[derive(PartialEq, Copy, Drop, Serde, starknet::Store)]
struct InterestRateModel {
    min_target_utilization: u256,
    max_target_utilization: u256,
    target_utilization: u256,
    min_full_utilization_rate: u256,
    max_full_utilization_rate: u256,
    zero_utilization_rate: u256,
    rate_half_life: u256,
    target_rate_percent: u256,
}

#[starknet::component]
mod interest_rate_model_component {
    use starknet::{ContractAddress, get_block_timestamp};
    use vesu::{
        units::{SCALE}, common::calculate_rate_accumulator,
        extension::components::interest_rate_model::InterestRateModel
    };

    const UTILIZATION_SCALE: u256 = 100_000; // 1e5
    const UTILIZATION_SCALE_TO_SCALE: u256 = 10_000_000_000_000; // 1e13

    #[storage]
    struct Storage {
        // (pool_id, asset) -> interest rate model
        interest_rate_models: LegacyMap::<(felt252, ContractAddress), InterestRateModel>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[generate_trait]
    impl InterestRateModelTrait<TContractState, +HasComponent<TContractState>> of Trait<TContractState> {
        /// # Arguments
        /// * `pool_id` - Id of the pool
        /// * `asset` - Address of the asset
        /// * `utilization` - utilization [SCALE]
        /// * `last_updated` - The last time when the model was updated [seconds]
        /// * `last_full_utilization_rate` - The interest value when utilization is 100% [SCALE]
        /// # Returns
        /// * The new interest rate [SCALE]
        /// * The new full utilization interest rate [SCALE]
        fn interest_rate(
            self: @ComponentState<TContractState>,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_full_utilization_rate: u256,
        ) -> (u256, u256) {
            let model = self.interest_rate_models.read((pool_id, asset));
            let time_delta = get_block_timestamp() - last_updated;
            calculate_interest_rate(model, utilization, time_delta, last_full_utilization_rate)
        }

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

        fn set_model(
            ref self: ComponentState<TContractState>, pool_id: felt252, asset: ContractAddress, model: InterestRateModel
        ) {
            let current_model: InterestRateModel = self.interest_rate_models.read((pool_id, asset));
            assert!(current_model.max_target_utilization == 0, "model-already-set");
            self.interest_rate_models.write((pool_id, asset), model);
        }
    }

    /// # Arguments
    /// * `model` - The interest rate model
    /// * `utilization` - utilization [SCALE]
    /// * `time_delta` - The elapsed time since last update [seconds]
    /// * `last_full_utilization_rate` - The interest value when utilization is 100% [SCALE]
    /// # Returns
    /// * The new interest rate [SCALE]
    /// * The new full utilization interest rate [SCALE]
    fn calculate_interest_rate(
        model: InterestRateModel, utilization: u256, time_delta: u64, last_full_utilization_rate: u256,
    ) -> (u256, u256) {
        let utilization = utilization / UTILIZATION_SCALE_TO_SCALE;
        let InterestRateModel{target_utilization, zero_utilization_rate, .. } = model;

        // calculate interest rate based on utilization
        let next_full_utilization_rate = full_utilization_rate(
            model, time_delta.into(), utilization, last_full_utilization_rate
        );

        let target_rate = (((next_full_utilization_rate - zero_utilization_rate) * model.target_rate_percent) / SCALE)
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

    /// # Arguments
    /// * `time_delta` - The elapsed time since last update given in seconds
    /// * `utilization` - The utilization %, given with 5 decimals of precision
    /// * `full_utilization_rate` - The interest value when utilization is 100%, given with 18 decimals of precision
    /// * `model` - The variable interest rate model
    /// # Returns
    /// * The new maximum interest rate
    fn full_utilization_rate(
        model: InterestRateModel, time_delta: u256, utilization: u256, full_utilization_rate: u256,
    ) -> u256 {
        let InterestRateModel{min_target_utilization, max_target_utilization, .. } = model;
        let half_life_scale = model.rate_half_life * SCALE;

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

        if next_full_utilization_rate > model.max_full_utilization_rate {
            model.max_full_utilization_rate
        } else if next_full_utilization_rate < model.min_full_utilization_rate {
            model.min_full_utilization_rate
        } else {
            next_full_utilization_rate
        }
    }
}
