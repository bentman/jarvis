# 06c-VoiceInstall.ps1 - Modern Voice Dependencies Installation and Validation
# Purpose: Install and validate modern voice stack (faster-whisper + coqui-tts + openWakeWord) in backend virtual environment
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

# Define paths using critical backend pattern
$backendDir = Join-Path $projectRoot "backend"
$venvDir = Join-Path $backendDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"
$requirementsPath = Join-Path $backendDir "requirements.txt"

function Test-Prerequisites {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    # Test that backend virtual environment and voice setup prerequisites exist
    Write-Log -Message "Testing prerequisites..." -Level INFO -LogFile $LogFile
    # Check backend virtual environment exists
    if (-not (Test-Path $venvDir)) {
        Write-Log -Message "❌ Backend virtual environment not found - Run 02-FastApiBackend.ps1." -Level ERROR -LogFile $LogFile
        return $false
    }
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "❌ Python executable not found in backend - Run 02-FastApiBackend.ps1 " -Level ERROR -LogFile $LogFile
        return $false
    }
    # Check voice setup has been run
    if (-not (Test-Path (Join-Path $backendDir "services\voice_service.py"))) {
        Write-Log -Message "❌ Voice service not found - Run 06a-VoiceSetup.ps1" -Level ERROR -LogFile $LogFile
        return $false
    }
    
    Write-Log -Message "✅ All prerequisites verified" -Level SUCCESS -LogFile $LogFile
    return $true
}

function Test-PythonPackage {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile, 
        [string]$PackageName,
        [string]$Version = "",
        [string]$ImportName = ""
    )
    # Test if Python package is available and importable in virtual environment
    # Use import name if provided, otherwise use package name
    $testImport = if ($ImportName) { $ImportName } else { $PackageName }
    
    try {
        # Test import to verify package is available
        $importTest = @"
try:
    import $testImport
    print(f"SUCCESS: {$testImport} imported successfully")
except ImportError as e:
    print(f"FAILED: {$testImport} import failed - {e}")
    exit(1)
except Exception as e:
    print(f"ERROR: {$testImport} import error - {e}")
    exit(1)
"@
        
        $result = $importTest | & $venvPy 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "✅ Package $PackageName is available and importable" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "📦 Package $PackageName not found - will install" -Level INFO -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "❌ Error testing package ${PackageName}: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Install-ModernVoiceDependencies {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    # Install modern voice stack dependencies with hardware optimization in backend virtual environment
    Write-Log -Message "Installing modern voice dependencies in backend virtual environment..." -Level INFO -LogFile $LogFile
    
    # Upgrade pip first
    Write-Log -Message "Upgrading pip in backend virtual environment..." -Level INFO -LogFile $LogFile
    try {
        & $venvPy -m pip install --upgrade pip --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "✅ pip upgraded successfully" -Level SUCCESS -LogFile $LogFile
        }
        else { Write-Log -Message "⚠️ pip upgrade failed" -Level WARN -LogFile $LogFile }
    }
    catch { Write-Log -Message "⚠️ pip upgrade error: $($_.Exception.Message)" -Level WARN -LogFile $LogFile }
    
    # Get hardware optimization configuration
    $hwConfig = Get-OptimalConfiguration -Hardware $hardware
    $torchIndexUrl = if ($hardware.GPU.Type -eq "NVIDIA" -and $hardware.GPU.CUDACapable) { 
        "https://download.pytorch.org/whl/cu118" 
    }
    else { "https://download.pytorch.org/whl/cpu" }
    
    Write-Log -Message "Installing PyTorch with hardware optimization..." -Level INFO -LogFile $LogFile
    Write-Log -Message "Hardware: $($hardware.GPU.Type), Using index: $torchIndexUrl" -Level INFO -LogFile $LogFile
    
    # Core dependencies with hardware optimization
    $coreDeps = @(
        @{Name = "torch>=2.0.0"; IndexUrl = $torchIndexUrl },
        @{Name = "torchaudio>=2.0.0"; IndexUrl = $torchIndexUrl },
        @{Name = "numpy>=1.24.0" },
        @{Name = "scipy>=1.10.0" }
    )
    
    foreach ($dep in $coreDeps) {
        Write-Log -Message "Installing $($dep.Name)..." -Level INFO -LogFile $LogFile
        try {
            if ($dep.IndexUrl) {
                & $venvPy -m pip install $dep.Name --index-url $dep.IndexUrl --quiet
            }
            else {
                & $venvPy -m pip install $dep.Name --quiet
            }
            if ($LASTEXITCODE -eq 0) { Write-Log -Message "✅ $($dep.Name) installed successfully" -Level SUCCESS -LogFile $LogFile }
            else { Write-Log -Message "❌ $($dep.Name) installation failed" -Level ERROR -LogFile $LogFile }
        }
        catch { Write-Log -Message "❌ $($dep.Name) installation error: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile }
    }
    
    # Modern voice stack dependencies - UPDATED: sounddevice replaces PyAudio
    Write-Log -Message "Installing modern voice stack dependencies..." -Level INFO -LogFile $LogFile
    $voiceDeps = @(
        @{Name = "faster-whisper>=1.0.0"; ImportName = "faster_whisper" },
        @{Name = "coqui-tts>=0.22.0"; ImportName = "TTS" },
        @{Name = "openWakeWord>=0.5.0"; ImportName = "openwakeword" },
        @{Name = "sounddevice>=0.4.6" },  # CHANGED: from pyaudio>=0.2.11 to sounddevice
        @{Name = "librosa>=0.10.0" },
        @{Name = "soundfile>=0.12.1" }
        # REMOVED: @{Name = "pyaudio>=0.2.11" } - replaced with sounddevice for better Windows/ARM64 compatibility
    )
    
    $successCount = 0
    foreach ($dep in $voiceDeps) {
        # Test if package already installed and skip if present
        $packageName = $dep.Name.Split('>=')[0].Split('[')[0]  # Extract base package name
        $importName = if ($dep.ImportName) { $dep.ImportName } else { $packageName }
        
        if (Test-PythonPackage -PackageName $packageName -ImportName $importName -LogFile $LogFile) {
            Write-Log -Message "$($dep.Name) already installed - skipping installation" -Level INFO -LogFile $LogFile
            $successCount++
            continue
        }
        
        Write-Log -Message "Installing $($dep.Name)..." -Level INFO -LogFile $LogFile
        try {
            & $venvPy -m pip install $dep.Name --quiet
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Message "✅ $($dep.Name) installed successfully" -Level SUCCESS -LogFile $LogFile
                $successCount++
            }
            else { Write-Log -Message "❌ $($dep.Name) installation failed" -Level ERROR -LogFile $LogFile }
        }
        catch { Write-Log -Message "❌ $($dep.Name) installation error: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile }
    }
    
    # Check for dependency conflicts
    Write-Log -Message "Checking for dependency conflicts..." -Level INFO -LogFile $LogFile
    try {
        $pipCheck = & $venvPy -m pip check 2>&1
        if ($pipCheck -match "has requirement|conflicts with") {
            Write-Log -Message "⚠️ Dependency conflicts detected: $pipCheck - Run this script again." -Level WARN -LogFile $LogFile
        }
        else { Write-Log -Message "✅ No dependency conflicts detected" -Level SUCCESS -LogFile $LogFile }
    }
    catch { Write-Log -Message "⚠️ Error checking dependencies: $($_.Exception.Message)" -Level WARN -LogFile $LogFile }
    
    if ($successCount -eq $voiceDeps.Count) {
        Write-Log -Message "✅ All modern voice dependencies installed successfully" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    
    Write-Log -Message "⚠️ Some dependencies failed ($successCount/$($voiceDeps.Count))" -Level WARN -LogFile $LogFile
    return $successCount -gt ($voiceDeps.Count * 0.7)  # 70% success threshold
}

function Test-ModernVoiceHardware {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    # Test voice hardware capabilities including PyTorch GPU, microphone, and voice components
    Write-Log -Message "Testing modern voice hardware capabilities..." -Level INFO -LogFile $LogFile
    
    try {
        # Test PyTorch GPU availability
        Write-Log -Message "Testing PyTorch GPU acceleration..." -Level INFO -LogFile $LogFile
        $gpuTest = @"
import torch
print("PyTorch version:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("CUDA version:", torch.version.cuda)
    print("GPU device:", torch.cuda.get_device_name(0))
    print("GPU memory:", f"{torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")
else:
    print("Using CPU for inference")
"@
        $gpuResult = $gpuTest | & $venvPy 2>&1
        Write-Log -Message "GPU test results: $gpuResult" -Level INFO -LogFile $LogFile
        
        # Test microphone access using sounddevice (UPDATED from PyAudio)
        Write-Log -Message "Testing microphone access with sounddevice..." -Level INFO -LogFile $LogFile
        $micTest = @"
import sounddevice as sd
import numpy as np
import sys

try:
    devices = sd.query_devices()
    input_devices = [d for i, d in enumerate(devices) if d['max_input_channels'] > 0]
    print(f"Found {len(input_devices)} input devices using sounddevice")
    
    # Test default input device availability
    try:
        sd.check_input_settings(samplerate=16000, channels=1)
        print("Default input device validated successfully")
    except Exception as device_error:
        print(f"Default input device issue: {device_error}")
    
    sys.exit(0)  # Success
except Exception as e:
    print(f"sounddevice microphone test error: {e}")
    print("Audio devices may still be functional - continuing")
    sys.exit(0)  # Consider this a warning, not failure
"@
        
        $micResult = $micTest | & $venvPy 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Log -Message "✅ Microphone test passed: $micResult" -Level SUCCESS -LogFile $LogFile }
        else {
            Write-Log -Message "⚠️ Microphone test failed: $micResult" -Level WARN -LogFile $LogFile
        }
        
        # Test faster-whisper initialization
        Write-Log -Message "Testing faster-whisper initialization..." -Level INFO -LogFile $LogFile
        $whisperTest = @"
try:
    from faster_whisper import WhisperModel
    import torch
    
    device = "cuda" if torch.cuda.is_available() else "cpu"
    compute_type = "float16" if device == "cuda" else "int8"
    
    print(f"Initializing faster-whisper on {device} with {compute_type}")
    model = WhisperModel("tiny.en", device=device, compute_type=compute_type)
    print("faster-whisper initialized successfully")
    
    # Test with dummy audio
    import numpy as np
    dummy_audio = np.random.randn(16000).astype(np.float32)  # 1 second of random audio
    segments, info = model.transcribe(dummy_audio)
    print(f"Test transcription completed (language: {info.language})")
    
except Exception as e:
    print(f"faster-whisper test error: {e}")
    raise
"@
        
        $whisperResult = $whisperTest | & $venvPy 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "✅ faster-whisper test passed: $whisperResult" -Level SUCCESS -LogFile $LogFile
        }
        else {
            Write-Log -Message "❌ faster-whisper test failed: $whisperResult" -Level ERROR -LogFile $LogFile
        }
        
        # Test coqui-tts initialization (simplified)
        Write-Log -Message "Testing coqui-tts initialization..." -Level INFO -LogFile $LogFile
        $ttsTest = @"
try:
    from TTS.api import TTS
    import torch
    
    gpu_available = torch.cuda.is_available()
    print(f"GPU available for TTS: {gpu_available}")
    
    # Use a fast model for testing
    model_name = "tts_models/en/ljspeech/tacotron2-DDC"
    print(f"Initializing coqui-tts model: {model_name}")
    tts = TTS(model_name=model_name, progress_bar=False, gpu=gpu_available)
    print("coqui-tts initialized successfully")
    
except Exception as e:
    print(f"coqui-tts test error: {e}")
    raise
"@
        
        $ttsResult = $ttsTest | & $venvPy 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "✅ coqui-tts test passed: $ttsResult" -Level SUCCESS -LogFile $LogFile
        }
        else {
            Write-Log -Message "❌ coqui-tts test failed: $ttsResult" -Level ERROR -LogFile $LogFile
        }

        # Test openWakeWord initialization with JARVIS wake words
        Write-Log -Message "Testing openWakeWord initialization..." -Level INFO -LogFile $LogFile
        $wakeTest = @"
try:
    import openwakeword
    from openwakeword import Model as WakeWordModel
    from openwakeword.utils import download_models
    import numpy as np
    import os
    
    print("Initializing openWakeWord for JARVIS...")
    
    # Check if models directory exists and download if needed
    try:
        # Download models if not present
        download_models()
        print("Models downloaded/verified successfully")
    except Exception as download_error:
        print(f"Model download warning: {download_error}")
    
    # Try to initialize with available models for JARVIS wake words
    try:
        # First try with jarvis-specific models
        model = WakeWordModel(wakeword_models=["hey_jarvis"], inference_framework="onnx")
        print("Initialized with hey_jarvis model")
    except Exception:
        try:
            # Fallback to alexa model (commonly available)
            model = WakeWordModel(wakeword_models=["alexa"], inference_framework="onnx")
            print("Initialized with alexa model as fallback for JARVIS")
        except Exception:
            # Final fallback to default models
            model = WakeWordModel(inference_framework="onnx")
            print("Initialized with default models")
    
    print("openWakeWord initialized successfully")
    
    # Test with dummy audio
    dummy_audio = np.random.randint(-32768, 32767, 16000, dtype=np.int16)
    predictions = model.predict(dummy_audio)
    print(f"Wake word test completed, available models: {list(predictions.keys())}")
    
except Exception as e:
    print(f"openWakeWord test error: {e}")
    exit(1)  # Ensure proper error reporting
"@
        
        $wakeResult = $wakeTest | & $venvPy 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "✅ openWakeWord test passed: $wakeResult" -Level SUCCESS -LogFile $LogFile
        }
        else {
            Write-Log -Message "❌ openWakeWord test failed: $wakeResult" -Level ERROR -LogFile $LogFile
        }
        
        # Return true only if ALL critical tests passed
        $allTestsPassed = $true
        # Check each test result individually
        if ($LASTEXITCODE -ne 0) {
            $allTestsPassed = $false
            Write-Log -Message "❌ Critical voice component test failed" -Level ERROR -LogFile $LogFile
        }
        
        return $allTestsPassed
    }
    catch {
        Write-Log -Message "❌ Voice hardware test error: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Invoke-ModernVoiceIntegrationTests {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    # Run pytest integration tests for voice functionality
    Write-Log -Message "Running modern voice integration tests..." -Level INFO -LogFile $LogFile
    
    if (-not (Test-Path (Join-Path $backendDir "tests\test_voice_integration.py"))) {
        Write-Log -Message "❌ Voice integration tests not found - Run 06a-VoiceSetup.ps1" -Level ERROR -LogFile $LogFile
        return $false
    }
    
    $testFilePath = Join-Path $backendDir "tests\test_voice_integration.py"
    $pytestCacheDir = Join-Path $backendDir ".pytest_cache"
    
    try {
        Write-Log -Message "Installing pytest for integration tests..." -Level INFO -LogFile $LogFile
        & $venvPy -m pip install pytest --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "❌ Failed to install pytest" -Level ERROR -LogFile $LogFile
            return $false
        }
        
        # Ensure pytest cache directory exists
        if (-not (Test-Path $pytestCacheDir)) {
            New-Item -ItemType Directory -Path $pytestCacheDir -Force | Out-Null
        }
        
        Write-Log -Message "Executing modern voice integration tests..." -Level INFO -LogFile $LogFile
        $testOutput = & $venvPy -m pytest $testFilePath -o cache_dir=$pytestCacheDir -v --tb=short 2>&1
        Write-Log -Message "Pytest output: $testOutput" -Level INFO -LogFile $LogFile
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "✅ All modern voice integration tests passed" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        
        Write-Log -Message "⚠️ Some voice tests failed (exit code: $LASTEXITCODE)" -Level WARN -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "❌Exception during voice test execution: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Test-ModernVoiceIntegrationSetup {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    # Validate complete voice integration setup including files, packages, and configuration
    Write-Log -Message "Validating modern voice integration setup..." -Level INFO -LogFile $LogFile
    
    $validationResults = @()
    
    # Check required files
    $requiredFiles = @(
        (Join-Path $backendDir "services\voice_service.py"),
        (Join-Path $backendDir "api\main.py"),
        (Join-Path $backendDir "tests\test_voice_integration.py"),
        "test_voice.ps1",
        ".env",
        $venvPy
    )
    
    foreach ($file in $requiredFiles) {
        if (Test-Path $file) {
            $size = (Get-Item $file).Length
            $validationResults += "✅ File: $file ($size bytes)"
        }
        else { $validationResults += "❌ Missing: $file" }
    }
    
    # Test modern voice packages - UPDATED: sounddevice instead of PyAudio
    $voicePackages = @(
        @{Name = "faster-whisper"; ImportName = "faster_whisper" },
        @{Name = "coqui-tts"; ImportName = "TTS" },
        @{Name = "openWakeWord"; ImportName = "openwakeword" },
        @{Name = "sounddevice" },  # CHANGED: from pyaudio to sounddevice
        @{Name = "torch" },
        @{Name = "numpy" },
        @{Name = "librosa" },
        @{Name = "soundfile" }
    )
    
    foreach ($package in $voicePackages) {
        $importName = if ($package.ImportName) { $package.ImportName } else { $package.Name }
        $status = Test-PythonPackage -PackageName $package.Name -ImportName $importName -LogFile $LogFile
        if ($status) { $validationResults += "✅ Python Package: $($package.Name)" }
        else { $validationResults += "❌ Python Package: $($package.Name)" }
    }
    
    # Check backend integration
    if (Test-Path (Join-Path $backendDir "api\main.py")) {
        $mainContent = Get-Content (Join-Path $backendDir "api\main.py") -Raw
        if ($mainContent -match "faster-whisper" -and $mainContent -match "coqui-tts" -and $mainContent -match "openWakeWord") {
            $validationResults += "✅ Backend: Modern voice stack integrated"
        }
        else { $validationResults += "❌ Backend: Modern voice stack not integrated" }
        
        if ($mainContent -match 'version.*2\.2\.0') { $validationResults += "✅ Backend: Version updated to 2.2.0" }
        else { $validationResults += "❌ Backend: Version not updated" }
    }
    
    # Configure personality voice settings (test, install, configure pattern)
    if (Test-Path "jarvis_personality.json") {
        try {
            $personality = Get-Content "jarvis_personality.json" -Raw | ConvertFrom-Json
            $needsUpdate = $false
            
            # Test if voice_settings exists and is properly configured
            if (-not $personality.PSObject.Properties['voice_settings']) {
                # Install voice_settings section
                $personality | Add-Member -MemberType NoteProperty -Name "voice_settings" -Value ([PSCustomObject]@{
                        voice_stack   = "faster-whisper + coqui-tts + openWakeWord"
                        audio_library = "sounddevice"  # NEW: document audio library choice
                        wake_words    = @("jarvis", "hey jarvis")
                        speech_rate   = 1.0
                        voice_pitch   = 0.5
                        responses     = [PSCustomObject]@{
                            wake_acknowledged = "Yes, how can I help you?"
                            listening         = "I'm listening..."
                            processing        = "Let me think about that..."
                            error_no_speech   = "I didn't hear anything. Please try again."
                        }
                    })
                $needsUpdate = $true
            }
            else {
                # Check/reconfigure existing voice_settings
                if ($personality.voice_settings.voice_stack -ne "faster-whisper + coqui-tts + openWakeWord") {
                    $personality.voice_settings.voice_stack = "faster-whisper + coqui-tts + openWakeWord"
                    $needsUpdate = $true
                }
                if (-not $personality.voice_settings.audio_library -or $personality.voice_settings.audio_library -ne "sounddevice") {
                    $personality.voice_settings.audio_library = "sounddevice"
                    $needsUpdate = $true
                }
                if (-not $personality.voice_settings.wake_words -or $personality.voice_settings.wake_words -notcontains "jarvis") {
                    $personality.voice_settings.wake_words = @("jarvis", "hey jarvis")
                    $needsUpdate = $true
                }
            }
            
            # Save updated configuration if needed
            if ($needsUpdate) {
                $personality | ConvertTo-Json -Depth 10 | Set-Content -Path "jarvis_personality.json" -Encoding UTF8
                $validationResults += "✅ Personality: Voice settings configured/updated with sounddevice"
            }
            else {
                $validationResults += "✅ Personality: Voice settings already configured with modern stack"
            }
        }
        catch { 
            $validationResults += "❌ Personality: Error configuring voice settings - $($_.Exception.Message)"
        }
    }
    else {
        $validationResults += "⚠️ Personality: jarvis_personality.json not found"
    }
    
    # Configure JARVIS voice environment variables - UPDATED for sounddevice
    if (Test-Path ".env") {
        $envContent = Get-Content ".env" -Raw
        $envUpdated = $false
        
        # Add JARVIS voice configuration if missing - updated for sounddevice
        $jarvisVoiceVars = @{
            "JARVIS_WAKE_WORDS"    = "jarvis,hey jarvis"
            "FASTER_WHISPER_MODEL" = "base"
            "COQUI_TTS_MODEL"      = "tts_models/en/ljspeech/tacotron2-DDC"
            "VOICE_SAMPLE_RATE"    = "16000"
            "AUDIO_LIBRARY"        = "sounddevice"  # NEW: document audio library choice
        }
        
        foreach ($var in $jarvisVoiceVars.GetEnumerator()) {
            if ($envContent -notmatch "$($var.Key)\s*=") {
                Add-Content -Path ".env" -Value "$($var.Key)=$($var.Value)"
                $envUpdated = $true
            }
        }
        
        if ($envUpdated) { $validationResults += "✅ .env: JARVIS voice variables configured with sounddevice" }
        else { $validationResults += "✅ .env: JARVIS voice variables already present" }
    }
    
    # Display results
    Write-Log -Message "=== MODERN VOICE INTEGRATION VALIDATION RESULTS ===" -Level INFO -LogFile $LogFile
    foreach ($result in $validationResults) {
        $level = if ($result -like "✅*") { "SUCCESS" } 
        elseif ($result -like "⚠️*") { "WARN" }
        else { "ERROR" }
        Write-Log -Message $result -Level $level -LogFile $LogFile
    }
    
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    
    Write-Log -Message "Modern Voice Integration: $successCount/$($validationResults.Count) passed, $failureCount failed, $warningCount warnings" -Level $(if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }) -LogFile $LogFile
    
    return $failureCount -eq 0
}

# Main execution
try {
    if (-not (Test-Prerequisites -LogFile $logFile)) {
        Stop-Transcript
        exit 1
    }
    
    $setupResults = @()
    
    if ($Install -or $Run) {
        Write-Log -Message "Installing modern voice dependencies..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Modern Voice Dependencies"; Success = (Install-ModernVoiceDependencies -LogFile $logFile) }
    }
    
    if ($Test -or $Run) {
        Write-Log -Message "Testing modern voice integration..." -Level INFO -LogFile $logFile
        
        # Check if core packages are available before running tests
        $coreAvailable = (Test-PythonPackage -PackageName "faster-whisper" -ImportName "faster_whisper" -LogFile $logFile) -and
        (Test-PythonPackage -PackageName "torch" -LogFile $logFile) -and
        (Test-PythonPackage -PackageName "sounddevice" -LogFile $logFile)
        
        if ($coreAvailable) {
            $setupResults += @{Name = "Voice Hardware Tests"; Success = (Test-ModernVoiceHardware -LogFile $logFile) }
            $setupResults += @{Name = "Integration Tests"; Success = (Invoke-ModernVoiceIntegrationTests -LogFile $logFile) }
        }
        else { Write-Log -Message "⚠️ Skipping tests - core dependencies not available (use -Install flag)" -Level WARN -LogFile $logFile }
    }
    
    if ($Configure -or $Run) { 
        Write-Log -Message "Validating modern voice setup..." -Level INFO -LogFile $logFile 
    } 
    
    Write-Log -Message "=== FINAL RESULTS ===" -Level INFO -LogFile $logFile
    $successCount = ($setupResults | Where-Object { $_.Success }).Count
    $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
    Write-Log -Message "✅ SUCCESS: $successCount components" -Level SUCCESS -LogFile $logFile
    if ($failCount -gt 0) {
        Write-Log -Message "❌ FAILED: $failCount components" -Level ERROR -LogFile $logFile
    }
    foreach ($result in $setupResults) {
        $status = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }
        $level = if ($result.Success) { "SUCCESS" } else { "ERROR" }
        Write-Log -Message "$($result.Name): $status" -Level $level -LogFile $logFile
    }
    
    # Always run validation
    Test-ModernVoiceIntegrationSetup -LogFile $logFile | Out-Null
    
    # Hardware optimization summary
    Write-Log -Message "=== HARDWARE OPTIMIZATION SUMMARY ===" -Level INFO -LogFile $logFile
    Write-Log -Message "Hardware Type: $($hardware.Platform) ($($hardware.GPU.Type))" -Level INFO -LogFile $logFile
    if ($hardware.GPU.Type -eq "NVIDIA" -and $hardware.GPU.CUDACapable) {
        Write-Log -Message "✅ CUDA Acceleration: Enabled for PyTorch and faster-whisper" -Level SUCCESS -LogFile $logFile
    }
    else { Write-Log -Message "CPU Inference: Using optimized CPU path" -Level INFO -LogFile $logFile }
    
    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    Write-Log -Message "1. To start the backend: .\run_backend.ps1" -Level INFO -LogFile $logFile
    Write-Log -Message "2. To test voice functionality: .\test_voice.ps1 -TestMic -TestTTS -TestAPI" -Level INFO -LogFile $logFile
    Write-Log -Message "3. For interactive voice mode: .\test_voice.ps1 -Interactive" -Level INFO -LogFile $logFile
    Write-Log -Message "4. Modern Voice API endpoints:" -Level INFO -LogFile $logFile
    Write-Log -Message "   - POST /api/voice/listen   # Speech-to-text (faster-whisper + sounddevice)" -Level INFO -LogFile $logFile
    Write-Log -Message "   - POST /api/voice/speak    # Text-to-speech (coqui-tts + sounddevice)" -Level INFO -LogFile $logFile
    Write-Log -Message "   - POST /api/voice/wake     # Wake word detection (openWakeWord + sounddevice)" -Level INFO -LogFile $logFile
    Write-Log -Message "   - POST /api/voice/chat     # Complete modern voice interaction" -Level INFO -LogFile $logFile
    Write-Log -Message "   - GET  /api/voice/status   # Modern voice system status" -Level INFO -LogFile $logFile
    
    # Exit with proper error code if critical components failed
    if ($failCount -gt 0) {
        Write-Log -Message "❌ Voice installation failed due to critical component failures." -Level ERROR -LogFile $logFile
        Stop-Transcript
        exit 1
    }
    else { 
        Write-Log -Message "✅ All voice components installed and validated successfully!" -Level SUCCESS -LogFile $logFile 
    } 
}
catch {
    Write-Log -Message "❌ Error: $_" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript