"""Licence key tool, for us (the seller) only. Never run on the customer's server.

  python scripts/license_keys.py genkeys
      Creates a signing key pair. Keep the PRIVATE key in a password manager (never in git or on the
      server). Put the PUBLIC key in the server setting LICENSE_PUBLIC_KEY.

  LICENSE_PRIVATE_KEY=... python scripts/license_keys.py issue --beds 250 --to "Origin Living" [--months 12]
      Prints a licence key that allows up to 250 beds (all PGs together), optionally expiring.

  python scripts/license_keys.py check <key> --public <public key>
      Shows what a key allows.
"""
import argparse
import base64
import os
import sys
import uuid
from datetime import date, timedelta

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: E402
from cryptography.hazmat.primitives.serialization import Encoding, NoEncryption, PrivateFormat, PublicFormat  # noqa: E402


def b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("genkeys")
    i = sub.add_parser("issue")
    i.add_argument("--beds", type=int, required=True)
    i.add_argument("--to", default=None, help="Customer name (shown in the licence)")
    i.add_argument("--months", type=int, default=None, help="Validity; omit for no expiry")
    c = sub.add_parser("check")
    c.add_argument("key")
    c.add_argument("--public", required=True)
    a = ap.parse_args()

    if a.cmd == "genkeys":
        k = Ed25519PrivateKey.generate()
        priv = k.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
        pub = k.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
        print(f"PRIVATE (keep secret, never commit): {b64(priv)}")
        print(f"LICENSE_PUBLIC_KEY (server setting):  {b64(pub)}")
        return

    from app.services import license_service

    if a.cmd == "issue":
        priv = os.environ.get("LICENSE_PRIVATE_KEY")
        if not priv:
            raise SystemExit("Set LICENSE_PRIVATE_KEY to the private key from 'genkeys'.")
        if a.beds < 1:
            raise SystemExit("--beds must be at least 1.")
        exp = (date.today() + timedelta(days=30 * a.months)).isoformat() if a.months else None
        print(license_service.sign({"v": 1, "lid": str(uuid.uuid4()), "beds": a.beds, "exp": exp, "to": a.to}, priv))
    else:
        lic = license_service.parse(a.key, a.public)
        print(f"Valid. Up to {lic.max_beds} beds. Expires: {lic.expires or 'never'}. Issued to: {lic.issued_to or '-'}.")


if __name__ == "__main__":
    main()
