# 03-IntegrateOllama.ps1 - AI integration into FastAPI backend
# Purpose: Add Ollama-based AIService, personality config, and tests
# Last edit: 2025-08-06 - Manual inpection and alignments

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "5.0.0"
$scriptPrefix = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$projectRoot = Get-Location
$logsDir = Join-Path $projectRoot "logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptFile = Join-Path $logsDir "${scriptPrefix}-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "${scriptPrefix}-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile
Write-Log -Message "=== $($MyInvocation.MyCommand.Name) v$scriptVersion ===" -Level INFO -LogFile $logFile

if (-not ($Install -or $Configure -or $Test)) { $Run = $true }

Write-SystemInfo -ScriptName $scriptPrefix -Version $scriptVersion -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Install   = $Install
    Configure = $Configure
    Test      = $Test
    Run       = $Run
}

$hardware = Get-AvailableHardware -LogFile $logFile

# Script-level path variables (matching 02-FastApiBackend.ps1 pattern)
$backendDir = Join-Path $projectRoot "backend"
$venvDir = Join-Path $backendDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"

# Test if backend exists
function Test-BackendExists {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    $exists = (Test-Path "backend/api/main.py") -and (Test-Path "backend/requirements.txt")
    if (-not $exists) { Write-Log -Message "Backend not found. Run 02-FastApiBackend.ps1." -Level "ERROR" -LogFile $LogFile }
    return $exists
}

