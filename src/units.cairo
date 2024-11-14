const SCALE: u256 = 1_000_000_000_000_000_000; // 1e18
const SCALE_128: u128 = 1_000_000_000_000_000_000; // 1e18
const PERCENT: u256 = 10_000_000_000_000_000; // 1e16
const FRACTION: u256 = 10_000_000_000_000; // 1e13
const YEAR_IN_SECONDS: u256 = consteval_int!(360 * 24 * 60 * 60);
const DAY_IN_SECONDS: u64 = consteval_int!(24 * 60 * 60);
const INFLATION_FEE_SHARES: u256 = 1000;
// has to be greater than INFLATION_FEE_SHARES such that total_collateral_shares is not reset to 0
const INFLATION_FEE: u256 = 2000;
