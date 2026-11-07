import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
import pytest
import sqlalchemy as sa
from urllib.parse import parse_qs, urlparse

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.bed import Bed
from app.models.user import User, UserPropertyAccess


def make_token_header(user_id: uuid.UUID, role_name: str, company_id: uuid.UUID) -> dict:
    token = create_access_token(
        subject=str(user_id),
        claims={
            "role": role_name,
            "company_id": str(company_id),
            "client_type": "resident_mobile" if role_name == "RESIDENT" else "admin_web",
        },
    )
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def upi_test_context(client):
    """Seeds test context with company, properties, roles, active residents, manager, and invoices."""
    db = client.app.state.testing_session()
    try:
        company = Company(name="Origin Stays Co", code="ORIGIN_UPI")
        db.add(company)
        db.flush()

        role_admin = Role(name="SUPER_ADMIN", display_name="Super Admin")
        role_pm = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        role_res = Role(name="RESIDENT", display_name="Resident")
        db.add_all([role_admin, role_pm, role_res])
        db.flush()

        prop = Property(
            company_id=company.id,
            name="Origin Heights PG",
            code="ORIGIN_H1",
            address_line1="100 Brigade Road",
            pincode="560025",
            is_active=True,
        )
        prop_other = Property(
            company_id=company.id,
            name="Origin Other PG",
            code="ORIGIN_H2",
            address_line1="200 Indiranagar",
            pincode="560038",
            is_active=True,
        )
        db.add_all([prop, prop_other])
        db.flush()

        # Manager
        manager_user = User(
            company_id=company.id,
            role_id=role_pm.id,
            email="manager_upi@origin.com",
            phone="9876599001",
            full_name="Manager Mike",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            approval_status="APPROVED",
        )
        db.add(manager_user)
        db.flush()
        db.add(UserPropertyAccess(user_id=manager_user.id, property_id=prop.id, access_level="MANAGER"))

        # Resident 1 (Approved & Active)
        res1_user = User(
            company_id=company.id,
            role_id=role_res.id,
            email="resident1@origin.com",
            phone="9876599002",
            full_name="Alice Resident",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            approval_status="APPROVED",
        )
        # Resident 2 (Approved & Active)
        res2_user = User(
            company_id=company.id,
            role_id=role_res.id,
            email="resident2@origin.com",
            phone="9876599003",
            full_name="Bob Resident",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            approval_status="APPROVED",
        )
        # Resident 3 (Pending Approval)
        res3_user = User(
            company_id=company.id,
            role_id=role_res.id,
            email="resident3@origin.com",
            phone="9876599004",
            full_name="Charlie Pending",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            approval_status="PENDING_APPROVAL",
        )
        db.add_all([res1_user, res2_user, res3_user])
        db.flush()

        res1 = Resident(
            user_id=res1_user.id,
            property_id=prop.id,
            check_in_date=date(2026, 1, 1),
            monthly_rent=Decimal("12000.00"),
            security_deposit=Decimal("20000.00"),
            status="ACTIVE",
            kyc_status="VERIFIED",
        )
        res2 = Resident(
            user_id=res2_user.id,
            property_id=prop.id,
            check_in_date=date(2026, 1, 1),
            monthly_rent=Decimal("10000.00"),
            security_deposit=Decimal("15000.00"),
            status="ACTIVE",
            kyc_status="VERIFIED",
        )
        res3 = Resident(
            user_id=res3_user.id,
            property_id=prop.id,
            check_in_date=date(2026, 1, 1),
            monthly_rent=Decimal("10000.00"),
            security_deposit=Decimal("15000.00"),
            status="PENDING_APPROVAL",
            kyc_status="PENDING",
        )
        db.add_all([res1, res2, res3])
        db.flush()

        # Invoices for Resident 1
        inv_payable = Invoice(
            property_id=prop.id,
            resident_id=res1.id,
            invoice_number="INV-UPI-001",
            billing_month="2026-11",
            invoice_type="RENT",
            amount=Decimal("12000.00"),
            paid_amount=Decimal("0.00"),
            due_date=date(2026, 11, 5),
            status="PENDING",
        )
        inv_partial = Invoice(
            property_id=prop.id,
            resident_id=res1.id,
            invoice_number="INV-UPI-002",
            billing_month="2026-10",
            invoice_type="RENT",
            amount=Decimal("15000.00"),
            paid_amount=Decimal("5000.00"),
            due_date=date(2026, 10, 5),
            status="PARTIALLY_PAID",
        )
        inv_paid = Invoice(
            property_id=prop.id,
            resident_id=res1.id,
            invoice_number="INV-UPI-003",
            billing_month="2026-09",
            invoice_type="RENT",
            amount=Decimal("12000.00"),
            paid_amount=Decimal("12000.00"),
            due_date=date(2026, 9, 5),
            status="PAID",
        )
        inv_cancelled = Invoice(
            property_id=prop.id,
            resident_id=res1.id,
            invoice_number="INV-UPI-004",
            billing_month="2026-08",
            invoice_type="RENT",
            amount=Decimal("12000.00"),
            paid_amount=Decimal("0.00"),
            due_date=date(2026, 8, 5),
            status="CANCELLED",
        )
        db.add_all([inv_payable, inv_partial, inv_paid, inv_cancelled])
        db.commit()

        return {
            "company_id": company.id,
            "prop_id": prop.id,
            "manager_user_id": manager_user.id,
            "res1_user_id": res1_user.id,
            "res1_id": res1.id,
            "res2_user_id": res2_user.id,
            "res2_id": res2.id,
            "res3_user_id": res3_user.id,
            "res3_id": res3.id,
            "inv_payable_id": inv_payable.id,
            "inv_partial_id": inv_partial.id,
            "inv_paid_id": inv_paid.id,
            "inv_cancelled_id": inv_cancelled.id,
        }
    finally:
        db.close()


