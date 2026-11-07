"""add payment module tables, reservations, and reconcile schema

Revision ID: b2c3d4e5f6a7
Revises: 7d2e4f6a8b10
Create Date: 2026-10-30 16:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'b2c3d4e5f6a7'
down_revision: Union[str, Sequence[str], None] = '7d2e4f6a8b10'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    curr_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if curr_db != "pg_management_test":
        raise RuntimeError(f"ABORTING: Refusing to run on database {curr_db}! Must be pg_management_test.")

    # 1. Payment Reservations
    op.create_table(
        'payment_reservations',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('invoice_id', sa.Uuid(as_uuid=True), sa.ForeignKey('invoices.id', ondelete='CASCADE'), nullable=False),
        sa.Column('resident_id', sa.Uuid(as_uuid=True), sa.ForeignKey('residents.id', ondelete='SET NULL'), nullable=True),
        sa.Column('payment_id', sa.Uuid(as_uuid=True), sa.ForeignKey('payments.id', ondelete='SET NULL'), nullable=True),
        sa.Column('amount', sa.Numeric(10, 2), nullable=False),
        sa.Column('idempotency_key', sa.String(128), unique=True, nullable=False),
        sa.Column('status', sa.String(32), server_default='PENDING', nullable=False),
        sa.Column('reservation_expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_payment_reservations_invoice_id', 'payment_reservations', ['invoice_id'])
    op.create_index('ix_payment_reservations_resident_id', 'payment_reservations', ['resident_id'])
    op.create_index('ix_payment_reservations_payment_id', 'payment_reservations', ['payment_id'])
    op.create_index('ix_payment_reservations_idempotency_key', 'payment_reservations', ['idempotency_key'])
    op.create_index('ix_payment_reservations_status', 'payment_reservations', ['status'])
    op.create_index('ix_payment_reservations_expires_at', 'payment_reservations', ['reservation_expires_at'])

    # 2. Receipts
    op.create_table(
        'receipts',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('payment_id', sa.Uuid(as_uuid=True), sa.ForeignKey('payments.id', ondelete='RESTRICT'), unique=True, nullable=False),
        sa.Column('invoice_id', sa.Uuid(as_uuid=True), sa.ForeignKey('invoices.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('receipt_number', sa.String(100), unique=True, nullable=False),
        sa.Column('amount', sa.Numeric(10, 2), nullable=False),
        sa.Column('issued_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('whatsapp_status', sa.String(50), server_default='PENDING', nullable=False),
        sa.Column('whatsapp_attempts', sa.Integer(), server_default='0', nullable=False),
        sa.Column('next_retry_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('last_delivery_error', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_receipts_payment_id', 'receipts', ['payment_id'])
    op.create_index('ix_receipts_invoice_id', 'receipts', ['invoice_id'])
    op.create_index('ix_receipts_receipt_number', 'receipts', ['receipt_number'])
    op.create_index('ix_receipts_whatsapp_status', 'receipts', ['whatsapp_status'])

    # 3. Processed Webhook Events
    op.create_table(
        'processed_webhook_events',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('provider', sa.String(50), nullable=False),
        sa.Column('event_id', sa.String(150), unique=True, nullable=False),
        sa.Column('event_type', sa.String(100), nullable=False),
        sa.Column('status', sa.String(50), server_default='PROCESSED', nullable=False),
        sa.Column('processed_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_processed_webhook_events_provider', 'processed_webhook_events', ['provider'])
    op.create_index('ix_processed_webhook_events_event_id', 'processed_webhook_events', ['event_id'])
    op.create_index('ix_processed_webhook_events_event_type', 'processed_webhook_events', ['event_type'])

    # 4. Payment Links
    op.create_table(
        'payment_links',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('payment_id', sa.Uuid(as_uuid=True), sa.ForeignKey('payments.id', ondelete='CASCADE'), nullable=False),
        sa.Column('invoice_id', sa.Uuid(as_uuid=True), sa.ForeignKey('invoices.id', ondelete='CASCADE'), nullable=False),
        sa.Column('resident_id', sa.Uuid(as_uuid=True), sa.ForeignKey('residents.id', ondelete='CASCADE'), nullable=False),
        sa.Column('token_hash', sa.String(64), unique=True, nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_revoked', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('whatsapp_sent', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('whatsapp_message_id', sa.String(150), nullable=True),
        sa.Column('whatsapp_last_error', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_payment_links_payment_id', 'payment_links', ['payment_id'])
    op.create_index('ix_payment_links_invoice_id', 'payment_links', ['invoice_id'])
    op.create_index('ix_payment_links_resident_id', 'payment_links', ['resident_id'])
    op.create_index('ix_payment_links_token_hash', 'payment_links', ['token_hash'])
    op.create_index('ix_payment_links_expires_at', 'payment_links', ['expires_at'])
    op.create_index('ix_payment_links_is_revoked', 'payment_links', ['is_revoked'])

    # 5. Device Tokens (if not exists)
    conn.execute(sa.text("""
        ALTER TABLE users ADD COLUMN IF NOT EXISTS approval_status VARCHAR(50) NOT NULL DEFAULT 'APPROVED';
        CREATE INDEX IF NOT EXISTS ix_users_approval_status ON users(approval_status);

        CREATE TABLE IF NOT EXISTS device_tokens (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL,
            token VARCHAR(512) UNIQUE NOT NULL,
            device_type VARCHAR(50) NOT NULL DEFAULT 'ANDROID',
            is_active BOOLEAN NOT NULL DEFAULT TRUE,
            last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT fk_device_tokens_user_id FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS ix_device_tokens_user_id ON device_tokens(user_id);
    """))

    # 6. Reconcile Payments Columns & Constraints
    conn.execute(sa.text("""
        ALTER TABLE payments DROP CONSTRAINT IF EXISTS fk_payments_invoice_id_property_id;
        ALTER TABLE payments DROP CONSTRAINT IF EXISTS fk_payments_resident_id_property_id;
        ALTER TABLE payments DROP CONSTRAINT IF EXISTS uq_payments_id_property_id;

        ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_property_id_fkey;
        ALTER TABLE payments ADD CONSTRAINT payments_property_id_fkey FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE RESTRICT;

        ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_invoice_id_fkey;
        ALTER TABLE payments ADD CONSTRAINT payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT;

        ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_resident_id_fkey;
        ALTER TABLE payments ADD CONSTRAINT payments_resident_id_fkey FOREIGN KEY (resident_id) REFERENCES residents(id) ON DELETE RESTRICT;

        ALTER TABLE payments ALTER COLUMN company_id DROP NOT NULL;
        ALTER TABLE payments ALTER COLUMN payment_date DROP NOT NULL;
        ALTER TABLE payments ALTER COLUMN payment_method DROP NOT NULL;

        ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(50) NOT NULL DEFAULT 'UPI';
        ALTER TABLE payments ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128);
        ALTER TABLE payments ADD COLUMN IF NOT EXISTS reservation_expires_at TIMESTAMPTZ;
        ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_order_id VARCHAR(150);
        ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_payment_id VARCHAR(150);
        ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_signature VARCHAR(255);
        ALTER TABLE payments ADD COLUMN IF NOT EXISTS receipt_url VARCHAR(512);
        ALTER TABLE payments ADD COLUMN IF NOT EXISTS failure_reason TEXT;

        ALTER TABLE payments ALTER COLUMN paid_at DROP NOT NULL;
        ALTER TABLE payments ALTER COLUMN paid_at DROP DEFAULT;
        ALTER TABLE payments ALTER COLUMN status SET DEFAULT 'PENDING';

        ALTER TABLE payments DROP CONSTRAINT IF EXISTS uq_payments_gateway_payment_id;
        ALTER TABLE payments ADD CONSTRAINT uq_payments_gateway_payment_id UNIQUE (gateway_payment_id);

        ALTER TABLE payments DROP CONSTRAINT IF EXISTS uq_payment_invoice_idempotency;
        ALTER TABLE payments ADD CONSTRAINT uq_payment_invoice_idempotency UNIQUE (invoice_id, idempotency_key);

        CREATE INDEX IF NOT EXISTS ix_payments_reservation_expires_at ON payments(reservation_expires_at);
        CREATE INDEX IF NOT EXISTS ix_payments_status ON payments(status);
    """))

    # 7. Reconcile Invoices Columns & Constraints
    conn.execute(sa.text("""
        ALTER TABLE invoices DROP CONSTRAINT IF EXISTS fk_invoices_resident_id_property_id;
        ALTER TABLE invoices DROP CONSTRAINT IF EXISTS uq_invoices_id_property_id;
        ALTER TABLE invoices DROP CONSTRAINT IF EXISTS uq_resident_billing_month_type;

        ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_property_id_fkey;
        ALTER TABLE invoices ADD CONSTRAINT invoices_property_id_fkey FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE RESTRICT;

        ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_resident_id_fkey;
        ALTER TABLE invoices ADD CONSTRAINT invoices_resident_id_fkey FOREIGN KEY (resident_id) REFERENCES residents(id) ON DELETE RESTRICT;

        ALTER TABLE invoices ALTER COLUMN company_id DROP NOT NULL;
        ALTER TABLE invoices ALTER COLUMN billing_period_start DROP NOT NULL;
        ALTER TABLE invoices ALTER COLUMN billing_period_end DROP NOT NULL;
        ALTER TABLE invoices ALTER COLUMN issue_date DROP NOT NULL;
        ALTER TABLE invoices ALTER COLUMN rent_amount DROP NOT NULL;
        ALTER TABLE invoices ALTER COLUMN additional_charges DROP NOT NULL;
        ALTER TABLE invoices ALTER COLUMN discount_amount DROP NOT NULL;
        ALTER TABLE invoices ALTER COLUMN total_amount DROP NOT NULL;
        ALTER TABLE invoices ALTER COLUMN balance_amount DROP NOT NULL;

        ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00;
        UPDATE invoices SET amount = total_amount WHERE amount = 0.00 AND total_amount IS NOT NULL;

        ALTER TABLE invoices ALTER COLUMN status SET DEFAULT 'PENDING';
        ALTER TABLE invoices ALTER COLUMN notes TYPE TEXT;

        ALTER TABLE invoices DROP CONSTRAINT IF EXISTS uq_resident_invoice_cycle;
        ALTER TABLE invoices ADD CONSTRAINT uq_resident_invoice_cycle UNIQUE (resident_id, billing_month, invoice_type);
    """))

    # 8. Reconcile Residents Columns & Constraints
    conn.execute(sa.text("""
        ALTER TABLE residents DROP CONSTRAINT IF EXISTS fk_residents_bed_id_property_id;
        ALTER TABLE residents DROP CONSTRAINT IF EXISTS fk_residents_room_id_property_id;
        ALTER TABLE residents DROP CONSTRAINT IF EXISTS uq_residents_id_property_id;

        ALTER TABLE residents ALTER COLUMN company_id DROP NOT NULL;
        ALTER TABLE residents ALTER COLUMN full_name DROP NOT NULL;
        ALTER TABLE residents ALTER COLUMN phone DROP NOT NULL;
        ALTER TABLE residents ALTER COLUMN monthly_rent DROP NOT NULL;
        ALTER TABLE residents ALTER COLUMN security_deposit DROP NOT NULL;
        ALTER TABLE residents ALTER COLUMN kyc_status DROP NOT NULL;

        ALTER TABLE residents ADD COLUMN IF NOT EXISTS id_proof_document_path VARCHAR(512);

        ALTER TABLE residents ALTER COLUMN status SET DEFAULT 'ACTIVE';
        ALTER TABLE residents ALTER COLUMN check_in_date SET DEFAULT CURRENT_DATE;

        ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_user_id_fkey;
        ALTER TABLE residents ADD CONSTRAINT residents_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

        ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_property_id_fkey;
        ALTER TABLE residents ADD CONSTRAINT residents_property_id_fkey FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE RESTRICT;

        ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_room_id_fkey;
        ALTER TABLE residents ADD CONSTRAINT residents_room_id_fkey FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE SET NULL;

        ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_bed_id_fkey;
        ALTER TABLE residents ADD CONSTRAINT residents_bed_id_fkey FOREIGN KEY (bed_id) REFERENCES beds(id) ON DELETE SET NULL;
    """))


def downgrade() -> None:
    conn = op.get_bind()
    curr_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if curr_db != "pg_management_test":
        raise RuntimeError(f"ABORTING: Refusing to run on database {curr_db}! Must be pg_management_test.")

    op.drop_table('payment_links')
    op.drop_table('processed_webhook_events')
    op.drop_table('receipts')
    op.drop_table('payment_reservations')
