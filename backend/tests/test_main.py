import pytest
from fastapi.testclient import TestClient
from api.main import app

client = TestClient(app)

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "running"
    assert "Jarvis" in data["message"]

def test_health_check():
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"

def test_chat_endpoint():
    response = client.post("/api/chat", json={"content": "Hello"})
    assert response.status_code == 200
    data = response.json()
    assert "Echo: Hello" in data["response"]
    assert "timestamp" in data

def test_status_endpoint():
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert data["backend"] == "running"
