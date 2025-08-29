# 06-VoiceBackend.ps1 - Combined Voice Setup, Backend Integration, and Installation
# Purpose: Modern voice stack with faster-whisper + Kokoro-82M + openWakeWord
# Last edit: 2025-08-25 - Removed non-existent pymicro-wakeword package and fixed duplicate results

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "5.0.5"
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

# Script-level path variables (following 02-FastApiBackend.ps1 pattern)
$backendDir = Join-Path $projectRoot "backend"
$venvDir = Join-Path $backendDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"
$voiceServicePath = Join-Path $backendDir "services\voice_service.py"
$voiceConfigPath = Join-Path $projectRoot "jarvis_voice.json"
$mainPath = Join-Path $backendDir "api\main.py"
$testPath = Join-Path $backendDir "tests\test_voice_integration.py"

# -------------------------
# Functions
# -------------------------

function Test-Prerequisites {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing voice system prerequisites..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path $backendDir)) {
        Write-Log -Message "Backend directory not found. Run 02-FastApiBackend.ps1 first." -Level ERROR -LogFile $LogFile
        return $false
    }
    if (-not (Test-Path (Join-Path $backendDir 'services'))) {
        Write-Log -Message "Backend services directory not found." -Level ERROR -LogFile $LogFile
        return $false
    }
    if (-not (Test-Path (Join-Path $backendDir 'services\ai_service.py'))) {
        Write-Log -Message "AI service not found - required dependency for voice integration" -Level ERROR -LogFile $LogFile
        Write-Log -Message "Run 03-IntegrateOllama.ps1 first." -Level ERROR -LogFile $LogFile
        return $false
    }
    if (-not (Test-Path $venvDir) -or -not (Test-Path $venvPy)) {
        Write-Log -Message "Backend virtual environment missing. Run 02-FastApiBackend.ps1 first." -Level ERROR -LogFile $LogFile
        return $false
    }
    Write-Log -Message "All prerequisites verified" -Level SUCCESS -LogFile $LogFile
    return $true
}

