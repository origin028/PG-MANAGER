import uuid
from datetime import date, datetime
from typing import Dict, List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.models.bed import Bed
from app.models.complaint import Complaint
from app.models.food_menu import FoodMenu
from app.models.invoice import Invoice
from app.models.notice import Notice
from app.models.payment import Payment
from app.models.property import Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.resident_preference import ResidentPreference
from app.models.room import Room
from app.models.staff import Staff
from app.models.user import User
from app.schemas.resident_mobile import (
    AssignedBedDetail,
    AssignedRoomDetail,
    FoodMenuItem,
    FoodMenuWeeklyResponse,
    PayNowSummary,
    PropertyContactsResponse,
    ResidentAddressInfo,
    ResidentBasicInfo,
    ResidentComplaintCreate,
    ResidentComplaintRead,
    ResidentDashboardResponse,
    ResidentInvoiceDetailResponse,
    ResidentInvoiceListItem,
    ResidentKYCStatusInfo,
    ResidentNoticeSummary,
    ResidentPaymentHistoryItem,
    ResidentPaymentSummary,
    ResidentProfileFullRead,
    ResidentPropertyDetailsResponse,
    ResidentRentSummary,
    ResidentSettingsRead,
    ResidentSettingsUpdate,
    ResidentStaySummary,
    StaffContactItem,
)


class ResidentMobileService:
    def __init__(self, db: Session):
        self.db = db

    def get_dashboard(self, active_resident: Resident, user: User) -> ResidentDashboardResponse:
        """Aggregates all key dashboard widgets for the authenticated resident."""
        # 1. Stay & Property info
        property_record = self.db.get(Property, active_resident.property_id) if active_resident.property_id else None
        room_record = self.db.get(Room, active_resident.room_id) if active_resident.room_id else None
        bed_record = self.db.get(Bed, active_resident.bed_id) if active_resident.bed_id else None

        stay_details = ResidentStaySummary(
            property_id=active_resident.property_id,
            property_name=property_record.name if property_record else "Unknown PG",
            property_address=property_record.address_line1 if property_record else None,
            room_number=room_record.room_number if room_record else None,
            floor_number=room_record.floor_number if room_record else None,
            bed_number=bed_record.bed_number if bed_record else None,
            check_in_date=active_resident.check_in_date,
            living_since=active_resident.check_in_date,
            monthly_rent=float(active_resident.monthly_rent or 0.0),
            security_deposit=float(active_resident.security_deposit or 0.0),
        )

        resident_info = ResidentBasicInfo(
            resident_id=active_resident.id,
            user_id=user.id,
            full_name=user.full_name,
            phone=user.phone,
            email=user.email,
            avatar_url=user.avatar_url,
            approval_status=getattr(user, "approval_status", "APPROVED"),
            status=active_resident.status,
        )

        # 2. Rent Summary
        invoices = self.db.scalars(
            sa.select(Invoice)
            .where(Invoice.resident_id == active_resident.id)
            .order_by(Invoice.due_date.asc())
        ).all()

        total_due = 0.0
        total_paid = 0.0
        next_due_date = None
        has_pending = False
        earliest_unpaid_inv = None

        for inv in invoices:
            total_paid += float(inv.paid_amount or 0.0)
            bal = float(inv.balance_amount)
            if inv.status in ["PENDING", "PARTIALLY_PAID", "OVERDUE"] and bal > 0:
                total_due += bal
                has_pending = True
                if not next_due_date or inv.due_date < next_due_date:
                    next_due_date = inv.due_date
                    earliest_unpaid_inv = inv

        # Check if past due
        today = date.today()
        rent_status = "PAID"
        if has_pending:
            if next_due_date and next_due_date < today:
                rent_status = "OVERDUE"
            else:
                rent_status = "DUE"
        elif not invoices:
            rent_status = "NO_INVOICE"

        # Pay now info
        pay_now = None
        if has_pending and earliest_unpaid_inv:
            pay_now = PayNowSummary(
                can_pay=True,
                invoice_id=earliest_unpaid_inv.id,
                invoice_number=earliest_unpaid_inv.invoice_number,
                amount_due=round(float(earliest_unpaid_inv.balance_amount), 2),
                billing_month=earliest_unpaid_inv.billing_month,
                payment_methods=["UPI", "DEMO_ONLINE"],
            )
        else:
            pay_now = PayNowSummary(can_pay=False, amount_due=0.0)

        # Rent Reminders
        pref = self.db.scalar(
            sa.select(ResidentPreference).where(ResidentPreference.user_id == user.id)
        )
        reminders = []
        reminders_enabled = pref.rent_reminders_enabled if pref else True
        if reminders_enabled and has_pending and earliest_unpaid_inv:
            days_left = (earliest_unpaid_inv.due_date - today).days
            if days_left < 0:
                reminders.append(f"Rent invoice {earliest_unpaid_inv.invoice_number} is overdue by {abs(days_left)} days.")
            elif days_left == 0:
                reminders.append(f"Rent invoice {earliest_unpaid_inv.invoice_number} is due today.")
            elif days_left <= 7:
                reminders.append(f"Rent invoice of ₹{float(earliest_unpaid_inv.balance_amount):,.2f} for {earliest_unpaid_inv.billing_month} is due in {days_left} days.")

        # Last payment
        last_payment = self.db.scalars(
            sa.select(Payment)
            .where(Payment.resident_id == active_resident.id, Payment.status == "SUCCESS")
            .order_by(Payment.created_at.desc())
        ).first()

        rent_summary = ResidentRentSummary(
            current_rent_amount=float(active_resident.monthly_rent or 0.0),
            total_paid=round(total_paid, 2),
            outstanding_dues=round(total_due, 2),
            total_due=round(total_due, 2),
            rent_due_date=next_due_date,
            next_due_date=next_due_date,
            last_payment_amount=float(last_payment.amount) if last_payment else None,
            last_payment_date=last_payment.paid_at if (last_payment and last_payment.paid_at) else (last_payment.created_at if last_payment else None),
            rent_payment_status=rent_status,
            status=rent_status,
            pay_now=pay_now,
            rent_reminders=reminders,
        )

        # 3. Recent Notices (Scoped to resident's property)
        notices = self.db.scalars(
            sa.select(Notice)
            .where(Notice.property_id == active_resident.property_id)
            .order_by(Notice.is_pinned.desc(), Notice.created_at.desc())
            .limit(5)
        ).all()

        recent_notices = [
            ResidentNoticeSummary(
                id=n.id,
                title=n.title,
                content=n.content,
                is_pinned=n.is_pinned,
                created_at=n.created_at,
            )
            for n in notices
        ]

        # 4. Last three payments (explicitly 3 as required)
        recent_payments_records = self.db.scalars(
            sa.select(Payment)
            .where(Payment.resident_id == active_resident.id)
            .order_by(Payment.created_at.desc())
            .limit(3)
        ).all()

        recent_payments = []
        for p in recent_payments_records:
            rcpt = self.db.scalar(sa.select(Receipt).where(Receipt.payment_id == p.id))
            receipt_available = bool(p.receipt_url or rcpt)
            recent_payments.append(
                ResidentPaymentSummary(
                    payment_id=p.id,
                    amount=float(p.amount),
                    payment_mode=getattr(p, "payment_mode", "UPI"),
                    payment_method=getattr(p, "payment_mode", "UPI"),
                    transaction_reference=p.transaction_reference,
                    payment_date=p.paid_at or p.created_at,
                    status=p.status,
                    paid_at=p.paid_at or p.created_at,
                    receipt_available=receipt_available,
                    receipt_url=getattr(p, "receipt_url", None),
                    receipt_number=rcpt.receipt_number if rcpt else None,
                )
            )

        return ResidentDashboardResponse(
            resident_info=resident_info,
            stay_details=stay_details,
            rent_summary=rent_summary,
            recent_notices=recent_notices,
            recent_payments=recent_payments,
        )

    def get_food_menu(self, active_resident: Resident) -> FoodMenuWeeklyResponse:
        """Retrieves active weekly food menu for resident's assigned PG."""
        property_record = self.db.get(Property, active_resident.property_id)
        prop_name = property_record.name if property_record else "Unknown PG"

        menu_records = self.db.scalars(
            sa.select(FoodMenu)
            .where(FoodMenu.property_id == active_resident.property_id, FoodMenu.is_active == True)
        ).all()

        meal_order = {"BREAKFAST": 1, "LUNCH": 2, "SNACKS": 3, "DINNER": 4}
        days_order = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]
        menu_by_day: Dict[str, List[FoodMenuItem]] = {day: [] for day in days_order}

        for item in menu_records:
            day_key = item.day_of_week.upper()
            if day_key not in menu_by_day:
                menu_by_day[day_key] = []
            menu_by_day[day_key].append(
                FoodMenuItem(
                    id=item.id,
                    property_id=item.property_id,
                    day_of_week=item.day_of_week,
                    meal_type=item.meal_type,
                    start_time=item.start_time,
                    end_time=item.end_time,
                    dishes=item.dishes if isinstance(item.dishes, list) else [],
                    is_active=item.is_active,
                )
            )

        # Sort each day's meals: Breakfast -> Lunch -> Dinner
        for day in menu_by_day:
            menu_by_day[day].sort(key=lambda m: meal_order.get(m.meal_type.upper(), 99))

        return FoodMenuWeeklyResponse(
            property_id=active_resident.property_id,
            property_name=prop_name,
            menu_by_day=menu_by_day,
        )

    def get_invoices(
        self, active_resident: Resident, status_filter: Optional[str] = None
    ) -> List[ResidentInvoiceListItem]:
        """Lists all invoices issued to the authenticated resident."""
        query = sa.select(Invoice).where(Invoice.resident_id == active_resident.id)
        if status_filter:
            query = query.where(Invoice.status == status_filter.upper())
        query = query.order_by(Invoice.due_date.desc())

        invoices = self.db.scalars(query).all()
        return [
            ResidentInvoiceListItem(
                id=inv.id,
                invoice_number=inv.invoice_number,
                billing_month=inv.billing_month,
                invoice_type=inv.invoice_type,
                amount=float(inv.amount),
                paid_amount=float(inv.paid_amount),
                balance_amount=float(inv.balance_amount),
                outstanding_balance=float(inv.balance_amount),
                due_date=inv.due_date,
                status=inv.status,
                can_pay=(inv.status != "PAID" and inv.balance_amount > 0),
                notes=inv.notes,
                created_at=inv.created_at,
            )
            for inv in invoices
        ]

    def get_invoice_detail(
        self, active_resident: Resident, invoice_id: uuid.UUID
    ) -> ResidentInvoiceDetailResponse:
        """Retrieves single invoice detail strictly scoped to authenticated resident (Anti-IDOR)."""
        invoice = self.db.get(Invoice, invoice_id)
        if not invoice or invoice.resident_id != active_resident.id:
            raise NotFoundError("Invoice not found or does not belong to your account.")

        payments = self.db.scalars(
            sa.select(Payment).where(Payment.invoice_id == invoice.id).order_by(Payment.created_at.desc())
        ).all()

        payment_summaries = []
        for p in payments:
            rcpt = self.db.scalar(sa.select(Receipt).where(Receipt.payment_id == p.id))
            receipt_available = bool(p.receipt_url or rcpt)
            payment_summaries.append(
                ResidentPaymentSummary(
                    payment_id=p.id,
                    amount=float(p.amount),
                    payment_mode=getattr(p, "payment_mode", "UPI"),
                    payment_method=getattr(p, "payment_mode", "UPI"),
                    transaction_reference=p.transaction_reference,
                    payment_date=p.paid_at or p.created_at,
                    status=p.status,
                    paid_at=p.paid_at or p.created_at,
                    receipt_available=receipt_available,
                    receipt_url=getattr(p, "receipt_url", None),
                    receipt_number=rcpt.receipt_number if rcpt else None,
                )
            )

        can_pay = (invoice.status != "PAID" and invoice.balance_amount > 0)
        pay_now = None
        if can_pay:
            pay_now = PayNowSummary(
                can_pay=True,
                invoice_id=invoice.id,
                invoice_number=invoice.invoice_number,
                amount_due=round(float(invoice.balance_amount), 2),
                billing_month=invoice.billing_month,
                payment_methods=["UPI", "DEMO_ONLINE"],
            )

        return ResidentInvoiceDetailResponse(
            id=invoice.id,
            property_id=invoice.property_id,
            resident_id=invoice.resident_id,
            invoice_number=invoice.invoice_number,
            billing_month=invoice.billing_month,
            billing_period_start=getattr(invoice, "billing_period_start", None),
            billing_period_end=getattr(invoice, "billing_period_end", None),
            invoice_type=invoice.invoice_type,
            rent_amount=float(getattr(invoice, "rent_amount", 0.0)) if getattr(invoice, "rent_amount", None) is not None else float(invoice.amount),
            additional_charges=float(getattr(invoice, "additional_charges", 0.0)) if getattr(invoice, "additional_charges", None) is not None else None,
            discount_amount=float(getattr(invoice, "discount_amount", 0.0)) if getattr(invoice, "discount_amount", None) is not None else None,
            amount=float(invoice.amount),
            paid_amount=float(invoice.paid_amount),
            balance_amount=float(invoice.balance_amount),
            outstanding_balance=float(invoice.balance_amount),
            due_date=invoice.due_date,
            status=invoice.status,
            can_pay=can_pay,
            pay_now=pay_now,
            notes=invoice.notes,
            payments=payment_summaries,
            created_at=invoice.created_at,
        )

    def get_payments(self, active_resident: Resident) -> List[ResidentPaymentHistoryItem]:
        """Lists all payment transactions for the authenticated resident."""
        payments = self.db.scalars(
            sa.select(Payment)
            .where(Payment.resident_id == active_resident.id)
            .order_by(Payment.created_at.desc())
        ).all()

        items = []
        for p in payments:
            inv = self.db.get(Invoice, p.invoice_id) if p.invoice_id else None
            rcpt = self.db.scalar(sa.select(Receipt).where(Receipt.payment_id == p.id))
            receipt_available = bool(p.receipt_url or rcpt)
            items.append(
                ResidentPaymentHistoryItem(
                    id=p.id,
                    payment_number=getattr(p, "payment_number", None),
                    invoice_id=p.invoice_id,
                    invoice_number=inv.invoice_number if inv else None,
                    amount=float(p.amount),
                    payment_mode=getattr(p, "payment_mode", "UPI"),
                    payment_method=getattr(p, "payment_mode", "UPI"),
                    transaction_reference=p.transaction_reference,
                    status=p.status,
                    payment_date=p.paid_at or p.created_at,
                    paid_at=p.paid_at or p.created_at,
                    receipt_available=receipt_available,
                    receipt_url=getattr(p, "receipt_url", None),
                    receipt_number=rcpt.receipt_number if rcpt else None,
                    created_at=p.created_at,
                )
            )
        return items

    def get_profile(self, active_resident: Resident, user: User) -> ResidentProfileFullRead:
        """Retrieves resident's personal, stay, and safe KYC verification details."""
        property_record = self.db.get(Property, active_resident.property_id) if active_resident.property_id else None
        room_record = self.db.get(Room, active_resident.room_id) if active_resident.room_id else None
        bed_record = self.db.get(Bed, active_resident.bed_id) if active_resident.bed_id else None

        stay_summary = ResidentStaySummary(
            property_id=active_resident.property_id,
            property_name=property_record.name if property_record else "Unknown PG",
            property_address=property_record.address_line1 if property_record else None,
            room_number=room_record.room_number if room_record else None,
            floor_number=room_record.floor_number if room_record else None,
            bed_number=bed_record.bed_number if bed_record else None,
            check_in_date=active_resident.check_in_date,
            living_since=active_resident.check_in_date,
            monthly_rent=float(active_resident.monthly_rent or 0.0),
            security_deposit=float(active_resident.security_deposit or 0.0),
        )

        address_info = ResidentAddressInfo(
            house_flat_no=getattr(active_resident, "house_flat_no", None),
            street=getattr(active_resident, "street", None),
            landmark=getattr(active_resident, "landmark", None),
            city=getattr(active_resident, "city", None),
            state=getattr(active_resident, "state", None),
            pincode=getattr(active_resident, "pincode", None),
        )

        kyc_info = ResidentKYCStatusInfo(
            kyc_status=active_resident.kyc_status or "PENDING_VERIFICATION",
            verification_method=getattr(active_resident, "verification_method", None),
            id_proof_type=active_resident.id_proof_type,
            id_proof_number_masked=active_resident.id_proof_number_masked,
            has_aadhaar_front=bool(getattr(active_resident, "aadhaar_front_path", None)),
            has_aadhaar_back=bool(getattr(active_resident, "aadhaar_back_path", None)),
            has_pan_card=bool(getattr(active_resident, "pan_card_path", None)),
            has_passport=bool(getattr(active_resident, "passport_path", None)),
            has_selfie=bool(getattr(active_resident, "resident_selfie_path", None)),
        )

        return ResidentProfileFullRead(
            resident_id=active_resident.id,
            user_id=user.id,
            full_name=user.full_name,
            phone=user.phone,
            email=user.email,
            avatar_url=user.avatar_url,
            date_of_birth=getattr(active_resident, "date_of_birth", None),
            gender=getattr(active_resident, "gender", None),
            occupation=getattr(active_resident, "occupation", None),
            emergency_contact_name=getattr(active_resident, "emergency_contact_name", None) or getattr(active_resident, "emergency_contact", None),
            emergency_contact_phone=getattr(active_resident, "emergency_contact_phone", None),
            living_since=active_resident.check_in_date,
            permanent_address=address_info,
            stay_details=stay_summary,
            kyc_details=kyc_info,
        )

    def get_property_details(self, active_resident: Resident) -> ResidentPropertyDetailsResponse:
        """Retrieves assigned PG details, address, assigned room/bed, amenities and rules."""
        prop = self.db.get(Property, active_resident.property_id)
        if not prop:
            raise NotFoundError("Assigned property not found.")

        room_record = self.db.get(Room, active_resident.room_id) if active_resident.room_id else None
        bed_record = self.db.get(Bed, active_resident.bed_id) if active_resident.bed_id else None

        assigned_room = None
        if room_record:
            # Handle amenities whether stored as list or dict
            raw_amenities = room_record.amenities
            room_amenities_list = []
            if isinstance(raw_amenities, list):
                room_amenities_list = raw_amenities
            elif isinstance(raw_amenities, dict):
                room_amenities_list = [k for k, v in raw_amenities.items() if v]

            assigned_room = AssignedRoomDetail(
                id=room_record.id,
                room_number=room_record.room_number,
                floor_number=room_record.floor_number,
                room_type=room_record.room_type,
                amenities=room_amenities_list,
            )

        assigned_bed = None
        if bed_record:
            assigned_bed = AssignedBedDetail(
                id=bed_record.id,
                bed_number=bed_record.bed_number,
                monthly_rent=float(bed_record.monthly_rent) if bed_record.monthly_rent is not None else None,
            )

        # Amenities and rules with defaults
        amenities = prop.amenities if (prop.amenities and isinstance(prop.amenities, list)) else [
            "High-Speed Wi-Fi",
            "24/7 Power Backup",
            "RO Drinking Water",
            "Washing Machine & Laundry Area",
            "Daily Housekeeping",
            "CCTV Surveillance",
        ]
        inclusions = [
            "High-Speed Internet Included",
            "Water & Electricity Included",
            "Common Area Maintenance Included",
            "Bi-Weekly Linen Change Included",
        ]
        rules = prop.rules if (prop.rules and isinstance(prop.rules, list)) else [
            "Main gate closes at 10:30 PM",
            "Smoking and alcohol strictly prohibited on premises",
            "30-day notice period required before checkout",
            "Visitors allowed in common lounge only (9 AM - 8 PM)",
        ]

        return ResidentPropertyDetailsResponse(
            id=prop.id,
            name=prop.name,
            code=prop.code,
            property_type=prop.property_type,
            address_line1=prop.address_line1,
            address_line2=prop.address_line2,
            city=prop.city,
            state=prop.state,
            pincode=prop.pincode,
            contact_phone=prop.contact_phone,
            contact_email=prop.contact_email,
            total_floors=prop.total_floors,
            assigned_room=assigned_room,
            assigned_bed=assigned_bed,
            amenities=amenities,
            inclusions=inclusions,
            rules=rules,
        )

    def list_complaints(self, active_resident: Resident) -> List[ResidentComplaintRead]:
        """Lists maintenance complaints raised by the authenticated resident."""
        complaints = self.db.scalars(
            sa.select(Complaint)
            .where(Complaint.resident_id == active_resident.id)
            .order_by(Complaint.created_at.desc())
        ).all()

        items = []
        for c in complaints:
            staff_name = None
            if c.assigned_staff_id:
                staff_member = self.db.get(Staff, c.assigned_staff_id)
                staff_name = staff_member.name if staff_member else None
            items.append(
                ResidentComplaintRead(
                    id=c.id,
                    property_id=c.property_id,
                    resident_id=c.resident_id,
                    category=c.category,
                    title=c.title,
                    description=c.description or getattr(c, "issue", ""),
                    priority=c.priority,
                    status=c.status,
                    photo_path=c.photo_path,
                    assigned_staff_name=staff_name,
                    resolution_notes=c.resolution_notes,
                    created_at=c.created_at,
                    updated_at=c.updated_at,
                )
            )
        return items

    def create_complaint(
        self, active_resident: Resident, payload: ResidentComplaintCreate
    ) -> ResidentComplaintRead:
        """Creates a maintenance complaint for the resident's assigned PG."""
        desc = payload.description.strip()
        complaint = Complaint(
            property_id=active_resident.property_id,
            resident_id=active_resident.id,
            category=payload.category.upper(),
            title=payload.title.strip(),
            description=desc,
            priority=payload.priority.upper(),
            status="PENDING",
            photo_path=payload.photo_path,
        )
        # Ensure legacy column 'issue' is populated for complete backward compatibility
        if hasattr(complaint, "issue"):
            complaint.issue = desc

        self.db.add(complaint)
        self.db.commit()
        self.db.refresh(complaint)

        # Dispatch in-app notification if resident preferences allow
        pref = self.db.scalar(
            sa.select(ResidentPreference).where(ResidentPreference.user_id == active_resident.user_id)
        )
        if not pref or pref.maintenance_alerts_enabled:
            from app.services.notification_service import NotificationService
            NotificationService(self.db).dispatch(
                user_id=active_resident.user_id,
                title=f"Complaint Logged: {complaint.category}",
                body=f"Your complaint '{complaint.title}' has been registered successfully and is under review.",
                channel="PUSH",
            )

        return ResidentComplaintRead(
            id=complaint.id,
            property_id=complaint.property_id,
            resident_id=complaint.resident_id,
            category=complaint.category,
            title=complaint.title,
            description=complaint.description,
            priority=complaint.priority,
            status=complaint.status,
            photo_path=complaint.photo_path,
            assigned_staff_name=None,
            resolution_notes=None,
            created_at=complaint.created_at,
            updated_at=complaint.updated_at,
        )

    def get_property_contacts(self, active_resident: Resident) -> PropertyContactsResponse:
        """Retrieves Property Manager and Staff contact numbers for resident's PG."""
        prop = self.db.get(Property, active_resident.property_id)
        if not prop:
            raise NotFoundError("Property not found.")

        staff_list = self.db.scalars(
            sa.select(Staff)
            .where(Staff.property_id == active_resident.property_id, Staff.is_active == True)
        ).all()

        manager_item = None
        caretaker_item = None
        other_staff = []

        for s in staff_list:
            role_upper = s.role.upper()
            item = StaffContactItem(
                id=s.id,
                name=s.name,
                role=s.role,
                phone=s.phone,
                availability_hours=s.availability_hours or "9:00 AM - 6:00 PM",
                is_emergency=s.is_emergency_contact,
            )
            if not manager_item and role_upper in ["PROPERTY_MANAGER", "MANAGER", "WARDEN"]:
                manager_item = item
            elif not caretaker_item and role_upper in ["CARETAKER", "SECURITY", "NIGHT_CARETAKER", "GUARD", "NIGHT_SECURITY"]:
                caretaker_item = item
            else:
                other_staff.append(item)

        # Fallback if no specific manager record exists in staff table: use property contact info
        if not manager_item and (prop.contact_phone or prop.contact_email):
            manager_item = StaffContactItem(
                id=uuid.uuid4(),
                name=f"{prop.name} Helpdesk",
                role="Property Manager",
                phone=prop.contact_phone or "N/A",
                availability_hours="9:00 AM - 8:00 PM",
                is_emergency=True,
            )

        return PropertyContactsResponse(
            property_id=prop.id,
            property_name=prop.name,
            property_address=prop.address_line1,
            property_phone=prop.contact_phone,
            property_email=prop.contact_email,
            property_manager=manager_item,
            night_caretaker_security=caretaker_item,
            staff_contacts=other_staff,
        )

    def get_settings(self, user: User) -> ResidentSettingsRead:
        """Retrieves resident user's app preferences, initializing defaults if needed."""
        pref = self.db.scalar(
            sa.select(ResidentPreference).where(ResidentPreference.user_id == user.id)
        )
        if not pref:
            pref = ResidentPreference(
                user_id=user.id,
                dark_mode=False,
                language="en",
                rent_reminders_enabled=True,
                maintenance_alerts_enabled=True,
            )
            self.db.add(pref)
            self.db.commit()
            self.db.refresh(pref)

        return ResidentSettingsRead(
            dark_mode=pref.dark_mode,
            language=pref.language,
            rent_reminders_enabled=pref.rent_reminders_enabled,
            maintenance_alerts_enabled=pref.maintenance_alerts_enabled,
        )

    def update_settings(self, user: User, payload: ResidentSettingsUpdate) -> ResidentSettingsRead:
        """Updates resident user's app preferences."""
        pref = self.db.scalar(
            sa.select(ResidentPreference).where(ResidentPreference.user_id == user.id)
        )
        if not pref:
            pref = ResidentPreference(user_id=user.id)
            self.db.add(pref)

        if payload.dark_mode is not None:
            pref.dark_mode = payload.dark_mode
        if payload.language is not None:
            pref.language = payload.language
        if payload.rent_reminders_enabled is not None:
            pref.rent_reminders_enabled = payload.rent_reminders_enabled
        if payload.maintenance_alerts_enabled is not None:
            pref.maintenance_alerts_enabled = payload.maintenance_alerts_enabled

        self.db.commit()
        self.db.refresh(pref)

        return ResidentSettingsRead(
            dark_mode=pref.dark_mode,
            language=pref.language,
            rent_reminders_enabled=pref.rent_reminders_enabled,
            maintenance_alerts_enabled=pref.maintenance_alerts_enabled,
        )
