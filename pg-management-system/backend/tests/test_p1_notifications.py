import uuid
from datetime import datetime, timezone
import pytest
from app.core.security import create_access_token, get_password_hash
from app.models.notification import Notification
from app.models.property import Company
from app.models.role import Role
from app.models.user import User


from app.main import app


@pytest.fixture
def db(client):
    session = app.state.testing_session()
    yield session
    session.close()


@pytest.fixture
def notif_test_context(db):
    company = Company(name="Notification Test Co", code="NOTIF_CO")
    db.add(company)
    db.flush()

    super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
    resident_role = Role(name="RESIDENT", display_name="Resident")
    db.add_all([super_admin_role, resident_role])
    db.flush()

    user_a = User(
        company_id=company.id,
        role_id=resident_role.id,
        email="usera@example.com",
        phone="9876543201",
        full_name="User Alpha",
        password_hash=get_password_hash("password123"),
        is_active=True,
    )
    user_b = User(
        company_id=company.id,
        role_id=resident_role.id,
        email="userb@example.com",
        phone="9876543202",
        full_name="User Beta",
        password_hash=get_password_hash("password123"),
        is_active=True,
    )
    db.add_all([user_a, user_b])
    db.flush()

    # User A notifications: 2 unread, 1 read
    n1 = Notification(
        user_id=user_a.id,
        title="Rent Due",
        body="Your rent for November is generated.",
        channel="PUSH",
        status="PENDING",
    )
    n2 = Notification(
        user_id=user_a.id,
        title="Maintenance Notice",
        body="Water tank cleaning today.",
        channel="PUSH",
        status="PENDING",
    )
    n3 = Notification(
        user_id=user_a.id,
        title="Welcome to PG",
        body="Welcome aboard Alpha!",
        channel="PUSH",
        status="READ",
    )

    # User B notification: 1 unread
    n4 = Notification(
        user_id=user_b.id,
        title="Beta Only",
        body="Confidential for Beta.",
        channel="PUSH",
        status="PENDING",
    )
    db.add_all([n1, n2, n3, n4])
    db.commit()

    token_a = create_access_token(subject=str(user_a.id), claims={"role": "RESIDENT"})
    token_b = create_access_token(subject=str(user_b.id), claims={"role": "RESIDENT"})

    return {
        "user_a": user_a,
        "user_b": user_b,
        "token_a": token_a,
        "token_b": token_b,
        "n1_id": str(n1.id),
        "n2_id": str(n2.id),
        "n3_id": str(n3.id),
        "n4_id": str(n4.id),
    }


def test_get_notifications_all_and_unread_only(client, notif_test_context):
    headers_a = {"Authorization": f"Bearer {notif_test_context['token_a']}"}

    # Fetch all for User A
    res = client.get("/api/v1/notifications", headers=headers_a)
    assert res.status_code == 200
    data = res.json()["data"]
    assert len(data) == 3
    # Check is_read boolean presence
    assert any(n["is_read"] is True for n in data)
    assert any(n["is_read"] is False for n in data)

    # Fetch unread only for User A
    res_unread = client.get("/api/v1/notifications?unread_only=true", headers=headers_a)
    assert res_unread.status_code == 200
    unread_data = res_unread.json()["data"]
    assert len(unread_data) == 2
    for n in unread_data:
        assert n["is_read"] is False
        assert n["status"] != "READ"


def test_unread_count(client, notif_test_context):
    headers_a = {"Authorization": f"Bearer {notif_test_context['token_a']}"}
    headers_b = {"Authorization": f"Bearer {notif_test_context['token_b']}"}

    res_a = client.get("/api/v1/notifications/unread-count", headers=headers_a)
    assert res_a.status_code == 200
    assert res_a.json()["data"]["unread_count"] == 2

    res_b = client.get("/api/v1/notifications/unread-count", headers=headers_b)
    assert res_b.status_code == 200
    assert res_b.json()["data"]["unread_count"] == 1


def test_mark_single_notification_read(client, notif_test_context):
    headers_a = {"Authorization": f"Bearer {notif_test_context['token_a']}"}
    n1_id = notif_test_context["n1_id"]

    res = client.patch(f"/api/v1/notifications/{n1_id}/read", headers=headers_a)
    assert res.status_code == 200
    assert res.json()["data"]["is_read"] is True

    # Check unread count dropped to 1
    res_count = client.get("/api/v1/notifications/unread-count", headers=headers_a)
    assert res_count.json()["data"]["unread_count"] == 1


def test_mark_notification_read_cross_user_forbidden(client, notif_test_context):
    headers_b = {"Authorization": f"Bearer {notif_test_context['token_b']}"}
    n1_id = notif_test_context["n1_id"]  # belongs to User A

    res = client.patch(f"/api/v1/notifications/{n1_id}/read", headers=headers_b)
    assert res.status_code in (403, 404)


def test_mark_all_notifications_read(client, notif_test_context):
    headers_a = {"Authorization": f"Bearer {notif_test_context['token_a']}"}
    headers_b = {"Authorization": f"Bearer {notif_test_context['token_b']}"}

    res = client.post("/api/v1/notifications/read-all", headers=headers_a)
    assert res.status_code == 200
    assert res.json()["data"]["updated_count"] == 2

    # User A unread count is now 0
    res_a = client.get("/api/v1/notifications/unread-count", headers=headers_a)
    assert res_a.json()["data"]["unread_count"] == 0

    # User B still has 1 unread notification (isolation maintained)
    res_b = client.get("/api/v1/notifications/unread-count", headers=headers_b)
    assert res_b.json()["data"]["unread_count"] == 1
