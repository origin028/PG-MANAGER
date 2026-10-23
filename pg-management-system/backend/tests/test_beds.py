def test_beds_endpoint_unauthorized(client):
    response = client.get("/api/v1/beds?room_id=00000000-0000-0000-0000-000000000000")
    assert response.status_code == 401
