from app.core.permissions import RoleEnum, has_permission, is_role_allowed


def test_super_admin_permissions():
    assert has_permission(RoleEnum.SUPER_ADMIN, "any:permission:key") is True
    assert has_permission(RoleEnum.SUPER_ADMIN, "properties:read") is True


def test_property_manager_permissions():
    assert has_permission(RoleEnum.PROPERTY_MANAGER, "properties:read") is True
    assert has_permission(RoleEnum.PROPERTY_MANAGER, "rooms:manage") is True
    assert has_permission(RoleEnum.PROPERTY_MANAGER, "audit:purge") is False


def test_resident_permissions():
    assert has_permission(RoleEnum.RESIDENT, "bed:self") is True
    assert has_permission(RoleEnum.RESIDENT, "invoices:self") is True
    assert has_permission(RoleEnum.RESIDENT, "rooms:manage") is False


def test_role_allowed():
    assert is_role_allowed(RoleEnum.SUPER_ADMIN, ["SUPER_ADMIN", "PROPERTY_MANAGER"]) is True
    assert is_role_allowed(RoleEnum.RESIDENT, ["SUPER_ADMIN", "PROPERTY_MANAGER"]) is False
