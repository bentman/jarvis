# 03-IntegrateOllama.ps1 - AI integration into FastAPI backend
# Purpose: Add Ollama-based AIService, personality config, and tests
# Last edit: 2025-07-11 - Aligned to J.A.R.V.I.S. standards
param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1
$scriptVersion = "4.2.2"
$scriptPrefix = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$projectRoot = Get-Location
$logsDir = Join-Path $projectRoot "logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptFile = Join-Path $logsDir "$scriptPrefix-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "$scriptPrefix-log-$timestamp.txt"
New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile
Write-Log -Message "=== $($MyInvocation.MyCommand.Name) v$scriptVersion ===" -Level INFO -LogFile $logFile

# Default to full Run if no switch provided
if (-not ($Install -or $Configure -or $Test -or $Run)) {
    $Run = $true
}

$setupResults = @()
Write-SystemInfo -ScriptName $scriptPrefix -Version $scriptVersion -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Install   = $Install
    Configure = $Configure
    Test      = $Test
    Run       = $Run
}

# Setup logging
$projectRoot = Get-Location
$logsDir = Join-Path $projectRoot "logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptFile = Join-Path $logsDir "03-ai-integration-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "03-ai-integration-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile

# Test if backend exists
function Test-BackendExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    $exists = (Test-Path "backend/api/main.py") -and (Test-Path "backend/requirements.txt")
    if (-not $exists) {
        Write-Log -Message "Backend not found. Please run 02-FastApiBackend.ps1 first." -Level "ERROR" -LogFile $LogFile
    }
    return $exists
}

