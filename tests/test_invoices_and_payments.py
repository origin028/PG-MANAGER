import uuid
from decimal import Decimal
from tests.test_roles_and_scopes import get_token


def _setup_kor_hsr_ind(client, admin_token):
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")
    hsr_id = next(p["id"] for p in props if p["code"] == "OG-HSR")
    ind_id = next(p["id"] for p in props if p["code"] == "OG-IND")
    return kor_id, hsr_id, ind_id


def _admit_resident(client, token, prop_id, name="Test Resident", phone="9888877771"):
    payload = {
        "property_id": prop_id,
        "full_name": name,
        "phone": phone,
        "email": f"{phone}@example.com",
        "emergency_contact_name": "Emergency Person",
        "emergency_contact_phone": "9888877770",
        "monthly_rent": 12000.0,
        "security_deposit": 24000.0,
        "id_proof_type": "AADHAAR",
        "id_proof_number": "9999 8888 7777",
    }
    resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["data"]["id"]


def test_super_admin_create_invoice_rent_and_deposit(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)
    res_id = _admit_resident(client, admin_token, kor_id, "Rohan Verma", "9111122221")

    # 1. Create Rent Invoice
    payload_rent = {
        "property_id": kor_id,
        "resident_id": res_id,
        "billing_month": "2026-11",
        "billing_period_start": "2026-11-01",
        "billing_period_end": "2026-11-30",
        "issue_date": "2026-11-01",
        "due_date": "2026-11-05",
        "invoice_type": "RENT",
        "rent_amount": "12000.00",
        "additional_charges": "500.00",
        "discount_amount": "200.00",
        "notes": "November 2026 Rent",
    }
    resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload_rent,
    )
    assert resp.status_code == 201, resp.text
    inv_data = resp.json()["data"]
    assert inv_data["invoice_number"].startswith("INV-OG-KOR-202611-")
    assert Decimal(str(inv_data["total_amount"])) == Decimal("12300.00")
    assert Decimal(str(inv_data["paid_amount"])) == Decimal("0.00")
    assert Decimal(str(inv_data["balance_amount"])) == Decimal("12300.00")
    assert inv_data["status"] == "ISSUED"

    # 2. Create Security Deposit Invoice for the same resident in the same month (allowed because invoice_type differs)
    payload_dep = {
        "property_id": kor_id,
        "resident_id": res_id,
        "billing_month": "2026-11",
        "billing_period_start": "2026-11-01",
        "billing_period_end": "2026-11-30",
        "issue_date": "2026-11-01",
        "due_date": "2026-11-05",
        "invoice_type": "SECURITY_DEPOSIT",
        "rent_amount": "24000.00",
        "additional_charges": "0.00",
        "discount_amount": "0.00",
        "notes": "Security Deposit",
    }
    resp_dep = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload_dep,
    )
    assert resp_dep.status_code == 201, resp_dep.text
    dep_data = resp_dep.json()["data"]
    assert dep_data["invoice_type"] == "SECURITY_DEPOSIT"
    assert Decimal(str(dep_data["total_amount"])) == Decimal("24000.00")


def test_duplicate_invoice_same_month_and_type_rejected(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)
    res_id = _admit_resident(client, admin_token, kor_id, "Maya Sen", "9111122222")

    payload = {
        "property_id": kor_id,
        "resident_id": res_id,
        "billing_month": "2026-12",
        "billing_period_start": "2026-12-01",
        "billing_period_end": "2026-12-31",
        "issue_date": "2026-12-01",
        "due_date": "2026-12-05",
        "invoice_type": "RENT",
        "rent_amount": "10000.00",
    }
    resp1 = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp1.status_code == 201

    # Second invoice with same resident, month, and type must be rejected with 409
    resp2 = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp2.status_code == 409
    assert "already exists" in resp2.json()["error"]["message"]


def test_negative_total_amount_rejected(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)
    res_id = _admit_resident(client, admin_token, kor_id, "Kunal Roy", "9111122223")

    payload = {
        "property_id": kor_id,
        "resident_id": res_id,
        "billing_month": "2026-10",
        "billing_period_start": "2026-10-01",
        "billing_period_end": "2026-10-31",
        "issue_date": "2026-10-01",
        "due_date": "2026-10-05",
        "invoice_type": "RENT",
        "rent_amount": "5000.00",
        "discount_amount": "6000.00",  # Discount greater than rent
    }
    resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp.status_code == 400 or resp.status_code == 422
    assert "negative" in str(resp.json()).lower()


