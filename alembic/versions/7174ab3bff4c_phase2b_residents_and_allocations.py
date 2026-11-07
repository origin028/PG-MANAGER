"""phase2b_residents_and_allocations

Revision ID: 7174ab3bff4c
Revises: b518259e353b
Create Date: 2026-10-23 21:26:38.889382

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7174ab3bff4c'
down_revision: Union[str, Sequence[str], None] = 'b518259e353b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Enforce unique (id, property_id) pair on beds table
    # This allows composite FK from residents (bed_id, property_id) -> beds (id, property_id)
    op.create_unique_constraint(
        'uq_beds_id_property_id',
        'beds',
        ['id', 'property_id'],
    )

    # 2. Create residents table
    op.create_table(
        'residents',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('room_id', sa.Uuid(as_uuid=True), nullable=True),
        sa.Column('bed_id', sa.Uuid(as_uuid=True), nullable=True),
        sa.Column('user_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('full_name', sa.String(150), nullable=False),
        sa.Column('email', sa.String(255), nullable=True),
        sa.Column('phone', sa.String(30), nullable=False),
        sa.Column('emergency_contact_name', sa.String(150), nullable=True),
        sa.Column('emergency_contact_phone', sa.String(30), nullable=True),
        sa.Column('check_in_date', sa.Date(), nullable=True),
        sa.Column('expected_check_out_date', sa.Date(), nullable=True),
        sa.Column('actual_check_out_date', sa.Date(), nullable=True),
        sa.Column('monthly_rent', sa.Numeric(10, 2), server_default='0.00', nullable=False),
        sa.Column('security_deposit', sa.Numeric(10, 2), server_default='0.00', nullable=False),
        sa.Column('status', sa.String(50), server_default='PENDING', nullable=False),
        sa.Column('kyc_status', sa.String(50), server_default='PENDING', nullable=False),
        sa.Column('id_proof_type', sa.String(50), nullable=True),
        sa.Column('id_proof_number_masked', sa.String(50), nullable=True),
        sa.Column('kyc_notes', sa.String(255), nullable=True),
        sa.Column('verified_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('verified_by_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ['room_id', 'property_id'],
            ['rooms.id', 'rooms.property_id'],
            name='fk_residents_room_id_property_id',
            ondelete='RESTRICT',
        ),
        sa.ForeignKeyConstraint(
            ['bed_id', 'property_id'],
            ['beds.id', 'beds.property_id'],
            name='fk_residents_bed_id_property_id',
            ondelete='RESTRICT',
        ),
    )

    # 3. Create indexes
    op.create_index('ix_residents_company_id', 'residents', ['company_id'])
    op.create_index('ix_residents_property_id', 'residents', ['property_id'])
    op.create_index('ix_residents_room_id', 'residents', ['room_id'])
    op.create_index('ix_residents_bed_id', 'residents', ['bed_id'])
    op.create_index('ix_residents_user_id', 'residents', ['user_id'])
    op.create_index('ix_residents_phone', 'residents', ['phone'])
    op.create_index('ix_residents_email', 'residents', ['email'])
    op.create_index('ix_residents_status', 'residents', ['status'])
    op.create_index('ix_residents_kyc_status', 'residents', ['kyc_status'])
    op.create_index('ix_residents_property_status', 'residents', ['property_id', 'status'])

    # Partial unique index enforcing only ONE active resident per bed at the DB storage level
    op.create_index(
        'uq_active_resident_bed',
        'residents',
        ['bed_id'],
        unique=True,
        postgresql_where=sa.text("status = 'ACTIVE' AND bed_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index('uq_active_resident_bed', table_name='residents')
    op.drop_index('ix_residents_property_status', table_name='residents')
    op.drop_index('ix_residents_kyc_status', table_name='residents')
    op.drop_index('ix_residents_status', table_name='residents')
    op.drop_index('ix_residents_email', table_name='residents')
    op.drop_index('ix_residents_phone', table_name='residents')
    op.drop_index('ix_residents_user_id', table_name='residents')
    op.drop_index('ix_residents_bed_id', table_name='residents')
    op.drop_index('ix_residents_room_id', table_name='residents')
    op.drop_index('ix_residents_property_id', table_name='residents')
    op.drop_index('ix_residents_company_id', table_name='residents')
    op.drop_table('residents')
    op.drop_constraint('uq_beds_id_property_id', 'beds', type_='unique')
