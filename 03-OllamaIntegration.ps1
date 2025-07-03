# 03-OllamaIntegration.ps1 - Add real AI capabilities to existing FastAPI backend
# Incrementally adds Ollama integration while keeping existing functionality

param(
    [switch]$Install,
    [switch]$Setup,
    [switch]$Test,
    [switch]$All
)

function Write-Step($message) {
    Write-Host "🔧 $message" -ForegroundColor Green
}

function Write-Success($message) {
    Write-Host "✅ $message" -ForegroundColor Green
}

function Write-Warning($message) {
    Write-Host "⚠️  $message" -ForegroundColor Yellow
}

function Test-OllamaRunning {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5
        return $true
    } catch {
        return $false
    }
}

function Add-OllamaDependency {
    Write-Step "Adding Ollama client to requirements..."
    
    # Read existing requirements
    $requirements = Get-Content "backend/requirements.txt"
    
    # Add ollama client if not present
    if ($requirements -notcontains "ollama==0.1.7") {
        $requirements += ""
        $requirements += "# AI Integration"
        $requirements += "ollama==0.1.7"
        $requirements += "httpx==0.25.2"
        
        Set-Content -Path "backend/requirements.txt" -Value $requirements
        Write-Success "Added Ollama dependency to requirements.txt"
    } else {
        Write-Success "Ollama dependency already present"
    }
}

function Create-PersonalityConfig {
    Write-Step "Creating personality configuration..."
    
    if (Test-Path "jarvis_personality.json") {
        Write-Success "Personality config already exists - skipping"
        return
    }
    
    $personalityConfig = @"
{
  "_comment_purpose": "Jarvis AI Assistant Personality Configuration",
  "_comment_description": "This file defines the personality, behavior, and identity of your AI assistant. Modify these settings to customize how your AI responds and behaves.",
  "_comment_usage": "This configuration is loaded during backend startup and applied to all AI interactions. Changes require restarting the backend to take effect.",
  "_comment_customization": "To customize: 1) Edit values below 2) Save file 3) Restart backend (.\run_backend.ps1) 4) Test with frontend chat",
  "_comment_after_build": "After building/deploying, you can still modify this file to change personality without rebuilding code. Just restart the backend service.",

  "identity": {
    "_comment": "Core identity settings - who the AI thinks it is",
    "name": "Jarvis",
    "display_name": "J.A.R.V.I.S.",
    "full_name": "Just A Rather Very Intelligent System",
    "role": "AI Assistant"
  },

  "personality": {
    "_comment": "Personality traits - adjust these to change how the AI behaves and responds",
    "base_personality": "You are Jarvis, an AI assistant inspired by Tony Stark's AI. Be helpful, intelligent, and slightly witty.",
    "tone": "professional yet friendly",
    "humor_level": "subtle wit and occasional dry humor",
    "formality": "respectful but not overly formal",
    "confidence": "confident but not arrogant",
    "_comment_examples": "Examples: 'dry and sarcastic' vs 'warm and encouraging' vs 'formal and precise'"
  },

  "behavior": {
    "_comment": "How the AI should behave in conversations",
    "response_style": "concise yet thorough",
    "proactiveness": "offer helpful suggestions when appropriate",
    "problem_solving": "analytical and methodical",
    "error_handling": "acknowledge limitations gracefully",
    "_comment_tips": "Adjust response_style: 'brief and direct' vs 'detailed explanations' vs 'conversational'"
  },

  "capabilities": {
    "_comment": "What the AI claims it can help with - for self-description",
    "primary_functions": [
      "Answer questions and provide information",
      "Help with problem-solving and analysis",
      "Assist with planning and organization",
      "Provide technical guidance and explanations"
    ],
    "specialties": [
      "Technology and programming",
      "Data analysis and research", 
      "Creative problem solving",
      "Process optimization"
    ]
  },

  "interaction_style": {
    "_comment": "Detailed behavioral guidelines for conversations",
    "greeting_style": "acknowledging and ready to assist",
    "farewell_style": "professional and helpful",
    "clarification_approach": "ask focused questions to better understand needs",
    "explanation_method": "break down complex topics into understandable parts",
    "_comment_greeting_examples": "'Hello! How can I assist you today?' vs 'Good to see you again. What can I help with?'"
  },

  "advanced_settings": {
    "_comment": "Advanced personality tweaks - be careful modifying these",
    "creativity_level": "balanced - creative when helpful, practical when needed",
    "technical_depth": "adjust explanation detail based on user expertise",
    "initiative_level": "moderate - helpful suggestions without being pushy",
    "emotional_intelligence": "empathetic and supportive when appropriate",
    "_comment_warning": "These settings affect core behavior. Small changes can have big impacts."
  }
}
"@
    
    Set-Content -Path "jarvis_personality.json" -Value $personalityConfig
    Write-Success "Personality configuration created"
}

