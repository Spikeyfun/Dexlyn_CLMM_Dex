#[test_only]
module dexlyn_clmm::add_liquidity_test {
    use std::option;
    use std::signer::{Self, address_of};
    use std::string::{Self, utf8};
    use std::vector;

    use supra_framework::account;
    use supra_framework::coin::{Self, migrate_to_fungible_store};
    use supra_framework::timestamp;

    use dexlyn_clmm::clmm_math;
    use dexlyn_clmm::clmm_router::{
        add_fee_tier,
        add_liquidity,
        add_liquidity_coin_asset,
        add_liquidity_coin_coin,
        add_liquidity_fix_value,
        add_liquidity_fix_value_coin_asset,
        create_pool_coin_asset,
        create_pool_coin_coin,
        remove_liquidity
    };
    use dexlyn_clmm::factory;
    use dexlyn_clmm::fee_tier;
    use dexlyn_clmm::fee_tier::get_fee_rate;
    use dexlyn_clmm::pool;
    use dexlyn_clmm::pool::get_pool_liquidity;
    use dexlyn_clmm::position_nft;
    use dexlyn_clmm::test_helpers::{
        mint_tokens,
        setup_fungible_assets,
        TestCoinA,
        TestCoinB
    };
    use dexlyn_clmm::token_factory;
    use dexlyn_clmm::utils;

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_create_and_add_liquidity(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));

        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 100000;
        let amount_b = 400000;
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 16000;
        let fee_rate = 1000;

        factory::init_factory_module(admin);

        add_fee_tier(admin, tick_spacing, fee_rate);
        assert!(fee_rate == get_fee_rate(tick_spacing), 1001);

        let user_balance_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

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
            true,
            tick_lower,
            tick_upper,
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 181602, 1002); // min[181602.549077, 20201666.612228]

        let user_balance_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_a_before - user_balance_a_after) == 100000, 1003); // 99999.6976491452
        assert!((user_balance_b_before - user_balance_b_after) == 3596, 1004); // 3595.782535883948
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        user_a = @0xA,
        user_b = @0xB,
    )]
    public entry fun test_nft_transfer_and_close_position(
        user_a: &signer,
        user_b: &signer,
        supra_framework: &signer,
        admin: &signer
    ) {
        // Setup: mint tokens to user_a
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user_a));
        account::create_account_for_test(signer::address_of(user_b));
        timestamp::set_time_has_started_for_testing(supra_framework);
        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 100000;
        let amount_b = 400000;
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 16000;
        let fee_rate = 1000;

        factory::init_factory_module(admin);
        add_fee_tier(admin, tick_spacing, fee_rate);
        assert!(fee_rate == get_fee_rate(tick_spacing), 2001);

        let pool_address = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );
        let pool_index = dexlyn_clmm::pool::get_pool_index(pool_address);

        let position_index = 1;
        let collection = dexlyn_clmm::position_nft::collection_name(tick_spacing, token_a, token_b);
        let nft_name = dexlyn_clmm::position_nft::position_name(pool_index, position_index);
        add_liquidity_fix_value(
            admin,
            pool_address,
            amount_a,
            amount_b,
            true,
            tick_lower,
            tick_upper,
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 181602, 2002); // min[181602.549077, 20201666.612228]

        let token_address = aptos_token_objects::token::create_token_address(
            &pool_address,
            &collection,
            &nft_name
        );

        // check nft owner and is vaild
        let is_valid_nft = position_nft::is_valid_nft(token_address, pool_address);
        assert!(is_valid_nft == true, 1001);

        let token_obj = aptos_framework::object::address_to_object<aptos_token_objects::token::Token>(token_address);
        aptos_framework::object::transfer(admin, token_obj, signer::address_of(user_b));

        // get the NFT details from Token Address
        let vec_token_address = vector[token_address, token_address];
        let _nft_details = position_nft::get_nft_details(vec_token_address);


        remove_liquidity(
            user_b,
            pool_address,
            181602,
            0,
            0,
            1,
            true
        );

        let pool_liquidity2 = get_pool_liquidity(pool_address);
        assert!(pool_liquidity2 == 0, 2003);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_add_liquidity_full_range(admin: &signer, supra_framework: &signer) {
        let admin_addr = signer::address_of(admin);
        account::create_account_for_test(admin_addr);

        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 2;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 100000;
        let amount_b = 100000;
        let tick_lower = 18446744073709107980; // -min_lower
        let tick_upper = 443636;

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

        let user_balance_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        add_liquidity_fix_value(
            admin,
            pool_address,
            amount_a,
            amount_b,
            true,
            tick_lower,
            tick_upper,
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 100000, 1001); // min[100000.000023, 100000.000023]

        let user_balance_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_a_before - user_balance_a_after) == 100000, 1002); // 99999.9999767165
        assert!((user_balance_b_before - user_balance_b_after) == 100000, 1003); // 99999.9999767165

        add_liquidity(
            admin,
            pool_address,
            25000,
            amount_a,
            amount_b,
            tick_lower,
            tick_upper,
            true,
            1,
        );
        let pool_liquidity2 = get_pool_liquidity(pool_address);
        assert!(pool_liquidity2 == 100000 + 25000, 1004);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_liquidity_below_current_tick(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616; // at 0
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

        let amount_a = 100000;
        let amount_b = 100000;
        let tick_lower = 18446744073709549616; // -2000
        let tick_upper = 18446744073709550616; // -1000

        let user_balance_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        add_liquidity_fix_value(
            admin,
            pool_address,
            amount_a,
            amount_b,
            false,
            tick_lower,
            tick_upper,
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 0, 1001); // one-side-liquidity

        let user_balance_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_a_before - user_balance_a_after) == 0, 1002);
        assert!((user_balance_b_before - user_balance_b_after) == 100000, 1003); // 99999.98553585552
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_liquidity_above_current_tick(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616; // at 0
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

        let amount_a = 100000;
        let amount_b = 100000;
        let tick_lower = 16000;
        let tick_upper = 26000;

        let user_balance_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        add_liquidity_fix_value(
            admin,
            pool_address,
            amount_a,
            amount_b,
            true,
            tick_lower,
            tick_upper,
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 0, 1001); // one-side-liquidity

        let user_balance_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_a_before - user_balance_a_after) == 100000, 1002); // 99999.3271327113
        assert!((user_balance_b_before - user_balance_b_after) == 0, 1003);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_multiple_overlapping_positions(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616; // at 0
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

        let user_balance_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        // Position 1
        add_liquidity_fix_value(
            admin,
            pool_address,
            100000,
            100000,
            false,
            18446744073709549616, // -2000
            0, // 0
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 0, 1001); // min[0.000000, 1050883.152001]

        let user_balance_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_a_before - user_balance_a_after) == 0, 1002);
        assert!((user_balance_b_before - user_balance_b_after) == 100000, 1003);

        // Position 2
        add_liquidity_fix_value(
            admin,
            pool_address,
            100000,
            100000,
            true,
            18446744073709550616, // -1000
            16000,
            true,
            0,
        );

        let pool_liquidity2 = get_pool_liquidity(pool_address);
        assert!(pool_liquidity2 == 181602, 1004); // min[181602.549077, 2050516.626811]

        let user_balance_a_after2 = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_after2 = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_a_after - user_balance_a_after2) == 100000, 1005); // 99999.6976491452
        assert!((user_balance_b_after - user_balance_b_after2) == 8857, 1006); // 8856.402217154447

        // Position 3
        add_liquidity_fix_value(
            admin,
            pool_address,
            100000,
            100000,
            true,
            0,
            26000,
            true,
            0,
        );

        let pool_liquidity3 = get_pool_liquidity(pool_address);
        assert!(pool_liquidity3 == 137466 + pool_liquidity2, 1007); // [137466.399379, 0]

        let user_balance_a_after3 = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_after3 = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_a_after2 - user_balance_a_after3) == 100000, 1008);
        assert!((user_balance_b_after3 - user_balance_b_after2) == 0, 1009);

        let position_ids = vector[1, 2, 3];
        let token_addressess = pool::generate_token_addresses(pool_address, position_ids);
        assert!(vector::length(&token_addressess) == 3, 1010);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_narrow_range_position(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 2;
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

        let amount_a = 100000;
        let amount_b = 100000;
        let tick_lower = 18446744073709551596; // -20
        let tick_upper = 20;

        let user_balance_a_before = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        add_liquidity_fix_value(
            admin,
            pool_address,
            amount_a,
            amount_b,
            true,
            tick_lower,
            tick_upper,
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 100055008, 1001); // min[ 100055008.249595, 200060003.999810 ]

        let user_balance_a_after = token_factory::get_token_balance(admin, address_of(admin), token_a_name);
        let user_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_a_before - user_balance_a_after) == 100000, 1002); // 99999.99975054196
        assert!((user_balance_b_before - user_balance_b_after) == 100000, 1003); // 99999.99975053998
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = pool::EIS_NOT_VALID_TICK)] // EIS_NOT_VALID_TICK
    public entry fun test_invalid_tick_range(admin: &signer, supra_framework: &signer) {
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
            100000,
            100000,
            true,
            16000,
            0,
            true,
            0,
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = clmm_math::EINVALID_FIXED_TOKEN_TYPE)] // EINVALID_FIXED_TOKEN_TYPE
    public entry fun test_uninitialized_tick(admin: &signer, supra_framework: &signer) {
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
            100000,
            100000,
            true,
            18446744073709549616, // -2000
            18446744073709550616, // -1000
            true,
            0,
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = pool::EAMOUNT_INCORRECT)] // EAMOUNT_INCORRECT
    public entry fun test_insufficient_liquidity(admin: &signer, supra_framework: &signer) {
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

        // add liquidity with zero amounts
        add_liquidity_fix_value(
            admin,
            pool_address,
            0,
            0,
            true,
            0,
            16000,
            true,
            0,
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = pool::EIS_NOT_VALID_TICK)] // EIS_NOT_VALID_TICK
    public entry fun test_invalid_tick_spacing(admin: &signer, supra_framework: &signer) {
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
            100000,
            100000,
            true,
            100, // not aligned to tick spacing
            16000,
            true,
            0,
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure] // EINSUFFICIENT_BALANCE
    public entry fun test_invalid_token_amounts(admin: &signer, supra_framework: &signer) {
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
            18446744073709551615,
            18446744073709551615,
            true,
            0,
            16000,
            true,
            0,
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = factory::EINVALID_SQRTPRICE)] // E_INVALID_SQRT_PRICE
    public entry fun test_invalid_sqrt_price(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 200;
        let init_sqrt_price = 0;
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
            100000,
            100000,
            true,
            0,
            16000,
            true,
            0,
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = fee_tier::EINVALID_FEE_RATE)] // EINVALID_FEE_RATE
    public entry fun test_invalid_fee_rate(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        let tick_spacing = 200;
        factory::init_factory_module(admin);
        add_fee_tier(admin, tick_spacing, 1000000);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure] // ERESOURCE_ACCCOUNT_EXISTS
    public entry fun test_create_pool_with_same_token_types(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));

        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 2;
        let tick_spacing2 = 200;
        let init_sqrt_price = 18446744073709551616;

        factory::init_factory_module(admin);

        add_fee_tier(admin, tick_spacing, 1000);
        add_fee_tier(admin, tick_spacing2, 1000);
        factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );
        factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_create_and_add_liquidity_fix_token_with_coins(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));

        timestamp::set_time_has_started_for_testing(supra_framework);
        mint_tokens(admin);

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 100000;
        let amount_b = 400000;
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 16000;
        let fee_rate = 1000;

        factory::init_factory_module(admin);

        add_fee_tier(admin, tick_spacing, fee_rate);
        assert!(fee_rate == get_fee_rate(tick_spacing), 1001);

        let user_balance_a_before = coin::balance<TestCoinA>(signer::address_of(admin));
        let user_balance_b_before = coin::balance<TestCoinB>(signer::address_of(admin));

        create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
        );

        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let b_addr = utils::coin_to_fa_address<TestCoinB>();
        let clmm_pool_addr_opt = factory::get_pool(tick_spacing, a_addr, b_addr);
        let pool_address = option::extract(&mut clmm_pool_addr_opt);

        migrate_to_fungible_store<TestCoinB>(admin);
        add_liquidity_fix_value_coin_asset<TestCoinA>(
            admin,
            pool_address,
            amount_a,
            amount_b,
            true,
            tick_lower,
            tick_upper,
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 181602, 1002); // min[181602.549077, 20201666.612228]

        let user_balance_a_after = coin::balance<TestCoinA>(signer::address_of(admin));
        let user_balance_b_after = coin::balance<TestCoinB>(signer::address_of(admin));

        assert!((user_balance_a_before - user_balance_a_after) == 100000, 1003); // 99999.6976491452
        assert!((user_balance_b_before - user_balance_b_after) == 3596, 1004); // 3595.782535883948
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_create_and_add_liquidity_fix_token_with_coin_asset(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));

        timestamp::set_time_has_started_for_testing(supra_framework);
        mint_tokens(admin);

        let token_b_name = utf8(b"Token B");
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));


        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 100000;
        let amount_b = 400000;
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 16000;
        let fee_rate = 1000;

        factory::init_factory_module(admin);

        add_fee_tier(admin, tick_spacing, fee_rate);
        assert!(fee_rate == get_fee_rate(tick_spacing), 1001);

        let user_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        create_pool_coin_asset<TestCoinA>(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_b
        );

        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let clmm_pool_addr_opt = factory::get_pool(tick_spacing, a_addr, token_b);
        let pool_address = option::extract(&mut clmm_pool_addr_opt);

        add_liquidity_fix_value_coin_asset<TestCoinA>(
            admin,
            pool_address,
            amount_a,
            amount_b,
            true,
            tick_lower,
            tick_upper,
            true,
            0,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 181602, 1002); // min[181602.549077, 20201666.612228]

        let user_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_b_before - user_balance_b_after) == 3596, 1004); // 3595.782535883948
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_create_and_add_liquidity_with_coins(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));

        timestamp::set_time_has_started_for_testing(supra_framework);
        mint_tokens(admin);

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 100000;
        let amount_b = 400000;
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 16000;
        let fee_rate = 1000;

        factory::init_factory_module(admin);

        add_fee_tier(admin, tick_spacing, fee_rate);
        assert!(fee_rate == get_fee_rate(tick_spacing), 1001);

        create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
        );

        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let b_addr = utils::coin_to_fa_address<TestCoinB>();
        let clmm_pool_addr_opt = factory::get_pool(tick_spacing, a_addr, b_addr);
        let pool_address = option::extract(&mut clmm_pool_addr_opt);

        add_liquidity_coin_coin<TestCoinA, TestCoinB>(
            admin,
            pool_address,
            25000,
            amount_a,
            amount_b,
            tick_lower,
            tick_upper,
            true,
            1,
        );

        let pool_liquidity2 = get_pool_liquidity(pool_address);
        assert!(pool_liquidity2 == 25000, 1004);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_create_and_add_liquidity_with_coin_asset(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));

        timestamp::set_time_has_started_for_testing(supra_framework);
        mint_tokens(admin);

        let token_b_name = utf8(b"Token B");
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));


        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 100000;
        let amount_b = 400000;
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 16000;
        let fee_rate = 1000;

        factory::init_factory_module(admin);

        add_fee_tier(admin, tick_spacing, fee_rate);
        assert!(fee_rate == get_fee_rate(tick_spacing), 1001);

        let user_balance_b_before = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        create_pool_coin_asset<TestCoinA>(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_b
        );

        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let clmm_pool_addr_opt = factory::get_pool(tick_spacing, a_addr, token_b);
        let pool_address = option::extract(&mut clmm_pool_addr_opt);

        add_liquidity_coin_asset<TestCoinA>(
            admin,
            pool_address,
            181602,
            amount_a,
            amount_b,
            tick_lower,
            tick_upper,
            true,
            1,
        );

        let pool_liquidity = get_pool_liquidity(pool_address);
        assert!(pool_liquidity == 181602, 1002);

        let user_balance_b_after = token_factory::get_token_balance(admin, address_of(admin), token_b_name);

        assert!((user_balance_b_before - user_balance_b_after) == 3596, 1004); // 3595.782535883948
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_is_pool_exists(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name, token_c_name) = (utf8(b"Token A"), utf8(b"Token B"), utf8(b"Token C"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));
        let token_c = setup_fungible_assets(admin, token_c_name, utf8(b"TC"));

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let fee_rate = 1000;

        factory::init_factory_module(admin);
        add_fee_tier(admin, tick_spacing, fee_rate);
        assert!(fee_rate == get_fee_rate(tick_spacing), 1001);

        let pool_address = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_b,
        );

        let pool_address1 = factory::create_pool(
            admin,
            tick_spacing,
            init_sqrt_price,
            string::utf8(b""),
            token_a,
            token_c,
        );

        let pool_addresses = vector[pool_address, pool_address1, @dexlyn_clmm];
        let pool_exists = pool:: is_pool_exists(pool_addresses);
        assert!(*vector::borrow(&pool_exists, 0), 1001);
        assert!(*vector::borrow(&pool_exists, 1), 1002);
        assert!(!*vector::borrow(&pool_exists, 2), 1003);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_find_best_swap(admin: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);

        let (token_a_name, token_b_name) = (utf8(b"Token A"), utf8(b"Token B"));
        let token_a = setup_fungible_assets(admin, token_a_name, utf8(b"TA"));
        let token_b = setup_fungible_assets(admin, token_b_name, utf8(b"TB"));

        let tick_spacing = 200;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 155668;
        let amount_b = 300000;
        let tick_lower = 18446744073709551416;
        let tick_upper = 200;

        let fee_rate1 = 1000;
        let fee_rate2 = 500;
        let fee_rate3 = 100;

        factory::init_factory_module(admin);
        add_fee_tier(admin, tick_spacing, fee_rate1);


        // Create two pools
        let pool_address1 = factory::create_pool(
            admin, tick_spacing, init_sqrt_price, string::utf8(b""), token_a, token_b
        );

        // Add different liquidity to each pool
        add_liquidity_fix_value(
            admin, pool_address1, amount_a, amount_b, true, tick_lower, tick_upper, true, 0
        );


        let tick_spacing = 60;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 358963;
        let amount_b = 400000;
        let tick_lower = 18446744073709551556;
        let tick_upper = 60;
        add_fee_tier(admin, tick_spacing, fee_rate2);

        let pool_address2 = factory::create_pool(
            admin, tick_spacing, init_sqrt_price, string::utf8(b""), token_a, token_b
        );

        add_liquidity_fix_value(
            admin, pool_address2, amount_a, amount_b, true, tick_lower, tick_upper, true, 0
        );


        let tick_spacing = 30;
        let init_sqrt_price = 18446744073709551616;
        let amount_a = 125669;
        let amount_b = 256856;
        let tick_lower = 18446744073709551586;
        let tick_upper = 30;
        add_fee_tier(admin, tick_spacing, fee_rate3);

        let pool_address3 = factory::create_pool(
            admin, tick_spacing, init_sqrt_price, string::utf8(b""), token_a, token_b
        );

        add_liquidity_fix_value(
            admin, pool_address3, amount_a, amount_b, true, tick_lower, tick_upper, true, 0
        );


        let pool_addresses = vector[pool_address1, pool_address2, pool_address3];
        let (best_pool, best_amount) = pool::swap_routing(pool_addresses, true, true, 100000);

        assert!(best_pool == pool_address3, 9001);
    }
}