"""add payment_links table

Revision ID: 9a81b2c3d4e5
Revises: 7c32e912ab01
"""
from alembic import op
import sqlalchemy as sa

revision = "9a81b2c3d4e5"
down_revision = "7c32e912ab01"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "payment_links",
        sa.Column("payment_id", sa.Uuid(), nullable=False),
        sa.Column("invoice_id", sa.Uuid(), nullable=False),
        sa.Column("resident_id", sa.Uuid(), nullable=False),
        sa.Column("token_hash", sa.String(64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_revoked", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("whatsapp_sent", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("whatsapp_message_id", sa.String(150), nullable=True),
        sa.Column("whatsapp_last_error", sa.Text(), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.ForeignKeyConstraint(["payment_id"], ["payments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["invoice_id"], ["invoices.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["resident_id"], ["residents.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash", name="uq_payment_link_token_hash"),
    )
    op.create_index("ix_payment_links_payment_id", "payment_links", ["payment_id"])
    op.create_index("ix_payment_links_invoice_id", "payment_links", ["invoice_id"])
    op.create_index("ix_payment_links_resident_id", "payment_links", ["resident_id"])
    op.create_index("ix_payment_links_token_hash", "payment_links", ["token_hash"])
    op.create_index("ix_payment_links_expires_at", "payment_links", ["expires_at"])
    op.create_index("ix_payment_links_is_revoked", "payment_links", ["is_revoked"])


def downgrade():
    op.drop_index("ix_payment_links_is_revoked", table_name="payment_links")
    op.drop_index("ix_payment_links_expires_at", table_name="payment_links")
    op.drop_index("ix_payment_links_token_hash", table_name="payment_links")
    op.drop_index("ix_payment_links_resident_id", "payment_links")
    op.drop_index("ix_payment_links_invoice_id", "payment_links")
    op.drop_index("ix_payment_links_payment_id", "payment_links")
    op.drop_table("payment_links")
