/// The global config is initialized only once and store the protocol_authority, protocol_fee_claim_authority,
/// pool_create_authority and protocol_fee_rate.
/// The protocol_authority control the protocol, can update the protocol_fee_claim_authority, pool_create_authority and
/// protocol_fee_rate, and can be tranfered to others.
module dexlyn_clmm::config {
    use std::signer;

    use supra_framework::event;
    use supra_framework::timestamp;

    use dexlyn_clmm::acl::{Self, ACL};

    friend dexlyn_clmm::factory;


    const DEFAULT_ADDRESS: address = @0x0;
    const MAX_PROTOCOL_FEE_RATE: u64 = 4000;
    const DEFAULT_PROTOCOL_FEE_RATE: u64 = 3333;

    /// the signer is not authorized to perform the action
    const ENOT_HAS_PRIVILEGE: u64 = 1;

    /// The global config is already initialized
    const ECONFIG_ALREADY_INITIALIZED: u64 = 2;

    /// The protocol fee rate is set too high
    const EINVALID_PROTOCOL_FEE_RATE: u64 = 3;

    /// The protocol is paused and an action is attempted
    const EPROTOCOL_IS_PAUSED: u64 = 4;

    /// Invalid ACL role is provided
    const EINVALID_ACL_ROLE: u64 = 5;

    /// Roles
    const ROLE_SET_POSITION_NFT_URI: u8 = 1;
    const ROLE_RESET_INIT_SQRT_PRICE: u8 = 2;

    /// The clmmpools global config
    struct GlobalConfig has key {
        /// The authority to control the config and clmmpools related to this clmmconfig.
        protocol_authority: address,

        /// `protocol_pending_authority` is used when transfer protocol authority, store the new authority to accept in next step and as the new authority.
        protocol_pending_authority: address,

        /// `protocol_fee_claim_authority` is used when claim the protocol fee.
        protocol_fee_claim_authority: address,

        /// `pool_create_authority` is used when create pool. if this address is Default it means everyone can create the pool.
        pool_create_authority: address,

        /// `fee_rate` The protocol fee rate
        protocol_fee_rate: u64,

        is_pause: bool,
    }

    struct ClmmACL has key {
        acl: ACL
    }


    #[event]
    struct TransferAuthEvent has drop, store {
        old_auth: address,
        new_auth: address,
        timestamp: u64,
    }

    #[event]
    struct AcceptAuthEvent has drop, store {
        old_auth: address,
        new_auth: address,
        timestamp: u64,
    }

    #[event]
    struct UpdateClaimAuthEvent has drop, store {
        old_auth: address,
        new_auth: address,
        timestamp: u64,
    }

    #[event]
    struct UpdatePoolCreateEvent has drop, store {
        old_auth: address,
        new_auth: address,
        timestamp: u64,
    }

    #[event]
    struct UpdateFeeRateEvent has drop, store {
        old_fee_rate: u64,
        new_fee_rate: u64,
        timestamp: u64,
    }


    /// initialize the global config of dexlyn clmm protocol
    public fun initialize(
        account: &signer,
    ) {
        assert_initialize_authority(account);
        let deployer = @dexlyn_clmm;
        move_to(account, GlobalConfig {
            protocol_authority: deployer,
            protocol_pending_authority: DEFAULT_ADDRESS,
            protocol_fee_claim_authority: deployer,
            pool_create_authority: DEFAULT_ADDRESS,
            protocol_fee_rate: DEFAULT_PROTOCOL_FEE_RATE,
            is_pause: false,
        });
    }

