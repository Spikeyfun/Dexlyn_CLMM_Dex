/// The FeeTiers info provide the fee_tier metadata used when create pool.
/// The FeeTier is stored in the deployed account(@dexlyn_clmm).
/// The FeeTier is identified by the tick_spacing.
/// The FeeTier can only be created and updated by the protocol.

module dexlyn_clmm::fee_tier {
    use aptos_std::simple_map::{Self, SimpleMap};
    use supra_framework::event;
    use dexlyn_clmm::config;
    use supra_framework::timestamp;

    /// Max swap fee rate(100000 = 200000/1000000 = 20%)
    const MAX_FEE_RATE: u64 = 200000;

    /// Errors
    /// The fee tier already exist
    const EFEE_TIER_ALREADY_EXIST: u64 = 1;

    /// The fee tier not found
    const EFEE_TIER_NOT_FOUND: u64 = 2;

    /// The fee tier already initialized
    const EFEETIER_ALREADY_INITIALIZED: u64 = 3;

    /// The fee rate is invalid
    const EINVALID_FEE_RATE: u64 = 4;

    /// The clmmpools fee tier data
    struct FeeTier has store, copy, drop {
        /// The tick spacing
        tick_spacing: u64,

        /// The default fee rate
        fee_rate: u64,
    }

    /// The clmmpools fee tier map
    struct FeeTiers has key {
        fee_tiers: SimpleMap<u64, FeeTier>,
    }

    #[event]
    struct AddEvent has drop, store {
        tick_spacing: u64,
        fee_rate: u64,
        timestamp: u64,
    }

    #[event]
    struct UpdateEvent has drop, store {
        tick_spacing: u64,
        old_fee_rate: u64,
        new_fee_rate: u64,
        timestamp: u64,
    }

    #[event]
    struct DeleteEvent has drop, store {
        tick_spacing: u64,
        timestamp: u64,
    }

    /// initialize the global FeeTier of dexlyn clmm protocol
    public fun initialize(
        account: &signer,
    ) {
        config::assert_initialize_authority(account);
        move_to(account, FeeTiers {
            fee_tiers: simple_map::create<u64, FeeTier>(),
        });
    }

    /// Add a fee tier
    public fun add_fee_tier(
        account: &signer,
        tick_spacing: u64,
        fee_rate: u64
    ) acquires FeeTiers {
        assert!(fee_rate <= MAX_FEE_RATE, EINVALID_FEE_RATE);

        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@dexlyn_clmm);
        assert!(
            !simple_map::contains_key(&fee_tiers.fee_tiers, &tick_spacing),
            EFEE_TIER_ALREADY_EXIST
        );
        simple_map::add(&mut fee_tiers.fee_tiers, tick_spacing, FeeTier {
            tick_spacing,
            fee_rate
        });
        event::emit(AddEvent {
            tick_spacing,
            fee_rate,
            timestamp: timestamp::now_seconds()
        })
    }

    /// Update the default fee rate
    public fun update_fee_tier(
        account: &signer,
        tick_spacing: u64,
        new_fee_rate: u64,
    ) acquires FeeTiers {
        assert!(new_fee_rate <= MAX_FEE_RATE, EINVALID_FEE_RATE);

        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@dexlyn_clmm);
        assert!(
            simple_map::contains_key(&fee_tiers.fee_tiers, &tick_spacing),
            EFEE_TIER_NOT_FOUND
        );

        let fee_tier = simple_map::borrow_mut(&mut fee_tiers.fee_tiers, &tick_spacing);
        let old_fee_rate = fee_tier.fee_rate;
        fee_tier.fee_rate = new_fee_rate;
        event::emit(UpdateEvent {
            tick_spacing,
            old_fee_rate,
            new_fee_rate,
            timestamp: timestamp::now_seconds()
        });
    }

    /// Delete fee_tier
    public fun delete_fee_tier(
        account: &signer,
        tick_spacing: u64,
    ) acquires FeeTiers {
        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@dexlyn_clmm);
        assert!(
            simple_map::contains_key(&fee_tiers.fee_tiers, &tick_spacing),
            EFEE_TIER_NOT_FOUND
        );
        simple_map::remove(&mut fee_tiers.fee_tiers, &tick_spacing);
        event::emit(DeleteEvent {
            tick_spacing,
            timestamp: timestamp::now_seconds()
        });
    }

    #[view]
    public fun get_fee_rate(tick_spacing: u64): u64 acquires FeeTiers {
        let fee_tiers = &borrow_global<FeeTiers>(@dexlyn_clmm).fee_tiers;
        assert!(
            simple_map::contains_key(fee_tiers, &tick_spacing),
            EFEE_TIER_NOT_FOUND
        );
        let fee_tier = simple_map::borrow(fee_tiers, &tick_spacing);
        fee_tier.fee_rate
    }

    #[view]
    public fun max_fee_rate(): u64 {
        MAX_FEE_RATE
    }
}
