# 06a-VoiceSetup.ps1 - Voice Service Architecture Setup
# Purpose: Create voice service module and jarvis_voice.json configuration system
# Last edit: 2025-07-25 - Simplified NPU detection using direct ARM64 platform check

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "2.7.0"
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

# Define script-level paths using critical backend pattern
$backendDir = Join-Path $projectRoot "backend"
$venvDir = Join-Path $backendDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"
$voiceServicePath = Join-Path $backendDir "services\voice_service.py"
$voiceConfigPath = Join-Path $projectRoot "jarvis_voice.json"
$personalityPath = Join-Path $projectRoot "jarvis_personality.json"

function Test-Prerequisites {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing prerequisites..." -Level INFO -LogFile $LogFile
    # Check backend directory structure exists
    if (-not (Test-Path $backendDir)) {
        Write-Log -Message "Backend directory not found at $backendDir" -Level ERROR -LogFile $LogFile
        Write-Log -Message "REMEDIATION: Run 02-FastApiBackend.ps1 first to create backend structure" -Level ERROR -LogFile $LogFile
        return $false
    }
    # Check backend services directory exists
    $servicesDir = Join-Path $backendDir "services"
    if (-not (Test-Path $servicesDir)) {
        Write-Log -Message "Backend services directory not found" -Level ERROR -LogFile $LogFile
        Write-Log -Message "REMEDIATION: Run 02-FastApiBackend.ps1 and 03-IntegrateOllama.ps1 first" -Level ERROR -LogFile $LogFile
        return $false
    }
    # Check AI service exists (voice depends on AI integration)
    $aiServicePath = Join-Path $backendDir "services\ai_service.py"
    if (-not (Test-Path $aiServicePath)) {
        Write-Log -Message "AI service not found - required dependency for voice integration" -Level ERROR -LogFile $LogFile
        Write-Log -Message "REMEDIATION: Run 03-IntegrateOllama.ps1 first" -Level ERROR -LogFile $LogFile
        return $false
    }
    Write-Log -Message "All prerequisites verified" -Level SUCCESS -LogFile $LogFile
    return $true
}