    /// Transfer the protocol authority
    public fun transfer_protocol_authority(
        account: &signer,
        protocol_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@dexlyn_clmm);
        global_config.protocol_pending_authority = protocol_authority;
        event::emit(TransferAuthEvent {
            old_auth: global_config.protocol_authority,
            new_auth: protocol_authority,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Accept the protocol authority protocol authority
    public fun accept_protocol_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global_mut<GlobalConfig>(@dexlyn_clmm);
        assert!(
            global_config.protocol_pending_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
        let old_auth = global_config.protocol_authority;
        global_config.protocol_authority = signer::address_of(account);
        global_config.protocol_pending_authority = DEFAULT_ADDRESS;
        event::emit(AcceptAuthEvent {
            old_auth,
            new_auth: global_config.protocol_authority,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update the protocol fee claim authority
    public fun update_protocol_fee_claim_authority(
        account: &signer,
        protocol_fee_claim_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@dexlyn_clmm);
        let old_auth = global_config.protocol_fee_claim_authority;
        global_config.protocol_fee_claim_authority = protocol_fee_claim_authority;
        event::emit(UpdateClaimAuthEvent {
            old_auth,
            new_auth: global_config.protocol_fee_claim_authority,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update the pool create authority
    public fun update_pool_create_authority(
        account: &signer,
        pool_create_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@dexlyn_clmm);
        let old_auth = global_config.pool_create_authority;
        global_config.pool_create_authority = pool_create_authority;
        event::emit(UpdatePoolCreateEvent {
            old_auth,
            new_auth: global_config.pool_create_authority,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update the protocol fee rate
    public fun update_protocol_fee_rate(
        account: &signer,
        protocol_fee_rate: u64
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        assert!(protocol_fee_rate <= MAX_PROTOCOL_FEE_RATE, EINVALID_PROTOCOL_FEE_RATE);
        let global_config = borrow_global_mut<GlobalConfig>(@dexlyn_clmm);
        let old_fee_rate = global_config.protocol_fee_rate;
        global_config.protocol_fee_rate = protocol_fee_rate;
        event::emit(UpdateFeeRateEvent {
            old_fee_rate,
            new_fee_rate: protocol_fee_rate,
            timestamp: timestamp::now_seconds(),
        });
    }


    public fun pause(account: &signer) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@dexlyn_clmm);
        global_config.is_pause = true;
    }

    public fun unpause(account: &signer) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@dexlyn_clmm);
        global_config.is_pause = false;
    }

    public fun assert_protocol_status() acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@dexlyn_clmm);
        if (global_config.is_pause) {
            abort EPROTOCOL_IS_PAUSED
        }
    }

    #[view]
    /// Get protocol fee rate
    public fun get_protocol_fee_rate(): u64 acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@dexlyn_clmm);
        global_config.protocol_fee_rate
    }

    public fun assert_initialize_authority(account: &signer) {
        assert!(
            signer::address_of(account) == @dexlyn_clmm,
            ENOT_HAS_PRIVILEGE
        );
    }

    public fun assert_protocol_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@dexlyn_clmm);
        assert!(
            global_config.protocol_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
    }

    public fun assert_protocol_fee_claim_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@dexlyn_clmm);
        assert!(
            global_config.protocol_fee_claim_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
    }

    public fun assert_pool_create_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@dexlyn_clmm);
        assert!(
            (
                global_config.pool_create_authority == signer::address_of(account) ||
                    global_config.pool_create_authority == DEFAULT_ADDRESS
            ),
            ENOT_HAS_PRIVILEGE
        );
    }

    public fun init_clmm_acl(account: &signer) {
        assert_initialize_authority(account);
        move_to(account, ClmmACL {
            acl: acl::new()
        })
    }

    public fun add_role(account: &signer, member: address, role: u8) acquires GlobalConfig, ClmmACL {
        assert!(role == ROLE_SET_POSITION_NFT_URI || role == ROLE_RESET_INIT_SQRT_PRICE, EINVALID_ACL_ROLE);
        assert_protocol_authority(account);
        let clmm_acl = borrow_global_mut<ClmmACL>(@dexlyn_clmm);
        acl::add_role(&mut clmm_acl.acl, member, role)
    }

    public fun remove_role(account: &signer, member: address, role: u8) acquires GlobalConfig, ClmmACL {
        assert!(role == ROLE_SET_POSITION_NFT_URI || role == ROLE_RESET_INIT_SQRT_PRICE, EINVALID_ACL_ROLE);
        assert_protocol_authority(account);
        let clmm_acl = borrow_global_mut<ClmmACL>(@dexlyn_clmm);
        acl::remove_role(&mut clmm_acl.acl, member, role)
    }

    public fun allow_set_position_nft_uri(
        account: &signer
    ): bool acquires ClmmACL {
        let clmm_acl = borrow_global<ClmmACL>(@dexlyn_clmm);
        acl::has_role(&clmm_acl.acl, signer::address_of(account), ROLE_SET_POSITION_NFT_URI)
    }

    public fun assert_reset_init_price_authority(
        account: &signer
    ) acquires ClmmACL {
        let clmm_acl = borrow_global<ClmmACL>(@dexlyn_clmm);
        if (!acl::has_role(&clmm_acl.acl, signer::address_of(account), ROLE_RESET_INIT_SQRT_PRICE)) {
            abort ENOT_HAS_PRIVILEGE
        }
    }
}