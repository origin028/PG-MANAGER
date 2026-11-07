"""add device_tokens table

Revision ID: a1b2c3d4e5f6
Revises: 9a81b2c3d4e5
"""
from alembic import op
import sqlalchemy as sa

revision = "a1b2c3d4e5f6"
down_revision = "9a81b2c3d4e5"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "device_tokens",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_token", sa.String(255), nullable=False),
        sa.Column("platform", sa.String(50), nullable=False, server_default="android"),
        sa.Column("device_name", sa.String(100), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "device_token", name="uq_user_device_token"),
    )
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])
    op.create_index("ix_device_tokens_device_token", "device_tokens", ["device_token"])


def downgrade():
    op.drop_index("ix_device_tokens_device_token", table_name="device_tokens")
    op.drop_index("ix_device_tokens_user_id", table_name="device_tokens")
    op.drop_table("device_tokens")
