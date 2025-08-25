module dexlyn_clmm::utils {
    use std::bcs;
    use std::string::{Self, String};
    use std::vector;
    use aptos_std::comparator;
    use aptos_std::type_info;

    use supra_framework::coin::{Self, zero};
    use supra_framework::fungible_asset;
    use supra_framework::object;

    #[view]
    public fun compare_address(a: address, b: address): comparator::Result {
        let a_bytes = bcs::to_bytes(&a);
        let b_bytes = bcs::to_bytes(&b);
        comparator::compare_u8_vector(a_bytes, b_bytes)
    }

    #[view]
    public fun str(num: u64): String {
        if (num == 0) {
            return string::utf8(b"0")
        };
        let remainder: u8;
        let digits = vector::empty<u8>();
        while (num > 0) {
            remainder = (num % 10 as u8);
            num = num / 10;
            vector::push_back(&mut digits, remainder + 48);
        };
        vector::reverse(&mut digits);
        string::utf8(digits)
    }

    #[view]
    public fun compare_coin<CoinTypeA, CoinTypeB>(): comparator::Result {
        let type_info_a = type_info::type_of<CoinTypeA>();
        let type_info_b = type_info::type_of<CoinTypeB>();
        comparator::compare<type_info::TypeInfo>(&type_info_a, &type_info_b)
    }

    #[view]
    public fun coin_to_fa_address<CoinType>(): address {
        let fungible_asset = coin::coin_to_fungible_asset<CoinType>(zero<CoinType>());
        let asset_metadata = fungible_asset::metadata_from_asset(&fungible_asset);
        fungible_asset::destroy_zero(fungible_asset);
        object::object_address(&asset_metadata)
    }
}