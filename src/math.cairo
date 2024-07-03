use vesu::units::SCALE;

/// Adapted from https://github.com/influenceth/cubit/blob/main/src/f128/math/core.cairo#L240
/// # Arguments
/// * `x` - base [SCALE]
/// * `n` - exponent [decimal]
/// * `is_negative` - true if `n` is negative
/// # Returns
/// * `result` - [SCALE]
fn pow_scale(mut x: u256, mut n: u256, is_negative: bool) -> u256 {
    if is_negative {
        x = SCALE * SCALE / x;
    }

    if n == 0 {
        return SCALE;
    }

    let mut y = SCALE;
    let two = integer::u256_as_non_zero(2);

    while n > 1 {
        let (div, rem, _) = integer::u256_safe_divmod(n, two);

        if rem == 1 {
            y = x * y / SCALE;
        }

        x = x * x / SCALE;
        n = div;
    };

    x * y / SCALE
}

// From satoru/src/utils/arrays.cairo
/// Raise a number to a power, computes x^n.
/// # Arguments
/// * `x` - number to raise
/// * `n` - exponent
/// # Returns
/// * `u256` - result of x raised to the power of n
fn pow(x: u256, n: usize) -> u256 {
    if x == 0 {
        return 0;
    }
    if n == 0 {
        1
    } else if n == 1 {
        x
    } else if (n & 1) == 1 {
        x * pow(x * x, n / 2)
    } else {
        pow(x * x, n / 2)
    }
}

/// Same as pow_10, but returns 0 if n is 0.
/// # Arguments
/// * `n` - exponent.
/// # Returns
/// * `u256` - result
fn pow_10_or_0(n: usize) -> u256 {
    if n == 0 {
        0
    } else {
        pow_10(n)
    }
}

/// Raise 10 to the power of n.
/// # Arguments
/// * `n` - exponent
/// # Returns
/// * `u256` - result
fn pow_10(n: usize) -> u256 {
    if n == 18 {
        1_000_000_000_000_000_000
    } else if n == 6 {
        1_000_000
    } else {
        pow(10, n)
    }
}

/// Compute the log base 10 of a number
/// # Arguments
/// * `x` - number to compute the log of
/// # Returns
/// * `u8` - log base 10 of x
fn log_10(mut x: u256) -> u8 {
    assert!(x != 0, "log-10-zero");
    if x == SCALE {
        return 18;
    } else if x == 1_000_000 {
        return 6;
    }

    let mut n = 0;
    while x >= SCALE {
        x = x / SCALE;
        n += 18;
    };
    while x >= 10_000 {
        x = x / 10_000;
        n = n + 4;
    };
    while x >= 10 {
        x = x / 10;
        n = n + 1;
    };

    n
}

/// Same as log_10, but returns 0 if x is 0.
/// # Arguments
/// * `x` - number to compute the log of
/// # Returns
/// * `u8` - log base 10 of x
fn log_10_or_0(mut x: u256) -> u8 {
    if x == 0 {
        0
    } else {
        log_10(x)
    }
}
