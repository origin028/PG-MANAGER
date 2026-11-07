from app.core.security import get_password_hash, verify_password, create_access_token, decode_token


def test_password_hashing():
    raw_password = "SecurePassword@123"
    hashed = get_password_hash(raw_password)
    assert hashed != raw_password
    assert verify_password(raw_password, hashed) is True
    assert verify_password("WrongPassword", hashed) is False


def test_access_token_creation_and_decoding():
    subject_id = "550e8400-e29b-41d4-a716-446655440000"
    claims = {"role": "SUPER_ADMIN", "company_id": "company-123"}
    token = create_access_token(subject=subject_id, claims=claims)
    decoded = decode_token(token)

    assert decoded["sub"] == subject_id
    assert decoded["role"] == "SUPER_ADMIN"
    assert decoded["company_id"] == "company-123"
    assert decoded["type"] == "access"
    assert "exp" in decoded


def test_login_missing_credentials(client):
    response = client.post("/api/v1/auth/login", json={})
    assert response.status_code == 422
