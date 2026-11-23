"""add payment reservations and idempotency

Revision ID: 4c11d205aa12
Revises: f1c4a0e3d2b1
"""
from alembic import op
import sqlalchemy as sa
revision="4c11d205aa12"; down_revision="f1c4a0e3d2b1"; branch_labels=None; depends_on=None
def upgrade():
    # NULL preserves existing historical rows; PostgreSQL permits multiple NULLs
    # in a unique constraint. New API-created records always provide both values.
    op.add_column("payments", sa.Column("idempotency_key", sa.String(128), nullable=True)); op.add_column("payments", sa.Column("reservation_expires_at", sa.DateTime(timezone=True), nullable=True)); op.create_index("ix_payments_reservation_expires_at","payments",["reservation_expires_at"]); op.create_unique_constraint("uq_payment_invoice_idempotency","payments",["invoice_id","idempotency_key"])
def downgrade():
    op.drop_constraint("uq_payment_invoice_idempotency","payments",type_="unique"); op.drop_index("ix_payments_reservation_expires_at",table_name="payments"); op.drop_column("payments","reservation_expires_at"); op.drop_column("payments","idempotency_key")