class TestUpiRentPaymentFlow:
    """Targeted tests for direct UPI rent payment initiation, intents, and verification."""

    def test_initiate_requires_configured_payee_vpa(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        assert res.status_code == 503
        err = res.json().get("detail") or res.json().get("error", {}).get("message", "")
        assert "UPI_PAYEE_VPA" in err

    def test_initiate_success_and_correct_amount_and_upi_uri(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "masisokatali90900@okaxis")
        monkeypatch.setattr(settings, "UPI_PAYEE_NAME", "Saukatali Masi")
        monkeypatch.setattr(settings, "UPI_MERCHANT_CODE", "5411")

        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        assert res.status_code == 201
        data = res.json()["data"]

        # 1. Amount verification (Calculated strictly from DB: 12000.00)
        assert data["amount"] == 12000.00
        assert data["currency"] == "INR"
        assert data["payee_vpa"] == "masisokatali90900@okaxis"
        assert data["payee_name"] == "Saukatali Masi"
        assert data["status"] == "PENDING"
        assert data["transaction_ref"].startswith("TXN")
        assert data["payment_number"].startswith("PAY-UPI-")

        # 2. UPI URI verification according to NPCI Deep Link specs
        upi_uri = data["upi_uri"]
        assert upi_uri.startswith("upi://pay?")
        parsed = urlparse(upi_uri)
        query = parse_qs(parsed.query)

        assert query["pa"] == ["masisokatali90900@okaxis"]
        assert query["pn"] == ["Saukatali Masi"]
        assert query["am"] == ["12000.00"]
        assert query["cu"] == ["INR"]
        assert query["tr"] == [data["transaction_ref"]]
        assert "Rent payment" in query["tn"][0]
        assert query["mc"] == ["5411"]

        # 3. Google Pay and PhonePe specific intent options
        assert data["google_pay_uri"] == f"{upi_uri}&package=com.google.android.apps.nbu.paisa.user"
        assert data["phonepe_uri"] == f"{upi_uri}&package=com.phonepe.app"

        apps = data["apps"]
        assert "google_pay" in apps
        assert apps["google_pay"]["name"] == "Google Pay"
        assert apps["google_pay"]["package_name"] == "com.google.android.apps.nbu.paisa.user"
        assert apps["google_pay"]["intent_uri"] == data["google_pay_uri"]

        assert "phonepe" in apps
        assert apps["phonepe"]["name"] == "PhonePe"
        assert apps["phonepe"]["package_name"] == "com.phonepe.app"
        assert apps["phonepe"]["intent_uri"] == data["phonepe_uri"]

    def test_initiate_partial_invoice_calculates_exact_outstanding_balance(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        # Invoice 2 has amount 15000.00, already paid 5000.00 -> exact outstanding is 10000.00
        res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_partial_id"])},
            headers=headers,
        )
        assert res.status_code == 201
        data = res.json()["data"]
        assert data["amount"] == 10000.00
        assert "am=10000.00" in data["upi_uri"]

    def test_initiate_cross_resident_invoice_rejected(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        # Resident 2 tries to initiate payment on Resident 1's invoice
        headers = make_token_header(upi_test_context["res2_user_id"], "RESIDENT", upi_test_context["company_id"])

        res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        assert res.status_code == 403
        assert "only pay their own invoices" in res.json()["error"]["message"]

    def test_initiate_paid_or_cancelled_invoice_rejected(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        # Paid invoice
        res_paid = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_paid_id"])},
            headers=headers,
        )
        assert res_paid.status_code == 409
        assert "not eligible for payment" in res_paid.json()["error"]["message"]

        # Cancelled invoice
        res_can = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_cancelled_id"])},
            headers=headers,
        )
        assert res_can.status_code == 409
        assert "not eligible for payment" in res_can.json()["error"]["message"]

    def test_pending_approval_resident_cannot_initiate(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        # Resident 3 is in PENDING_APPROVAL
        headers = make_token_header(upi_test_context["res3_user_id"], "RESIDENT", upi_test_context["company_id"])

        res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        assert res.status_code == 403
        assert "pending admin approval" in res.json()["error"]["message"]

    def test_return_from_upi_app_sets_pending_verification_never_paid(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        # 1. Initiate
        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        payment_id = init_res.json()["data"]["payment_id"]

        # 2. Return from UPI App (Google Pay / PhonePe)
        ret_res = client.post(f"/api/v1/payments/upi/{payment_id}/return", headers=headers)
        assert ret_res.status_code == 200
        data = ret_res.json()["data"]

        # Must transition to PENDING_VERIFICATION, NEVER automatically mark as PAID
        assert data["status"] == "PENDING_VERIFICATION"
        assert data["is_settled"] is False
        assert data["receipt_id"] is None

        # Verify in DB directly
        db = client.app.state.testing_session()
        payment = db.get(Payment, uuid.UUID(payment_id))
        invoice = db.get(Invoice, upi_test_context["inv_payable_id"])
        assert payment.status == "PENDING_VERIFICATION"
        assert invoice.status == "PENDING"
        assert invoice.paid_amount == Decimal("0.00")
        db.close()

    def test_cancel_pending_payment(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        payment_id = init_res.json()["data"]["payment_id"]

        can_res = client.post(f"/api/v1/payments/upi/{payment_id}/cancel", headers=headers)
        assert can_res.status_code == 200
        assert can_res.json()["data"]["status"] == "CANCELLED"

    def test_rejection_of_unverified_client_side_success(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        monkeypatch.setattr(settings, "UPI_VERIFICATION_PROVIDER_URL", "")
        monkeypatch.setattr(settings, "UPI_BANK_API_KEY", "")

        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        payment_id = init_res.json()["data"]["payment_id"]

        # Client submits a fake or unverified transaction reference
        verify_res = client.post(
            f"/api/v1/payments/upi/{payment_id}/verify",
            json={"client_txn_id": "FAKE_UTR_1234567890", "notes": "I paid on PhonePe"},
            headers=headers,
        )
        assert verify_res.status_code == 200
        v_data = verify_res.json()["data"]

        # Must NOT mark as verified or paid
        assert v_data["is_verified"] is False
        assert v_data["status"] == "PENDING_VERIFICATION"
        assert "Automatic confirmation requires an authorized Bank/UPI" in v_data["message"]
        assert "Bank Direct UPI Merchant API" in v_data["required_integration"]

        # Ensure DB status is still not PAID
        db = client.app.state.testing_session()
        payment = db.get(Payment, uuid.UUID(payment_id))
        invoice = db.get(Invoice, upi_test_context["inv_payable_id"])
        assert payment.status == "PENDING_VERIFICATION"
        assert invoice.status != "PAID"
        db.close()

    def test_verified_payment_settlement_and_receipt_generation(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        mgr_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])

        # 1. Initiate
        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res_headers,
        )
        payment_id = init_res.json()["data"]["payment_id"]

        # 2. Authorized Property Manager reconciles confirmed bank statement credit
        settle_res = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "ICICIUTR9988776655", "notes": "Verified against ICICI bank statement"},
            headers=mgr_headers,
        )
        assert settle_res.status_code == 200
        s_data = settle_res.json()["data"]

        assert s_data["status"] == "PAID"
        assert s_data["is_settled"] is True
        assert s_data["bank_reference"] == "ICICIUTR9988776655"
        assert s_data["receipt_id"] is not None
        assert s_data["receipt_number"].startswith("RCT-UPI-")

        # 3. Check Invoice and Receipt in DB
        db = client.app.state.testing_session()
        invoice = db.get(Invoice, upi_test_context["inv_payable_id"])
        payment = db.get(Payment, uuid.UUID(payment_id))
        receipt = db.get(Receipt, uuid.UUID(s_data["receipt_id"]))

        assert invoice.status == "PAID"
        assert invoice.paid_amount == Decimal("12000.00")
        assert payment.status == "PAID"
        assert payment.paid_at is not None
        assert receipt.amount == Decimal("12000.00")
        assert receipt.payment_id == payment.id

        from app.models.audit_log import AuditLog
        audit = db.scalar(
            sa.select(AuditLog).where(
                AuditLog.action == "UPI_PAYMENT_SETTLED",
                AuditLog.resource_id == str(payment_id),
            )
        )
        assert audit is not None
        assert audit.user_role == "PROPERTY_MANAGER"
        db.close()

    def test_duplicate_verification_and_duplicate_receipt_prevention(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        mgr_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])

        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res_headers,
        )
        payment_id = init_res.json()["data"]["payment_id"]

        # First settlement
        res1 = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR1001"},
            headers=mgr_headers,
        )
        receipt_id_1 = res1.json()["data"]["receipt_id"]

        # Second settlement attempt (Idempotent retry)
        res2 = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR1001"},
            headers=mgr_headers,
        )
        receipt_id_2 = res2.json()["data"]["receipt_id"]

        # Must return same receipt and avoid duplicate invoice balance addition
        assert receipt_id_1 == receipt_id_2
        assert "already settled" in res2.json()["message"]

        db = client.app.state.testing_session()
        invoice = db.get(Invoice, upi_test_context["inv_payable_id"])
        receipts_count = db.scalar(
            sa.select(sa.func.count(Receipt.id)).where(Receipt.payment_id == uuid.UUID(payment_id))
        )
        assert receipts_count == 1
        assert invoice.paid_amount == Decimal("12000.00")  # Not 24000!
        db.close()

    def test_bank_webhook_settlement(self, client, upi_test_context, monkeypatch):
        secret = "secret-bank-webhook-key"
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        monkeypatch.setattr(settings, "UPI_BANK_WEBHOOK_SECRET", secret)

        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res_headers,
        )
        txn_ref = init_res.json()["data"]["transaction_ref"]

        # 1. Invalid signature rejected
        bad_hook = client.post(
            "/api/v1/payments/upi/webhook/bank",
            json={"transaction_ref": txn_ref, "bank_reference": "HDFCUTR9988"},
            headers={"X-Bank-Signature": "wrong-secret"},
        )
        assert bad_hook.status_code == 401

        # 2. Valid bank webhook settles payment
        good_hook = client.post(
            "/api/v1/payments/upi/webhook/bank",
            json={"transaction_ref": txn_ref, "bank_reference": "HDFCUTR9988"},
            headers={"X-Bank-Signature": secret},
        )
        assert good_hook.status_code == 200
        assert "settled via direct bank webhook" in good_hook.json()["message"]

        db = client.app.state.testing_session()
        invoice = db.get(Invoice, upi_test_context["inv_payable_id"])
        payment = db.scalar(sa.select(Payment).where(Payment.gateway_order_id == txn_ref))
        assert payment.status == "PAID"
        assert invoice.status == "PAID"
        db.close()

    def test_bank_webhook_hmac_and_replay_protection(self, client, upi_test_context, monkeypatch):
        import hashlib
        import hmac
        import json

        secret = "secret-bank-webhook-key-hmac"
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        monkeypatch.setattr(settings, "UPI_BANK_WEBHOOK_SECRET", secret)

        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res_headers,
        )
        txn_ref = init_res.json()["data"]["transaction_ref"]

        # 1. Unconfigured secret returns 503
        monkeypatch.setattr(settings, "UPI_BANK_WEBHOOK_SECRET", "")
        no_sec_res = client.post(
            "/api/v1/payments/upi/webhook/bank",
            json={"transaction_ref": txn_ref, "bank_reference": "UTR123"},
            headers={"X-Bank-Signature": "any"},
        )
        assert no_sec_res.status_code == 503
        monkeypatch.setattr(settings, "UPI_BANK_WEBHOOK_SECRET", secret)

        # 2. Missing header returns 401
        no_sig_res = client.post(
            "/api/v1/payments/upi/webhook/bank",
            json={"transaction_ref": txn_ref, "bank_reference": "UTR123"},
        )
        assert no_sig_res.status_code == 401

        # 3. Valid HMAC-SHA256 signature of body succeeds
        payload_dict = {"transaction_ref": txn_ref, "bank_reference": "ICICI987654321", "event_id": f"evt_{txn_ref}"}
        payload_bytes = json.dumps(payload_dict).encode("utf-8")
        calc_hmac = hmac.new(secret.encode("utf-8"), payload_bytes, hashlib.sha256).hexdigest()

        hmac_res = client.post(
            "/api/v1/payments/upi/webhook/bank",
            content=payload_bytes,
            headers={"Content-Type": "application/json", "X-Bank-Signature": calc_hmac},
        )
        assert hmac_res.status_code == 200
        assert "settled via direct bank webhook" in hmac_res.json()["message"]

        # 4. Replay of same event_id is safely recognized as duplicate
        replay_res = client.post(
            "/api/v1/payments/upi/webhook/bank",
            content=payload_bytes,
            headers={"Content-Type": "application/json", "X-Bank-Signature": calc_hmac},
        )
        assert replay_res.status_code == 200
        assert "already processed" in replay_res.json()["message"]

    def test_admin_settle_validates_bank_reference(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        mgr_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])
        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res_headers,
        )
        payment_id = init_res.json()["data"]["payment_id"]

        # Blank or whitespace-only bank_reference is rejected with 422
        bad_settle = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "   "},
            headers=mgr_headers,
        )
        assert bad_settle.status_code == 422

    def test_payment_status_inquiry_endpoints(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res_headers,
        )
        payment_id = init_res.json()["data"]["payment_id"]

        # 1. Specific UPI status endpoint
        upi_stat = client.get(f"/api/v1/payments/upi/{payment_id}/status", headers=res_headers)
        assert upi_stat.status_code == 200
        assert upi_stat.json()["data"]["payment_id"] == payment_id
        assert upi_stat.json()["data"]["status"] == "PENDING"
        assert upi_stat.json()["data"]["is_settled"] is False

        # 2. General payment status endpoint
        gen_stat = client.get(f"/api/v1/payments/{payment_id}/status", headers=res_headers)
        assert gen_stat.status_code == 200
        assert gen_stat.json()["data"]["payment_id"] == payment_id
        assert gen_stat.json()["data"]["is_settled"] is False

    def test_bank_webhook_amount_and_currency_validation(self, client, upi_test_context, monkeypatch):
        secret = "secret-webhook-key-amount"
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        monkeypatch.setattr(settings, "UPI_BANK_WEBHOOK_SECRET", secret)

        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res_headers,
        )
        txn_ref = init_res.json()["data"]["transaction_ref"]

        # 1. Amount mismatch (expected 12000.00, received 500.00) rejected with 422
        bad_amt_res = client.post(
            "/api/v1/payments/upi/webhook/bank",
            json={"transaction_ref": txn_ref, "bank_reference": "UTR_AMT_1", "amount": 500.00},
            headers={"X-Bank-Signature": secret},
        )
        assert bad_amt_res.status_code == 422
        msg1 = bad_amt_res.json().get("detail") or bad_amt_res.json().get("error", {}).get("message", "")
        assert "Amount mismatch" in msg1

        # 2. Currency mismatch (expected INR, received USD) rejected with 422
        bad_curr_res = client.post(
            "/api/v1/payments/upi/webhook/bank",
            json={"transaction_ref": txn_ref, "bank_reference": "UTR_AMT_2", "amount": 12000.00, "currency": "USD"},
            headers={"X-Bank-Signature": secret},
        )
        assert bad_curr_res.status_code == 422
        msg2 = bad_curr_res.json().get("detail") or bad_curr_res.json().get("error", {}).get("message", "")
        assert "Unsupported currency" in msg2

        # 3. Matching amount and currency succeeds
        good_res = client.post(
            "/api/v1/payments/upi/webhook/bank",
            json={"transaction_ref": txn_ref, "bank_reference": "UTR_AMT_3", "amount": 12000.00, "currency": "INR"},
            headers={"X-Bank-Signature": secret},
        )
        assert good_res.status_code == 200

    def test_bank_reference_reuse_across_different_payments_rejected(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        mgr_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])
        res1_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        res2_headers = make_token_header(upi_test_context["res2_user_id"], "RESIDENT", upi_test_context["company_id"])

        # Create an unpaid invoice for Resident 2
        db = client.app.state.testing_session()
        inv_res2 = Invoice(
            property_id=upi_test_context["prop_id"],
            resident_id=upi_test_context["res2_id"],
            invoice_number="INV-RES2-001",
            billing_month="2026-11",
            invoice_type="RENT",
            amount=Decimal("10000.00"),
            paid_amount=Decimal("0.00"),
            due_date=date(2026, 11, 5),
            status="PENDING",
        )
        db.add(inv_res2)
        db.commit()
        inv_res2_id = inv_res2.id
        db.close()

        # Resident 1 initiates payment 1
        p1_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res1_headers,
        )
        p1_id = p1_res.json()["data"]["payment_id"]

        # Resident 2 initiates payment 2
        p2_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(inv_res2_id)},
            headers=res2_headers,
        )
        p2_id = p2_res.json()["data"]["payment_id"]

        # Settle payment 1 with bank UTR "UNIQUE_UTR_999"
        s1 = client.post(
            f"/api/v1/payments/upi/{p1_id}/admin-settle",
            json={"bank_reference": "UNIQUE_UTR_999"},
            headers=mgr_headers,
        )
        assert s1.status_code == 200

        # Attempt to reuse "UNIQUE_UTR_999" to settle payment 2 must be rejected with 409 Conflict
        s2 = client.post(
            f"/api/v1/payments/upi/{p2_id}/admin-settle",
            json={"bank_reference": "UNIQUE_UTR_999"},
            headers=mgr_headers,
        )
        assert s2.status_code == 409
        assert "already been credited" in s2.json()["error"]["message"]

    def test_settle_against_already_paid_invoice_rejected(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        mgr_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])
        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        # Initiate payment attempt A
        res_a = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"]), "idempotency_key": "attempt_a_key"},
            headers=res_headers,
        )
        p_a_id = res_a.json()["data"]["payment_id"]

        # Manually create another payment attempt B directly in DB against same invoice (simulating concurrent initiation)
        db = client.app.state.testing_session()
        payment_b = Payment(
            property_id=upi_test_context["prop_id"],
            invoice_id=upi_test_context["inv_payable_id"],
            resident_id=upi_test_context["res1_id"],
            payment_number="PAY-UPI-CONCURRENT-B",
            amount=Decimal("12000.00"),
            payment_mode="UPI",
            gateway_order_id="TXN_CONCURRENT_B",
            status="PENDING",
            idempotency_key="attempt_b_key",
        )
        db.add(payment_b)
        db.commit()
        p_b_id = str(payment_b.id)
        db.close()

        # Settle attempt A -> invoice becomes fully PAID
        s_a = client.post(
            f"/api/v1/payments/upi/{p_a_id}/admin-settle",
            json={"bank_reference": "UTR_FIRST_A"},
            headers=mgr_headers,
        )
        assert s_a.status_code == 200

        # Attempt B tries to settle against now fully paid invoice -> rejected with 409 Conflict
        s_b = client.post(
            f"/api/v1/payments/upi/{p_b_id}/admin-settle",
            json={"bank_reference": "UTR_SECOND_B"},
            headers=mgr_headers,
        )
        assert s_b.status_code == 409
        assert "already been fully settled" in s_b.json()["error"]["message"]

    def test_resident_my_payments_endpoint(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        res1_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        res2_headers = make_token_header(upi_test_context["res2_user_id"], "RESIDENT", upi_test_context["company_id"])
        res3_pending_headers = make_token_header(upi_test_context["res3_user_id"], "RESIDENT", upi_test_context["company_id"])

        # Resident 1 initiates a payment
        p1 = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res1_headers,
        )
        p1_id = p1.json()["data"]["payment_id"]

        # Resident 1 retrieves their own payments
        res1_my = client.get("/api/v1/payments/my", headers=res1_headers)
        assert res1_my.status_code == 200
        my_payments = res1_my.json()["data"]
        assert len(my_payments) >= 1
        assert any(item["id"] == p1_id for item in my_payments)

        # Resident 2 retrieves their own payments -> cannot see Resident 1's payment
        res2_my = client.get("/api/v1/payments/my", headers=res2_headers)
        assert res2_my.status_code == 200
        res2_payments = res2_my.json()["data"]
        assert not any(item["id"] == p1_id for item in res2_payments)

        # Resident 3 in PENDING_APPROVAL is blocked with 403
        res3_my = client.get("/api/v1/payments/my", headers=res3_pending_headers)
        assert res3_my.status_code == 403

    def test_unauthorized_and_cross_property_admin_settlement(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        res1_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        
        # Initiate payment under Property 1
        p_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res1_headers,
        )
        payment_id = p_res.json()["data"]["payment_id"]

        # 1. Resident cannot call admin-settle (Forbidden)
        res_settle = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR_FAIL_ROLE"},
            headers=res1_headers,
        )
        assert res_settle.status_code == 403

        # 2. Staff user cannot call admin-settle (Forbidden)
        db = client.app.state.testing_session()
        role_staff = db.scalar(sa.select(Role).where(Role.name == "STAFF"))
        if not role_staff:
            role_staff = Role(name="STAFF", display_name="Staff")
            db.add(role_staff)
            db.flush()
        staff_user = User(
            company_id=upi_test_context["company_id"],
            role_id=role_staff.id,
            email="staff_test@origin.com",
            phone="9876599099",
            full_name="Staff Sam",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            approval_status="APPROVED",
        )
        db.add(staff_user)
        db.flush()
        staff_headers = make_token_header(staff_user.id, "STAFF", upi_test_context["company_id"])

        staff_settle = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR_FAIL_STAFF"},
            headers=staff_headers,
        )
        assert staff_settle.status_code == 403

        # 3. Manager assigned ONLY to Property 2 cannot settle Property 1's payment (Cross-property access blocked)
        role_pm = db.scalar(sa.select(Role).where(Role.name == "PROPERTY_MANAGER"))
        mgr_prop2 = User(
            company_id=upi_test_context["company_id"],
            role_id=role_pm.id,
            email="mgr_prop2@origin.com",
            phone="9876599088",
            full_name="Manager Two",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            approval_status="APPROVED",
        )
        db.add(mgr_prop2)
        db.flush()
        # Grant access only to prop_other (not prop)
        prop_other = db.scalar(sa.select(Property).where(Property.code == "ORIGIN_H2"))
        db.add(UserPropertyAccess(user_id=mgr_prop2.id, property_id=prop_other.id, access_level="MANAGER"))
        db.commit()

        mgr2_headers = make_token_header(mgr_prop2.id, "PROPERTY_MANAGER", upi_test_context["company_id"])
        cross_res = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR_CROSS_PROPERTY"},
            headers=mgr2_headers,
        )
        assert cross_res.status_code == 403
        assert "not have access rights for property" in cross_res.json()["error"]["message"]
        db.close()

    def test_cancel_settled_payment_and_cross_resident_cancel_rejected(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        res1_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        res2_headers = make_token_header(upi_test_context["res2_user_id"], "RESIDENT", upi_test_context["company_id"])
        mgr_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])

        # Initiate
        p_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res1_headers,
        )
        payment_id = p_res.json()["data"]["payment_id"]

        # Resident 2 cannot cancel Resident 1's payment (Permission Denied)
        res2_cancel = client.post(f"/api/v1/payments/upi/{payment_id}/cancel", headers=res2_headers)
        assert res2_cancel.status_code == 403

        # Resident 2 cannot query status of Resident 1's payment
        res2_status = client.get(f"/api/v1/payments/upi/{payment_id}/status", headers=res2_headers)
        assert res2_status.status_code == 403

        # Settle the payment
        settle_res = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR_CANCEL_TEST"},
            headers=mgr_headers,
        )
        assert settle_res.status_code == 200

        # Resident 1 attempts to cancel settled payment -> Rejected with 409 Conflict
        res1_cancel = client.post(f"/api/v1/payments/upi/{payment_id}/cancel", headers=res1_headers)
        assert res1_cancel.status_code == 409
        assert "Cannot cancel an already settled payment" in res1_cancel.json()["error"]["message"]

    def test_payment_notifications_lifecycle(self, client, upi_test_context, monkeypatch):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        res1_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        mgr_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])

        # 1. Initiate payment
        p_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res1_headers,
        )
        payment_id = p_res.json()["data"]["payment_id"]

        # 2. Return from UPI app (pending verification)
        ret_res = client.post(f"/api/v1/payments/upi/{payment_id}/return", headers=res1_headers)
        assert ret_res.status_code == 200

        from app.models.notification import Notification
        db = client.app.state.testing_session()
        notifs = db.scalars(
            sa.select(Notification)
            .where(Notification.user_id == upi_test_context["res1_user_id"])
            .order_by(Notification.created_at.desc())
        ).all()
        assert any("Pending Verification" in n.title for n in notifs)

        # 3. Settle payment
        settle_res = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR_NOTIF_TEST"},
            headers=mgr_headers,
        )
        assert settle_res.status_code == 200

        notifs_after_settle = db.scalars(
            sa.select(Notification)
            .where(Notification.user_id == upi_test_context["res1_user_id"])
            .order_by(Notification.created_at.desc())
        ).all()
        assert any("Payment Confirmed" in n.title for n in notifs_after_settle)
        db.close()



