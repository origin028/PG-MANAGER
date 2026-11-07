import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
import pytest
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User


@pytest.fixture
def db(client):
    session = app.state.testing_session()
    yield session
    session.close()


@pytest.fixture
def receipt_test_context(db):
    company = Company(name="PDF Receipt Test Co", code="PDF_CO")
    db.add(company)
    db.flush()

    resident_role = Role(name="RESIDENT", display_name="Resident")
    db.add(resident_role)
    db.flush()

    property_1 = Property(
        company_id=company.id,
        name="Serenity PG",
        code="PROP_SERENITY",
        address_line1="123 Lake View Rd",
        city="Bengaluru",
        state="Karnataka",
        pincode="560100",
    )
    db.add(property_1)
    db.flush()

    room = Room(
        property_id=property_1.id,
        room_number="301",
        floor=3,
        room_type="SINGLE",
        base_rent=Decimal("8000.00"),
    )
    db.add(room)
    db.flush()

    user_alice = User(
        company_id=company.id,
        role_id=resident_role.id,
        email="alice@example.com",
        phone="9876543301",
        full_name="Alice Smith",
        password_hash=get_password_hash("password123"),
        is_active=True,
        approval_status="APPROVED",
    )
    user_bob = User(
        company_id=company.id,
        role_id=resident_role.id,
        email="bob@example.com",
        phone="9876543302",
        full_name="Bob Jones",
        password_hash=get_password_hash("password123"),
        is_active=True,
        approval_status="APPROVED",
    )
    db.add_all([user_alice, user_bob])
    db.flush()

    resident_alice = Resident(
        user_id=user_alice.id,
        property_id=property_1.id,
        room_id=room.id,
        status="ACTIVE",
        check_in_date=date(2026, 1, 1),
    )
    resident_bob = Resident(
        user_id=user_bob.id,
        property_id=property_1.id,
        status="ACTIVE",
        check_in_date=date(2026, 1, 1),
    )
    db.add_all([resident_alice, resident_bob])
    db.flush()

    invoice = Invoice(
        property_id=property_1.id,
        resident_id=resident_alice.id,
        invoice_number="INV-2026-11-999",
        billing_month="2026-11",
        amount=Decimal("8000.00"),
        paid_amount=Decimal("8000.00"),
        status="PAID",
        invoice_type="RENT",
        due_date=date(2026, 11, 5),
    )
    db.add(invoice)
    db.flush()

    payment = Payment(
        property_id=property_1.id,
        resident_id=resident_alice.id,
        invoice_id=invoice.id,
        payment_number="PAY-2026-11-999",
        amount=Decimal("8000.00"),
        payment_mode="UPI",
        status="SUCCESS",
        gateway_payment_id="UPI-99998888",
        paid_at=datetime.now(timezone.utc),
    )
    db.add(payment)
    db.flush()

    receipt = Receipt(
        invoice_id=invoice.id,
        payment_id=payment.id,
        receipt_number="REC-2026-11-0099",
        amount=Decimal("8000.00"),
        issued_at=datetime.now(timezone.utc),
    )
    db.add(receipt)
    db.commit()

    token_alice = create_access_token(subject=str(user_alice.id), claims={"role": "RESIDENT"})
    token_bob = create_access_token(subject=str(user_bob.id), claims={"role": "RESIDENT"})

    return {
        "receipt_id": str(receipt.id),
        "token_alice": token_alice,
        "token_bob": token_bob,
    }


def test_download_receipt_pdf_success(client, receipt_test_context):
    headers = {"Authorization": f"Bearer {receipt_test_context['token_alice']}"}
    receipt_id = receipt_test_context["receipt_id"]

    res = client.get(f"/api/v1/receipts/{receipt_id}/pdf", headers=headers)
    assert res.status_code == 200
    assert res.headers["content-type"] == "application/pdf"
    assert "attachment; filename=" in res.headers["content-disposition"]
    # PDF magic bytes
    assert res.content.startswith(b"%PDF-")


def test_download_receipt_pdf_cross_resident_forbidden(client, receipt_test_context):
    # Bob tries to download Alice's receipt
    headers = {"Authorization": f"Bearer {receipt_test_context['token_bob']}"}
    receipt_id = receipt_test_context["receipt_id"]

    res = client.get(f"/api/v1/receipts/{receipt_id}/pdf", headers=headers)
    assert res.status_code == 403


def test_download_receipt_pdf_nonexistent_not_found(client, receipt_test_context):
    headers = {"Authorization": f"Bearer {receipt_test_context['token_alice']}"}
    fake_id = str(uuid.uuid4())

    res = client.get(f"/api/v1/receipts/{fake_id}/pdf", headers=headers)
    assert res.status_code == 404
