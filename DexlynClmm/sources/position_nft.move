/// The user position authority is represented by the token. User who own the token control the position.
/// Every pool has a collection, so all positions of this pool belongs to this collection.
/// The position unique index in a pool is stored in the token property map.
/// The `TOKEN_BURNABLE_BY_OWNER` is stored in every position default property_map, so the creator can burn the token when the liquidity of the position is zero.
module dexlyn_clmm::position_nft {
    use std::option::Option;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_std::bcs;
    use aptos_std::from_bcs;
    use aptos_framework::object::{Self, Object};

    use aptos_token_objects::collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token;
    use supra_framework::event;
    use supra_framework::fungible_asset::{Self, Metadata};
    use supra_framework::object::address_to_object;
    use supra_framework::timestamp;

    use dexlyn_clmm::utils;

    friend dexlyn_clmm::pool;

    /// The tick is invalid
    const ENFT_DOES_NOT_EXIST: u64 = 1;

    const KEY_POSITION_INDEX: vector<u8> = b"position_index";
    const KEY_TOKEN_CREATOR: vector<u8> = b"token_creator";
    const KEY_TICK_LOWER: vector<u8> = b"tick_lower";
    const KEY_TICK_UPPER: vector<u8> = b"tick_upper";
    const KEY_LIQUIDITY: vector<u8> = b"liquidity";
    const KEY_TOKEN_A_ADDRESS: vector<u8> = b"token_a_address";
    const KEY_TOKEN_B_ADDRESS: vector<u8> = b"token_b_address";
    const KEY_CREATION_TIMESTAMP: vector<u8> = b"creation_timestamp";

    struct PositionNFTObjectController has key {
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        extend_ref: object::ExtendRef,
        property_mutator_ref: property_map::MutatorRef,
    }

    struct CollectionController has key {
        mutator_ref: collection::MutatorRef,
        extend_ref: object::ExtendRef,
    }

    struct NFTDetails has copy, drop, store {
        pool_address: address,
        position_index: u64,
        tick_lower: u64,
        tick_upper: u64,
        liquidity: u128,
    }

    #[event]
    struct CreateCollectionEvent has drop, store {
        creator: address,
        collection_name: String,
        pool_address: address,
        collection_address: address,
        timestamp: u64,
    }

    #[event]
    struct NFTMintEvent has drop, store {
        creator: address,
        receiver: address,
        token_address: address,
        pool_address: address,
        position_index: u64,
        tick_lower: u64,
        tick_upper: u64,
        timestamp: u64,
    }

    #[event]
    struct NFTBurnEvent has drop, store {
        creator: address,
        owner: address,
        token_address: address,
        pool_address: address,
        position_index: u64,
        timestamp: u64,
    }


    /// Create position NFT collection
    /// Params
    ///     - creator: The creator(pool resrouce account).
    ///     - tick_spacing: The pool tick spacing.
    ///     - description: The collection description.
    ///     - uri: The NFT collection uri.
    ///     - asset_a_addr: FungibleAsset A address
    ///     - asset_b_addr: FungibleAsset B address
    public fun create_collection(
        creator: &signer,
        tick_spacing: u64,
        description: String,
        uri: String,
        royalty: Option<Royalty>,
        asset_a_addr: address,
        asset_b_addr: address,
    ): String {
        let collection_name = collection_name(tick_spacing, asset_a_addr, asset_b_addr);

        // Create collection
        let collection_constructor_ref = collection::create_unlimited_collection(
            creator,
            description,
            collection_name,
            royalty,
            uri
        );

        let mutator_ref = collection::generate_mutator_ref(&collection_constructor_ref);
        let extend_ref = object::generate_extend_ref(&collection_constructor_ref);
        let collection_signer = object::generate_signer(&collection_constructor_ref);

        move_to(&collection_signer, CollectionController {
            mutator_ref,
            extend_ref
        });

        event::emit(CreateCollectionEvent {
            creator: signer::address_of(creator),
            collection_name,
            pool_address: signer::address_of(creator),
            collection_address: object::address_from_constructor_ref(&collection_constructor_ref),
            timestamp: timestamp::now_seconds(),
        });
        collection_name
    }

