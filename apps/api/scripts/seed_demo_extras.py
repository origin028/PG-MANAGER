"""Adds realistic demo content on top of seed_demo_pg_data.py. Safe to run repeatedly.

    ENVIRONMENT=development python scripts/seed_demo_extras.py

Never run against production: it refuses unless ENVIRONMENT is a development environment.
"""
import os
import sys
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import sqlalchemy as sa  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.security import get_password_hash  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.models.announcement import Announcement  # noqa: E402
from app.models.attendance import AttendanceLog  # noqa: E402
from app.models.complaint import Complaint  # noqa: E402
from app.models.deposit_ledger import DepositLedgerEntry  # noqa: E402
from app.models.expense import Expense  # noqa: E402
from app.models.food_menu import FoodMenu  # noqa: E402
from app.models.invoice import Invoice  # noqa: E402
from app.models.lead import Lead  # noqa: E402
from app.models.payment import Payment  # noqa: E402
from app.models.property import Property  # noqa: E402
from app.models.resident import Resident  # noqa: E402
from app.models.role import Role  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services.deposit_service import DepositService  # noqa: E402

MENU = {
    "MONDAY": (["Poha", "Banana", "Tea / Coffee"], ["Rice", "Dal tadka", "Aloo gobi", "Roti", "Curd"], ["Jeera rice", "Rajma", "Roti", "Salad"]),
    "TUESDAY": (["Idli", "Sambar", "Coconut chutney"], ["Rice", "Sambar", "Beans poriyal", "Roti"], ["Veg pulao", "Paneer butter masala", "Roti"]),
    "WEDNESDAY": (["Aloo paratha", "Curd", "Pickle"], ["Rice", "Chole", "Bhindi fry", "Roti"], ["Rice", "Egg curry / Veg kurma", "Roti"]),
    "THURSDAY": (["Upma", "Chutney", "Tea / Coffee"], ["Lemon rice", "Dal", "Cabbage sabzi", "Roti"], ["Rice", "Kadhi pakoda", "Roti", "Salad"]),
    "FRIDAY": (["Dosa", "Sambar", "Chutney"], ["Rice", "Rasam", "Mixed veg", "Roti"], ["Veg biryani", "Raita", "Gulab jamun"]),
    "SATURDAY": (["Bread omelette / Bread jam", "Tea / Coffee"], ["Rice", "Dal makhani", "Aloo matar", "Roti"], ["Rice", "Chicken curry / Paneer curry", "Roti"]),
    "SUNDAY": (["Puri", "Aloo sabzi", "Tea / Coffee"], ["Veg fried rice", "Manchurian"], ["Rice", "Dal", "Mix veg", "Roti", "Ice cream"]),
}
TIMES = {"BREAKFAST": ("07:30 AM", "09:30 AM"), "LUNCH": ("12:30 PM", "02:30 PM"), "DINNER": ("08:00 PM", "10:00 PM")}