def test_draft_invoice_issue_and_cancel_lifecycle(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)
    res_id = _admit_resident(client, admin_token, kor_id, "Sneha Rao", "9111122224")

    # 1. Create DRAFT invoice — use a future due_date so it stays ISSUED (not OVERDUE)
    payload = {
        "property_id": kor_id,
        "resident_id": res_id,
        "billing_month": "2027-03",
        "billing_period_start": "2027-03-01",
        "billing_period_end": "2027-03-31",
        "issue_date": "2027-03-01",
        "due_date": "2027-03-05",
        "invoice_type": "RENT",
        "rent_amount": "11000.00",
        "is_draft": True,
    }
    resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp.status_code == 201
    inv_data = resp.json()["data"]
    inv_id = inv_data["id"]
    assert inv_data["status"] == "DRAFT"

    # Cannot record payment against draft invoice
    pay_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "5000.00",
            "payment_method": "UPI",
        },
    )
    assert pay_resp.status_code == 409
    assert "draft" in pay_resp.json()["error"]["message"].lower()

    # 2. Issue the draft invoice — due_date is in the future so status = ISSUED
    issue_resp = client.post(
        f"/api/v1/invoices/{inv_id}/issue",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert issue_resp.status_code == 200
    assert issue_resp.json()["data"]["status"] == "ISSUED"

    # 3. Cancel the unpaid issued invoice
    cancel_resp = client.post(
        f"/api/v1/invoices/{inv_id}/cancel",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert cancel_resp.status_code == 200
    assert cancel_resp.json()["data"]["status"] == "CANCELLED"

    # Cannot record payment against cancelled invoice
    pay_resp2 = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "5000.00",
            "payment_method": "UPI",
        },
    )
    assert pay_resp2.status_code == 409
    assert "cancelled" in pay_resp2.json()["error"]["message"].lower()


def test_payment_recording_partial_full_and_overpayment_rejected(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)
    res_id = _admit_resident(client, admin_token, kor_id, "Arjun Kapoor", "9111122225")

    # Create Invoice for 10,000.00 — use future due_date so status doesn't flip to OVERDUE
    inv_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2027-04",
            "billing_period_start": "2027-04-01",
            "billing_period_end": "2027-04-30",
            "issue_date": "2027-04-01",
            "due_date": "2027-04-05",
            "invoice_type": "RENT",
            "rent_amount": "10000.00",
        },
    )
    assert inv_resp.status_code == 201
    inv_id = inv_resp.json()["data"]["id"]

    # 1. Partial payment 4,000.00
    pay1_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "4000.00",
            "payment_method": "UPI",
            "transaction_reference": "TXN-APR27-001",
            "notes": "First installment",
        },
    )
    assert pay1_resp.status_code == 201
    p1 = pay1_resp.json()["data"]
    assert p1["payment_number"].startswith("PAY-OG-KOR-")
    assert Decimal(str(p1["amount"])) == Decimal("4000.00")
    assert p1["status"] == "COMPLETED"

    # Verify invoice status is now PARTIALLY_PAID
    inv_check1 = client.get(
        f"/api/v1/invoices/{inv_id}",
        headers={"Authorization": f"Bearer {admin_token}"},
    ).json()["data"]
    assert inv_check1["status"] == "PARTIALLY_PAID"
    assert Decimal(str(inv_check1["paid_amount"])) == Decimal("4000.00")
    assert Decimal(str(inv_check1["balance_amount"])) == Decimal("6000.00")

    # 2. Overpayment attempt: Remaining balance is 6000, attempt to pay 6000.01
    overpay_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "6000.01",
            "payment_method": "BANK_TRANSFER",
        },
    )
    assert overpay_resp.status_code == 409
    assert "exceeds outstanding invoice balance" in overpay_resp.json()["error"]["message"]

    # 3. Pay remaining 6,000.00 exactly
    pay2_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "6000.00",
            "payment_method": "BANK_TRANSFER",
            "transaction_reference": "TXN-APR27-002",
        },
    )
    assert pay2_resp.status_code == 201

    # Verify invoice is now PAID and fully settled
    inv_check2 = client.get(
        f"/api/v1/invoices/{inv_id}",
        headers={"Authorization": f"Bearer {admin_token}"},
    ).json()["data"]
    assert inv_check2["status"] == "PAID"
    assert Decimal(str(inv_check2["paid_amount"])) == Decimal("10000.00")
    assert Decimal(str(inv_check2["balance_amount"])) == Decimal("0.00")
    assert len(inv_check2["payments"]) == 2

    # 4. Attempt to pay on already fully settled invoice returns 409
    pay3_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "100.00",
            "payment_method": "CASH",
        },
    )
    assert pay3_resp.status_code == 409
    assert "settled" in pay3_resp.json()["error"]["message"].lower()


