pub const SCALE: u256 = 1_000_000_000_000_000_000; // 1e18
pub const SCALE_128: u128 = 1_000_000_000_000_000_000; // 1e18
pub const PERCENT: u256 = 10_000_000_000_000_000; // 1e16
pub const FRACTION: u256 = 10_000_000_000_000; // 1e13
pub const YEAR_IN_SECONDS: u256 = 31_104_000; // 360 * 24 * 60 * 60
pub const DAY_IN_SECONDS: u64 = 86_400; // 24 * 60 * 60
pub const INFLATION_FEE_SHARES: u256 = 1000;
// has to be greater than INFLATION_FEE_SHARES such that total_collateral_shares is not reset to 0
pub const INFLATION_FEE: u256 = 2000;