def main() -> None:
    if settings.is_production:
        raise SystemExit("Refusing to seed demo data in production.")
    db = SessionLocal()
    prop = db.scalar(sa.select(Property).order_by(Property.created_at))
    if not prop:
        raise SystemExit("Run scripts/seed_demo_pg_data.py first.")
    owner = db.scalar(sa.select(User).where(User.email == "admin@originpg.com"))
    residents = db.scalars(sa.select(Resident).where(Resident.property_id == prop.id, Resident.status == "ACTIVE")).all()
    today = date.today()

    # Resident demo password so residents can test without email OTP.
    for r in residents:
        if r.user:
            r.user.password_hash = get_password_hash("Resident@123")

    # Easy demo logins (development only; this script refuses to run in production):
    #   owner    -> admin / admin
    #   resident -> 0000000000 / 0000000000
    #   kitchen  -> kitchen / kitchen
    if owner and not db.scalar(sa.select(User.id).where(User.email == "admin")):
        db.add(User(company_id=owner.company_id, role_id=owner.role_id, email="admin", phone="0000000009",
                    full_name="Demo Owner", password_hash=get_password_hash("admin"), is_active=True, approval_status="APPROVED"))
    kitchen_role = db.scalar(sa.select(Role).where(Role.name == "KITCHEN"))
    if owner and kitchen_role and not db.scalar(sa.select(User.id).where(User.email == "kitchen")):
        db.add(User(company_id=owner.company_id, role_id=kitchen_role.id, email="kitchen", phone="0000000008",
                    full_name="Kitchen Staff", password_hash=get_password_hash("kitchen"), is_active=True, approval_status="APPROVED"))
    demo = next((r for r in residents if r.user and r.user.phone in ("9876543210", "0000000000")), residents[0] if residents else None)
    if demo and demo.user:
        demo.user.phone = "0000000000"
        demo.user.password_hash = get_password_hash("0000000000")

    # Weekly menu
    if not db.scalar(sa.select(FoodMenu.id).where(FoodMenu.property_id == prop.id)):
        for day, meals in MENU.items():
            for meal_type, dishes in zip(("BREAKFAST", "LUNCH", "DINNER"), meals):
                db.add(FoodMenu(property_id=prop.id, day_of_week=day, meal_type=meal_type, dishes=dishes,
                                start_time=TIMES[meal_type][0], end_time=TIMES[meal_type][1], is_active=True))

    # Announcements
    if not db.scalar(sa.select(Announcement.id).where(Announcement.company_id == prop.company_id)):
        db.add(Announcement(company_id=prop.company_id, property_id=prop.id, created_by_user_id=owner.id if owner else None,
                            title="Water tank cleaning on Sunday", content="Water supply will be off from 10am to 1pm this Sunday for tank cleaning.", is_active=True))
        db.add(Announcement(company_id=prop.company_id, property_id=None, created_by_user_id=owner.id if owner else None,
                            title="Rent due by the 5th", content="Please pay this month's rent in the app before the 5th. Thank you!", is_active=True))

    # Complaints in each state
    if residents and not db.scalar(sa.select(Complaint.id).where(Complaint.property_id == prop.id)):
        for r, cat, title, status, notes in [
            (residents[0], "PLUMBING", "Bathroom tap leaking", "OPEN", None),
            (residents[-1], "WIFI", "Wi-Fi slow on second floor", "IN_PROGRESS", None),
            (residents[0], "CLEANING", "Room not cleaned on Tuesday", "RESOLVED", "Cleaned the same evening. Sorry for the miss."),
        ]:
            db.add(Complaint(property_id=prop.id, resident_id=r.id, category=cat, title=title, description=title,
                             priority="MEDIUM", status=status, resolution_notes=notes))

    # Expenses (this month)
    if not db.scalar(sa.select(Expense.id).where(Expense.company_id == prop.company_id)):
        first = today.replace(day=1)
        for cat, title, amt, method, d in [
            ("GROCERIES", "Vegetables and groceries", 6850, "UPI", 2), ("SALARIES", "Cook and housekeeping salaries", 8000, "BANK_TRANSFER", 1),
            ("UTILITIES", "Electricity bill", 3180, "UPI", 6), ("UTILITIES", "Internet bill", 1499, "UPI", 8),
            ("MAINTENANCE", "Plumber visit", 1200, "CASH", 10), ("SUPPLIES", "Cleaning supplies", 940, "UPI", 12),
        ]:
            db.add(Expense(company_id=prop.company_id, property_id=prop.id, created_by_id=owner.id if owner else None,
                           category=cat, title=title, amount=Decimal(amt), method=method, date=min(today, first + timedelta(days=d - 1))))

    # Last month's rent: invoiced and paid, so history and collections are not empty.
    last = (today.replace(day=1) - timedelta(days=1))
    ym = last.strftime("%Y-%m")
    for i, r in enumerate(residents):
        if db.scalar(sa.select(Invoice.id).where(Invoice.resident_id == r.id, Invoice.billing_month == ym)):
            continue
        inv = Invoice(property_id=prop.id, resident_id=r.id, invoice_number=f"INV-{ym.replace('-', '')}-DEMO{i:02d}", billing_month=ym,
                      invoice_type="RENT", amount=Decimal(str(r.monthly_rent)), paid_amount=Decimal(str(r.monthly_rent)),
                      due_date=last.replace(day=5), status="PAID", notes="Demo: last month's rent")
        db.add(inv)
        db.flush()
        db.add(Payment(property_id=prop.id, invoice_id=inv.id, resident_id=r.id, payment_number=f"PAY-{ym.replace('-', '')}-DEMO{i:02d}",
                       amount=Decimal(str(r.monthly_rent)), payment_mode="UPI", status="SUCCESS",
                       paid_at=datetime.combine(last.replace(day=3), time(10, 30), tzinfo=timezone.utc)))

    # Earlier months (1-9 months back): rent paid and running costs, so the Finance charts have a real trend.
    # Costs are sized for this small demo home; amounts vary month to month like a real PG.
    for back in range(1, 10):
        m = today.replace(day=1)
        for _ in range(back):
            m = (m - timedelta(days=1)).replace(day=1)
        ym = m.strftime("%Y-%m")
        for i, r in enumerate(residents):
            if r.check_in_date and r.check_in_date > m:
                continue
            number = f"INV-{ym.replace('-', '')}-DEMO{i:02d}"
            if db.scalar(sa.select(Invoice.id).where(Invoice.invoice_number == number)):
                continue
            rent = Decimal(str(r.monthly_rent))
            inv = Invoice(property_id=prop.id, resident_id=r.id, invoice_number=number, billing_month=ym, invoice_type="RENT",
                          amount=rent, paid_amount=rent, due_date=m.replace(day=5), status="PAID", notes="Demo rent")
            db.add(inv)
            db.flush()
            db.add(Payment(property_id=prop.id, invoice_id=inv.id, resident_id=r.id, payment_number=f"PAY-{ym.replace('-', '')}-DEMO{i:02d}",
                           amount=rent, payment_mode="CASH" if (back + i) % 4 == 0 else "UPI", status="SUCCESS",
                           paid_at=datetime.combine(m.replace(day=2 + (back + i) % 5), time(10, 30), tzinfo=timezone.utc)))
        marker = f"(demo {ym})"
        if not db.scalar(sa.select(Expense.id).where(Expense.title.like(f"%{marker}"))):
            season = [100, 0, 400, 900, 1500, 1800, 1200, 600, 200][back - 1]  # summer electricity peak
            for cat, title, amt, method, day in [
                ("SALARIES", "Part-time cook", 8000, "BANK_TRANSFER", 1),
                ("GROCERIES", "Vegetables and groceries", 6200 + (back * 370) % 1600, "UPI", 3),
                ("UTILITIES", "Electricity bill", 2900 + season, "UPI", 7),
                ("UTILITIES", "Internet bill", 1499, "UPI", 9),
            ] + ([("MAINTENANCE", "Repairs", 1800 + back * 150, "CASH", 14)] if back % 3 == 0 else []):
                db.add(Expense(company_id=prop.company_id, property_id=prop.id, created_by_id=owner.id if owner else None,
                               category=cat, title=f"{title} {marker}", amount=Decimal(amt), method=method, date=m.replace(day=day)))

    # Deposits on the ledger
    svc = DepositService(db)
    for r in residents:
        if not db.scalar(sa.select(DepositLedgerEntry.id).where(DepositLedgerEntry.resident_id == r.id)):
            svc.record_received(r, prop.company_id, Decimal("5000.00"), "Demo deposit", owner.id if owner else None)

    # Fingerprint ids + today's entries
    if residents and not db.scalar(sa.select(AttendanceLog.id).where(AttendanceLog.property_id == prop.id)):
        start = datetime.combine(today, time(2, 0), tzinfo=timezone.utc)  # ~7:30 IST
        for i, r in enumerate(residents):
            r.biometric_id = str(101 + i)
            db.add(AttendanceLog(property_id=prop.id, resident_id=r.id, device_user_id=r.biometric_id, punched_at=start + timedelta(minutes=40 * i), direction="OUT"))
            if i % 2 == 0:
                db.add(AttendanceLog(property_id=prop.id, resident_id=r.id, device_user_id=r.biometric_id, punched_at=start + timedelta(hours=9, minutes=15 * i), direction="IN"))

    # Website enquiries
    if not db.scalar(sa.select(Lead.id).where(Lead.property_id == prop.id)):
        db.add(Lead(property_id=prop.id, name="Ananya Rao", phone="9845011122", status="NEW", source="WEBSITE", requirement="Looking for a double-sharing room from next month."))
        db.add(Lead(property_id=prop.id, name="Kabir Singh", phone="9900112233", status="CONTACTED", source="WEBSITE"))

    db.commit()
    print(f"Demo extras ready for '{prop.name}' ({len(residents)} active residents).")


if __name__ == "__main__":
    main()
