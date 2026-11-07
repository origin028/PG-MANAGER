import uuid
from datetime import datetime
from typing import Dict, Optional
from decimal import Decimal
from pydantic import BaseModel, ConfigDict, Field, field_validator


class PaymentRequestCreate(BaseModel):
    invoice_id: uuid.UUID
    amount: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    idempotency_key: str = Field(min_length=8, max_length=128)


class PaymentRequestRead(BaseModel):
    payment_id: uuid.UUID
    payment_number: str
    gateway_order_id: str
    amount: Decimal
    amount_paise: int
    currency: str = "INR"
    key_id: str = ""
    property_name: Optional[str] = None
    description: Optional[str] = None
    resident_name: Optional[str] = None
    resident_phone: Optional[str] = None
    resident_email: Optional[str] = None


class PaymentStatusRead(BaseModel):
    payment_id: uuid.UUID
    payment_number: str
    invoice_id: uuid.UUID
    amount: float
    status: str
    payment_mode: str
    gateway_order_id: Optional[str] = None
    gateway_payment_id: Optional[str] = None
    paid_at: Optional[datetime] = None
    is_settled: bool
    receipt_id: Optional[uuid.UUID] = None
    receipt_number: Optional[str] = None


class PaymentVerifyRequest(BaseModel):
    payment_id: uuid.UUID
    razorpay_order_id: str = Field(min_length=1, max_length=150)
    razorpay_payment_id: str = Field(min_length=1, max_length=150)
    razorpay_signature: str = Field(min_length=1, max_length=255)



class PaymentBase(BaseModel):
    amount: float
    payment_mode: str = "UPI"


class PaymentCreate(PaymentBase):
    invoice_id: uuid.UUID
    property_id: uuid.UUID
    resident_id: uuid.UUID
    gateway_order_id: Optional[str] = None
    gateway_payment_id: Optional[str] = None


class PaymentRead(PaymentBase):
    id: uuid.UUID
    property_id: uuid.UUID
    invoice_id: uuid.UUID
    resident_id: uuid.UUID
    payment_number: str
    gateway_order_id: Optional[str] = None
    gateway_payment_id: Optional[str] = None
    status: str
    receipt_url: Optional[str] = None
    paid_at: Optional[datetime] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PaymentSummary(BaseModel):
    id: uuid.UUID
    payment_number: str
    amount: float
    payment_mode: str
    status: str
    invoice_id: Optional[uuid.UUID] = None
    created_at: Optional[datetime] = None
    paid_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class PaymentLinkCreate(BaseModel):
    invoice_id: uuid.UUID
    amount: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    idempotency_key: str = Field(min_length=8, max_length=128)
    send_whatsapp: bool = False


class PaymentLinkRead(BaseModel):
    link_id: uuid.UUID
    payment_id: uuid.UUID
    payment_number: str
    payment_url: str
    expires_at: datetime
    whatsapp_sent: bool
    whatsapp_message_id: Optional[str] = None


class PublicPaymentCheckoutDetails(BaseModel):
    property_name: str
    room_number: str
    invoice_number: str
    billing_month: str
    amount: Decimal
    amount_paise: int
    currency: str = "INR"
    gateway_order_id: str
    key_id: str
    expires_at: datetime


class UpiPaymentInitiateRequest(BaseModel):
    invoice_id: uuid.UUID
    idempotency_key: Optional[str] = Field(None, max_length=128)


class UpiAppOption(BaseModel):
    name: str
    package_name: str
    intent_uri: str


class UpiPaymentInitiateRead(BaseModel):
    payment_id: uuid.UUID
    payment_number: str
    transaction_ref: str
    invoice_id: uuid.UUID
    amount: float
    currency: str = "INR"
    payee_vpa: str
    payee_name: str
    description: str
    upi_uri: str
    google_pay_uri: str
    phonepe_uri: str
    apps: Dict[str, UpiAppOption]
    status: str
    created_at: datetime
    is_merchant_configured: bool = False
    merchant_code: Optional[str] = None
    bank_name: Optional[str] = None


class UpiPaymentStatusRead(BaseModel):
    payment_id: uuid.UUID
    payment_number: str
    invoice_id: uuid.UUID
    amount: float
    status: str
    payment_mode: str
    transaction_ref: Optional[str] = None
    bank_reference: Optional[str] = None
    is_settled: bool
    paid_at: Optional[datetime] = None
    receipt_id: Optional[uuid.UUID] = None
    receipt_number: Optional[str] = None


class UpiClientVerifyRequest(BaseModel):
    client_txn_id: Optional[str] = Field(None, max_length=100)
    notes: Optional[str] = Field(None, max_length=255)


class UpiClientVerifyResponse(BaseModel):
    payment_id: uuid.UUID
    status: str
    is_verified: bool
    message: str
    required_integration: Optional[str] = None


