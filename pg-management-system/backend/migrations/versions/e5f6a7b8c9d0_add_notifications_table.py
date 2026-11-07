"""add notifications table

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-11-01 20:30:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e5f6a7b8c9d0'
down_revision: Union[str, None] = 'd4e5f6a7b8c9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Strict safety check: Abort immediately unless connected to pg_management_test or test runner DB
    conn = op.get_bind()
    current_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if current_db != "pg_management_test" and not current_db.startswith("test_"):
        err_msg = f"Safety check aborted: Migration can only execute on 'pg_management_test', not '{current_db}'."
        raise RuntimeError(err_msg)

    # 2. Check if table already exists (idempotency check)
    inspector = sa.inspect(conn)
    if "notifications" not in inspector.get_table_names():
        op.create_table(
            'notifications',
            sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
            sa.Column('user_id', sa.Uuid(as_uuid=True), nullable=False),
            sa.Column('title', sa.String(length=200), nullable=False),
            sa.Column('body', sa.Text(), nullable=False),
            sa.Column('channel', sa.String(length=50), server_default='PUSH', nullable=False),
            sa.Column('status', sa.String(length=50), server_default='PENDING', nullable=False),
            sa.Column('scheduled_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('sent_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        )
        op.create_index('ix_notifications_id', 'notifications', ['id'], unique=False)
        op.create_index('ix_notifications_user_id', 'notifications', ['user_id'], unique=False)
        op.create_index('ix_notifications_status', 'notifications', ['status'], unique=False)


def downgrade() -> None:
    conn = op.get_bind()
    current_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if current_db != "pg_management_test":
        err_msg = f"Safety check aborted: Migration can only execute on 'pg_management_test', not '{current_db}'."
        raise RuntimeError(err_msg)

    inspector = sa.inspect(conn)
    if "notifications" in inspector.get_table_names():
        op.drop_index('ix_notifications_status', table_name='notifications')
        op.drop_index('ix_notifications_user_id', table_name='notifications')
        op.drop_index('ix_notifications_id', table_name='notifications')
        op.drop_table('notifications')
