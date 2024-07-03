#[cfg(test)]
mod TestMath {
    use vesu::{math::{pow, pow_10, pow_10_or_0, pow_scale, log_10}, units::{SCALE}};

    #[test]
    fn test_pow_scale() {
        // Test with positive exponent
        assert!(pow_scale(4 * SCALE, 2, false) == (4 * 4) * SCALE, "SCALE^2");
        // Test with negative exponent
        assert!(pow_scale(100 * SCALE, 2, true) == 100000000000000, "SCALE^-2");
    }

    #[test]
    #[fuzzer(runs: 22, seed: 38)]
    fn test_pow_scale_fuzz(num: u16) {
        // Test with positive exponent
        assert!(pow_scale(num.into() * SCALE, 2, false) == (num.into() * num.into()) * SCALE, "SCALE^2");
    }

    #[test]
    fn test_pow() {
        // Test with zero exponent
        assert!(pow(10, 0) == 1, "10^0");
        // Test with one exponent
        assert!(pow(10, 1) == 10, "10^1");
        // Test with even exponent
        assert!(pow(10, 2) == 100, "10^2");
        // Test with odd exponent
        assert!(pow(10, 3) == 1000, "10^3");
    }

    #[test]
    fn test_pow_10() {
        // Test with 18
        assert!(pow_10(18) == 1_000_000_000_000_000_000, "10^18");
        // Test with 6
        assert!(pow_10(6) == 1_000_000, "10^6");
        // Test with other number
        assert!(pow_10(2) == 100, "10^2");
        assert!(pow_10(0) == 1, "10^0");
        assert!(pow_10_or_0(0) == 0, "10^0 keep 0");
    }

    #[test]
    fn test_log_10() {
        assert!(log_10(100 * SCALE) == 20, "1e20");
        assert!(log_10(SCALE) == 18, "1e18");
        assert!(log_10(1_000_000) == 6, "1e6");
        assert!(log_10(1_002_003) == 6, "1e6+");
        assert!(log_10(100) == 2, "100");
        assert!(log_10(11) == 1, "11");
        assert!(log_10(10) == 1, "10");
        assert!(log_10(9) == 0, "9");
        assert!(log_10(1) == 0, "1");
    }
}
