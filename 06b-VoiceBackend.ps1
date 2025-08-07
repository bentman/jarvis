# 06b-VoiceBackendIntegration.ps1 - Voice Backend Integration & Testing Infrastructure  
# Purpose: Integrate voice service with FastAPI backend and create testing infrastructure
# Last edit: 2025-08-06 - Manual inpection and alignments

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "4.0.0"
$scriptPrefix = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$projectRoot = Get-Location
$logsDir = Join-Path $projectRoot "logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptFile = Join-Path $logsDir "${scriptPrefix}-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "${scriptPrefix}-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile
Write-Log -Message "=== $($MyInvocation.MyCommand.Name) v$scriptVersion ===" -Level INFO -LogFile $logFile

# Set default mode
if (-not ($Install -or $Configure -or $Test -or $Run)) { $Run = $true }

Write-SystemInfo -ScriptName $scriptPrefix -Version $scriptVersion -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Install   = $Install
    Configure = $Configure
    Test      = $Test
    Run       = $Run
}

$hardware = Get-AvailableHardware -LogFile $logFile

# Define script-level paths using critical backend pattern
$backendDir = Join-Path $projectRoot "backend"
$venvDir = Join-Path $backendDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"
$mainPath = Join-Path $backendDir "api\main.py"
$testPath = Join-Path $backendDir "tests\test_voice_integration.py"
$voiceServicePath = Join-Path $backendDir "services\voice_service.py"
$voiceConfigPath = Join-Path $projectRoot "jarvis_voice.json"

function Test-Prerequisites {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing prerequisites..." -Level INFO -LogFile $LogFile
    # Check that 06a has been run first
    if (-not (Test-Path $voiceServicePath)) {
        Write-Log -Message "❌ Voice service not found. Run 06a-VoiceSetup.ps1." -Level ERROR -LogFile $LogFile
        return $false
    }
    # Check voice service contains modern stack
    $serviceContent = Get-Content $voiceServicePath -Raw
    if (-not ($serviceContent -match "faster-whisper" -and $serviceContent -match "coqui" -and $serviceContent -match "openWakeWord")) {
        Write-Log -Message "❌ Voice service does not contain modern voice stack. Re-run 06a-VoiceSetup.ps1." -Level ERROR -LogFile $LogFile
        return $false
    }
    # Check main.py exists for backend integration
    if (-not (Test-Path $mainPath)) {
        Write-Log -Message "❌ FastAPI main.py not found. Run 02-FastApiBackend.ps1." -Level ERROR -LogFile $LogFile
        return $false
    }
    Write-Log -Message "✅ All prerequisites verified" -Level SUCCESS -LogFile $LogFile
    return $true
}

