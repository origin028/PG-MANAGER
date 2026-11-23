"""add resident approval_status and otp_verifications table

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
"""
from alembic import op
import sqlalchemy as sa

revision = "b2c3d4e5f6a7"
down_revision = "a1b2c3d4e5f6"
branch_labels = None
depends_on = None


def upgrade():
    # 1. Add approval_status to users with 'APPROVED' default so existing users remain fully approved
    op.add_column(
        "users",
        sa.Column(
            "approval_status",
            sa.String(50),
            nullable=False,
            server_default="APPROVED",
        ),
    )
    op.create_index("ix_users_approval_status", "users", ["approval_status"])

    # 2. Create otp_verifications table
    op.create_table(
        "otp_verifications",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("phone", sa.String(30), nullable=False),
        sa.Column("otp_hash", sa.String(255), nullable=False),
        sa.Column("salt", sa.String(64), nullable=False),
        sa.Column("purpose", sa.String(50), nullable=False, server_default="RESIDENT_REGISTRATION"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("max_attempts", sa.Integer(), nullable=False, server_default="3"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_otp_verifications_phone", "otp_verifications", ["phone"])
    op.create_index("ix_otp_verifications_purpose", "otp_verifications", ["purpose"])
    op.create_index("ix_otp_verifications_expires_at", "otp_verifications", ["expires_at"])
    op.create_index("ix_otp_verifications_is_verified", "otp_verifications", ["is_verified"])


def downgrade():
    op.drop_index("ix_otp_verifications_is_verified", table_name="otp_verifications")
    op.drop_index("ix_otp_verifications_expires_at", table_name="otp_verifications")
    op.drop_index("ix_otp_verifications_purpose", table_name="otp_verifications")
    op.drop_index("ix_otp_verifications_phone", table_name="otp_verifications")
    op.drop_table("otp_verifications")

    op.drop_index("ix_users_approval_status", table_name="users")
    op.drop_column("users", "approval_status")
