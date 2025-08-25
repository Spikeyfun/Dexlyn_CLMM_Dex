#[test_only]
module dexlyn_clmm::tick_math_test {
    use dexlyn_clmm::tick_math;
    use integer_mate::i64;

    #[test]
    #[expected_failure(abort_code = tick_math::EINVALID_TICK)] // EINVALID_TICK
    public entry fun test_get_sqrt_price_at_tick_too_low() {
        let tick = i64::add(tick_math::min_tick(), i64::neg_from(1));
        tick_math::get_sqrt_price_at_tick(tick);
    }

    #[test]
    #[expected_failure(abort_code = tick_math::EINVALID_TICK)] // EINVALID_TICK
    public entry fun test_get_sqrt_price_at_tick_too_high() {
        let tick = i64::add(tick_math::max_tick(), i64::from(1));
        tick_math::get_sqrt_price_at_tick(tick);
    }

    #[test]
    public entry fun test_get_sqrt_price_at_tick_min() {
        let sqrt_price = tick_math::get_sqrt_price_at_tick(tick_math::min_tick());
        assert!(sqrt_price == tick_math::min_sqrt_price(), 100);
    }

    #[test]
    public entry fun test_get_sqrt_price_at_tick_max() {
        let sqrt_price = tick_math::get_sqrt_price_at_tick(tick_math::max_tick());
        assert!(sqrt_price == tick_math::max_sqrt_price(), 101);
    }

    #[test]
    #[expected_failure(abort_code = tick_math::EINVALID_SQRT_PRICE)] // EINVALID_SQRT_PRICE
    public entry fun test_get_tick_at_sqrt_price_too_low() {
        tick_math::get_tick_at_sqrt_price(tick_math::min_sqrt_price() - 1);
    }

    #[test]
    #[expected_failure(abort_code = tick_math::EINVALID_SQRT_PRICE)] // EINVALID_SQRT_PRICE
    public entry fun test_get_tick_at_sqrt_price_too_high() {
        tick_math::get_tick_at_sqrt_price(tick_math::max_sqrt_price() + 1);
    }

    #[test]
    public entry fun test_get_tick_at_sqrt_price_min() {
        let tick = tick_math::get_tick_at_sqrt_price(tick_math::min_sqrt_price());
        assert!(tick == tick_math::min_tick(), 102);
    }

    #[test]
    public entry fun test_get_tick_at_sqrt_price_max() {
        let tick = tick_math::get_tick_at_sqrt_price(tick_math::max_sqrt_price());
        assert!(tick == tick_math::max_tick(), 103);
    }

    #[test]
    public entry fun test_tick_and_sqrt_price_consistency_positive() {
        let tick = i64::from(1000);
        let sqrt_price = tick_math::get_sqrt_price_at_tick(tick);
        let tick_back = tick_math::get_tick_at_sqrt_price(sqrt_price);
        let sqrt_price_back = tick_math::get_sqrt_price_at_tick(tick_back);

        assert!(sqrt_price == sqrt_price_back && tick == tick_back, 104);
    }

    #[test]
    public entry fun test_tick_and_sqrt_price_consistency_negative() {
        let tick = i64::neg_from(1000);
        let sqrt_price = tick_math::get_sqrt_price_at_tick(tick);
        let tick_back = tick_math::get_tick_at_sqrt_price(sqrt_price);
        let sqrt_price_back = tick_math::get_sqrt_price_at_tick(tick_back);

        assert!(sqrt_price == sqrt_price_back && tick == tick_back, 104);
    }
}