# Add Ollama dependency to backend
function Add-OllamaDependency {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Adding Ollama client to backend requirements..." -Level "INFO" -LogFile $LogFile
    $requirementsPath = "backend/requirements.txt"
    if (-not (Test-Path $requirementsPath)) {
        Write-Log -Message "Backend requirements.txt not found - run 02-FastApiBackend.ps1 first" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    $requirements = Get-Content $requirementsPath
    if ($requirements -notcontains "ollama>=0.4.5") {
        $requirements += ""
        $requirements += "# AI Integration"
        $requirements += "ollama>=0.4.5"
        try {
            Set-Content -Path $requirementsPath -Value $requirements -ErrorAction Stop
            Write-Log -Message "Added Ollama dependency to requirements.txt" -Level "SUCCESS" -LogFile $LogFile
        }
        catch {
            Write-Log -Message "Failed to update requirements.txt: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
            return $false
        }
    }
    else {
        Write-Log -Message "Ollama dependency already present in requirements.txt" -Level "SUCCESS" -LogFile $LogFile
    }
    return $true
}

# Create personality configuration
function New-PersonalityConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating personality configuration..." -Level "INFO" -LogFile $LogFile
    $personalityPath = "jarvis_personality.json"
    if (Test-Path $personalityPath) {
        Write-Log -Message "Personality config already exists - skipping creation" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    
    $personalityConfig = @"
{
  "_comment_purpose": "Jarvis AI Assistant Personality Configuration",
  "identity": {
    "name": "Jarvis",
    "display_name": "J.A.R.V.I.S.",
    "full_name": "Just A Rather Very Intelligent System",
    "role": "Personal AI Assistant"
  },
  "personality": {
    "base_personality": "You are Jarvis, an AI assistant inspired by Tony Stark's AI. Be helpful, intelligent, and slightly witty.",
    "tone": "formal, polished, with calm restraint and dry elegance yet friendly",
    "humor_level": "occasional dry wit or gentle sarcasm — never flippant",
    "formality": "address user respectfully; professional but not overly formal",
    "confidence": "confident but not arrogant; self-assured and proactive"
  },
  "behavior": {
    "proactiveness": "anticipate needs, flag potential issues, suggest improvements",
    "problem_solving": "methodical and tech-savvy, analytical in diagnostics",
    "error_handling": "calmly acknowledge limitations, offer alternatives with wit",
    "response_style": "concise yet thorough"
  },
  "capabilities": {
    "primary_functions": [
      "Provide precise, tech-informed answers",
      "Manage diagnostics and system operations",
      "Support strategic planning with real-time analysis",
      "Assist with planning and organization",
      "Provide technical guidance"
    ],
    "specialties": [
      "Technology and programming",
      "Data analysis and research",
      "Creative problem solving",
      "Process optimization"
    ]
  },
  "interaction_style": {
    "greeting_style": "confident, polite, quietly charming",
    "farewell_style": "professional and helpful",
    "clarification_approach": "ask focused questions; respectful follow-ups",
    "explanation_method": "break down complex topics into understandable parts"
  },
  "advanced_settings": {
    "creativity_level": "balanced—innovative ideas grounded in practicality",
    "technical_depth": "adjust explanation detail based on user expertise",
    "initiative_level": "high - monitor context and offer preemptive assistance",
    "emotional_intelligence": "formal empathy; supportive and loyal"
  }
}
"@
    
    try {
        Set-Content -Path $personalityPath -Value $personalityConfig -ErrorAction Stop
        Write-Log -Message "Personality configuration created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create personality configuration: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Create AI service module
function New-AIService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating AI service module..." -Level "INFO" -LogFile $LogFile
    New-DirectoryStructure -Directories @("backend/services") -LogFile $LogFile
    $aiServicePath = "backend/services/ai_service.py"
    
    if (Test-Path $aiServicePath) {
        $existing = Get-Content $aiServicePath -Raw
        if ($existing -match "ollama" -and $existing -match "AIService" -and $existing -match "os.getenv") {
            Write-Log -Message "AI service module already exists and is current" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
    }
    
    $aiService = @"
import ollama
import asyncio
import json
import os
from typing import Optional
import logging
import httpx
from datetime import datetime

logger = logging.getLogger(__name__)

class AIService:
    def __init__(self, model: str = os.getenv("OLLAMA_MODEL", "phi3:mini"), ollama_url: str = os.getenv("OLLAMA_URL", "http://localhost:11434")):
        self.model = self._validate_model(model, ollama_url)
        self.ollama_url = ollama_url
        self.client = None
        self.personality_config = self._load_personality_config()
        self._initialize_client()
    
    def _validate_model(self, model: str, ollama_url: str) -> str:
        try:
            response = httpx.get(f"{ollama_url}/api/tags", timeout=5)
            if response.status_code == 200:
                available_models = [m['name'] for m in response.json().get('models', [])]
                if model in available_models:
                    logger.info(f"Validated model: {model}")
                    return model
                logger.warning(f"Model {model} not found, defaulting to phi3:mini")
                return "phi3:mini"
            logger.warning(f"Ollama API not available at {ollama_url}, defaulting to phi3:mini")
            return "phi3:mini"
        except Exception as e:
            logger.warning(f"Failed to validate model: {e}, defaulting to phi3:mini")
            return "phi3:mini"
    
    def _load_personality_config(self):
        config_paths = [
            "../../jarvis_personality.json",
            "../jarvis_personality.json",
            "jarvis_personality.json"
        ]
        for config_path in config_paths:
            try:
                if os.path.exists(config_path):
                    with open(config_path, 'r', encoding='utf-8') as f:
                        config = json.load(f)
                        logger.info(f"Loaded personality config from {config_path}")
                        return config
            except Exception as e:
                logger.warning(f"Failed to load personality config from {config_path}: {e}")
        logger.warning("Personality config not found, using defaults")
        return self._get_default_personality()
    
    def _get_default_personality(self):
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
        config = self.personality_config
        system_prompt = config.get("personality", {}).get("base_personality", "You are Jarvis, an AI assistant. Be helpful and intelligent.")
        personality = config.get("personality", {})
        for attr in ["tone", "humor_level", "confidence"]:
            if personality.get(attr):
                system_prompt += f" Your {attr.replace('_', ' ')} should be {personality[attr]}."
        behavior = config.get("behavior", {})
        for attr in ["response_style", "problem_solving"]:
            if behavior.get(attr):
                system_prompt += f" Keep {attr.replace('_', ' ')} {behavior[attr]}."
        return system_prompt
    
    def _initialize_client(self):
        try:
            response = httpx.get(f"{self.ollama_url}/api/tags", timeout=5)
            if response.status_code == 200:
                self.client = ollama.Client(host=self.ollama_url)
                logger.info(f"Ollama client initialized, model: {self.model}")
            else:
                logger.warning(f"Ollama not available at {self.ollama_url}")
        except Exception as e:
            logger.warning(f"Failed to initialize Ollama client: {e}")
    
    async def is_available(self) -> bool:
        if not self.client:
            return False
        try:
            await asyncio.get_event_loop().run_in_executor(None, lambda: self.client.list())
            return True
        except Exception as e:
            logger.warning(f"AI service not available: {e}")
            return False
    
    async def generate_response(self, message: str) -> dict:
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
        name = self.personality_config.get("identity", {}).get("name", "Assistant")
        return {
            "response": f"Echo from {name}: {message}",
            "mode": "echo",
            "model": "fallback",
            "personality": name,
            "timestamp": datetime.now().isoformat()
        }
    
    async def _generate_ai_response(self, message: str) -> Optional[str]:
        try:
            system_prompt = self._get_system_prompt()
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.client.chat(
                    model=self.model,
                    messages=[
                        {'role': 'system', 'content': system_prompt},
                        {'role': 'user', 'content': message}
                    ]
                )
            )
            return response['message']['content']
        except Exception as e:
            logger.error(f"Ollama generation error: {e}")
            return None
    
    async def get_status(self) -> dict:
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
                models = await asyncio.get_event_loop().run_in_executor(None, lambda: self.client.list())
                status["available_models"] = [model['name'] for model in models.get('models', [])]
            except:
                pass
        return status

ai_service = AIService()
"@
    
    try {
        Set-Content -Path $aiServicePath -Value $aiService -ErrorAction Stop
        Set-Content -Path "backend/services/__init__.py" -Value "" -ErrorAction Stop
        Write-Log -Message "AI service module created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create AI service module: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Update main FastAPI application
function Update-FastAPIApplication {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Updating main application with AI integration..." -Level "INFO" -LogFile $LogFile
    $mainPath = "backend/api/main.py"
    if (-not (Test-Path $mainPath)) {
        Write-Log -Message "Main application not found - run 02-FastApiBackend.ps1 first" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    $existing = Get-Content $mainPath -Raw
    if ($existing -match "ai_service" -and $existing -match "1\.1\.0") {
        Write-Log -Message "Main application already has AI integration" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    
    Copy-Item $mainPath "$mainPath.backup" -ErrorAction SilentlyContinue
    $updatedMain = @"
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
import os
from dotenv import load_dotenv
import logging
from services.ai_service import ai_service

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Jarvis AI Assistant",
    description="AI Assistant Backend with Ollama Integration",
    version="1.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatMessage(BaseModel):
    content: str

class ChatResponse(BaseModel):
    response: str
    mode: str
    model: str
    timestamp: str

@app.get("/")
async def root():
    return {
        "message": "Jarvis AI Assistant Backend",
        "status": "running",
        "version": "1.1.0",
        "features": ["chat", "ai_integration", "fallback_mode"],
        "docs": "/docs"
    }

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

@app.post("/api/chat", response_model=ChatResponse)
async def chat(message: ChatMessage):
    logger.info(f"Chat request: {message.content}")
    result = await ai_service.generate_response(message.content)
    return ChatResponse(
        response=result["response"],
        mode=result["mode"],
        model=result["model"],
        timestamp=result["timestamp"]
    )

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

@app.get("/api/ai/status")
async def ai_status():
    return await ai_service.get_status()

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
    return {
        "ai_available": False,
        "test_successful": False,
        "message": "AI service not available - using fallback mode"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
"@
    
    try {
        Set-Content -Path $mainPath -Value $updatedMain -ErrorAction Stop
        Write-Log -Message "Main application updated with AI integration" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to update main application: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Create AI integration tests
function New-AIIntegrationTests {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating AI integration tests..." -Level "INFO" -LogFile $LogFile
    $testPath = "backend/tests/test_ai_integration.py"
    if (Test-Path $testPath) {
        Write-Log -Message "AI integration tests already exist" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    
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
    assert "mode" in data
    assert "model" in data
    assert "timestamp" in data

def test_ai_status_endpoint():
    response = client.get("/api/ai/status")
    assert response.status_code == 200
    data = response.json()
    assert "ai_available" in data
    assert "mode" in data
    assert "personality" in data

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
    result = await ai_service.generate_response("Test message")
    assert "response" in result
    assert "mode" in result
"@
    
    try {
        Set-Content -Path $testPath -Value $aiTests -ErrorAction Stop
        Write-Log -Message "AI integration tests created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create AI integration tests: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Install AI dependencies
function Install-AIDependencies {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Installing AI integration dependencies..." -Level "INFO" -LogFile $LogFile
    if (Test-PythonPackageInstalled -PackageName "ollama" -LogFile $LogFile) {
        Write-Log -Message "Ollama Python package already installed" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    
    if (Install-PythonPackage -PackageName "ollama>=0.4.5" -LogFile $LogFile) {
        Write-Log -Message "Ollama Python package installed successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    Write-Log -Message "Failed to install Ollama Python package" -Level "ERROR" -LogFile $LogFile
    return $false
}

# Run AI integration tests
function Invoke-AIIntegrationTests {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Running AI integration tests..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-Path "backend/tests/test_ai_integration.py")) {
        Write-Log -Message "AI integration test files not found" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    try {
        Push-Location backend
        $pythonCmd = Get-PythonCommand -LogFile $LogFile
        if (-not $pythonCmd) {
            Write-Log -Message "No Python command found for running tests" -Level "ERROR" -LogFile $LogFile
            return $false
        }
        
        Write-Log -Message "Executing AI integration tests..." -Level "INFO" -LogFile $LogFile
        & $pythonCmd -m pytest tests/test_ai_integration.py -v
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Run AI integration tests passed" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Some AI integration tests failed (exit code: $LASTEXITCODE)" -Level "WARN" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Exception during AI test execution: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    finally {
        Pop-Location
    }
}

# Validate AI integration setup
function Test-AIIntegrationSetup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Validating AI integration setup..." -Level "INFO" -LogFile $LogFile
    $validationResults = @()
    
    $requiredFiles = @(
        "backend/requirements.txt",
        "backend/api/main.py",
        "backend/services/ai_service.py",
        "backend/services/__init__.py",
        "backend/tests/test_ai_integration.py",
        "jarvis_personality.json"
    )
    
    foreach ($file in $requiredFiles) {
        if (Test-Path $file) {
            $size = (Get-Item $file).Length
            $validationResults += "✅ File: $file ($size bytes)"
        }
        else {
            $validationResults += "❌ Missing: $file"
        }
    }
    
    $pythonPackages = @("ollama", "fastapi", "uvicorn")
    foreach ($package in $pythonPackages) {
        $status = Test-PythonPackageInstalled -PackageName $package -LogFile $LogFile
        $validationResults += "$($status ? '✅' : '❌') Python Package: $package"
    }
    
    if (Test-Path "backend/api/main.py") {
        $mainContent = Get-Content "backend/api/main.py" -Raw
        $validationResults += ($mainContent -match "ai_service" -and $mainContent -match "1\.1\.0") ? 
        "✅ Backend: AI-enhanced FastAPI (v1.1.0)" : 
        "❌ Backend: Missing AI integration"
    }
    
    if (Test-Path "jarvis_personality.json") {
        try {
            $configContent = Get-Content "jarvis_personality.json" -Raw | ConvertFrom-Json
            $name = $configContent.identity.name
            $displayName = $configContent.identity.display_name
            $validationResults += "✅ Personality Config: $name ($displayName)"
        }
        catch {
            $validationResults += "⚠️  Personality Config: File exists but may be malformed"
        }
    }
    
    $envValid = Test-EnvironmentConfig -LogFile $LogFile
    $validationResults += $envValid ? "✅ Environment Config: Valid" : "❌ Environment Config: Invalid or missing OLLAMA_MODEL"
    
    Write-Log -Message "=== AI INTEGRATION VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $validationResults) {
        Write-Log -Message $result -Level ($result -like "✅*" ? "SUCCESS" : ($result -like "⚠️*" ? "WARN" : "ERROR")) -LogFile $LogFile
    }
    
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    Write-Log -Message "AI Integration: $successCount/$($validationResults.Count) passed, $failureCount failed, $warningCount warnings" -Level ($failureCount -eq 0 ? "SUCCESS" : "ERROR") -LogFile $LogFile
    
    return $failureCount -eq 0
}

# Main execution
Write-Log -Message "JARVIS AI Integration Setup (v4.1) Starting..." -Level "SUCCESS" -LogFile $logFile
Write-SystemInfo -ScriptName "03-AIIntegration.ps1" -Version "4.1" -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Install   = $Install
    Test      = $Test
    Configure = $Configure
    Run       = $Run
}

if (-not (Test-BackendExists -LogFile $logFile)) {
    Stop-Transcript
    exit 1
}

$setupResults = @()
Write-Log -Message "Setting up AI integration components..." -Level "INFO" -LogFile $logFile
$setupResults += @{Name = "Environment Config"; Success = (Test-EnvironmentConfig -LogFile $logFile) }
$setupResults += @{Name = "Ollama Dependency"; Success = (Add-OllamaDependency -LogFile $logFile) }
$setupResults += @{Name = "Personality Config"; Success = (New-PersonalityConfig -LogFile $logFile) }
$setupResults += @{Name = "AI Service Module"; Success = (New-AIService -LogFile $logFile) }
$setupResults += @{Name = "FastAPI Enhancement"; Success = (Update-FastAPIApplication -LogFile $logFile) }
$setupResults += @{Name = "AI Integration Tests"; Success = (New-AIIntegrationTests -LogFile $logFile) }

if ($Install -or $Run) {
    Write-Log -Message "Installing AI dependencies..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "AI Dependencies"; Success = (Install-AIDependencies -LogFile $logFile) }
}
elseif (-not (Test-PythonPackageInstalled -PackageName "ollama" -LogFile $logFile)) {
    Write-Log -Message "Ollama Python package missing - installing automatically..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "Ollama Package (Auto)"; Success = (Install-AIDependencies -LogFile $logFile) }
}

if ($Configure -or $Run) {
    Write-Log -Message "Validating environment configuration..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "Environment Update"; Success = (Test-EnvironmentConfig -LogFile $logFile) }
}

if ($Test -or $Run) {
    Write-Log -Message "Running AI integration tests..." -Level "INFO" -LogFile $logFile
    if (Test-PythonPackageInstalled -PackageName "ollama" -LogFile $logFile) {
        $setupResults += @{Name = "AI Tests"; Success = (Invoke-AIIntegrationTests -LogFile $logFile) }
    }
    else {
        Write-Log -Message "Skipping tests - dependencies not installed (use -Install flag)" -Level "WARN" -LogFile $logFile
    }
}

Write-Log -Message "=== SETUP SUMMARY ===" -Level "INFO" -LogFile $logFile
$successfulSetups = ($setupResults | Where-Object { $_.Success }).Count
$failedSetups = ($setupResults | Where-Object { -not $_.Success }).Count
foreach ($result in $setupResults) {
    Write-Log -Message "$($result.Name) - $($result.Success ? 'SUCCESS' : 'FAILED')" -Level ($result.Success ? "SUCCESS" : "ERROR") -LogFile $logFile
}
Write-Log -Message "Setup Results: $successfulSetups successful, $failedSetups failed" -Level "INFO" -LogFile $logFile

Test-AIIntegrationSetup -LogFile $logFile | Out-Null

if (-not ($Install -or $Test -or $Configure -or $Run)) {
    Write-Log -Message "=== NEXT STEPS ===" -Level "INFO" -LogFile $logFile
    Write-Log -Message "1. .\03-AIIntegration.ps1 -Configure   # Validate environment" -Level "INFO" -LogFile $logFile
    Write-Log -Message "2. .\03-AIIntegration.ps1 -Test       # Run AI integration tests" -Level "INFO" -LogFile $logFile
    Write-Log -Message "3. .\04-OllamaSetup.ps1               # Setup Ollama service and models" -Level "INFO" -LogFile $logFile
    Write-Log -Message "Or run with full setup: .\03-AIIntegration.ps1 -Run" -Level "INFO" -LogFile $logFile
}

Write-Log -Message "Backend AI integration ready!" -Level "SUCCESS" -LogFile $logFile
Write-Log -Message "Next: Run 04-OllamaSetup.ps1 to configure Ollama service and models" -Level "INFO" -LogFile $logFile
Write-Log -Message "Log Files Created:" -Level "INFO" -LogFile $logFile
Write-Log -Message "Full transcript: $transcriptFile" -Level "INFO" -LogFile $logFile
Write-Log -Message "Structured log: $logFile" -Level "INFO" -LogFile $logFile
Write-Log -Message "JARVIS AI Integration Setup (v4.1) Complete!" -Level "SUCCESS" -LogFile $logFile


# Colorized summary output
$successCount = ($setupResults | Where-Object { $_.Success }).Count
$failCount = ($setupResults | Where-Object { -not $_.Success }).Count
Write-Host "SUCCESS: $successCount" -ForegroundColor Green
Write-Host "FAILED: $failCount" -ForegroundColor Red
foreach ($result in $setupResults) {
    $fg = if ($result.Success) { "Green" } else { "Red" }
    Write-Host "$($result.Name): $($result.Success ? 'SUCCESS' : 'FAILED')" -ForegroundColor $fg
}

Stop-Transcript