function Update-FastAPIWithVoiceIntegration {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Integrating voice service with FastAPI backend..." -Level INFO -LogFile $LogFile
    # Check current main.py status
    $mainContent = Get-Content $mainPath -Raw
    if ($mainContent -match "voice_service" -and $mainContent -match "2\.3\.0") {
        Write-Log -Message "FastAPI already integrated with voice service v$($JARVIS_APP_VERSION)" -Level INFO -LogFile $LogFile
        return $true
    }
    # Backup existing main.py
    $backupPath = "${mainPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $mainPath $backupPath
    Write-Log -Message "Backed up existing main.py to: $backupPath" -Level INFO -LogFile $LogFile
    # Create updated FastAPI application with voice integration
    $fastApiCode = @'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import os
from dotenv import load_dotenv
import logging
from services.ai_service import ai_service
from services.voice_service import voice_service

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Jarvis AI Assistant",
    description="AI Assistant Backend with Ollama and Modern Voice Integration",
    version="$($JARVIS_APP_VERSION)"
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

class VoiceMessage(BaseModel):
    content: str
    device_id: Optional[str] = None

class VoiceListenRequest(BaseModel):
    timeout: int = 10
    device_id: Optional[str] = None

class VoiceConfigureRequest(BaseModel):
    command: str
    params: dict

class ChatResponse(BaseModel):
    response: str
    mode: str
    model: str
    timestamp: str

@app.get("/")
async def root():
    voice_status = await voice_service.get_status()
    return {
        "message": "Jarvis AI Assistant Backend",
        "status": "running",
        "version": "2.2.0",
        "features": ["chat", "ai_integration", "voice_recognition", "text_to_speech", "wake_word_detection", "voice_configuration", "fallback_mode"],
        "voice_stack": voice_status.get("voice_stack", "unknown"),
        "docs": "/docs"
    }

@app.get("/api/health")
async def health_check():
    ai_status = await ai_service.get_status()
    voice_status = await voice_service.get_status()
    return {
        "status": "healthy",
        "service": "jarvis-backend",
        "version": "2.2.0",
        "ai_integration": ai_status,
        "voice_enabled": True,
        "voice_stack": {
            "stt": "faster-whisper",
            "tts": "coqui-tts", 
            "wake_word": "openWakeWord"
        },
        "voice_config_loaded": voice_status.get("config", {}) != {},
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
    voice_status = await voice_service.get_status()
    return {
        "backend": "running",
        "version": "2.2.0",
        "ai_service": ai_status,
        "voice_service": {
            "device": voice_status.get("device", "unknown"),
            "config_source": "jarvis_voice.json" if voice_status.get("config", {}) else "defaults",
            "whisper_available": voice_status.get("whisper_available", False),
            "tts_available": voice_status.get("tts_available", False),
            "wake_word_available": voice_status.get("wake_word_available", False)
        },
        "voice_stack": voice_status.get("voice_stack", "unknown"),
        "features": {
            "chat": True,
            "ai_integration": ai_status["ai_available"],
            "voice_recognition": voice_status.get("whisper_available", False),
            "text_to_speech": voice_status.get("tts_available", False),
            "wake_word_detection": voice_status.get("wake_word_available", False),
            "voice_configuration": True,
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

# Voice API Endpoints
@app.get("/api/voice/status")
async def voice_status():
    """Get voice service status and configuration"""
    return await voice_service.get_status()

@app.get("/api/voice/config")
async def voice_config():
    """Get voice configuration details"""
    voice_status = await voice_service.get_status()
    config = voice_status.get("config", {})
    
    # Load personality config for comparison
    personality_config = {}
    personality_paths = ["jarvis_personality.json", "../jarvis_personality.json", "../../jarvis_personality.json"]
    for path in personality_paths:
        if os.path.exists(path):
            try:
                import json
                with open(path, 'r', encoding='utf-8') as f:
                    personality_config = json.load(f).get("voice", {})
                    break
            except:
                pass
    
    return {
        "voice_config": config,
        "personality_config": personality_config,
        "config_source": "jarvis_voice.json" if config else "embedded_defaults"
    }

@app.post("/api/voice/speak")
async def voice_speak(message: VoiceMessage):
    """Convert text to speech using coqui-tts"""
    return await voice_service.speak(message.content, message.device_id)

@app.post("/api/voice/listen")
async def voice_listen(request: VoiceListenRequest = VoiceListenRequest()):
    """Convert speech to text using faster-whisper"""
    return await voice_service.listen(request.timeout, request.device_id)

@app.post("/api/voice/wake")
async def voice_wake():
    """Detect wake word using openWakeWord"""
    return await voice_service.detect_wake_word()

@app.post("/api/voice/stop")
async def voice_stop():
    """Stop all voice operations"""
    return await voice_service.stop()

@app.post("/api/voice/configure")
async def voice_configure(request: VoiceConfigureRequest):
    """Configure voice settings"""
    return await voice_service.configure(request.command, request.params)

@app.post("/api/voice/chat")
async def voice_chat():
    """Complete voice interaction (wake word -> listen -> AI -> speak)"""
    return await voice_service.chat()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
'@
    
    try {
        Set-Content -Path $mainPath -Value $fastApiCode -Encoding UTF8
        Write-Log -Message "✅ FastAPI backend updated with voice integration v2.3.0" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "❌ Failed to update FastAPI backend: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-VoiceIntegrationTests {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating voice integration tests..." -Level INFO -LogFile $LogFile
    $voiceTests = @'
import pytest
from fastapi.testclient import TestClient
from api.main import app

client = TestClient(app)

def test_root_shows_modern_voice_stack():
    """Test that root endpoint shows modern voice stack"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "voice_stack" in data
    assert "faster-whisper" in data["voice_stack"]
    assert "coqui-tts" in data["voice_stack"]
    assert "openWakeWord" in data["voice_stack"]

def test_root_shows_voice_features():
    """Test that root endpoint shows voice features"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "voice_recognition" in data["features"]
    assert "text_to_speech" in data["features"]
    assert "wake_word_detection" in data["features"]
    assert "voice_configuration" in data["features"]
    assert data["version"] == "2.2.0"

def test_health_includes_modern_voice():
    """Test health endpoint includes modern voice info"""
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert "voice_enabled" in data
    assert data["voice_enabled"] == True
    assert "voice_stack" in data
    assert "stt" in data["voice_stack"]
    assert "tts" in data["voice_stack"]
    assert "wake_word" in data["voice_stack"]
    assert data["voice_stack"]["stt"] == "faster-whisper"
    assert data["voice_stack"]["tts"] == "coqui-tts"
    assert data["voice_stack"]["wake_word"] == "openWakeWord"
    assert "voice_config_loaded" in data
    assert data["version"] == "2.2.0"

def test_status_includes_modern_voice_service():
    """Test status endpoint includes modern voice service info"""
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert "voice_service" in data
    assert "voice_stack" in data
    assert "faster-whisper" in data["voice_stack"]
    assert "coqui-tts" in data["voice_stack"]
    assert "openWakeWord" in data["voice_stack"]
    assert "device" in data["voice_service"]
    assert "config_source" in data["voice_service"]
    assert "whisper_available" in data["voice_service"]
    assert "tts_available" in data["voice_service"]
    assert "wake_word_available" in data["voice_service"]
    assert "voice_recognition" in data["features"]
    assert "text_to_speech" in data["features"]
    assert "wake_word_detection" in data["features"]
    assert "voice_configuration" in data["features"]
    assert data["version"] == "2.2.0"

def test_voice_status_endpoint():
    """Test voice status endpoint"""
    response = client.get("/api/voice/status")
    assert response.status_code == 200
    data = response.json()
    assert "voice_stack" in data
    assert "whisper_available" in data
    assert "tts_available" in data
    assert "wake_word_available" in data
    assert "device" in data
    assert "models" in data
    assert "config" in data
    assert "wake_words" in data

def test_voice_config_endpoint():
    """Test voice configuration endpoint"""
    response = client.get("/api/voice/config")
    assert response.status_code == 200
    data = response.json()
    assert "voice_config" in data
    assert "personality_config" in data
    assert "config_source" in data

def test_voice_speak_endpoint():
    """Test voice speak endpoint"""
    response = client.post("/api/voice/speak", json={"content": "Test message"})
    assert response.status_code == 200
    data = response.json()
    assert "success" in data
    assert "message" in data

def test_voice_listen_endpoint():
    """Test voice listen endpoint"""
    response = client.post("/api/voice/listen")
    assert response.status_code == 200
    data = response.json()
    assert "success" in data
    assert "message" in data

def test_voice_wake_endpoint():
    """Test wake word detection endpoint"""
    response = client.post("/api/voice/wake")
    assert response.status_code == 200
    data = response.json()
    assert "success" in data
    assert "message" in data

def test_voice_stop_endpoint():
    """Test voice stop endpoint"""
    response = client.post("/api/voice/stop")
    assert response.status_code == 200
    data = response.json()
    assert "success" in data

def test_voice_configure_endpoint():
    """Test voice configuration endpoint"""
    response = client.post("/api/voice/configure", json={
        "command": "configure",
        "params": {"speech_rate": 1.1}
    })
    assert response.status_code == 200
    data = response.json()
    assert "success" in data

def test_voice_chat_endpoint():
    """Test complete voice chat endpoint"""
    response = client.post("/api/voice/chat")
    assert response.status_code == 200
    data = response.json()
    assert "success" in data
    assert "message" in data

def test_voice_endpoints_return_proper_structure():
    """Test that voice endpoints return consistent structure"""
    endpoints = [
        ("/api/voice/speak", "post", {"content": "test"}),
        ("/api/voice/listen", "post", {}),
        ("/api/voice/wake", "post", {}),
        ("/api/voice/stop", "post", {}),
        ("/api/voice/chat", "post", {})
    ]
    
    for endpoint, method, payload in endpoints:
        if method == "post":
            response = client.post(endpoint, json=payload)
        else:
            response = client.get(endpoint)
            
        assert response.status_code == 200
        data = response.json()
        assert "success" in data
        assert "message" in data
        # Most endpoints should have "data" field
        if endpoint not in ["/api/voice/stop"]:
            assert "data" in data or not data["success"]

def test_voice_service_integration_with_ai():
    """Test that voice service can work alongside AI service"""
    # Test AI endpoint still works
    ai_response = client.get("/api/ai/status")
    assert ai_response.status_code == 200
    
    # Test voice endpoint works
    voice_response = client.get("/api/voice/status")
    assert voice_response.status_code == 200
    
    # Test combined status includes both
    status_response = client.get("/api/status")
    assert status_response.status_code == 200
    status_data = status_response.json()
    assert "ai_service" in status_data
    assert "voice_service" in status_data

def test_voice_configuration_loading():
    """Test that voice service properly loads configuration"""
    response = client.get("/api/voice/status")
    assert response.status_code == 200
    data = response.json()
    
    # Check that config contains expected structure
    config = data.get("config", {})
    expected_sections = ["voice_stack", "models", "audio_settings", "voice_responses", "hardware_optimization"]
    for section in expected_sections:
        assert section in config, f"Missing config section: {section}"
        
    # Check voice stack is modern
    assert config.get("voice_stack") == "faster-whisper + coqui-tts + openWakeWord"

def test_backend_version_updated():
    """Test that backend version is updated to 2.2.0"""
    endpoints = ["/", "/api/health", "/api/status"]
    
    for endpoint in endpoints:
        response = client.get(endpoint)
        assert response.status_code == 200
        data = response.json()
        assert data.get("version") == "2.2.0"
'@
    
    try {
        # Ensure tests directory exists
        $testsDir = Join-Path $backendDir "tests"
        if (-not (Test-Path $testsDir)) {
            New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
        }
        Set-Content -Path $testPath -Value $voiceTests -Encoding UTF8
        Write-Log -Message "✅ Voice integration tests created successfully" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "❌ Failed to create voice integration tests: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-VoiceDemoScript {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating voice testing demo script..." -Level INFO -LogFile $LogFile
    $demoScript = @'
# test_voice.ps1 - Modern Voice Integration Test Script (faster-whisper + coqui-tts + openWakeWord)
# Supports jarvis_voice.json configuration system
param(
    [switch]$TestMic,
    [switch]$TestTTS,
    [switch]$TestAPI,
    [switch]$Interactive,
    [switch]$ShowConfig
)

. .\00-CommonUtils.ps1
$logFile = Join-Path (Get-Location) "logs/test_voice_log_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

Write-Log -Message "Starting JARVIS Modern Voice Integration Test" -Level "INFO" -LogFile $logFile
Write-Host "JARVIS Modern Voice Integration Test" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "Voice Stack: faster-whisper + coqui-tts + openWakeWord" -ForegroundColor Green
Write-Host "Configuration: jarvis_voice.json" -ForegroundColor Green

$baseUrl = "http://localhost:8000"

if ($ShowConfig) {
    Write-Log -Message "Displaying voice configuration..." -Level "INFO" -LogFile $logFile
    Write-Host "`nVoice Configuration:" -ForegroundColor Yellow
    try {
        $config = Invoke-RestMethod -Uri "$baseUrl/api/voice/config"
        Write-Host "Configuration Source: $($config.config_source)" -ForegroundColor Cyan
        
        if (Test-Path "jarvis_voice.json") {
            $voiceConfig = Get-Content "jarvis_voice.json" -Raw | ConvertFrom-Json
            Write-Host "`nCurrent jarvis_voice.json settings:" -ForegroundColor White
            Write-Host "  Voice Stack: $($voiceConfig.voice_stack)" -ForegroundColor Gray
            Write-Host "  Whisper Model: $($voiceConfig.models.whisper_model)" -ForegroundColor Gray
            Write-Host "  TTS Model: $($voiceConfig.models.tts_model)" -ForegroundColor Gray
            Write-Host "  Wake Word Model: $($voiceConfig.models.wake_word_model)" -ForegroundColor Gray
            Write-Host "  Sample Rate: $($voiceConfig.audio_settings.sample_rate)" -ForegroundColor Gray
            Write-Host "  Speech Rate: $($voiceConfig.audio_settings.speech_rate)" -ForegroundColor Gray
            Write-Host "  Wake Words: $($voiceConfig.wake_words -join ', ')" -ForegroundColor Gray
        } else {
            Write-Host "jarvis_voice.json not found - using defaults" -ForegroundColor Yellow
        }
    } catch {
        Write-Log -Message "Failed to get voice configuration: $_" -Level "ERROR" -LogFile $logFile
        Write-Host "❌ Failed to get voice configuration: $_" -ForegroundColor Red
    }
}

if ($TestMic) {
    Write-Log -Message "Testing Microphone (faster-whisper)..." -Level "INFO" -LogFile $logFile
    Write-Host "`nTesting Microphone (faster-whisper)..." -ForegroundColor Yellow
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/api/voice/listen" -Method Post -TimeoutSec 15
        if ($response.success) {
            Write-Log -Message "Microphone working! Recognized: $($response.data.text)" -Level "SUCCESS" -LogFile $logFile
            Write-Host "✅ Microphone working! Recognized: $($response.data.text)" -ForegroundColor Green
        } else {
            Write-Log -Message "No speech detected: $($response.message)" -Level "WARN" -LogFile $logFile
            Write-Host "⚠️ No speech detected: $($response.message)" -ForegroundColor Yellow
        }
    } catch {
        Write-Log -Message "Microphone test failed: $_" -Level "ERROR" -LogFile $logFile
        Write-Host "❌ Microphone test failed: $_" -ForegroundColor Red
    }
}

if ($TestTTS) {
    Write-Log -Message "Testing Text-to-Speech (coqui-tts)..." -Level "INFO" -LogFile $logFile
    Write-Host "`nTesting Text-to-Speech (coqui-tts)..." -ForegroundColor Yellow
    try {
        $body = @{content = "Hello, I am Jarvis, your AI assistant. Modern voice systems with coqui TTS and jarvis voice json configuration are now operational."} | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "$baseUrl/api/voice/speak" -Method Post -Body $body -ContentType "application/json"
        if ($response.success) {
            Write-Log -Message "TTS working! coqui-tts speaking..." -Level "SUCCESS" -LogFile $logFile
            Write-Host "✅ TTS working! coqui-tts speaking..." -ForegroundColor Green
            Start-Sleep -Seconds 8
        } else {
            Write-Log -Message "TTS failed: $($response.message)" -Level "ERROR" -LogFile $logFile
            Write-Host "❌ TTS failed: $($response.message)" -ForegroundColor Red
        }
    } catch {
        Write-Log -Message "TTS test failed: $_" -Level "ERROR" -LogFile $logFile
        Write-Host "❌ TTS test failed: $_" -ForegroundColor Red
    }
}

if ($TestAPI) {
    Write-Log -Message "Testing Modern Voice API Endpoints..." -Level "INFO" -LogFile $logFile
    Write-Host "`nTesting Modern Voice API Endpoints..." -ForegroundColor Yellow
    
    try {
        $status = Invoke-RestMethod -Uri "$baseUrl/api/voice/status"
        Write-Log -Message "Voice status retrieved" -Level "SUCCESS" -LogFile $logFile
        Write-Host "Modern Voice Status:" -ForegroundColor Cyan
        Write-Host "  Voice Stack: $($status.voice_stack)" -ForegroundColor White
        Write-Host "  faster-whisper: $(if ($status.whisper_available) { '✅' } else { '❌' })" -ForegroundColor $(if ($status.whisper_available) { 'Green' } else { 'Red' })
        Write-Host "  coqui-tts: $(if ($status.tts_available) { '✅' } else { '❌' })" -ForegroundColor $(if ($status.tts_available) { 'Green' } else { 'Red' })
        Write-Host "  openWakeWord: $(if ($status.wake_word_available) { '✅' } else { '❌' })" -ForegroundColor $(if ($status.wake_word_available) { 'Green' } else { 'Red' })
        Write-Host "  Device: $($status.device)" -ForegroundColor White
        Write-Host "  Models:" -ForegroundColor White
        Write-Host "    Whisper: $($status.models.whisper_model)" -ForegroundColor Gray
        Write-Host "    TTS: $($status.models.tts_model)" -ForegroundColor Gray
        Write-Host "    Wake Word: $($status.models.wake_word_model)" -ForegroundColor Gray
        Write-Host "  Wake Words: $($status.wake_words -join ', ')" -ForegroundColor White
        
        # Test configuration endpoint
        Write-Host "`nTesting Voice Configuration Endpoint..." -ForegroundColor Yellow
        $config = Invoke-RestMethod -Uri "$baseUrl/api/voice/config"
        Write-Host "  Config Source: $($config.config_source)" -ForegroundColor White
        Write-Host "  Config Loaded: $(if ($config.voice_config.voice_stack) { '✅' } else { '❌' })" -ForegroundColor $(if ($config.voice_config.voice_stack) { 'Green' } else { 'Red' })
        
        # Test backend integration
        Write-Host "`nTesting Backend Integration..." -ForegroundColor Yellow
        $backendStatus = Invoke-RestMethod -Uri "$baseUrl/api/status"
        Write-Host "  Backend Version: $($backendStatus.version)" -ForegroundColor White
        Write-Host "  Voice Service Integration: $(if ($backendStatus.voice_service) { '✅' } else { '❌' })" -ForegroundColor $(if ($backendStatus.voice_service) { 'Green' } else { 'Red' })
        Write-Host "  Voice Features Available: $(($backendStatus.features | Where-Object { $_.Key -like '*voice*' -or $_.Key -like '*speech*' -or $_.Key -like '*wake*' }).Count)" -ForegroundColor White
        
    } catch {
        Write-Log -Message "Failed to get voice status: $_" -Level "ERROR" -LogFile $logFile
        Write-Host "❌ Failed to get voice status: $_" -ForegroundColor Red
    }
}

if ($Interactive) {
    Write-Log -Message "Starting Interactive Modern Voice Test..." -Level "INFO" -LogFile $logFile
    Write-Host "`nStarting Interactive Modern Voice Test..." -ForegroundColor Yellow
    Write-Host "Say your wake word to activate, then speak your message." -ForegroundColor Cyan
    Write-Host "Uses: openWakeWord -> faster-whisper -> AI -> coqui-tts" -ForegroundColor Gray
    Write-Host "Configuration: jarvis_voice.json" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to exit." -ForegroundColor Gray
    
    while ($true) {
        try {
            Write-Log -Message "Listening for wake word (openWakeWord)..." -Level "INFO" -LogFile $logFile
            Write-Host "`nListening for wake word (openWakeWord)..." -ForegroundColor Gray
            $wake = Invoke-RestMethod -Uri "$baseUrl/api/voice/wake" -Method Post -TimeoutSec 35
            
            if ($wake.success) {
                Write-Log -Message "Wake word detected!" -Level "SUCCESS" -LogFile $logFile
                Write-Host "✅ Wake word detected!" -ForegroundColor Green
                if ($wake.data.wake_words) {
                    Write-Host "   Configured wake words: $($wake.data.wake_words -join ', ')" -ForegroundColor Gray
                }
                
                Write-Log -Message "Processing modern voice chat..." -Level "INFO" -LogFile $logFile
                Write-Host "Processing modern voice chat (faster-whisper + coqui-tts)..." -ForegroundColor Cyan
                $chat = Invoke-RestMethod -Uri "$baseUrl/api/voice/chat" -Method Post -TimeoutSec 30
                
                if ($chat.success) {
                    Write-Log -Message "You said: $($chat.data.user_text)" -Level "INFO" -LogFile $logFile
                    Write-Log -Message "Jarvis: $($chat.data.ai_response)" -Level "SUCCESS" -LogFile $logFile
                    Write-Host "You said: $($chat.data.user_text)" -ForegroundColor Yellow
                    Write-Host "Jarvis: $($chat.data.ai_response)" -ForegroundColor Cyan
                    Start-Sleep -Seconds 3
                } else {
                    Write-Log -Message "Voice chat failed: $($chat.message)" -Level "ERROR" -LogFile $logFile
                    Write-Host "❌ Voice chat failed: $($chat.message)" -ForegroundColor Red
                    if ($chat.data.spoken_response) {
                        Write-Host "   Spoken response: $($chat.data.spoken_response)" -ForegroundColor Gray
                    }
                }
            }
        } catch {
            if ($_.Exception.Message -like "*operation was canceled*") {
                Write-Log -Message "Exiting interactive mode" -Level "INFO" -LogFile $logFile
                Write-Host "`nExiting interactive mode." -ForegroundColor Yellow
                break
            }
            Write-Log -Message "Error: $_" -Level "ERROR" -LogFile $logFile
            Write-Host "❌ Error: $_" -ForegroundColor Red
        }
        
        Start-Sleep -Seconds 1
    }
}

if (-not ($TestMic -or $TestTTS -or $TestAPI -or $Interactive -or $ShowConfig)) {
    Write-Log -Message "Displaying usage instructions" -Level "INFO" -LogFile $logFile
    Write-Host "`nUsage:" -ForegroundColor Yellow
    Write-Host "  .\test_voice.ps1 -ShowConfig     # Show voice configuration" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -TestMic        # Test microphone (faster-whisper)" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -TestTTS        # Test text-to-speech (coqui-tts)" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -TestAPI        # Test API endpoints" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -Interactive    # Interactive voice mode (full stack)" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -TestMic -TestTTS -TestAPI  # Run all tests" -ForegroundColor Gray
    Write-Host "`nConfiguration:" -ForegroundColor Yellow
    Write-Host "  Edit jarvis_voice.json to customize voice settings, models, and responses" -ForegroundColor Gray
    Write-Host "  Restart backend after changing jarvis_voice.json" -ForegroundColor Gray
    Write-Host "`nBackend Integration:" -ForegroundColor Yellow
    Write-Host "  Backend version should be 2.2.0 with voice integration" -ForegroundColor Gray
    Write-Host "  All voice endpoints available at /api/voice/*" -ForegroundColor Gray
}
'@
    
    try {
        Set-Content -Path "test_voice.ps1" -Value $demoScript -Encoding UTF8
        Write-Log -Message "✅ Voice testing demo script created: test_voice.ps1" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "❌ Failed to create demo script: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Test-BackendIntegration {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing backend voice integration..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "❌ Virtual environment not found - cannot test backend integration" -Level ERROR -LogFile $LogFile
        Write-Log -Message "❌ Run 02-FastApiBackend.ps1 first" -Level ERROR -LogFile $LogFile
        return $false
    }
    # Test backend can import voice service
    Push-Location
    try {
        Write-Log -Message "Testing voice service import..." -Level INFO -LogFile $LogFile
        # Change to backend directory for Python import context
        Set-Location $backendDir
        $importTest = @"
try:
    from services.voice_service import voice_service
    print(f"Voice service loaded successfully")
    print(f"Voice stack: {voice_service.voice_config.get('voice_stack', 'unknown')}")
    print(f"Config loaded: {len(voice_service.voice_config) > 5}")
    print(f"Device: {voice_service.device}")
except Exception as e:
    print(f"Voice service import failed: {e}")
    raise
"@
        
        $importResult = $importTest | & $venvPy 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "✅ Voice service import test passed: $importResult" -Level SUCCESS -LogFile $LogFile
        }
        else {
            Write-Log -Message "❌ Voice service import test failed: $importResult" -Level ERROR -LogFile $LogFile
            Write-Log -Message "❌ Ensure 06a-VoiceSetup.ps1 completed successfully and voice service exists." -Level ERROR -LogFile $LogFile
            return $false
        }
        # Test FastAPI app can start with voice integration
        Write-Log -Message "Testing FastAPI app import with voice integration..." -Level INFO -LogFile $LogFile
        $appTest = @"
try:
    from api.main import app
    print("FastAPI app with voice integration loaded successfully")
    print(f"App title: {app.title}")
    print(f"App version: {app.version}")
    
    # Test that voice endpoints are registered
    routes = [route.path for route in app.routes]
    voice_routes = [route for route in routes if '/voice/' in route]
    print(f"Voice routes found: {len(voice_routes)}")
    for route in voice_routes:
        print(f"  {route}")
        
except Exception as e:
    print(f"FastAPI app import failed: {e}")
    raise
"@
        
        $appResult = $appTest | & $venvPy 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "✅ FastAPI app integration test passed: $appResult" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "❌ FastAPI app integration test failed: $appResult" -Level ERROR -LogFile $LogFile
            Write-Log -Message "❌ Check backend main.py syntax and voice service integration." -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "❌ Backend integration test error: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
    finally { Pop-Location }
}

function New-BackendIntegrationValidation {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Validating backend integration..." -Level INFO -LogFile $LogFile
    $validationResults = @()
    # Check FastAPI main.py has voice integration
    if (Test-Path $mainPath) {
        $mainContent = Get-Content $mainPath -Raw
        if ($mainContent -match "voice_service" -and $mainContent -match "2\.2\.0") {
            $validationResults += "✅ Backend: Voice integration updated to v2.2.0"
        }
        else { $validationResults += "❌ Backend: Voice integration not updated" }
        # Check for voice endpoints
        $voiceEndpoints = @("/api/voice/status", "/api/voice/config", "/api/voice/speak", "/api/voice/listen", "/api/voice/wake", "/api/voice/stop", "/api/voice/configure", "/api/voice/chat")
        $foundEndpoints = 0
        foreach ($endpoint in $voiceEndpoints) {
            if ($mainContent -match [regex]::Escape($endpoint)) { $foundEndpoints++ }
        }
        $validationResults += "✅ Voice endpoints: $foundEndpoints/8 found"
        if ($mainContent -match "from services\.voice_service import voice_service") {
            $validationResults += "✅ Voice service import: Present in main.py"
        }
        else { $validationResults += "❌ Voice service import: Missing from main.py" }
    }
    else { $validationResults += "❌ Backend: main.py not found" }
    # Check integration tests
    if (Test-Path $testPath) {
        $testContent = Get-Content $testPath -Raw
        if ($testContent -match "test_.*voice" -and $testContent -match "faster-whisper" -and $testContent -match "2\.2\.0") {
            $validationResults += "✅ Integration tests: Modern voice tests created"
        }
        else { $validationResults += "❌ Integration tests: Not modern or incomplete" }
    }
    else { $validationResults += "❌ Integration tests: test_voice_integration.py missing" }
    # Check demo script
    if (Test-Path "test_voice.ps1") {
        $demoContent = Get-Content "test_voice.ps1" -Raw
        if ($demoContent -match "faster-whisper" -and $demoContent -match "jarvis_voice\.json" -and $demoContent -match "ShowConfig") {
            $validationResults += "✅ Demo script: test_voice.ps1 created with modern features"
        }
        else { $validationResults += "❌ Demo script: Missing modern features" }
    }
    else { $validationResults += "❌ Demo script: test_voice.ps1 missing" }
    # Display results
    Write-Log -Message "=== BACKEND INTEGRATION VALIDATION ===" -Level INFO -LogFile $LogFile
    foreach ($result in $validationResults) {
        $level = if ($result -like "✅*") { "SUCCESS" } else { "ERROR" }
        Write-Log -Message $result -Level $level -LogFile $LogFile
    }
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    Write-Log -Message "Backend Integration: $successCount/$($validationResults.Count) passed, $failureCount failed" -Level $(if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }) -LogFile $logFile
    return $failureCount -eq 0
}

# Main execution
try {
    if (-not (Test-Prerequisites -LogFile $logFile)) {
        Stop-Transcript
        exit 1
    }
    $setupResults = @()
    # Backend integration setup - always run
    Write-Log -Message "Setting up voice backend integration..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "FastAPI Voice Integration"; Success = (Update-FastAPIWithVoiceIntegration -LogFile $logFile) }
    $setupResults += @{Name = "Voice Integration Tests"; Success = (New-VoiceIntegrationTests -LogFile $logFile) }
    $setupResults += @{Name = "Voice Demo Script"; Success = (New-VoiceDemoScript -LogFile $logFile) }
    if ($Test -or $Run) {
        Write-Log -Message "Testing backend integration..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Backend Integration Test"; Success = (Test-BackendIntegration -LogFile $logFile) }
    }

    Write-Log -Message "=== FINAL RESULTS ===" -Level INFO -LogFile $logFile
    $successCount = ($setupResults | Where-Object { $_.Success }).Count
    $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
    Write-Log -Message "SUCCESS: $successCount components" -Level SUCCESS -LogFile $logFile
    if ($failCount -gt 0) {
        Write-Log -Message "❌ FAILED: $failCount components" -Level ERROR -LogFile $logFile
    }
    foreach ($result in $setupResults) {
        $status = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }
        $level = if ($result.Success) { "SUCCESS" } else { "ERROR" }
        Write-Log -Message "$($result.Name): $status" -Level $level -LogFile $logFile
    }

    if ($failCount -gt 0) {
        Write-Log -Message "❌ Voice backend integration setup had failures" -Level ERROR -LogFile $logFile
        Stop-Transcript
        exit 1
    }
    # Always run validation summary
    New-BackendIntegrationValidation -LogFile $logFile | Out-Null
    # Output integration info
    Write-Log -Message "=== VOICE BACKEND INTEGRATION ===" -Level INFO -LogFile $logFile
    Write-Log -Message "FastAPI Backend: Updated to v2.2.0 with voice endpoints" -Level INFO -LogFile $logFile
    Write-Log -Message "Integration Tests: backend/tests/test_voice_integration.py" -Level INFO -LogFile $logFile
    Write-Log -Message "Demo Script: test_voice.ps1 (with -ShowConfig option)" -Level INFO -LogFile $logFile
    Write-Log -Message "Voice Endpoints: /api/voice/* (8 endpoints)" -Level INFO -LogFile $logFile
    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    Write-Log -Message "1. Run .\06c-VoiceInstall.ps1 -Install -Test to install voice dependencies" -Level INFO -LogFile $logFile
    Write-Log -Message "2. Start backend: .\run_backend.ps1" -Level INFO -LogFile $logFile
    Write-Log -Message "3. Test integration: .\test_voice.ps1 -ShowConfig -TestAPI" -Level INFO -LogFile $logFile
    Write-Log -Message "4. Run tests: Push-Location; Set-Location backend; .\.venv\Scripts\python.exe -m pytest tests/test_voice_integration.py -v; Pop-Location" -Level INFO -LogFile $logFile
}
catch {
    Write-Log -Message "❌ Error: $_" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript