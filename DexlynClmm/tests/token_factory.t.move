#[test_only]
module dexlyn_clmm::token_factory {

    use std::option;
    use std::signer::address_of;
    use std::string;
    use std::string::{bytes, String};
    use std::vector;
    use aptos_std::table::Table;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{BurnRef, FungibleAsset, Metadata, MintRef, TransferRef};
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, Object, object_exists};
    use aptos_framework::primary_fungible_store;

    // ============== Constants ================ //
    const TOKEN_SEED: vector<u8> = b"DEXLYN";
    const ASSET_SEED: vector<u8> = b"DEXLYNSWAP_OBJ";
    const MAX_DECIMALS: u8 = 18;
    const MAX_URI_LENGTH: u64 = 256;

    // ============== Errors ================ //
    /// User is not an owner
    const E_NOT_AN_OWNER: u64 = 0;
    /// Token is already exists
    const E_TOKEN_ALREADY_EXISIS: u64 = 1;
    /// Invalid decimal count (<= 18)
    const E_INVALID_DECIMALS: u64 = 2;
    /// Invalid uri length (<= 256)
    const E_INVALID_URI_LENGTH: u64 = 3;

    struct TokenInfo has key {
        owner: address,
        name: String,
        symbol: String,
        token: address,
        created_at: u64
    }

    struct TokenRegistry has key {
        tokens: Table<address, TokenInfo>,
        total_tokens: u64
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ManageFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        admin: address
    }

    /// Initialize token
    public fun initialize_token(
        owner: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        icon_uri: String,
        project_uri: String
    ): (address, address, Object<Metadata>) {
        // Validate input parameters
        validate_token_parameters(decimals, &icon_uri, &project_uri);

        let owner_addr = address_of(owner);
        let token_seed = bytes(&name);

        // Check if token already exusts for this owner
        let token_addr = get_token_object_addr(owner_addr, *token_seed);
        assert!(!object_exists<Metadata>(token_addr), E_TOKEN_ALREADY_EXISIS);
        let constuctor_ref = &create_object_by_seed(owner, *token_seed);

        // Create primary store and metadata
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constuctor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri
        );

        // Generate and store management references
        let mint_ref = fungible_asset::generate_mint_ref(constuctor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constuctor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constuctor_ref);
        let metadata_object_signer = object::generate_signer(constuctor_ref);

        move_to(&metadata_object_signer, ManageFungibleAsset {
            mint_ref,
            burn_ref,
            transfer_ref,
            admin: owner_addr
        });

        let token = get_token_metadata(owner_addr, name);
        (owner_addr, token_addr, token)
    }


    /// Mint custom token
    public fun mint_token(
        owner: &signer,
        to: address,
        token_name: String,
        amount: u64
    ) acquires ManageFungibleAsset {
        let owner_addr = address_of(owner);
        let asset = get_token_metadata(owner_addr, token_name);

        let metadata = authorized_borrow_metadata_refs(owner_addr, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);

        let token = fungible_asset::mint(&metadata.mint_ref, amount);
        fungible_asset::deposit_with_ref(&metadata.transfer_ref, to_wallet, token);
    }

    /// Transfer custom token
    public fun transfer_token(
        owner: &signer,
        from: address,
        to: address,
        token_name: String,
        amount: u64
    ) acquires ManageFungibleAsset {
        let owner_addr = address_of(owner);
        let asset = get_token_metadata(owner_addr, token_name);

        let transfer_ref = &authorized_borrow_metadata_refs(owner_addr, asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);

        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::transfer_with_ref(transfer_ref, from_wallet, to_wallet, amount);
    }

    /// Burn custom token
    public fun burn_token(owner: &signer, from: address, token_name: String, amount: u64) acquires ManageFungibleAsset {
        let owner_addr = address_of(owner);
        let asset = get_token_metadata(owner_addr, token_name);

        let burn_ref = &authorized_borrow_metadata_refs(owner_addr, asset).burn_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, amount);
    }

    /// Freeze custom token
    public fun freeze_account(owner: &signer, token_name: String, account: address) acquires ManageFungibleAsset {
        let owner_addr = address_of(owner);
        let asset = get_token_metadata(owner_addr, token_name);

        let transfer_ref = &authorized_borrow_metadata_refs(owner_addr, asset).transfer_ref;
        let wallet = primary_fungible_store::ensure_primary_store_exists(account, asset);
        fungible_asset::set_frozen_flag(transfer_ref, wallet, true);
    }

    /// Unfreeze custom token
    public fun unfreeze_account(owner: &signer, token_name: String, account: address) acquires ManageFungibleAsset {
        let owner_addr = address_of(owner);
        let asset = get_token_metadata(owner_addr, token_name);

        let transfer_ref = &authorized_borrow_metadata_refs(owner_addr, asset).transfer_ref;
        let wallet = primary_fungible_store::ensure_primary_store_exists(account, asset);
        fungible_asset::set_frozen_flag(transfer_ref, wallet, false);
    }

    /// Deposite custom token
    public fun deposit(
        owner: &signer,
        to: address,
        token_name: String,
        token: FungibleAsset
    ) acquires ManageFungibleAsset {
        let owner_addr = address_of(owner);
        let asset = get_token_metadata(owner_addr, token_name);

        let transfer_ref = &authorized_borrow_metadata_refs(owner_addr, asset).transfer_ref;
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::deposit_with_ref(transfer_ref, to_wallet, token);
    }

    // ================ View ============ //
    #[view]
    public fun get_token_metadata(user_addr: address, suffix: String): Object<Metadata> {
        let asset_addr = get_token_object_addr(user_addr, *bytes(&suffix));
        object::address_to_object<Metadata>(asset_addr)
    }

    #[view]
    public fun get_token_address(user_addr: address, suffix: String): address {
        let address = get_token_object_addr(user_addr, *bytes(&suffix));
        address
    }

    // ================ Helpers ============ //
    /// Generate token object creation seed
    fun generate_token_object_seed(suffix: vector<u8>): vector<u8> {
        let seed = TOKEN_SEED;
        vector::append(&mut seed, suffix);
        seed
    }

    /// Create the token object from seed
    public fun create_object_by_seed(user: &signer, suffix: vector<u8>): ConstructorRef {
        object::create_named_object(user, generate_token_object_seed(suffix))
    }

    /// Get the token object address
    public fun get_token_object_addr(user_addr: address, name: vector<u8>): address {
        object::create_object_address(&user_addr, generate_token_object_seed(name))
    }

    /// Assert if user is not a owner of token
    public fun assert_is_objet_owner<T: key>(owner_addr: address, asset: Object<T>) {
        assert!(object::is_owner<T>(asset, owner_addr), E_NOT_AN_OWNER);
    }

    /// Validate the token authority
    inline fun authorized_borrow_metadata_refs(owner_addr: address, asset: Object<Metadata>):
    &ManageFungibleAsset {
        assert_is_objet_owner<Metadata>(owner_addr, asset);
        borrow_global_mut<ManageFungibleAsset>(object::object_address(&asset))
    }

    /// Validate the token creation perameters
    fun validate_token_parameters(
        decimals: u8,
        icon_uri: &String,
        project_uri: &String
    ) {
        assert!(decimals <= MAX_DECIMALS, E_INVALID_DECIMALS);
        assert!(string::length(icon_uri) <= MAX_URI_LENGTH, E_INVALID_URI_LENGTH);
        assert!(string::length(project_uri) <= MAX_URI_LENGTH, E_INVALID_URI_LENGTH);
    }

    // ================ Test ============ //
    #[test_only]
    public fun get_token_balance(owner: &signer, addr: address, suffix: String): u64 {
        let owner_addr = address_of(owner);
        let asset = get_token_metadata(owner_addr, suffix);
        assert_is_objet_owner<Metadata>(owner_addr, asset);
        let wallet = primary_fungible_store::primary_store(addr, asset);
        fungible_asset::balance(wallet)
    }
}
