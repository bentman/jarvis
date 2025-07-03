import pytest
from fastapi.testclient import TestClient
from api.main import app
from services.ai_service import ai_service

client = TestClient(app)

def test_root_updated():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["version"] == "1.1.0"
    assert "ai_integration" in data["features"]

def test_health_check_with_ai():
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert "ai_integration" in data
    assert data["version"] == "1.1.0"

def test_chat_endpoint_with_ai():
    response = client.post("/api/chat", json={"content": "Hello"})
    assert response.status_code == 200
    data = response.json()
    assert "response" in data
    assert "mode" in data  # Should be "ai" or "echo"
    assert "model" in data
    assert "timestamp" in data

def test_ai_status_endpoint():
    response = client.get("/api/ai/status")
    assert response.status_code == 200
    data = response.json()
    assert "ai_available" in data
    assert "mode" in data

def test_ai_test_endpoint():
    response = client.get("/api/ai/test")
    assert response.status_code == 200
    data = response.json()
    assert "ai_available" in data
    assert "test_successful" in data

def test_status_endpoint_updated():
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert data["version"] == "1.1.0"
    assert "ai_service" in data
    assert "fallback_mode" in data["features"]

@pytest.mark.asyncio
async def test_ai_service_fallback():
    # Test that AI service handles unavailable Ollama gracefully
    result = await ai_service.generate_response("Test message")
    assert "response" in result
    assert "mode" in result
    # Should work regardless of whether Ollama is available
