# 06-VoiceIntegration.ps1 (v1.0) - Voice Integration for JARVIS AI Assistant
# Adds speech recognition and text-to-speech capabilities to existing backend
# Uses speech_recognition + pyttsx3 for voice I/O, pvporcupine for wake-word detection

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$All
)

# Requires PowerShell 7+
#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# Dot-source shared utilities
. .\00-CommonUtils.ps1

# Setup logging
$projectRoot = Get-Location
$logsDir = Join-Path $projectRoot "logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptFile = Join-Path $logsDir "06-voice-integration-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "06-voice-integration-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile

# Test if backend exists
function Test-BackendExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    $exists = (Test-Path "backend/api/main.py") -and (Test-Path "backend/services/ai_service.py")
    if (-not $exists) {
        Write-Log -Message "Backend not found. Run scripts 02-03 first." -Level "ERROR" -LogFile $LogFile
    }
    return $exists
}

# Create voice service directory
function New-VoiceServiceStructure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating voice service structure..." -Level "INFO" -LogFile $LogFile
    $directories = @(
        "backend/services",
        "backend/audio",
        "backend/audio/cache"
    )
    
    return New-DirectoryStructure -Directories $directories -LogFile $LogFile
}

# Add voice dependencies to requirements.txt
function Add-VoiceDependencies {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Adding voice dependencies to requirements.txt..." -Level "INFO" -LogFile $LogFile
    $requirementsPath = "backend/requirements.txt"
    
    if (-not (Test-Path $requirementsPath)) {
        Write-Log -Message "Requirements.txt not found" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    $requirements = Get-Content $requirementsPath
    $voiceDeps = @(
        "",
        "# Voice Integration",
        "SpeechRecognition>=3.10.0",
        "pyttsx3>=2.90",
        "pyaudio>=0.2.13",
        "pvporcupine>=3.0.0",
        "webrtcvad>=2.0.10",
        "sounddevice>=0.4.6",
        "numpy>=1.24.0",
        "pocketsphinx>=5.0.0"
    )
    
    $added = $false
    foreach ($dep in $voiceDeps) {
        if ($dep -and $requirements -notcontains $dep -and -not ($requirements | Where-Object { $_ -like "$($dep.Split('>=')[0])*" })) {
            $requirements += $dep
            $added = $true
        }
    }
    
    if ($added) {
        try {
            Set-Content -Path $requirementsPath -Value $requirements -ErrorAction Stop
            Write-Log -Message "Voice dependencies added to requirements.txt" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        catch {
            Write-Log -Message "Failed to update requirements.txt: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
            return $false
        }
    }
    else {
        Write-Log -Message "Voice dependencies already present" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
}

# Create voice service module
function New-VoiceService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating voice service module..." -Level "INFO" -LogFile $LogFile
    $voiceServicePath = "backend/services/voice_service.py"
    
    $voiceService = @'
import speech_recognition as sr
import pyttsx3
import asyncio
import os
import json
import logging
import sounddevice as sd
import numpy as np
from typing import Optional, Dict, Any
from datetime import datetime
import threading
import queue
import time

logger = logging.getLogger(__name__)

class VoiceService:
    def __init__(self):
        # Speech recognition
        self.recognizer = sr.Recognizer()
        self.microphone = None
        
        # Text-to-speech
        self.tts_engine = None
        self.tts_queue = queue.Queue()
        self.tts_thread = None
        self.is_speaking = False
        
        # Wake word detection (placeholder for Porcupine)
        self.wake_word_enabled = False
        self.wake_words = ["jarvis", "hey jarvis"]
        
        # Audio settings
        self.sample_rate = 16000
        self.chunk_size = 1024
        
        # Voice configuration
        self.voice_config = self._load_voice_config()
        
        # Initialize components
        self._initialize_microphone()
        self._initialize_tts()
        self._start_tts_thread()
        
        logger.info("Voice service initialized")
    
    def _load_voice_config(self) -> Dict[str, Any]:
        """Load voice configuration from personality config"""
        config = {
            "voice_id": 0,  # Default voice
            "speech_rate": 180,  # Words per minute
            "volume": 0.9,
            "language": "en-US",
            "energy_threshold": 4000,
            "pause_threshold": 0.8,
            "phrase_threshold": 0.3,
            "non_speaking_duration": 0.5
        }
        
        # Try to load from jarvis_personality.json
        personality_paths = [
            "../../jarvis_personality.json",
            "../jarvis_personality.json",
            "jarvis_personality.json"
        ]
        
        for path in personality_paths:
            if os.path.exists(path):
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        personality = json.load(f)
                        if "voice_settings" in personality:
                            config.update(personality["voice_settings"])
                            logger.info(f"Loaded voice settings from {path}")
                            break
                except Exception as e:
                    logger.warning(f"Could not load voice settings from {path}: {e}")
        
        return config
    
    def _initialize_microphone(self):
        """Initialize microphone for speech recognition"""
        try:
            self.microphone = sr.Microphone(sample_rate=self.sample_rate)
            
            # Adjust for ambient noise
            with self.microphone as source:
                logger.info("Adjusting for ambient noise...")
                self.recognizer.adjust_for_ambient_noise(source, duration=1)
                self.recognizer.energy_threshold = self.voice_config["energy_threshold"]
                self.recognizer.pause_threshold = self.voice_config["pause_threshold"]
                self.recognizer.phrase_threshold = self.voice_config["phrase_threshold"]
                self.recognizer.non_speaking_duration = self.voice_config["non_speaking_duration"]
            
            logger.info("Microphone initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize microphone: {e}")
            self.microphone = None
    
    def _initialize_tts(self):
        """Initialize text-to-speech engine"""
        try:
            self.tts_engine = pyttsx3.init()
            
            # Configure voice
            voices = self.tts_engine.getProperty('voices')
            if voices and self.voice_config["voice_id"] < len(voices):
                self.tts_engine.setProperty('voice', voices[self.voice_config["voice_id"]].id)
            
            # Set properties
            self.tts_engine.setProperty('rate', self.voice_config["speech_rate"])
            self.tts_engine.setProperty('volume', self.voice_config["volume"])
            
            logger.info("TTS engine initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize TTS: {e}")
            self.tts_engine = None
    
    def _start_tts_thread(self):
        """Start background thread for TTS processing"""
        def tts_worker():
            while True:
                try:
                    text = self.tts_queue.get(timeout=0.1)
                    if text is None:  # Shutdown signal
                        break
                    
                    self.is_speaking = True
                    if self.tts_engine:
                        self.tts_engine.say(text)
                        self.tts_engine.runAndWait()
                    self.is_speaking = False
                    
                except queue.Empty:
                    continue
                except Exception as e:
                    logger.error(f"TTS error: {e}")
                    self.is_speaking = False
        
        self.tts_thread = threading.Thread(target=tts_worker, daemon=True)
        self.tts_thread.start()
    
    async def listen_for_speech(self, timeout: Optional[float] = None) -> Optional[str]:
        """Listen for speech and convert to text"""
        if not self.microphone:
            logger.error("Microphone not available")
            return None
        
        try:
            with self.microphone as source:
                logger.info("Listening...")
                
                # Use async to not block
                loop = asyncio.get_event_loop()
                audio = await loop.run_in_executor(
                    None,
                    lambda: self.recognizer.listen(source, timeout=timeout, phrase_time_limit=10)
                )
                
                logger.info("Processing speech...")
                
                # Try multiple recognition engines
                try:
                    # Google Speech Recognition (free, no API key)
                    text = await loop.run_in_executor(
                        None,
                        lambda: self.recognizer.recognize_google(audio, language=self.voice_config["language"])
                    )
                    logger.info(f"Recognized: {text}")
                    return text
                except sr.UnknownValueError:
                    logger.warning("Speech not understood")
                    return None
                except sr.RequestError as e:
                    logger.error(f"Recognition service error: {e}")
                    
                    # Fallback to offline recognition if available
                    try:
                        text = await loop.run_in_executor(
                            None,
                            lambda: self.recognizer.recognize_sphinx(audio)
                        )
                        logger.info(f"Recognized (offline): {text}")
                        return text
                    except:
                        return None
        
        except Exception as e:
            logger.error(f"Listen error: {e}")
            return None
    
    async def speak(self, text: str, wait: bool = False):
        """Convert text to speech"""
        if not self.tts_engine:
            logger.error("TTS engine not available")
            return
        
        # Clean text for speech
        text = text.strip()
        if not text:
            return
        
        logger.info(f"Speaking: {text[:50]}...")
        
        if wait:
            # Synchronous speaking
            self.is_speaking = True
            try:
                self.tts_engine.say(text)
                self.tts_engine.runAndWait()
            finally:
                self.is_speaking = False
        else:
            # Queue for async speaking
            self.tts_queue.put(text)
    
    def is_wake_word(self, text: str) -> bool:
        """Check if text contains wake word"""
        if not text:
            return False
        
        text_lower = text.lower()
        for wake_word in self.wake_words:
            if wake_word in text_lower:
                return True
        return False
    
    async def listen_for_wake_word(self, timeout: float = 30) -> bool:
        """Listen specifically for wake word"""
        logger.info("Listening for wake word...")
        text = await self.listen_for_speech(timeout=timeout)
        
        if text and self.is_wake_word(text):
            logger.info("Wake word detected!")
            return True
        return False
    
    def stop_speaking(self):
        """Stop current speech"""
        if self.tts_engine and self.is_speaking:
            self.tts_engine.stop()
            self.is_speaking = False
            # Clear the queue
            while not self.tts_queue.empty():
                try:
                    self.tts_queue.get_nowait()
                except:
                    break
    
    def get_available_voices(self) -> list:
        """Get list of available TTS voices"""
        if not self.tts_engine:
            return []
        
        voices = []
        for voice in self.tts_engine.getProperty('voices'):
            voices.append({
                "id": voice.id,
                "name": voice.name,
                "languages": getattr(voice, 'languages', []),
                "gender": getattr(voice, 'gender', 'unknown')
            })
        return voices
    
    def set_voice(self, voice_id: int):
        """Change TTS voice"""
        if not self.tts_engine:
            return
        
        voices = self.tts_engine.getProperty('voices')
        if voices and 0 <= voice_id < len(voices):
            self.tts_engine.setProperty('voice', voices[voice_id].id)
            self.voice_config["voice_id"] = voice_id
            logger.info(f"Voice changed to: {voices[voice_id].name}")
    
    def set_speech_rate(self, rate: int):
        """Set speech rate (words per minute)"""
        if self.tts_engine:
            self.tts_engine.setProperty('rate', rate)
            self.voice_config["speech_rate"] = rate
    
    def cleanup(self):
        """Cleanup resources"""
        logger.info("Cleaning up voice service...")
        
        # Stop TTS thread
        if self.tts_thread:
            self.tts_queue.put(None)  # Shutdown signal
            self.tts_thread.join(timeout=2)
        
        # Stop TTS engine
        if self.tts_engine:
            self.tts_engine.stop()
        
        logger.info("Voice service cleanup complete")

# Global instance
voice_service = VoiceService()
'@
    
    try {
        Set-Content -Path $voiceServicePath -Value $voiceService -ErrorAction Stop
        Write-Log -Message "Voice service module created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create voice service: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Update main.py to include voice endpoints
function Update-MainApplication {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating voice-enhanced main.py..." -Level "INFO" -LogFile $LogFile
    $mainPath = "backend/api/main.py"
    
    if (-not (Test-Path $mainPath)) {
        Write-Log -Message "Main application not found" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    # Check if already has voice integration
    $currentContent = Get-Content $mainPath -Raw
    if ($currentContent -match "voice_service" -and $currentContent -match "/api/voice/") {
        Write-Log -Message "Voice integration already present in main.py" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    
    # Create backup
    Copy-Item $mainPath "$mainPath.backup_voice" -Force
    
    # Create updated main.py with voice endpoints
    $updatedMain = @'
from fastapi import FastAPI, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
import os
from dotenv import load_dotenv
import logging
from services.ai_service import ai_service
from services.voice_service import voice_service
from typing import Optional

load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Jarvis AI Assistant",
    description="AI Assistant Backend with Voice Integration",
    version="1.2.0"
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

class VoiceCommand(BaseModel):
    command: str
    params: Optional[dict] = {}

class VoiceResponse(BaseModel):
    success: bool
    message: str
    data: Optional[dict] = None

@app.get("/")
async def root():
    return {
        "message": "Jarvis AI Assistant Backend",
        "status": "running",
        "version": "1.2.0",
        "features": ["chat", "ai_integration", "voice", "fallback_mode"],
        "docs": "/docs"
    }

@app.get("/api/health")
async def health_check():
    ai_status = await ai_service.get_status()
    return {
        "status": "healthy",
        "service": "jarvis-backend",
        "version": "1.2.0",
        "ai_integration": ai_status,
        "voice_enabled": voice_service.microphone is not None,
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
        "version": "1.2.0",
        "ai_service": ai_status,
        "voice_service": {
            "microphone_available": voice_service.microphone is not None,
            "tts_available": voice_service.tts_engine is not None,
            "is_speaking": voice_service.is_speaking
        },
        "features": {
            "chat": True,
            "ai_integration": ai_status["ai_available"],
            "voice_recognition": voice_service.microphone is not None,
            "text_to_speech": voice_service.tts_engine is not None,
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

# Voice endpoints
@app.post("/api/voice/listen")
async def voice_listen():
    """Listen for voice input and convert to text"""
    try:
        text = await voice_service.listen_for_speech(timeout=10)
        if text:
            return VoiceResponse(
                success=True,
                message="Speech recognized",
                data={"text": text, "timestamp": datetime.now().isoformat()}
            )
        return VoiceResponse(
            success=False,
            message="No speech detected or not understood"
        )
    except Exception as e:
        logger.error(f"Voice listen error: {e}")
        return VoiceResponse(
            success=False,
            message=f"Voice recognition error: {str(e)}"
        )

@app.post("/api/voice/speak")
async def voice_speak(message: ChatMessage, background_tasks: BackgroundTasks):
    """Convert text to speech"""
    try:
        # Add to background task for async speaking
        background_tasks.add_task(voice_service.speak, message.content)
        
        return VoiceResponse(
            success=True,
            message="Speaking text",
            data={"text": message.content, "timestamp": datetime.now().isoformat()}
        )
    except Exception as e:
        logger.error(f"Voice speak error: {e}")
        return VoiceResponse(
            success=False,
            message=f"Text-to-speech error: {str(e)}"
        )

@app.post("/api/voice/stop")
async def voice_stop():
    """Stop current speech"""
    try:
        voice_service.stop_speaking()
        return VoiceResponse(success=True, message="Speech stopped")
    except Exception as e:
        return VoiceResponse(success=False, message=f"Error: {str(e)}")

@app.get("/api/voice/status")
async def voice_status():
    """Get voice service status"""
    return {
        "microphone_available": voice_service.microphone is not None,
        "tts_available": voice_service.tts_engine is not None,
        "is_speaking": voice_service.is_speaking,
        "wake_words": voice_service.wake_words,
        "voice_config": voice_service.voice_config,
        "available_voices": voice_service.get_available_voices()
    }

@app.post("/api/voice/wake")
async def listen_wake_word():
    """Listen for wake word"""
    try:
        detected = await voice_service.listen_for_wake_word(timeout=30)
        return VoiceResponse(
            success=detected,
            message="Wake word detected" if detected else "Wake word not detected"
        )
    except Exception as e:
        return VoiceResponse(success=False, message=f"Error: {str(e)}")

@app.post("/api/voice/configure")
async def configure_voice(config: VoiceCommand):
    """Configure voice settings"""
    try:
        params = config.params
        
        if "voice_id" in params:
            voice_service.set_voice(params["voice_id"])
        
        if "speech_rate" in params:
            voice_service.set_speech_rate(params["speech_rate"])
        
        if "wake_words" in params:
            voice_service.wake_words = params["wake_words"]
        
        return VoiceResponse(
            success=True,
            message="Voice configuration updated",
            data={"config": voice_service.voice_config}
        )
    except Exception as e:
        return VoiceResponse(success=False, message=f"Configuration error: {str(e)}")

# Combined voice + AI endpoint
@app.post("/api/voice/chat")
async def voice_chat(background_tasks: BackgroundTasks):
    """Complete voice interaction: listen -> AI -> speak"""
    try:
        # Listen for user input
        user_text = await voice_service.listen_for_speech(timeout=10)
        if not user_text:
            error_msg = "I didn't catch that. Could you please repeat?"
            background_tasks.add_task(voice_service.speak, error_msg)
            return VoiceResponse(
                success=False,
                message="No speech detected",
                data={"spoken_response": error_msg}
            )
        
        # Get AI response
        ai_response = await ai_service.generate_response(user_text)
        response_text = ai_response["response"]
        
        # Speak the response
        background_tasks.add_task(voice_service.speak, response_text)
        
        return VoiceResponse(
            success=True,
            message="Voice chat completed",
            data={
                "user_text": user_text,
                "ai_response": response_text,
                "mode": ai_response["mode"],
                "model": ai_response["model"],
                "timestamp": ai_response["timestamp"]
            }
        )
    except Exception as e:
        logger.error(f"Voice chat error: {e}")
        error_msg = "I'm having trouble with voice interaction right now."
        background_tasks.add_task(voice_service.speak, error_msg)
        return VoiceResponse(
            success=False,
            message=f"Voice chat error: {str(e)}",
            data={"spoken_response": error_msg}
        )

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    voice_service.cleanup()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
'@
    
    try {
        Set-Content -Path $mainPath -Value $updatedMain -ErrorAction Stop
        Write-Log -Message "Main application updated with voice endpoints" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to update main application: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Create voice integration tests
function New-VoiceIntegrationTests {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating voice integration tests..." -Level "INFO" -LogFile $LogFile
    $testPath = "backend/tests/test_voice_integration.py"
    
    $voiceTests = @'
import pytest
from fastapi.testclient import TestClient
from api.main import app

client = TestClient(app)

def test_voice_endpoints_exist():
    """Test that voice endpoints are available"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "voice" in data["features"]

def test_voice_status():
    """Test voice status endpoint"""
    response = client.get("/api/voice/status")
    assert response.status_code == 200
    data = response.json()
    assert "microphone_available" in data
    assert "tts_available" in data
    assert "is_speaking" in data

def test_voice_speak():
    """Test text-to-speech endpoint"""
    response = client.post("/api/voice/speak", json={"content": "Test message"})
    assert response.status_code == 200
    data = response.json()
    assert data["success"] in [True, False]  # Depends on TTS availability

def test_voice_listen():
    """Test speech recognition endpoint"""
    response = client.post("/api/voice/listen")
    assert response.status_code == 200
    data = response.json()
    assert "success" in data
    assert "message" in data

def test_voice_stop():
    """Test stop speech endpoint"""
    response = client.post("/api/voice/stop")
    assert response.status_code == 200
    data = response.json()
    assert "success" in data

def test_voice_configure():
    """Test voice configuration endpoint"""
    response = client.post("/api/voice/configure", json={
        "command": "configure",
        "params": {"speech_rate": 200}
    })
    assert response.status_code == 200
    data = response.json()
    assert "success" in data

def test_health_includes_voice():
    """Test that health check includes voice status"""
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert "voice_enabled" in data

def test_status_includes_voice():
    """Test that status includes voice service info"""
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert "voice_service" in data
    assert "voice_recognition" in data["features"]
    assert "text_to_speech" in data["features"]
'@
    
    try {
        Set-Content -Path $testPath -Value $voiceTests -ErrorAction Stop
        Write-Log -Message "Voice integration tests created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create voice tests: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Install voice dependencies
function Install-VoiceDependencies {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Installing voice integration dependencies..." -Level "INFO" -LogFile $LogFile
    
    # Core voice packages
    $packages = @(
        "SpeechRecognition",
        "pyttsx3",
        "pyaudio",
        "sounddevice",
        "numpy",
        "webrtcvad",
        "pocketsphinx"
    )
    
    $successCount = 0
    foreach ($package in $packages) {
        if (Install-PythonPackage -PackageName $package -LogFile $LogFile) {
            $successCount++
        }
    }
    
    # Try to install pvporcupine (may fail on some systems)
    Write-Log -Message "Installing wake word detection (optional)..." -Level "INFO" -LogFile $LogFile
    Install-PythonPackage -PackageName "pvporcupine" -LogFile $LogFile | Out-Null
    
    if ($successCount -eq $packages.Count) {
        Write-Log -Message "All voice dependencies installed successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    
    Write-Log -Message "Some voice dependencies failed ($successCount/$($packages.Count))" -Level "WARN" -LogFile $LogFile
    return $successCount -gt 3  # At least core packages
}

# Test voice hardware
function Test-VoiceHardware {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Testing voice hardware..." -Level "INFO" -LogFile $LogFile
    
    Push-Location
    try {
        Set-Location backend
        
        $pythonCmd = Get-PythonCommand -LogFile $LogFile
        if (-not $pythonCmd) {
            Write-Log -Message "No Python command found" -Level "ERROR" -LogFile $LogFile
            return $false
        }
        
        # Test microphone
        Write-Log -Message "Testing microphone..." -Level "INFO" -LogFile $LogFile
        $micTest = @"
import speech_recognition as sr
import sys

try:
    r = sr.Recognizer()
    with sr.Microphone() as source:
        print("Microphone detected!")
        r.adjust_for_ambient_noise(source, duration=1)
        print(f"Energy threshold: {r.energy_threshold}")
        sys.exit(0)
except Exception as e:
    print(f"Microphone error: {e}")
    sys.exit(1)
"@
        
        $micTestResult = $micTest | & $pythonCmd 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Microphone test passed" -Level "SUCCESS" -LogFile $LogFile
            Write-Log -Message "Output: $micTestResult" -Level "INFO" -LogFile $LogFile
        }
        else {
            Write-Log -Message "Microphone test failed: $micTestResult" -Level "ERROR" -LogFile $LogFile
        }
        
        # Test TTS
        Write-Log -Message "Testing text-to-speech..." -Level "INFO" -LogFile $LogFile
        $ttsTest = @"
import pyttsx3
import sys

try:
    engine = pyttsx3.init()
    voices = engine.getProperty('voices')
    print(f"TTS initialized with {len(voices)} voices available")
    
    # List voices
    for i, voice in enumerate(voices):
        print(f"Voice {i}: {voice.name}")
    
    # Test speak (won't actually speak in test)
    engine.save_to_file("Test", "test.wav")
    engine.runAndWait()
    
    import os
    if os.path.exists("test.wav"):
        os.remove("test.wav")
        print("TTS test successful")
        sys.exit(0)
    else:
        print("TTS test failed - no output file")
        sys.exit(1)
except Exception as e:
    print(f"TTS error: {e}")
    sys.exit(1)
"@
        
        $ttsTestResult = $ttsTest | & $pythonCmd 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "TTS test passed" -Level "SUCCESS" -LogFile $LogFile
            Write-Log -Message "Output: $ttsTestResult" -Level "INFO" -LogFile $LogFile
        }
        else {
            Write-Log -Message "TTS test failed: $ttsTestResult" -Level "ERROR" -LogFile $LogFile
        }
        
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        Write-Log -Message "Voice hardware test error: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    finally {
        Pop-Location
    }
}

# Run voice integration tests
function Invoke-VoiceIntegrationTests {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Running voice integration tests..." -Level "INFO" -LogFile $LogFile
    
    if (-not (Test-Path "backend/tests/test_voice_integration.py")) {
        Write-Log -Message "Voice test files not found" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    try {
        Push-Location backend
        $pythonCmd = Get-PythonCommand -LogFile $LogFile
        if (-not $pythonCmd) {
            Write-Log -Message "No Python command found for running tests" -Level "ERROR" -LogFile $LogFile
            return $false
        }
        
        Write-Log -Message "Executing voice integration tests..." -Level "INFO" -LogFile $LogFile
        & $pythonCmd -m pytest tests/test_voice_integration.py -v
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "All voice integration tests passed" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        
        Write-Log -Message "Some voice tests failed (exit code: $LASTEXITCODE)" -Level "WARN" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Exception during voice test execution: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    finally {
        Pop-Location
    }
}

# Update personality.json with voice settings
function Update-PersonalityConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Updating personality configuration with voice settings..." -Level "INFO" -LogFile $LogFile
    $personalityPath = "jarvis_personality.json"
    
    if (-not (Test-Path $personalityPath)) {
        Write-Log -Message "Personality config not found" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    try {
        $personality = Get-Content $personalityPath -Raw | ConvertFrom-Json
        
        # Add voice settings if not present
        if (-not $personality.PSObject.Properties['voice_settings']) {
            $voiceSettings = [PSCustomObject]@{
                "_comment"              = "Voice configuration for TTS and speech recognition"
                "voice_id"              = 0
                "speech_rate"           = 180
                "volume"                = 0.9
                "language"              = "en-US"
                "energy_threshold"      = 4000
                "pause_threshold"       = 0.8
                "phrase_threshold"      = 0.3
                "non_speaking_duration" = 0.5
                "wake_words"            = @("jarvis", "hey jarvis")
            }
            
            $voiceResponses = [PSCustomObject]@{
                "_comment"      = "Special responses for voice interactions"
                "wake_response" = "Yes sir, how may I assist you?"
                "listening"     = "I'm listening..."
                "thinking"      = "Let me think about that..."
                "error_speech"  = "I apologize, I didn't catch that. Could you please repeat?"
                "error_tts"     = "I'm having trouble with my voice systems at the moment."
            }
            
            $personality | Add-Member -MemberType NoteProperty -Name "voice_settings" -Value $voiceSettings -Force
            $personality | Add-Member -MemberType NoteProperty -Name "voice_responses" -Value $voiceResponses -Force
            
            $updatedJson = $personality | ConvertTo-Json -Depth 10
            Set-Content -Path $personalityPath -Value $updatedJson
            
            Write-Log -Message "Added voice settings to personality configuration" -Level "SUCCESS" -LogFile $LogFile
        }
        else {
            Write-Log -Message "Voice settings already present in personality config" -Level "SUCCESS" -LogFile $LogFile
        }
        
        return $true
    }
    catch {
        Write-Log -Message "Failed to update personality config: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Create voice demo script
function New-VoiceDemoScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating voice demo script..." -Level "INFO" -LogFile $LogFile
    
    $demoScript = @'
# test_voice.ps1 - Voice Integration Test Script
param(
    [switch]$TestMic,
    [switch]$TestTTS,
    [switch]$TestAPI,
    [switch]$Interactive
)

Write-Host "JARVIS Voice Integration Test" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan

$baseUrl = "http://localhost:8000"

if ($TestMic) {
    Write-Host "`nTesting Microphone..." -ForegroundColor Yellow
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/api/voice/listen" -Method Post -TimeoutSec 15
        if ($response.success) {
            Write-Host "✓ Microphone working! Recognized: $($response.data.text)" -ForegroundColor Green
        } else {
            Write-Host "✗ No speech detected: $($response.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ Microphone test failed: $_" -ForegroundColor Red
    }
}

if ($TestTTS) {
    Write-Host "`nTesting Text-to-Speech..." -ForegroundColor Yellow
    try {
        $body = @{content = "Hello, I am Jarvis, your AI assistant. Voice systems are operational."} | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "$baseUrl/api/voice/speak" -Method Post -Body $body -ContentType "application/json"
        if ($response.success) {
            Write-Host "✓ TTS working! Speaking text..." -ForegroundColor Green
            Start-Sleep -Seconds 3
        } else {
            Write-Host "✗ TTS failed: $($response.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ TTS test failed: $_" -ForegroundColor Red
    }
}

if ($TestAPI) {
    Write-Host "`nTesting Voice API Endpoints..." -ForegroundColor Yellow
    
    # Get voice status
    try {
        $status = Invoke-RestMethod -Uri "$baseUrl/api/voice/status"
        Write-Host "Voice Status:" -ForegroundColor Cyan
        Write-Host "  Microphone: $(if ($status.microphone_available) { '✓' } else { '✗' })" -ForegroundColor $(if ($status.microphone_available) { 'Green' } else { 'Red' })
        Write-Host "  TTS Engine: $(if ($status.tts_available) { '✓' } else { '✗' })" -ForegroundColor $(if ($status.tts_available) { 'Green' } else { 'Red' })
        Write-Host "  Available Voices: $($status.available_voices.Count)" -ForegroundColor White
        Write-Host "  Wake Words: $($status.wake_words -join ', ')" -ForegroundColor White
    } catch {
        Write-Host "✗ Failed to get voice status: $_" -ForegroundColor Red
    }
}

if ($Interactive) {
    Write-Host "`nStarting Interactive Voice Test..." -ForegroundColor Yellow
    Write-Host "Say 'Jarvis' to activate, then speak your message." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to exit." -ForegroundColor Gray
    
    while ($true) {
        try {
            Write-Host "`nListening for wake word..." -ForegroundColor Gray
            $wake = Invoke-RestMethod -Uri "$baseUrl/api/voice/wake" -Method Post -TimeoutSec 35
            
            if ($wake.success) {
                Write-Host "✓ Wake word detected!" -ForegroundColor Green
                
                # Voice chat
                Write-Host "Processing voice chat..." -ForegroundColor Cyan
                $chat = Invoke-RestMethod -Uri "$baseUrl/api/voice/chat" -Method Post -TimeoutSec 30
                
                if ($chat.success) {
                    Write-Host "You said: $($chat.data.user_text)" -ForegroundColor Yellow
                    Write-Host "Jarvis: $($chat.data.ai_response)" -ForegroundColor Cyan
                } else {
                    Write-Host "Voice chat failed: $($chat.message)" -ForegroundColor Red
                }
            }
        } catch {
            if ($_.Exception.Message -like "*operation was canceled*") {
                Write-Host "`nExiting interactive mode." -ForegroundColor Yellow
                break
            }
            Write-Host "Error: $_" -ForegroundColor Red
        }
        
        Start-Sleep -Seconds 1
    }
}

if (-not ($TestMic -or $TestTTS -or $TestAPI -or $Interactive)) {
    Write-Host "`nUsage:" -ForegroundColor Yellow
    Write-Host "  .\test_voice.ps1 -TestMic      # Test microphone" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -TestTTS      # Test text-to-speech" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -TestAPI      # Test API endpoints" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -Interactive  # Interactive voice mode" -ForegroundColor Gray
    Write-Host "  .\test_voice.ps1 -TestMic -TestTTS -TestAPI  # Run all tests" -ForegroundColor Gray
}
'@
    
    try {
        Set-Content -Path "test_voice.ps1" -Value $demoScript -ErrorAction Stop
        Write-Log -Message "Voice demo script created: test_voice.ps1" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create demo script: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Validate voice integration setup
function Test-VoiceIntegrationSetup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Validating voice integration setup..." -Level "INFO" -LogFile $LogFile
    $validationResults = @()
    
    # Check files
    $requiredFiles = @(
        "backend/services/voice_service.py",
        "backend/api/main.py",
        "backend/tests/test_voice_integration.py",
        "test_voice.ps1"
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
    
    # Check Python packages
    $voicePackages = @("SpeechRecognition", "pyttsx3", "pyaudio", "sounddevice", "numpy", "webrtcvad", "pocketsphinx")
    foreach ($package in $voicePackages) {
        $status = Test-PythonPackageInstalled -PackageName $package -LogFile $LogFile
        if ($status) {
            $validationResults += "✅ Python Package: $package"
        }
        else {
            $validationResults += "❌ Python Package: $package"
        }
    }
    
    # Check main.py has voice endpoints
    if (Test-Path "backend/api/main.py") {
        $mainContent = Get-Content "backend/api/main.py" -Raw
        if ($mainContent -match "voice_service" -and $mainContent -match "/api/voice/") {
            $validationResults += "✅ Backend: Voice endpoints integrated"
        }
        else {
            $validationResults += "❌ Backend: Voice endpoints missing"
        }
    }
    
    # Check personality config
    if (Test-Path "jarvis_personality.json") {
        try {
            $personality = Get-Content "jarvis_personality.json" -Raw | ConvertFrom-Json
            if ($personality.PSObject.Properties['voice_settings']) {
                $validationResults += "✅ Personality: Voice settings configured"
            }
            else {
                $validationResults += "⚠️  Personality: Voice settings not configured"
            }
        }
        catch {
            $validationResults += "⚠️  Personality: Error reading config"
        }
    }
    
    # Display results
    Write-Log -Message "=== VOICE INTEGRATION VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $validationResults) {
        $level = if ($result -like "✅*") { "SUCCESS" } 
        elseif ($result -like "⚠️*") { "WARN" }
        else { "ERROR" }
        Write-Log -Message $result -Level $level -LogFile $LogFile
    }
    
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    
    Write-Log -Message "Voice Integration: $successCount/$($validationResults.Count) passed, $failureCount failed, $warningCount warnings" -Level ($failureCount -eq 0 ? "SUCCESS" : "ERROR") -LogFile $LogFile
    
    return $failureCount -eq 0
}

# Main execution
Write-Log -Message "JARVIS Voice Integration Setup (v1.0) Starting..." -Level "SUCCESS" -LogFile $logFile
Write-SystemInfo -ScriptName "06-VoiceIntegration.ps1" -Version "1.0" -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Install   = $Install
    Configure = $Configure
    Test      = $Test
    All       = $All
}

if (-not (Test-BackendExists -LogFile $logFile)) {
    Stop-Transcript
    exit 1
}

$setupResults = @()

# Always setup structure and files
Write-Log -Message "Setting up voice integration components..." -Level "INFO" -LogFile $logFile
$setupResults += @{Name = "Voice Service Structure"; Success = (New-VoiceServiceStructure -LogFile $logFile) }
$setupResults += @{Name = "Voice Dependencies"; Success = (Add-VoiceDependencies -LogFile $logFile) }
$setupResults += @{Name = "Voice Service Module"; Success = (New-VoiceService -LogFile $logFile) }
$setupResults += @{Name = "Backend Integration"; Success = (Update-MainApplication -LogFile $logFile) }
$setupResults += @{Name = "Voice Tests"; Success = (New-VoiceIntegrationTests -LogFile $logFile) }
$setupResults += @{Name = "Demo Script"; Success = (New-VoiceDemoScript -LogFile $logFile) }

if ($Configure -or $All) {
    Write-Log -Message "Configuring voice settings..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "Personality Config"; Success = (Update-PersonalityConfig -LogFile $logFile) }
}

if ($Install -or $All) {
    Write-Log -Message "Installing voice dependencies..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "Python Packages"; Success = (Install-VoiceDependencies -LogFile $logFile) }
}

if ($Test -or $All) {
    Write-Log -Message "Testing voice integration..." -Level "INFO" -LogFile $logFile
    if (Test-PythonPackageInstalled -PackageName "SpeechRecognition" -LogFile $logFile) {
        $setupResults += @{Name = "Voice Hardware"; Success = (Test-VoiceHardware -LogFile $logFile) }
        $setupResults += @{Name = "Integration Tests"; Success = (Invoke-VoiceIntegrationTests -LogFile $logFile) }
    }
    else {
        Write-Log -Message "Skipping tests - dependencies not installed (use -Install flag)" -Level "WARN" -LogFile $logFile
    }
}

# Summary
Write-Log -Message "=== SETUP SUMMARY ===" -Level "INFO" -LogFile $logFile
$successfulSetups = ($setupResults | Where-Object { $_.Success }).Count
$failedSetups = ($setupResults | Where-Object { -not $_.Success }).Count

foreach ($result in $setupResults) {
    $status = if ($result.Success) { "SUCCESS" } else { "FAILED" }
    Write-Log -Message "$($result.Name) - $status" -Level $status -LogFile $logFile
}

Write-Log -Message "Setup Results: $successfulSetups successful, $failedSetups failed" -Level "INFO" -LogFile $logFile

# Validation
Test-VoiceIntegrationSetup -LogFile $logFile | Out-Null

# Next steps
if (-not ($Install -or $Configure -or $Test -or $All)) {
    Write-Log -Message "=== NEXT STEPS ===" -Level "INFO" -LogFile $logFile
    Write-Log -Message "1. .\06-VoiceIntegration.ps1 -Install    # Install Python packages" -Level "INFO" -LogFile $logFile
    Write-Log -Message "2. .\06-VoiceIntegration.ps1 -Configure  # Update configurations" -Level "INFO" -LogFile $logFile
    Write-Log -Message "3. .\06-VoiceIntegration.ps1 -Test       # Test voice hardware" -Level "INFO" -LogFile $logFile
    Write-Log -Message "Or run with: .\06-VoiceIntegration.ps1 -All" -Level "INFO" -LogFile $logFile
}

Write-Log -Message "=== VOICE USAGE ===" -Level "INFO" -LogFile $logFile
Write-Log -Message "Test voice features:" -Level "INFO" -LogFile $logFile
Write-Log -Message "1. Start backend: .\run_backend.ps1" -Level "INFO" -LogFile $logFile
Write-Log -Message "2. Test voice: .\test_voice.ps1 -TestMic -TestTTS" -Level "INFO" -LogFile $logFile
Write-Log -Message "3. Interactive mode: .\test_voice.ps1 -Interactive" -Level "INFO" -LogFile $logFile

Write-Log -Message "Voice API endpoints:" -Level "INFO" -LogFile $logFile
Write-Log -Message "- POST /api/voice/listen   # Speech to text" -Level "INFO" -LogFile $logFile
Write-Log -Message "- POST /api/voice/speak    # Text to speech" -Level "INFO" -LogFile $logFile
Write-Log -Message "- POST /api/voice/chat     # Complete voice interaction" -Level "INFO" -LogFile $logFile
Write-Log -Message "- GET  /api/voice/status   # Voice system status" -Level "INFO" -LogFile $logFile

if ($failedSetups -gt 0) {
    Write-Log -Message "Some components failed. Check logs for details." -Level "WARN" -LogFile $logFile
}

Write-Log -Message "Log Files Created:" -Level "INFO" -LogFile $logFile
Write-Log -Message "Full transcript: $transcriptFile" -Level "INFO" -LogFile $logFile
Write-Log -Message "Structured log: $logFile" -Level "INFO" -LogFile $logFile

Write-Log -Message "JARVIS Voice Integration Setup (v1.0) Complete!" -Level "SUCCESS" -LogFile $logFile

Stop-Transcript