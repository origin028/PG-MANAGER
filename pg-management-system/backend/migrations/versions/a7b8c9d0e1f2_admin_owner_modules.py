"""add admin owner modules and leads table

Revision ID: a7b8c9d0e1f2
Revises: f6a7b8c9d0e1
Create Date: 2026-11-02 17:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a7b8c9d0e1f2'
down_revision: Union[str, None] = 'f6a7b8c9d0e1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    existing_tables = inspector.get_table_names()

    # 1. Create leads table if not exists
    if 'leads' not in existing_tables:
        op.create_table(
            'leads',
            sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
            sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='CASCADE'), nullable=False),
            sa.Column('name', sa.String(150), nullable=False),
            sa.Column('phone', sa.String(30), nullable=False),
            sa.Column('email', sa.String(255), nullable=True),
            sa.Column('status', sa.String(50), nullable=False, server_default='NEW'),
            sa.Column('source', sa.String(100), nullable=True),
            sa.Column('requirement', sa.Text(), nullable=True),
            sa.Column('visit_date', sa.DateTime(timezone=True), nullable=True),
            sa.Column('follow_up_date', sa.DateTime(timezone=True), nullable=True),
            sa.Column('notes', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.create_index('ix_leads_property_id', 'leads', ['property_id'])
        op.create_index('ix_leads_phone', 'leads', ['phone'])
        op.create_index('ix_leads_status', 'leads', ['status'])

    # 2. Update otp_verifications table for email-based 2FA Super Key
    if 'otp_verifications' in existing_tables:
        otp_cols = [c['name'] for c in inspector.get_columns('otp_verifications')]
        if 'email' not in otp_cols:
            op.add_column('otp_verifications', sa.Column('email', sa.String(255), nullable=True))
            op.create_index('ix_otp_verifications_email', 'otp_verifications', ['email'])
            op.alter_column('otp_verifications', 'phone', existing_type=sa.String(30), nullable=True)

    # 3. Update staff table for email and joining_date
    if 'staff' in existing_tables:
        staff_cols = [c['name'] for c in inspector.get_columns('staff')]
        if 'email' not in staff_cols:
            op.add_column('staff', sa.Column('email', sa.String(255), nullable=True))
        if 'joining_date' not in staff_cols:
            op.add_column('staff', sa.Column('joining_date', sa.Date(), nullable=True))

    # 4. Update properties table for description
    if 'properties' in existing_tables:
        prop_cols = [c['name'] for c in inspector.get_columns('properties')]
        if 'description' not in prop_cols:
            op.add_column('properties', sa.Column('description', sa.Text(), nullable=True))

    # 5. Update companies table for subscription plan and status
    if 'companies' in existing_tables:
        comp_cols = [c['name'] for c in inspector.get_columns('companies')]
        if 'subscription_plan' not in comp_cols:
            op.add_column('companies', sa.Column('subscription_plan', sa.String(50), nullable=False, server_default='STANDARD'))
        if 'subscription_status' not in comp_cols:
            op.add_column('companies', sa.Column('subscription_status', sa.String(50), nullable=False, server_default='ACTIVE'))


def downgrade() -> None:
    # 5. Companies
    op.drop_column('companies', 'subscription_status')
    op.drop_column('companies', 'subscription_plan')

    # 4. Properties
    op.drop_column('properties', 'description')

    # 3. Staff
    op.drop_column('staff', 'joining_date')
    op.drop_column('staff', 'email')

    # 2. OTP Verifications
    op.alter_column('otp_verifications', 'phone', existing_type=sa.String(30), nullable=False)
    op.drop_index('ix_otp_verifications_email', 'otp_verifications')
    op.drop_column('otp_verifications', 'email')

    # 1. Leads
    op.drop_index('ix_leads_status', 'leads')
    op.drop_index('ix_leads_phone', 'leads')
    op.drop_index('ix_leads_property_id', 'leads')
    op.drop_table('leads')