function Create-AIService {
    Write-Step "Creating AI service module..."
    
    # Create services directory
    if (!(Test-Path "backend/services")) {
        New-Item -ItemType Directory -Path "backend/services" -Force | Out-Null
    }
    
    $aiService = @"
import ollama
import asyncio
import json
import os
from typing import Optional
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

class AIService:
    def __init__(self, model: str = "llama3.1:8b", ollama_url: str = "http://localhost:11434"):
        self.model = model
        self.ollama_url = ollama_url
        self.client = None
        self.personality_config = self._load_personality_config()
        self._initialize_client()
    
    def _load_personality_config(self):
        """Load personality configuration from jarvis_personality.json"""
        config_path = "../../jarvis_personality.json"  # Go up two levels from backend/services/
        fallback_config_path = "../jarvis_personality.json"  # Try backend/ directory as fallback
        fallback_config_path2 = "jarvis_personality.json"  # Try current directory as last resort
        
        try:
            # Try project root first (normal case when run from backend/services/)
            if os.path.exists(config_path):
                with open(config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    logger.info("Loaded personality config from ../../jarvis_personality.json")
                    return config
            # Try backend directory as fallback
            elif os.path.exists(fallback_config_path):
                with open(fallback_config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    logger.info("Loaded personality config from ../jarvis_personality.json")
                    return config
            # Try current directory as last resort
            elif os.path.exists(fallback_config_path2):
                with open(fallback_config_path2, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    logger.info("Loaded personality config from jarvis_personality.json")
                    return config
            else:
                logger.warning("Personality config file not found, using defaults")
                return self._get_default_personality()
        except Exception as e:
            logger.error(f"Failed to load personality config: {e}")
            return self._get_default_personality()
    
    def _get_default_personality(self):
        """Default personality configuration if file is missing"""
        return {
            "identity": {
                "name": "Jarvis",
                "display_name": "J.A.R.V.I.S.",
                "role": "AI Assistant"
            },
            "personality": {
                "base_personality": "You are Jarvis, an AI assistant inspired by Tony Stark's AI. Be helpful, intelligent, and slightly witty."
            }
        }
    
    def _get_system_prompt(self):
        """Build system prompt from personality configuration"""
        config = self.personality_config
        
        # Start with base personality
        system_prompt = config.get("personality", {}).get(
            "base_personality", 
            "You are Jarvis, an AI assistant. Be helpful and intelligent."
        )
        
        # Add personality traits
        personality = config.get("personality", {})
        if personality.get("tone"):
            system_prompt += f" Your tone should be {personality['tone']}."
        if personality.get("humor_level"):
            system_prompt += f" Use {personality['humor_level']}."
        if personality.get("confidence"):
            system_prompt += f" Be {personality['confidence']}."
        
        # Add behavior guidelines
        behavior = config.get("behavior", {})
        if behavior.get("response_style"):
            system_prompt += f" Keep responses {behavior['response_style']}."
        if behavior.get("problem_solving"):
            system_prompt += f" Approach problems in an {behavior['problem_solving']} way."
        
        # Add interaction style
        interaction = config.get("interaction_style", {})
        if interaction.get("explanation_method"):
            system_prompt += f" When explaining complex topics, {interaction['explanation_method']}."
        
        return system_prompt
    
    def _initialize_client(self):
        """Initialize Ollama client"""
        try:
            # Test if Ollama is available
            import httpx
            response = httpx.get(f"{self.ollama_url}/api/tags", timeout=5)
            if response.status_code == 200:
                self.client = ollama.Client(host=self.ollama_url)
                logger.info(f"Ollama client initialized successfully with personality: {self.personality_config.get('identity', {}).get('name', 'Unknown')}")
            else:
                logger.warning(f"Ollama not available at {self.ollama_url}")
        except Exception as e:
            logger.warning(f"Failed to initialize Ollama client: {e}")
            self.client = None
    
    async def is_available(self) -> bool:
        """Check if AI service is available"""
        if not self.client:
            return False
        
        try:
            # Test with a simple request
            response = await asyncio.get_event_loop().run_in_executor(
                None, 
                lambda: self.client.list()
            )
            return True
        except Exception as e:
            logger.warning(f"AI service not available: {e}")
            return False
    
    async def generate_response(self, message: str) -> dict:
        """Generate AI response with personality configuration"""
        
        # Try AI first
        if self.client:
            try:
                ai_response = await self._generate_ai_response(message)
                if ai_response:
                    return {
                        "response": ai_response,
                        "mode": "ai",
                        "model": self.model,
                        "personality": self.personality_config.get("identity", {}).get("name", "AI"),
                        "timestamp": datetime.now().isoformat()
                    }
            except Exception as e:
                logger.error(f"AI generation failed: {e}")
        
        # Fallback to echo mode with personality
        name = self.personality_config.get("identity", {}).get("name", "Assistant")
        return {
            "response": f"Echo from {name}: {message}",
            "mode": "echo",
            "model": "fallback",
            "personality": name,
            "timestamp": datetime.now().isoformat()
        }
    
    async def _generate_ai_response(self, message: str) -> Optional[str]:
        """Generate response using Ollama with personality"""
        try:
            system_prompt = self._get_system_prompt()
            
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.client.chat(
                    model=self.model,
                    messages=[
                        {
                            'role': 'system',
                            'content': system_prompt
                        },
                        {
                            'role': 'user',
                            'content': message
                        }
                    ]
                )
            )
            return response['message']['content']
        except Exception as e:
            logger.error(f"Ollama generation error: {e}")
            return None
    
    async def get_status(self) -> dict:
        """Get AI service status with personality info"""
        is_available = await self.is_available()
        
        status = {
            "ai_available": is_available,
            "model": self.model if is_available else "unavailable",
            "mode": "ai" if is_available else "echo",
            "ollama_url": self.ollama_url,
            "personality": {
                "name": self.personality_config.get("identity", {}).get("name", "Unknown"),
                "display_name": self.personality_config.get("identity", {}).get("display_name", "AI Assistant"),
                "config_loaded": self.personality_config is not None
            }
        }
        
        if is_available and self.client:
            try:
                models = await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: self.client.list()
                )
                status["available_models"] = [model['name'] for model in models.get('models', [])]
            except:
                pass
        
        return status

# Global AI service instance
ai_service = AIService()
"@
    
    Set-Content -Path "backend/services/ai_service.py" -Value $aiService
    Set-Content -Path "backend/services/__init__.py" -Value ""
    Write-Success "AI service module created with personality configuration"
}

function Update-MainApp {
    Write-Step "Updating main application with AI integration..."
    
    # Backup original
    Copy-Item "backend/api/main.py" "backend/api/main.py.backup"
    
    $updatedMain = @"
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
"@
    
    Set-Content -Path "backend/api/main.py" -Value $updatedMain
    Write-Success "Main application updated with AI integration"
}

function Create-AITests {
    Write-Step "Creating AI integration tests..."
    
    $aiTests = @"
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
"@
    
    Set-Content -Path "backend/tests/test_ai_integration.py" -Value $aiTests
    Write-Success "AI integration tests created"
}

function Update-RunScript {
    Write-Step "Updating run script with AI capabilities..."
    
    $updatedRunScript = @"
# run_backend.ps1 - Enhanced script to start the backend with AI integration
param(
    [switch]`$Test,
    [switch]`$CheckOllama,
    [switch]`$SetupOllama
)

if (`$CheckOllama) {
    Write-Host "🔍 Checking Ollama status..." -ForegroundColor Yellow
    try {
        `$response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5
        Write-Host "✅ Ollama is running!" -ForegroundColor Green
        Write-Host "Available models:" -ForegroundColor Cyan
        `$response.models | ForEach-Object { Write-Host "  - `$(`$_.name)" -ForegroundColor White }
    } catch {
        Write-Host "❌ Ollama not running or not accessible" -ForegroundColor Red
        Write-Host "💡 Start Ollama with: ollama serve" -ForegroundColor Yellow
        Write-Host "💡 Pull model with: ollama pull llama3.1:8b" -ForegroundColor Yellow
    }
    return
}

if (`$SetupOllama) {
    Write-Host "🚀 Setting up Ollama..." -ForegroundColor Yellow
    Write-Host "1. Starting Ollama service..." -ForegroundColor Cyan
    Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
    
    Start-Sleep -Seconds 3
    
    Write-Host "2. Pulling llama3.1:8b model (this may take a few minutes)..." -ForegroundColor Cyan
    & ollama pull llama3.1:8b
    
    Write-Host "✅ Ollama setup complete!" -ForegroundColor Green
    return
}

if (`$Test) {
    Write-Host "🧪 Running tests..." -ForegroundColor Yellow
    Set-Location backend
    python -m pytest tests/ -v
    Set-Location ..
} else {
    Write-Host "🤖 Starting Jarvis AI Backend with AI Integration..." -ForegroundColor Green
    Write-Host ""
    Write-Host "📍 API Documentation: http://localhost:8000/docs" -ForegroundColor Cyan
    Write-Host "🏥 Health Check: http://localhost:8000/api/health" -ForegroundColor Cyan
    Write-Host "💬 Chat Endpoint: http://localhost:8000/api/chat" -ForegroundColor Cyan
    Write-Host "🤖 AI Status: http://localhost:8000/api/ai/status" -ForegroundColor Cyan
    Write-Host "🧪 AI Test: http://localhost:8000/api/ai/test" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "💡 Check Ollama status with: .\run_backend.ps1 -CheckOllama" -ForegroundColor Yellow
    Write-Host "💡 Setup Ollama with: .\run_backend.ps1 -SetupOllama" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    Write-Host ""
    
    Set-Location backend
    python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
}
"@
    
    Set-Content -Path "run_backend.ps1" -Value $updatedRunScript
    Write-Success "Run script updated with AI capabilities"
}

function Update-Readme {
    Write-Step "Updating README with AI integration info..."
    
    $updatedReadme = @"
# Jarvis AI Assistant - Backend with AI Integration

FastAPI backend with Ollama integration for real AI responses.

## Features

- ✅ **FastAPI Backend** - RESTful API with auto-documentation
- 🤖 **Ollama Integration** - Local AI model responses
- 🔄 **Smart Fallback** - Echo mode when AI unavailable
- 🧪 **Comprehensive Testing** - Unit tests for all functionality
- 📊 **Status Monitoring** - Health checks and AI status
- 🎭 **Personality Configuration** - Customizable AI personality

## Quick Start

### 1. Install Dependencies
``````powershell
cd backend
pip install -r requirements.txt
``````

### 2. Setup Ollama (Optional but Recommended)
``````powershell
# Setup Ollama automatically
.\run_backend.ps1 -SetupOllama

# Or manually:
ollama serve                    # Start Ollama service
ollama pull llama3.1:8b        # Pull AI model
``````

### 3. Start the Server
``````powershell
# Start with helper script
.\run_backend.ps1

# Or manually
cd backend
python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
``````

### 4. Test the Integration
``````powershell
# Check Ollama status
.\run_backend.ps1 -CheckOllama

# Run all tests
.\run_backend.ps1 -Test
``````

## Personality Configuration

The AI personality can be customized by editing `jarvis_personality.json` in the project root:

``````json
{
  "identity": {
    "name": "Jarvis",
    "display_name": "J.A.R.V.I.S."
  },
  "personality": {
    "base_personality": "You are Jarvis, an AI assistant...",
    "tone": "professional yet friendly"
  }
}
``````

After modifying the configuration, restart the backend to apply changes.

## API Endpoints

### Core Endpoints
- `GET /` - Root endpoint with service info
- `GET /api/health` - Health check with AI status
- `POST /api/chat` - Chat with AI (or fallback to echo)
- `GET /api/status` - Detailed service status

### AI-Specific Endpoints
- `GET /api/ai/status` - AI service status and available models
- `GET /api/ai/test` - Test AI connectivity and response

## Chat Response Modes

### AI Mode (when Ollama available)
``````json
{
  "response": "Hello! I'm Jarvis, how can I assist you today?",
  "mode": "ai",
  "model": "llama3.1:8b",
  "timestamp": "2025-07-02T20:55:46"
}
``````

### Fallback Mode (when Ollama unavailable)
``````json
{
  "response": "Echo from Jarvis: Hello Jarvis!",
  "mode": "echo", 
  "model": "fallback",
  "timestamp": "2025-07-02T20:55:46"
}
``````

## Testing

``````powershell
# Test health check
Invoke-RestMethod -Uri http://localhost:8000/api/health

# Test chat (PowerShell)
`$body = @{content = "Hello Jarvis!"} | ConvertTo-Json
Invoke-RestMethod -Uri http://localhost:8000/api/chat -Method Post -Body `$body -ContentType "application/json"

# Test AI status
Invoke-RestMethod -Uri http://localhost:8000/api/ai/status
``````

## Project Structure

``````
jarvis/
├── jarvis_personality.json     # AI personality configuration
├── backend/
│   ├── api/
│   │   ├── main.py              # FastAPI app with AI integration
│   │   └── __init__.py
│   ├── services/
│   │   ├── ai_service.py        # Ollama integration service
│   │   └── __init__.py
│   ├── tests/
│   │   ├── test_main.py         # Basic API tests
│   │   ├── test_ai_integration.py # AI integration tests
│   │   └── __init__.py
│   └── requirements.txt         # Dependencies including Ollama
├── .env                         # Environment configuration
├── run_backend.ps1              # Enhanced helper script
└── README.md                   # This file
``````

## Troubleshooting

### Ollama Not Working?
1. Check if Ollama is running: `.\run_backend.ps1 -CheckOllama`
2. Start Ollama: `ollama serve`
3. Pull model: `ollama pull llama3.1:8b`

### Still Having Issues?
- Backend will work in echo mode even without Ollama
- Check logs in the terminal where you started the backend
- Visit http://localhost:8000/docs for interactive testing

## Next Steps

1. ✅ **Backend with AI** - Current phase
2. 🎨 **Add React Frontend** - Chat interface
3. 🗣️ **Voice Integration** - Speech-to-text and text-to-speech
4. ☁️ **Deploy to Azure** - Cloud hosting
"@
    
    Set-Content -Path "README.md" -Value $updatedReadme
    Write-Success "README updated with AI integration info"
}

# Main execution
Write-Host "🤖 Adding AI Integration to Jarvis Backend" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

# Add AI capabilities incrementally
Add-OllamaDependency
Create-PersonalityConfig
Create-AIService
Update-MainApp
Create-AITests
Update-RunScript

Write-Host ""
Write-Success "AI integration setup complete!"

if ($Install -or $All) {
    Write-Host ""
    if (Install-Dependencies) {
        Write-Success "Ready to test AI integration!"
    }
}

# Show comprehensive validation
Write-Host ""
Write-Host "🔍 Complete System Validation - Backend + AI Integration:" -ForegroundColor Cyan
Write-Host "-" * 60 -ForegroundColor Gray

$validationResults = @()

# Check directory structure
$requiredDirs = @("backend", "backend/api", "backend/services", "backend/tests")
foreach ($dir in $requiredDirs) {
    if (Test-Path $dir) {
        $validationResults += "✅ Directory: $dir"
    } else {
        $validationResults += "❌ Missing: $dir"
    }
}

# Check core backend files
$coreFiles = @(
    "backend/requirements.txt",
    "backend/api/main.py",
    "backend/api/__init__.py",
    "backend/tests/test_main.py",
    ".env"
)

foreach ($file in $coreFiles) {
    if (Test-Path $file) {
        $size = (Get-Item $file).Length
        $validationResults += "✅ Core File: $file ($size bytes)"
    } else {
        $validationResults += "❌ Missing Core: $file"
    }
}

# Check AI integration files
$aiFiles = @(
    "backend/services/ai_service.py",
    "backend/services/__init__.py",
    "backend/tests/test_ai_integration.py",
    "jarvis_personality.json"
)

foreach ($file in $aiFiles) {
    if (Test-Path $file) {
        $size = (Get-Item $file).Length
        $validationResults += "✅ AI File: $file ($size bytes)"
    } else {
        $validationResults += "❌ Missing AI: $file"
    }
}

# Check enhanced files (only run script, not README)
if (Test-Path "run_backend.ps1") {
    $content = Get-Content "run_backend.ps1" -Raw
    $size = (Get-Item "run_backend.ps1").Length
    if ($content -match "AI" -or $content -match "Ollama" -or $content -match "CheckOllama") {
        $validationResults += "✅ Enhanced: run_backend.ps1 ($size bytes) - AI integrated"
    } else {
        $validationResults += "⚠️  Basic: run_backend.ps1 ($size bytes) - may need AI enhancement"
    }
} else {
    $validationResults += "❌ Missing: run_backend.ps1"
}

# Check README (should exist from script 02, but not AI-enhanced yet)
if (Test-Path "README.md") {
    $size = (Get-Item "README.md").Length
    $content = Get-Content "README.md" -Raw
    if ($content -match "Personality Configuration") {
        $validationResults += "✅ Enhanced: README.md ($size bytes) - AI documented"
    } else {
        $validationResults += "✅ File: README.md ($size bytes) - from base setup"
    }
} else {
    $validationResults += "❌ Missing: README.md"
}

# Check Python dependencies
$originalLocation = Get-Location
try {
    Set-Location backend
    $pipList = pip list 2>$null
    
    # Core dependencies
    $corePackages = @("fastapi", "uvicorn", "pydantic")
    foreach ($package in $corePackages) {
        if ($pipList -match $package) {
            $validationResults += "✅ Dependency: $package installed"
        } else {
            $validationResults += "❌ Dependency: $package missing"
        }
    }
    
    # AI dependencies
    $aiPackages = @("ollama", "httpx")
    foreach ($package in $aiPackages) {
        if ($pipList -match $package) {
            $validationResults += "✅ AI Dependency: $package installed"
        } else {
            $validationResults += "❌ AI Dependency: $package missing"
        }
    }
    
    Set-Location $originalLocation
} catch {
    $validationResults += "⚠️  Could not verify Python packages"
    Set-Location $originalLocation -ErrorAction SilentlyContinue
}

# Check backend version and AI integration
if (Test-Path "backend/api/main.py") {
    $mainContent = Get-Content "backend/api/main.py" -Raw
    if ($mainContent -match "ai_service" -and $mainContent -match "version.*1\.1\.0") {
        $validationResults += "✅ Backend: AI-enhanced FastAPI (v1.1.0)"
    } elseif ($mainContent -match "version.*1\.0\.0") {
        $validationResults += "⚠️  Backend: Basic FastAPI (v1.0.0) - needs AI upgrade"
    } else {
        $validationResults += "❌ Backend: Version unclear or missing"
    }
}

# Check personality configuration
if (Test-Path "jarvis_personality.json") {
    try {
        $configContent = Get-Content "jarvis_personality.json" -Raw | ConvertFrom-Json
        $name = $configContent.identity.name
        $displayName = $configContent.identity.display_name
        $validationResults += "✅ Personality Config: $name ($displayName) ready"
    } catch {
        $validationResults += "⚠️  Personality Config: File exists but may be malformed"
    }
} else {
    $validationResults += "❌ Personality Config: Not found"
}

# Check Ollama service availability
$ollamaRunning = Test-OllamaRunning
if ($ollamaRunning) {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5
        $modelCount = $response.models.Count
        $validationResults += "✅ Ollama Service: Running with $modelCount models"
        
        # Check for recommended model
        $hasLlama = $response.models | Where-Object { $_.name -like "*llama*" }
        if ($hasLlama) {
            $modelName = $hasLlama[0].name
            $validationResults += "✅ AI Model: $modelName ready"
        } else {
            $validationResults += "⚠️  AI Model: No Llama model (run: ollama pull llama3.1:8b)"
        }
    } catch {
        $validationResults += "⚠️  Ollama Service: Running but could not get model info"
    }
} else {
    $validationResults += "❌ Ollama Service: Not running (start with: ollama serve)"
}

