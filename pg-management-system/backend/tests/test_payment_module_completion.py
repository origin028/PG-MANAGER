import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from unittest.mock import patch
import pytest
import sqlalchemy as sa

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.user import User, UserPropertyAccess
from tests.test_upi_rent_payments import make_token_header, upi_test_context


class TestPaymentModuleCompletion:
    """Complete automated verification suite for PG Management System payment module."""

    def test_01_upi_initiation_success_and_payload(self, client, upi_test_context, monkeypatch):
        """Validates that UPI initiation generates all required intent parameters and NPCI URI."""
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        monkeypatch.setattr(settings, "UPI_PAYEE_NAME", "Origin Grand PG")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        assert resp.status_code == 201, resp.text
        data = resp.json()["data"]
        assert "payment_id" in data
        assert data["payment_number"].startswith("PAY-UPI-")
        assert data["transaction_ref"].startswith("TXN")
        assert data["amount"] == 12000.0
        assert data["currency"] == "INR"
        assert data["payee_vpa"] == "originpg@icici"
        assert data["payee_name"] == "Origin Grand PG"
        assert data["status"] == "PENDING"
        assert "upi://pay?" in data["upi_uri"]
        assert "pa=originpg%40icici" in data["upi_uri"]
        assert "am=12000.00" in data["upi_uri"]
        assert "com.google.android.apps.nbu.paisa.user" in data["google_pay_uri"]
        assert "com.phonepe.app" in data["phonepe_uri"]

    def test_02_upi_status_retrieval(self, client, upi_test_context, monkeypatch):
        """Validates authoritative status retrieval by resident owner."""
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        payment_id = init_resp.json()["data"]["payment_id"]

        status_resp = client.get(f"/api/v1/payments/upi/{payment_id}/status", headers=headers)
        assert status_resp.status_code == 200
        s_data = status_resp.json()["data"]
        assert s_data["payment_id"] == payment_id
        assert s_data["status"] == "PENDING"
        assert s_data["is_settled"] is False
        assert s_data["amount"] == 12000.0

    def test_03_upi_cancellation_and_idempotency(self, client, upi_test_context, monkeypatch):
        """Validates that unverified payments can be cancelled and cancellation is idempotent."""
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        payment_id = init_resp.json()["data"]["payment_id"]

        cancel_resp = client.post(f"/api/v1/payments/upi/{payment_id}/cancel", headers=headers)
        assert cancel_resp.status_code == 200, cancel_resp.text
        assert cancel_resp.json()["data"]["status"] == "CANCELLED"

        # Idempotent second call must succeed with 200
        cancel_resp2 = client.post(f"/api/v1/payments/upi/{payment_id}/cancel", headers=headers)
        assert cancel_resp2.status_code == 200
        assert cancel_resp2.json()["data"]["status"] == "CANCELLED"

    def test_04_missing_notification_resilience(self, client, upi_test_context, monkeypatch):
        """
        Validates that if notification dispatch encounters an error (e.g. simulated missing table),
        cancellation does NOT return HTTP 500 and the payment status is accurately returned as CANCELLED.
        """
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        payment_id = init_resp.json()["data"]["payment_id"]

        # Simulate notification failure
        with patch("app.services.notification_service.NotificationService.dispatch", side_effect=RuntimeError("Simulated missing relation")):
            cancel_resp = client.post(f"/api/v1/payments/upi/{payment_id}/cancel", headers=headers)
            assert cancel_resp.status_code == 200, f"Expected 200 despite notification error, got {cancel_resp.status_code}"
            assert cancel_resp.json()["data"]["status"] == "CANCELLED"

    def test_05_unverified_upi_payment_must_not_become_paid(self, client, upi_test_context, monkeypatch):
        """
        Strict security rule: Opening UPI app, returning to app, or submitting client claims
        must NEVER mark the payment as PAID. Must remain in PENDING_VERIFICATION.
        """
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        payment_id = init_resp.json()["data"]["payment_id"]

        # Resident returns from UPI app
        ret_resp = client.post(f"/api/v1/payments/upi/{payment_id}/return", headers=headers)
        assert ret_resp.status_code == 200
        assert ret_resp.json()["data"]["status"] == "PENDING_VERIFICATION"
        assert ret_resp.json()["data"]["is_settled"] is False

        # Resident calls verify endpoint claiming success with client-entered UTR
        verify_resp = client.post(
            f"/api/v1/payments/upi/{payment_id}/verify",
            json={"utr": "999888777666", "status": "SUCCESS"},
            headers=headers,
        )
        assert verify_resp.status_code == 200
        v_data = verify_resp.json()["data"]
        assert v_data["is_verified"] is False
        assert v_data["status"] == "PENDING_VERIFICATION"
        assert "Bank Direct UPI Merchant API" in v_data["required_integration"]

        # Ensure payment record in DB did NOT become PAID
        db = client.app.state.testing_session()
        payment = db.get(Payment, uuid.UUID(payment_id))
        assert payment.status == "PENDING_VERIFICATION"
        db.close()

    def test_06_invoice_already_paid_rejected(self, client, upi_test_context, monkeypatch):
        """Validates that initiating a payment on an already PAID invoice is rejected with HTTP 409 Conflict."""
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_paid_id"])},
            headers=headers,
        )
        assert resp.status_code == 409
        assert "not eligible for payment" in resp.text

    def test_07_duplicate_payment_initiation_idempotency(self, client, upi_test_context, monkeypatch):
        """Validates that providing the same idempotency_key returns the active payment without duplicate rows."""
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        key = "idemp_test_key_001"

        resp1 = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"]), "idempotency_key": key},
            headers=headers,
        )
        assert resp1.status_code == 201
        pid1 = resp1.json()["data"]["payment_id"]

        resp2 = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"]), "idempotency_key": key},
            headers=headers,
        )
        assert resp2.status_code == 201
        pid2 = resp2.json()["data"]["payment_id"]
        assert pid1 == pid2, "Duplicate payment created despite matching idempotency key!"

    def test_08_duplicate_settlement_protection(self, client, upi_test_context, monkeypatch):
        """Validates that settling an already settled payment is idempotent and prevents duplicate receipts."""
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        res_headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        admin_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])

        init_resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res_headers,
        )
        payment_id = init_resp.json()["data"]["payment_id"]

        # Admin settles payment with bank UTR
        settle1 = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR123456789"},
            headers=admin_headers,
        )
        assert settle1.status_code == 200
        assert settle1.json()["data"]["is_settled"] is True
        receipt_id1 = settle1.json()["data"]["receipt_id"]
        assert receipt_id1 is not None

        # Settle second time (idempotent duplicate)
        settle2 = client.post(
            f"/api/v1/payments/upi/{payment_id}/admin-settle",
            json={"bank_reference": "UTR123456789"},
            headers=admin_headers,
        )
        assert settle2.status_code == 200
        assert "already settled" in settle2.json()["message"]
        assert settle2.json()["data"]["receipt_id"] == receipt_id1

    def test_09_invalid_invoice_ownership_rejected(self, client, upi_test_context, monkeypatch):
        """Validates that a resident cannot pay another resident's invoice (HTTP 403 Forbidden)."""
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        # Resident 2 attempts to pay Resident 1's invoice
        res2_headers = make_token_header(upi_test_context["res2_user_id"], "RESIDENT", upi_test_context["company_id"])

        resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=res2_headers,
        )
        assert resp.status_code == 403
        assert "only pay their own invoices" in resp.text

    def test_10_invalid_payment_amount_rejected_in_demo(self, client, upi_test_context):
        """Validates that overpayment and zero/negative amounts are rejected with 409 Conflict."""
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        # Zero amount
        r_zero = client.post(
            "/api/v1/payments/demo/pay",
            json={"invoice_id": str(upi_test_context["inv_payable_id"]), "amount": 0},
            headers=headers,
        )
        assert r_zero.status_code in (409, 422)

        # Exceeds balance
        r_over = client.post(
            "/api/v1/payments/demo/pay",
            json={"invoice_id": str(upi_test_context["inv_payable_id"]), "amount": 999999.00},
            headers=headers,
        )
        assert r_over.status_code == 409
        assert "exceeds outstanding invoice balance" in r_over.text

    def test_11_demo_payment_success_and_receipt_creation(self, client, upi_test_context):
        """Validates that DEMO_ONLINE payment marks payment and invoice PAID and creates digital receipt."""
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        idemp_key = "demo_idemp_key_101"

        resp = client.post(
            "/api/v1/payments/demo/pay",
            json={
                "invoice_id": str(upi_test_context["inv_payable_id"]),
                "amount": 12000.0,
                "payment_mode": "DEMO_ONLINE",
                "idempotency_key": idemp_key,
            },
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        assert data["status"] == "PAID"
        assert data["invoice_status"] == "PAID"
        assert data["remaining_balance"] == 0.0
        assert data["receipt_number"].startswith("RCT-DEMO-")

        # Duplicate demo call with same idempotency key returns idempotent success
        resp2 = client.post(
            "/api/v1/payments/demo/pay",
            json={
                "invoice_id": str(upi_test_context["inv_payable_id"]),
                "amount": 12000.0,
                "payment_mode": "DEMO_ONLINE",
                "idempotency_key": idemp_key,
            },
            headers=headers,
        )
        assert resp2.status_code == 200
        assert resp2.json()["data"]["payment_id"] == data["payment_id"]

    def test_12_resident_payment_history(self, client, upi_test_context):
        """Validates GET /api/v1/payments/my retrieves payment history scoped to resident."""
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        resp = client.get("/api/v1/payments/my", headers=headers)
        assert resp.status_code == 200
        items = resp.json()["data"]
        assert isinstance(items, list)

    def test_13_admin_payment_listing(self, client, upi_test_context):
        """Validates GET /api/v1/payments?property_id=... retrieves paginated payment records for admin."""
        admin_headers = make_token_header(upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"])

        resp = client.get(
            f"/api/v1/payments?property_id={upi_test_context['prop_id']}&page=1&page_size=10",
            headers=admin_headers,
        )
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert "items" in data
        assert "total" in data

    def test_14_nested_savepoint_isolation_on_notification_db_failure(self, client, upi_test_context):
        """
        Requirements 2, 3, 4, 5, 6:
        Simulate an actual database-level insertion failure inside NotificationService.dispatch()
        while an outer payment transaction has pending uncommitted database changes.
        Verifies:
        - Notification error rolls back ONLY the savepoint.
        - Outer payment changes are NOT rolled back.
        - SQLAlchemy session remains usable after the notification failure.
        - Outer changes commit successfully.
        """
        from app.services.notification_service import NotificationService
        from app.models.payment import Payment

        db = client.app.state.testing_session()
        payment = db.scalar(sa.select(Payment).where(Payment.invoice_id == upi_test_context["inv_payable_id"]))
        if not payment:
            payment = Payment(
                invoice_id=upi_test_context["inv_payable_id"],
                resident_id=upi_test_context["res1_id"],
                property_id=upi_test_context["prop_id"],
                payment_number=f"PAY-TEST-{uuid.uuid4().hex[:6]}",
                amount=Decimal("12000.00"),
                payment_mode="UPI",
                status="PENDING",
            )
            db.add(payment)
            db.commit()
            db.refresh(payment)

        original_status = payment.status

        # 1. Outer uncommitted change in the session
        payment.status = "CANCELLED"
        payment.gateway_payment_id = "TEST-OUTER-UNCOMMITTED-REF"
        db.flush()

        # 2. Call NotificationService.dispatch with None causing NOT NULL integrity violation on DB level
        notif_service = NotificationService(db)
        notif_result = notif_service.dispatch(
            user_id=None,  # type: ignore[arg-type] - intentionally violates NOT NULL
            title=None,    # type: ignore[arg-type] - intentionally violates NOT NULL
            body="This should fail at the DB level",
        )
        assert notif_result is None, "Expected notification dispatch to return None on DB error"

        # 3. Verify session is still usable (NOT in InFailedSqlTransaction)
        refreshed_payment = db.scalar(sa.select(Payment).where(Payment.id == payment.id))
        assert refreshed_payment is not None
        assert refreshed_payment.status == "CANCELLED"
        assert refreshed_payment.gateway_payment_id == "TEST-OUTER-UNCOMMITTED-REF"

        # 4. Commit outer transaction
        db.commit()

        # 5. Verify the outer changes persisted in DB
        db.refresh(payment)
        assert payment.status == "CANCELLED"
        assert payment.gateway_payment_id == "TEST-OUTER-UNCOMMITTED-REF"

        # Restore original state
        payment.status = original_status
        payment.gateway_payment_id = None
        db.commit()
        db.close()

    def test_15_repeated_upi_cancellation_idempotency(self, client, upi_test_context, monkeypatch):
        """
        Requirement 7:
        Tests repeated UPI cancellation calls against the same payment.
        Verifies that all repeated calls return HTTP 200, status CANCELLED, and do not raise errors.
        """
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "originpg@icici")
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        init_resp = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=headers,
        )
        payment_id = init_resp.json()["data"]["payment_id"]

        # Call cancel 4 times consecutively
        for call_idx in range(1, 5):
            cancel_resp = client.post(f"/api/v1/payments/upi/{payment_id}/cancel", headers=headers)
            assert cancel_resp.status_code == 200, f"Call {call_idx} failed: {cancel_resp.text}"
            assert cancel_resp.json()["data"]["status"] == "CANCELLED"

    def test_16_database_guard_and_no_prod_connection(self):
        """
        Requirement 10:
        Verifies that the backend configured database is strictly pg_management_test and never pg_management.
        """
        from sqlalchemy import make_url

        url = make_url(settings.DATABASE_URL)
        assert url.database == "pg_management_test", (
            f"Safety violation: Configured backend database is '{url.database}', expected 'pg_management_test'!"
        )
        assert url.database != "pg_management", "CRITICAL: Configured database points to production 'pg_management'!"

    def test_17_demo_payment_repeated_requests_and_no_duplicate_receipts(self, client, upi_test_context):
        """
        Tasks 4, 7:
        Validates that repeated demo payment requests with the same idempotency_key:
        - Return HTTP 200 on every repeat call.
        - Return the exact same payment_id, receipt_id, and receipt_number.
        - Do not create any duplicate payment or receipt records in the database.
        """
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])
        db = client.app.state.testing_session()

        # Count initial payments and receipts
        initial_payments_count = db.scalar(sa.select(sa.func.count(Payment.id)))
        initial_receipts_count = db.scalar(sa.select(sa.func.count(Receipt.id)))

        idemp_key = f"demo_idem_{uuid.uuid4().hex[:12]}"
        payload = {
            "invoice_id": str(upi_test_context["inv_partial_id"]),
            "amount": 10000.0,
            "payment_mode": "DEMO_ONLINE",
            "idempotency_key": idemp_key,
        }

        # 1. First execution
        resp1 = client.post("/api/v1/payments/demo/pay", json=payload, headers=headers)
        assert resp1.status_code == 200, resp1.text
        data1 = resp1.json()["data"]
        payment_id = data1["payment_id"]
        receipt_id = data1["receipt_id"]
        receipt_number = data1["receipt_number"]
        assert receipt_id is not None
        assert receipt_number is not None

        # 2. Repeat execution 3 more times with the exact same idempotency_key
        for i in range(2, 5):
            resp_repeat = client.post("/api/v1/payments/demo/pay", json=payload, headers=headers)
            assert resp_repeat.status_code == 200, f"Repeat {i} failed: {resp_repeat.text}"
            repeat_data = resp_repeat.json()["data"]
            assert repeat_data["payment_id"] == payment_id
            assert repeat_data["receipt_id"] == receipt_id
            assert repeat_data["receipt_number"] == receipt_number
            assert "idempotent duplicate" in resp_repeat.json()["message"]

        # 3. Verify database count: exactly 1 payment and 1 receipt added in total
        final_payments_count = db.scalar(sa.select(sa.func.count(Payment.id)))
        final_receipts_count = db.scalar(sa.select(sa.func.count(Receipt.id)))
        assert final_payments_count == initial_payments_count + 1, "Duplicate payment created!"
        assert final_receipts_count == initial_receipts_count + 1, "Duplicate receipt created!"
        db.close()

    def test_18_demo_payment_different_or_missing_key_on_paid_invoice_rejected(self, client, upi_test_context):
        """
        Tasks 5, 7:
        Validates that for an already-paid invoice:
        - A request with a DIFFERENT idempotency_key is rejected with HTTP 409 Conflict.
        - A request with MISSING or None idempotency_key is rejected with HTTP 409 Conflict.
        - No additional payments or receipts can be generated.
        """
        headers = make_token_header(upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"])

        # Try to pay inv_paid_id (which has status 'PAID') with a new idempotency key
        diff_payload = {
            "invoice_id": str(upi_test_context["inv_paid_id"]),
            "amount": 12000.0,
            "payment_mode": "DEMO_ONLINE",
            "idempotency_key": "different_key_for_paid_invoice",
        }
        resp_diff = client.post("/api/v1/payments/demo/pay", json=diff_payload, headers=headers)
        assert resp_diff.status_code == 409, f"Expected 409 Conflict, got {resp_diff.status_code}"
        assert "not eligible for payment" in resp_diff.text or "PAID" in resp_diff.text

        # Try without any idempotency key
        no_key_payload = {
            "invoice_id": str(upi_test_context["inv_paid_id"]),
            "payment_mode": "DEMO_ONLINE",
        }
        resp_no_key = client.post("/api/v1/payments/demo/pay", json=no_key_payload, headers=headers)
        assert resp_no_key.status_code == 409, f"Expected 409 Conflict, got {resp_no_key.status_code}"
        assert "not eligible for payment" in resp_no_key.text or "PAID" in resp_no_key.text

    def test_19_demo_payment_openapi_schema_exposes_idempotency_key(self):
        """
        Tasks 1, 2, 6:
        Verifies that OpenAPI documentation explicitly exposes idempotency_key in:
        - DemoPaymentRequest schema properties and description.
        - DemoPaymentRequest schema example.
        - POST /api/v1/payments/demo/pay requestBody examples.
        """
        from app.main import app

        schema = app.openapi()
        path = schema.get("paths", {}).get("/api/v1/payments/demo/pay", {}).get("post", {})
        assert path, "Route POST /api/v1/payments/demo/pay not found in OpenAPI schema!"

        # 1. Verify endpoint description mentions idempotency
        assert "Idempotency Protection" in path.get("description", "")

        # 2. Verify requestBody examples
        req_body = path.get("requestBody", {})
        content = req_body.get("content", {}).get("application/json", {})
        examples = content.get("examples", {})
        assert "with_idempotency_key" in examples
        assert "idempotency_key" in examples["with_idempotency_key"]["value"]

        # 3. Verify DemoPaymentRequest schema in components
        components_schemas = schema.get("components", {}).get("schemas", {})
        demo_schema = components_schemas.get("DemoPaymentRequest", {})
        assert "idempotency_key" in demo_schema.get("properties", {})
        assert "idempotency_key" in demo_schema.get("example", {})
