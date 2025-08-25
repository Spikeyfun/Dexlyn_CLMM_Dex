#[test_only]
module dexlyn_clmm::acl_test {
    use dexlyn_clmm::acl;

    struct TestACL has key {
        acl: acl::ACL
    }


    #[test(dummy = @0x1234)]
    public fun test_add_and_has_role(dummy: signer) {
        let acl = acl::new();
        let member: address = @0x1;
        let role: u8 = 1;
        acl::add_role(&mut acl, member, role);
        assert!(acl::has_role(&acl, member, role), 100);
        assert!(!acl::has_role(&acl, member, 2), 101);

        move_to(&dummy, TestACL { acl });
    }

    #[test(dummy = @0x1234)]
    public fun test_remove_role(dummy: signer) {
        let acl = acl::new();
        let member: address = @0x2;
        let role: u8 = 3;
        acl::add_role(&mut acl, member, role);
        assert!(acl::has_role(&acl, member, role), 200);
        acl::remove_role(&mut acl, member, role);
        assert!(!acl::has_role(&acl, member, role), 201);

        move_to(&dummy, TestACL { acl });
    }

    #[test(dummy = @0x1234)]
    public fun test_set_roles(dummy: signer) {
        let acl = acl::new();
        let member: address = @0x3;
        let permissions: u128 = 0xA; // roles 1 and 3 (1010)
        acl::set_roles(&mut acl, member, permissions);
        assert!(!acl::has_role(&acl, member, 0), 300);
        assert!(acl::has_role(&acl, member, 1), 301);
        assert!(!acl::has_role(&acl, member, 2), 302);
        assert!(acl::has_role(&acl, member, 3), 303);

        move_to(&dummy, TestACL { acl });
    }

    #[test(dummy = @0x1234)]
    fun test_end_to_end(dummy: signer) {
        let acl = acl::new();
        acl::add_role(&mut acl, @0x1234, 12);
        acl::add_role(&mut acl, @0x1234, 99);
        acl::add_role(&mut acl, @0x1234, 88);
        acl::add_role(&mut acl, @0x1234, 123);
        acl::add_role(&mut acl, @0x1234, 2);
        acl::add_role(&mut acl, @0x1234, 1);
        acl::remove_role(&mut acl, @0x1234, 2);
        acl::set_roles(&mut acl, @0x5678, (1 << 123) | (1 << 2) | (1 << 1));
        let i = 0;
        while (i < 128) {
            let has = acl::has_role(&acl, @0x1234, i);
            assert!(if (i == 12 || i == 99 || i == 88 || i == 123 || i == 1) has else !has, 0);
            has = acl::has_role(&acl, @0x5678, i);
            assert!(if (i == 123 || i == 2 || i == 1) has else !has, 1);
            i = i + 1;
        };

        // can't drop so must store
        move_to(&dummy, TestACL { acl });
    }
}