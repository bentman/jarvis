from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
import os
from dotenv import load_dotenv
import logging

# Import our AI service
from services.ai_service import ai_service

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="Jarvis AI Assistant",
    description="AI Assistant Backend with Ollama Integration",
    version="1.1.0"
)

# CORS middleware for frontend access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pydantic models
class ChatMessage(BaseModel):
    content: str

class ChatResponse(BaseModel):
    response: str
    mode: str
    model: str
    timestamp: str

# Root endpoint
@app.get("/")
async def root():
    return {
        "message": "Jarvis AI Assistant Backend",
        "status": "running",
        "version": "1.1.0",
        "features": ["chat", "ai_integration", "fallback_mode"],
        "docs": "/docs"
    }

# Health check endpoint
@app.get("/api/health")
async def health_check():
    ai_status = await ai_service.get_status()
    
    return {
        "status": "healthy",
        "service": "jarvis-backend",
        "version": "1.1.0",
        "ai_integration": ai_status,
        "timestamp": datetime.now().isoformat()
    }

# Enhanced chat endpoint with AI
@app.post("/api/chat", response_model=ChatResponse)
async def chat(message: ChatMessage):
    logger.info(f"Chat request: {message.content}")
    
    # Generate response using AI service (with fallback)
    result = await ai_service.generate_response(message.content)
    
    return ChatResponse(
        response=result["response"],
        mode=result["mode"],
        model=result["model"],
        timestamp=result["timestamp"]
    )

# Enhanced status endpoint
@app.get("/api/status")
async def get_status():
    ai_status = await ai_service.get_status()
    
    return {
        "backend": "running",
        "version": "1.1.0",
        "ai_service": ai_status,
        "features": {
            "chat": True,
            "ai_integration": ai_status["ai_available"],
            "fallback_mode": True,
            "health_check": True
        }
    }

# New endpoint: AI service info
@app.get("/api/ai/status")
async def ai_status():
    return await ai_service.get_status()

# New endpoint: Test AI connectivity
@app.get("/api/ai/test")
async def test_ai():
    is_available = await ai_service.is_available()
    
    if is_available:
        test_result = await ai_service.generate_response("Hello, are you working?")
        return {
            "ai_available": True,
            "test_successful": True,
            "test_response": test_result
        }
    else:
        return {
            "ai_available": False,
            "test_successful": False,
            "message": "AI service not available - using fallback mode"
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
