module dexlyn_clmm::clmm_router {
    use std::signer;
    use std::string::String;

    use supra_framework::coin;
    use supra_framework::fungible_asset::{Self, Metadata};
    use supra_framework::object;
    use supra_framework::primary_fungible_store;

    use dexlyn_clmm::config;
    use dexlyn_clmm::factory;
    use dexlyn_clmm::fee_tier;
    use dexlyn_clmm::partner;
    use dexlyn_clmm::pool;
    use dexlyn_clmm::utils;
    use integer_mate::i64;

    /// reuired amount A exceeds the maximum allowed value
    const EAMOUNT_IN_ABOVE_MAX_LIMIT: u64 = 1;

    /// returned amount B is below the minimum limit
    const EAMOUNT_OUT_BELOW_MIN_LIMIT: u64 = 2;

    /// the tick is not valid for the pool
    const EIS_NOT_VALID_TICK: u64 = 3;

    /// the liquidity is not valid for the pool
    const EINVALID_LIQUIDITY: u64 = 4;

    /// the pool address is not valid
    const EPOOL_ADDRESS_ERROR: u64 = 5;

    /// the pool pair is not valid
    const EINVALID_POOL_PAIR: u64 = 6;

    /// the swap amount is incorrect
    const ESWAP_AMOUNT_INCORRECT: u64 = 7;

    /// the position index is not valid
    const EPOSITION_INDEX_ERROR: u64 = 8;

    /// the position is not zero, can not close it.
    const EPOSITION_IS_NOT_ZERO: u64 = 9;

    /// Transfer the `protocol_authority` to new authority.
    /// Params
    ///     - next_protocol_authority
    /// Returns
    public entry fun transfer_protocol_authority(
        protocol_authority: &signer,
        next_protocol_authority: address
    ) {
        config::transfer_protocol_authority(protocol_authority, next_protocol_authority);
    }

    /// Accept the `protocol_authority`.
    /// Params
    /// Returns
    public entry fun accept_protocol_authority(
        next_protocol_authority: &signer
    ) {
        config::accept_protocol_authority(next_protocol_authority);
    }


    /// Update the `protocol_fee_claim_authority`.
    /// Params
    ///     - next_protocol_fee_claim_authority
    /// Returns
    public entry fun update_protocol_fee_claim_authority(
        protocol_authority: &signer,
        next_protocol_fee_claim_authority: address,
    ) {
        config::update_protocol_fee_claim_authority(protocol_authority, next_protocol_fee_claim_authority);
    }

    /// Update the `pool_create_authority`.
    /// Params
    ///     - pool_create_authority
    /// Returns
    public entry fun update_pool_create_authority(
        protocol_authority: &signer,
        pool_create_authority: address
    ) {
        config::update_pool_create_authority(protocol_authority, pool_create_authority);
    }

    /// Update the `protocol_fee_rate`, the protocol_fee_rate is unique and global for the clmmpool protocol.
    /// Params
    ///     - protocol_fee_rate
    /// Returns
    public entry fun update_protocol_fee_rate(
        protocol_authority: &signer,
        protocol_fee_rate: u64
    ) {
        config::update_protocol_fee_rate(protocol_authority, protocol_fee_rate);
    }

    /// Add a new `fee_tier`. fee_tier is identified by the tick_spacing.
    /// Params
    ///     - tick_spacing
    ///     - fee_rate
    /// Returns
    public entry fun add_fee_tier(
        protocol_authority: &signer,
        tick_spacing: u64,
        fee_rate: u64
    ) {
        fee_tier::add_fee_tier(protocol_authority, tick_spacing, fee_rate);
    }

    /// Update the fee_rate of a fee_tier.
    /// Params
    ///     - tick_spacing
    ///     - new_fee_rate
    /// Returns
    public entry fun update_fee_tier(
        protocol_authority: &signer,
        tick_spacing: u64,
        new_fee_rate: u64
    ) {
        fee_tier::update_fee_tier(protocol_authority, tick_spacing, new_fee_rate);
    }

