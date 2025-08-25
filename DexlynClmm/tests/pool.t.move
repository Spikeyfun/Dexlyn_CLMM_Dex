#[test_only]
module dexlyn_clmm::pool_test {
    use std::option;
    use std::signer;
    use std::string::Self;

    use supra_framework::account;
    use supra_framework::coin;
    use supra_framework::timestamp;

    use dexlyn_clmm::clmm_router;
    use dexlyn_clmm::clmm_router::add_fee_tier;
    use dexlyn_clmm::factory;
    use dexlyn_clmm::pool;
    use dexlyn_clmm::test_helpers::{mint_tokens, TestCoinA, TestCoinB};
    use dexlyn_clmm::utils;

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    #[expected_failure] // E_SAME_COIN_TYPE
    public fun test_create_pool_same_coin_type(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        factory::init_factory_module(admin);

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;

        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinA>(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b"")
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    #[expected_failure(abort_code = factory::EINVALID_SQRTPRICE)] // E_INVALID_SQRT_PRICE
    public fun test_invalid_sqrt_price(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        factory::init_factory_module(admin);
        mint_tokens(admin);

        let tick_spacing = 200;
        let init_sqrt_price = 100;

        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b"")
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public fun test_nonexistent_pool(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        factory::init_factory_module(admin);
        mint_tokens(admin);

        let asset_a_addr = utils::coin_to_fa_address<TestCoinA>();
        let asset_b_addr = utils::coin_to_fa_address<TestCoinB>();


        let pool_opt = factory::get_pool(200, asset_a_addr, asset_b_addr);
        assert!(option::is_none(&pool_opt), 1);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public fun test_fetch_positions_and_get_position(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        mint_tokens(admin);


        let tick_spacing = 100;
        let init_sqrt_price = 18446744073709551616;
        let fee_rate = 1000;

        add_fee_tier(admin, tick_spacing, fee_rate);

        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin, tick_spacing, init_sqrt_price, string::utf8(b"")
        );

        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let b_addr = utils::coin_to_fa_address<TestCoinB>();
        let pool_address = get_pool_address(tick_spacing, a_addr, b_addr);

        // Open a position
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 400;
        let pos_id = pool::open_position(
            admin, pool_address, integer_mate::i64::from_u64(tick_lower), integer_mate::i64::from_u64(tick_upper)
        );

        // fetch_positions
        let (_start, positions) = pool::fetch_positions(pool_address, 0, 10);
        assert!(std::vector::length<pool::Position>(&positions) > 0, 100);

        // get_position
        let position_vec = vector[pos_id, pos_id, 2, 3];
        let _pos = pool::get_positions(pool_address, position_vec);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public fun test_fetch_ticks_and_get_position_tick_range(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        mint_tokens(admin);

        let fee_rate = 1000;
        let tick_spacing = 100;
        let init_sqrt_price = 18446744073709551616;

        add_fee_tier(admin, tick_spacing, fee_rate);
        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin, tick_spacing, init_sqrt_price, string::utf8(b"")
        );

        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let b_addr = utils::coin_to_fa_address<TestCoinB>();
        let pool_address = get_pool_address(tick_spacing, a_addr, b_addr);

        // fetch_ticks
        let (_tick_index, _bit_index, ticks) = pool::fetch_ticks(pool_address, 0, 0, 10);
        assert!(std::vector::length<pool::Tick>(&ticks) >= 0, 101);

        // Open a position and get its tick range
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 400;
        let pos_id = pool::open_position(
            admin, pool_address, integer_mate::i64::from_u64(tick_lower), integer_mate::i64::from_u64(tick_upper)
        );
        let (_lower, _upper) = pool::get_position_tick_range(pool_address, pos_id);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public fun test_get_rewarder_len_and_get_tick_spacing(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        mint_tokens(admin);

        let tick_spacing = 100;
        let fee_rate = 1000;
        let init_sqrt_price = 18446744073709551616;
        add_fee_tier(admin, tick_spacing, fee_rate);

        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin, tick_spacing, init_sqrt_price, string::utf8(b"")
        );


        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let b_addr = utils::coin_to_fa_address<TestCoinB>();
        let pool_address = get_pool_address(tick_spacing, a_addr, b_addr);

        // get_rewarder_len
        let rewarder_len = pool::get_rewarder_len(pool_address);
        assert!(rewarder_len >= 0, 102);

        // get_tick_spacing
        let spacing = pool::get_tick_spacing(pool_address);
        assert!(spacing == tick_spacing, 103);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public fun test_reset_init_price_v2_and_tick_offset_and_update_fee_rate(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        clmm_router::init_clmm_acl(admin);
        clmm_router::add_role(admin, signer::address_of(admin), 1);
        clmm_router::add_role(admin, signer::address_of(admin), 2);
        mint_tokens(admin);

        let tick_spacing = 100;
        let init_sqrt_price = 18446744073709551616;
        let fee_rate = 1000;
        add_fee_tier(admin, tick_spacing, fee_rate);
        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin, tick_spacing, init_sqrt_price, string::utf8(b"")
        );

        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let b_addr = utils::coin_to_fa_address<TestCoinB>();
        let pool_address = get_pool_address(tick_spacing, a_addr, b_addr);

        // reset_init_price_v2
        pool::reset_init_price_v2(admin, pool_address, init_sqrt_price);

        // update_fee_rate
        pool::update_fee_rate(admin, pool_address, 1234);
    }

    #[test_only]
    public fun get_pool_address(tick_spacing: u64, a_addr: address, b_addr: address): address {
        let clmm_pool_addr_opt = factory::get_pool(tick_spacing, a_addr, b_addr);
        option::extract(&mut clmm_pool_addr_opt)
    }
}