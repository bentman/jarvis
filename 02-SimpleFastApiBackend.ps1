# 02-SimpleFastApiBackend.ps1 - Create minimal working FastAPI backend for Jarvis AI
# Creates a simple, functional backend that we can test immediately

param(
    [switch]$Install,
    [switch]$Run,
    [switch]$All
)

function Write-Step($message) {
    Write-Host "🔧 $message" -ForegroundColor Green
}

function Write-Success($message) {
    Write-Host "✅ $message" -ForegroundColor Green
}

function Create-BackendStructure {
    Write-Step "Creating simple backend structure..."
    
    # Create minimal directory structure
    $directories = @(
        "backend",
        "backend/api",
        "backend/tests"
    )
    
    $created = 0
    $skipped = 0
    
    foreach ($dir in $directories) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "  Created: $dir" -ForegroundColor DarkGreen
            $created++
        } else {
            Write-Host "  Exists: $dir" -ForegroundColor Gray
            $skipped++
        }
    }
    
    if ($created -gt 0) {
        Write-Success "Created $created directories"
    }
    if ($skipped -gt 0) {
        Write-Host "Skipped $skipped existing directories" -ForegroundColor Gray
    }
}

function Create-Requirements {
    Write-Step "Creating requirements.txt..."
    
    if (Test-Path "backend/requirements.txt") {
        $existing = Get-Content "backend/requirements.txt" -Raw
        if ($existing -match "fastapi==0.104.1" -and $existing -match "uvicorn") {
            Write-Success "Requirements.txt already exists and is current - skipping"
            return
        } else {
            Write-Host "Updating requirements.txt..." -ForegroundColor Yellow
        }
    }
    
    $requirements = @"
# Core FastAPI dependencies
fastapi==0.104.1
uvicorn[standard]==0.24.0

# Basic utilities
python-dotenv==1.0.0
pydantic==2.5.0
pydantic-settings==2.1.0

# Development tools
pytest==7.4.3
httpx==0.25.2
"@
    
    Set-Content -Path "backend/requirements.txt" -Value $requirements
    Write-Success "Requirements.txt created"
}