def test_duplicate_transaction_reference_rejected(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)
    res_id = _admit_resident(client, admin_token, kor_id, "Meera Nair", "9111122226")

    inv_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2026-07",
            "billing_period_start": "2026-07-01",
            "billing_period_end": "2026-07-31",
            "issue_date": "2026-07-01",
            "due_date": "2026-07-05",
            "invoice_type": "RENT",
            "rent_amount": "15000.00",
        },
    )
    inv_id = inv_resp.json()["data"]["id"]

    # First payment with unique reference
    p1 = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "5000.00",
            "payment_method": "UPI",
            "transaction_reference": "UPI-REF-UNIQUE-999",
        },
    )
    assert p1.status_code == 201

    # Second payment with same transaction reference must be rejected with 409
    p2 = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "5000.00",
            "payment_method": "UPI",
            "transaction_reference": "UPI-REF-UNIQUE-999",
        },
    )
    assert p2.status_code == 409
    assert "transaction reference" in p2.json()["error"]["message"].lower()


def test_payment_refund_flow_and_balance_reinstatement(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)
    res_id = _admit_resident(client, admin_token, kor_id, "Devika Pillai", "9111122227")

    # Use a future due_date so that after refund, status returns to ISSUED (not OVERDUE)
    inv_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2027-05",
            "billing_period_start": "2027-05-01",
            "billing_period_end": "2027-05-31",
            "issue_date": "2027-05-01",
            "due_date": "2027-05-05",
            "invoice_type": "RENT",
            "rent_amount": "9000.00",
        },
    )
    inv_id = inv_resp.json()["data"]["id"]

    # Fully pay invoice
    pay_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "9000.00",
            "payment_method": "UPI",
            "transaction_reference": "REFUND-TEST-001",
        },
    )
    assert pay_resp.status_code == 201
    pay_id = pay_resp.json()["data"]["id"]

    # Invoice is PAID
    inv_before = client.get(
        f"/api/v1/invoices/{inv_id}",
        headers={"Authorization": f"Bearer {admin_token}"},
    ).json()["data"]
    assert inv_before["status"] == "PAID"

    # Cannot cancel invoice because payment is recorded
    cancel_resp = client.post(
        f"/api/v1/invoices/{inv_id}/cancel",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert cancel_resp.status_code == 409
    assert "recorded payments" in cancel_resp.json()["error"]["message"]

    # Refund the payment
    refund_resp = client.post(
        f"/api/v1/payments/{pay_id}/refund",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"reason": "Incorrect bank account debited"},
    )
    assert refund_resp.status_code == 200
    ref_data = refund_resp.json()["data"]
    assert ref_data["status"] == "REFUNDED"

    # Invoice balance is reinstated and status is ISSUED (future due_date)
    inv_after = client.get(
        f"/api/v1/invoices/{inv_id}",
        headers={"Authorization": f"Bearer {admin_token}"},
    ).json()["data"]
    assert inv_after["status"] == "ISSUED"
    assert Decimal(str(inv_after["paid_amount"])) == Decimal("0.00")
    assert Decimal(str(inv_after["balance_amount"])) == Decimal("9000.00")


