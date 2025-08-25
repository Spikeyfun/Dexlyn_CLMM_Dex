#[test_only]
module dexlyn_clmm::swap_math_test {
    use dexlyn_clmm::clmm_math;

    #[test]
    public entry fun test_exact_amount_in_capped_at_price_target() {
        let price = 18446744073709551616; // reserves(1, 1)
        let price_target = 18538748355542988169; // reserves(101, 100)
        let liquidity = 200_000_000;
        let amount = 100_000_000;
        let fee = 600;
        let a2b = false;
        let by_amount_in = true;
        let (amount_in, amount_out, sqrt_q, fee_amount) = clmm_math::compute_swap_step(
            price, price_target, liquidity, amount, fee, a2b, by_amount_in
        );

        assert!(amount_in == 997513, 100);
        assert!(fee_amount == 599, 101);
        assert!(amount_out == 992561, 102);
        assert!(amount_in + fee_amount <= amount, 103);
        let price_after_whole_input = clmm_math::get_next_sqrt_price_from_input(
            price, liquidity, amount, a2b
        );
        assert!(sqrt_q == price_target, 104);
        assert!(sqrt_q < price_after_whole_input, 105);
    }

    #[test]
    public entry fun test_exact_amount_out_capped_at_price_target() {
        let price = 18446744073709551616; // at reserves(1, 1)
        let price_target = 18538748355542988169; // at reserves(101, 100)
        let liquidity = 200_000_000;
        let amount = 100_000_000;
        let fee = 600;
        let a2b = false;
        let by_amount_in = false;
        let (amount_in, amount_out, sqrt_q, fee_amount) = clmm_math::compute_swap_step(
            price, price_target, liquidity, amount, fee, a2b, by_amount_in
        );
        assert!(amount_in == 997513, 200);
        assert!(fee_amount <= 599, 201);
        assert!(amount_out <= 992561, 202);
        let price_after_whole_output = clmm_math::get_next_sqrt_price_from_output(
            price, liquidity, amount, a2b
        );
        assert!(sqrt_q == price_target, 203);
        assert!(sqrt_q < price_after_whole_output, 204);
    }

    #[test]
    public entry fun test_exact_amount_in_fully_spent() {
        let price = 18446744073709551616; // at reserves(1, 1)
        let price_target = 58333726687135158848; // at reserves(1000, 100)
        let liquidity = 200_000_000;
        let amount = 100_000_000;
        let fee = 600;
        let a2b = false;
        let by_amount_in = true;
        let (amount_in, _amount_out, sqrt_q, fee_amount) = clmm_math::compute_swap_step(
            price, price_target, liquidity, amount, fee, a2b, by_amount_in
        );
        assert!(amount_in + fee_amount == amount, 303);
        let price_after_whole_input_less_fee = clmm_math::get_next_sqrt_price_from_input(
            price, liquidity, amount - fee_amount, a2b
        );
        assert!(sqrt_q < price_target, 304);
        assert!(sqrt_q == price_after_whole_input_less_fee, 305);
    }

    #[test]
    public entry fun test_exact_amount_out_fully_received() {
        let price = 18446744073709551616; // at reserves(1, 1)
        let price_target = 184467440737095516160; // at reserves(10000, 100)
        let liquidity = 200_000_000;
        let amount = 100_000_000;
        let fee = 600;
        let a2b = false;
        let by_amount_in = false;
        let (amount_in, amount_out, sqrt_q, fee_amount) = clmm_math::compute_swap_step(
            price, price_target, liquidity, amount, fee, a2b, by_amount_in
        );
        assert!(amount_in == 200000000, 401);
        assert!(fee_amount == 120073, 402);
        assert!(amount_out == amount, 403);
        let price_after_whole_output = clmm_math::get_next_sqrt_price_from_output(
            price, liquidity, amount, a2b
        );
        assert!(sqrt_q < price_target, 403);
        assert!(sqrt_q == price_after_whole_output, 404);
    }

    #[test]
    public entry fun test_amount_out_is_capped() {
        let price = 97167715013977308122856;
        let price_target = 338272718368148901;
        let liquidity = 37100321005938362671;
        let amount = 1;
        let fee = 1;
        let a2b = true;
        let by_amount_in = false;
        let (amount_in, amount_out, sqrt_q, fee_amount) = clmm_math::compute_swap_step(
            price, price_target, liquidity, amount, fee, a2b, by_amount_in
        );
        assert!(amount_in == 1, 500);
        assert!(fee_amount == 1, 501);
        assert!(amount_out == 1, 502);
        assert!(sqrt_q == price - 1, 503);
    }

    #[test]
    public entry fun test_target_price_uses_partial_input() {
        let price = 2;
        let price_target = 1;
        let liquidity = 1;
        let amount = 18446744073709551615; // 2^64-1
        let fee = 1;
        let a2b = true;
        let by_amount_in = true;
        let (amount_in, amount_out, sqrt_q, fee_amount) = clmm_math::compute_swap_step(
            price, price_target, liquidity, amount, fee, a2b, by_amount_in
        );
        assert!(amount_in == 9223372036854775808, 600);
        assert!(fee_amount == 9223381260237, 601);
        assert!(amount_in + fee_amount <= amount, 602);
        assert!(amount_out == 0, 603);
        assert!(sqrt_q == 1, 604);
    }

    #[test]
    public entry fun test_entire_input_taken_as_fee() {
        let price = 97167715013977308122856;
        let price_target = 338272718368148901;
        let liquidity = 37100321005938362671;
        let amount = 10;
        let fee = 1000000;
        let a2b = true;
        let by_amount_in = true;
        let (amount_in, amount_out, sqrt_q, fee_amount) = clmm_math::compute_swap_step(
            price, price_target, liquidity, amount, fee, a2b, by_amount_in
        );
        assert!(amount_in == 0, 700);
        assert!(fee_amount == 10, 701);
        assert!(amount_out == 0, 702);
        assert!(sqrt_q == price, 703);
    }

    #[test]
    public entry fun test_intermediate_insufficient_liquidity_zero_for_one_exact_output() {
        let sqrt_p = 4722366482869645213696;
        let sqrt_p_target = sqrt_p * 11 / 10;
        let liquidity = 1024;
        let amount_remaining = 4;
        let fee_pips = 3000;
        let a2b = false;
        let by_amount_in = false;
        let (amount_in, amount_out, sqrt_q, fee_amount) = clmm_math::compute_swap_step(
            sqrt_p, sqrt_p_target, liquidity, amount_remaining, fee_pips, a2b, by_amount_in
        );
        assert!(amount_out == 0, 800);
        assert!(sqrt_q == sqrt_p_target, 801);
        assert!(amount_in == 26215, 802);
        assert!(fee_amount == 79, 803);
    }
}
