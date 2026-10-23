def test_properties_endpoint_unauthorized(client):
    response = client.get("/api/v1/properties")
    assert response.status_code == 401
    data = response.json()
    assert data["success"] is False
    assert data["error"]["code"] == "AUTHENTICATION_FAILED"