class UpiAdminSettleRequest(BaseModel):
    bank_reference: str = Field(min_length=1, max_length=100, description="Bank UTR or transaction reference number")
    notes: Optional[str] = Field(None, max_length=255)

    @field_validator("bank_reference")
    @classmethod
    def validate_bank_reference(cls, v: str) -> str:
        s = v.strip()
        if not s:
            raise ValueError("Bank reference / UTR cannot be empty or whitespace.")
        return s




class ManualPaymentCreate(BaseModel):
    invoice_id: uuid.UUID
    amount: Decimal = Field(gt=0, max_digits=10, decimal_places=2, description="Amount to be paid")
    payment_mode: str = Field(default="CASH", description="Payment mode: CASH, BANK_TRANSFER, UPI, or CARD")
    reference_number: Optional[str] = Field(None, max_length=150, description="Cheque/UTR/POS/Receipt reference")
    notes: Optional[str] = Field(None, max_length=500, description="Administrative payment notes")


class ManualPaymentRead(BaseModel):
    payment_id: uuid.UUID
    payment_number: str
    invoice_id: uuid.UUID
    amount: float
    payment_mode: str
    status: str
    paid_at: datetime
    receipt_id: uuid.UUID
    receipt_number: str
    invoice_status: str
    new_paid_amount: float
    remaining_balance: float


class DemoPaymentRequest(BaseModel):
    invoice_id: uuid.UUID = Field(
        ...,
        description="UUID of the invoice to pay",
        examples=["550e8400-e29b-41d4-a716-446655440000"],
    )
    amount: Optional[Decimal] = Field(
        default=None,
        gt=0,
        max_digits=10,
        decimal_places=2,
        description="Optional custom amount; defaults to full remaining invoice balance",
        examples=[12000.00],
    )
    payment_mode: str = Field(
        default="DEMO_ONLINE",
        description="Demo payment mode (DEMO_ONLINE, DEMO_UPI, DEMO_CARD)",
        examples=["DEMO_ONLINE"],
    )
    idempotency_key: Optional[str] = Field(
        default=None,
        max_length=128,
        description="Optional idempotency key to prevent duplicate demo payments on retries",
        examples=["demo-idem-20261101-001"],
    )

    @field_validator("idempotency_key")
    @classmethod
    def clean_idempotency_key(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            s = v.strip()
            return s if s else None
        return None

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "invoice_id": "550e8400-e29b-41d4-a716-446655440000",
                "amount": 12000.00,
                "payment_mode": "DEMO_ONLINE",
                "idempotency_key": "demo-idem-20261101-001",
            }
        }
    )


class DemoPaymentResponse(BaseModel):
    payment_id: uuid.UUID
    payment_number: str
    invoice_id: uuid.UUID
    amount: float
    status: str
    paid_at: datetime
    receipt_id: Optional[uuid.UUID] = None
    receipt_number: Optional[str] = None
    invoice_status: str
    paid_amount: float
    remaining_balance: float

    model_config = ConfigDict(from_attributes=True)


class RentCollectionCreate(BaseModel):
    resident_id: uuid.UUID
    invoice_id: uuid.UUID
    property_id: uuid.UUID
    collect_amount: Decimal = Field(gt=0, max_digits=10, decimal_places=2, description="Amount collected")
    payment_mode: str = Field(default="CASH", description="Payment mode: CASH, BANK_TRANSFER, UPI, CARD, CHEQUE")
    transaction_reference: Optional[str] = Field(None, max_length=150, description="Cheque/UTR/POS/Receipt reference")
    collection_date: Optional[datetime] = Field(None, description="Date/time of offline collection")
    notes: Optional[str] = Field(None, max_length=500, description="Collection notes")


class RentCollectionRead(BaseModel):
    payment_id: uuid.UUID
    payment_number: str
    invoice_id: uuid.UUID
    resident_id: uuid.UUID
    property_id: uuid.UUID
    amount: float
    payment_mode: str
    status: str
    paid_at: datetime
    receipt_id: uuid.UUID
    receipt_number: str
    invoice_status: str
    invoice_paid_amount: float
    remaining_balance: float

    model_config = ConfigDict(from_attributes=True)


class PaymentDetailRead(BaseModel):
    id: uuid.UUID
    payment_number: str
    property_id: uuid.UUID
    invoice_id: uuid.UUID
    resident_id: uuid.UUID
    amount: float
    payment_mode: str
    status: str
    gateway_order_id: Optional[str] = None
    gateway_payment_id: Optional[str] = None
    paid_at: Optional[datetime] = None
    created_at: datetime
    receipt_id: Optional[uuid.UUID] = None
    receipt_number: Optional[str] = None
    resident_name: Optional[str] = None
    resident_phone: Optional[str] = None
    invoice_number: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
