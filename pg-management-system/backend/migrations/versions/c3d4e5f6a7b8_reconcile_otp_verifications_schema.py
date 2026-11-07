"""reconcile otp_verifications schema for resident registration

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-10-30 17:40:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c3d4e5f6a7b8'
down_revision: Union[str, Sequence[str], None] = 'b2c3d4e5f6a7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    curr_db = conn.execute(sa.text("SELECT current_database()")).scalar()

    # 1. Strict Database Safety Guard: Abort unless running against pg_management_test or test runner DB
    if curr_db != "pg_management_test" and not curr_db.startswith("test_"):
        err_msg = f"ABORTING: Migration {revision} is strictly restricted to 'pg_management_test'. Attempted execution against database: '{curr_db}'."
        raise RuntimeError(err_msg)

    # 2. Strict Precondition Check: Abort unless table has exactly zero rows
    row_count = conn.execute(sa.text("SELECT count(*) FROM otp_verifications")).scalar()
    if row_count != 0:
        err_msg = f"ABORTING: Table 'otp_verifications' contains {row_count} rows. To prevent data corruption, this migration strictly requires zero rows."
        raise RuntimeError(err_msg)

    inspector = sa.inspect(conn)
    existing_cols = {c['name'] for c in inspector.get_columns('otp_verifications')}
    existing_indexes = {i['name'] for i in inspector.get_indexes('otp_verifications')}

    # 3. Drop legacy index and columns if present
    if 'ix_otp_verifications_email' in existing_indexes:
        op.drop_index('ix_otp_verifications_email', table_name='otp_verifications')
    if 'email' in existing_cols:
        op.drop_column('otp_verifications', 'email')
    if 'is_used' in existing_cols:
        op.drop_column('otp_verifications', 'is_used')

    # 4. Add modern columns if missing
    if 'phone' not in existing_cols:
        op.add_column('otp_verifications', sa.Column('phone', sa.String(30), nullable=False))
    if 'salt' not in existing_cols:
        op.add_column('otp_verifications', sa.Column('salt', sa.String(64), nullable=False))
    if 'purpose' not in existing_cols:
        op.add_column(
            'otp_verifications',
            sa.Column('purpose', sa.String(50), nullable=False, server_default='RESIDENT_REGISTRATION')
        )
    if 'max_attempts' not in existing_cols:
        op.add_column(
            'otp_verifications',
            sa.Column('max_attempts', sa.Integer(), nullable=False, server_default='3')
        )
    if 'is_verified' not in existing_cols:
        op.add_column(
            'otp_verifications',
            sa.Column('is_verified', sa.Boolean(), nullable=False, server_default=sa.text('false'))
        )

    # 5. Create modern indexes if missing
    if 'ix_otp_verifications_phone' not in existing_indexes:
        op.create_index('ix_otp_verifications_phone', 'otp_verifications', ['phone'])
    if 'ix_otp_verifications_purpose' not in existing_indexes:
        op.create_index('ix_otp_verifications_purpose', 'otp_verifications', ['purpose'])
    if 'ix_otp_verifications_expires_at' not in existing_indexes:
        op.create_index('ix_otp_verifications_expires_at', 'otp_verifications', ['expires_at'])
    if 'ix_otp_verifications_is_verified' not in existing_indexes:
        op.create_index('ix_otp_verifications_is_verified', 'otp_verifications', ['is_verified'])


def downgrade() -> None:
    conn = op.get_bind()
    curr_db = conn.execute(sa.text("SELECT current_database()")).scalar()

    # 1. Strict Database Safety Guard: Abort unless running against pg_management_test
    if curr_db != "pg_management_test":
        err_msg = f"ABORTING: Refusing downgrade against database '{curr_db}'. Downgrade is strictly restricted to 'pg_management_test'."
        raise RuntimeError(err_msg)

    # 2. Strict Precondition Check: Abort if rows exist to preserve verification data
    row_count = conn.execute(sa.text("SELECT count(*) FROM otp_verifications")).scalar()
    if row_count > 0:
        err_msg = f"ABORTING: Table 'otp_verifications' contains {row_count} rows. Cannot safely downgrade without discarding phone verification data."
        raise RuntimeError(err_msg)

    # 3. Only when table is empty: drop modern indexes
    op.drop_index('ix_otp_verifications_is_verified', table_name='otp_verifications')
    op.drop_index('ix_otp_verifications_expires_at', table_name='otp_verifications')
    op.drop_index('ix_otp_verifications_purpose', table_name='otp_verifications')
    op.drop_index('ix_otp_verifications_phone', table_name='otp_verifications')

    # 4. Drop modern columns
    op.drop_column('otp_verifications', 'is_verified')
    op.drop_column('otp_verifications', 'max_attempts')
    op.drop_column('otp_verifications', 'purpose')
    op.drop_column('otp_verifications', 'salt')
    op.drop_column('otp_verifications', 'phone')

    # 5. Restore original legacy columns
    op.add_column('otp_verifications', sa.Column('email', sa.String(255), nullable=False))
    op.add_column(
        'otp_verifications',
        sa.Column('is_used', sa.Boolean(), server_default=sa.text('false'), nullable=False)
    )

    # 6. Restore legacy email index
    op.create_index('ix_otp_verifications_email', 'otp_verifications', ['email'])