# Display results
foreach ($result in $validationResults) {
    Write-Host $result
}

# Summary with intelligent messaging
$successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
$warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
$failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
$totalChecks = $validationResults.Count

Write-Host ""
if ($failureCount -eq 0 -and $warningCount -eq 0) {
    Write-Host "🎉 Complete System Validation: $successCount/$totalChecks checks passed!" -ForegroundColor Green
    Write-Host "✅ Jarvis AI Backend fully operational with personality configuration" -ForegroundColor Green
} elseif ($failureCount -eq 0) {
    Write-Host "⚠️  System Validation: $successCount/$totalChecks ready, $warningCount minor issues" -ForegroundColor Yellow
    Write-Host "✅ Core system operational with personality support" -ForegroundColor Green
} elseif ($failureCount -eq 1 -and ($validationResults | Where-Object { $_ -like "*Ollama Service*Not running*" })) {
    Write-Host "⚠️  System Validation: $successCount/$totalChecks ready, Ollama optional" -ForegroundColor Yellow
    Write-Host "✅ Backend fully functional with personality configuration" -ForegroundColor Green
} else {
    Write-Host "❗ System Validation: $successCount/$totalChecks ready, $failureCount missing, $warningCount warnings" -ForegroundColor Red
    Write-Host "❌ Some system components need attention" -ForegroundColor Red
}

if ($Setup -or $All) {
    Write-Host ""
    Write-Step "Setting up Ollama..."
    Write-Host "💡 Run: .\run_backend.ps1 -SetupOllama" -ForegroundColor Yellow
}

if ($Test -or $All) {
    Write-Host ""
    Test-Integration
}

# Quick test instructions (always show if components exist)
if ((Test-Path "backend/services/ai_service.py") -and (Test-Path "jarvis_personality.json") -and ($successCount -gt 8)) {
    Write-Host ""
    Write-Host "🚀 Personality Configuration Ready - Quick Start:" -ForegroundColor Cyan
    Write-Host "# Start enhanced backend:" -ForegroundColor Gray
    Write-Host ".\run_backend.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "# Test personality configuration:" -ForegroundColor Gray
    Write-Host "`$body = @{content = 'Hello, who are you?'} | ConvertTo-Json" -ForegroundColor White
    Write-Host "Invoke-RestMethod -Uri http://localhost:8000/api/chat -Method Post -Body `$body -ContentType 'application/json'" -ForegroundColor White
    Write-Host ""
    Write-Host "# Customize personality:" -ForegroundColor Gray
    Write-Host "# 1. Edit jarvis_personality.json" -ForegroundColor White
    Write-Host "# 2. Restart backend" -ForegroundColor White
    Write-Host "# 3. Test changes" -ForegroundColor White
}

if (-not ($Install -or $Setup -or $Test -or $All)) {
    Write-Host ""
    Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
    Write-Host "1. .\03-OllamaIntegration.ps1 -Install     # Install AI dependencies" -ForegroundColor White
    Write-Host "2. .\03-OllamaIntegration.ps1 -Test        # Test AI integration" -ForegroundColor White
    Write-Host ""
    Write-Host "Or run everything:" -ForegroundColor Yellow
    Write-Host ".\03-OllamaIntegration.ps1 -All" -ForegroundColor White
    Write-Host ""
    Write-Host "💡 Personality configuration now available in jarvis_personality.json" -ForegroundColor Cyan
    Write-Host "🚀 Ready for script 04 to setup Ollama and test personality" -ForegroundColor Cyan
}