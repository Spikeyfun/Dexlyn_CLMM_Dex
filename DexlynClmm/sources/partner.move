/// The partner module provide the ability to the thrid party to share part of protocol fee, when swaping through clmmpool.
/// The partner is created and controled by the protocol.
/// The partner is identified by name.
/// The partner is valided by start_time and end_time.
/// The partner fee is received by receiver.
/// The receiver can transfer the receiver address to other address.
/// The partner fee_rate, start_time and end_time can be update by the protocol.

module dexlyn_clmm::partner {
    use std::signer;
    use std::string::{Self, String};
    use aptos_std::table::{Self, Table};

    use supra_framework::account;
    use supra_framework::event;
    use supra_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use supra_framework::object;
    use supra_framework::primary_fungible_store;
    use supra_framework::timestamp;

    use dexlyn_clmm::config;

    const PARTNER_RATE_DENOMINATOR: u64 = 10000;
    const DEFAULT_ADDRESS: address = @0x0;
    const MAX_PARTNER_FEE_RATE: u64 = 10000;

    /// Errors

    /// The partner is already initialized
    const EPARTNER_ALREADY_INITIALIZED: u64 = 1;

    /// The partner already existed
    const EPARTNER_ALREADY_EXISTED: u64 = 2;

    /// The partner not existed
    const EPARTNER_NOT_EXISTED: u64 = 3;

    /// The receiver is invalid
    const EINVALID_RECEIVER: u64 = 4;

    /// The start_time and end_time is invalid
    const EINVALID_TIME: u64 = 5;

    /// The partner fee rate is invalid
    const EINVALID_PARTNER_FEE_RATE: u64 = 6;

    /// The partner name is invalid
    const EINVALID_PARTNER_NAME: u64 = 7;

    /// The Partners map
    struct Partners has key {
        data: Table<String, Partner>,
    }

    struct PartnerMetadata has store, copy, drop {
        partner_address: address,
        receiver: address,
        pending_receiver: address,
        fee_rate: u64,
        start_time: u64,
        end_time: u64,
    }

    /// The Partner.
    struct Partner has store {
        metadata: PartnerMetadata,
        signer_capability: account::SignerCapability,
    }

    #[event]
    struct CreateEvent has drop, store {
        partner_address: address,
        fee_rate: u64,
        name: String,
        receiver: address,
        start_time: u64,
        end_time: u64,
        timestamp: u64,
    }

    #[event]
    struct UpdateFeeRateEvent has drop, store {
        name: String,
        old_fee_rate: u64,
        new_fee_rate: u64,
        timestamp: u64,
    }

    #[event]
    struct UpdateTimeEvent has drop, store {
        name: String,
        start_time: u64,
        end_time: u64,
        timestamp: u64,
    }

    #[event]
    struct TransferReceiverEvent has drop, store {
        name: String,
        old_receiver: address,
        new_receiver: address,
        timestamp: u64,
    }

    #[event]
    struct AcceptReceiverEvent has drop, store {
        name: String,
        receiver: address,
        timestamp: u64
    }

    #[event]
    struct ReceiveRefFeeEvent has drop, store {
        name: String,
        amount: u64,
        asset_type: address,
        timestamp: u64,
    }

    #[event]
    struct ClaimRefFeeEvent has drop, store {
        name: String,
        receiver: address,
        asset_type: address,
        amount: u64,
        timestamp: u64,
    }

    #[view]
    public fun partner_fee_rate_denominator(): u64 {
        PARTNER_RATE_DENOMINATOR
    }

    /// Initialize the partner in @dexlyn_clmm account.
    /// Params
    /// Return
    ///
    public fun initialize(account: &signer) {
        config::assert_initialize_authority(account);
        move_to(account, Partners {
            data: table::new<String, Partner>(),
        })
    }