def test_property_manager_and_staff_scoping(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    manager_token = get_token(client, "manager@originpg.com", "Manager@123456")
    staff_token = get_token(client, "staff@originpg.com", "Staff@123456")
    kor_id, hsr_id, ind_id = _setup_kor_hsr_ind(client, admin_token)

    # Resident admitted in KOR (assigned to Manager & Staff)
    res_kor = _admit_resident(client, admin_token, kor_id, "Kiran Rao", "9111122228")
    # Resident admitted in IND (NOT assigned to Manager or Staff)
    res_ind = _admit_resident(client, admin_token, ind_id, "Ishaan Sen", "9111122229")

    # 1. Manager can create invoice in assigned KOR property
    mgr_inv_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_kor,
            "billing_month": "2026-05",
            "billing_period_start": "2026-05-01",
            "billing_period_end": "2026-05-31",
            "issue_date": "2026-05-01",
            "due_date": "2026-05-05",
            "invoice_type": "RENT",
            "rent_amount": "8000.00",
        },
    )
    assert mgr_inv_resp.status_code == 201
    kor_inv_id = mgr_inv_resp.json()["data"]["id"]

    # 2. Manager CANNOT create invoice in unassigned IND property
    mgr_ind_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={
            "property_id": ind_id,
            "resident_id": res_ind,
            "billing_month": "2026-05",
            "billing_period_start": "2026-05-01",
            "billing_period_end": "2026-05-31",
            "issue_date": "2026-05-01",
            "due_date": "2026-05-05",
            "invoice_type": "RENT",
            "rent_amount": "8000.00",
        },
    )
    assert mgr_ind_resp.status_code == 403

    # 3. Staff CANNOT create invoices (only Super Admin and Property Managers can)
    staff_create_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_kor,
            "billing_month": "2026-04",
            "billing_period_start": "2026-04-01",
            "billing_period_end": "2026-04-30",
            "issue_date": "2026-04-01",
            "due_date": "2026-04-05",
            "invoice_type": "RENT",
            "rent_amount": "8000.00",
        },
    )
    assert staff_create_resp.status_code == 403

    # 4. Staff CAN record payment for invoice in assigned property
    staff_pay_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={
            "invoice_id": kor_inv_id,
            "amount": "2000.00",
            "payment_method": "CASH",
        },
    )
    assert staff_pay_resp.status_code == 201
    pay_id = staff_pay_resp.json()["data"]["id"]

    # 5. Staff CANNOT refund payments
    staff_refund_resp = client.post(
        f"/api/v1/payments/{pay_id}/refund",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert staff_refund_resp.status_code == 403


def test_resident_isolation_and_mobile_endpoints(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    resident_token = get_token(client, "resident@originpg.com", "Resident@123456", client_type="resident_mobile")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)

    # Note: Seeded resident has phone "9876543213"
    # Find or admit resident with phone matching seeded resident user
    res_list = client.get(
        "/api/v1/residents?search=Rahul",
        headers={"Authorization": f"Bearer {admin_token}"},
    ).json()["data"]

    if res_list:
        res_id = res_list[0]["id"]
    else:
        res_id = _admit_resident(client, admin_token, kor_id, "Rahul Sharma", "9876543213")

    # Create an invoice for this resident
    inv_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2026-03",
            "billing_period_start": "2026-03-01",
            "billing_period_end": "2026-03-31",
            "issue_date": "2026-03-01",
            "due_date": "2026-03-05",
            "invoice_type": "RENT",
            "rent_amount": "9500.00",
        },
    )
    assert inv_resp.status_code == 201
    my_inv_id = inv_resp.json()["data"]["id"]

    # 1. Resident can retrieve their own invoices via /me
    my_invs = client.get(
        "/api/v1/invoices/me",
        headers={"Authorization": f"Bearer {resident_token}"},
    )
    assert my_invs.status_code == 200
    my_inv_data = my_invs.json()["data"]
    assert any(inv["id"] == my_inv_id for inv in my_inv_data)

    # 2. Resident can view the specific invoice details
    detail_resp = client.get(
        f"/api/v1/invoices/{my_inv_id}",
        headers={"Authorization": f"Bearer {resident_token}"},
    )
    assert detail_resp.status_code == 200
    assert detail_resp.json()["data"]["id"] == my_inv_id

    # 3. Resident CANNOT access other invoices or admin creation endpoints
    bad_create = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {resident_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2026-02",
            "billing_period_start": "2026-02-01",
            "billing_period_end": "2026-02-28",
            "issue_date": "2026-02-01",
            "due_date": "2026-02-05",
            "invoice_type": "RENT",
            "rent_amount": "9500.00",
        },
    )
    assert bad_create.status_code == 403

    # 4. Resident CANNOT record payments directly via API (must be staff/admin or payment gateway)
    bad_pay = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {resident_token}"},
        json={
            "invoice_id": my_inv_id,
            "amount": "5000.00",
            "payment_method": "UPI",
        },
    )
    assert bad_pay.status_code == 403


def test_financial_summary_aggregate_and_per_property(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, hsr_id, _ = _setup_kor_hsr_ind(client, admin_token)

    # Check summary endpoint
    summary_resp = client.get(
        "/api/v1/invoices/summary",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert summary_resp.status_code == 200
    s_data = summary_resp.json()["data"]
    assert "total_invoiced" in s_data
    assert "total_collected" in s_data
    assert "total_outstanding" in s_data
    assert "property_summaries" in s_data
    assert isinstance(s_data["property_summaries"], list)


def test_audit_logs_recorded_for_invoices_and_payments(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ind(client, admin_token)
    res_id = _admit_resident(client, admin_token, kor_id, "Tanya Sen", "9111122230")

    # 1. Create invoice -> audit log
    inv_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2026-01",
            "billing_period_start": "2026-01-01",
            "billing_period_end": "2026-01-31",
            "issue_date": "2026-01-01",
            "due_date": "2026-01-05",
            "invoice_type": "RENT",
            "rent_amount": "7500.00",
        },
    )
    inv_id = inv_resp.json()["data"]["id"]

    # 2. Record payment -> audit log
    pay_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id,
            "amount": "7500.00",
            "payment_method": "UPI",
            "transaction_reference": "AUDIT-LOG-TXN-01",
        },
    )
    pay_id = pay_resp.json()["data"]["id"]

    # 3. Query audit logs
    audit_resp = client.get(
        "/api/v1/audit-logs",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert audit_resp.status_code == 200
    logs_data = audit_resp.json()["data"]
    items = logs_data["items"]
    actions = {item["action"] for item in items}
    assert "INVOICE_CREATED" in actions
    assert "PAYMENT_RECORDED" in actions