function New-VoiceConfiguration {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating modern voice configuration..." -Level INFO -LogFile $LogFile
    if (Test-Path $voiceConfigPath) {
        Write-Log -Message "jarvis_voice.json already exists - preserving existing configuration" -Level INFO -LogFile $LogFile
        return $true
    }
    # Load personality defaults if available
    $personalityDefaults = @{
        speech_rate = 1.0
        voice_pitch = 0.5
        wake_words  = @('jarvis', 'hey jarvis')
    }
    $personalityPath = Join-Path $projectRoot "jarvis_personality.json"
    if (Test-Path $personalityPath) {
        try {
            $personality = Get-Content $personalityPath -Raw | ConvertFrom-Json
            if ($personality.voice) {
                $personalityDefaults.speech_rate = $personality.voice.speech_rate ?? $personalityDefaults.speech_rate
                $personalityDefaults.voice_pitch = $personality.voice.voice_pitch ?? $personalityDefaults.voice_pitch
                $personalityDefaults.wake_words = $personality.voice.wake_words ?? $personalityDefaults.wake_words
            }
        }
        catch { Write-Log -Message "Could not parse personality config, using defaults: $($_.Exception.Message)" -Level WARN -LogFile $LogFile }
    }
    # Modern voice stack configuration
    $voiceConfig = @{
        voice_stack           = 'faster-whisper + kokoro-tts + openWakeWord'
        models                = @{
            whisper_model     = 'large-v3'           # RTX 3060 optimized
            whisper_model_npu = 'medium'         # NPU optimized  
            tts_model         = 'kokoro-82M'
            wake_word_model   = 'hey_jarvis_v0.1'  # openWakeWord model
        }
        hardware_optimization = @{
            npu_backend         = 'directml'
            onnx_runtime        = $true
            espeak_ng_path      = 'C:/Program Files/eSpeak NG/'
            prefer_npu          = $true
            gpu_memory_fraction = 0.7
            cpu_threads         = 4
        }
        audio_settings        = @{
            sample_rate    = 24000                   # Kokoro native rate
            chunk_duration = 1.0
            speech_rate    = $personalityDefaults.speech_rate
            voice_pitch    = $personalityDefaults.voice_pitch
            volume         = 0.8
        }
        wake_words            = $personalityDefaults.wake_words
        voice_responses       = @{
            wake_acknowledged = 'Yes, how can I help you?'
            listening         = "I'm listening..."
            processing        = 'Let me think about that...'
        }
        advanced              = @{
            vad_threshold         = 0.5
            silence_timeout       = 2.0
            phrase_timeout        = 3.0
            wake_word_sensitivity = 0.5
        }
    }
    try {
        $voiceConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $voiceConfigPath -Encoding UTF8
        Write-Log -Message 'Created jarvis_voice.json with modern voice stack configuration' -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create jarvis_voice.json: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-ModernVoiceServiceModule {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating modern voice service module..." -Level INFO -LogFile $LogFile
    if (Test-Path $voiceServicePath) {
        $backupPath = "${voiceServicePath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $voiceServicePath $backupPath
        Write-Log -Message "Backed up existing voice service to: $backupPath" -Level INFO -LogFile $LogFile
    }
    # Modern voice service with Kokoro-82M + faster-whisper + openWakeWord
    $voiceServiceCode = @'
# services/voice_service.py - Modern Voice Service with Kokoro-82M TTS
import asyncio
import json
import os
import logging
from typing import Optional, Dict, Any
from datetime import datetime

# Modern voice stack imports with graceful fallback
try:
    from kokoro import KPipeline
    import soundfile as sf
    from faster_whisper import WhisperModel
    import openwakeword
    import onnxruntime as ort
    VOICE_DEPENDENCIES_AVAILABLE = True
except ImportError as e:
    logging.warning(f"Voice dependencies not available: {e}")
    VOICE_DEPENDENCIES_AVAILABLE = False

class ModernVoiceService:
    def __init__(self):
        self.voice_config = self._load_voice_config()
        self.hardware_config = self._detect_hardware()
        self.tts_pipeline = None
        self.whisper_model = None
        self.wake_word_detector = None
        self._initialize_components()
    
    def _load_voice_config(self) -> Dict[str, Any]:
        """Load voice configuration from jarvis_voice.json"""
        config_paths = [
            "../../jarvis_voice.json",
            "../jarvis_voice.json", 
            "jarvis_voice.json"
        ]
        
        for path in config_paths:
            try:
                if os.path.exists(path):
                    with open(path, 'r', encoding='utf-8') as f:
                        config = json.load(f)
                        logging.info(f"Loaded voice config from {path}")
                        return config
            except Exception as e:
                logging.warning(f"Failed to load voice config from {path}: {e}")
        
        logging.warning("Voice config not found, using defaults")
        return self._get_default_voice_config()
    
    def _get_default_voice_config(self) -> Dict[str, Any]:
        return {
            "voice_stack": "faster-whisper + kokoro-tts + openWakeWord",
            "models": {
                "tts_model": "kokoro-82M",
                "whisper_model": "base"
            },
            "audio_settings": {
                "sample_rate": 24000,
                "speech_rate": 1.0
            },
            "hardware_optimization": {
                "prefer_npu": False
            },
            "wake_words": ["jarvis", "hey jarvis"]
        }
    
    def _detect_hardware(self) -> Dict[str, Any]:
        """Detect available hardware acceleration following NPU → GPU → CPU priority"""
        hardware = {
            "device": "cpu",
            "npu_available": False,
            "gpu_available": False,
            "providers": []
        }
        
        try:
            # Check ONNX Runtime providers
            providers = ort.get_available_providers()
            hardware["providers"] = providers
            
            # Priority 1: NPU (for NPU-capable systems)
            # Note: NPU support would need specific implementation
            
            # Priority 2: GPU with CUDA (NVIDIA only)
            if 'CUDAExecutionProvider' in providers:
                hardware["gpu_available"] = True  
                hardware["device"] = "cuda"
                logging.info("CUDA (GPU) support detected")
            # Priority 3: CPU fallback
            else:
                logging.info("Using CPU device (no GPU acceleration)")
                
        except Exception as e:
            logging.warning(f"Hardware detection failed: {e}")
        
        return hardware
    
    def _initialize_components(self):
        """Initialize voice components based on available hardware"""
        if not VOICE_DEPENDENCIES_AVAILABLE:
            logging.warning("Voice dependencies not available - voice features disabled")
            return
            
        try:
            # Initialize Kokoro TTS
            lang_code = 'a'  # American English
            self.tts_pipeline = KPipeline(lang_code=lang_code)
            logging.info("Kokoro TTS pipeline initialized")
            
            # Initialize Whisper based on hardware
            model_name = self.voice_config.get("models", {}).get("whisper_model", "base")
            device = self.hardware_config["device"]
            
            # Use supported devices only: cuda, cpu, auto
            if device == "cuda":
                self.whisper_model = WhisperModel(model_name, device="cuda")
                logging.info(f"Whisper model initialized: {model_name} on CUDA")
            else:
                self.whisper_model = WhisperModel(model_name, device="cpu")
                logging.info(f"Whisper model initialized: {model_name} on CPU")
            
        except Exception as e:
            logging.error(f"Failed to initialize voice components: {e}")
    
    async def text_to_speech(self, text: str, voice: str = "af_heart") -> Optional[bytes]:
        """Convert text to speech using Kokoro-82M"""
        if not self.tts_pipeline:
            logging.warning("TTS pipeline not available")
            return None
            
        try:
            generator = self.tts_pipeline(text, voice=voice)
            audio_data = None
            
            for i, (gs, ps, audio) in enumerate(generator):
                # Convert PyTorch tensor to numpy array, then to bytes for API response
                import numpy as np
                if hasattr(audio, 'cpu'):
                    # PyTorch tensor - convert to numpy
                    audio_np = audio.cpu().numpy()
                else:
                    # Already numpy array
                    audio_np = audio
                    
                audio_data = (audio_np * 32767).astype('int16').tobytes()
                break  # Take first chunk
                
            return audio_data
        except Exception as e:
            logging.error(f"TTS generation failed: {e}")
            return None
    
    async def speech_to_text(self, audio_data: bytes) -> Optional[str]:
        """Convert speech to text using faster-whisper"""
        if not self.whisper_model:
            logging.warning("Whisper model not available")
            return None
            
        try:
            # Implementation would convert audio_data and transcribe
            # This is a simplified version - full implementation would handle audio format conversion
            segments, info = self.whisper_model.transcribe(audio_data)
            result = " ".join([segment.text for segment in segments])
            return result.strip()
        except Exception as e:
            logging.error(f"STT transcription failed: {e}")
            return None
    
    async def get_status(self) -> Dict[str, Any]:
        """Get comprehensive voice service status"""
        return {
            "voice_stack": self.voice_config.get("voice_stack", "unknown"),
            "whisper_available": self.whisper_model is not None,
            "tts_available": self.tts_pipeline is not None,
            "wake_word_available": self.wake_word_detector is not None,
            "device": self.hardware_config["device"], 
            "npu_available": self.hardware_config["npu_available"],
            "gpu_available": self.hardware_config["gpu_available"],
            "providers": self.hardware_config["providers"],
            "models": self.voice_config.get("models", {}),
            "config": self.voice_config,
            "wake_words": self.voice_config.get("wake_words", ["jarvis"]),
            "dependencies_available": VOICE_DEPENDENCIES_AVAILABLE
        }

# Global instance
voice_service = ModernVoiceService()
'@
    
    try {
        Set-Content -Path $voiceServicePath -Value $voiceServiceCode -Encoding UTF8
        Write-Log -Message 'Modern voice service module created successfully' -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create voice service module: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Install-ModernVoiceDependencies {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Installing Python voice stack packages..." -Level INFO -LogFile $LogFile
    # Install Python packages in virtual environment
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "Virtual environment Python not found at $venvPy" -Level ERROR -LogFile $LogFile
        return $false
    }
    try {
        Write-Log -Message "Upgrading pip in virtual environment..." -Level INFO -LogFile $LogFile
        & $venvPy -m pip install --upgrade pip --quiet
        Write-Log -Message "Installing modern voice stack packages..." -Level INFO -LogFile $LogFile
        # Core dependencies first
        Write-Log -Message "Installing PyTorch and core audio libraries..." -Level INFO -LogFile $LogFile
        $coreDeps = @('torch', 'torchaudio', 'numpy>=1.24.0', 'soundfile>=0.12.1')
        foreach ($dep in $coreDeps) {
            Write-Log -Message "Installing: $dep" -Level INFO -LogFile $LogFile
            & $venvPy -m pip install $dep --quiet
        }
        # Voice stack dependencies with FastAPI file upload support
        Write-Log -Message "Installing voice processing libraries..." -Level INFO -LogFile $LogFile
        $voiceDeps = @(
            'faster-whisper>=1.0.0',
            'kokoro>=0.9.4', 
            'openwakeword>=0.6.0',
            'onnxruntime-directml>=1.22.0',
            'sounddevice>=0.4.6',
            'librosa>=0.10.0',
            'python-multipart>=0.0.6'  # Required for FastAPI file uploads
        )
        foreach ($dep in $voiceDeps) {
            Write-Log -Message "Installing: $dep" -Level INFO -LogFile $LogFile
            & $venvPy -m pip install $dep --quiet
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Python voice dependencies installed successfully" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Python voice dependencies installation failed" -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error installing voice dependencies: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Set-VoiceEnvironment {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Configuring voice environment variables..." -Level INFO -LogFile $LogFile
    # Use existing environment validation
    $envValid = Test-EnvironmentConfig -LogFile $LogFile
    try {
        # eSpeak-NG path configuration
        $espeakPath = "C:\Program Files\eSpeak NG"
        if (Test-Path $espeakPath) {
            [Environment]::SetEnvironmentVariable("PHONEMIZER_ESPEAK_LIBRARY", (Join-Path $espeakPath "libespeak-ng.dll"), "Process")
            [Environment]::SetEnvironmentVariable("PHONEMIZER_ESPEAK_PATH", (Join-Path $espeakPath "espeak-ng.exe"), "Process")
            [Environment]::SetEnvironmentVariable("ESPEAK_DATA_PATH", (Join-Path $espeakPath "espeak-ng-data"), "Process")
            Write-Log -Message "eSpeak-NG environment variables configured" -Level SUCCESS -LogFile $LogFile
        }
        else {
            Write-Log -Message "eSpeak-NG installation path not found - voice features may not work properly" -Level WARN -LogFile $LogFile
        }
        # Hardware-specific environment variables
        if ($hardware.NPU.Available) {
            [Environment]::SetEnvironmentVariable("KOKORO_DEVICE", "cpu", "Process")      # Kokoro uses CPU, NPU via DirectML bridge
            [Environment]::SetEnvironmentVariable("WHISPER_DEVICE", "directml", "Process")
            [Environment]::SetEnvironmentVariable("WAKE_WORD_ENGINE", "openWakeWord", "Process")
            [Environment]::SetEnvironmentVariable("ONNXRUNTIME_PROVIDERS", "DmlExecutionProvider", "Process")
            Write-Log -Message "NPU optimization environment configured" -Level SUCCESS -LogFile $LogFile
        }
        elseif ($hardware.GPU.Available -and $hardware.GPU.Type -eq "NVIDIA") {
            [Environment]::SetEnvironmentVariable("KOKORO_DEVICE", "cuda", "Process")
            [Environment]::SetEnvironmentVariable("WHISPER_DEVICE", "cuda", "Process")
            [Environment]::SetEnvironmentVariable("WAKE_WORD_ENGINE", "openWakeWord", "Process")
            Write-Log -Message "NVIDIA GPU optimization environment configured" -Level SUCCESS -LogFile $LogFile
        }
        else {
            [Environment]::SetEnvironmentVariable("KOKORO_DEVICE", "cpu", "Process")
            [Environment]::SetEnvironmentVariable("WHISPER_DEVICE", "cpu", "Process")
            [Environment]::SetEnvironmentVariable("WAKE_WORD_ENGINE", "openWakeWord", "Process")
            Write-Log -Message "CPU fallback environment configured" -Level SUCCESS -LogFile $LogFile
        }
        return $true
    }
    catch {
        Write-Log -Message "Voice environment configuration failed: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Update-FastAPIWithVoiceIntegration {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Integrating voice service with FastAPI backend..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path $mainPath)) {
        Write-Log -Message 'FastAPI main.py missing - ensure backend exists' -Level ERROR -LogFile $LogFile
        return $false
    }
    $mainContent = Get-Content $mainPath -Raw
    if ($mainContent -match 'voice_service' -and $mainContent -match [regex]::Escape($JARVIS_APP_VERSION)) {
        Write-Log -Message "FastAPI already integrated with voice service v$($JARVIS_APP_VERSION)" -Level INFO -LogFile $LogFile
        return $true
    }
    $backupPath = "${mainPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $mainPath $backupPath
    Write-Log -Message "Backed up existing main.py to: $backupPath" -Level INFO -LogFile $LogFile
    # Enhanced FastAPI with voice endpoints
    $fastApiCode = @"
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel
from datetime import datetime
import os
from dotenv import load_dotenv

# Import AI service and Voice service with graceful fallback
try:
    from services.ai_service import ai_service
except ImportError:
    ai_service = None

try:
    from services.voice_service import voice_service
except ImportError:
    voice_service = None

load_dotenv()
app = FastAPI(
    title='Jarvis AI Assistant',
    description='AI Assistant Backend API with Voice Integration',
    version='$JARVIS_APP_VERSION'
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)

class ChatMessage(BaseModel):
    content: str

class ChatResponse(BaseModel):
    response: str
    timestamp: str
    mode: str
    model: str

class TTSRequest(BaseModel):
    text: str
    voice: str = "af_heart"

@app.get('/')
async def root():
    vs = await voice_service.get_status() if voice_service else {"voice_stack": "unavailable"}
    return {
        'message': 'Jarvis AI Assistant Backend',
        'status': 'running',
        'version': '$JARVIS_APP_VERSION',
        'voice_stack': vs.get('voice_stack', 'unavailable'),
        'features': {
            'ai_chat': ai_service is not None,
            'voice_tts': vs.get('tts_available', False) if voice_service else False,
            'voice_stt': vs.get('whisper_available', False) if voice_service else False,
            'wake_word': vs.get('wake_word_available', False) if voice_service else False
        },
        'docs': '/docs'
    }

@app.get('/api/health')
async def health_check():
    vs = await voice_service.get_status() if voice_service else {}
    return {
        'status': 'healthy',
        'service': 'jarvis-backend',
        'version': '$JARVIS_APP_VERSION',
        'timestamp': datetime.now().isoformat(),
        'voice_integration': voice_service is not None,
        'voice_status': vs
    }

@app.post('/api/chat', response_model=ChatResponse)
async def chat(message: ChatMessage):
    if ai_service:
        result = await ai_service.generate_response(message.content)
        return ChatResponse(
            response=str(result.get('response', '')),
            timestamp=str(result.get('timestamp', datetime.now().isoformat())),
            mode=str(result.get('mode', 'echo')),
            model=str(result.get('model', 'fallback'))
        )
    
    response = f'Echo: {message.content}'
    return ChatResponse(
        response=response, 
        timestamp=datetime.now().isoformat(), 
        mode='echo', 
        model='fallback'
    )

@app.get('/api/status')
async def get_status():
    vs = await voice_service.get_status() if voice_service else {}
    ai_status = await ai_service.get_status() if ai_service else {}
    
    return {
        'backend': 'running',
        'version': '$JARVIS_APP_VERSION',
        'ai_available': ai_service is not None,
        'ai_service': ai_status,
        'voice_available': voice_service is not None,
        'voice_service': vs,
        'features': {
            'chat': True,
            'health_check': True,
            'voice_tts': vs.get('tts_available', False),
            'voice_stt': vs.get('whisper_available', False),
            'wake_word': vs.get('wake_word_available', False),
            'echo_mode': not ai_status.get('ai_available', False)
        }
    }

# Voice API Endpoints
@app.get('/api/voice/status')
async def voice_status():
    if not voice_service:
        raise HTTPException(status_code=503, detail="Voice service not available")
    return await voice_service.get_status()

@app.post('/api/voice/tts')
async def text_to_speech(request: TTSRequest):
    if not voice_service:
        raise HTTPException(status_code=503, detail="Voice service not available")
    
    audio_data = await voice_service.text_to_speech(request.text, request.voice)
    if audio_data:
        return Response(content=audio_data, media_type="audio/wav")
    raise HTTPException(status_code=500, detail="TTS generation failed")

@app.post('/api/voice/stt')
async def speech_to_text(audio: UploadFile = File(...)):
    if not voice_service:
        raise HTTPException(status_code=503, detail="Voice service not available")
    
    audio_data = await audio.read()
    text = await voice_service.speech_to_text(audio_data)
    return {"text": text if text else ""}

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=8000)
"@
    
    try {
        Set-Content -Path $mainPath -Value $fastApiCode -ErrorAction Stop
        Write-Log -Message 'FastAPI backend updated with modern voice integration' -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to update FastAPI backend: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-VoiceIntegrationTests {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating voice integration tests..." -Level INFO -LogFile $LogFile
    $voiceTests = @'
# tests/test_voice_integration.py - Modern Voice Integration Tests
import pytest
from fastapi.testclient import TestClient
from api.main import app

client = TestClient(app)

def test_root_with_voice():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["version"] == "2.3.0"
    assert "voice_stack" in data
    assert "features" in data

def test_health_check_with_voice():
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert "voice_integration" in data
    assert "voice_status" in data
    assert data["version"] == "2.3.0"

def test_voice_status_endpoint():
    response = client.get("/api/voice/status")
    # Should either work (200) or be unavailable (503)
    assert response.status_code in [200, 503]
    
    if response.status_code == 200:
        data = response.json()
        assert "voice_stack" in data
        assert "faster-whisper" in data.get("voice_stack", "")
        assert "kokoro" in data.get("voice_stack", "")
        assert "openWakeWord" in data.get("voice_stack", "")

def test_updated_status_endpoint():
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert data["version"] == "2.3.0"
    assert "voice_available" in data
    assert "voice_service" in data
    assert "features" in data

def test_tts_endpoint():
    response = client.post("/api/voice/tts", json={"text": "Hello world", "voice": "af_heart"})
    # Should either work (200) or be unavailable (503) - not 500 error
    assert response.status_code in [200, 503]
    
    if response.status_code == 200:
        # Should return audio data
        assert response.headers.get("content-type") == "audio/wav"

def test_modern_voice_stack_components():
    response = client.get("/api/voice/status")
    
    if response.status_code == 200:
        data = response.json()
        assert "models" in data
        if data.get("dependencies_available"):
            # Only test these if dependencies are available
            assert data["models"]["tts_model"] == "kokoro-82M"
            assert "whisper_model" in data["models"]
            assert "wake_words" in data
'@
    
    try {
        $testsDir = Join-Path $backendDir 'tests'
        if (-not (Test-Path $testsDir)) {
            New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
        }
        Set-Content -Path $testPath -Value $voiceTests -Encoding UTF8
        Write-Log -Message 'Voice integration tests created successfully' -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create voice integration tests: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Invoke-VoiceIntegrationTests {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Running voice integration tests..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path $testPath)) {
        Write-Log -Message "Voice integration test files not found" -Level ERROR -LogFile $LogFile
        return $false
    }
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "Virtual environment Python not found at $venvPy" -Level ERROR -LogFile $LogFile
        return $false
    }
    try {
        # Ensure pytest is available in the venv
        Write-Log -Message "Ensuring pytest is installed in virtual environment..." -Level INFO -LogFile $LogFile
        & $venvPy -m pip install pytest --quiet 2>&1 | Out-Null
        Write-Log -Message "Running pytest for voice integration..." -Level INFO -LogFile $LogFile
        Push-Location $backendDir
        try {
            $output = & $venvPy -m pytest "tests\test_voice_integration.py" -v --tb=short 2>&1
        }
        finally { Pop-Location }
        Write-Log -Message "Pytest output: $output" -Level INFO -LogFile $LogFile
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Voice integration tests passed" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Some voice integration tests failed" -Level WARN -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error running voice integration tests: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-VoiceValidationSummary {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Running comprehensive voice integration validation..." -Level INFO -LogFile $LogFile
    $validationResults = @()
    # File validation
    $requiredFiles = @(
        (Join-Path $backendDir "services\voice_service.py"),
        (Join-Path $projectRoot "jarvis_voice.json"),
        (Join-Path $backendDir "tests\test_voice_integration.py"),
        (Join-Path $backendDir "api\main.py")
    )
    foreach ($filePath in $requiredFiles) {
        $fileName = Split-Path $filePath -Leaf
        if (Test-Path $filePath) { $validationResults += "✅ File: $fileName" }
        else { $validationResults += "❌ Missing: $fileName" }
    }
    # Tool validation using existing Test-Tool function
    Write-Log -Message "Validating eSpeak-NG installation..." -Level INFO -LogFile $LogFile
    $espeakStatus = Test-Tool -Id "eSpeak-NG.eSpeak-NG" -Name "eSpeak-NG" -Command "espeak-ng" -LogFile $LogFile
    $checkmark = if ($espeakStatus) { '✅' } else { '❌' }
    $validationResults += "$checkmark System Tool: eSpeak-NG"
    # Python package validation - including python-multipart
    $pythonPackages = @("kokoro", "faster_whisper", "openwakeword", "sounddevice", "python-multipart")
    foreach ($package in $pythonPackages) {
        $status = $false
        if (Test-Path $venvPy) {
            try {
                & $venvPy -m pip show $package *>$null 2>&1
                $status = $LASTEXITCODE -eq 0
            }
            catch { $status = $false }
        }
        $checkmark = if ($status) { '✅' } else { '❌' }
        $validationResults += "$checkmark Python Package: $package"
    }
    # Configuration validation
    if (Test-Path $voiceConfigPath) {
        try {
            $configContent = Get-Content $voiceConfigPath -Raw | ConvertFrom-Json
            $stack = $configContent.voice_stack
            if ($stack -match "kokoro" -and $stack -match "faster-whisper" -and $stack -match "openWakeWord") {
                $validationResults += "✅ Voice Config: Modern stack (kokoro + faster-whisper + openWakeWord)"
            }
            else {
                $validationResults += "❌ Voice Config: Not modern stack"
            }
        }
        catch { $validationResults += "⚠️ Voice Config: File exists but may be malformed" }
    }
    
    # Environment validation
    $envValid = Test-EnvironmentConfig -LogFile $LogFile
    if ($envValid) {
        $validationResults += "✅ Environment Config: Valid"
    }
    else { $validationResults += "❌ Environment Config: Invalid or missing" }
    Write-Log -Message "=== VOICE INTEGRATION VALIDATION RESULTS ===" -Level INFO -LogFile $LogFile
    foreach ($result in $validationResults) {
        $level = if ($result -like "✅*") { "SUCCESS" } elseif ($result -like "⚠️*") { "WARN" } else { "ERROR" }
        Write-Log -Message $result -Level $level -LogFile $LogFile
    }
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    $summaryLevel = if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }
    Write-Log -Message "Voice Integration: $successCount/$($validationResults.Count) passed, $failureCount failed, $warningCount warnings" -Level $summaryLevel -LogFile $LogFile
    return $failureCount -eq 0
}

# -------------------------
# Main execution
# -------------------------

try {
    if (-not (Test-Prerequisites -LogFile $logFile)) {
        Stop-Transcript
        exit 1
    }
    
    $setupResults = @()
    
    if ($Install -or $Run) {
        Write-Log -Message "Installing modern voice dependencies and system tools..." -Level INFO -LogFile $logFile
        
        # Install system tools first
        Write-Log -Message "Installing eSpeak-NG system dependency..." -Level INFO -LogFile $logFile
        $espeakInstall = Install-Tool -Id "eSpeak-NG.eSpeak-NG" -Name "eSpeak-NG" -Command "espeak-ng" -LogFile $logFile
        if ($espeakInstall) {
            # Refresh PATH after installation
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 5
        }
        $setupResults += @{Name = "eSpeak-NG Installation"; Success = $espeakInstall }
        
        # Install Python voice dependencies
        $setupResults += @{Name = "Voice Python Dependencies"; Success = (Install-ModernVoiceDependencies -LogFile $logFile) }
    }
    
    if ($Configure -or $Run) {
        Write-Log -Message "Configuring modern voice integration..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Voice Configuration"; Success = (New-VoiceConfiguration -LogFile $logFile) }
        $setupResults += @{Name = "Voice Service Module"; Success = (New-ModernVoiceServiceModule -LogFile $logFile) }
        $setupResults += @{Name = "Voice Environment"; Success = (Set-VoiceEnvironment -LogFile $logFile) }
        $setupResults += @{Name = "FastAPI Voice Integration"; Success = (Update-FastAPIWithVoiceIntegration -LogFile $logFile) }
        $setupResults += @{Name = "Voice Test Creation"; Success = (New-VoiceIntegrationTests -LogFile $logFile) }
    }
    
    if ($Test -or $Run) {
        Write-Log -Message "Testing voice integration components..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Voice Integration Tests"; Success = (Invoke-VoiceIntegrationTests -LogFile $logFile) }
    }
    
    # Comprehensive validation
    Write-Log -Message "Running comprehensive validation..." -Level INFO -LogFile $logFile
    $validationSuccess = New-VoiceValidationSummary -LogFile $logFile
    
    # === FINAL RESULTS ===
    Write-Log -Message "=== FINAL RESULTS ===" -Level INFO -LogFile $logFile
    $successCount = ($setupResults | Where-Object { $_.Success }).Count
    $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
    Write-Log -Message "SUCCESS: $successCount components" -Level SUCCESS -LogFile $logFile
    if ($failCount -gt 0) { Write-Log -Message "FAILED: $failCount components" -Level ERROR -LogFile $logFile }
    foreach ($result in $setupResults) {
        $status = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }
        $level = if ($result.Success) { "SUCCESS" } else { "ERROR" }
        Write-Log -Message "$($result.Name): $status" -Level $level -LogFile $logFile
    }
    
    if (-not $validationSuccess) {
        Write-Log -Message "Voice configuration completed with issues - review logs for remediation steps" -Level WARN -LogFile $logFile
    }
    else {
        Write-Log -Message "Modern voice configuration completed successfully - all components validated" -Level SUCCESS -LogFile $logFile
    }
    
    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    if ($validationSuccess) {
        Write-Log -Message "1. Start backend: .\run_backend.ps1" -Level INFO -LogFile $logFile
        Write-Log -Message "2. Start frontend: .\run_frontend.ps1" -Level INFO -LogFile $logFile
        Write-Log -Message "3. Test voice APIs at: http://localhost:8000/api/voice/status" -Level INFO -LogFile $logFile
    }
    else {
        Write-Log -Message "1. Review error logs above for specific issues" -Level INFO -LogFile $logFile
        Write-Log -Message "2. Re-run this script with -Install flag after resolving issues" -Level INFO -LogFile $logFile
    }
    
    if ($failCount -gt 0) {
        Write-Log -Message "Voice setup had failures" -Level ERROR -LogFile $logFile
        Stop-Transcript
        exit 1
    }
}
catch {
    Write-Log -Message "Critical error during voice configuration: $($_.Exception.Message)" -Level ERROR -LogFile $logFile
    Write-Log -Message "Check PowerShell execution policy and administrator privileges." -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript