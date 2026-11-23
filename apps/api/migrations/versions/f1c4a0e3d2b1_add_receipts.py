"""add durable payment receipts

Revision ID: f1c4a0e3d2b1
Revises: bd0a1cc93d5d
"""
from alembic import op
import sqlalchemy as sa

revision = "f1c4a0e3d2b1"
down_revision = "bd0a1cc93d5d"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("receipts",
        sa.Column("payment_id", sa.Uuid(), nullable=False), sa.Column("invoice_id", sa.Uuid(), nullable=False),
        sa.Column("receipt_number", sa.String(100), nullable=False), sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("whatsapp_status", sa.String(50), nullable=False), sa.Column("whatsapp_attempts", sa.Integer(), nullable=False),
        sa.Column("next_retry_at", sa.DateTime(timezone=True)), sa.Column("last_delivery_error", sa.Text()),
        sa.Column("id", sa.Uuid(), nullable=False), sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False), sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.ForeignKeyConstraint(["payment_id"], ["payments.id"], ondelete="RESTRICT"), sa.ForeignKeyConstraint(["invoice_id"], ["invoices.id"], ondelete="RESTRICT"), sa.PrimaryKeyConstraint("id"), sa.UniqueConstraint("payment_id"), sa.UniqueConstraint("receipt_number"))
    op.create_index("ix_receipts_payment_id", "receipts", ["payment_id"])
    op.create_index("ix_receipts_invoice_id", "receipts", ["invoice_id"])
    op.create_index("ix_receipts_receipt_number", "receipts", ["receipt_number"])
    op.create_index("ix_receipts_whatsapp_status", "receipts", ["whatsapp_status"])


def downgrade():
    op.drop_table("receipts")