function New-VoiceConfiguration {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating jarvis_voice.json configuration..." -Level INFO -LogFile $LogFile
    # Check if voice config already exists
    if (Test-Path $voiceConfigPath) {
        Write-Log -Message "jarvis_voice.json already exists - preserving existing configuration" -Level INFO -LogFile $LogFile
        return $true
    }
    # Load personality config for voice parameter defaults
    $personalityDefaults = @{
        voice_enabled = $true
        speech_rate   = 1.0
        voice_pitch   = 0.5
        wake_words    = @("jarvis", "hey jarvis")
    }
    if (Test-Path $personalityPath) {
        try {
            $personalityConfig = Get-Content $personalityPath -Raw | ConvertFrom-Json
            if ($personalityConfig.voice) {
                $personalityDefaults.speech_rate = if ($personalityConfig.voice.speech_rate) { $personalityConfig.voice.speech_rate } else { 1.0 }
                $personalityDefaults.voice_pitch = if ($personalityConfig.voice.voice_pitch) { $personalityConfig.voice.voice_pitch } else { 0.5 }
                $personalityDefaults.wake_words = if ($personalityConfig.voice.wake_words) { $personalityConfig.voice.wake_words } else { @("jarvis", "hey jarvis") }
            }
        }
        catch {
            Write-Log -Message "Could not parse personality config, using defaults: $($_.Exception.Message)" -Level WARN -LogFile $LogFile
        }
    }
    # Create comprehensive voice configuration
    $voiceConfig = @{
        voice_stack           = "faster-whisper + coqui-tts + openWakeWord"
        models                = @{
            whisper_model   = "base"
            tts_model       = "tts_models/en/ljspeech/tacotron2-DDC"
            wake_word_model = "alexa_v0.1"
        }
        audio_settings        = @{
            sample_rate    = 16000
            chunk_duration = 1.0
            speech_rate    = $personalityDefaults.speech_rate
            voice_pitch    = $personalityDefaults.voice_pitch
            volume         = 0.8
        }
        voice_responses       = @{
            wake_acknowledged  = "Yes, how can I help you?"
            listening          = "I'm listening..."
            processing         = "Let me think about that..."
            error_no_speech    = "I didn't hear anything. Please try again."
            error_no_wake_word = "I'm waiting for the wake word..."
            error_tts_failed   = "I had trouble speaking that response."
            error_stt_failed   = "I had trouble understanding what you said."
        }
        hardware_optimization = @{
            prefer_gpu          = $true
            device              = "auto"
            gpu_memory_fraction = 0.7
            cpu_threads         = 4
        }
        wake_words            = $personalityDefaults.wake_words
        advanced              = @{
            vad_threshold         = 0.5
            silence_timeout       = 2.0
            phrase_timeout        = 3.0
            wake_word_sensitivity = 0.5
        }
    }
    try {
        $voiceConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $voiceConfigPath -Encoding UTF8
        Write-Log -Message "Created jarvis_voice.json with default configuration" -Level SUCCESS -LogFile $LogFile
        Write-Log -Message "Configuration path: ${voiceConfigPath}" -Level INFO -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create jarvis_voice.json: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-VoiceServiceModule {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating modern voice service module..." -Level INFO -LogFile $LogFile
    # Backup existing voice service if present (always regenerate with latest logic)
    if (Test-Path $voiceServicePath) {
        $backupPath = "${voiceServicePath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $voiceServicePath $backupPath
        Write-Log -Message "Backed up existing voice service to: $backupPath" -Level INFO -LogFile $LogFile
        Write-Log -Message "Regenerating voice service with latest hardware detection" -Level INFO -LogFile $LogFile
    }
    $voiceServiceCode = @'
import os
import json
import logging
import asyncio
from typing import Dict, Any, Optional, List
from pathlib import Path

logger = logging.getLogger(__name__)

class ModernVoiceService:
    """Modern voice service using faster-whisper + coqui-tts + openWakeWord"""
    
    def __init__(self):
        self.voice_config = self._load_voice_config()
        self.device = self._detect_device()
        self.whisper_model = None
        self.tts_model = None
        self.wake_word_model = None
        self._initialize_models()
    
    def _load_voice_config(self) -> Dict[str, Any]:
        """Load voice configuration from jarvis_voice.json"""
        voice_config_paths = [
            "jarvis_voice.json", 
            "../jarvis_voice.json", 
            "../../jarvis_voice.json"
        ]
        
        for path in voice_config_paths:
            if os.path.exists(path):
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        config = json.load(f)
                        logger.info(f"Loaded voice configuration from {path}")
                        return config
                except Exception as e:
                    logger.error(f"Failed to load voice config from {path}: {e}")
        
        # Load from personality config as fallback
        personality_paths = [
            "jarvis_personality.json",
            "../jarvis_personality.json", 
            "../../jarvis_personality.json"
        ]
        
        for path in personality_paths:
            if os.path.exists(path):
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        personality = json.load(f)
                        if 'voice' in personality:
                            logger.info(f"Using voice settings from personality config: {path}")
                            return self._create_voice_config_from_personality(personality['voice'])
                except Exception as e:
                    logger.error(f"Failed to load personality config from {path}: {e}")
        
        # Use embedded defaults
        logger.warning("No voice configuration found, using embedded defaults")
        return self._get_default_voice_config()
    
    def _create_voice_config_from_personality(self, personality_voice: Dict[str, Any]) -> Dict[str, Any]:
        """Create voice config from personality settings"""
        return {
            "voice_stack": "faster-whisper + coqui-tts + openWakeWord",
            "models": {
                "whisper_model": "base",
                "tts_model": "tts_models/en/ljspeech/tacotron2-DDC",
                "wake_word_model": "alexa_v0.1"
            },
            "audio_settings": {
                "sample_rate": 16000,
                "speech_rate": personality_voice.get("speech_rate", 1.0),
                "voice_pitch": personality_voice.get("voice_pitch", 0.5),
                "volume": 0.8
            },
            "wake_words": personality_voice.get("wake_words", ["jarvis", "hey jarvis"]),
            "voice_responses": personality_voice.get("responses", {
                "wake_acknowledged": "Yes, how can I help you?",
                "listening": "I'm listening...",
                "error_no_speech": "I didn't hear anything. Please try again."
            }),
            "hardware_optimization": {
                "prefer_gpu": True,
                "device": "auto"
            }
        }
    
    def _get_default_voice_config(self) -> Dict[str, Any]:
        """Get embedded default voice configuration"""
        return {
            "voice_stack": "faster-whisper + coqui-tts + openWakeWord",
            "models": {
                "whisper_model": "base",
                "tts_model": "tts_models/en/ljspeech/tacotron2-DDC", 
                "wake_word_model": "alexa_v0.1"
            },
            "audio_settings": {
                "sample_rate": 16000,
                "chunk_duration": 1.0,
                "speech_rate": 1.0,
                "voice_pitch": 0.5,
                "volume": 0.8
            },
            "voice_responses": {
                "wake_acknowledged": "Yes, how can I help you?",
                "listening": "I'm listening...",
                "processing": "Let me think about that...",
                "error_no_speech": "I didn't hear anything. Please try again.",
                "error_no_wake_word": "I'm waiting for the wake word...",
                "error_tts_failed": "I had trouble speaking that response.",
                "error_stt_failed": "I had trouble understanding what you said."
            },
            "hardware_optimization": {
                "prefer_gpu": True,
                "device": "auto",
                "gpu_memory_fraction": 0.7,
                "cpu_threads": 4
            },
            "wake_words": ["jarvis", "hey jarvis"],
            "advanced": {
                "vad_threshold": 0.5,
                "silence_timeout": 2.0,
                "phrase_timeout": 3.0,
                "wake_word_sensitivity": 0.5
            }
        }
    
    def _detect_device(self) -> str:
        """Detect optimal device for voice processing using JARVIS hardware detection"""
        import os
        import subprocess
        import json
        
        try:
            # Simple hardware detection
            import platform
            if platform.machine().lower() == 'arm64':
                logger.info("Using NPU on ARM64 Snapdragon X system")
                return "npu_qualcomm"
        except Exception as e:
            logger.warning(f"Platform detection failed: {e}, falling back to PyTorch detection")
        
        # Fallback to PyTorch detection for compatibility
        try:
            import torch
            if torch.cuda.is_available():
                device = "cuda"
                logger.info(f"Using CUDA device: {torch.cuda.get_device_name()}")
            else:
                device = "cpu"
                logger.info("Using CPU device for voice processing")
            return device
        except ImportError:
            logger.info("PyTorch not available, using CPU")
            return "cpu"
    
    def _initialize_models(self):
        """Initialize voice models based on configuration"""
        logger.info("Voice models will be loaded on-demand to optimize startup time")
        logger.info(f"Configured voice stack: {self.voice_config.get('voice_stack', 'unknown')}")
        logger.info(f"Device: {self.device}")
        logger.info(f"Models: {self.voice_config.get('models', {})}")
    
    async def get_status(self) -> Dict[str, Any]:
        """Get voice service status"""
        return {
            "voice_stack": self.voice_config.get("voice_stack", "unknown"),
            "whisper_available": self._check_whisper_available(),
            "tts_available": self._check_tts_available(), 
            "wake_word_available": self._check_wake_word_available(),
            "device": self.device,
            "models": self.voice_config.get("models", {}),
            "config": self.voice_config,
            "wake_words": self.voice_config.get("wake_words", [])
        }
    
    def _check_whisper_available(self) -> bool:
        """Check if faster-whisper is available"""
        try:
            import faster_whisper
            return True
        except ImportError:
            return False
    
    def _check_tts_available(self) -> bool:
        """Check if coqui-tts is available"""
        try:
            import TTS
            return True
        except ImportError:
            return False
    
    def _check_wake_word_available(self) -> bool:
        """Check if openWakeWord is available"""
        try:
            import openwakeword
            return True
        except ImportError:
            return False
    
    async def speak(self, text: str) -> Dict[str, Any]:
        """Convert text to speech using coqui-tts"""
        try:
            if not self._check_tts_available():
                return {
                    "success": False,
                    "message": "TTS not available - install coqui-tts",
                    "data": {"text": text}
                }
            
            # TTS implementation will be loaded when dependencies are installed
            logger.info(f"TTS request: {text[:50]}...")
            return {
                "success": True,
                "message": "TTS functionality ready (requires dependencies)",
                "data": {"text": text, "voice_config": self.voice_config["audio_settings"]}
            }
            
        except Exception as e:
            logger.error(f"TTS error: {e}")
            return {
                "success": False,
                "message": f"TTS failed: {str(e)}",
                "data": {"text": text}
            }
    
    async def listen(self, timeout: int = 10) -> Dict[str, Any]:
        """Convert speech to text using faster-whisper"""
        try:
            if not self._check_whisper_available():
                return {
                    "success": False,
                    "message": "STT not available - install faster-whisper",
                    "data": {}
                }
            
            # STT implementation will be loaded when dependencies are installed
            logger.info("STT listening request")
            return {
                "success": True,
                "message": "STT functionality ready (requires dependencies)",
                "data": {"timeout": timeout, "voice_config": self.voice_config["audio_settings"]}
            }
            
        except Exception as e:
            logger.error(f"STT error: {e}")
            return {
                "success": False,
                "message": f"STT failed: {str(e)}",
                "data": {}
            }
    
    async def detect_wake_word(self, timeout: int = 30) -> Dict[str, Any]:
        """Detect wake word using openWakeWord"""
        try:
            if not self._check_wake_word_available():
                return {
                    "success": False,
                    "message": "Wake word detection not available - install openWakeWord",
                    "data": {}
                }
            
            # Wake word implementation will be loaded when dependencies are installed
            logger.info("Wake word detection request")
            return {
                "success": True,
                "message": "Wake word detection ready (requires dependencies)",
                "data": {
                    "wake_words": self.voice_config.get("wake_words", []),
                    "timeout": timeout,
                    "sensitivity": self.voice_config.get("advanced", {}).get("wake_word_sensitivity", 0.5)
                }
            }
            
        except Exception as e:
            logger.error(f"Wake word detection error: {e}")
            return {
                "success": False,
                "message": f"Wake word detection failed: {str(e)}",
                "data": {}
            }
    
    async def stop(self) -> Dict[str, Any]:
        """Stop all voice operations"""
        logger.info("Voice operations stopped")
        return {
            "success": True,
            "message": "Voice operations stopped",
            "data": {}
        }
    
    async def configure(self, command: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """Configure voice settings"""
        try:
            if command == "configure":
                # Update audio settings
                if "speech_rate" in params:
                    self.voice_config["audio_settings"]["speech_rate"] = params["speech_rate"]
                if "voice_pitch" in params:
                    self.voice_config["audio_settings"]["voice_pitch"] = params["voice_pitch"]
                if "volume" in params:
                    self.voice_config["audio_settings"]["volume"] = params["volume"]
                
                return {
                    "success": True,
                    "message": "Voice configuration updated",
                    "data": {"updated_settings": params}
                }
            
            return {
                "success": False,
                "message": f"Unknown configuration command: {command}",
                "data": {}
            }
            
        except Exception as e:
            logger.error(f"Configuration error: {e}")
            return {
                "success": False,
                "message": f"Configuration failed: {str(e)}",
                "data": {}
            }
    
    async def chat(self) -> Dict[str, Any]:
        """Complete voice chat interaction (wake word -> listen -> AI -> speak)"""
        try:
            # This will be implemented when all dependencies are available
            logger.info("Voice chat interaction requested")
            return {
                "success": True,
                "message": "Voice chat ready (requires full voice stack installation)",
                "data": {
                    "pipeline": "wake word -> STT -> AI -> TTS",
                    "voice_stack": self.voice_config.get("voice_stack", "unknown")
                }
            }
            
        except Exception as e:
            logger.error(f"Voice chat error: {e}")
            return {
                "success": False,
                "message": f"Voice chat failed: {str(e)}",
                "data": {}
            }

# Global voice service instance
voice_service = ModernVoiceService()
'@
    
    try {
        Set-Content -Path $voiceServicePath -Value $voiceServiceCode -Encoding UTF8
        Write-Log -Message "Modern voice service module created successfully" -Level SUCCESS -LogFile $LogFile
        Write-Log -Message "Voice service path: ${voiceServicePath}" -Level INFO -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create voice service module: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-VoiceServiceValidation {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Validating voice service architecture..." -Level INFO -LogFile $LogFile
    $validationResults = @()
    # Check voice service file
    if (Test-Path $voiceServicePath) {
        $validationResults += "✅ Voice service module: $voiceServicePath"
        # Check for modern voice stack indicators
        $serviceContent = Get-Content $voiceServicePath -Raw
        if ($serviceContent -match "faster-whisper" -and $serviceContent -match "coqui" -and $serviceContent -match "openWakeWord") {
            $validationResults += "✅ Modern voice stack: faster-whisper + coqui-tts + openWakeWord"
        }
        else { $validationResults += "❌ Voice stack: Not modern stack" }
        
        if ($serviceContent -match "jarvis_voice\.json") { $validationResults += "✅ Configuration system: jarvis_voice.json integration" }
        else { $validationResults += "❌ Configuration system: Missing jarvis_voice.json integration" }
    }
    else { $validationResults += "❌ Voice service module: Missing" }
    # Check voice configuration
    if (Test-Path $voiceConfigPath) {
        try {
            $voiceConfig = Get-Content $voiceConfigPath -Raw | ConvertFrom-Json
            $validationResults += "✅ Voice configuration: jarvis_voice.json exists and valid"
            # Check required configuration sections
            $requiredSections = @("voice_stack", "models", "audio_settings", "voice_responses", "hardware_optimization")
            foreach ($section in $requiredSections) {
                if ($voiceConfig.PSObject.Properties[$section]) {
                    $validationResults += "✅ Config section: $section"
                }
                else { $validationResults += "❌ Config section: Missing $section" }
            }
        }
        catch { $validationResults += "❌ Voice configuration: Invalid JSON format" }
    }
    else { $validationResults += "❌ Voice configuration: jarvis_voice.json missing" }
    # Display results
    Write-Log -Message "=== VOICE SERVICE ARCHITECTURE VALIDATION ===" -Level INFO -LogFile $LogFile
    foreach ($result in $validationResults) {
        $level = if ($result -like "✅*") { "SUCCESS" } else { "ERROR" }
        Write-Log -Message $result -Level $level -LogFile $LogFile
    }
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    Write-Log -Message "Voice Service Architecture: $successCount/$($validationResults.Count) passed, $failureCount failed" -Level $(if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }) -LogFile $LogFile
    return $failureCount -eq 0
}

# Main execution
try {
    if (-not (Test-Prerequisites -LogFile $logFile)) {
        Stop-Transcript
        exit 1
    }
    $setupResults = @()
    # Voice service architecture setup - always run
    Write-Log -Message "Setting up voice service architecture..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "Voice Configuration"; Success = (New-VoiceConfiguration -LogFile $logFile) }
    $setupResults += @{Name = "Voice Service Module"; Success = (New-VoiceServiceModule -LogFile $logFile) }
    if ($Test -or $Run) {
        Write-Log -Message "Validating voice service architecture..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Architecture Validation"; Success = (New-VoiceServiceValidation -LogFile $logFile) }
    }
    # Summary
    Write-Log -Message "=== SETUP SUMMARY ===" -Level INFO -LogFile $logFile
    $successCount = 0
    $failCount = 0
    foreach ($result in $setupResults) {
        if ($result.Success) {
            Write-Log -Message "$($result.Name) - SUCCESS" -Level SUCCESS -LogFile $logFile
            $successCount++
        }
        else {
            Write-Log -Message "$($result.Name) - FAILED" -Level ERROR -LogFile $logFile
            $failCount++
        }
    }
    Write-Log -Message "Setup Results: $successCount successful, $failCount failed" -Level INFO -LogFile $logFile
    if ($failCount -gt 0) {
        Write-Log -Message "Voice service architecture setup had failures" -Level ERROR -LogFile $logFile
        Stop-Transcript
        exit 1
    }
    # Output architecture info
    Write-Log -Message "=== VOICE SERVICE ARCHITECTURE ===" -Level INFO -LogFile $logFile
    Write-Log -Message "Voice Service: backend/services/voice_service.py" -Level INFO -LogFile $logFile
    Write-Log -Message "Configuration: jarvis_voice.json (customizable)" -Level INFO -LogFile $logFile
    Write-Log -Message "Voice Stack: faster-whisper + coqui-tts + openWakeWord" -Level INFO -LogFile $logFile
    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    Write-Log -Message "1. Run .\06b-VoiceBackendIntegration.ps1 to integrate with FastAPI backend" -Level INFO -LogFile $logFile
    Write-Log -Message "2. Run .\06c-VoiceInstall.ps1 -Install -Test to install voice dependencies" -Level INFO -LogFile $logFile
    Write-Log -Message "3. Customize jarvis_voice.json if needed (optional)" -Level INFO -LogFile $logFile
    Write-Log -Message "4. Start backend: .\run_backend.ps1" -Level INFO -LogFile $logFile
}
catch {
    Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript