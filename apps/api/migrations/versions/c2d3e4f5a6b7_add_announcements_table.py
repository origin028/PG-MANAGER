"""add announcements table

Revision ID: c2d3e4f5a6b7
Revises: c1d2e3f4a5b6
Create Date: 2026-11-23 11:45:00.000000

"""
from typing import Sequence, Union
import uuid
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c2d3e4f5a6b7'
down_revision: Union[str, None] = 'c1d2e3f4a5b6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()

    if 'announcements' not in tables:
        op.create_table(
            'announcements',
            sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4),
            sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='CASCADE'), nullable=False),
            sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='CASCADE'), nullable=True),
            sa.Column('created_by_user_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False),
            sa.Column('title', sa.String(length=255), nullable=False),
            sa.Column('content', sa.Text(), nullable=False),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('true')),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        )
        op.create_index('ix_announcements_id', 'announcements', ['id'])
        op.create_index('ix_announcements_company_id', 'announcements', ['company_id'])
        op.create_index('ix_announcements_property_id', 'announcements', ['property_id'])
        op.create_index('ix_announcements_created_by_user_id', 'announcements', ['created_by_user_id'])
        op.create_index('ix_announcements_is_active', 'announcements', ['is_active'])


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()

    if 'announcements' in tables:
        op.drop_table('announcements')
