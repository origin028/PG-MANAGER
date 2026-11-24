"""Licence ("super key") for selling the software: one key per customer sets the maximum number of beds.

Status: BUILT BUT OFF. While settings.LICENSE_ENFORCED is false (the default during testing) keys can be
activated and are stored, but nothing is blocked. Turning it on later (LICENSE_ENFORCED=true +
LICENSE_PUBLIC_KEY) makes:
  - owners activate a key before using the dashboard (see `require_active_license`), and
  - the bed limit come from the key (`effective_bed_limit`), so a customer cannot add more beds/PGs
    than they paid for.

Keys are signed with our private Ed25519 key (kept offline, never in this repo) and verified with the
public key, so a key cannot be forged or edited (e.g. changing 250 beds to 900).
Format: OL1.<base64url JSON payload>.<base64url signature>
Payload: {"v": 1, "lid": "<licence id>", "beds": 250, "exp": "2027-11-24" | null, "to": "<customer>"}
Issue keys with: python scripts/license_keys.py issue --beds 250 --to "Customer" --months 12
"""
import base64
import json
from dataclasses import dataclass
from datetime import date, datetime, timezone
from typing import Optional

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

from app.core.config import settings
from app.core.exceptions import BadRequestError, PGException
from app.models.property import Company

PREFIX = "OL1"


@dataclass
class License:
    license_id: str
    max_beds: int
    expires: Optional[date]
    issued_to: Optional[str]


def _b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def sign(payload: dict, private_key_b64: str) -> str:
    """Used only by our offline key tool (scripts/license_keys.py)."""
    key = Ed25519PrivateKey.from_private_bytes(_unb64(private_key_b64))
    body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    return f"{PREFIX}.{_b64(body)}.{_b64(key.sign(body))}"


def parse(key: str, public_key_b64: Optional[str] = None) -> License:
    """Verifies the signature and returns what the key allows. Raises BadRequestError for any bad key."""
    pub = public_key_b64 if public_key_b64 is not None else settings.LICENSE_PUBLIC_KEY
    if not pub:
        raise BadRequestError("Licence keys are not set up on this server yet.")
    try:
        prefix, body_b64, sig_b64 = key.strip().split(".")
        if prefix != PREFIX:
            raise ValueError
        body = _unb64(body_b64)
        Ed25519PublicKey.from_public_bytes(_unb64(pub)).verify(_unb64(sig_b64), body)
        p = json.loads(body)
        beds = int(p["beds"])
        if p.get("v") != 1 or beds < 1:
            raise ValueError
        exp = date.fromisoformat(p["exp"]) if p.get("exp") else None
    except (ValueError, KeyError, TypeError, InvalidSignature, json.JSONDecodeError):
        raise BadRequestError("This licence key is not valid. Please check it and try again.")
    if exp and exp < date.today():
        raise BadRequestError("This licence key has expired.")
    return License(license_id=str(p.get("lid", "")), max_beds=beds, expires=exp, issued_to=p.get("to"))


def activate(company: Company, key: str) -> License:
    lic = parse(key)
    company.license_key = key.strip()
    company.license_max_beds = lic.max_beds
    company.license_activated_at = datetime.now(timezone.utc)
    company.license_expires_at = datetime(lic.expires.year, lic.expires.month, lic.expires.day, tzinfo=timezone.utc) if lic.expires else None
    if settings.LICENSE_ENFORCED:
        company.bed_limit = lic.max_beds
    return lic


def is_active(company: Company) -> bool:
    if not company.license_key or not company.license_max_beds:
        return False
    exp = company.license_expires_at
    return not exp or (exp if exp.tzinfo else exp.replace(tzinfo=timezone.utc)) > datetime.now(timezone.utc)


def effective_bed_limit(company: Company) -> int:
    """The bed cap in force. With enforcement off this is the company's own setting (default 250)."""
    if settings.LICENSE_ENFORCED:
        return company.license_max_beds if is_active(company) else 0
    return company.bed_limit


def status(company: Company) -> dict:
    return {
        "enforced": settings.LICENSE_ENFORCED,
        "active": is_active(company),
        "max_beds": company.license_max_beds,
        "bed_limit_in_force": effective_bed_limit(company),
        "activated_at": company.license_activated_at.isoformat() if company.license_activated_at else None,
        "expires_at": company.license_expires_at.isoformat() if company.license_expires_at else None,
    }


class LicenseRequiredError(PGException):
    def __init__(self):
        super().__init__(status_code=402, message="Enter your licence key to start using the system.", code="LICENSE_REQUIRED")


def require_active_license(company: Optional[Company]) -> None:
    """Gate for owner/staff screens. Does nothing while enforcement is off (testing phase)."""
    if settings.LICENSE_ENFORCED and (not company or not is_active(company)):
        raise LicenseRequiredError()
