"""add resident registration fields and pending registrations table

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-10-30 22:15:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd4e5f6a7b8c9'
down_revision: Union[str, None] = 'c3d4e5f6a7b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Strict safety check: Abort immediately unless connected to pg_management_test or test runner DB
    conn = op.get_bind()
    current_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if current_db != "pg_management_test" and not current_db.startswith("test_"):
        err_msg = f"Safety check aborted: Migration can only execute on 'pg_management_test', not '{current_db}'."
        raise RuntimeError(err_msg)

    # 2. Add resident onboarding and KYC columns to 'residents' table
    op.add_column('residents', sa.Column('date_of_birth', sa.Date(), nullable=True))
    op.add_column('residents', sa.Column('gender', sa.String(length=20), nullable=True))
    op.add_column('residents', sa.Column('occupation', sa.String(length=100), nullable=True))
    op.add_column('residents', sa.Column('emergency_contact', sa.String(length=150), nullable=True))
    op.add_column('residents', sa.Column('house_flat_no', sa.String(length=100), nullable=True))
    op.add_column('residents', sa.Column('street', sa.String(length=150), nullable=True))
    op.add_column('residents', sa.Column('landmark', sa.String(length=150), nullable=True))
    op.add_column('residents', sa.Column('city', sa.String(length=100), nullable=True))
    op.add_column('residents', sa.Column('state', sa.String(length=100), nullable=True))
    op.add_column('residents', sa.Column('pincode', sa.String(length=20), nullable=True))
    op.add_column('residents', sa.Column('verification_method', sa.String(length=50), nullable=True))
    op.add_column('residents', sa.Column('aadhaar_front_path', sa.String(length=512), nullable=True))
    op.add_column('residents', sa.Column('aadhaar_back_path', sa.String(length=512), nullable=True))
    op.add_column('residents', sa.Column('pan_card_path', sa.String(length=512), nullable=True))
    op.add_column('residents', sa.Column('passport_path', sa.String(length=512), nullable=True))
    op.add_column('residents', sa.Column('resident_selfie_path', sa.String(length=512), nullable=True))
    op.add_column('residents', sa.Column('kyc_documents', sa.JSON(), nullable=True))

    # 3. Create 'pending_resident_registrations' staging table
    op.create_table(
        'pending_resident_registrations',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column('phone', sa.String(length=30), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('registration_data', sa.JSON(), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index(
        'ix_pending_resident_registrations_phone',
        'pending_resident_registrations',
        ['phone'],
        unique=True,
    )
    op.create_index(
        'ix_pending_resident_registrations_email',
        'pending_resident_registrations',
        ['email'],
        unique=False,
    )


def downgrade() -> None:
    # 1. Strict safety check
    conn = op.get_bind()
    current_db = conn.execute(sa.text("SELECT current_database()")).scalar()
    if current_db != "pg_management_test":
        err_msg = f"Safety check aborted: Migration can only execute on 'pg_management_test', not '{current_db}'."
        raise RuntimeError(err_msg)

    # 2. Drop staging table
    op.drop_index('ix_pending_resident_registrations_email', table_name='pending_resident_registrations')
    op.drop_index('ix_pending_resident_registrations_phone', table_name='pending_resident_registrations')
    op.drop_table('pending_resident_registrations')

    # 3. Drop added columns from 'residents'
    op.drop_column('residents', 'kyc_documents')
    op.drop_column('residents', 'resident_selfie_path')
    op.drop_column('residents', 'passport_path')
    op.drop_column('residents', 'pan_card_path')
    op.drop_column('residents', 'aadhaar_back_path')
    op.drop_column('residents', 'aadhaar_front_path')
    op.drop_column('residents', 'verification_method')
    op.drop_column('residents', 'pincode')
    op.drop_column('residents', 'state')
    op.drop_column('residents', 'city')
    op.drop_column('residents', 'landmark')
    op.drop_column('residents', 'street')
    op.drop_column('residents', 'house_flat_no')
    op.drop_column('residents', 'emergency_contact')
    op.drop_column('residents', 'occupation')
    op.drop_column('residents', 'gender')
    op.drop_column('residents', 'date_of_birth')
