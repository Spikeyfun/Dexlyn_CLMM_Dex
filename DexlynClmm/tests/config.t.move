#[test_only]
module dexlyn_clmm::config_test {

    use std::signer;

    use dexlyn_clmm::config::Self;

    #[test(admin = @dexlyn_clmm)]
    public fun test_initialize_and_get_fee_rate(admin: signer) {
        config::initialize(&admin);
        let fee_rate = config::get_protocol_fee_rate();
        assert!(fee_rate == 3333, 100); // 3333 is DEFAULT_PROTOCOL_FEE_RATE
    }

    #[test(admin = @dexlyn_clmm)]
    #[expected_failure]
    public fun test_assert_protocol_status_aborts_when_paused(admin: signer) {
        config::initialize(&admin);
        config::pause(&admin);
        config::assert_protocol_status();// Should abort
    }

    #[test(admin = @dexlyn_clmm)]
    public fun test_add_and_remove_role(admin: signer) {
        config::initialize(&admin);
        config::init_clmm_acl(&admin);
        config::add_role(&admin, @0x123, 1);
        config::remove_role(&admin, @0x123, 1);
    }

    #[test(admin = @dexlyn_clmm)]
    public fun test_init_clmm_acl(admin: signer) {
        config::initialize(&admin);
        config::init_clmm_acl(&admin);
    }

    #[test(admin = @dexlyn_clmm)]
    public fun test_allow_set_position_nft_uri(admin: signer) {
        config::initialize(&admin);
        config::init_clmm_acl(&admin);
        // add role 1 to admin
        config::add_role(&admin, signer::address_of(&admin), 1);
        let allowed = config::allow_set_position_nft_uri(&admin);
        assert!(allowed, 200);
    }

    #[test(admin = @dexlyn_clmm)]
    #[expected_failure]
    public fun test_add_role_invalid_role(admin: signer) {
        config::initialize(&admin);
        config::init_clmm_acl(&admin);
        // attempt to add a role that is not defined
        config::add_role(&admin, @0x123, 3);
    }

    #[test(admin = @dexlyn_clmm, new_admin = @0x123)]
    #[expected_failure]
    public fun test_transfer_and_accept_protocol_authority(admin: signer, new_admin: signer) {
        config::initialize(&admin);
        // trander authority to new_admin
        config::transfer_protocol_authority(&admin, signer::address_of(&new_admin));
        // accept authority with new_admin
        config::accept_protocol_authority(&new_admin);
    }

    #[test(admin = @dexlyn_clmm)]
    #[expected_failure]
    public fun test_update_protocol_fee_rate(admin: signer) {
        config::initialize(&admin);
        config::update_protocol_fee_rate(&admin, 2500);
        let fee_rate = config::get_protocol_fee_rate();
        assert!(fee_rate == 2500, 300);
    }

    #[test(admin = @dexlyn_clmm)]
    #[expected_failure]
    public fun test_update_protocol_fee_rate_too_high(admin: signer) {
        config::initialize(&admin);
        // MAX_PROTOCOL_FEE_RATE is 3000, so 4000 should abort
        config::update_protocol_fee_rate(&admin, 4000);
    }

    #[test(admin = @dexlyn_clmm, new_admin = @0x123)]
    #[expected_failure]
    public fun test_update_pool_create_authority(admin: signer, new_admin: signer) {
        config::initialize(&admin);
        config::update_pool_create_authority(&admin, signer::address_of(&new_admin));
    }

    #[test(admin = @dexlyn_clmm, new_admin = @0x123)]
    #[expected_failure]
    public fun test_update_protocol_fee_claim_authority(admin: signer, new_admin: signer) {
        config::initialize(&admin);
        config::update_protocol_fee_claim_authority(&admin, signer::address_of(&new_admin));
    }
}