function Create-MainApp {
    Write-Step "Creating main FastAPI application..."
    
    if (Test-Path "backend/api/main.py") {
        $existing = Get-Content "backend/api/main.py" -Raw
        if ($existing -match "Jarvis AI Assistant" -and $existing -match "FastAPI") {
            Write-Success "Main application already exists and is current - skipping"
            return
        } else {
            Write-Host "Updating main application..." -ForegroundColor Yellow
        }
    }
    
    $mainApp = @"
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Create FastAPI app
app = FastAPI(
    title="Jarvis AI Assistant",
    description="Simple AI Assistant Backend",
    version="1.0.0"
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
    timestamp: str

# Root endpoint
@app.get("/")
async def root():
    return {
        "message": "Jarvis AI Assistant Backend",
        "status": "running",
        "version": "1.0.0",
        "docs": "/docs"
    }

# Health check endpoint
@app.get("/api/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "jarvis-backend",
        "version": "1.0.0",
        "timestamp": datetime.now().isoformat()
    }

# Simple chat endpoint (echo for now)
@app.post("/api/chat", response_model=ChatResponse)
async def chat(message: ChatMessage):
    # For now, just echo the message back
    response = f"Echo: {message.content}"
    
    return ChatResponse(
        response=response,
        timestamp=datetime.now().isoformat()
    )

# Status endpoint
@app.get("/api/status")
async def get_status():
    return {
        "backend": "running",
        "ai_model": "echo (test mode)",
        "features": {
            "chat": True,
            "health_check": True,
            "echo_mode": True
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
"@
    
    Set-Content -Path "backend/api/main.py" -Value $mainApp
    Set-Content -Path "backend/api/__init__.py" -Value ""
    Write-Success "Main FastAPI application created"
}

function Create-EnvFile {
    Write-Step "Creating environment configuration..."
    
    $envContent = @"
# Jarvis AI Assistant - Environment Configuration

# Application Settings
ENVIRONMENT=development
DEBUG=true
LOG_LEVEL=DEBUG

# API Configuration
API_HOST=0.0.0.0
API_PORT=8000

# Future AI Integration (for later phases)
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=llama3.1:8b

# API Keys (add when ready)
OPENAI_API_KEY=your_openai_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here

# Security
SECRET_KEY=dev_secret_key_$(Get-Random)
"@
    
    Set-Content -Path ".env" -Value $envContent
    Write-Success "Environment file created"
}

function Create-Tests {
    Write-Step "Creating basic tests..."
    
    $testMain = @"
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
"@
    
    Set-Content -Path "backend/tests/test_main.py" -Value $testMain
    Set-Content -Path "backend/tests/__init__.py" -Value ""
    Write-Success "Basic tests created"
}

function Create-RunScript {
    Write-Step "Creating run script..."
    
    $runScript = @"
# run_backend.ps1 - Simple script to start the backend
param([switch]`$Test)

if (`$Test) {
    Write-Host "🧪 Running tests..." -ForegroundColor Yellow
    Set-Location backend
    python -m pytest tests/ -v
    Set-Location ..
} else {
    Write-Host "🚀 Starting Jarvis AI Backend..." -ForegroundColor Green
    Write-Host "📍 API Documentation: http://localhost:8000/docs" -ForegroundColor Cyan
    Write-Host "🏥 Health Check: http://localhost:8000/api/health" -ForegroundColor Cyan
    Write-Host "💬 Chat Test: http://localhost:8000/api/chat" -ForegroundColor Cyan
    Write-Host ""
    Set-Location backend
    python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
}
"@
    
    Set-Content -Path "run_backend.ps1" -Value $runScript
    Write-Success "Run script created"
}

function Create-Readme {
    Write-Step "Creating README..."
    
    $readme = @"
# Jarvis AI Assistant - Simple Backend

A minimal FastAPI backend for the Jarvis AI Assistant project.

## Quick Start

### 1. Install Dependencies
``````powershell
cd backend
pip install -r requirements.txt
``````

### 2. Start the Server
``````powershell
# From root directory
.\run_backend.ps1

# Or manually
cd backend
python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
``````

### 3. Test the API
- **API Documentation**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/api/health
- **Root**: http://localhost:8000/

### 4. Run Tests
``````powershell
.\run_backend.ps1 -Test
``````

## API Endpoints

- `GET /` - Root endpoint with basic info
- `GET /api/health` - Health check
- `POST /api/chat` - Chat endpoint (echo mode)
- `GET /api/status` - Service status

## Next Steps

1. ✅ **Get basic backend running**
2. 🔄 **Add simple frontend**
3. 🤖 **Integrate Ollama for AI responses**
4. 🗣️ **Add voice capabilities**
5. ☁️ **Deploy to Azure**

## Project Structure

``````
jarvis/
├── backend/
│   ├── api/
│   │   ├── main.py          # FastAPI application
│   │   └── __init__.py
│   ├── tests/
│   │   ├── test_main.py     # Basic tests
│   │   └── __init__.py
│   └── requirements.txt     # Python dependencies
├── .env                     # Environment configuration
├── run_backend.ps1          # Helper script
└── README.md               # This file
``````
"@
    
    Set-Content -Path "README.md" -Value $readme
    Write-Success "README created"
}

function Install-Dependencies {
    Write-Step "Installing Python dependencies..."
    
    # Check if already installed
    $originalLocation = Get-Location
    Set-Location backend
    try {
        $pipList = pip list 2>$null
        $fastapiInstalled = $pipList -match "fastapi"
        $uvicornInstalled = $pipList -match "uvicorn"
        
        if ($fastapiInstalled -and $uvicornInstalled) {
            Write-Success "Dependencies already installed - skipping"
            Set-Location $originalLocation
            return $true
        }
        
        Write-Host "Installing missing dependencies..." -ForegroundColor Yellow
        pip install -r requirements.txt
        Write-Success "Dependencies installed successfully"
    } catch {
        Write-Host "❌ Failed to install dependencies: $_" -ForegroundColor Red
        return $false
    } finally {
        Set-Location $originalLocation
    }
    return $true
}

function Start-Backend {
    Write-Step "Starting FastAPI backend..."
    
    # Verify we're in the right directory and backend exists
    if (!(Test-Path "backend/api/main.py")) {
        Write-Host "❌ Cannot find backend/api/main.py - make sure you're in the right directory" -ForegroundColor Red
        Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "🚀 Starting Jarvis AI Backend..." -ForegroundColor Green
    Write-Host "📍 API Documentation: http://localhost:8000/docs" -ForegroundColor Cyan
    Write-Host "🏥 Health Check: http://localhost:8000/api/health" -ForegroundColor Cyan
    Write-Host "💬 Chat Test: POST to http://localhost:8000/api/chat" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  The server will start and block this terminal." -ForegroundColor Yellow
    Write-Host "📋 Once running, open a NEW terminal to test:" -ForegroundColor Yellow
    Write-Host "   Invoke-RestMethod -Uri http://localhost:8000/api/health" -ForegroundColor Gray
    Write-Host "   `$body = @{content = 'Hello!'} | ConvertTo-Json" -ForegroundColor Gray
    Write-Host "   Invoke-RestMethod -Uri http://localhost:8000/api/chat -Method Post -Body `$body -ContentType 'application/json'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "🛑 Press Ctrl+C in THIS terminal to stop the server" -ForegroundColor Red
    Write-Host "📖 Visit http://localhost:8000/docs for interactive testing" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Starting server in 3 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    Write-Host ""
    
    $originalLocation = Get-Location
    try {
        Set-Location backend
        python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
    } finally {
        Set-Location $originalLocation
    }
}

# Main execution
Write-Host "🤖 Creating Simple FastAPI Backend for Jarvis AI" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

# Create structure and files
Create-BackendStructure
Create-Requirements
Create-MainApp
Create-EnvFile
Create-Tests
Create-RunScript
Create-Readme

Write-Host ""
Write-Success "Simple FastAPI backend setup complete!"

if ($Install -or $All) {
    Write-Host ""
    if (Install-Dependencies) {
        Write-Success "Ready to run!"
    }
}

# Always show validation regardless of parameters
Write-Host ""
Write-Host "🔍 Validation - Checking Current State:" -ForegroundColor Cyan
Write-Host "-" * 50 -ForegroundColor Gray

$validationResults = @()

# Check directories
$requiredDirs = @("backend", "backend/api", "backend/tests")
foreach ($dir in $requiredDirs) {
    if (Test-Path $dir) {
        $validationResults += "✅ Directory: $dir"
    } else {
        $validationResults += "❌ Missing: $dir"
    }
}

# Check files
$requiredFiles = @(
    "backend/requirements.txt",
    "backend/api/main.py", 
    "backend/api/__init__.py",
    "backend/tests/test_main.py",
    "backend/tests/__init__.py",
    ".env",
    "run_backend.ps1",
    "README.md"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        $size = (Get-Item $file).Length
        $validationResults += "✅ File: $file ($size bytes)"
    } else {
        $validationResults += "❌ Missing: $file"
    }
}

# Check Python dependencies
try {
    $originalLocation = Get-Location
    Set-Location backend
    $pipList = pip list 2>$null
    if ($pipList -match "fastapi") {
        $validationResults += "✅ FastAPI installed"
    } else {
        $validationResults += "❌ FastAPI not installed"
    }
    if ($pipList -match "uvicorn") {
        $validationResults += "✅ Uvicorn installed"
    } else {
        $validationResults += "❌ Uvicorn not installed"
    }
    Set-Location $originalLocation
} catch {
    $validationResults += "⚠️  Could not verify Python packages"
    Set-Location $originalLocation -ErrorAction SilentlyContinue
}

# Display results
foreach ($result in $validationResults) {
    Write-Host $result
}

# Summary
$successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
$totalChecks = $validationResults.Count
$failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count

Write-Host ""
if ($failureCount -eq 0) {
    Write-Host "🎉 Validation Complete: $successCount/$totalChecks checks passed!" -ForegroundColor Green
    Write-Host "✅ Simple FastAPI Backend ready for use" -ForegroundColor Green
} else {
    Write-Host "⚠️  Validation Complete: $successCount/$totalChecks checks passed, $failureCount failed" -ForegroundColor Yellow
    Write-Host "❗ Some components may be missing - review output above" -ForegroundColor Red
}

if ($Run -or $All) {
    Write-Host ""
    Write-Host "🎯 Starting Backend Server:" -ForegroundColor Yellow
    Write-Host "This will start the server and block this terminal." -ForegroundColor Gray
    Write-Host "After startup completes, use a NEW terminal window for testing." -ForegroundColor Gray
    Write-Host ""
    $confirm = Read-Host "Ready to start the server? (Y/n)"
    if ($confirm -eq "" -or $confirm -eq "y" -or $confirm -eq "Y") {
        Start-Backend
    } else {
        Write-Host "✅ Server start cancelled. Run manually with: .\run_backend.ps1" -ForegroundColor Green
    }
}

if (-not ($Install -or $Run -or $All)) {
    Write-Host ""
    Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
    Write-Host "1. .\02-SimpleFastApiBackend.ps1 -Install    # Install dependencies" -ForegroundColor White
    Write-Host "2. .\02-SimpleFastApiBackend.ps1 -Run        # Start the server" -ForegroundColor White
    Write-Host "3. Visit: http://localhost:8000/docs         # Test the API" -ForegroundColor White
    Write-Host ""
    Write-Host "Or run everything at once:" -ForegroundColor Yellow
    Write-Host ".\02-SimpleFastApiBackend.ps1 -All" -ForegroundColor White
}

# Quick test instructions (always show if components exist)
if ((Test-Path "backend/api/main.py") -and ($Install -or $All -or (pip list 2>$null | Select-String "fastapi"))) {
    Write-Host ""
    Write-Host "🚀 Quick Test Commands:" -ForegroundColor Cyan
    Write-Host "# Test the backend (run in another terminal):" -ForegroundColor Gray
    Write-Host "Invoke-RestMethod -Uri http://localhost:8000/api/health" -ForegroundColor White
    Write-Host "`$body = @{content = 'Hello!'} | ConvertTo-Json" -ForegroundColor White
    Write-Host "Invoke-RestMethod -Uri http://localhost:8000/api/chat -Method Post -Body `$body -ContentType 'application/json'" -ForegroundColor White
}