# Add Ollama dependency to backend
function Add-OllamaDependency {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Adding Ollama client to backend requirements..." -Level "INFO" -LogFile $LogFile
    $requirementsPath = "backend/requirements.txt"
    if (-not (Test-Path $requirementsPath)) {
        Write-Log -Message "Backend requirements.txt not found. Run 02-FastApiBackend.ps1." -Level "ERROR" -LogFile $LogFile
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
    else { Write-Log -Message "Ollama dependency already present in requirements.txt" -Level "SUCCESS" -LogFile $LogFile }
    return $true
}

# Create personality configuration
function New-PersonalityConfig {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
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
      "traits": [
          "witty",
          "sarcastic",
          "helpful",
          "loyal",
          "efficient"
      ],
      "tone": "professional with humor",
      "humor_level": "medium"
  },
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
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
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

# Create AI integration tests
function New-AIIntegrationTests {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
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

# Install AI dependencies (simplified - copy of 02-FastApiBackend.ps1 pattern)
function Install-AIDependencies {
    param( [string]$LogFile )
    Write-Log -Message "Installing AI integration dependencies..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "Virtual environment Python not found at $venvPy. Run 02-FastApiBackend.ps1." -Level "ERROR" -LogFile $LogFile
        return $false
    }
    try {
        Write-Log -Message "Installing requirements..." -Level "INFO" -LogFile $LogFile
        & $venvPy -m pip install -r (Join-Path $backendDir "requirements.txt") --quiet
        if ($LASTEXITCODE -eq 0) { Write-Log -Message "Backend requirements installed successfully" -Level "SUCCESS" -LogFile $LogFile }
        Write-Log -Message "Installing ollama>=0.4.5..." -Level "INFO" -LogFile $LogFile
        & $venvPy -m pip install ollama>=0.4.5 --quiet
        Write-Log -Message "Installing pytest-asyncio>=0.23.0..." -Level "INFO" -LogFile $LogFile
        & $venvPy -m pip install pytest-asyncio>=0.23.0 --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "AI integration packages installed successfully" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Failed to install ollama package" -Level "ERROR" -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error installing dependencies: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Run AI integration tests (simplified - no directory changes)
function Invoke-AIIntegrationTests {
    param( [string]$LogFile )
    Write-Log -Message "Running AI integration tests..." -Level "INFO" -LogFile $LogFile
    $testFile = Join-Path $backendDir "tests\test_ai_integration.py"
    if (-not (Test-Path $testFile)) {
        Write-Log -Message "AI integration test files not found at $testFile" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "Virtual environment Python not found at $venvPy" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    try {
        Write-Log -Message "Executing AI integration tests..." -Level "INFO" -LogFile $LogFile
        Push-Location $backendDir
        & $venvPy -m pytest "tests\test_ai_integration.py" -v --tb=short
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "AI integration tests passed" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Some AI integration tests failed (exit code: $LASTEXITCODE)" -Level "WARN" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Exception during AI test execution: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    finally { Pop-Location }
}

# Validate AI integration setup
function Test-AIIntegrationSetup {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Validating AI integration setup..." -Level "INFO" -LogFile $LogFile
    $validationResults = @()
    $requiredFiles = @(
        (Join-Path $backendDir "requirements.txt"),
        (Join-Path $backendDir "api\main.py"),
        (Join-Path $backendDir "services\ai_service.py"),
        (Join-Path $backendDir "services\__init__.py"),
        (Join-Path $backendDir "tests\test_ai_integration.py"),
        (Join-Path $projectRoot "jarvis_personality.json")
    )
    foreach ($filePath in $requiredFiles) {
        $fileName = Split-Path $filePath -Leaf
        if (Test-Path $filePath) { $validationResults += "✅ File: $fileName" }
        else { $validationResults += "❌ Missing: $fileName" }
    }
    # Check packages in virtual environment using script-level variables
    $pythonPackages = @("ollama", "fastapi", "uvicorn")
    foreach ($package in $pythonPackages) {
        $status = $false
        if (Test-Path $venvPy) {
            try {
                & $venvPy -m pip show $package *>$null
                $status = $LASTEXITCODE -eq 0
            }
            catch { $status = $false }
        }
        $checkmark = if ($status) { '✅' } else { '❌' }
        $validationResults += "$checkmark Python Package: $package"
    }
    $mainPath = Join-Path $backendDir "api\main.py"
    if (Test-Path $mainPath) {
        $mainContent = Get-Content $mainPath -Raw
        if ($mainContent -match "ai_service" -and $mainContent -match "1\.1\.0") {
            $validationResults += "✅ Backend: AI-enhanced FastAPI (v1.1.0)"
        }
        else {
            $validationResults += "❌ Backend: Missing AI integration"
        }
    }
    $personalityPath = Join-Path $projectRoot "jarvis_personality.json"
    if (Test-Path $personalityPath) {
        try {
            $configContent = Get-Content $personalityPath -Raw | ConvertFrom-Json
            $name = $configContent.identity.name
            $displayName = $configContent.identity.display_name
            $validationResults += "✅ Personality Config: $name ($displayName)"
        }
        catch { $validationResults += "⚠️  Personality Config: File exists but may be malformed" }
    }
    $envValid = Test-EnvironmentConfig -LogFile $LogFile
    if ($envValid) {
        $validationResults += "✅ Environment Config: Valid"
    }
    else {
        $validationResults += "❌ Environment Config: Invalid or missing OLLAMA_MODEL"
    }
    Write-Log -Message "=== AI INTEGRATION VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $validationResults) {
        $level = if ($result -like "✅*") { "SUCCESS" } elseif ($result -like "⚠️*") { "WARN" } else { "ERROR" }
        Write-Log -Message $result -Level $level -LogFile $LogFile
    }
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    $summaryLevel = if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }
    Write-Log -Message "AI Integration: $successCount/$($validationResults.Count) passed, $failureCount failed, $warningCount warnings" -Level $summaryLevel -LogFile $LogFile
    return $failureCount -eq 0
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

$setupResults += @{Name = "AI Integration Tests"; Success = (New-AIIntegrationTests -LogFile $logFile) }
if ($Install -or $Run) {
    Write-Log -Message "Installing AI dependencies..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "AI Dependencies"; Success = (Install-AIDependencies -LogFile $logFile) }
}
if ($Configure -or $Run) {
    Write-Log -Message "Validating environment configuration..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "Environment Update"; Success = (Test-EnvironmentConfig -LogFile $logFile) }
}
if ($Test -or $Run) {
    Write-Log -Message "Running AI integration tests..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "AI Tests"; Success = (Invoke-AIIntegrationTests -LogFile $logFile) }
}

# === NEXT STEPS ===
Write-Log -Message "=== NEXT STEPS ===" -Level "INFO" -LogFile $logFile
if (-not ($Install -or $Test -or $Configure -or $Run)) {
    Write-Log -Message "1. To validate environment: .\03-IntegrateOllama.ps1 -Configure" -Level "INFO" -LogFile $logFile
    Write-Log -Message "2. To run AI integration tests: .\03-IntegrateOllama.ps1 -Test" -Level "INFO" -LogFile $logFile
    Write-Log -Message "3. To setup Ollama service and models: .\04a-OllamaSetup.ps1" -Level "INFO" -LogFile $logFile
}
Write-Log -Message "Backend AI integration ready!" -Level "SUCCESS" -LogFile $logFile
Write-Log -Message "Next: Run .\04a-OllamaSetup.ps1 to configure Ollama service and models" -Level "INFO" -LogFile $logFile
Write-Log -Message "Log Files Created:" -Level "INFO" -LogFile $logFile
Write-Log -Message "Full transcript: $transcriptFile" -Level "INFO" -LogFile $logFile
Write-Log -Message "Structured log: $logFile" -Level "INFO" -LogFile $logFile

# === FINAL RESULTS ===
Write-Log -Message "=== FINAL RESULTS ===" -Level INFO -LogFile $logFile
$successCount = ($setupResults | Where-Object { $_.Success }).Count
$failCount = ($setupResults | Where-Object { -not $_.Success }).Count
Write-Log -Message "SUCCESS: $successCount components" -Level SUCCESS -LogFile $logFile
if ($failCount -gt 0) {
    Write-Log -Message "FAILED: $failCount components" -Level ERROR -LogFile $logFile
}
foreach ($result in $setupResults) {
    $status = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }
    $level = if ($result.Success) { "SUCCESS" } else { "ERROR" }
    Write-Log -Message "$($result.Name): $status" -Level $level -LogFile $logFile
}

Write-Log -Message "$scriptPrefix v$scriptVersion complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript
