"""phase2d_operations_tables

Adds the operational tables introduced for resident registration OTPs,
complaints, expenses, and staff records.

Revision ID: 7d2e4f6a8b10
Revises: 6cb475ecad6d
Create Date: 2026-10-25 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7d2e4f6a8b10'
down_revision: Union[str, Sequence[str], None] = '6cb475ecad6d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Registration / verification one-time passwords
    op.create_table(
        'otp_verifications',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column('email', sa.String(255), nullable=False),
        sa.Column('otp_hash', sa.String(255), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_used', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('attempts', sa.Integer(), server_default='0', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_otp_verifications_email', 'otp_verifications', ['email'])

    # 2. Resident complaints
    op.create_table(
        'complaints',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('resident_id', sa.Uuid(as_uuid=True), sa.ForeignKey('residents.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('room_id', sa.Uuid(as_uuid=True), sa.ForeignKey('rooms.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('issue', sa.Text(), nullable=False),
        sa.Column('priority', sa.String(20), nullable=False),
        sa.Column('status', sa.String(20), server_default='PENDING', nullable=False),
        sa.Column('assigned_to_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('resolved_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('resolution_notes', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_complaints_company_id', 'complaints', ['company_id'])
    op.create_index('ix_complaints_property_id', 'complaints', ['property_id'])
    op.create_index('ix_complaints_resident_id', 'complaints', ['resident_id'])
    op.create_index('ix_complaints_room_id', 'complaints', ['room_id'])

    # 3. Property operational expenses
    op.create_table(
        'expenses',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='RESTRICT'), nullable=True),
        sa.Column('title', sa.String(150), nullable=False),
        sa.Column('category', sa.String(100), nullable=False),
        sa.Column('amount', sa.Numeric(10, 2), nullable=False),
        sa.Column('date', sa.Date(), nullable=False),
        sa.Column('method', sa.String(50), nullable=False),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('created_by_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_expenses_company_id', 'expenses', ['company_id'])
    op.create_index('ix_expenses_property_id', 'expenses', ['property_id'])
    op.create_index('ix_expenses_created_by_id', 'expenses', ['created_by_id'])

    # 4. Staff employment records
    op.create_table(
        'staff',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='RESTRICT'), nullable=True),
        sa.Column('user_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('name', sa.String(150), nullable=False),
        sa.Column('role', sa.String(100), nullable=False),
        sa.Column('phone', sa.String(30), nullable=False),
        sa.Column('salary', sa.Numeric(10, 2), nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_staff_company_id', 'staff', ['company_id'])
    op.create_index('ix_staff_property_id', 'staff', ['property_id'])
    op.create_index('ix_staff_user_id', 'staff', ['user_id'])


def downgrade() -> None:
    op.drop_index('ix_staff_user_id', table_name='staff')
    op.drop_index('ix_staff_property_id', table_name='staff')
    op.drop_index('ix_staff_company_id', table_name='staff')
    op.drop_table('staff')

    op.drop_index('ix_expenses_created_by_id', table_name='expenses')
    op.drop_index('ix_expenses_property_id', table_name='expenses')
    op.drop_index('ix_expenses_company_id', table_name='expenses')
    op.drop_table('expenses')

    op.drop_index('ix_complaints_room_id', table_name='complaints')
    op.drop_index('ix_complaints_resident_id', table_name='complaints')
    op.drop_index('ix_complaints_property_id', table_name='complaints')
    op.drop_index('ix_complaints_company_id', table_name='complaints')
    op.drop_table('complaints')

    op.drop_index('ix_otp_verifications_email', table_name='otp_verifications')
    op.drop_table('otp_verifications')
