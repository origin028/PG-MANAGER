import uuid
from decimal import Decimal
import pytest
import sqlalchemy as sa

from app.core.config import settings
from app.models.audit_log import AuditLog
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.receipt import Receipt
from tests.test_upi_rent_payments import make_token_header, upi_test_context  # noqa: F401


class TestDirectUpiIntentEndpoints:
    """Comprehensive tests for /upi/response, /{payment_id}/status, /history, and /reconcile."""

    def test_upi_response_success_stays_pending_verification_never_settled(
        self, client, upi_test_context, monkeypatch
    ):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "smartpg@icici")
        res_headers = make_token_header(
            upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"]
        )

        # 1. Initiate payment (even if rogue amount passed, DB invoice balance is used)
        init_res = client.post(
            "/api/v1/payments/upi/initiate",
            json={
                "invoice_id": str(upi_test_context["inv_payable_id"]),
                "app_name": "Google Pay",
                "package_name": "com.google.android.apps.nbu.paisa.user",
                "amount": 1.00,
            },
            headers=res_headers,
        )
        assert init_res.status_code == 201
        init_data = init_res.json()["data"]
        assert init_data["amount"] == 12000.00
        assert "paytm" in init_data["apps"]
        assert "bhim" in init_data["apps"]

        payment_id = init_data["payment_id"]
        txn_ref = init_data["transaction_ref"]

        # 2. Report SUCCESS callback from UPI Intent -> MUST remain PENDING_VERIFICATION
        resp_res = client.post(
            "/api/v1/payments/upi/response",
            json={
                "payment_id": payment_id,
                "status": "SUCCESS",
                "txn_ref": txn_ref,
                "upi_txn_id": "412345678901",
                "approval_ref_no": "APP998877",
                "response_code": "00",
                "raw_response": f"txnId=412345678901&responseCode=00&Status=SUCCESS&txnRef={txn_ref}",
                "app_package": "com.google.android.apps.nbu.paisa.user",
            },
            headers=res_headers,
        )
        assert resp_res.status_code == 200
        resp_data = resp_res.json()["data"]
        assert resp_data["status"] == "PENDING_VERIFICATION"
        assert resp_data["reconciliation_status"] == "PENDING_RECONCILIATION"
        assert resp_data["is_settled"] is False
        assert resp_data["client_upi_txn_id"] == "412345678901"
        assert resp_data["bank_reference"] is None
        assert resp_data["receipt_id"] is None

        # Verify DB invoice untouched & no receipt issued yet
        db = client.app.state.testing_session()
        try:
            inv = db.get(Invoice, upi_test_context["inv_payable_id"])
            assert inv.status == "PENDING"
            assert Decimal(str(inv.paid_amount)) == Decimal("0.00")
            receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == uuid.UUID(payment_id)))
            assert receipt is None
            audit = db.scalar(
                sa.select(AuditLog).where(
                    AuditLog.resource_id == payment_id,
                    AuditLog.action == "UPI_INTENT_RESPONSE",
                )
            )
            assert audit is not None
        finally:
            db.close()

        # 3. Query generic /{payment_id}/status alias
        status_res = client.get(f"/api/v1/payments/{payment_id}/status", headers=res_headers)
        assert status_res.status_code == 200
        assert status_res.json()["data"]["status"] == "PENDING_VERIFICATION"

    def test_upi_response_failure_and_cancelled_and_ownership_checks(
        self, client, upi_test_context, monkeypatch
    ):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "smartpg@icici")
        r1_headers = make_token_header(
            upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"]
        )
        r2_headers = make_token_header(
            upi_test_context["res2_user_id"], "RESIDENT", upi_test_context["company_id"]
        )

        # Initiate 2 attempts
        p1 = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=r1_headers,
        ).json()["data"]
        p2 = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_partial_id"])},
            headers=r1_headers,
        ).json()["data"]

        # Resident 2 cannot post response for Resident 1's payment
        forbidden = client.post(
            "/api/v1/payments/upi/response",
            json={"payment_id": p1["payment_id"], "status": "SUCCESS"},
            headers=r2_headers,
        )
        assert forbidden.status_code == 403

        # Transaction ref mismatch rejected
        mismatch = client.post(
            "/api/v1/payments/upi/response",
            json={"payment_id": p1["payment_id"], "status": "FAILURE", "txn_ref": "TXNWRONGREF"},
            headers=r1_headers,
        )
        assert mismatch.status_code == 400

        # FAILURE -> FAILED
        fail_res = client.post(
            "/api/v1/payments/upi/response",
            json={
                "payment_id": p1["payment_id"],
                "status": "FAILURE",
                "response_code": "Z9",
                "raw_response": "Status=FAILURE&responseCode=Z9",
            },
            headers=r1_headers,
        )
        assert fail_res.status_code == 200
        assert fail_res.json()["data"]["status"] == "FAILED"
        assert fail_res.json()["data"]["response_code"] == "Z9"

        # CANCELLED -> CANCELLED
        cancel_res = client.post(
            "/api/v1/payments/upi/response",
            json={"payment_id": p2["payment_id"], "status": "CANCELLED"},
            headers=r1_headers,
        )
        assert cancel_res.status_code == 200
        assert cancel_res.json()["data"]["status"] == "CANCELLED"

    def test_admin_reconcile_approve_reject_duplicate_utr_and_history_endpoints(
        self, client, upi_test_context, monkeypatch
    ):
        monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "smartpg@icici")
        r1_headers = make_token_header(
            upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"]
        )
        r2_headers = make_token_header(
            upi_test_context["res2_user_id"], "RESIDENT", upi_test_context["company_id"]
        )
        mgr_headers = make_token_header(
            upi_test_context["manager_user_id"], "PROPERTY_MANAGER", upi_test_context["company_id"]
        )

        p1 = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_payable_id"])},
            headers=r1_headers,
        ).json()["data"]
        p2 = client.post(
            "/api/v1/payments/upi/initiate",
            json={"invoice_id": str(upi_test_context["inv_partial_id"])},
            headers=r1_headers,
        ).json()["data"]

        # Resident reports SUBMITTED on p1
        client.post(
            "/api/v1/payments/upi/response",
            json={"payment_id": p1["payment_id"], "status": "SUBMITTED", "upi_txn_id": "UTR-CLAIM-1"},
            headers=r1_headers,
        )

        # Resident cannot reconcile own payment
        res_reconcile = client.post(
            f"/api/v1/payments/upi/{p1['payment_id']}/reconcile",
            json={"action": "APPROVE", "bank_reference": "HDFC-UTR-555001"},
            headers=r1_headers,
        )
        assert res_reconcile.status_code == 403

        # Admin approves p1 with verified UTR
        approve_res = client.post(
            f"/api/v1/payments/upi/{p1['payment_id']}/reconcile",
            json={"action": "APPROVE", "bank_reference": "HDFC-UTR-555001", "notes": "Verified in HDFC statement"},
            headers=mgr_headers,
        )
        assert approve_res.status_code == 200
        approve_data = approve_res.json()["data"]
        assert approve_data["status"] == "PAID"
        assert approve_data["is_settled"] is True
        assert approve_data["bank_reference"] == "HDFC-UTR-555001"
        assert approve_data["receipt_number"] is not None

        # Client replay callback after settlement CANNOT downgrade status
        replay = client.post(
            "/api/v1/payments/upi/response",
            json={"payment_id": p1["payment_id"], "status": "FAILURE"},
            headers=r1_headers,
        )
        assert replay.status_code == 200
        assert replay.json()["data"]["status"] == "PAID"

        # Duplicate bank UTR across p2 is rejected with 409
        dup_utr = client.post(
            f"/api/v1/payments/upi/{p2['payment_id']}/reconcile",
            json={"action": "APPROVE", "bank_reference": "HDFC-UTR-555001"},
            headers=mgr_headers,
        )
        assert dup_utr.status_code == 409

        # Admin rejects p2 (no credit received)
        reject_res = client.post(
            f"/api/v1/payments/upi/{p2['payment_id']}/reconcile",
            json={"action": "REJECT", "notes": "Not found in bank credit statement"},
            headers=mgr_headers,
        )
        assert reject_res.status_code == 200
        assert reject_res.json()["data"]["status"] == "FAILED"

        # Resident 1 history sees p1 & p2, Resident 2 sees 0
        r1_hist = client.get("/api/v1/payments/history", headers=r1_headers)
        assert r1_hist.status_code == 200
        assert len(r1_hist.json()["data"]) >= 2

        r2_hist = client.get("/api/v1/payments/history", headers=r2_headers)
        assert r2_hist.status_code == 200
        assert len(r2_hist.json()["data"]) == 0

        # Admin history filtered by property & search finds verified payment + receipt
        adm_hist = client.get(
            f"/api/v1/payments/history?property_id={upi_test_context['prop_id']}&search=HDFC-UTR-555001",
            headers=mgr_headers,
        )
        assert adm_hist.status_code == 200
        items = adm_hist.json()["data"]
        assert len(items) == 1
        assert items[0]["reconciliation_status"] == "VERIFIED"
        assert items[0]["receipt_number"] == approve_data["receipt_number"]

    def test_demo_pay_still_works_independently(self, client, upi_test_context):
        r1_headers = make_token_header(
            upi_test_context["res1_user_id"], "RESIDENT", upi_test_context["company_id"]
        )
        demo_res = client.post(
            "/api/v1/payments/demo/pay",
            json={
                "invoice_id": str(upi_test_context["inv_payable_id"]),
                "amount": 12000.00,
                "payment_mode": "DEMO_ONLINE",
            },
            headers=r1_headers,
        )
        assert demo_res.status_code == 200
        assert demo_res.json()["data"]["status"] == "PAID"

    def test_upi_uri_builder_sanitizes_note_and_rejects_malformed_merchant_code(self):
        from app.services.upi_payment_service import build_upi_uri, redact_vpa
        from urllib.parse import parse_qs, urlparse

        uri = build_upi_uri(
            payee_vpa="merchant@barodampay",
            payee_name="Origin PG",
            amount=Decimal("1.00"),
            transaction_ref="TXN998877",
            description="Rent+Payment+08bd684a-aef1-4f11-ae43-6cd52a329c43 & Very Long Note Name",
            merchant_code="BAD_MC",
        )
        assert "+" not in uri
        parsed = parse_qs(urlparse(uri).query)
        assert len(parsed["tn"][0]) <= 50
        assert "mc" not in parsed
        assert redact_vpa("masisokatali90900@okaxis") == "ma***00@okaxis"

