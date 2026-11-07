"""phase2c_invoices_and_payments

Revision ID: 6cb475ecad6d
Revises: 7174ab3bff4c
Create Date: 2026-10-23 21:57:28.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6cb475ecad6d'
down_revision: Union[str, Sequence[str], None] = '7174ab3bff4c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Enforce unique (id, property_id) on residents table
    # This allows composite FK fk_invoices_resident_id_property_id -> residents (id, property_id)
    op.create_unique_constraint(
        'uq_residents_id_property_id',
        'residents',
        ['id', 'property_id'],
    )

    # 2. Create invoices table
    op.create_table(
        'invoices',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('resident_id', sa.Uuid(as_uuid=True), nullable=False),
        sa.Column('invoice_number', sa.String(100), unique=True, nullable=False),
        sa.Column('billing_month', sa.String(7), nullable=False),
        sa.Column('billing_period_start', sa.Date(), nullable=False),
        sa.Column('billing_period_end', sa.Date(), nullable=False),
        sa.Column('issue_date', sa.Date(), nullable=False),
        sa.Column('due_date', sa.Date(), nullable=False),
        sa.Column('invoice_type', sa.String(50), server_default='RENT', nullable=False),
        sa.Column('rent_amount', sa.Numeric(10, 2), server_default='0.00', nullable=False),
        sa.Column('additional_charges', sa.Numeric(10, 2), server_default='0.00', nullable=False),
        sa.Column('discount_amount', sa.Numeric(10, 2), server_default='0.00', nullable=False),
        sa.Column('total_amount', sa.Numeric(10, 2), server_default='0.00', nullable=False),
        sa.Column('paid_amount', sa.Numeric(10, 2), server_default='0.00', nullable=False),
        sa.Column('balance_amount', sa.Numeric(10, 2), server_default='0.00', nullable=False),
        sa.Column('status', sa.String(50), server_default='ISSUED', nullable=False),
        sa.Column('notes', sa.String(255), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ['resident_id', 'property_id'],
            ['residents.id', 'residents.property_id'],
            name='fk_invoices_resident_id_property_id',
            ondelete='RESTRICT',
        ),
        sa.UniqueConstraint('resident_id', 'billing_month', 'invoice_type', name='uq_resident_billing_month_type'),
        sa.UniqueConstraint('id', 'property_id', name='uq_invoices_id_property_id'),
    )

    # 3. Create indexes on invoices
    op.create_index('ix_invoices_company_id', 'invoices', ['company_id'])
    op.create_index('ix_invoices_property_id', 'invoices', ['property_id'])
    op.create_index('ix_invoices_resident_id', 'invoices', ['resident_id'])
    op.create_index('ix_invoices_invoice_number', 'invoices', ['invoice_number'])
    op.create_index('ix_invoices_billing_month', 'invoices', ['billing_month'])
    op.create_index('ix_invoices_status', 'invoices', ['status'])
    op.create_index('ix_invoices_due_date', 'invoices', ['due_date'])
    op.create_index('ix_invoices_property_status', 'invoices', ['property_id', 'status'])

    # 4. Create payments table
    op.create_table(
        'payments',
        sa.Column('id', sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column('company_id', sa.Uuid(as_uuid=True), sa.ForeignKey('companies.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('property_id', sa.Uuid(as_uuid=True), sa.ForeignKey('properties.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('invoice_id', sa.Uuid(as_uuid=True), nullable=False),
        sa.Column('resident_id', sa.Uuid(as_uuid=True), nullable=False),
        sa.Column('payment_number', sa.String(100), unique=True, nullable=False),
        sa.Column('amount', sa.Numeric(10, 2), nullable=False),
        sa.Column('payment_method', sa.String(50), nullable=False),
        sa.Column('transaction_reference', sa.String(150), nullable=True),
        sa.Column('status', sa.String(50), server_default='COMPLETED', nullable=False),
        sa.Column('recorded_by_user_id', sa.Uuid(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('payment_date', sa.Date(), nullable=False),
        sa.Column('paid_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('notes', sa.String(255), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(
            ['invoice_id', 'property_id'],
            ['invoices.id', 'invoices.property_id'],
            name='fk_payments_invoice_id_property_id',
            ondelete='RESTRICT',
        ),
        sa.ForeignKeyConstraint(
            ['resident_id', 'property_id'],
            ['residents.id', 'residents.property_id'],
            name='fk_payments_resident_id_property_id',
            ondelete='RESTRICT',
        ),
    )

    # 5. Create indexes on payments
    op.create_index('ix_payments_company_id', 'payments', ['company_id'])
    op.create_index('ix_payments_property_id', 'payments', ['property_id'])
    op.create_index('ix_payments_invoice_id', 'payments', ['invoice_id'])
    op.create_index('ix_payments_resident_id', 'payments', ['resident_id'])
    op.create_index('ix_payments_payment_number', 'payments', ['payment_number'])
    op.create_index('ix_payments_status', 'payments', ['status'])
    op.create_index('ix_payments_payment_date', 'payments', ['payment_date'])
    op.create_index('ix_payments_property_status', 'payments', ['property_id', 'status'])

    # Partial unique index enforcing unique transaction_reference when provided
    op.create_index(
        'uq_payment_transaction_ref',
        'payments',
        ['transaction_reference'],
        unique=True,
        postgresql_where=sa.text("transaction_reference IS NOT NULL AND transaction_reference != ''"),
    )


def downgrade() -> None:
    op.drop_index('uq_payment_transaction_ref', table_name='payments')
    op.drop_index('ix_payments_property_status', table_name='payments')
    op.drop_index('ix_payments_payment_date', table_name='payments')
    op.drop_index('ix_payments_status', table_name='payments')
    op.drop_index('ix_payments_payment_number', table_name='payments')
    op.drop_index('ix_payments_resident_id', table_name='payments')
    op.drop_index('ix_payments_invoice_id', table_name='payments')
    op.drop_index('ix_payments_property_id', table_name='payments')
    op.drop_index('ix_payments_company_id', table_name='payments')
    op.drop_table('payments')

    op.drop_index('ix_invoices_property_status', table_name='invoices')
    op.drop_index('ix_invoices_due_date', table_name='invoices')
    op.drop_index('ix_invoices_status', table_name='invoices')
    op.drop_index('ix_invoices_billing_month', table_name='invoices')
    op.drop_index('ix_invoices_invoice_number', table_name='invoices')
    op.drop_index('ix_invoices_resident_id', table_name='invoices')
    op.drop_index('ix_invoices_property_id', table_name='invoices')
    op.drop_index('ix_invoices_company_id', table_name='invoices')
    op.drop_table('invoices')

    op.drop_constraint('uq_residents_id_property_id', 'residents', type_='unique')
