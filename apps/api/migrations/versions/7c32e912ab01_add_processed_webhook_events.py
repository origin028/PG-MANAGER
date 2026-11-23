"""add processed_webhook_events table

Revision ID: 7c32e912ab01
Revises: 4c11d205aa12
"""
from alembic import op
import sqlalchemy as sa

revision = "7c32e912ab01"
down_revision = "4c11d205aa12"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "processed_webhook_events",
        sa.Column("provider", sa.String(50), nullable=False),
        sa.Column("event_id", sa.String(150), nullable=False),
        sa.Column("event_type", sa.String(100), nullable=False),
        sa.Column("status", sa.String(50), nullable=False, server_default="PROCESSED"),
        sa.Column("processed_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("event_id", name="uq_processed_webhook_event_id"),
    )
    op.create_index("ix_processed_webhook_events_provider", "processed_webhook_events", ["provider"])
    op.create_index("ix_processed_webhook_events_event_id", "processed_webhook_events", ["event_id"])
    op.create_index("ix_processed_webhook_events_event_type", "processed_webhook_events", ["event_type"])


def downgrade():
    op.drop_index("ix_processed_webhook_events_event_type", table_name="processed_webhook_events")
    op.drop_index("ix_processed_webhook_events_event_id", table_name="processed_webhook_events")
    op.drop_index("ix_processed_webhook_events_provider", table_name="processed_webhook_events")
    op.drop_table("processed_webhook_events")