    /// Create a partner, identified by name
    /// Params
    ///     - fee_rate
    ///     - name: partner name.
    ///     - receiver: receiver address used for receive asset.
    ///     - start_time
    ///     - end_time
    /// Return
    ///
    public fun create_partner(
        account: &signer,
        name: String,
        fee_rate: u64,
        receiver: address,
        start_time: u64,
        end_time: u64,
    ) acquires Partners {
        assert!(end_time > start_time, EINVALID_TIME);
        assert!(end_time > timestamp::now_seconds(), EINVALID_TIME);
        assert!(fee_rate < MAX_PARTNER_FEE_RATE, EINVALID_PARTNER_FEE_RATE);
        assert!(!string::is_empty(&name), EINVALID_PARTNER_NAME);

        config::assert_protocol_authority(account);
        let partners = borrow_global_mut<Partners>(@dexlyn_clmm);
        assert!(!table::contains(&partners.data, name), EPARTNER_ALREADY_EXISTED);
        let (partner_signer, signer_capability) = account::create_resource_account(
            account,
            *string::bytes(&name)
        );
        let partner_address = signer::address_of(&partner_signer);
        table::add(&mut partners.data, name, Partner {
            metadata: PartnerMetadata {
                receiver,
                pending_receiver: DEFAULT_ADDRESS,
                fee_rate,
                start_time,
                end_time,
                partner_address,
            },
            signer_capability,
        });
        event::emit<CreateEvent>(CreateEvent {
            partner_address,
            fee_rate,
            name,
            receiver,
            start_time,
            end_time,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update the partner fee_rate by protocol_fee_authority
    /// Params
    ///     - name: partner name.
    ///     - new_fee_rate
    /// Return
    ///
    public fun update_fee_rate(
        account: &signer,
        name: String,
        new_fee_rate: u64
    ) acquires Partners {
        assert!(new_fee_rate < MAX_PARTNER_FEE_RATE, EINVALID_PARTNER_FEE_RATE);

        config::assert_protocol_authority(account);
        let partners = borrow_global_mut<Partners>(@dexlyn_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);

        let partner = table::borrow_mut(&mut partners.data, name);
        let old_fee_rate = partner.metadata.fee_rate;
        partner.metadata.fee_rate = new_fee_rate;
        event::emit(UpdateFeeRateEvent {
            name,
            old_fee_rate,
            new_fee_rate,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update the partner time by protocol_fee_authority
    /// Update the partner fee_rate by protocol_fee_authority
    /// Params
    ///     - name: partner name.
    ///     - start_time
    ///     - end_time
    /// Return
    ///
    public fun update_time(
        account: &signer,
        name: String,
        start_time: u64,
        end_time: u64
    ) acquires Partners {
        assert!(end_time > start_time, EINVALID_TIME);
        assert!(end_time > timestamp::now_seconds(), EINVALID_TIME);

        config::assert_protocol_authority(account);

        let partners = borrow_global_mut<Partners>(@dexlyn_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);
        let partner = table::borrow_mut(&mut partners.data, name);
        partner.metadata.start_time = start_time;
        partner.metadata.end_time = end_time;
        event::emit(UpdateTimeEvent {
            name,
            start_time,
            end_time,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Transfer the claim authority
    /// Params
    ///     -name
    ///     -new_receiver
    /// Return
    ///
    public fun transfer_receiver(
        account: &signer,
        name: String,
        new_receiver: address
    ) acquires Partners {
        let old_receiver_addr = signer::address_of(account);
        let partners = borrow_global_mut<Partners>(@dexlyn_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);
        let partner = table::borrow_mut(&mut partners.data, name);
        assert!(old_receiver_addr == partner.metadata.receiver, EINVALID_RECEIVER);
        partner.metadata.pending_receiver = new_receiver;
        event::emit(TransferReceiverEvent {
            name,
            old_receiver: partner.metadata.receiver,
            new_receiver,
            timestamp: timestamp::now_seconds(),
        })
    }

    /// Accept the partner receiver.
    /// Params
    ///     - name
    /// Return
    ///
    public fun accept_receiver(account: &signer, name: String) acquires Partners {
        let receiver_addr = signer::address_of(account);
        let partners = borrow_global_mut<Partners>(@dexlyn_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);
        let partner = table::borrow_mut(&mut partners.data, name);
        assert!(receiver_addr == partner.metadata.pending_receiver, EINVALID_RECEIVER);
        partner.metadata.receiver = receiver_addr;
        partner.metadata.pending_receiver = DEFAULT_ADDRESS;
        event::emit(AcceptReceiverEvent {
            name,
            receiver: receiver_addr,
            timestamp: timestamp::now_seconds(),
        })
    }

    #[view]
    /// get partner fee rate by name.
    /// Params
    ///     -name
    /// Return
    ///     -u64: ref_fee_rate
    public fun get_ref_fee_rate(name: String): u64 acquires Partners {
        let partners = &borrow_global<Partners>(@dexlyn_clmm).data;
        if (!table::contains(partners, name)) {
            return 0
        };
        let partner = table::borrow(partners, name);
        let current_time = timestamp::now_seconds();
        if (partner.metadata.start_time > current_time || partner.metadata.end_time <= current_time) {
            return 0
        };
        partner.metadata.fee_rate
    }

    /// Receive the asset direct from swap.
    /// Params
    ///     -name
    ///     -asset: the asset resource to transfer to partner.
    /// Return
    ///
    public fun receive_ref_fee(
        name: String,
        receive_asset: FungibleAsset,
        asset_addr: address,
    ) acquires Partners {
        let partners = borrow_global_mut<Partners>(@dexlyn_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);

        let partner = table::borrow(&partners.data, name);

        // Send ref fee to partner account.
        let amount = fungible_asset::amount(&receive_asset);
        primary_fungible_store::deposit(partner.metadata.partner_address, receive_asset);

        event::emit(ReceiveRefFeeEvent {
            name,
            amount,
            asset_type: asset_addr,
            timestamp: timestamp::now_seconds(),
        })
    }

    /// Claim partner account's ref fee for partner
    public fun claim_ref_fee(account: &signer, name: String, asset_type_addr: address) acquires Partners {
        let partners = borrow_global_mut<Partners>(@dexlyn_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);

        let partner = table::borrow(&partners.data, name);
        assert!(signer::address_of(account) == partner.metadata.receiver, EINVALID_RECEIVER);
        let asset_reward_metadata = object::address_to_object<Metadata>(asset_type_addr);
        let balance = primary_fungible_store::balance(partner.metadata.partner_address, asset_reward_metadata);
        let partner_account = account::create_signer_with_capability(&partner.signer_capability);
        let ref_fee = primary_fungible_store::withdraw(&partner_account, asset_reward_metadata, balance);
        primary_fungible_store::deposit(signer::address_of(account), ref_fee);

        event::emit(ClaimRefFeeEvent {
            name,
            receiver: partner.metadata.receiver,
            asset_type: asset_type_addr,
            amount: balance,
            timestamp: timestamp::now_seconds(),
        })
    }
}
