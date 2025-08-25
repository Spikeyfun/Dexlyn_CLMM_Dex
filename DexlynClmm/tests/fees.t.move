#[test_only]
module dexlyn_clmm::fees_test {
    use std::signer;
    use std::signer::address_of;
    use std::string::{Self, utf8};
    use std::vector;

    use supra_framework::account;
    use supra_framework::timestamp;

    use dexlyn_clmm::clmm_router::{
        add_fee_tier,
        add_liquidity,
        add_liquidity_fix_value,
        collect_fee,
        collect_protocol_fee,
        remove_liquidity,
        swap
    };
    use dexlyn_clmm::config;
    use dexlyn_clmm::factory;
    use dexlyn_clmm::fee_tier;
    use dexlyn_clmm::pool;
    use dexlyn_clmm::test_helpers::setup_fungible_assets;
    use dexlyn_clmm::tick_math;
    use dexlyn_clmm::token_factory;

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public entry fun test_swap_fees_distribution(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        factory::init_factory_module(admin);

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 1000000;
        let amount_b = 1000000;
        let fix_a = true;
        let tick_lower = 18446744073709541616; // -10000
        let tick_upper = 10000;
        let is_new_position = true;

        add_fee_tier(admin, tick_spacing, 1000);
        let pool_address = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );

        add_liquidity_fix_value(
            admin,
            pool_address,
            amount_a,
            amount_b,
            fix_a,
            tick_lower,
            tick_upper,
            is_new_position,
            0,
        );

        let token_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        // Swap A->B
        let a2b = true;
        let exact_input = true;
        let amount = 100000;
        let min_or_max = 0;
        let price_limit = tick_math::min_sqrt_price() + 1;
        let referral = string::utf8(b"");
        swap(admin, pool_address, a2b, exact_input, amount, min_or_max, price_limit, referral);

        let _calculated_result = pool::calculate_swap_result(
            pool_address,
            a2b,
            exact_input,
            amount
        );
        // actual fee amount after swap
        // fee amount = swapamount * fee_rate / 1000000
        //            = 100000 * 1000 / 1000000 = 100

        let token_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);


        assert!(token_balance_b_after > token_balance_b_before, 100);

        // Collect LP fees
        let fee_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let _fee_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);
        collect_fee(admin, pool_address, 1);

        // LP fee collection = fee amount - protocol fee= 100 - 34 = 66

        let fee_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let _fee_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        let lp_collect_fees_a = fee_a_after - fee_a_before;
        assert!(lp_collect_fees_a == 65, 101); // 65

        // Protocol fee collection = fee amount * protocol_fee_rate / 10000
        //                         = 100 * 3333 / 10000 = 33.33
        collect_protocol_fee(admin, pool_address);

        let protocol_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let _protocol_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        let protocol_fees = protocol_a_after - fee_a_after;
        assert!(protocol_fees == 34, 102);
    }

    // LP fee collection after partial and full withdrawal
    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_lp_fee_collection_on_withdraw(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 1;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 1000000;
        let amount_b = 1000000;
        let _fix_a = true;
        let tick_lower = 18446744073709541616; // -10000
        let tick_upper = 10000;
        let is_new_position = true;

        factory::init_factory_module(admin);
        add_fee_tier(admin, tick_spacing, 1000);

        let pool_address = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );
        add_liquidity(
            admin,
            pool_address,
            2541592,
            amount_a,
            amount_b,
            tick_lower,
            tick_upper,
            is_new_position,
            0,
        );

        let a2b = true;
        let exact_input = true;
        let amount = 100000;
        let min_or_max = 0;
        let price_limit = tick_math::min_sqrt_price() + 1;
        let referral = string::utf8(b"");
        swap(admin, pool_address, a2b, exact_input, amount, min_or_max, price_limit, referral);

        let balance_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);

        remove_liquidity(
            admin,
            pool_address,
            2541592,
            0,
            0,
            1,
            true
        ); // remove liquidity with fees

        let balance_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        assert!(balance_a_after - balance_a_before > amount_a, 103); // balance will have: deposited liquidity + fees
    }


    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_no_swap_no_fees(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        factory::init_factory_module(admin);

        add_fee_tier(admin, tick_spacing, 1000);
        let pool_address = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );
        add_liquidity_fix_value(
            admin,
            pool_address,
            1000000,
            1000000,
            true,
            0,
            10000,
            true,
            0,
        );

        let balance_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        collect_fee(admin, pool_address, 1);

        let balance_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!(balance_a_after == balance_a_before && balance_b_after == balance_b_before, 105); // No fees accrued
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = pool::EPOSITION_NOT_EXIST)] // EPOSITION_NOT_EXIST
    public entry fun test_collect_fee_position_not_found(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        factory::init_factory_module(admin);
        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        add_fee_tier(admin, tick_spacing, 1000);
        let pool_address = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );

        collect_fee(admin, pool_address, 99); // position doesn't exist
    }


    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm, user= @0x123
    )]
    #[expected_failure(abort_code = config::ENOT_HAS_PRIVILEGE)] // ENOT_HAS_PRIVILEGE
    public entry fun test_collect_protocol_fee_not_authorized(admin: &signer, user: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        factory::init_factory_module(admin);
        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        add_fee_tier(admin, tick_spacing, 1000);
        let pool_address = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );

        collect_protocol_fee(user, pool_address);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = fee_tier::EINVALID_FEE_RATE)] // EINVALID_FEE_RATE
    public entry fun test_add_fee_tier_too_high(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        let tick_spacing = 200;

        add_fee_tier(admin, tick_spacing, 999999);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_calculate_multiple_fees(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        factory::init_factory_module(admin);

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 1000000;
        let amount_b = 1000000;
        let fix_a = true;
        let tick_lower = 18446744073709541616; // -10000
        let tick_upper = 10000;
        let is_new_position = true;

        add_fee_tier(admin, tick_spacing, 1000);
        let pool_address = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b
        );

        // Create multiple positions
        add_liquidity_fix_value(
            admin,
            pool_address,
            amount_a,
            amount_b,
            fix_a,
            tick_lower,
            tick_upper,
            is_new_position,
            0
        );

        add_liquidity_fix_value(
            admin,
            pool_address,
            amount_a,
            amount_b,
            fix_a,
            tick_lower + 1000,
            tick_upper + 1000,
            is_new_position,
            0
        );

        // Perform some swaps to generate fees
        let a2b = true;
        let exact_input = true;
        let amount = 100000;
        let min_or_max = 0;
        let price_limit = tick_math::min_sqrt_price() + 1;
        let referral = string::utf8(b"");

        swap(
            admin,
            pool_address,
            false,
            exact_input,
            amount,
            min_or_max,
            tick_math::max_sqrt_price(),
            referral
        );
        swap(admin, pool_address, a2b, exact_input, amount, min_or_max, price_limit, referral);

        let position_indices = vector[0, 1, 4, 2, 3];
        let results = pool::calculate_positions_fees(pool_address, position_indices);

        assert!(vector::length(&results) == 2, 1);
    }
}
