from decimal import Decimal

import pytest

from app.services.deposit_service import compute_exit_settlement as settle


def D(x):
    return Decimal(x)


def test_fifty_percent_refund_regardless_of_stay():
    s = settle(5000)
    assert (s.refund, s.forfeited, s.deductions, s.net_payable_by_resident) == (D("2500.00"), D("2500.00"), D(0), D(0))


def test_dues_and_damages_come_out_of_refundable_half():
    s = settle(5000, unpaid_dues=1200, damage_charges=500)
    assert s.refund == D("800.00")
    assert s.deducted_from_deposit == D("1700.00")
    assert s.net_payable_by_resident == D(0)


def test_dues_exceeding_refundable_half_leave_balance_owed():
    s = settle(5000, unpaid_dues=3000)
    assert s.refund == D(0)
    assert s.deducted_from_deposit == D("2500.00")
    assert s.net_payable_by_resident == D("500.00")


def test_money_is_conserved():
    for dep, dues, dmg in [(5000, 0, 0), (5000, 1234.56, 99.99), (7777.77, 100, 0), (0, 500, 0)]:
        s = settle(dep, dues, dmg)
        assert s.refund + s.forfeited + s.deducted_from_deposit == s.deposit_held


def test_rounding_half_up_to_paise():
    assert settle("1001.01").refund == D("500.51")  # 500.505 -> 500.51


def test_zero_deposit_and_custom_percent():
    assert settle(0).refund == D(0)
    assert settle(5000, refund_percent=100).refund == D("5000.00")
    with pytest.raises(ValueError):
        settle(5000, refund_percent=101)
