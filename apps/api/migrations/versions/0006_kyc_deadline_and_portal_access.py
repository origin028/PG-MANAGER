"""KYC deadline and resident app access switch

Revision ID: 0006
Revises: 0005
Create Date: 2026-11-24 12:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0006'
down_revision: Union[str, Sequence[str], None] = '0005'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Days a new resident gets to finish KYC before their app access turns off.
    op.add_column('companies', sa.Column('kyc_deadline_days', sa.Integer(), server_default='7', nullable=False))
    # NULL kyc_due_at = no deadline (existing residents are never switched off by this change).
    op.add_column('residents', sa.Column('kyc_due_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('residents', sa.Column('portal_enabled', sa.Boolean(), server_default=sa.text('true'), nullable=False))
    op.add_column('residents', sa.Column('portal_reason', sa.String(length=40), nullable=True))
    op.add_column('residents', sa.Column('portal_changed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('residents', sa.Column('kyc_reminder_sent_at', sa.DateTime(timezone=True), nullable=True))
    op.create_index('ix_residents_kyc_due_open', 'residents', ['kyc_due_at'], postgresql_where=sa.text('portal_enabled'))


def downgrade() -> None:
    op.drop_index('ix_residents_kyc_due_open', table_name='residents')
    op.drop_column('residents', 'kyc_reminder_sent_at')
    op.drop_column('residents', 'portal_changed_at')
    op.drop_column('residents', 'portal_reason')
    op.drop_column('residents', 'portal_enabled')
    op.drop_column('residents', 'kyc_due_at')
    op.drop_column('companies', 'kyc_deadline_days')