    /// Mint Position NFT .
    /// Params
    ///     - user: The nft receiver
    ///     - creator: The creator
    ///     - pool_index: The pool index
    ///     - position_index: The position index
    ///     - pool_uri: The pool uri
    ///     - collection: The nft collection
    ///     - min_tick: The minimum tick of the position
    ///     - max_tick: The maximum tick of the position
    ///     - liquidity: The initial liquidity of the position
    ///     - token_a_address: The FA address of token A
    ///     - token_b_address: The FA address of token B
    /// Return
    public(friend) fun mint(
        creator: &signer,
        receiver: &signer,
        pool_index: u64,
        position_index: u64,
        pool_uri: String,
        collection_name: String,
        tick_lower: u64,
        tick_upper: u64,
        liquidity: u128,
        asset_a_addr: address,
        asset_b_addr: address,
        royalty: Option<Royalty>
    ) {
        let token_name = position_name(pool_index, position_index);
        let token_description = string::utf8(b"Dexlyn CLMM Position NFT");
        let creation_time = timestamp::now_seconds();


        // Create token with Digital Asset Standard
        let constructor_ref = token::create_named_token(
            creator,
            collection_name,
            token_description,
            token_name,
            royalty,
            pool_uri,
        );

        property_map::init(&constructor_ref, property_map::prepare_input(vector[], vector[], vector[]));


        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let property_mutator_ref = property_map::generate_mutator_ref(&constructor_ref);


        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(KEY_POSITION_INDEX),
            bcs::to_bytes(&position_index)
        );
        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(KEY_TOKEN_CREATOR),
            bcs::to_bytes(creator)
        );
        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(KEY_TICK_LOWER),
            bcs::to_bytes(&tick_lower)
        );
        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(KEY_TICK_UPPER),
            bcs::to_bytes(&tick_upper)
        );
        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(KEY_LIQUIDITY),
            bcs::to_bytes(&liquidity)
        );
        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(KEY_TOKEN_A_ADDRESS),
            bcs::to_bytes(&asset_a_addr)
        );
        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(KEY_TOKEN_B_ADDRESS),
            bcs::to_bytes(&asset_b_addr)
        );
        property_map::add_typed(
            &property_mutator_ref,
            string::utf8(KEY_CREATION_TIMESTAMP),
            bcs::to_bytes(&creation_time)
        );

        let constructor_addr = object::address_from_constructor_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);

        // Store PositionNFTObjectController resource at the object
        move_to(&object_signer, PositionNFTObjectController {
            mutator_ref,
            burn_ref,
            extend_ref,
            property_mutator_ref,
        });

        let token = object::address_to_object<PositionNFTObjectController>(constructor_addr);
        object::transfer(creator, token, signer::address_of(receiver));

        event::emit(NFTMintEvent {
            creator: signer::address_of(creator),
            receiver: signer::address_of(receiver),
            token_address: object::object_address(&token),
            pool_address: signer::address_of(creator),
            position_index,
            tick_lower,
            tick_upper,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update liquidity of a position NFT
    /// Params
    ///     - creator: The nft creator
    ///     - collection_name: The collection name
    ///     - pool_index: The pool index
    ///     - position_index: The position index
    ///     - new_liquidity: The new liquidity value
    public(friend) fun update_liquidity(
        creator: &signer,
        collection_name: String,
        pool_index: u64,
        position_index: u64,
        new_liquidity: u128
    ) acquires PositionNFTObjectController {
        let token_obj = get_position_nft_object(
            pool_index,
            position_index,
            signer::address_of(creator),
            collection_name
        );
        let position_nft = borrow_global<PositionNFTObjectController>(object::object_address(&token_obj));

        // Update the liquidity property
        property_map::update_typed(
            &position_nft.property_mutator_ref,
            &string::utf8(KEY_LIQUIDITY),
            bcs::to_bytes(&new_liquidity)
        );
    }

    fun get_position_nft_object(
        pool_index: u64,
        position_index: u64,
        creator_address: address,
        collection_name: String
    ): Object<PositionNFTObjectController> {
        let token_name = position_name(pool_index, position_index);
        let token_address = token::create_token_address(
            &creator_address,
            &collection_name,
            &token_name
        );
        assert!(exists<PositionNFTObjectController>(token_address), ENFT_DOES_NOT_EXIST);
        object::address_to_object<PositionNFTObjectController>(token_address)
    }

    #[view]
    public fun is_position_nft_owner(
        creator_address: address,
        owner: address,
        collection_name: String,
        pool_index: u64,
        position_index: u64
    ): bool {
        let token = get_position_nft_object(pool_index, position_index, creator_address, collection_name);
        object::is_owner<PositionNFTObjectController>(token, owner)
    }

    /// Burn Position NFT .
    /// Params
    ///     - creator: The nft creator
    ///     - user: The nft owner
    ///     - collection_name
    ///     - pool_index: The pool index
    ///     - pos_index: The position index
    /// Return
    public(friend) fun burn_by_collection_and_index(
        creator: &signer,
        owner: address,
        collection_name: String,
        pool_index: u64,
        position_index: u64
    ) acquires PositionNFTObjectController {
        let token_obj = get_position_nft_object(
            pool_index,
            position_index,
            signer::address_of(creator),
            collection_name
        );

        let position_nft = move_from<PositionNFTObjectController>(object::object_address(&token_obj));
        let PositionNFTObjectController { mutator_ref: _, burn_ref, extend_ref: _, property_mutator_ref } = position_nft;

        property_map::remove(&property_mutator_ref, &string::utf8(KEY_POSITION_INDEX));
        property_map::remove(&property_mutator_ref, &string::utf8(KEY_TOKEN_CREATOR));
        property_map::remove(&property_mutator_ref, &string::utf8(KEY_TICK_LOWER));
        property_map::remove(&property_mutator_ref, &string::utf8(KEY_TICK_UPPER));
        property_map::remove(&property_mutator_ref, &string::utf8(KEY_LIQUIDITY));
        property_map::remove(&property_mutator_ref, &string::utf8(KEY_TOKEN_A_ADDRESS));
        property_map::remove(&property_mutator_ref, &string::utf8(KEY_TOKEN_B_ADDRESS));
        property_map::remove(&property_mutator_ref, &string::utf8(KEY_CREATION_TIMESTAMP));

        token::burn(burn_ref);

        event::emit(NFTBurnEvent {
            creator: signer::address_of(creator),
            owner,
            token_address: object::object_address(&token_obj),
            pool_address: signer::address_of(creator),
            position_index,
            timestamp: timestamp::now_seconds(),
        })
    }

    #[view]
    /// Generate the position nft name
    /// Params
    ///     - pool_index
    ///     - index: position index.
    /// Return
    ///     - string: position_name
    public fun position_name(
        pool_index: u64,
        position_index: u64
    ): String {
        let name = string::utf8(b"Dexlyn LP | Pool");
        string::append(&mut name, utils::str(pool_index));
        string::append_utf8(&mut name, b"-");
        string::append(&mut name, utils::str(position_index));
        name
    }

    #[view]
    /// Generate the Position Token Collection Unique Name.
    /// "Dexlyn Position  | tokenA-tokenB_tick(#)"
    /// Params
    ///     - tick_spacing
    ///     - asset_a_addr: FungibleAsset A address
    ///     - asset_b_addr: FungibleAsset B address
    /// Return
    ///     - string: collection_name
    public fun collection_name(
        tick_spacing: u64,
        asset_a_addr: address,
        asset_b_addr: address
    ): String {
        let asset_a_object = address_to_object<Metadata>(asset_a_addr);
        let asset_b_object = address_to_object<Metadata>(asset_b_addr);
        let collect_name = string::utf8(b"Dexlyn Position | ");
        string::append(&mut collect_name, fungible_asset::symbol(asset_a_object));
        string::append_utf8(&mut collect_name, b"-");
        string::append(&mut collect_name, fungible_asset::symbol(asset_b_object));
        string::append_utf8(&mut collect_name, b"_tick(");
        string::append(&mut collect_name, utils::str(tick_spacing));
        string::append_utf8(&mut collect_name, b")");
        collect_name
    }

    #[view]
    /// Returns the NFT details from token address.
    public fun get_nft_details(token_addresses: vector<address>): vector<NFTDetails> {
        let nft_vector = vector::empty<NFTDetails>();
        vector::for_each(token_addresses, |token_address| {
            let token_obj = object::address_to_object<PositionNFTObjectController>(token_address);
            assert!(exists<PositionNFTObjectController>(token_address), ENFT_DOES_NOT_EXIST);

            let pool_address = from_bcs::to_address(property_map::read_bytes<PositionNFTObjectController>(
                &token_obj,
                &string::utf8(KEY_TOKEN_CREATOR)
            ));
            let position_index = from_bcs::to_u64(property_map::read_bytes<PositionNFTObjectController>(
                &token_obj,
                &string::utf8(KEY_POSITION_INDEX)
            ));
            let tick_lower = from_bcs::to_u64(property_map::read_bytes<PositionNFTObjectController>(
                &token_obj,
                &string::utf8(KEY_TICK_LOWER)
            ));
            let tick_upper = from_bcs::to_u64(property_map::read_bytes<PositionNFTObjectController>(
                &token_obj,
                &string::utf8(KEY_TICK_UPPER)
            ));
            let liquidity = from_bcs::to_u128(property_map::read_bytes<PositionNFTObjectController>(
                &token_obj,
                &string::utf8(KEY_LIQUIDITY)
            ));
            vector::push_back(&mut nft_vector, NFTDetails {
                pool_address,
                position_index,
                tick_lower,
                tick_upper,
                liquidity,
            });
        });
        nft_vector
    }

    public fun get_nft_details_struct(details: &NFTDetails): (address, u64, u64, u64, u128) {
        (details.pool_address, details.position_index, details.tick_lower, details.tick_upper, details.liquidity)
    }

    #[view]
    /// Check if the NFT is valid or not.
    public fun is_valid_nft(
        token_address: address,
        pool_address: address,
    ): bool
    {
        let token_obj = object::address_to_object<PositionNFTObjectController>(token_address);
        assert!(exists<PositionNFTObjectController>(token_address), ENFT_DOES_NOT_EXIST);

        let token_creator = from_bcs::to_address(property_map::read_bytes<PositionNFTObjectController>(
            &token_obj,
            &string::utf8(KEY_TOKEN_CREATOR)
        ));
        token_creator == pool_address
    }

    public fun mutate_collection_uri(_creator: &signer, _collection: String, _uri: String) {}
}
