# PG Management — Decision Record: payments.invoice_id ON DELETE Behavior

**Document:** `migration_proposal_review/production_plan_v3_1/03_payment_fk_decision_v3_1.md`  
**Target Constraint:** `payments_invoice_id_fkey` ON `payments (invoice_id)` REFERENCES `invoices (id)`  
**Decision:** **ON DELETE RESTRICT (CONFIRMED & MANDATED)**  
**Status:** ARCHITECTURAL DECISION RECORD & REGULATORY COMPLIANCE AUDIT  

---

## 1. Problem Statement & Historical Context

During earlier migration proposal drafts (V1/V2), inconsistent statements were recorded regarding the `ON DELETE` action for `payments.invoice_id`:
- Certain draft comparison tables listed `ON DELETE CASCADE`.
- The active model declaration and Alembic migrations specify `ON DELETE RESTRICT`.

This document performs an exhaustive, multi-layered audit across the active codebase, migration history, PostgreSQL physical schema, and accounting principles to definitively establish the required `ON DELETE` rule.

---

## 2. Multi-Layer Evidentiary Audit

### 2.1 Active SQLAlchemy ORM Models
- **`Payment` Model (`app/models/payment.py` line 26):**
  ```python
  invoice_id: Mapped[uuid.UUID] = mapped_column(
      sa.Uuid(as_uuid=True),
      sa.ForeignKey("invoices.id", ondelete="RESTRICT"),
      nullable=False,
      index=True,
  )
  ```
  The active `Payment` model explicitly declares `ondelete="RESTRICT"`.
- **`Invoice` Model (`app/models/invoice.py` lines 42–43):**
  ```python
  # Relationships
  resident: Mapped["Resident"] = relationship("Resident", back_populates="invoices")
  payments: Mapped[List["Payment"]] = relationship("Payment", back_populates="invoice")
  ```
  The relationship does **not** specify `cascade="all, delete-orphan"`. SQLAlchemy will not cascade delete payments when an invoice is deleted.

### 2.2 Active Alembic Migration Tree
- **Initial Active Migration (`migrations/versions/bd0a1cc93d5d_initial_schema.py` line 371):**
  ```python
  sa.ForeignKeyConstraint(['invoice_id'], ['invoices.id'], ondelete='RESTRICT'),
  ```
  When the active database is created fresh from Alembic head, it creates `payments.invoice_id` with `ON DELETE RESTRICT`.
- **Receipts Migration (`migrations/versions/f1c4a0e3d2b1_add_receipts.py` line 23):**
  ```python
  sa.ForeignKeyConstraint(["invoice_id"], ["invoices.id"], ondelete="RESTRICT"),
  ```
  Both payment and receipt foreign keys referencing `invoices.id` are defined with `RESTRICT`.

### 2.3 Baseline Legacy Schema in `pg_management`
- **Legacy Constraint Definition (`fk_payments_invoice_id_property_id`):**
  ```sql
  FOREIGN KEY (invoice_id, property_id) REFERENCES invoices(id, property_id) ON DELETE RESTRICT
  ```
  The legacy schema originally enforced `ON DELETE RESTRICT`.

### 2.4 Accounting & Financial Ledger Integrity
- Payments represent real-world monetary movements (direct UPI transfers, bank credits, cash receipts) tied to unique transaction IDs and legal tax invoices.
- If an administrator or background task attempts to delete an `Invoice` that has already received settled payments, cascading the deletion would:
  1. Destroy the payment ledger and bank reconciliation records.
  2. Create orphan digital receipts (`receipts.payment_id` references payments).
  3. Violate standard accounting principles and regulatory audit requirements.
- By enforcing `ON DELETE RESTRICT`, PostgreSQL halts any accidental invoice deletion at the database engine level, raising an `IntegrityError` unless all payment rows are formally reconciled or voided.

### 2.5 Clarification: Why `payment_links` Uses CASCADE
- In `app/models/payment_link.py`:
  ```python
  invoice_id: Mapped[uuid.UUID] = mapped_column(sa.ForeignKey("invoices.id", ondelete="CASCADE"))
  ```
- Payment links are transient, short-lived checkout tokens (cryptographic URLs for UPI self-checkout). If an unpaid invoice is canceled, its uncompleted checkout link should naturally be invalidated and removed.
- Earlier draft documents conflated ephemeral `payment_links.invoice_id` (`CASCADE`) with durable `payments.invoice_id` (`RESTRICT`).

---

## 3. Empirical Sandbox Test Verification

In the disposable sandbox (`pg_reconcile_v3_1_sandbox_test`), the following regression test was executed:
1. Created an `Invoice` ($7,000 rent).
2. Created a settled `Payment` referencing that invoice.
3. Attempted to execute `session.delete(invoice)` and `session.flush()`.
4. **Result:** PostgreSQL blocked the operation and raised `psycopg.errors.ForeignKeyViolation: update or delete on table "invoices" violates foreign key constraint "payments_invoice_id_fkey" on table "payments"`.
5. SQLAlchemy caught `IntegrityError` and rolled back cleanly:
   `PASS: Deleting invoice with existing payment was correctly RESTRICTED (IntegrityError).`

---

## 4. Final Architectural Mandate

The unified V3.1 reconciliation script [`01_unified_reconcile_pg_management_v3_1.sql`](file:///D:/PG_Management/migration_proposal_review/production_plan_v3_1/01_unified_reconcile_pg_management_v3_1.sql) strictly enforces:

```sql
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_invoice_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_invoice_id_fkey
    FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE RESTRICT;
```

This decision:
- Matches the active `Payment` model 100%.
- Matches fresh active Alembic migrations 100%.
- Preserves full accounting and transaction history.
- Prevents data loss under concurrent cancellation attempts.
