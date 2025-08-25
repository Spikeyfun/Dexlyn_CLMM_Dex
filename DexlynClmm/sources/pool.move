module dexlyn_clmm::pool {
    use std::bit_vector::{Self, BitVector};
    use std::option::{Self, is_none, Option};
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_std::table::{Self, Table};

    use aptos_token_objects::token;
    use supra_framework::account;
    use supra_framework::event;
    use supra_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use supra_framework::object;
    use supra_framework::primary_fungible_store;
    use supra_framework::timestamp;

    use dexlyn_clmm::clmm_math;
    use dexlyn_clmm::config;
    use dexlyn_clmm::fee_tier;
    use dexlyn_clmm::partner;
    use dexlyn_clmm::position_nft;
    use dexlyn_clmm::tick_math;
    use dexlyn_clmm::tick_math::{is_valid_index, max_sqrt_price, min_sqrt_price};
    use integer_mate::full_math_u128;
    use integer_mate::full_math_u64;
    use integer_mate::i128::{Self, I128, is_neg};
    use integer_mate::i64::{Self, I64};
    use integer_mate::math_u128;
    use integer_mate::math_u64;

    #[test_only]
    use std::string::utf8;
    #[test_only]
    use dexlyn_clmm::test_helpers::setup_fungible_assets;

    // use aptos_token_objects::royalty;
    friend dexlyn_clmm::factory;

    /// The BitVector of tick indexes length
    const TICK_INDEXES_LENGTH: u64 = 1000;

    /// The denominator of protocol fee rate(rate=protocol_fee_rate/10000)
    const PROTOCOL_FEE_DENOMNINATOR: u64 = 10000;

    /// Royalty numerator and denominator 5%
    // const ROYALTY_NUMERATOR: u64 = 500;
    // const ROYALTY_DENOMNINATOR: u64 = 10000;

    /// rewarder num
    const REWARDER_NUM: u64 = 3;

    ///
    const DAYS_IN_SECONDS: u128 = 24 * 60 * 60;
    const DEFAULT_ADDRESS: address = @0x0;

    const COLLECTION_DESCRIPTION: vector<u8> = b"Dexlyn Liquidity Position";
    const POOL_DEFAULT_URI: vector<u8> = b"";

    /// Errors

    /// The tick is invalid
    const EINVALID_TICK: u64 = 1;

    /// The pool is already initialized
    const ETICK_ALREADY_INTIIALIZE: u64 = 2;

    /// The tick spacing is zero
    const ETICK_SPACING_IS_ZERO: u64 = 3;

    /// reuired amount A exceeds the maximum allowed value
    const EAMOUNT_IN_ABOVE_MAX_LIMIT: u64 = 4;

    /// returned amount B is below the minimum limit
    const EAMOUNT_OUT_BELOW_MIN_LIMIT: u64 = 5;

    /// The amount in or out is incorrect
    const EAMOUNT_INCORRECT: u64 = 6;

    /// The liquidity overflow
    const ELIQUIDITY_OVERFLOW: u64 = 7;

    /// The liquidity underflow
    const ELIQUIDITY_UNDERFLOW: u64 = 8;

    /// The tick indexes are not set
    const ETICK_INDEXES_NOT_SET: u64 = 9;

    /// The tick not found
    const ETICK_NOT_FOUND: u64 = 10;

    /// The liquidity is zero
    const ELIQUIDITY_IS_ZERO: u64 = 11;

    /// Not enough liquidity in the pool to perform the swap
    const ENOT_ENOUGH_LIQUIDITY: u64 = 12;

    // The remainer amount underflow
    const EREMAINER_AMOUNT_UNDERFLOW: u64 = 13;

    /// The swap amount in or out overflow
    const ESWAP_AMOUNT_IN_OVERFLOW: u64 = 14;

    /// The swap amount out overflow
    const ESWAP_AMOUNT_OUT_OVERFLOW: u64 = 15;

    /// The swap fee amount overflow
    const ESWAP_FEE_AMOUNT_OVERFLOW: u64 = 16;

    /// The fee rate is incorrect
    const EINVALID_FEE_RATE: u64 = 17;

    /// The fixed token type is invalid
    const EINVALID_FIXED_TOKEN_TYPE: u64 = 18;

    /// The pool not exists
    const EPOOL_NOT_EXISTS: u64 = 19;

    /// The swap amount in is incorrect
    const ESWAP_AMOUNT_INCORRECT: u64 = 20;

    /// The partner is invalid
    const EINVALID_PARTNER: u64 = 21;

    /// The sqrt price is not in the range of tick spacing
    const EWRONG_SQRT_PRICE_LIMIT: u64 = 22;

    /// The reward index is invalid
    const EINVALID_REWARD_INDEX: u64 = 23;

    /// The reward amount is insufficient
    const EREWARD_AMOUNT_INSUFFICIENT: u64 = 24;

    /// The reward not match with index
    const EREWARD_NOT_MATCH_WITH_INDEX: u64 = 25;

    /// The reward authority is not match with pool
    const EREWARD_AUTH_ERROR: u64 = 26;

    /// The time is invalid
    const EINVALID_TIME: u64 = 27;

    /// The position owner is not match with pool
    const EPOSITION_OWNER_ERROR: u64 = 28;

    /// The position not exist
    const EPOSITION_NOT_EXIST: u64 = 29;

    /// The tick is not valid
    const EIS_NOT_VALID_TICK: u64 = 30;

    /// The pool address is not match with pool
    const EPOOL_ADDRESS_ERROR: u64 = 31;

    /// The pool is paused
    const EPOOL_IS_PAUDED: u64 = 32;

    /// The pool liquidity is not zero, can not reset the init price
    const EPOOL_LIQUIDITY_IS_NOT_ZERO: u64 = 33;

    /// The rewarder owned overflow
    const EREWARDER_OWNED_OVERFLOW: u64 = 34;

    /// The fee owned overflow
    const EFEE_OWNED_OVERFLOW: u64 = 35;

    /// The delta liquidity is invalid
    const EINVALID_DELTA_LIQUIDITY: u64 = 36;

    /// The asset type is same
    const ESAME_ASSET_TYPE: u64 = 37;

    /// The sqrt price is invalid
    const EINVALID_SQRT_PRICE: u64 = 38;

    /// The function is disabled
    const EFUNC_DISABLED: u64 = 39;

    /// The account has no privilege to call this function
    const ENOT_HAS_PRIVILEGE: u64 = 40;

    /// The pool uri is invalid
    const EINVALID_POOL_URI: u64 = 41;

    /// The asset type is different
    const EDIFFERENT_ASSET_TYPE: u64 = 42;

    /// The clmmpool metadata info
    struct Pool has key {
        /// Pool index
        index: u64,

        /// pool position token collection name
        collection_name: String,

        /// The pool asset A type
        asset_a: u64,

        /// The pool asset B type
        asset_b: u64,

        /// The tick spacing
        tick_spacing: u64,

        /// The numerator of fee rate, the denominator is 1_000_000.
        fee_rate: u64,

        /// The liquidity of current tick index
        liquidity: u128,

        /// The current sqrt price
        current_sqrt_price: u128,

        /// The current tick index
        current_tick_index: I64,

        /// The global fee growth of asset a as Q64.64
        fee_growth_global_a: u128,
        /// The global fee growth of asset b as Q64.64
        fee_growth_global_b: u128,

        /// The amounts of asset a owed to protocol
        fee_protocol_asset_a: u64,
        /// The amounts of asset b owed to protocol
        fee_protocol_asset_b: u64,

        /// The tick indexes table
        tick_indexes: Table<u64, BitVector>,
        /// The ticks table
        ticks: Table<I64, Tick>,

        rewarder_infos: vector<Rewarder>,
        rewarder_last_updated_time: u64,

        /// Positions
        positions: Table<u64, Position>,
        /// Position Count
        position_index: u64,

        /// is the pool paused
        is_pause: bool,

        /// The position nft uri.
        uri: String,

        /// The pool account signer capability
        signer_cap: account::SignerCapability,

        /// FungibleAsset A object address
        asset_a_addr: address,

        /// FungibleAsset B object address
        asset_b_addr: address,

    }

    /// The clmmpool's tick item
    struct Tick has copy, drop, store {
        index: I64,
        sqrt_price: u128,
        liquidity_net: I128,
        liquidity_gross: u128,
        fee_growth_outside_a: u128,
        fee_growth_outside_b: u128,
        rewarders_growth_outside: vector<u128>,
    }

    /// The clmmpool's liquidity position.
    struct Position has copy, drop, store {
        pool: address,
        index: u64,
        liquidity: u128,
        tick_lower_index: I64,
        tick_upper_index: I64,
        fee_growth_inside_a: u128,
        fee_owed_a: u64,
        fee_growth_inside_b: u128,
        fee_owed_b: u64,
        rewarder_infos: vector<PositionRewarder>,
    }

    /// The clmmpools's Rewarder for provide additional liquidity incentives.
    struct Rewarder has copy, drop, store {
        asset_address: address,
        authority: address,
        pending_authority: address,
        emissions_per_second: u128,
        growth_global: u128,
    }

    /// The PositionRewarder for record position's additional liquidity incentives.
    struct PositionRewarder has drop, copy, store {
        growth_inside: u128,
        amount_owed: u64,
    }

    /// Flash loan resource for swap.
    /// There is no way in Move to pass calldata and make dynamic calls, but a resource can be used for this purpose.
    /// To make the execution into a single transaction, the flash loan function must return a resource
    /// that cannot be copied, cannot be saved, cannot be dropped, or cloned.
    struct FlashSwapReceipt {
        pool_address: address,
        a2b: bool,
        partner_name: String,
        pay_amount: u64,
        ref_fee_amount: u64
    }

    /// Flash loan resource for add_liquidity
    struct AddLiquidityReceipt {
        pool_address: address,
        amount_a: u64,
        amount_b: u64
    }

    /// The swap result
    struct SwapResult has copy, drop {
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        ref_fee_amount: u64,
    }

    /// The calculated swap result
    struct CalculatedSwapResult has copy, drop, store {
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        fee_rate: u64,
        after_sqrt_price: u128,
        is_exceed: bool,
        step_results: vector<SwapStepResult>
    }

    /// The step swap result
    struct SwapStepResult has copy, drop, store {
        current_sqrt_price: u128,
        target_sqrt_price: u128,
        current_liquidity: u128,
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        remainer_amount: u64
    }

    /// The position's fee result
    struct PositionReward has drop {
        pool_address: address,
        position_id: u64,
        fee_a: u64,
        fee_b: u64,
    }

    /// The position's NFT details
    struct NftDetails has copy, drop, store {
        pool_address: address,
        index: u64,
        tick_lower: u64,
        tick_upper: u64,
        liquidity: u128,
    }

    // Events
    //============================================================================================================
    #[event]
    struct OpenPositionEvent has drop, store {
        user: address,
        pool: address,
        tick_lower: I64,
        tick_upper: I64,
        position_index: u64,
        timestamp: u64,
    }

    #[event]
    struct ClosePositionEvent has drop, store {
        user: address,
        pool: address,
        position_index: u64,
        timestamp: u64,
    }

    #[event]
    struct AddLiquidityEvent has drop, store {
        pool_address: address,
        tick_lower: I64,
        tick_upper: I64,
        liquidity: u128,
        amount_a: u64,
        amount_b: u64,
        position_index: u64,
        timestamp: u64,
    }

    #[event]
    struct RemoveLiquidityEvent has drop, store {
        pool_address: address,
        tick_lower: I64,
        tick_upper: I64,
        liquidity: u128,
        amount_a: u64,
        amount_b: u64,
        position_index: u64,
        timestamp: u64,
    }

    #[event]
    struct AssetSwapEvent has drop, store {
        atob: bool,
        pool_address: address,
        swap_from: address,
        partner: String,
        amount_in: u64,
        amount_out: u64,
        ref_amount: u64,
        fee_amount: u64,
        vault_a_amount: u64,
        vault_b_amount: u64,
        timestamp: u64,
        current_sqrt_price: u128,
        current_tick: I64,
    }

    #[event]
    struct CollectProtocolFeeEvent has drop, store {
        pool_address: address,
        amount_a: u64,
        amount_b: u64,
        timestamp: u64,
    }

    #[event]
    struct CollectFeeEvent has drop, store {
        position_index: u64,
        user: address,
        pool_address: address,
        amount_a: u64,
        amount_b: u64,
        timestamp: u64,
    }

    #[event]
    struct UpdateFeeRateEvent has drop, store {
        pool_address: address,
        old_fee_rate: u64,
        new_fee_rate: u64,
        timestamp: u64,
    }

    #[event]
    struct UpdateEmissionEvent has drop, store {
        pool_address: address,
        rewarder_index: u8,
        emissions_per_second: u128,
        timestamp: u64,
    }

    #[event]
    struct TransferRewardAuthEvent has drop, store {
        pool_address: address,
        rewarder_index: u8,
        old_authority: address,
        new_authority: address,
        timestamp: u64,
    }

    #[event]
    struct AcceptRewardAuthEvent has drop, store {
        pool_address: address,
        rewarder_index: u8,
        authority: address,
        timestamp: u64
    }

    #[event]
    struct CollectRewardEvent has drop, store {
        position_index: u64,
        user: address,
        pool_address: address,
        amount: u64,
        rewarder_index: u8,
        timestamp: u64,
    }

    // PUBLIC FUNCTIONS
    //============================================================================================================
    /// Initialize a Pool
    /// Params
    ///     - account The pool resource account
    ///     - tick_spacing The pool tick spacing
    ///     - init_sqrt_price The pool initialize sqrt price
    ///     - index The pool index
    ///     - uri The pool's position collection uri
    ///     - signer_cap The pool resrouce account signer cap
    /// Returns
    ///     - pool_name: The clmmpool's position NFT collection name.
    ///
    public(friend) fun new(
        account: &signer,
        tick_spacing: u64,
        init_sqrt_price: u128,
        index: u64,
        uri: String,
        signer_cap: account::SignerCapability,
        asset_a_addr: address,
        asset_b_addr: address,
    ): String {
        assert!(asset_a_addr != asset_b_addr, ESAME_ASSET_TYPE);

        let fee_rate = fee_tier::get_fee_rate(tick_spacing);


        // let royalty = royalty::create(ROYALTY_NUMERATOR, ROYALTY_DENOMNINATOR, signer::address_of(account));

        // Create clmmpool's position NFT collection.
        let collection_name = position_nft::create_collection(
            account,
            tick_spacing,
            string::utf8(COLLECTION_DESCRIPTION),
            uri,
            // option::some(royalty)
            option::none(),
            asset_a_addr,
            asset_b_addr,
        );

        // Create clmmpool resrouce.
        move_to(account, Pool {
            asset_a: 0,
            asset_b: 0,
            tick_spacing,
            fee_rate,
            liquidity: 0,
            current_sqrt_price: init_sqrt_price,
            current_tick_index: tick_math::get_tick_at_sqrt_price(init_sqrt_price),
            fee_growth_global_a: 0,
            fee_growth_global_b: 0,
            fee_protocol_asset_a: 0,
            fee_protocol_asset_b: 0,
            tick_indexes: table::new(),
            ticks: table::new(),
            rewarder_infos: vector::empty(),
            rewarder_last_updated_time: 0,
            collection_name,
            index,
            positions: table::new(),
            position_index: 1,
            is_pause: false,
            uri,
            signer_cap,
            asset_a_addr,
            asset_b_addr
        });

        position_nft::mint(
            account,
            account,
            index,
            0,
            uri,
            collection_name,
            0,
            0,
            0,
            asset_a_addr,
            asset_b_addr,
            // option::some(royalty)
            option::none()
        );

        collection_name
    }

    /// Reset the pool initilize price if the pool is never add any liquidity.
    /// params
    ///     - pool_address The pool account address
    ///     - new_initialize_price The pool's new initialize sqrt price
    /// return
    ///     - None
    public fun reset_init_price(_pool_address: address, _new_initialize_price: u128) {
        abort EFUNC_DISABLED
        //let pool = borrow_global_mut<Pool>(pool_address);
        //assert!(pool.position_index == 1, EPOOL_LIQUIDITY_IS_NOT_ZERO);
        //pool.current_sqrt_price = new_initialize_price;
        //pool.current_tick_index = tick_math::get_tick_at_sqrt_price(new_initialize_price);
    }

    public fun reset_init_price_v2(
        account: &signer,
        pool_address: address,
        new_initialize_price: u128
    ) acquires Pool {
        config::assert_reset_init_price_authority(account);
        let pool = borrow_global_mut<Pool>(pool_address);
        assert!(
            new_initialize_price > tick_math::get_sqrt_price_at_tick(tick_min(pool.tick_spacing)) &&
                new_initialize_price < tick_math::get_sqrt_price_at_tick(tick_max(pool.tick_spacing)),
            EINVALID_SQRT_PRICE
        );
        assert!(pool.position_index == 1, EPOOL_LIQUIDITY_IS_NOT_ZERO);
        pool.current_sqrt_price = new_initialize_price;
        pool.current_tick_index = tick_math::get_tick_at_sqrt_price(new_initialize_price);
    }

    /// Pause the pool
    /// params
    ///     - pool_address The pool account address
    ///     - account The protocol authority signer
    /// return
    ///     null
    public fun pause(
        account: &signer,
        pool_address: address
    ) acquires Pool {
        config::assert_protocol_status();
        config::assert_protocol_authority(account);
        let pool = borrow_global_mut<Pool>(pool_address);
        pool.is_pause = true;
    }

    /// Unpause the pool
    /// params
    ///     - pool_address The pool account address
    ///     - account The protocol authority signer
    /// return
    ///     null
    public fun unpause(
        account: &signer,
        pool_address: address
    ) acquires Pool {
        config::assert_protocol_status();
        config::assert_protocol_authority(account);
        let pool = borrow_global_mut<Pool>(pool_address);
        pool.is_pause = false;
    }

    /// Update pool fee rate
    /// Params
    ///     - authority The protocol authority signer
    ///     - pool_address The address of pool
    ///     - fee_rate: new fee rate
    /// Return
    ///     null
    public fun update_fee_rate(
        account: &signer,
        pool_address: address,
        fee_rate: u64
    ) acquires Pool {
        if (fee_rate > fee_tier::max_fee_rate()) {
            abort EINVALID_FEE_RATE
        };

        config::assert_protocol_authority(account);

        let pool_info = borrow_global_mut<Pool>(pool_address);
        assert_status(pool_info);
        let old_fee_rate = pool_info.fee_rate;
        pool_info.fee_rate = fee_rate;
        event::emit(UpdateFeeRateEvent {
            pool_address,
            old_fee_rate,
            new_fee_rate: fee_rate,
            timestamp: timestamp::now_seconds(),
        })
    }

    /// Open a position
    /// params
    ///     - account The position owner
    ///     - pool_address The pool account address
    ///     - tick_lower_index The position tick lower index
    ///     - tick_upper_index The position tick upper index
    /// returns
    ///     position_index: u64
    public fun open_position(
        account: &signer,
        pool_address: address,
        tick_lower_index: I64,
        tick_upper_index: I64,
    ): u64 acquires Pool {
        assert!(i64::lt(tick_lower_index, tick_upper_index), EIS_NOT_VALID_TICK);

        // Get pool resource
        let pool_info = borrow_global_mut<Pool>(pool_address);
        assert_status(pool_info);

        // Check tick range
        assert!(is_valid_index(tick_lower_index, pool_info.tick_spacing), EIS_NOT_VALID_TICK);
        assert!(is_valid_index(tick_upper_index, pool_info.tick_spacing), EIS_NOT_VALID_TICK);

        // Add position to clmmpool
        table::add(
            &mut pool_info.positions,
            pool_info.position_index,
            new_empty_position(pool_address, tick_lower_index, tick_upper_index, pool_info.position_index)
        );

        // Mint position NFT
        let pool_signer = account::create_signer_with_capability(&pool_info.signer_cap);
        position_nft::mint(
            &pool_signer,
            account,
            pool_info.index,
            pool_info.position_index,
            pool_info.uri,
            pool_info.collection_name,
            i64::as_u64(tick_lower_index),
            i64::as_u64(tick_upper_index),
            pool_info.liquidity,
            pool_info.asset_a_addr,
            pool_info.asset_b_addr,
            option::none()
        );

        // Emit event
        event::emit(OpenPositionEvent {
            user: signer::address_of(account),
            pool: pool_address,
            tick_upper: tick_upper_index,
            tick_lower: tick_lower_index,
            position_index: pool_info.position_index,
            timestamp: timestamp::now_seconds(),
        });

        let position_index = pool_info.position_index;
        pool_info.position_index = pool_info.position_index + 1;
        position_index
    }

    /// Add liquidity on a position by liquidity amount.
    /// anyone can add liquidity on any position, please check the ownership of the position befor call it.
    /// params
    ///     pool_address The pool account address
    ///     liqudity The delta liqudity amount
    ///     position_index The position index
    /// return
    ///     receipt The add liquidity receipt(hot-potato)
    public fun add_liquidity(
        pool_address: address,
        liquidity: u128,
        position_index: u64
    ): AddLiquidityReceipt acquires Pool {
        assert!(liquidity != 0, ELIQUIDITY_IS_ZERO);
        add_liquidity_internal(
            pool_address,
            position_index,
            false,
            liquidity,
            0,
            false
        )
    }

    /// Add liquidity on a position by asset amount.
    /// anyone can add liquidity on any position, please check the ownership of the position befor call it.
    /// params
    ///     pool_address The pool account address
    ///     amount The asset amount
    ///     fix_amount_a If true the amount is asset_a else is asset_b
    ///     position_index The position index
    /// return
    ///     receipt The add liquidity receipt(hot-potato)
    public fun add_liquidity_fix_asset(
        pool_address: address,
        amount: u64,
        fix_amount_a: bool,
        position_index: u64
    ): AddLiquidityReceipt acquires Pool {
        assert!(amount > 0, EAMOUNT_INCORRECT);
        add_liquidity_internal(
            pool_address,
            position_index,
            true,
            0,
            amount,
            fix_amount_a
        )
    }

    /// Repay asset for increased liquidity
    /// params
    ///     asset_a The asset a
    ///     asset_b The asset b
    ///     receipt The add liquidity receipt(hot-patato)
    public fun repay_add_liquidity(
        asset_a: FungibleAsset,
        asset_b: FungibleAsset,
        receipt: AddLiquidityReceipt
    ) acquires Pool {
        let AddLiquidityReceipt {
            pool_address,
            amount_a,
            amount_b
        } = receipt;
        assert!(fungible_asset::amount(&asset_a) == amount_a, EAMOUNT_INCORRECT);
        assert!(fungible_asset::amount(&asset_b) == amount_b, EAMOUNT_INCORRECT);
        let pool = borrow_global_mut<Pool>(pool_address);
        // Merge asset
        primary_fungible_store::deposit(pool_address, asset_a);
        primary_fungible_store::deposit(pool_address, asset_b);
        pool.asset_a = pool.asset_a + amount_a;
        pool.asset_b = pool.asset_b + amount_b;
    }

    /// Remove liquidity from pool
    /// params
    ///     - account The position owner
    ///     - pool_address The pool account address
    ///     - position_index The position index
    /// return
    ///     - asset_a The asset a sended to user
    ///     - asset_b The asset b sended to user
    public fun remove_liquidity(
        account: &signer,
        pool_address: address,
        liquidity: u128,
        position_index: u64
    ): (FungibleAsset, FungibleAsset) acquires Pool {
        assert!(liquidity != 0, ELIQUIDITY_IS_ZERO);
        check_position_authority(account, pool_address, position_index);

        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool);
        update_rewarder(pool);

        // 1. Update position's fee and rewarder
        let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
            pool,
            position_index
        );
        let (fee_growth_inside_a, fee_growth_inside_b) = get_fee_in_tick_range(
            pool,
            tick_lower,
            tick_upper
        );
        let rewards_growth_inside = get_reward_in_tick_range(pool, tick_lower, tick_upper);
        let position = table::borrow_mut(&mut pool.positions, position_index);
        update_position_fee_and_reward(position, fee_growth_inside_a, fee_growth_inside_b, rewards_growth_inside);

        // 2. Update position's liquidity
        update_position_liquidity(
            position,
            liquidity,
            false
        );

        let new_liquidity = position.liquidity;

        // 3. Upsert ticks
        upsert_tick_by_liquidity(pool, tick_lower, liquidity, false, false);
        upsert_tick_by_liquidity(pool, tick_upper, liquidity, false, true);

        // 4. Update pool's liquidity and calculate liquidity's amounts.
        let (amount_a, amount_b) = clmm_math::get_amount_by_liquidity(
            tick_lower,
            tick_upper,
            pool.current_tick_index,
            pool.current_sqrt_price,
            liquidity,
            false,
        );
        let (after_liquidity, is_overflow) = if (i64::lte(tick_lower, pool.current_tick_index) && i64::lt(
            pool.current_tick_index,
            tick_upper
        )) {
            math_u128::overflowing_sub(pool.liquidity, liquidity)
        }else {
            (pool.liquidity, false)
        };
        if (is_overflow) {
            abort ELIQUIDITY_OVERFLOW
        };
        pool.liquidity = after_liquidity;


        // Update the Position NFT's liquidity property
        let collection_name = position_nft::collection_name(pool.tick_spacing, pool.asset_a_addr, pool.asset_b_addr);
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);


        position_nft::update_liquidity(
            &pool_signer,
            collection_name,
            pool.index,
            position_index,
            new_liquidity
        );


        // Emit event
        event::emit(RemoveLiquidityEvent {
            pool_address,
            tick_lower,
            tick_upper,
            liquidity,
            amount_a,
            amount_b,
            position_index: position_index,
            timestamp: timestamp::now_seconds(),
        });

        // Extract asset
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        let asset_a_metadata = object::address_to_object<Metadata>(pool.asset_a_addr);
        let asset_b_metadata = object::address_to_object<Metadata>(pool.asset_b_addr);

        let asset_a = primary_fungible_store::withdraw(
            &pool_signer,
            asset_a_metadata,
            amount_a
        );
        let asset_b = primary_fungible_store::withdraw(
            &pool_signer,
            asset_b_metadata,
            amount_b
        );

        pool.asset_a = pool.asset_a - amount_a;
        pool.asset_b = pool.asset_b - amount_b;

        (asset_a, asset_b)
    }

    /// Close the position with check
    /// params
    ///     - account The position owner
    ///     - pool_address The pool account address
    ///     - position_index The position index
    /// return
    ///     - is_closed
    public fun checked_close_position(
        account: &signer,
        pool_address: address,
        position_index: u64
    ): bool acquires Pool {
        check_position_authority(account, pool_address, position_index);
        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool);
        let position = table::borrow(&pool.positions, position_index);

        // 1. Check position liquidity is zero.
        if (position.liquidity != 0) {
            return false
        };
        // 2. Check liquidity fee
        if (position.fee_owed_a > 0 || position.fee_owed_b > 0) {
            return false
        };
        // 3. Check rewarder
        let i = 0;
        while (i < REWARDER_NUM) {
            if (vector::borrow(&position.rewarder_infos, i).amount_owed != 0) {
                return false
            };
            i = i + 1;
        };

        // 4. Remove position from pool
        table::remove(&mut pool.positions, position_index);

        // 5. Burn position NFT
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        let user_address = signer::address_of(account);
        position_nft::burn_by_collection_and_index(
            &pool_signer,
            user_address,
            pool.collection_name,
            pool.index,
            position_index
        );

        // Emit event
        event::emit(ClosePositionEvent {
            user: user_address,
            pool: pool_address,
            position_index: position_index,
            timestamp: timestamp::now_seconds(),
        });

        true
    }

    /// Collect position's liquidity fee
    /// Params
    ///     - account The position's owner
    ///     - pool_address The address of pool
    ///     - position_index The position index
    ///     - recalculate If recalcuate the position's fee before collect.
    /// Return
    ///     - asset_a The position's fee of asset_a
    ///     - asset_b The position's fee of asset_b
    public fun collect_fee(
        account: &signer,
        pool_address: address,
        position_index: u64,
        recalculate: bool,
    ): (FungibleAsset, FungibleAsset) acquires Pool {
        check_position_authority(account, pool_address, position_index);
        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool);

        let position = if (recalculate) {
            let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
                pool,
                position_index
            );
            let (fee_growth_inside_a, fee_growth_inside_b) = get_fee_in_tick_range(
                pool,
                tick_lower,
                tick_upper
            );
            let position = table::borrow_mut(&mut pool.positions, position_index);
            update_position_fee(position, fee_growth_inside_a, fee_growth_inside_b);
            position
        } else {
            table::borrow_mut(&mut pool.positions, position_index)
        };

        // Get fee
        let (amount_a, amount_b) = (position.fee_owed_a, position.fee_owed_b);
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        let a_metadata = object::address_to_object<Metadata>(pool.asset_a_addr);
        let b_metadata = object::address_to_object<Metadata>(pool.asset_b_addr);

        let asset_a = primary_fungible_store::withdraw(
            &pool_signer,
            a_metadata,
            amount_a
        );
        let asset_b = primary_fungible_store::withdraw(
            &pool_signer,
            b_metadata,
            amount_b
        );

        pool.asset_a = pool.asset_a - amount_a;
        pool.asset_b = pool.asset_b - amount_b;

        // Reset position fee
        position.fee_owed_a = 0;
        position.fee_owed_b = 0;

        // Emit event
        event::emit(CollectFeeEvent {
            pool_address,
            user: signer::address_of(account),
            amount_a,
            amount_b,
            position_index: position_index,
            timestamp: timestamp::now_seconds(),
        });

        (asset_a, asset_b)
    }

    /// Collect position's reward
    /// Params
    ///     - account The position's owner
    ///     - pool_address The address of pool
    ///     - position_index The position index
    ///     - rewarder_index The rewarder index
    ///     - recalculate If recalcuate the position's fee before collect.
    /// Return
    ///     - asset The reward asset
    public fun collect_rewarder(
        account: &signer,
        pool_address: address,
        position_index: u64,
        rewarder_index: u8,
        recalculate: bool,
        asset_addr: address
    ): FungibleAsset acquires Pool {
        check_position_authority(account, pool_address, position_index);

        let pool = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool);
        update_rewarder(pool);

        let position = if (recalculate) {
            let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
                pool,
                position_index
            );
            let rewards_growth_inside = get_reward_in_tick_range(pool, tick_lower, tick_upper);
            let position = table::borrow_mut(&mut pool.positions, position_index);
            update_position_rewarder(position, rewards_growth_inside);
            position
        } else {
            table::borrow_mut(&mut pool.positions, position_index)
        };

        // Get rewarder asset and reset owed rewarder.
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        let amount = &mut vector::borrow_mut(&mut position.rewarder_infos, (rewarder_index as u64)).amount_owed;
        let asset_metadata = object::address_to_object<Metadata>(asset_addr);
        let rewarder_asset = primary_fungible_store::withdraw(
            &pool_signer,
            asset_metadata,
            *amount
        );
        *amount = 0;

        event::emit(CollectRewardEvent {
            pool_address,
            user: signer::address_of(account),
            amount: fungible_asset::amount(&rewarder_asset),
            position_index: position_index,
            rewarder_index: rewarder_index,
            timestamp: timestamp::now_seconds(),
        });

        rewarder_asset
    }

    /// Update pool's position nft collection and token uri.
    /// Params:
    ///     - account The setter
    ///     - pool_address The pool address
    ///     - uri The new uri
    /// Returns:
    ///     None
    public fun update_pool_uri(
        account: &signer,
        pool_address: address,
        uri: String
    ) acquires Pool {
        assert!(!string::is_empty(&uri), EINVALID_POOL_URI);
        assert!(config::allow_set_position_nft_uri(account), ENOT_HAS_PRIVILEGE);
        let pool = borrow_global_mut<Pool>(pool_address);
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        position_nft::mutate_collection_uri(&pool_signer, pool.collection_name, uri);
        pool.uri = uri;
    }

    /// Swap output asset and flash loan resource.
    /// Params
    ///     - pool_address The address of pool
    ///     - swap_from The swap from address for record swap event
    ///     - partner_name The name of partner
    ///     - a2b The swap direction
    ///     - by_amount_in Express swap by amount in or amount out
    ///     - amount if by_amount_in is true it mean input amount else it mean output amount.
    ///     - sqrt_price_limit After swap the limit of pool's current sqrt price
    /// Returns
    ///     - asset_a The output of asset a, if a2b is true it zero
    ///     - asset_b The output of asset b, if a2b is false it zero
    ///     - receipt The flash loan resource
    public fun flash_swap(
        pool_address: address,
        swap_from: address,
        partner_name: String,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        sqrt_price_limit: u128,
    ): (FungibleAsset, FungibleAsset, FlashSwapReceipt) acquires Pool {
        let ref_fee_rate = partner::get_ref_fee_rate(partner_name);
        let protocol_fee_rate = config::get_protocol_fee_rate();

        let pool = borrow_global_mut<Pool>(pool_address);
        assert_status(pool);
        update_rewarder(pool);

        if (a2b) {
            assert!(
                pool.current_sqrt_price > sqrt_price_limit && sqrt_price_limit >= min_sqrt_price(),
                EWRONG_SQRT_PRICE_LIMIT
            );
        } else {
            assert!(
                pool.current_sqrt_price < sqrt_price_limit && sqrt_price_limit <= max_sqrt_price(),
                EWRONG_SQRT_PRICE_LIMIT
            );
        };

        let result = swap_in_pool(
            pool,
            a2b,
            by_amount_in,
            sqrt_price_limit,
            amount,
            protocol_fee_rate,
            ref_fee_rate
        );

        //event
        event::emit(AssetSwapEvent {
            atob: a2b,
            pool_address,
            swap_from,
            partner: partner_name,
            amount_in: result.amount_in,
            amount_out: result.amount_out,
            ref_amount: result.ref_fee_amount,
            fee_amount: result.fee_amount,
            vault_a_amount: pool.asset_a,
            vault_b_amount: pool.asset_b,
            timestamp: timestamp::now_seconds(),
            current_sqrt_price: pool.current_sqrt_price,
            current_tick: pool.current_tick_index,
        });

        let a_metadata = object::address_to_object<Metadata>(pool.asset_a_addr);
        let b_metadata = object::address_to_object<Metadata>(pool.asset_b_addr);
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        let (asset_a, asset_b) = if (a2b) {
            pool.asset_b = pool.asset_b - result.amount_out;
            (fungible_asset::zero(a_metadata), primary_fungible_store::withdraw(
                &pool_signer,
                b_metadata,
                result.amount_out
            ))
        } else {
            pool.asset_a = pool.asset_a - result.amount_out;
            (primary_fungible_store::withdraw(
                &pool_signer,
                a_metadata,
                result.amount_out
            ), fungible_asset::zero(b_metadata))
        };

        // Return the out asset and swap receipt
        (
            asset_a,
            asset_b,
            FlashSwapReceipt {
                pool_address,
                a2b,
                partner_name,
                pay_amount: result.amount_in + result.fee_amount,
                ref_fee_amount: result.ref_fee_amount
            }
        )
    }

    /// Repay for flash swap
    /// params
    ///     asset_a The asset a
    ///     asset_b The asset b
    /// returns
    ///     null
    public fun repay_flash_swap(
        asset_a: FungibleAsset,
        asset_b: FungibleAsset,
        receipt: FlashSwapReceipt
    ) acquires Pool {
        let FlashSwapReceipt {
            pool_address,
            a2b,
            partner_name,
            pay_amount,
            ref_fee_amount
        } = receipt;
        let pool = borrow_global_mut<Pool>(pool_address);
        if (a2b) {
            assert!(fungible_asset::amount(&asset_a) == pay_amount, EAMOUNT_INCORRECT);
            // send ref fee to partner
            if (ref_fee_amount > 0) {
                let ref_fee = fungible_asset::extract(&mut asset_a, ref_fee_amount);
                partner::receive_ref_fee(partner_name, ref_fee, pool.asset_a_addr);
            };
            primary_fungible_store::deposit(pool_address, asset_a);
            fungible_asset::destroy_zero(asset_b);
            pool.asset_a = pool.asset_a + pay_amount - ref_fee_amount;
        } else {
            assert!(fungible_asset::amount(&asset_b) == pay_amount, EAMOUNT_INCORRECT);
            // send ref fee to partner
            if (ref_fee_amount > 0) {
                let ref_fee = fungible_asset::extract(&mut asset_b, ref_fee_amount);
                partner::receive_ref_fee(partner_name, ref_fee, pool.asset_b_addr);
            };
            primary_fungible_store::deposit(pool_address, asset_b);
            fungible_asset::destroy_zero(asset_a);
            pool.asset_b = pool.asset_b + pay_amount - ref_fee_amount;
        }
    }

    /// Collect the protocol fee by the protocol_feee_claim_authority
    /// Params
    ///     - pool_address The address of pool
    /// Return
    ///     FA, FA
    public fun collect_protocol_fee(
        account: &signer,
        pool_address: address
    ): (FungibleAsset, FungibleAsset) acquires Pool {
        config::assert_protocol_fee_claim_authority(account);

        let pool_info = borrow_global_mut<Pool>(pool_address);
        //assert_status(pool_info);
        let amount_a = pool_info.fee_protocol_asset_a;
        let amount_b = pool_info.fee_protocol_asset_b;
        let pool_signer = account::create_signer_with_capability(&pool_info.signer_cap);

        let a_metadata = object::address_to_object<Metadata>(pool_info.asset_a_addr);
        let b_metadata = object::address_to_object<Metadata>(pool_info.asset_b_addr);
        let asset_a = primary_fungible_store::withdraw(&pool_signer, a_metadata, amount_a);
        let asset_b = primary_fungible_store::withdraw(&pool_signer, b_metadata, amount_b);

        pool_info.asset_a = pool_info.asset_a - amount_a;
        pool_info.asset_b = pool_info.asset_b - amount_b;

        pool_info.fee_protocol_asset_a = 0;
        pool_info.fee_protocol_asset_b = 0;
        event::emit(CollectProtocolFeeEvent {
            pool_address,
            amount_a,
            amount_b,
            timestamp: timestamp::now_seconds(),
        });
        (asset_a, asset_b)
    }

    /// Initialize the rewarder
    /// Params
    ///     - account The protocol authority signer
    ///     - pool_address The address of pool
    ///     - authority The rewarder authority.
    ///     - index: rewarder index.
    /// Return
    ///     null
    public fun initialize_rewarder(
        account: &signer,
        pool_address: address,
        authority: address,
        rewarder_index: u64,
        reward_asset_addr: address
    ) acquires Pool {
        config::assert_protocol_authority(account);
        let pool = borrow_global_mut<Pool>(pool_address);
        assert_status(pool);

        let rewarder_infos = &mut pool.rewarder_infos;
        let rewarder_metadata = object::address_to_object<Metadata>(reward_asset_addr);
        assert!(
            vector::length(rewarder_infos) == rewarder_index && rewarder_index < REWARDER_NUM,
            EINVALID_REWARD_INDEX
        );
        let rewarder = Rewarder {
            asset_address: reward_asset_addr,
            authority,
            pending_authority: DEFAULT_ADDRESS,
            emissions_per_second: 0,
            growth_global: 0,
        };
        primary_fungible_store::ensure_primary_store_exists(pool_address, rewarder_metadata);
        vector::push_back(rewarder_infos, rewarder);
    }

    /// Update the rewarder emission speed to start the rewarder to generate.
    /// Params
    ///     - account The rewarder authority
    ///     - pool_address The address of pool
    ///     - index: rewarder index.
    ///     - emissions_per_second: the asset number generated every second represented by X64.
    /// Return
    ///     null
    public fun update_emission(
        account: &signer,
        pool_address: address,
        rewarder_index: u8,
        emissions_per_second: u128,
        asset_addr: address
    ) acquires Pool {
        let pool = borrow_global_mut<Pool>(pool_address);
        assert_status(pool);
        update_rewarder(pool);

        let emission_per_day = full_math_u128::mul_shr(DAYS_IN_SECONDS, emissions_per_second, 64);
        assert!((rewarder_index as u64) < vector::length(&pool.rewarder_infos), EINVALID_REWARD_INDEX);
        let rewarder = vector::borrow_mut(&mut pool.rewarder_infos, (rewarder_index as u64));
        let account_addr = signer::address_of(account);
        assert!(account_addr == rewarder.authority, EREWARD_AUTH_ERROR);
        assert!(rewarder.asset_address == asset_addr, EREWARD_NOT_MATCH_WITH_INDEX);
        let asset_metadata = object::address_to_object<Metadata>(rewarder.asset_address);
        assert!(
            primary_fungible_store::balance(pool_address, asset_metadata) >= (emission_per_day as u64),
            EREWARD_AMOUNT_INSUFFICIENT
        );
        rewarder.emissions_per_second = emissions_per_second;
        event::emit(UpdateEmissionEvent {
            pool_address,
            rewarder_index,
            emissions_per_second,
            timestamp: timestamp::now_seconds(),
        })
    }

    /// Transfer the rewarder authority.
    /// Params
    ///     - account The rewarder authority
    ///     - pool_address The address of pool
    ///     - index
    ///     - new_authority
    /// Return
    ///     null
    public fun transfer_rewarder_authority(
        account: &signer,
        pool_address: address,
        rewarder_index: u8,
        new_authority: address
    ) acquires Pool {
        let old_authority = signer::address_of(account);
        let pool_info = borrow_global_mut<Pool>(pool_address);
        assert_status(pool_info);
        assert!((rewarder_index as u64) < vector::length(&pool_info.rewarder_infos), EINVALID_REWARD_INDEX);

        let rewarder = vector::borrow_mut(&mut pool_info.rewarder_infos, (rewarder_index as u64));
        assert!(rewarder.authority == old_authority, EREWARD_AUTH_ERROR);
        *&mut rewarder.pending_authority = new_authority;
        event::emit(TransferRewardAuthEvent {
            pool_address,
            rewarder_index,
            old_authority,
            new_authority,
            timestamp: timestamp::now_seconds(),
        })
    }

    /// Accept the rewarder authority.
    /// Params
    ///     - pool_address The address of pool
    ///     - index
    /// Return
    ///     null
    public fun accept_rewarder_authority(
        account: &signer,
        pool_address: address,
        rewarder_index: u8,
    ) acquires Pool {
        let new_authority = signer::address_of(account);
        let pool_info = borrow_global_mut<Pool>(pool_address);
        assert_status(pool_info);
        assert!((rewarder_index as u64) < vector::length(&pool_info.rewarder_infos), EINVALID_REWARD_INDEX);

        let rewarder = vector::borrow_mut(&mut pool_info.rewarder_infos, (rewarder_index as u64));
        assert!(rewarder.pending_authority == new_authority, EREWARD_AUTH_ERROR);
        *&mut rewarder.pending_authority = DEFAULT_ADDRESS;
        *&mut rewarder.authority = new_authority;
        event::emit(AcceptRewardAuthEvent {
            pool_address,
            rewarder_index,
            authority: new_authority,
            timestamp: timestamp::now_seconds(),
        })
    }

    /// Check the position ownership
    /// params
    ///     account The position owner
    ///     pool_address The pool account address
    ///     position_index The position index
    public fun check_position_authority(
        account: &signer,
        pool_address: address,
        position_index: u64
    ) acquires Pool {
        let pool = borrow_global<Pool>(pool_address);
        if (!table::contains(&pool.positions, position_index)) {
            abort EPOSITION_NOT_EXIST
        };
        let user_address = signer::address_of(account);
        let pool_address = account::get_signer_capability_address(&pool.signer_cap);
        assert!(
            position_nft::is_position_nft_owner(
                pool_address,
                user_address,
                pool.collection_name,
                pool.index,
                position_index
            ),
            EPOSITION_OWNER_ERROR
        );
    }

    // VIEW AND GETTER FUNCTIONS
    //============================================================================================================
    public fun fetch_ticks(
        pool_address: address, index: u64, offset: u64, limit: u64
    ): (u64, u64, vector<Tick>) acquires Pool {
        let pool = borrow_global_mut<Pool>(pool_address);
        let tick_spacing = pool.tick_spacing;
        let max_indexes_index = tick_indexes_max(tick_spacing);
        let search_indexes_index = index;
        let ticks = vector::empty<Tick>();
        let offset = offset;
        let count = 0;
        while ((search_indexes_index >= 0) && (search_indexes_index <= max_indexes_index)) {
            if (table::contains(&pool.tick_indexes, search_indexes_index)) {
                let indexes = table::borrow(&pool.tick_indexes, search_indexes_index);
                while ((offset >= 0) && (offset < TICK_INDEXES_LENGTH)) {
                    if (bit_vector::is_index_set(indexes, offset)) {
                        let tick_idx = i64::sub(
                            i64::from((TICK_INDEXES_LENGTH * search_indexes_index + offset) * tick_spacing),
                            tick_max(tick_spacing)
                        );
                        let tick = table::borrow(&pool.ticks, tick_idx);
                        count = count + 1;
                        vector::push_back(&mut ticks, *tick);
                        if (count == limit) {
                            return (search_indexes_index, offset, ticks)
                        }
                    };
                    offset = offset + 1;
                };
                offset = 0;
            };
            search_indexes_index = search_indexes_index + 1;
        };
        (search_indexes_index, offset, ticks)
    }

    public fun fetch_positions(
        pool_address: address, index: u64, limit: u64
    ): (u64, vector<Position>) acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        let positions = vector::empty<Position>();
        let count = 0;
        while (count < limit && index < pool_info.position_index) {
            if (table::contains(&pool_info.positions, index)) {
                let pos = table::borrow(&pool_info.positions, index);
                vector::push_back(&mut positions, *pos);
                count = count + 1;
            };
            index = index + 1;
        };
        (index, positions)
    }


    #[view]
    /// Calculate the swap result.
    /// Params
    ///     - pool_address The address of pool
    ///     - a2b The swap direction
    ///     - by_amount_in Express swap by amount in or amount out
    ///     - amount if by_amount_in is true it mean input amount else it mean output amount.
    /// Returns
    ///     - swap_result The swap result
    public fun calculate_swap_result(
        pool_address: address,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
    ): CalculatedSwapResult acquires Pool {
        let pool = borrow_global<Pool>(pool_address);
        let current_sqrt_price = pool.current_sqrt_price;
        let current_liquidity = pool.liquidity;
        let swap_result = default_swap_result();
        let remainer_amount = amount;
        let next_tick_idx = pool.current_tick_index;
        let (min_tick, max_tick) = (tick_min(pool.tick_spacing), tick_max(pool.tick_spacing));
        let result = CalculatedSwapResult {
            amount_in: 0,
            amount_out: 0,
            fee_amount: 0,
            fee_rate: pool.fee_rate,
            after_sqrt_price: pool.current_sqrt_price,
            is_exceed: false,
            step_results: vector::empty(),
        };
        while (remainer_amount > 0) {
            if (i64::gt(next_tick_idx, max_tick) || i64::lt(next_tick_idx, min_tick)) {
                result.is_exceed = true;
                break
            };
            let opt_next_tick = get_next_tick_for_swap(pool, next_tick_idx, a2b, max_tick);
            if (option::is_none(&opt_next_tick)) {
                result.is_exceed = true;
                break
            };
            let next_tick: Tick = option::destroy_some(opt_next_tick);
            let target_sqrt_price = next_tick.sqrt_price;
            let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
                current_sqrt_price,
                target_sqrt_price,
                current_liquidity,
                remainer_amount,
                pool.fee_rate,
                a2b,
                by_amount_in
            );

            if (amount_in != 0 || fee_amount != 0) {
                if (by_amount_in) {
                    remainer_amount = check_sub_remainer_amount(remainer_amount, amount_in);
                    remainer_amount = check_sub_remainer_amount(remainer_amount, fee_amount);
                } else {
                    remainer_amount = check_sub_remainer_amount(remainer_amount, amount_out);
                };
                // Update the swap result by step result
                update_swap_result(&mut swap_result, amount_in, amount_out, fee_amount);
            };
            vector::push_back(&mut result.step_results, SwapStepResult {
                current_sqrt_price,
                target_sqrt_price,
                current_liquidity,
                amount_in,
                amount_out,
                fee_amount,
                remainer_amount
            });
            if (next_sqrt_price == next_tick.sqrt_price) {
                current_sqrt_price = next_tick.sqrt_price;
                let liquidity_change = if (a2b) {
                    i128::neg(next_tick.liquidity_net)
                } else {
                    next_tick.liquidity_net
                };
                // update pool current liquidity
                if (!is_neg(liquidity_change)) {
                    let (pool_liquidity, overflowing) = math_u128::overflowing_add(
                        current_liquidity,
                        i128::abs_u128(liquidity_change)
                    );
                    if (overflowing) {
                        abort ELIQUIDITY_OVERFLOW
                    };
                    current_liquidity = pool_liquidity;
                } else {
                    let (pool_liquidity, overflowing) = math_u128::overflowing_sub(
                        current_liquidity,
                        i128::abs_u128(liquidity_change)
                    );
                    if (overflowing) {
                        abort ELIQUIDITY_UNDERFLOW
                    };
                    current_liquidity = pool_liquidity;
                };
            } else {
                current_sqrt_price = next_sqrt_price;
            };
            if (a2b) {
                next_tick_idx = i64::sub(next_tick.index, i64::from(1));
            } else {
                next_tick_idx = next_tick.index;
            };
        };

        result.amount_in = swap_result.amount_in;
        result.amount_out = swap_result.amount_out;
        result.fee_amount = swap_result.fee_amount;
        result.after_sqrt_price = current_sqrt_price;
        result
    }

    /// Get the swap pay amount
    public fun swap_pay_amount(receipt: &FlashSwapReceipt): u64 {
        receipt.pay_amount
    }

    /// Get the add liquidity receipt pay amounts.
    /// params
    ///     receipt
    /// return
    ///     amount_a The amount of asset a
    ///     amount_b The amount of asset b
    public fun add_liqudity_pay_amount(
        receipt: &AddLiquidityReceipt
    ): (u64, u64) {
        (receipt.amount_a, receipt.amount_b)
    }

    #[view]
    public fun get_tick_spacing(pool: address): u64 acquires Pool {
        if (!exists<Pool>(pool)) {
            abort EPOOL_NOT_EXISTS
        };
        let pool_info = borrow_global<Pool>(pool);
        pool_info.tick_spacing
    }

    #[view]
    public fun get_pool_liquidity(pool: address): u128 acquires Pool {
        if (!exists<Pool>(pool)) {
            abort EPOOL_NOT_EXISTS
        };
        let pool_info = borrow_global<Pool>(pool);
        pool_info.liquidity
    }

    #[view]
    public fun get_pool_index(pool: address): u64 acquires Pool {
        let pool_info = borrow_global<Pool>(pool);
        pool_info.index
    }

    #[view]
    public fun get_positions(
        pool_address: address,
        pos_indices: vector<u64>
    ): vector<Position> acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        let positions = vector::empty<Position>();
        vector::for_each(pos_indices, |pos_index| {
            if (table::contains(&pool_info.positions, pos_index)) {
                let pos = table::borrow(&pool_info.positions, pos_index);
                vector::push_back(&mut positions, *pos);
            }
        });
        positions
    }

    public fun get_position_tick_range_by_pool(
        pool_info: &Pool,
        position_index: u64
    ): (I64, I64) {
        if (!table::contains(&pool_info.positions, position_index)) {
            abort EPOSITION_NOT_EXIST
        };
        let position = table::borrow(&pool_info.positions, position_index);
        (position.tick_lower_index, position.tick_upper_index)
    }

    #[view]
    public fun get_position_tick_range(
        pool_address: address,
        position_index: u64
    ): (I64, I64) acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        if (!table::contains(&pool_info.positions, position_index)) {
            abort EPOSITION_NOT_EXIST
        };
        let position = table::borrow(&pool_info.positions, position_index);
        (position.tick_lower_index, position.tick_upper_index)
    }

    #[view]
    public fun get_rewarder_len(pool_address: address): u8 acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        let len = vector::length(&pool_info.rewarder_infos);
        return (len as u8)
    }

    #[view]
    /// calculate fees with multiple positions
    public fun calculate_positions_fees(
        pool_address: address,
        position_indices: vector<u64>,
    ): vector<PositionReward> acquires Pool {
        let pool = borrow_global_mut<Pool>(pool_address);
        let results = vector::empty<PositionReward>();

        vector::for_each(position_indices, |position_index| {
            if (table::contains(&pool.positions, position_index)) {
                let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
                    pool,
                    position_index
                );
                let (fee_growth_inside_a, fee_growth_inside_b) = get_fee_in_tick_range(
                    pool,
                    tick_lower,
                    tick_upper
                );
                let position = table::borrow(&pool.positions, position_index);
                let growth_delta_a = math_u128::wrapping_sub(fee_growth_inside_a, position.fee_growth_inside_a);
                let fee_delta_a = full_math_u128::mul_shr(position.liquidity, growth_delta_a, 64);
                let growth_delta_b = math_u128::wrapping_sub(fee_growth_inside_b, position.fee_growth_inside_b);
                let fee_delta_b = full_math_u128::mul_shr(position.liquidity, growth_delta_b, 64);
                let (fee_owed_a, is_overflow_a) = math_u64::overflowing_add(position.fee_owed_a, (fee_delta_a as u64));
                let (fee_owed_b, is_overflow_b) = math_u64::overflowing_add(position.fee_owed_b, (fee_delta_b as u64));
                assert!(!is_overflow_a, EFEE_OWNED_OVERFLOW);
                assert!(!is_overflow_b, EFEE_OWNED_OVERFLOW);

                let position_reward = PositionReward {
                    pool_address,
                    position_id: position_index,
                    fee_a: fee_owed_a,
                    fee_b: fee_owed_b,
                };
                vector::push_back(&mut results, position_reward);
            };
        });
        results
    }

    #[view]
    public fun get_pool_assets(pool_address: address): (address, address) acquires Pool {
        let pool_info = borrow_global<Pool>(pool_address);
        return (pool_info.asset_a_addr, pool_info.asset_b_addr)
    }

    #[view]
    public fun is_pool_exists(pool_addresses: vector<address>): vector<bool> {
        let results = vector::empty<bool>();

        vector::for_each(pool_addresses, |pool_address| {
            let is_exists = exists<Pool>(pool_address);
            vector::push_back(&mut results, is_exists);
        });

        results
    }

    #[view]
    /// Generate the token addresses for the positions.
    public fun generate_token_addresses(pool_address: address, position_ids: vector<u64>): vector<address> acquires Pool
    {
        let pool = borrow_global<Pool>(pool_address);
        let token_addresses = vector::empty<address>();

        vector::for_each(position_ids, |pos_ids|{
            let collection_name = position_nft::collection_name(
                pool.tick_spacing,
                pool.asset_a_addr,
                pool.asset_b_addr
            );
            let token_name = position_nft::position_name(pool.index, pos_ids);
            let token_address = token::create_token_address(
                &pool_address,
                &collection_name,
                &token_name
            );
            vector::push_back(&mut token_addresses, token_address);
        });
        token_addresses
    }

    #[view]
    public fun swap_routing(
        pool_addresses: vector<address>,
        a2b: bool,
        by_amount_in: bool,
        amount: u64
    ): (address, CalculatedSwapResult) acquires Pool {
        let (fa_a, fa_b) = get_pool_assets(*vector::borrow(&pool_addresses, 0));

        vector::for_each(pool_addresses, |addr| {
            let (a, b) = get_pool_assets(addr);
            assert!(a == fa_a && b == fa_b, EDIFFERENT_ASSET_TYPE);
        });

        let best_pool_address = @0x0;
        let best_amount_out = 0;
        let best_swap_result = CalculatedSwapResult {
            amount_out: 0, amount_in: 0, fee_amount: 0, fee_rate: 0, after_sqrt_price: 0, is_exceed: false, step_results: vector::empty(
            )
        };

        vector::for_each(pool_addresses, |pool_address| {
            let result = calculate_swap_result(pool_address, a2b, by_amount_in, amount);
            if (result.amount_out > best_amount_out && result.is_exceed == false) {
                best_pool_address = pool_address;
                best_swap_result = result;
            };
        });
        (best_pool_address, best_swap_result)
    }

    // PRIVATE FUNCTIONS
    //============================================================================================================
    fun assert_status(pool: &Pool) {
        config::assert_protocol_status();
        if (pool.is_pause) {
            abort EPOOL_IS_PAUDED
        };
    }

    /// Get the tick indexes index
    fun tick_indexes_index(tick: I64, tick_spacing: u64): u64 {
        let num = i64::sub(tick, tick_min(tick_spacing));
        if (i64::is_neg(num)) {
            abort EINVALID_TICK
        };
        let denom = tick_spacing * TICK_INDEXES_LENGTH;
        i64::as_u64(num) / denom
    }

    /// Get the tick store position. the tick indexes index and the offset in tick indexes.
    /// Returns
    ///     index The index of tick indexes
    ///     offset The offset of tick in tick indexes
    fun tick_position(tick: I64, tick_spacing: u64): (u64, u64) {
        let index = tick_indexes_index(tick, tick_spacing);
        let u_tick = i64::as_u64(i64::add(tick, tick_max(tick_spacing)));
        let offset = (u_tick - (index * tick_spacing * TICK_INDEXES_LENGTH)) / tick_spacing;
        (index, offset)
    }

    /// Get the tick offset in tick indexes
    /// Returns
    ///     offset The offset of tick in tick indexes
    fun tick_offset(indexes_index: u64, tick_spacing: u64, tick: I64): u64 {
        let u_tick = i64::as_u64(i64::add(tick, tick_max(tick_spacing)));
        (u_tick - (indexes_index * tick_spacing * TICK_INDEXES_LENGTH)) / tick_spacing
    }

    /// Get the max tick indexes index
    fun tick_indexes_max(tick_spacing: u64): u64 {
        ((tick_math::tick_bound() * 2) / (tick_spacing * TICK_INDEXES_LENGTH)) + 1
        //let max_tick = tick_max(tick_spacing);
        //tick_indexes_index(max_tick, tick_spacing)
    }

    // Get the min bound of tick with tick spacing
    fun tick_min(tick_spacing: u64): I64 {
        let min_tick = tick_math::min_tick();
        let mod = i64::mod(min_tick, i64::from(tick_spacing));
        i64::sub(min_tick, mod)
    }

    // Get the max bound of tick with tick spacing
    fun tick_max(tick_spacing: u64): I64 {
        let max_tick = tick_math::max_tick();
        let mod = i64::mod(max_tick, i64::from(tick_spacing));
        i64::sub(max_tick, mod)
    }

    fun get_fee_in_tick_range(
        pool: &Pool,
        tick_lower_index: I64,
        tick_upper_index: I64
    ): (u128, u128) {
        let op_tick_lower = borrow_tick(pool, tick_lower_index);
        let op_tick_upper = borrow_tick(pool, tick_upper_index);
        let current_tick_index = pool.current_tick_index;
        let (fee_growth_below_a, fee_growth_below_b) = if (is_none<Tick>(&op_tick_lower)) {
            (pool.fee_growth_global_a, pool.fee_growth_global_b)
        }else {
            let tick_lower = option::borrow<Tick>(&op_tick_lower);
            if (i64::lt(current_tick_index, tick_lower_index)) {
                (math_u128::wrapping_sub(pool.fee_growth_global_a, tick_lower.fee_growth_outside_a),
                    math_u128::wrapping_sub(pool.fee_growth_global_b, tick_lower.fee_growth_outside_b))
            }else {
                (tick_lower.fee_growth_outside_a, tick_lower.fee_growth_outside_b)
            }
        };
        let (fee_growth_above_a, fee_growth_above_b) = if (is_none<Tick>(&op_tick_upper)) {
            (0, 0)
        }else {
            let tick_upper = option::borrow<Tick>(&op_tick_upper);
            if (i64::lt(current_tick_index, tick_upper_index)) {
                (tick_upper.fee_growth_outside_a, tick_upper.fee_growth_outside_b)
            }else {
                (math_u128::wrapping_sub(pool.fee_growth_global_a, tick_upper.fee_growth_outside_a),
                    math_u128::wrapping_sub(pool.fee_growth_global_b, tick_upper.fee_growth_outside_b))
            }
        };
        (
            math_u128::wrapping_sub(
                math_u128::wrapping_sub(pool.fee_growth_global_a, fee_growth_below_a),
                fee_growth_above_a
            ),
            math_u128::wrapping_sub(
                math_u128::wrapping_sub(pool.fee_growth_global_b, fee_growth_below_b),
                fee_growth_above_b
            )
        )
    }

    // Add liquidity in pool
    fun add_liquidity_internal(
        pool_address: address,
        position_index: u64,
        by_amount: bool,
        liquidity: u128,
        amount: u64,
        fix_amount_a: bool
    ): AddLiquidityReceipt acquires Pool {
        // 1. Check position and pool
        let pool = borrow_global_mut<Pool>(pool_address);
        assert_status(pool);

        // 2. update rewarder
        update_rewarder(pool);

        // 3. Update position's fee and rewarder
        let (tick_lower, tick_upper) = get_position_tick_range_by_pool(
            pool,
            position_index
        );
        let (fee_growth_inside_a, fee_growth_inside_b) = get_fee_in_tick_range(
            pool,
            tick_lower,
            tick_upper
        );
        let rewards_growth_inside = get_reward_in_tick_range(pool, tick_lower, tick_upper);
        let position = table::borrow_mut(&mut pool.positions, position_index);
        update_position_fee_and_reward(position, fee_growth_inside_a, fee_growth_inside_b, rewards_growth_inside);

        // 4. Calculate liquidity and amounts
        let (increase_liquidity, amount_a, amount_b) = if (by_amount) {
            clmm_math::get_liquidity_from_amount(
                tick_lower,
                tick_upper,
                pool.current_tick_index,
                pool.current_sqrt_price,
                amount,
                fix_amount_a,
            )
        } else {
            let (amount_a, amount_b) = clmm_math::get_amount_by_liquidity(
                tick_lower,
                tick_upper,
                pool.current_tick_index,
                pool.current_sqrt_price,
                liquidity,
                true
            );
            (liquidity, amount_a, amount_b)
        };

        // 5. Update position, pool ticks's liquidity
        update_position_liquidity(position, increase_liquidity, true);
        let new_liquidity = position.liquidity;
        upsert_tick_by_liquidity(pool, tick_lower, increase_liquidity, true, false);
        upsert_tick_by_liquidity(pool, tick_upper, increase_liquidity, true, true);
        let (after_liquidity, is_overflow) = if (i64::gte(pool.current_tick_index, tick_lower) && i64::lt(
            pool.current_tick_index,
            tick_upper
        )) {
            math_u128::overflowing_add(pool.liquidity, increase_liquidity)
        } else {
            (pool.liquidity, false)
        };
        assert!(!is_overflow, ELIQUIDITY_OVERFLOW);
        pool.liquidity = after_liquidity;

        // Update the Position NFT's liquidity property
        let collection_name = position_nft::collection_name(pool.tick_spacing, pool.asset_a_addr, pool.asset_b_addr);
        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);

        position_nft::update_liquidity(
            &pool_signer,
            collection_name,
            pool.index,
            position_index,
            new_liquidity
        );

        event::emit(AddLiquidityEvent {
            pool_address,
            tick_lower,
            tick_upper,
            liquidity: increase_liquidity,
            amount_a,
            amount_b,
            position_index: position_index,
            timestamp: timestamp::now_seconds(),
        });

        AddLiquidityReceipt {
            pool_address,
            amount_a,
            amount_b
        }
    }

    /// Swap in pool
    fun swap_in_pool(
        pool: &mut Pool,
        a2b: bool,
        by_amount_in: bool,
        sqrt_price_limit: u128,
        amount: u64,
        protocol_fee_rate: u64,
        ref_fee_rate: u64,
    ): SwapResult {
        let swap_result = default_swap_result();
        let remainer_amount = amount;
        let next_tick_idx = pool.current_tick_index;
        let (min_tick, max_tick) = (tick_min(pool.tick_spacing), tick_max(pool.tick_spacing));
        while (remainer_amount > 0 && pool.current_sqrt_price != sqrt_price_limit) {
            if (i64::gt(next_tick_idx, max_tick) || i64::lt(next_tick_idx, min_tick)) {
                abort ENOT_ENOUGH_LIQUIDITY
            };
            let opt_next_tick = get_next_tick_for_swap(pool, next_tick_idx, a2b, max_tick);
            if (option::is_none(&opt_next_tick)) {
                abort ENOT_ENOUGH_LIQUIDITY
            };
            let next_tick: Tick = option::destroy_some(opt_next_tick);

            let target_sqrt_price = if (a2b) {
                math_u128::max(sqrt_price_limit, next_tick.sqrt_price)
            } else {
                math_u128::min(sqrt_price_limit, next_tick.sqrt_price)
            };
            let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
                pool.current_sqrt_price,
                target_sqrt_price,
                pool.liquidity,
                remainer_amount,
                pool.fee_rate,
                a2b,
                by_amount_in
            );
            if (amount_in != 0 || fee_amount != 0) {
                if (by_amount_in) {
                    remainer_amount = check_sub_remainer_amount(remainer_amount, amount_in);
                    remainer_amount = check_sub_remainer_amount(remainer_amount, fee_amount);
                } else {
                    remainer_amount = check_sub_remainer_amount(remainer_amount, amount_out);
                };

                // Update the swap result by step result
                update_swap_result(&mut swap_result, amount_in, amount_out, fee_amount);

                // Update the pool's fee by step result
                swap_result.ref_fee_amount = update_pool_fee(pool, fee_amount, ref_fee_rate, protocol_fee_rate, a2b);
            };
            if (next_sqrt_price == next_tick.sqrt_price) {
                pool.current_sqrt_price = next_tick.sqrt_price;
                pool.current_tick_index = if (a2b) {
                    i64::sub(next_tick.index, i64::from(1))
                } else {
                    next_tick.index
                };
                // tick cross, update pool's liqudity and ticks's fee_growth_outside_[ab]
                cross_tick_and_update_liquidity(pool, next_tick.index, a2b);
            } else {
                pool.current_sqrt_price = next_sqrt_price;
                pool.current_tick_index = tick_math::get_tick_at_sqrt_price(next_sqrt_price);
            };
            if (a2b) {
                next_tick_idx = i64::sub(next_tick.index, i64::from(1));
            } else {
                next_tick_idx = next_tick.index;
            };
        };

        swap_result
    }

    /// Update the rewarder.
    /// Rewarder update is needed when swap, add liquidity, remove liquidity, collect rewarder and update emission.
    fun update_rewarder(
        pool: &mut Pool,
    ) {
        let current_time = timestamp::now_seconds();
        let last_time = pool.rewarder_last_updated_time;
        pool.rewarder_last_updated_time = current_time;
        assert!(last_time <= current_time, EINVALID_TIME);
        if (pool.liquidity == 0 || current_time == last_time) {
            return
        };
        let time_delta = (current_time - last_time);
        let idx = 0;
        while (idx < vector::length(&pool.rewarder_infos)) {
            let emission = vector::borrow(&pool.rewarder_infos, idx).emissions_per_second;
            let rewarder_grothw_delta = full_math_u128::mul_div_floor(
                (time_delta as u128),
                emission,
                pool.liquidity
            );
            let last_growth_global = vector::borrow(&pool.rewarder_infos, idx).growth_global;
            *&mut vector::borrow_mut(
                &mut pool.rewarder_infos,
                idx
            ).growth_global = last_growth_global + rewarder_grothw_delta;
            idx = idx + 1;
        }
    }

    /// Update the swap result
    fun update_swap_result(result: &mut SwapResult, amount_in: u64, amount_out: u64, fee_amount: u64) {
        let (result_amount_in, overflowing) = math_u64::overflowing_add(result.amount_in, amount_in);
        if (overflowing) {
            abort ESWAP_AMOUNT_IN_OVERFLOW
        };
        let (result_amount_out, overflowing) = math_u64::overflowing_add(result.amount_out, amount_out);
        if (overflowing) {
            abort ESWAP_AMOUNT_OUT_OVERFLOW
        };
        let (result_fee_amount, overflowing) = math_u64::overflowing_add(result.fee_amount, fee_amount);
        if (overflowing) {
            abort ESWAP_FEE_AMOUNT_OVERFLOW
        };
        result.amount_out = result_amount_out;
        result.amount_in = result_amount_in;
        result.fee_amount = result_fee_amount;
    }

    /// Update the pool's protocol_fee and fee_growth_global_[a/b]
    fun update_pool_fee(
        pool: &mut Pool,
        fee_amount: u64,
        ref_rate: u64,
        protocol_fee_rate: u64,
        a2b: bool
    ): u64 {
        let protocol_fee = full_math_u64::mul_div_ceil(fee_amount, protocol_fee_rate, PROTOCOL_FEE_DENOMNINATOR);
        let liquidity_fee = fee_amount - protocol_fee;
        let ref_fee = if (ref_rate == 0) {
            0
        }else {
            full_math_u64::mul_div_floor(protocol_fee, ref_rate, PROTOCOL_FEE_DENOMNINATOR)
        };
        protocol_fee = protocol_fee - ref_fee;
        if (a2b) {
            pool.fee_protocol_asset_a = math_u64::wrapping_add(pool.fee_protocol_asset_a, protocol_fee);
        } else {
            pool.fee_protocol_asset_b = math_u64::wrapping_add(pool.fee_protocol_asset_b, protocol_fee);
        };
        if (liquidity_fee == 0 || pool.liquidity == 0) {
            return ref_fee
        };
        let growth_fee = ((liquidity_fee as u128) << 64) / pool.liquidity;
        if (a2b) {
            pool.fee_growth_global_a = math_u128::wrapping_add(pool.fee_growth_global_a, growth_fee);
        } else {
            pool.fee_growth_global_b = math_u128::wrapping_add(pool.fee_growth_global_b, growth_fee);
        };
        ref_fee
    }

    /// Cross the tick
    fun cross_tick_and_update_liquidity(
        pool: &mut Pool,
        tick: I64,
        a2b: bool
    ) {
        let tick = table::borrow_mut(&mut pool.ticks, tick);
        let liquidity_change = if (a2b) {
            i128::neg(tick.liquidity_net)
        } else {
            tick.liquidity_net
        };

        // update pool liquidity
        if (!is_neg(liquidity_change)) {
            let (pool_liquidity, overflowing) = math_u128::overflowing_add(
                pool.liquidity,
                i128::abs_u128(liquidity_change)
            );
            if (overflowing) {
                abort ELIQUIDITY_OVERFLOW
            };
            pool.liquidity = pool_liquidity;
        } else {
            let (pool_liquidity, overflowing) = math_u128::overflowing_sub(
                pool.liquidity,
                i128::abs_u128(liquidity_change)
            );
            if (overflowing) {
                abort ELIQUIDITY_UNDERFLOW
            };
            pool.liquidity = pool_liquidity;
        };

        // update tick's fee_growth_outside_[ab]
        tick.fee_growth_outside_a =
            math_u128::wrapping_sub(pool.fee_growth_global_a, tick.fee_growth_outside_a);
        tick.fee_growth_outside_b =
            math_u128::wrapping_sub(pool.fee_growth_global_b, tick.fee_growth_outside_b);
        // update tick's rewarder
        let idx = 0;
        while (idx < vector::length(&pool.rewarder_infos)) {
            let growth_global = vector::borrow(&pool.rewarder_infos, idx).growth_global;
            let rewarder_growth_outside = *vector::borrow(&tick.rewarders_growth_outside, idx);
            *vector::borrow_mut(&mut tick.rewarders_growth_outside, idx) = math_u128::wrapping_sub(growth_global,
                rewarder_growth_outside);
            idx = idx + 1;
        }
    }

    fun check_sub_remainer_amount(remainer_amount: u64, amount: u64): u64 {
        let (r_amount, overflowing) = math_u64::overflowing_sub(remainer_amount, amount);
        if (overflowing) {
            abort EREMAINER_AMOUNT_UNDERFLOW
        };
        r_amount
    }

    /// Get the next tick for swap
    fun get_next_tick_for_swap(
        pool: &Pool,
        tick_idx: I64,
        a2b: bool,
        max_tick: I64
    ): Option<Tick> {
        let tick_spacing = pool.tick_spacing;
        let max_indexes_index = tick_indexes_max(tick_spacing);
        let (search_indexes_index, offset) = tick_position(tick_idx, tick_spacing);
        if (!a2b) {
            offset = offset + 1;
        };
        while ((search_indexes_index >= 0) && (search_indexes_index <= max_indexes_index)) {
            if (table::contains(&pool.tick_indexes, search_indexes_index)) {
                let indexes = table::borrow(&pool.tick_indexes, search_indexes_index);
                while ((offset >= 0) && (offset < TICK_INDEXES_LENGTH)) {
                    if (bit_vector::is_index_set(indexes, offset)) {
                        let tick_idx = i64::sub(
                            i64::from((TICK_INDEXES_LENGTH * search_indexes_index + offset) * tick_spacing),
                            max_tick
                        );
                        let tick = table::borrow(&pool.ticks, tick_idx);
                        return option::some(*tick)
                    };
                    if (a2b) {
                        if (offset == 0) {
                            break
                        } else {
                            offset = offset - 1;
                        };
                    } else {
                        offset = offset + 1;
                    }
                };
            };
            if (a2b) {
                if (search_indexes_index == 0) {
                    return option::none<Tick>()
                };
                offset = TICK_INDEXES_LENGTH - 1;
                search_indexes_index = search_indexes_index - 1;
            } else {
                offset = 0;
                search_indexes_index = search_indexes_index + 1;
            }
        };

        option::none<Tick>()
    }

    // Update the tick by delta liquidity
    fun upsert_tick_by_liquidity(
        pool: &mut Pool,
        tick_idx: I64,
        delta_liquidity: u128,
        is_increase: bool,
        is_upper_tick: bool
    ) {
        let tick = borrow_mut_tick_with_default(&mut pool.tick_indexes, &mut pool.ticks, pool.tick_spacing, tick_idx);
        if (delta_liquidity == 0) {
            return
        };
        let (liquidity_gross, overflow) = if (is_increase) {
            math_u128::overflowing_add(tick.liquidity_gross, delta_liquidity)
        } else {
            math_u128::overflowing_sub(tick.liquidity_gross, delta_liquidity)
        };
        if (overflow) {
            abort ELIQUIDITY_OVERFLOW
        };

        // If liquidity gross is zero, remove this tick from pool
        if (liquidity_gross == 0) {
            remove_tick(pool, tick_idx);
            return
        };

        let (fee_growth_outside_a, fee_growth_outside_b, reward_growth_outside) = if (tick.liquidity_gross == 0) {
            if (i64::gte(pool.current_tick_index, tick_idx)) {
                (pool.fee_growth_global_a, pool.fee_growth_global_b, rewarder_growth_globals(pool.rewarder_infos,
                ))
            } else {
                (0u128, 0u128, vector[0, 0, 0])
            }
        } else {
            (tick.fee_growth_outside_a, tick.fee_growth_outside_b, tick.rewarders_growth_outside)
        };
        let (liquidity_net, overflow) = if (is_increase) {
            if (is_upper_tick) {
                i128::overflowing_sub(tick.liquidity_net, i128::from(delta_liquidity))
            } else {
                i128::overflowing_add(tick.liquidity_net, i128::from(delta_liquidity))
            }
        } else {
            if (is_upper_tick) {
                i128::overflowing_add(tick.liquidity_net, i128::from(delta_liquidity))
            } else {
                i128::overflowing_sub(tick.liquidity_net, i128::from(delta_liquidity))
            }
        };
        if (overflow) {
            abort ELIQUIDITY_OVERFLOW
        };
        tick.liquidity_gross = liquidity_gross;
        tick.liquidity_net = liquidity_net;
        tick.fee_growth_outside_a = fee_growth_outside_a;
        tick.fee_growth_outside_b = fee_growth_outside_b;
        tick.rewarders_growth_outside = reward_growth_outside;
    }

    fun default_tick(tick_idx: I64): Tick {
        Tick {
            index: tick_idx,
            sqrt_price: tick_math::get_sqrt_price_at_tick(tick_idx),
            liquidity_net: i128::from(0),
            liquidity_gross: 0,
            fee_growth_outside_a: 0,
            fee_growth_outside_b: 0,
            rewarders_growth_outside: vector<u128>[0, 0, 0],
        }
    }

    fun borrow_tick(pool: &Pool, tick_idx: I64): Option<Tick> {
        let (index, _offset) = tick_position(tick_idx, pool.tick_spacing);
        if (!table::contains(&pool.tick_indexes, index)) {
            return option::none<Tick>()
        };
        if (!table::contains(&pool.ticks, tick_idx)) {
            return option::none<Tick>()
        };
        let tick = table::borrow(&pool.ticks, tick_idx);
        option::some(*tick)
    }


    fun default_swap_result(): SwapResult {
        SwapResult {
            amount_in: 0,
            amount_out: 0,
            fee_amount: 0,
            ref_fee_amount: 0,
        }
    }

    // Add tick only for test store
    fun borrow_mut_tick_with_default(
        tick_indexes: &mut Table<u64, BitVector>,
        ticks: &mut Table<I64, Tick>,
        tick_spacing: u64,
        tick_idx: I64,
    ): &mut Tick {
        let (index, offset) = tick_position(tick_idx, tick_spacing);

        // If tick indexes not eixst add it.
        if (!table::contains(tick_indexes, index)) {
            table::add(tick_indexes, index, bit_vector::new(TICK_INDEXES_LENGTH));
        };

        let indexes = table::borrow_mut(tick_indexes, index);
        bit_vector::set(indexes, offset);

        if (!table::contains(ticks, tick_idx)) {
            table::borrow_mut_with_default(ticks, tick_idx, default_tick(tick_idx))
        } else {
            table::borrow_mut(ticks, tick_idx)
        }
    }

    // Remove tick from pool
    fun remove_tick(
        pool: &mut Pool,
        tick_idx: I64
    ) {
        let (index, offset) = tick_position(tick_idx, pool.tick_spacing);
        if (!table::contains(&pool.tick_indexes, index)) {
            abort ETICK_INDEXES_NOT_SET
        };
        let indexes = table::borrow_mut(&mut pool.tick_indexes, index);
        bit_vector::unset(indexes, offset);
        if (!table::contains(&pool.ticks, tick_idx)) {
            abort ETICK_NOT_FOUND
        };
        table::remove(&mut pool.ticks, tick_idx);
    }

    fun rewarder_growth_globals(rewarders: vector<Rewarder>): vector<u128> {
        let res = vector[0, 0, 0];
        let idx = 0;
        while (idx < vector::length(&rewarders)) {
            *vector::borrow_mut(&mut res, idx) = vector::borrow(&rewarders, idx).growth_global;
            idx = idx + 1;
        };
        res
    }

    fun get_reward_in_tick_range(
        pool: &Pool,
        tick_lower_index: I64,
        tick_upper_index: I64
    ): vector<u128> {
        let op_tick_lower = borrow_tick(pool, tick_lower_index);
        let op_tick_upper = borrow_tick(pool, tick_upper_index);
        let current_tick_index = pool.current_tick_index;
        let res = vector::empty<u128>();
        let idx = 0;
        while (idx < vector::length(&pool.rewarder_infos)) {
            let growth_blobal = vector::borrow(&pool.rewarder_infos, idx).growth_global;
            let rewarder_growths_below = if (is_none<Tick>(&op_tick_lower)) {
                growth_blobal
            }else {
                let tick_lower = option::borrow<Tick>(&op_tick_lower);
                if (i64::lt(current_tick_index, tick_lower_index)) {
                    math_u128::wrapping_sub(growth_blobal, *vector::borrow(&tick_lower.rewarders_growth_outside, idx))
                }else {
                    *vector::borrow(&tick_lower.rewarders_growth_outside, idx)
                }
            };
            let rewarder_growths_above = if (is_none<Tick>(&op_tick_upper)) {
                0
            }else {
                let tick_upper = option::borrow<Tick>(&op_tick_upper);
                if (i64::lt(current_tick_index, tick_upper_index)) {
                    *vector::borrow(&tick_upper.rewarders_growth_outside, idx)
                }else {
                    math_u128::wrapping_sub(growth_blobal, *vector::borrow(&tick_upper.rewarders_growth_outside, idx))
                }
            };
            let rewarder_inside = math_u128::wrapping_sub(
                math_u128::wrapping_sub(growth_blobal, rewarder_growths_below),
                rewarder_growths_above
            );
            vector::push_back(&mut res, rewarder_inside);
            idx = idx + 1;
        };
        res
    }


    fun new_empty_position(
        pool_address: address,
        tick_lower_index: I64,
        tick_upper_index: I64,
        index: u64
    ): Position {
        Position {
            pool: pool_address,
            index,
            liquidity: 0,
            tick_lower_index,
            tick_upper_index,
            fee_growth_inside_a: 0,
            fee_owed_a: 0,
            fee_growth_inside_b: 0,
            fee_owed_b: 0,
            rewarder_infos: vector[
                PositionRewarder {
                    growth_inside: 0,
                    amount_owed: 0,
                },
                PositionRewarder {
                    growth_inside: 0,
                    amount_owed: 0,
                },
                PositionRewarder {
                    growth_inside: 0,
                    amount_owed: 0,
                },
            ],
        }
    }

    fun update_position_rewarder(position: &mut Position, rewarder_growths_inside: vector<u128>) {
        let idx = 0;
        while (idx < vector::length(&rewarder_growths_inside)) {
            let current_growth = *vector::borrow(&rewarder_growths_inside, idx);
            let rewarder = vector::borrow_mut(&mut position.rewarder_infos, idx);
            let growth_delta = math_u128::wrapping_sub(current_growth, rewarder.growth_inside);
            let amount_owed_delta = full_math_u128::mul_shr(growth_delta, position.liquidity, 64);
            *&mut rewarder.growth_inside = current_growth;
            let (latest_owned, is_overflow) = math_u64::overflowing_add(
                rewarder.amount_owed,
                (amount_owed_delta as u64)
            );
            assert!(!is_overflow, EREWARDER_OWNED_OVERFLOW);
            *&mut rewarder.amount_owed = latest_owned;
            idx = idx + 1;
        }
    }

    fun update_position_fee(position: &mut Position, fee_growth_inside_a: u128, fee_growth_inside_b: u128) {
        let growth_delta_a = math_u128::wrapping_sub(fee_growth_inside_a, position.fee_growth_inside_a);
        let fee_delta_a = full_math_u128::mul_shr(position.liquidity, growth_delta_a, 64);
        let growth_delta_b = math_u128::wrapping_sub(fee_growth_inside_b, position.fee_growth_inside_b);
        let fee_delta_b = full_math_u128::mul_shr(position.liquidity, growth_delta_b, 64);
        let (fee_owed_a, is_overflow_a) = math_u64::overflowing_add(position.fee_owed_a, (fee_delta_a as u64));
        let (fee_owed_b, is_overflow_b) = math_u64::overflowing_add(position.fee_owed_b, (fee_delta_b as u64));
        assert!(!is_overflow_a, EFEE_OWNED_OVERFLOW);
        assert!(!is_overflow_b, EFEE_OWNED_OVERFLOW);

        position.fee_owed_a = fee_owed_a;
        position.fee_owed_b = fee_owed_b;
        position.fee_growth_inside_a = fee_growth_inside_a;
        position.fee_growth_inside_b = fee_growth_inside_b;
    }

    fun update_position_liquidity(
        position: &mut Position,
        delta_liquidity: u128,
        is_increase: bool
    ) {
        if (delta_liquidity == 0) {
            return
        };
        let (liquidity, is_overflow) = {
            if (is_increase) {
                math_u128::overflowing_add(position.liquidity, delta_liquidity)
            }else {
                math_u128::overflowing_sub(position.liquidity, delta_liquidity)
            }
        };
        assert!(!is_overflow, EINVALID_DELTA_LIQUIDITY);
        position.liquidity = liquidity;
    }

    fun update_position_fee_and_reward(
        position: &mut Position,
        fee_growth_inside_a: u128,
        fee_growth_inside_b: u128,
        rewards_growth_inside: vector<u128>,
    ) {
        update_position_fee(position, fee_growth_inside_a, fee_growth_inside_b);
        update_position_rewarder(position, rewards_growth_inside);
    }

    // TESTS
    //============================================================================================================
    // Add more test
    #[test_only]
    struct Assets has key {
        asset_a_addr: address,
        asset_b_addr: address,
    }

    #[test_only]
    fun new_pool_for_testing(
        clmm: &signer,
        tick_spacing: u64,
        fee_rate: u64,
        init_sqrt_price: u128,
    ): address {
        let (asset_a_name, asset_b_name) = (utf8(b"Token A"), utf8(b"Token b"));
        let asset_a = setup_fungible_assets(clmm, asset_a_name, utf8(b"TA"));
        let asset_b = setup_fungible_assets(clmm, asset_b_name, utf8(b"TB"));

        let (pool_account, pool_cap) = account::create_resource_account(clmm, b"TestPool");
        move_to(
            clmm,
            Assets {
                asset_a_addr: asset_a,
                asset_b_addr: asset_b
            }
        );
        config::initialize(clmm);
        config::init_clmm_acl(clmm);
        fee_tier::initialize(clmm);
        partner::initialize(clmm);
        fee_tier::add_fee_tier(clmm, tick_spacing, fee_rate);
        new(
            &pool_account,
            tick_spacing,
            init_sqrt_price,
            1,
            string::utf8(b"CA"),
            pool_cap,
            asset_a,
            asset_b
        );
        signer::address_of(&pool_account)
    }

    #[test_only]
    fun add_tick_for_testing(
        pool: &mut Pool,
        tick_idx: I64,
        liquidity_net: I128,
        liquidity_gross: u128
    ) {
        let tick_spacing = pool.tick_spacing;
        let (index, offset) = tick_position(tick_idx, tick_spacing);

        // If tick indexes not eixst add it.
        if (!table::contains(&pool.tick_indexes, index)) {
            table::add(&mut pool.tick_indexes, index, bit_vector::new(TICK_INDEXES_LENGTH));
        };

        let indexes = table::borrow_mut(&mut pool.tick_indexes, index);
        bit_vector::set(indexes, offset);

        table::upsert(&mut pool.ticks, tick_idx, Tick {
            index: tick_idx,
            sqrt_price: tick_math::get_sqrt_price_at_tick(tick_idx),
            liquidity_net,
            liquidity_gross,
            fee_growth_outside_a: 0,
            fee_growth_outside_b: 0,
            rewarders_growth_outside: vector<u128>[0, 0, 0],
        })
    }

    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm
    )]
    fun test_new_pool(
        apt: &signer,
        clmm: signer
    ) acquires Pool {
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);

        account::create_account_for_test(signer::address_of(&clmm));
        let pool_address = new_pool_for_testing(&clmm, 50, 2000, 1000000000000);
        let pool = borrow_global<Pool>(pool_address);
        assert!(pool.tick_spacing == 50, 1);
        assert!(pool.current_sqrt_price == 1000000000000, 1);
        assert!(pool.fee_rate == 2000, 1);
    }

    #[test(
        apt = @0x1,
        clmm= @dexlyn_clmm
    )]
    #[expected_failure]
    fun test_new_pool_with_same_asset(
        apt: &signer,
        clmm: &signer,
    ): address {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);

        let (asset_a_name, asset_b_name) = (utf8(b"Token A"), utf8(b"Token A"));
        let asset_a = setup_fungible_assets(clmm, asset_a_name, utf8(b"TA"));
        let asset_b = setup_fungible_assets(clmm, asset_b_name, utf8(b"TA"));

        let (pool_account, pool_cap) = account::create_resource_account(clmm, b"TestPool");
        let (tick_spacing, fee_rate, init_sqrt_price) =
            (60, 2000, tick_math::get_sqrt_price_at_tick(i64::from(0)));
        config::initialize(clmm);
        fee_tier::initialize(clmm);
        partner::initialize(clmm);
        fee_tier::add_fee_tier(clmm, tick_spacing, fee_rate);
        new(
            &pool_account,
            tick_spacing,
            init_sqrt_price,
            1,
            string::utf8(b"CA"),
            pool_cap,
            asset_a,
            asset_b
        );
        signer::address_of(&pool_account)
    }

    #[test_only]
    struct PositionItem has store, drop, copy {
        liquidity: u128,
        tick_lower: I64,
        tick_upper: I64,
        amount_a: u64,
        amount_b: u64
    }

    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm,
        owner = @0x123456
    )]
    fun test_add_liquidity(
        apt: &signer,
        clmm: &signer,
        owner: &signer,
    ) acquires Pool, Assets {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(owner));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);
        // The current tick is -41957
        let (tick_spacing, fee_rate, init_sqrt_price) = (50, 2000, 2264044300179098811);

        let items = vector::empty<PositionItem>();
        vector::push_back(&mut items, PositionItem {
            liquidity: 2317299527,
            tick_lower: i64::neg_from(33450),
            tick_upper: i64::neg_from(33350),
            amount_a: 61541268,
            amount_b: 0
        });
        vector::push_back(&mut items, PositionItem {
            liquidity: 640335940,
            tick_lower: i64::neg_from(33150),
            tick_upper: i64::neg_from(33050),
            amount_a: 16752440,
            amount_b: 0
        });
        vector::push_back(&mut items, PositionItem {
            liquidity: 6359274375,
            tick_lower: i64::neg_from(33150),
            tick_upper: i64::neg_from(33050),
            amount_a: 166371043,
            amount_b: 0
        });
        vector::push_back(&mut items, PositionItem {
            liquidity: 1084606530,
            tick_lower: i64::neg_from(42000),
            tick_upper: i64::neg_from(29900),
            amount_a: 4000779948,
            amount_b: 287206
        });
        vector::push_back(&mut items, PositionItem {
            liquidity: 84885647553,
            tick_lower: i64::neg_from(33400),
            tick_upper: i64::neg_from(33350),
            amount_a: 1125758816,
            amount_b: 0,
        });


        let pool_address = new_pool_for_testing(clmm, tick_spacing, fee_rate, init_sqrt_price);
        let assets = borrow_global<Assets>(signer::address_of(clmm));
        let (amount_a, amount_b, liquidity) = (0, 0, 0);

        let i = 0;
        while (i < vector::length(&items)) {
            let item = *vector::borrow(&items, i);
            let position_index = open_position(
                owner,
                pool_address,
                item.tick_lower,
                item.tick_upper
            );
            let receipt = add_liquidity(pool_address, item.liquidity, position_index);
            assert!(item.amount_a == receipt.amount_a, 0);
            assert!(item.amount_b == receipt.amount_b, 0);
            amount_a = amount_a + receipt.amount_a;
            amount_b = amount_b + receipt.amount_b;

            let a_metadata = object::address_to_object<Metadata>(assets.asset_a_addr);
            let b_metadata = object::address_to_object<Metadata>(assets.asset_b_addr);
            let token_a = primary_fungible_store::withdraw(clmm, a_metadata, receipt.amount_a);
            let token_b = primary_fungible_store::withdraw(clmm, b_metadata, receipt.amount_b);

            repay_add_liquidity(token_a, token_b, receipt);
            let pool = borrow_global<Pool>(pool_address);
            if (
                i64::gte(pool.current_tick_index, item.tick_lower) &&
                    i64::lt(pool.current_tick_index, item.tick_upper)
            ) {
                liquidity = liquidity + item.liquidity;
            };
            i = i + 1;
            check_position_authority(owner, pool_address, position_index);
        };
        let pool = borrow_global<Pool>(pool_address);
        assert!(pool.asset_a == amount_a, 0);
        assert!(pool.asset_b == amount_b, 0);
        assert!(pool.liquidity == liquidity, 0);
        let tick_33450 = table::borrow(&pool.ticks, i64::neg_from(33450));
        assert!(i128::as_u128(tick_33450.liquidity_net) == 2317299527, 0);
        assert!(tick_33450.liquidity_gross == 2317299527, 0);
        let tick_33350 = table::borrow(&pool.ticks, i64::neg_from(33350));
        assert!(i128::eq(tick_33350.liquidity_net, i128::neg_from(87202947080)), 0);
        assert!(tick_33350.liquidity_gross == 87202947080, 0);
        let (index, offset) = tick_position(i64::neg_from(42000), tick_spacing);
        let indexes = table::borrow(&pool.tick_indexes, index);
        assert!(bit_vector::is_index_set(indexes, offset), 0);
        assert!(!bit_vector::is_index_set(indexes, offset - 1), 0);
    }


    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm,
        owner = @0x123456
    )]
    fun test_add_liquidity_fix_asset(
        apt: &signer,
        clmm: &signer,
        owner: &signer,
    ) acquires Assets, Pool {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(owner));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);
        // The current tick is -41957
        let (tick_spacing, fee_rate, init_sqrt_price) = (60, 2000, 3595932416355410538);

        let items = vector::empty<PositionItem>();
        vector::push_back(&mut items, PositionItem {
            liquidity: 0,
            tick_lower: i64::neg_from(443580),
            tick_upper: i64::from(443580),
            amount_a: 100000000,
            amount_b: 0
        });
        vector::push_back(&mut items, PositionItem {
            liquidity: 0,
            tick_lower: i64::neg_from(180000),
            tick_upper: i64::from(180000),
            amount_a: 100000000,
            amount_b: 0
        });

        let pool_address = new_pool_for_testing(clmm, tick_spacing, fee_rate, init_sqrt_price);
        let assets = borrow_global<Assets>(signer::address_of(clmm));

        let i = 0;
        while (i < vector::length(&items)) {
            let item = *vector::borrow(&items, i);
            let position_index = open_position(
                owner,
                pool_address,
                item.tick_lower,
                item.tick_upper
            );
            let receipt = add_liquidity_fix_asset(
                pool_address,
                item.amount_a,
                true,
                position_index
            );
            let a_metadata = object::address_to_object<Metadata>(assets.asset_a_addr);
            let b_metadata = object::address_to_object<Metadata>(assets.asset_b_addr);
            let asset_a = primary_fungible_store::withdraw(clmm, a_metadata, receipt.amount_a);
            let asset_b = primary_fungible_store::withdraw(clmm, b_metadata, receipt.amount_b);
            repay_add_liquidity(asset_a, asset_b, receipt);
            i = i + 1;
            check_position_authority(owner, pool_address, position_index);
        }
    }

    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm,
        owner = @0x123456
    )]
    fun test_remove_liquidity(
        apt: &signer,
        clmm: &signer,
        owner: &signer
    ) acquires Pool, Assets {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(owner));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);
        let pool_address = new_pool_for_testing(clmm, 100, 2000, tick_math::get_sqrt_price_at_tick(i64::from(10000)));
        let assets = borrow_global<Assets>(signer::address_of(clmm));
        let liquidity = 30000000000;
        let position_index = open_position(
            owner,
            pool_address,
            i64::neg_from(50000),
            i64::from(50000)
        );
        let receipt = add_liquidity(pool_address, liquidity, position_index);
        assert!(receipt.amount_a == 15733516889, 0);
        assert!(receipt.amount_b == 46997543902, 0);
        let a_metadata = object::address_to_object<Metadata>(assets.asset_a_addr);
        let b_metadata = object::address_to_object<Metadata>(assets.asset_b_addr);
        let asset_a = primary_fungible_store::withdraw(
            clmm,
            a_metadata,
            receipt.amount_a
        );
        let asset_b = primary_fungible_store::withdraw(
            clmm,
            b_metadata,
            receipt.amount_b
        );
        repay_add_liquidity(asset_a, asset_b, receipt);
        let pool = borrow_global<Pool>(pool_address);
        assert!(pool.asset_a == 15733516889, 0);
        assert!(pool.asset_b == 46997543902, 0);
        let i = 0;
        while (i <= 2) {
            let (asset_a, asset_b) = remove_liquidity(
                owner,
                pool_address,
                liquidity / 3,
                position_index
            );
            assert!(fungible_asset::amount(&asset_a) == 5244505629, 0);
            assert!(fungible_asset::amount(&asset_b) == 15665847967, 0);
            primary_fungible_store::deposit(signer::address_of(owner), asset_a);
            primary_fungible_store::deposit(signer::address_of(owner), asset_b);
            i = i + 1;
        };
    }


    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm,
        owner = @0x123456
    )]
    #[expected_failure]
    fun test_remove_liquidity_overflowing(
        apt: &signer,
        clmm: &signer,
        owner: &signer
    ) acquires Pool, Assets {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(owner));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);
        let pool_address = new_pool_for_testing(clmm, 100, 2000, tick_math::get_sqrt_price_at_tick(i64::from(300100)));
        let assets = borrow_global<Assets>(signer::address_of(clmm));
        let (_amount_a, _amount_b, liquidity) = (0, 0, 112942705988161);

        let position_index = open_position(
            owner,
            pool_address,
            i64::neg_from(300000),
            i64::from(300000)
        );
        let receipt = add_liquidity(pool_address, liquidity, position_index);
        let a_metadata = object::address_to_object<Metadata>(assets.asset_a_addr);
        let b_metadata = object::address_to_object<Metadata>(assets.asset_b_addr);
        let asset_a = primary_fungible_store::withdraw(clmm, a_metadata, receipt.amount_a);
        let asset_b = primary_fungible_store::withdraw(clmm, b_metadata, receipt.amount_b);
        repay_add_liquidity(asset_a, asset_b, receipt);
        {
            let pool = borrow_global_mut<Pool>(pool_address);
            pool.asset_a = pool.asset_a + 1152921504606846976;
            pool.asset_b = pool.asset_b + 1152921504606846976;
        };
        let i = 0;
        while (i <= 2) {
            let (asset_a, asset_b) = remove_liquidity(
                owner,
                pool_address,
                liquidity / 1000,
                position_index
            );
            fungible_asset::destroy_zero(asset_a);
            primary_fungible_store::deposit(signer::address_of(owner), asset_b);
            i = i + 1;
        };
    }


    #[test_only]
    fun new_pool_for_test_swap(
        clmm: &signer
    ): address acquires Pool, Assets {
        //|-------------------------------------------------------------------------------------------------------------------------|
        //|  index  |          sqrt_price           | liquidity_net | liquidity_gross | fee_growth_outside_a | fee_growth_outside_b |
        //|---------|-------------------------------|---------------|-----------------|----------------------|----------------------|
        //| -443580 |          4307090400           |    3999708    |     3999708     |          0           |          0           |
        //| -37800  |      2787046340236524056      |   16203513    |    16203513     |          0           |          0           |
        //| -33600  |      3438281822290508425      |   881443427   |    881443427    |    21528707421335    |          0           |
        //| -32940  |      3553632168384889063      |   508732271   |    508732271    |          0           |          0           |
        //| -32520  |      3629043723519240164      |  2644625738   |   2644625738    |    25550458736950    |     591814185792     |
        //| -32400  |      3650882344297301371      |  1635473525   |   1635473525    |    21528707421335    |          0           |
        //| -32340  |      3661850887500983734      |  4297786773   |   4297786773    |    21528707421335    |          0           |
        //| -32220  |      3683886933074000616      |  13182568433  |   13182568433   |          0           |          0           |
        //| -32160  |      3694954633748063382      | -13182568433  |   13182568433   |          0           |          0           |
        //| -32100  |      3706055585713611480      |  -4297786773  |   4297786773    |          0           |          0           |
        //| -32040  |      3717189888869297576      |  -2909088311  |   2909088311    |          0           |          0           |
        //| -31380  |      3841897275390034394      |  -508732271   |    508732271    |          0           |          0           |
        //| -30720  |      3970788449319480396      |  -873244625   |    873244625    |          0           |          0           |
        //| -29040  |      4318726111203610053      |  -1371010952  |   1371010952    |          0           |          0           |
        //| -26520  |      4898623158270717161      |   -16203513   |    16203513     |          0           |          0           |
        //| 443580  | 79005160168441461737552776218 |   -12198510   |    12198510     |          0           |          0           |
        //|-------------------------------------------------------------------------------------------------------------------------|

        let (tick_spacing, fee_rate, init_sqrt_price) = (60, 2000, 3689080658479008119);
        let pool_address = new_pool_for_testing(clmm, tick_spacing, fee_rate, init_sqrt_price);
        let assets = borrow_global<Assets>(signer::address_of(clmm));
        let pool = borrow_global_mut<Pool>(pool_address);
        pool.liquidity = 23170833388;

        add_tick_for_testing(pool, i64::neg_from(443580), i128::from(3999708), 3999708);
        add_tick_for_testing(pool, i64::neg_from(37800), i128::from(16203513), 16203513);
        add_tick_for_testing(pool, i64::neg_from(33600), i128::from(881443427), 881443427);
        add_tick_for_testing(pool, i64::neg_from(32940), i128::from(508732271), 508732271);
        add_tick_for_testing(pool, i64::neg_from(32520), i128::from(2644625738), 2644625738);
        add_tick_for_testing(pool, i64::neg_from(32400), i128::from(1635473525), 1635473525);
        add_tick_for_testing(pool, i64::neg_from(32340), i128::from(4297786773), 4297786773);
        add_tick_for_testing(pool, i64::neg_from(32220), i128::from(13182568433), 13182568433);
        add_tick_for_testing(pool, i64::neg_from(32160), i128::neg_from(13182568433), 13182568433);
        add_tick_for_testing(pool, i64::neg_from(32100), i128::neg_from(4297786773), 4297786773);
        add_tick_for_testing(pool, i64::neg_from(32040), i128::neg_from(2909088311), 2909088311);
        add_tick_for_testing(pool, i64::neg_from(31380), i128::neg_from(508732271), 508732271);
        add_tick_for_testing(pool, i64::neg_from(30720), i128::neg_from(873244625), 873244625);
        add_tick_for_testing(pool, i64::neg_from(29040), i128::neg_from(1371010952), 1371010952);
        add_tick_for_testing(pool, i64::neg_from(26520), i128::neg_from(16203513), 16203513);
        add_tick_for_testing(pool, i64::from(443580), i128::neg_from(12198510), 12198510);

        let a_metadata = object::address_to_object<Metadata>(assets.asset_a_addr);
        let b_metadata = object::address_to_object<Metadata>(assets.asset_b_addr);
        let pool_asset_a = primary_fungible_store::withdraw(clmm, a_metadata, 1804722468);
        let pool_asset_b = primary_fungible_store::withdraw(clmm, b_metadata, 39361979);

        let pool_signer = account::create_signer_with_capability(&pool.signer_cap);
        let pool_signer_addr = signer::address_of(&pool_signer);
        primary_fungible_store::deposit(pool_signer_addr, pool_asset_a);
        primary_fungible_store::deposit(pool_signer_addr, pool_asset_b);
        pool.asset_a = pool.asset_a + 1804722468;
        pool.asset_b = pool.asset_b + 39361979;

        pool_address
    }

    #[test_only]
    fun sqrt_price_limit_for_testing(a2b: bool): u128 {
        let sqrt_price_limit = if (a2b) {
            min_sqrt_price()
        } else {
            max_sqrt_price()
        };
        sqrt_price_limit
    }

    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm,
        trader = @0x123456
    )]
    fun test_swap(
        apt: &signer,
        clmm: &signer,
        trader: &signer
    ) acquires Pool, Assets {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(trader));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);

        let pool_address = new_pool_for_test_swap(clmm);
        let amount_in = 10000000000111300;
        let partner_name = string::utf8(b"");
        let swap_from = signer::address_of(trader);
        let a2b = false;
        let by_amount_in = true;
        let (asset_a, asset_b, receipt) = flash_swap(
            pool_address,
            swap_from,
            partner_name,
            a2b,
            by_amount_in,
            amount_in,
            sqrt_price_limit_for_testing(a2b),
        );
        assert!(fungible_asset::amount(&asset_a) == 1804696987, 0);
        assert!(fungible_asset::amount(&asset_b) == 0, 0);
        assert!(swap_pay_amount(&receipt) == amount_in, 0);
        let assets = borrow_global<Assets>(signer::address_of(clmm));
        let a_metadata = object::address_to_object<Metadata>(assets.asset_a_addr);
        let b_metadata = object::address_to_object<Metadata>(assets.asset_b_addr);
        if (a2b) {
            fungible_asset::destroy_zero(asset_a);
            primary_fungible_store::deposit(swap_from, asset_b);
            repay_flash_swap(
                primary_fungible_store::withdraw(clmm, a_metadata, swap_pay_amount(&receipt)),
                fungible_asset::zero(b_metadata),
                receipt
            );
        } else {
            fungible_asset::destroy_zero(asset_b);
            primary_fungible_store::deposit(swap_from, asset_a);
            repay_flash_swap(
                fungible_asset::zero(a_metadata),
                primary_fungible_store::withdraw(clmm, b_metadata, swap_pay_amount(&receipt)),
                receipt
            );
        };
    }

    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm,
        trader = @0x123456
    )]
    fun test_calculate_swap_result(
        apt: &signer,
        clmm: &signer,
        trader: &signer
    ) acquires Pool, Assets {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(trader));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);
        let pool_address = new_pool_for_test_swap(clmm);
        let result = calculate_swap_result(
            pool_address,
            false,
            true,
            10000000000111300
        );
        assert!(10000000000111300 == (result.amount_in + result.fee_amount), 0);
        assert!(result.amount_out == 1804696987, 0);
        assert!(!result.is_exceed, 0);

        let result = calculate_swap_result(
            pool_address,
            false,
            true,
            1
        );
        assert!(1 == result.fee_amount, 0);
        assert!(0 == result.amount_in, 0);
        assert!(result.amount_out == 0, 0);
        assert!(!result.is_exceed, 0);

        let result = calculate_swap_result(
            pool_address,
            true,
            true,
            1
        );
        assert!(1 == result.fee_amount, 0);
        assert!(0 == result.amount_in, 0);
        assert!(result.amount_out == 0, 0);
        assert!(!result.is_exceed, 0);

        let result = calculate_swap_result(
            pool_address,
            true,
            false,
            1
        );
        assert!(1 == result.fee_amount, 0);
        assert!(26 == result.amount_in, 0);
        assert!(result.amount_out == 1, 0);
        assert!(!result.is_exceed, 0);

        let result = calculate_swap_result(
            pool_address,
            false,
            false,
            1
        );
        assert!(1 == result.fee_amount, 0);
        assert!(1 == result.amount_in, 0);
        assert!(result.amount_out == 1, 0);
        assert!(!result.is_exceed, 0);

        let result = calculate_swap_result(
            pool_address,
            false,
            false,
            10000000000000000
        );
        assert!(104698865781772 == result.fee_amount, 0);
        assert!(52244734025102255 == result.amount_in, 0);
        assert!(1804696987 == result.amount_out, 0);
        assert!(result.is_exceed, 0);
    }

    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm,
        trader = @0x123456
    )]
    fun test_swap_in_pool(
        apt: &signer,
        clmm: &signer,
        trader: &signer
    ) acquires Pool, Assets {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(trader));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);
        let pool_address = new_pool_for_test_swap(clmm);
        let pool = borrow_global_mut<Pool>(pool_address);
        let result = swap_in_pool(
            pool,
            false,
            true,
            sqrt_price_limit_for_testing(false),
            10000000000111300,
            20,
            10
        );
        assert!(10000000000111300 == (result.amount_in + result.fee_amount), 0);
        assert!(result.amount_out == 1804696987, 0);
        assert!(result.ref_fee_amount == 39999999, 0);

        let before_protcol_fee = pool.fee_protocol_asset_b;
        let result = swap_in_pool(
            pool,
            false,
            true,
            sqrt_price_limit_for_testing(false),
            1,
            20,
            10
        );
        assert!(1 == result.fee_amount, 0);
        assert!(0 == result.amount_out, 0);
        assert!(0 == result.amount_out, 0);
        assert!(0 == result.ref_fee_amount, 0);
        assert!((pool.fee_protocol_asset_b - before_protcol_fee) == 1, 0);

        let before_protcol_fee = pool.fee_protocol_asset_a;
        let result = swap_in_pool(
            pool,
            true,
            true,
            sqrt_price_limit_for_testing(true),
            1,
            20,
            10
        );
        assert!(1 == result.fee_amount, 0);
        assert!(0 == result.amount_out, 0);
        assert!(0 == result.amount_out, 0);
        assert!(0 == result.ref_fee_amount, 0);
        assert!((pool.fee_protocol_asset_a - before_protcol_fee) == 1, 0);
    }

    #[test(
        apt = @0x1,
        clmm = @dexlyn_clmm,
        trader = @0x123456
    )]
    #[expected_failure]
    fun test_swap_in_pool_no_enough_liquidity(
        apt: &signer,
        clmm: &signer,
        trader: &signer
    ) acquires Pool, Assets {
        account::create_account_for_test(signer::address_of(clmm));
        account::create_account_for_test(signer::address_of(trader));
        account::create_account_for_test(signer::address_of(apt));
        timestamp::set_time_has_started_for_testing(apt);
        let pool_address = new_pool_for_test_swap(clmm);
        let pool = borrow_global_mut<Pool>(pool_address);
        swap_in_pool(
            pool,
            false,
            true,
            sqrt_price_limit_for_testing(false),
            10000000000111300000,
            20,
            10
        );
    }
}
