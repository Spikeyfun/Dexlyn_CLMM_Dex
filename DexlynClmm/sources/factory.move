module dexlyn_clmm::factory {
    use std::bcs;
    use std::option;
    use std::signer;
    use std::string::{Self, length, String};
    use aptos_std::comparator;
    use aptos_std::table::{Self, Table};

    use supra_framework::account;
    use supra_framework::event;
    use supra_framework::timestamp;

    use dexlyn_clmm::config;
    use dexlyn_clmm::fee_tier;
    use dexlyn_clmm::partner;
    use dexlyn_clmm::pool;
    use dexlyn_clmm::tick_math;
    use dexlyn_clmm::utils;

    /// Consts
    const POOL_OWNER_SEED: vector<u8> = b"DexlynPoolOwner";
    const COLLECTION_DESCRIPTION: vector<u8> = b"Dexlyn Liquidity Position";
    const POOL_DEFAULT_URI: vector<u8> = b"";

    /// Errors
    /// The pool is already initialized
    const EPOOL_ALREADY_INITIALIZED: u64 = 1;

    /// The initialize price is invalid
    const EINVALID_SQRTPRICE: u64 = 2;

    /// For support create pool by anyone, PoolOwner store a resource account signer_cap
    struct PoolOwner has key {
        signer_capability: account::SignerCapability,
    }

    struct PoolId has store, copy, drop {
        asset_a_address: address,
        asset_b_address: address,
        tick_spacing: u64
    }

    /// Store the pools metadata info in the deployed(@dexlyn_clmm) account.
    struct Pools has key {
        data: Table<PoolId, address>,
        index: u64,
    }

    #[event]
    struct CreatePoolEvent has drop, store {
        creator: address,
        pool_address: address,
        position_collection_name: String,
        asset_a_address: address,
        asset_b_address: address,
        tick_spacing: u64,
        timestamp: u64,
        init_sqrt_price: u128
    }

    fun init_module(
        account: &signer
    ) {
        move_to(account, Pools {
            data: table::new(),
            index: 0,
        });

        let (_, signer_cap) = account::create_resource_account(account, POOL_OWNER_SEED);
        move_to(account, PoolOwner {
            signer_capability: signer_cap,
        });
        config::initialize(account);
        fee_tier::initialize(account);
        partner::initialize(account);
    }

    /// Create pool with fa addresses
    public fun create_pool(
        account: &signer,
        tick_spacing: u64,
        initialize_price: u128,
        uri: String,
        asset_a_addr: address,
        asset_b_addr: address
    ): address acquires PoolOwner, Pools {
        config::assert_pool_create_authority(account);

        let uri = if (length(&uri) == 0 || !config::allow_set_position_nft_uri(account)) {
            string::utf8(POOL_DEFAULT_URI)
        } else {
            uri
        };

        assert!(
            initialize_price >= tick_math::min_sqrt_price() && initialize_price <= tick_math::max_sqrt_price(),
            EINVALID_SQRTPRICE
        );

        // Create pool account
        let pool_id = new_pool_id(tick_spacing, asset_a_addr, asset_b_addr);
        let pool_owner = borrow_global<PoolOwner>(@dexlyn_clmm);
        let pool_owner_signer = account::create_signer_with_capability(&pool_owner.signer_capability);

        let pool_seed = new_pool_seed(tick_spacing, asset_a_addr, asset_b_addr);
        let pool_seed = bcs::to_bytes<PoolId>(&pool_seed);
        let (pool_signer, signer_cap) = account::create_resource_account(&pool_owner_signer, pool_seed);
        let pool_address = signer::address_of(&pool_signer);

        let pools = borrow_global_mut<Pools>(@dexlyn_clmm);
        pools.index = pools.index + 1;
        assert!(
            !table::contains(&pools.data, pool_id),
            EPOOL_ALREADY_INITIALIZED
        );
        table::add(&mut pools.data, pool_id, pool_address);

        // Initialize pool's metadata
        let position_collection_name = pool::new(
            &pool_signer,
            tick_spacing,
            initialize_price,
            pools.index,
            uri,
            signer_cap,
            asset_a_addr,
            asset_b_addr,
        );

        event::emit(CreatePoolEvent {
            asset_a_address: asset_a_addr,
            asset_b_address: asset_b_addr,
            tick_spacing,
            creator: signer::address_of(account),
            pool_address,
            position_collection_name,
            timestamp: timestamp::now_seconds(),
            init_sqrt_price: initialize_price
        });
        pool_address
    }

    #[view]
    public fun get_pool(
        tick_spacing: u64,
        asset_a_addr: address,
        asset_b_addr: address
    ): option::Option<address> acquires Pools {
        let pools = borrow_global<Pools>(@dexlyn_clmm);
        let pool_id = new_pool_id(tick_spacing, asset_a_addr, asset_b_addr);
        if (table::contains(&pools.data, pool_id)) {
            return option::some(*table::borrow(&pools.data, pool_id))
        };
        option::none<address>()
    }

    fun new_pool_id(tick_spacing: u64, asset_a_address: address, asset_b_address: address): PoolId {
        PoolId {
            asset_a_address: asset_a_address,
            asset_b_address: asset_b_address,
            tick_spacing
        }
    }

    fun new_pool_seed(tick_spacing: u64, asset_a_address: address, asset_b_address: address): PoolId {
        if (comparator::is_smaller_than(&utils::compare_address(asset_a_address, asset_b_address))) {
            PoolId {
                asset_a_address: asset_a_address,
                asset_b_address: asset_b_address,
                tick_spacing
            }
        } else {
            PoolId {
                asset_a_address: asset_b_address,
                asset_b_address: asset_a_address,
                tick_spacing
            }
        }
    }

    #[test_only(admin= @dexlyn_clmm)]
    public fun init_factory_module(admin: &signer) {
        init_module(admin);
    }
}
