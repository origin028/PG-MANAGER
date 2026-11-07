import hashlib
import hmac

import pytest

from app.integrations.payment_gateway import RazorpayGateway


def test_webhook_signature_uses_hmac_sha256_of_raw_payload():
    payload = b'{"event":"payment.captured"}'
    secret = "webhook-secret"
    signature = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()

    gateway = RazorpayGateway("key_id", "key_secret")
    assert gateway.verify_webhook_signature(payload, signature, secret) is True
    assert gateway.verify_webhook_signature(payload + b" ", signature, secret) is False
    assert gateway.verify_webhook_signature(payload, "not-a-signature", secret) is False


def test_gateway_requires_real_credentials():
    with pytest.raises(ValueError, match="not configured"):
        RazorpayGateway("", "")
