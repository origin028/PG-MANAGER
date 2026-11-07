def test_root_endpoint(client):
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "service" in data
    assert "docs" in data
    assert "health" in data


def test_health_check_endpoint(client):
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    payload = response.json()
    assert "success" in payload
    assert "data" in payload
    assert "status" in payload["data"]
    assert "database" in payload["data"]
    assert "version" in payload["data"]
