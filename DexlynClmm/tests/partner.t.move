#[test_only]
module dexlyn_clmm::partner_test {
    use std::signer;
    use std::signer::address_of;
    use std::string::utf8;

    use supra_framework::account;
    use supra_framework::coin;
    use supra_framework::fungible_asset;
    use supra_framework::fungible_asset::Metadata;
    use supra_framework::object::address_to_object;
    use supra_framework::primary_fungible_store;
    use supra_framework::timestamp;

    use dexlyn_clmm::config;
    use dexlyn_clmm::partner;
    use dexlyn_clmm::test_helpers::setup_fungible_assets;

    const PARTNER_NAME: vector<u8> = b"PARTNER_NAME";

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        partner_admin = @0x123,
        receiver = @0x456,
        user = @0x789
    )]
    public entry fun test_create_and_claim_partner(
        admin: &signer,
        partner_admin: &signer,
        receiver: &signer,
        supra_framework: &signer,
        user: &signer
    ) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(partner_admin));
        account::create_account_for_test(signer::address_of(receiver));
        account::create_account_for_test(signer::address_of(user));

        timestamp::set_time_has_started_for_testing(supra_framework);
        let token_a = setup_fungible_assets(admin, utf8(b"Token A"), utf8(b"TA"));

        // Initialize partner
        config::initialize(admin);
        partner::initialize(admin);

        // Create partner
        let now = timestamp::now_seconds();
        let name = utf8(PARTNER_NAME);
        let fee_rate = 100;
        let start_time = now;
        let end_time = now + 100000;
        partner::create_partner(
            admin,
            name,
            fee_rate,
            signer::address_of(receiver),
            start_time,
            end_time
        );

        // Check fee rate view
        let rate = partner::get_ref_fee_rate(name);
        assert!(rate == fee_rate, 100);


        // Send referral fee to partner
        let asset_amount = 1000;

        let asset_a_metadata = address_to_object<Metadata>(token_a);

        let user_a_store = primary_fungible_store::ensure_primary_store_exists(address_of(admin), asset_a_metadata);

        let ref_fee = fungible_asset::withdraw(admin, user_a_store, asset_amount);
        partner::receive_ref_fee(name, ref_fee, token_a);

        let receiver_a_store = primary_fungible_store::ensure_primary_store_exists(
            address_of(receiver),
            asset_a_metadata
        );

        // Receiver claims referral fee
        let before = fungible_asset::balance(receiver_a_store);
        partner::claim_ref_fee(receiver, name, token_a);
        let after = fungible_asset::balance(receiver_a_store);
        assert!(after - before == asset_amount, 101);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        receiver = @456
    )]
    #[expected_failure] // E_PARTNER_ALREADY_EXISTS
    public entry fun test_duplicate_partner(admin: &signer, receiver: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(receiver));
        coin::create_coin_conversion_map(supra_framework);
        timestamp::set_time_has_started_for_testing(supra_framework);
        config::initialize(admin);
        partner::initialize(admin);

        let now = timestamp::now_seconds();
        let name = utf8(PARTNER_NAME);
        partner::create_partner(
            admin,
            name,
            100,
            signer::address_of(receiver),
            now,
            now + 100000
        );
        // Should fail: duplicate
        partner::create_partner(
            admin,
            name,
            100,
            signer::address_of(receiver),
            now,
            now + 100000
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        receiver = @0x456
    )]
    #[expected_failure] // E_PARTNER_NOT_FOUND
    public entry fun test_claim_nonexistent_partner(admin: &signer, receiver: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(receiver));
        timestamp::set_time_has_started_for_testing(supra_framework);
        partner::initialize(admin);

        let token_a = setup_fungible_assets(admin, utf8(b"Token A"), utf8(b"TA"));

        let name = utf8(b"notfound");
        partner::claim_ref_fee(receiver, name, token_a);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        receiver = @0x456,
        user = @0x123
    )]
    #[expected_failure] // E_NOT_AUTHORIZED
    public entry fun test_unauthorized_claim(
        admin: &signer,
        receiver: &signer,
        user: &signer,
        supra_framework: &signer
    ) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(receiver));
        account::create_account_for_test(signer::address_of(user));

        coin::create_coin_conversion_map(supra_framework);
        timestamp::set_time_has_started_for_testing(supra_framework);

        let token_a = setup_fungible_assets(admin, utf8(b"Token A"), utf8(b"TA"));

        config::initialize(admin);
        partner::initialize(admin);

        let now = timestamp::now_seconds();
        let name = utf8(PARTNER_NAME);
        partner::create_partner(
            admin,
            name,
            100,
            signer::address_of(receiver),
            now,
            now + 100000
        );
        // User tries to claim, should fail
        partner::claim_ref_fee(user, name, token_a);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        partner_admin = @0x123,
        receiver = @0x456
    )]
    public entry fun test_transfer_and_accept_receiver(
        admin: &signer,
        partner_admin: &signer,
        receiver: &signer,
        supra_framework: &signer
    ) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(partner_admin));
        account::create_account_for_test(signer::address_of(receiver));
        timestamp::set_time_has_started_for_testing(supra_framework);
        config::initialize(admin);
        partner::initialize(admin);

        let now = timestamp::now_seconds();
        let name = std::string::utf8(b"TRANSFER_PARTNER");
        partner::create_partner(
            admin,
            name,
            100,
            signer::address_of(partner_admin),
            now,
            now + 100000
        );
        partner::transfer_receiver(partner_admin, name, signer::address_of(receiver));
        partner::accept_receiver(receiver, name);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        partner_admin = @0x123,
        receiver = @0x456
    )]
    public entry fun test_update_fee_rate_and_time(
        admin: &signer,
        partner_admin: &signer,
        receiver: &signer,
        supra_framework: &signer
    ) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(partner_admin));
        account::create_account_for_test(signer::address_of(receiver));
        timestamp::set_time_has_started_for_testing(supra_framework);
        config::initialize(admin);
        partner::initialize(admin);

        let now = timestamp::now_seconds();
        let name = std::string::utf8(b"UPDATE_PARTNER");
        partner::create_partner(
            admin,
            name,
            100,
            signer::address_of(receiver),
            now,
            now + 100000
        );
        // update fee rate
        partner::update_fee_rate(admin, name, 200);
        // updae time
        partner::update_time(admin, name, now, now + 200000);
    }

    #[test]
    public entry fun test_partner_fee_rate_denominator() {
        let denom = partner::partner_fee_rate_denominator();
        assert!(denom == 10000, 9001);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        receiver = @0x456
    )]
    #[expected_failure] // E_INVALID_TIME
    public entry fun test_create_partner_invalid_time(admin: &signer, receiver: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(receiver));
        timestamp::set_time_has_started_for_testing(supra_framework);
        config::initialize(admin);
        partner::initialize(admin);

        let now = timestamp::now_seconds();
        let name = std::string::utf8(b"BADTIME");
        partner::create_partner(
            admin,
            name,
            100,
            signer::address_of(receiver),
            now + 1000,
            now
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        receiver = @0x456
    )]
    #[expected_failure] // E_FEE_RATE_TOO_HIGH
    public entry fun test_create_partner_fee_rate_too_high(
        admin: &signer,
        receiver: &signer,
        supra_framework: &signer
    ) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(receiver));
        timestamp::set_time_has_started_for_testing(supra_framework);
        config::initialize(admin);
        partner::initialize(admin);

        let now = timestamp::now_seconds();
        let name = std::string::utf8(b"BADFEE");
        partner::create_partner(
            admin,
            name,
            10000,
            signer::address_of(receiver),
            now,
            now + 100000
        );
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
        receiver = @0x456
    )]
    #[expected_failure] // E_EMPTY_NAME
    public entry fun test_create_partner_empty_name(admin: &signer, receiver: &signer, supra_framework: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(receiver));
        timestamp::set_time_has_started_for_testing(supra_framework);
        config::initialize(admin);
        partner::initialize(admin);

        let now = timestamp::now_seconds();
        let name = std::string::utf8(b"");
        partner::create_partner(
            admin,
            name,
            100,
            signer::address_of(receiver),
            now,
            now + 100000
        );
    }
}