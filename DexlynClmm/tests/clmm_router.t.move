#[test_only]
module dexlyn_clmm::clmm_router_test {
    use std::option;
    use std::signer;
    use std::string::utf8;

    use supra_framework::account;
    use supra_framework::coin;
    use supra_framework::timestamp;

    use dexlyn_clmm::clmm_router;
    use dexlyn_clmm::config;
    use dexlyn_clmm::factory;
    use dexlyn_clmm::partner;
    use dexlyn_clmm::test_helpers::{Self, TestCoinA, TestCoinB};
    use dexlyn_clmm::utils;

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        user = @0x123
    )]
    public entry fun test_acl_and_protocol_authority(admin: &signer, user: &signer, supra_framework: &signer) {
        timestamp::set_time_has_started_for_testing(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        config::initialize(admin);

        // ACL functions
        clmm_router::init_clmm_acl(admin);
        clmm_router::add_role(admin, signer::address_of(user), 1);
        clmm_router::remove_role(admin, signer::address_of(user), 1);

        // Protocol authority transfer/accept
        clmm_router::transfer_protocol_authority(admin, signer::address_of(user));
        clmm_router::accept_protocol_authority(user);
    }

    #[test(
        admin = @dexlyn_clmm
    )]
    public entry fun test_pause_unpause(admin: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        config::initialize(admin);

        clmm_router::pause(admin);
        clmm_router::unpause(admin);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        user = @0x123
    )]
    public entry fun test_update_config_fields(admin: &signer, user: &signer, supra_framework: &signer) {
        timestamp::set_time_has_started_for_testing(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        config::initialize(admin);

        clmm_router::update_pool_create_authority(admin, signer::address_of(user));
        clmm_router::update_protocol_fee_claim_authority(admin, signer::address_of(user));
        clmm_router::update_protocol_fee_rate(admin, 1234);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        receiver = @0x456,
        new_receiver = @0x789
    )]
    public entry fun test_partner_router_entries(
        admin: &signer,
        receiver: &signer,
        new_receiver: &signer,
        supra_framework: &signer
    ) {
        timestamp::set_time_has_started_for_testing(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(receiver));
        account::create_account_for_test(signer::address_of(new_receiver));
        config::initialize(admin);
        timestamp::set_time_has_started_for_testing(supra_framework);
        partner::initialize(admin);

        let now = timestamp::now_seconds();
        let name = utf8(b"ROUTER_PARTNER");
        clmm_router::create_partner(
            admin,
            name,
            100,
            signer::address_of(receiver),
            now,
            now + 100000
        );
        clmm_router::update_partner_fee_rate(admin, name, 200);
        clmm_router::update_partner_time(admin, name, now, now + 200000);
        clmm_router::transfer_partner_receiver(receiver, name, signer::address_of(new_receiver));
        clmm_router::accept_partner_receiver(new_receiver, name);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public entry fun test_fee_tier_management(admin: &signer, supra_framework: &signer) {
        // Setup
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);


        // Test fee tier operations
        let tick_spacing = 100;
        let fee_rate = 500;

        // Add fee tier
        clmm_router::add_fee_tier(admin, tick_spacing, fee_rate);

        // Update fee tier
        let new_fee_rate = 600;
        clmm_router::update_fee_tier(admin, tick_spacing, new_fee_rate);

        // Delete fee tier
        clmm_router::delete_fee_tier(admin, tick_spacing);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public entry fun test_pool_management(admin: &signer, supra_framework: &signer) {
        // Setup
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        clmm_router::init_clmm_acl(admin);
        test_helpers::mint_tokens(admin);

        // Create pool
        let tick_spacing = 100;
        clmm_router::add_fee_tier(admin, tick_spacing, 500);

        let init_sqrt_price = 18446744073709551616; // 1.0 as Q64.64
        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin,
            tick_spacing,
            init_sqrt_price,
            utf8(b"test-pool")
        );

        let asset_a_addr = utils::coin_to_fa_address<TestCoinA>();
        let asset_b_addr = utils::coin_to_fa_address<TestCoinB>();

        // Get pool address
        let pool_opt = factory::get_pool(tick_spacing, asset_a_addr, asset_b_addr);
        let pool_address = std::option::extract(&mut pool_opt);


        // Test pool pause/unpause
        clmm_router::pause_pool(admin, pool_address);
        clmm_router::unpause_pool(admin, pool_address);

        clmm_router::add_role(admin, signer::address_of(admin), 1);

        // Update pool URI
        clmm_router::update_pool_uri(admin, pool_address, utf8(b"new-uri"));
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        authority = @0x123
    )]
    public entry fun test_rewarder_management(admin: &signer, authority: &signer, supra_framework: &signer) {
        // Setup
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(authority));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        clmm_router::init_clmm_acl(admin);
        test_helpers::mint_tokens(admin);

        // Create pool
        let tick_spacing = 100;
        clmm_router::add_fee_tier(admin, tick_spacing, 500);

        let init_sqrt_price = 18446744073709551616;
        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin,
            tick_spacing,
            init_sqrt_price,
            utf8(b"test-pool")
        );

        let asset_a_addr = utils::coin_to_fa_address<TestCoinA>();
        let asset_b_addr = utils::coin_to_fa_address<TestCoinB>();

        let pool_opt = factory::get_pool(tick_spacing, asset_a_addr, asset_b_addr);
        let pool_address = std::option::extract(&mut pool_opt);

        // Initialize rewarder
        let rewarder_index = 0;
        clmm_router::initialize_rewarder(
            admin,
            pool_address,
            signer::address_of(authority),
            rewarder_index,
            asset_a_addr
        );

        // Transfer rewarder authority
        clmm_router::transfer_rewarder_authority(
            authority,
            pool_address,
            (rewarder_index as u8),
            signer::address_of(admin)
        );

        // Accept rewarder authority
        clmm_router::accept_rewarder_authority(
            admin,
            pool_address,
            (rewarder_index as u8),
        );

        // Update rewarder emission
        let emissions_per_second = 1000;
        clmm_router::update_rewarder_emission(
            admin,
            pool_address,
            (rewarder_index as u8),
            emissions_per_second,
            asset_a_addr
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    #[expected_failure] // E_CLOSE_POSITION_FAIL
    public entry fun test_position_management(admin: &signer, supra_framework: &signer) {
        // Setup
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        clmm_router::init_clmm_acl(admin);
        test_helpers::mint_tokens(admin);

        // Create pool
        let tick_spacing = 100;
        clmm_router::add_fee_tier(admin, tick_spacing, 500);

        let init_sqrt_price = 18446744073709551616;
        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin,
            tick_spacing,
            init_sqrt_price,
            utf8(b"test-pool")
        );

        let asset_a_addr = utils::coin_to_fa_address<TestCoinA>();
        let asset_b_addr = utils::coin_to_fa_address<TestCoinB>();

        let pool_opt = factory::get_pool(tick_spacing, asset_a_addr, asset_b_addr);
        let pool_address = std::option::extract(&mut pool_opt);

        // Add liquidity and create position
        let amount_a = 1000000;
        let amount_b = 1000000;
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 400;

        clmm_router::add_liquidity_fix_value(
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

        // Close position
        clmm_router::close_position(admin, pool_address, 1);
    }


    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        user = @0x123
    )]
    public entry fun test_claim_ref_fee(admin: &signer, user: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        timestamp::set_time_has_started_for_testing(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        factory::init_factory_module(admin);
        clmm_router::init_clmm_acl(admin);
        test_helpers::mint_tokens(admin);

        // Create a partner
        let name = utf8(b"PARTNER");
        let now = supra_framework::timestamp::now_seconds();
        clmm_router::create_partner(
            admin,
            name,
            100,
            signer::address_of(user),
            now,
            now + 100000
        );

        let asset_a_addr = utils::coin_to_fa_address<TestCoinA>();

        // Simulate referral fee accrual (this may require a swap or other action in your real logic)
        // For demonstration, we just call claim_ref_fee
        clmm_router::claim_ref_fee(user, name, asset_a_addr);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm
    )]
    public entry fun test_update_fee_rate(admin: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        clmm_router::init_clmm_acl(admin);
        test_helpers::mint_tokens(admin);

        let tick_spacing = 100;
        let init_sqrt_price = 18446744073709551616;
        clmm_router::add_fee_tier(admin, tick_spacing, 500);
        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin, tick_spacing, init_sqrt_price, utf8(b"test-pool")
        );

        let a_addr = utils::coin_to_fa_address<TestCoinA>();
        let b_addr = utils::coin_to_fa_address<TestCoinB>();
        let clmm_pool_addr_opt = factory::get_pool(tick_spacing, a_addr, b_addr);
        let pool_address = option::extract(&mut clmm_pool_addr_opt);

        // Update pool fee rate
        clmm_router::update_fee_rate(admin, pool_address, 1234);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        user = @0x123
    )]
    public entry fun test_collect_rewarder(admin: &signer, user: &signer, supra_framework: &signer) {
        coin::create_coin_conversion_map(supra_framework);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        timestamp::set_time_has_started_for_testing(supra_framework);
        factory::init_factory_module(admin);
        clmm_router::init_clmm_acl(admin);
        test_helpers::mint_tokens(admin);

        let tick_spacing = 100;
        let init_sqrt_price = 18446744073709551616;
        clmm_router::add_fee_tier(admin, tick_spacing, 500);
        clmm_router::create_pool_coin_coin<TestCoinA, TestCoinB>(
            admin, tick_spacing, init_sqrt_price, utf8(b"test-pool")
        );
        let asset_a_addr = utils::coin_to_fa_address<TestCoinA>();
        let asset_b_addr = utils::coin_to_fa_address<TestCoinB>();
        let clmm_pool_addr_opt = factory::get_pool(tick_spacing, asset_a_addr, asset_b_addr);
        let pool_address = option::extract(&mut clmm_pool_addr_opt);

        // Initialize rewarder
        clmm_router::initialize_rewarder(
            admin,
            pool_address,
            signer::address_of(admin),
            0,
            asset_a_addr
        );


        // Open a position for user
        let tick_lower = 18446744073709551216; // -400
        let tick_upper = 400;
        let pos_id = dexlyn_clmm::pool::open_position(
            user, pool_address, integer_mate::i64::from_u64(tick_lower), integer_mate::i64::from_u64(tick_upper)
        );

        // Collect rewarder (will only succeed if rewards are available)
        clmm_router::collect_rewarder(
            user,
            pool_address,
            0, // rewarder_index
            pos_id,
            asset_a_addr
        );
    }
}