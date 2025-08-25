module dexlyn_clmm::fee_tier_test {
    #[test_only]
    use dexlyn_clmm::config;
    #[test_only]
    use dexlyn_clmm::fee_tier;
    #[test_only]
    use supra_framework::timestamp;

    #[test(
        admin = @dexlyn_clmm,
    )]
    public entry fun test_fee_tier_initialize_success(admin: &signer) {
        config::initialize(admin);
        fee_tier::initialize(admin);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_update_fee_tier_success(admin: &signer, supra_framework: &signer) {
        config::initialize(admin);
        timestamp::set_time_has_started_for_testing(supra_framework);
        fee_tier::initialize(admin);
        fee_tier::add_fee_tier(admin, 100, 1000);
        fee_tier::update_fee_tier(admin, 100, 1500);
        let new_rate = fee_tier::get_fee_rate(100);
        assert!(new_rate == 1500, 2003);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = fee_tier::EFEE_TIER_NOT_FOUND)] // EFEE_TIER_NOT_FOUND
    public entry fun test_update_fee_tier_not_found(admin: &signer, supra_framework: &signer) {
        config::initialize(admin);
        timestamp::set_time_has_started_for_testing(supra_framework);
        fee_tier::initialize(admin);
        fee_tier::update_fee_tier(admin, 999, 1000);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_delete_fee_tier_success(admin: &signer, supra_framework: &signer) {
        config::initialize(admin);
        timestamp::set_time_has_started_for_testing(supra_framework);
        fee_tier::initialize(admin);
        fee_tier::add_fee_tier(admin, 100, 1000);
        fee_tier::delete_fee_tier(admin, 100);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = fee_tier::EFEE_TIER_NOT_FOUND)] // EFEE_TIER_NOT_FOUND
    public entry fun test_delete_fee_tier_not_found(admin: &signer, supra_framework: &signer) {
        config::initialize(admin);
        timestamp::set_time_has_started_for_testing(supra_framework);
        fee_tier::initialize(admin);
        fee_tier::delete_fee_tier(admin, 100);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    public entry fun test_get_fee_rate_success(admin: &signer, supra_framework: &signer) {
        config::initialize(admin);
        timestamp::set_time_has_started_for_testing(supra_framework);
        fee_tier::initialize(admin);
        fee_tier::add_fee_tier(admin, 100, 1234);
        let rate = fee_tier::get_fee_rate(100);
        assert!(rate == 1234, 2007);
    }

    #[test(
        supra_framework = @supra_framework,
        admin = @dexlyn_clmm,
    )]
    #[expected_failure(abort_code = fee_tier::EFEE_TIER_NOT_FOUND)] // EFEE_TIER_NOT_FOUND
    public entry fun test_get_fee_rate_not_found(admin: &signer, supra_framework: &signer) {
        config::initialize(admin);
        timestamp::set_time_has_started_for_testing(supra_framework);
        fee_tier::initialize(admin);
        fee_tier::get_fee_rate(999);
    }

    #[test]
    public entry fun test_max_fee_rate() {
        let max_rate = fee_tier::max_fee_rate();
        assert!(max_rate == 200000, 2009);
    }
}