    /// Delete fee_tier.
    /// Params
    ///     - tick_spacing
    /// Returns
    public entry fun delete_fee_tier(
        protocol_authority: &signer,
        tick_spacing: u64,
    ) {
        fee_tier::delete_fee_tier(protocol_authority, tick_spacing);
    }

    /// Create a pool of clmmpool protocol. The pool is identified by (CoinTypeA, CoinTypeB, tick_spacing).
    /// Params
    ///     - tick_spacing
    ///     - initialize_sqrt_price: the init sqrt price of the pool.
    ///     - uri: this uri is used for token uri of the position token of this pool.
    ///     - asset_a_addr: FungibleAsset A address
    ///     - asset_b_addr: FungibleAsset B address
    /// Returns
    public entry fun create_pool(
        account: &signer,
        tick_spacing: u64,
        initialize_sqrt_price: u128,
        uri: String,
        asset_a_addr: address,
        asset_b_addr: address,
    ) {
        factory::create_pool(
            account, tick_spacing,
            initialize_sqrt_price, uri,
            asset_a_addr,
            asset_b_addr,
        );
    }

    /// Create a pool of clmmpool protocol. The pool is identified by (CoinTypeA, CoinTypeB, tick_spacing).
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///     - tick_spacing
    ///     - initialize_sqrt_price: the init sqrt price of the pool.
    ///     - uri: this uri is used for token uri of the position token of this pool.
    /// Returns
    public entry fun create_pool_coin_coin<CoinTypeA, CoinTypeB>(
        account: &signer,
        tick_spacing: u64,
        initialize_sqrt_price: u128,
        uri: String,
    ) {
        factory::create_pool(
            account,
            tick_spacing,
            initialize_sqrt_price,
            uri,
            utils::coin_to_fa_address<CoinTypeA>(),
            utils::coin_to_fa_address<CoinTypeB>()
        );
    }

    /// Create a pool of clmmpool protocol. The pool is identified by (CoinType, FungibleAssetB, tick_spacing).
    /// Params
    ///     Type:
    ///         - CoinType
    ///     - tick_spacing
    ///     - initialize_sqrt_price: the init sqrt price of the pool.
    ///     - uri: this uri is used for token uri of the position token of this pool.
    ///     - asset_addr: FungibleAsset address
    /// Returns
    public entry fun create_pool_coin_asset<CoinType>(
        account: &signer,
        tick_spacing: u64,
        initialize_sqrt_price: u128,
        uri: String,
        asset_b_addr: address
    ) {
        factory::create_pool(
            account,
            tick_spacing,
            initialize_sqrt_price,
            uri,
            utils::coin_to_fa_address<CoinType>(),
            asset_b_addr
        );
    }

    /// Add liquidity into a pool with Coins. The position is identified by the name.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     - pool_address
    ///     - delta_liquidity
    ///     - max_amount_a: the max number of asset_a can be consumed by the pool.
    ///     - max_amount_b: the max number of asset_b can be consumed by the pool.
    ///     - tick_lower
    ///     - tick_upper
    ///     - is_open: control whether or not to create a new position or add liquidity on existed position.
    ///     - index: position index. if `is_open` is true, index is no use.
    /// Returns
    public entry fun add_liquidity_coin_coin<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        max_amount_a: u64,
        max_amount_b: u64,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        position_index: u64,
    ) {
        coin::migrate_to_fungible_store<CoinTypeA>(account);
        coin::migrate_to_fungible_store<CoinTypeB>(account);
        add_liquidity_internal(
            account,
            pool_address,
            delta_liquidity,
            max_amount_a,
            max_amount_b,
            tick_lower,
            tick_upper,
            is_open,
            position_index,
        )
    }

    /// Add liquidity into a pool with Coin and FungibleAsset. The position is identified by the name.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     - pool_address
    ///     - delta_liquidity
    ///     - max_amount_a: the max number of asset_a can be consumed by the pool.
    ///     - max_amount_b: the max number of asset_b can be consumed by the pool.
    ///     - tick_lower
    ///     - tick_upper
    ///     - is_open: control whether or not to create a new position or add liquidity on existed position.
    ///     - index: position index. if `is_open` is true, index is no use.
    /// Returns
    public entry fun add_liquidity_coin_asset<CoinType>(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        max_amount_a: u64,
        max_amount_b: u64,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        position_index: u64,
    ) {
        coin::migrate_to_fungible_store<CoinType>(account);
        add_liquidity_internal(
            account,
            pool_address,
            delta_liquidity,
            max_amount_a,
            max_amount_b,
            tick_lower,
            tick_upper,
            is_open,
            position_index,
        )
    }

    /// Add liquidity into a pool with FungibleAssets. The position is identified by the name.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     - pool_address
    ///     - delta_liquidity
    ///     - max_amount_a: the max number of asset_a can be consumed by the pool.
    ///     - max_amount_b: the max number of asset_b can be consumed by the pool.
    ///     - tick_lower
    ///     - tick_upper
    ///     - is_open: control whether or not to create a new position or add liquidity on existed position.
    ///     - index: position index. if `is_open` is true, index is no use.
    /// Returns
    public entry fun add_liquidity(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        max_amount_a: u64,
        max_amount_b: u64,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        position_index: u64,
    ) {
        add_liquidity_internal(
            account,
            pool_address,
            delta_liquidity,
            max_amount_a,
            max_amount_b,
            tick_lower,
            tick_upper,
            is_open,
            position_index,
        )
    }

    fun add_liquidity_internal(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        max_amount_a: u64,
        max_amount_b: u64,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        position_index: u64,
    ) {
        // Open position if needed.
        let tick_lower_index = i64::from_u64(tick_lower);
        let tick_upper_index = i64::from_u64(tick_upper);
        let pos_index = if (is_open) {
            pool::open_position(
                account,
                pool_address,
                tick_lower_index,
                tick_upper_index,
            )
        } else {
            pool::check_position_authority(account, pool_address, position_index);
            let (position_tick_lower, position_tick_upper) =
                pool::get_position_tick_range(pool_address, position_index);
            assert!(i64::eq(tick_lower_index, position_tick_lower), EIS_NOT_VALID_TICK);
            assert!(i64::eq(tick_upper_index, position_tick_upper), EIS_NOT_VALID_TICK);
            position_index
        };

        // Add liquidity
        let receipt = pool::add_liquidity(
            pool_address,
            delta_liquidity,
            pos_index
        );
        let (amount_a_needed, amount_b_needed) = pool::add_liqudity_pay_amount(&receipt);
        assert!(amount_a_needed <= max_amount_a, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        assert!(amount_b_needed <= max_amount_b, EAMOUNT_IN_ABOVE_MAX_LIMIT);

        let (asset_a_addr, asset_b_addr) = pool::get_pool_assets(pool_address);

        let asset_a_metadata = object::address_to_object<Metadata>(asset_a_addr);
        let asset_b_metadata = object::address_to_object<Metadata>(asset_b_addr);

        let asset_a = if (amount_a_needed > 0) {
            primary_fungible_store::withdraw(account, asset_a_metadata, amount_a_needed)
        }else {
            fungible_asset::zero(asset_a_metadata)
        };

        let asset_b = if (amount_b_needed > 0) {
            primary_fungible_store::withdraw(account, asset_b_metadata, amount_b_needed)
        }else {
            fungible_asset::zero(asset_b_metadata)
        };
        pool::repay_add_liquidity(asset_a, asset_b, receipt);
    }

    /// Add liquidity into a pool with Coins. The position is identified by the name.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     - pool_address
    ///     - amount_a: if fix_amount_a is false, amount_a is the max asset_a amount to be consumed.
    ///     - amount_b: if fix_amount_a is true, amount_b is the max asset_b amount to be consumed.
    ///     - fix_amount_a: control whether asset_a or asset_b amount is fixed
    ///     - tick_lower
    ///     - tick_upper
    ///     - is_open: control whether or not to create a new position or add liquidity on existed position.
    ///     - index: position index. if `is_open` is true, index is no use.
    /// Returns
    public entry fun add_liquidity_fix_value_coin_coin<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address,
        amount_a: u64,
        amount_b: u64,
        fix_amount_a: bool,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        index: u64,
    ) {
        coin::migrate_to_fungible_store<CoinTypeA>(account);
        coin::migrate_to_fungible_store<CoinTypeB>(account);
        add_liquidity_fix_value_internal(
            account,
            pool_address,
            amount_a,
            amount_b,
            fix_amount_a,
            tick_lower,
            tick_upper,
            is_open,
            index,
        )
    }


    /// Add liquidity into a pool with CoinType and FungibleAsset. The position is identified by the name.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     - pool_address
    ///     - amount_a: if fix_amount_a is false, amount_a is the max asset_a amount to be consumed.
    ///     - amount_b: if fix_amount_a is true, amount_b is the max asset_b amount to be consumed.
    ///     - fix_amount_a: control whether asset_a or asset_b amount is fixed
    ///     - tick_lower
    ///     - tick_upper
    ///     - is_open: control whether or not to create a new position or add liquidity on existed position.
    ///     - index: position index. if `is_open` is true, index is no use.
    /// Returns
    public entry fun add_liquidity_fix_value_coin_asset<CoinType>(
        account: &signer,
        pool_address: address,
        amount_a: u64,
        amount_b: u64,
        fix_amount_a: bool,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        position_index: u64,
    ) {
        coin::migrate_to_fungible_store<CoinType>(account);
        add_liquidity_fix_value_internal(
            account,
            pool_address,
            amount_a,
            amount_b,
            fix_amount_a,
            tick_lower,
            tick_upper,
            is_open,
            position_index,
        )
    }

    /// Add liquidity into a pool with FungibleAssets. The position is identified by the name.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     - pool_address
    ///     - amount_a: if fix_amount_a is false, amount_a is the max asset_a amount to be consumed.
    ///     - amount_b: if fix_amount_a is true, amount_b is the max asset_b amount to be consumed.
    ///     - fix_amount_a: control whether asset_a or asset_b amount is fixed
    ///     - tick_lower
    ///     - tick_upper
    ///     - is_open: control whether or not to create a new position or add liquidity on existed position.
    ///     - index: position index. if `is_open` is true, index is no use.
    /// Returns
    public entry fun add_liquidity_fix_value(
        account: &signer,
        pool_address: address,
        amount_a: u64,
        amount_b: u64,
        fix_amount_a: bool,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        index: u64,
    ) {
        add_liquidity_fix_value_internal(
            account,
            pool_address,
            amount_a,
            amount_b,
            fix_amount_a,
            tick_lower,
            tick_upper,
            is_open,
            index,
        )
    }


    /// add liquidiy fix token
    fun add_liquidity_fix_value_internal(
        account: &signer,
        pool_address: address,
        amount_a: u64,
        amount_b: u64,
        fix_amount_a: bool,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        position_index: u64,
    ) {
        // Open position if needed.
        let tick_lower_index = i64::from_u64(tick_lower);
        let tick_upper_index = i64::from_u64(tick_upper);
        let pos_index = if (is_open) {
            pool::open_position(
                account,
                pool_address,
                tick_lower_index,
                tick_upper_index,
            )
        } else {
            pool::check_position_authority(account, pool_address, position_index);
            let (position_tick_lower, position_tick_upper) =
                pool::get_position_tick_range(pool_address, position_index);
            assert!(i64::eq(tick_lower_index, position_tick_lower), EIS_NOT_VALID_TICK);
            assert!(i64::eq(tick_upper_index, position_tick_upper), EIS_NOT_VALID_TICK);
            position_index
        };

        // Add liquidity
        let amount = if (fix_amount_a) { amount_a } else { amount_b };
        let receipt = pool::add_liquidity_fix_asset(
            pool_address,
            amount,
            fix_amount_a,
            pos_index
        );
        let (amount_a_needed, amount_b_needed) = pool::add_liqudity_pay_amount(&receipt);
        if (fix_amount_a) {
            assert!(amount_a == amount_a_needed && amount_b_needed <= amount_b, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        }else {
            assert!(amount_b == amount_b_needed && amount_a_needed <= amount_a, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        };

        let (asset_a_addr, asset_b_addr) = pool::get_pool_assets(pool_address);

        let asset_a_metadata = object::address_to_object<Metadata>(asset_a_addr);
        let asset_b_metadata = object::address_to_object<Metadata>(asset_b_addr);
        let asset_a = if (amount_a_needed > 0) {
            primary_fungible_store::withdraw(account, asset_a_metadata, amount_a_needed)
        }else {
            fungible_asset::zero(asset_a_metadata)
        };
        let asset_b = if (amount_b_needed > 0) {
            primary_fungible_store::withdraw(account, asset_b_metadata, amount_b_needed)
        }else {
            fungible_asset::zero(asset_b_metadata)
        };
        pool::repay_add_liquidity(asset_a, asset_b, receipt);
    }

    /// Remove liquidity from a pool.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     - pool_address
    ///     - delta_liquidity
    ///     - min_amount_a
    ///     - min_amount_b
    ///     - position_index: the position index to remove liquidity.
    ///     - is_close: is or not to close the position if position is empty.
    /// Returns
    public entry fun remove_liquidity(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        min_amount_a: u64,
        min_amount_b: u64,
        position_index: u64,
        is_close: bool,
    ) {
        // Remove liquidity
        let (asset_a, asset_b) = pool::remove_liquidity(
            account,
            pool_address,
            delta_liquidity,
            position_index
        );
        assert!(fungible_asset::amount(&asset_a) >= min_amount_a, EAMOUNT_OUT_BELOW_MIN_LIMIT);
        assert!(fungible_asset::amount(&asset_b) >= min_amount_b, EAMOUNT_OUT_BELOW_MIN_LIMIT);
        let user_address = signer::address_of(account);
        primary_fungible_store::deposit(user_address, asset_a);
        primary_fungible_store::deposit(user_address, asset_b);

        // Collect position's fee
        let (fee_asset_a, fee_asset_b) = pool::collect_fee(
            account,
            pool_address,
            position_index,
            false
        );

        primary_fungible_store::deposit(user_address, fee_asset_a);
        primary_fungible_store::deposit(user_address, fee_asset_b);

        // Close position if is_close=true and position's liquidity is zero.
        if (is_close) {
            pool::checked_close_position(account, pool_address, position_index);
        }
    }

    /// Provide to close position if position is empty.
    /// Params
    ///     - pool_address: The pool account address
    ///     - position_index: The position iindex
    /// Returns
    public entry fun close_position(
        account: &signer,
        pool_address: address,
        position_index: u64,
    ) {
        let is_closed = pool::checked_close_position(
            account,
            pool_address,
            position_index
        );
        if (!is_closed) {
            abort EPOSITION_IS_NOT_ZERO
        };
    }

    /// Provide to the position to collect the fee of the position earned.
    /// Params
    ///     - pool_address: The pool account address
    ///     - position_index: The position index
    /// Returns
    public entry fun collect_fee(
        account: &signer,
        pool_address: address,
        position_index: u64
    ) {
        let user_address = signer::address_of(account);
        let (fee_asset_a, fee_asset_b) = pool::collect_fee(
            account,
            pool_address,
            position_index,
            true
        );
        primary_fungible_store::deposit(user_address, fee_asset_a);
        primary_fungible_store::deposit(user_address, fee_asset_b);
    }

    /// Provide to the position to collect the rewarder of the position earned.
    /// Params
    ///     - pool_address: pool address.
    ///     - rewarder_index: the rewarder index(0,1,2).
    ///     - pos_index: the position index to collect rewarder.
    ///     - asset_addr: FungibleAsset Reward address
    /// Returns
    public entry fun collect_rewarder(
        account: &signer,
        pool_address: address,
        rewarder_index: u8,
        pos_index: u64,
        asset_addr: address
    ) {
        let rewarder_asset = pool::collect_rewarder(
            account,
            pool_address,
            pos_index,
            rewarder_index,
            true,
            asset_addr
        );
        primary_fungible_store::deposit(signer::address_of(account), rewarder_asset);
    }

    /// Provide to protocol_claim_authority to collect protocol fee.
    /// Params
    ///     - account The protocol fee claim authority
    ///     - pool_address The pool account address
    /// Returns
    public entry fun collect_protocol_fee(
        account: &signer,
        pool_address: address
    ) {
        let addr = signer::address_of(account);
        let (asset_a, asset_b) = pool::collect_protocol_fee(
            account,
            pool_address
        );
        primary_fungible_store::deposit(addr, asset_a);
        primary_fungible_store::deposit(addr, asset_b);
    }

    /// Swap by Coin.
    /// Params
    ///     Type:
    ///         - CoinType
    ///     - account The swap tx signer
    ///     - pool_address: The pool account address
    ///     - a_to_b: true --> atob; false --> btoa
    ///     - by_amount_in: represent `amount` is the input(if a_to_b is true, then input is asset_a) amount to be consumed or output amount returned.
    ///     - amount
    ///     - amount_limit: if `by_amount_in` is true, `amount_limit` is the minimum outout amount returned;
    ///                     if `by_amount_in` is false, `amount_limit` is the maximum input amount can be consumed.
    ///     - sqrt_price_limit
    ///     - partner: The partner name
    /// Returns
    public entry fun swap_coin<CoinType>(
        account: &signer,
        pool_address: address,
        a_to_b: bool,
        by_amount_in: bool,
        amount: u64,
        amount_limit: u64,
        sqrt_price_limit: u128,
        partner: String,
    ) {
        coin::migrate_to_fungible_store<CoinType>(account);
        swap_internal(
            account,
            pool_address,
            a_to_b,
            by_amount_in,
            amount,
            amount_limit,
            sqrt_price_limit,
            partner,
        );
    }

    /// Swap by FungibleAsset.
    /// Params
    ///     - account The swap tx signer
    ///     - pool_address: The pool account address
    ///     - a_to_b: true --> atob; false --> btoa
    ///     - by_amount_in: represent `amount` is the input(if a_to_b is true, then input is asset_a) amount to be consumed or output amount returned.
    ///     - amount
    ///     - amount_limit: if `by_amount_in` is true, `amount_limit` is the minimum outout amount returned;
    ///                     if `by_amount_in` is false, `amount_limit` is the maximum input amount can be consumed.
    ///     - sqrt_price_limit
    ///     - partner: The partner name
    /// Returns
    public entry fun swap(
        account: &signer,
        pool_address: address,
        a_to_b: bool,
        by_amount_in: bool,
        amount: u64,
        amount_limit: u64,
        sqrt_price_limit: u128,
        partner: String,
    ) {
        swap_internal(
            account,
            pool_address,
            a_to_b,
            by_amount_in,
            amount,
            amount_limit,
            sqrt_price_limit,
            partner,
        );
    }

    /// Swap.
    fun swap_internal(
        account: &signer,
        pool_address: address,
        a_to_b: bool,
        by_amount_in: bool,
        amount: u64,
        amount_limit: u64,
        sqrt_price_limit: u128,
        partner: String,
    ) {
        let swap_from = signer::address_of(account);
        let (asset_a, asset_b, flash_receipt) = pool::flash_swap(
            pool_address,
            swap_from,
            partner,
            a_to_b,
            by_amount_in,
            amount,
            sqrt_price_limit,
        );
        let in_amount = pool::swap_pay_amount(&flash_receipt);
        let out_amount = if (a_to_b) {
            fungible_asset::amount(&asset_b)
        }else {
            fungible_asset::amount(&asset_a)
        };

        //check limit
        if (by_amount_in) {
            assert!(in_amount == amount, ESWAP_AMOUNT_INCORRECT);
            assert!(out_amount >= amount_limit, EAMOUNT_OUT_BELOW_MIN_LIMIT);
        }else {
            assert!(out_amount == amount, ESWAP_AMOUNT_INCORRECT);
            assert!(in_amount <= amount_limit, EAMOUNT_IN_ABOVE_MAX_LIMIT)
        };

        let (asset_a_addr, asset_b_addr) = pool::get_pool_assets(pool_address);
        let asset_a_metadata = object::address_to_object<Metadata>(asset_a_addr);
        let asset_b_metadata = object::address_to_object<Metadata>(asset_b_addr);

        //repay asset
        if (a_to_b) {
            fungible_asset::destroy_zero(asset_a);
            primary_fungible_store::deposit(swap_from, asset_b);
            let asset_a = primary_fungible_store::withdraw(account, asset_a_metadata, in_amount);
            pool::repay_flash_swap(asset_a, fungible_asset::zero(asset_b_metadata), flash_receipt);
        }else {
            fungible_asset::destroy_zero(asset_b);
            primary_fungible_store::deposit(swap_from, asset_a);
            let asset_b = primary_fungible_store::withdraw(account, asset_b_metadata, in_amount);
            pool::repay_flash_swap(fungible_asset::zero(asset_a_metadata), asset_b, flash_receipt);
        }
    }

    /// Provide to the protocol_authority to update the pool fee rate.
    /// Params
    ///     - pool_address
    ///     - new_fee_rate
    /// Returns
    public entry fun update_fee_rate(
        protocol_authority: &signer,
        pool_addr: address,
        new_fee_rate: u64
    ) {
        pool::update_fee_rate(protocol_authority, pool_addr, new_fee_rate);
    }


    /// Initialize the rewarder.
    /// Params
    ///     - account The protocol authority signer
    ///     - pool_address The pool account address
    ///     - authority The rewarder authority address
    ///     - index The rewarder index
    ///     - asset_addr: FungibleAsset Reward address
    /// Returns
    public entry fun initialize_rewarder(
        account: &signer,
        pool_address: address,
        authority: address,
        rewarder_index: u64,
        asset_addr: address
    ) {
        pool::initialize_rewarder(account, pool_address, authority, rewarder_index, asset_addr);
    }

    /// Update the rewarder emission.
    /// Params
    ///     - pool_address
    ///     - index
    ///     - emission_per_second
    ///     - asset_addr: FungibleAsset Reward address
    /// Returns
    public entry fun update_rewarder_emission(
        account: &signer,
        pool_address: address,
        rewarder_index: u8,
        emission_per_second: u128,
        asset_addr: address
    ) {
        pool::update_emission(account, pool_address, rewarder_index, emission_per_second, asset_addr);
    }

    /// Transfer the authority of a rewarder.
    /// Params
    ///     - pool_address
    ///     - index
    ///     - new_authority
    /// Returns
    public entry fun transfer_rewarder_authority(
        account: &signer,
        pool_addr: address,
        rewarder_index: u8,
        new_authority: address
    ) {
        pool::transfer_rewarder_authority(account, pool_addr, rewarder_index, new_authority);
    }

    /// Accept the authority of a rewarder.
    /// Params
    ///     - pool_address
    ///     - index
    /// Returns
    public entry fun accept_rewarder_authority(
        account: &signer,
        pool_addr: address,
        rewarder_index: u8,
    ) {
        pool::accept_rewarder_authority(account, pool_addr, rewarder_index);
    }

    /// Create a partner.
    /// The partner is identified by name.
    /// Params
    ///     - fee_rate
    ///     - name: partner name.
    ///     - receiver: the partner authority to claim the partner fee.
    ///     - start_time: partner valid start time.
    ///     - end_time: partner valid end time.
    /// Returns
    public entry fun create_partner(
        account: &signer,
        name: String,
        fee_rate: u64,
        receiver: address,
        start_time: u64,
        end_time: u64
    ) {
        partner::create_partner(account, name, fee_rate, receiver, start_time, end_time);
    }

    /// Update the fee_rate of a partner.
    /// Params
    ///     - name
    ///     - new_fee_rate
    /// Returns
    public entry fun update_partner_fee_rate(protocol_authority: &signer, name: String, new_fee_rate: u64) {
        partner::update_fee_rate(protocol_authority, name, new_fee_rate);
    }

    /// Update the time of a partner.
    /// Params
    ///     - name
    ///     - start_time
    ///     - end_time
    /// Returns
    public entry fun update_partner_time(protocol_authority: &signer, name: String, start_time: u64, end_time: u64) {
        partner::update_time(protocol_authority, name, start_time, end_time);
    }

    /// Transfer the receiver of a partner.
    /// Params
    ///     - name
    ///     - new_receiver
    /// Returns
    public entry fun transfer_partner_receiver(account: &signer, name: String, new_recevier: address) {
        partner::transfer_receiver(account, name, new_recevier);
    }

    /// Accept the recevier of a partner.
    /// Params
    ///     - name
    /// Returns
    public entry fun accept_partner_receiver(account: &signer, name: String) {
        partner::accept_receiver(account, name);
    }

    /// Pause the Protocol.
    /// Params
    /// Returns
    public entry fun pause(protocol_authority: &signer) {
        config::pause(protocol_authority);
    }

    /// Unpause the Protocol.
    /// Params
    /// Returns
    public entry fun unpause(protocol_authority: &signer) {
        config::unpause(protocol_authority);
    }

    /// Pause an pool.
    /// Params
    ///     - pool_address: address
    /// Returns
    public entry fun pause_pool(protocol_authority: &signer, pool_address: address) {
        pool::pause(protocol_authority, pool_address);
    }

    /// Unpause an pool.
    /// Params
    ///     - pool_address: address
    /// Returns
    public entry fun unpause_pool(protocol_authority: &signer, pool_address: address) {
        pool::unpause(protocol_authority, pool_address);
    }

    /// Claim partner's ref fee
    /// Params
    ///     - account: The partner receiver account signer
    ///     - name: The partner name
    ///     - asset_type_addr: FungibleAsset type address
    /// Returns
    public entry fun claim_ref_fee(account: &signer, name: String, asset_type_addr: address) {
        partner::claim_ref_fee(account, name, asset_type_addr)
    }

    /// Init clmm acl
    /// Params
    ///    - account: The clmmpool deployer
    public entry fun init_clmm_acl(account: &signer) {
        config::init_clmm_acl(account)
    }

    /// Update the pool's position nft collection and token uri.
    /// Params
    ///     - account: The setter account signer
    ///     - pool_address: The pool address
    ///     - uri: The nft uri
    /// Returns
    public entry fun update_pool_uri(account: &signer, pool_address: address, uri: String) {
        pool::update_pool_uri(account, pool_address, uri)
    }

    /// Add role in clmm acl
    /// Params
    ///     - account: The protocol authority signer
    ///     - member: The role member address
    ///     - role: The role
    /// Returns
    public entry fun add_role(account: &signer, member: address, role: u8) {
        config::add_role(account, member, role)
    }

    /// Add role in clmm acl
    /// Params
    ///     - account: The protocol authority signer
    ///     - member: The role member address
    ///     - role: The role
    /// Returns
    public entry fun remove_role(account: &signer, member: address, role: u8) {
        config::remove_role(account, member, role)
    }
}
