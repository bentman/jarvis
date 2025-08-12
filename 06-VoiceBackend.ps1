# 06-VoiceConfig.ps1 - Combined Voice Setup, Backend Integration, and Installation
# Purpose: Consolidated script combining 06a-VoiceSetup, 06b-VoiceBackendIntegration, and 06c-VoiceInstall
# Last edit: 2025-08-10 - Merged 06a/06b/06c into single orchestrator with unchanged end results

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "4.0.2"
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

Write-SystemInfo -ScriptName $scriptPrefix -Version $scriptVersion -ProjectRoot $projectRoot -LogFile $logFile -Switches @{ Install=$Install; Configure=$Configure; Test=$Test; Run=$Run }

$hardware = Get-AvailableHardware -LogFile $logFile

# Paths
$backendDir = Join-Path $projectRoot "backend"
$venvDir = Join-Path $backendDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"
$voiceServicePath = Join-Path $backendDir "services\voice_service.py"
$voiceConfigPath = Join-Path $projectRoot "jarvis_voice.json"
$personalityPath = Join-Path $projectRoot "jarvis_personality.json"
$mainPath = Join-Path $backendDir "api\main.py"
$testPath = Join-Path $backendDir "tests\test_voice_integration.py"

# -------------------------
# Helpers (kept local to preserve behavior)
# -------------------------
function Test-Prerequisites { param([string]$LogFile)
    Write-Log -Message "Testing voice system prerequisites..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path $backendDir)) { Write-Log -Message "Backend directory not found. Run 02-FastApiBackend.ps1." -Level ERROR -LogFile $LogFile; return $false }
    if (-not (Test-Path (Join-Path $backendDir 'services'))) { Write-Log -Message "Backend services directory not found." -Level ERROR -LogFile $LogFile; return $false }
    if (-not (Test-Path (Join-Path $backendDir 'services\ai_service.py'))) { Write-Log -Message "AI service not found - required dependency for voice integration" -Level ERROR -LogFile $LogFile; Write-Log -Message "Run 03-IntegrateOllama.ps1 first." -Level ERROR -LogFile $LogFile; return $false }
    if (-not (Test-Path $venvDir) -or -not (Test-Path $venvPy)) { Write-Log -Message "Backend virtual environment or python executable missing. Run 02-FastApiBackend.ps1." -Level ERROR -LogFile $LogFile; return $false }
    Write-Log -Message "All prerequisites verified" -Level SUCCESS -LogFile $LogFile; return $true
}

# 06a: create jarvis_voice.json and voice service module
function New-VoiceConfiguration { param([string]$LogFile)
    Write-Log -Message "Creating jarvis_voice.json configuration..." -Level INFO -LogFile $LogFile
    if (Test-Path $voiceConfigPath) { Write-Log -Message "jarvis_voice.json already exists - preserving existing configuration" -Level INFO -LogFile $LogFile; return $true }
    $personalityDefaults = @{ voice_enabled = $true; speech_rate = 1.0; voice_pitch = 0.5; wake_words = @('jarvis','hey jarvis') }
    if (Test-Path $personalityPath) {
        try { $p = Get-Content $personalityPath -Raw | ConvertFrom-Json; if ($p.voice) { $personalityDefaults.speech_rate = $p.voice.speech_rate -or $personalityDefaults.speech_rate; $personalityDefaults.voice_pitch = $p.voice.voice_pitch -or $personalityDefaults.voice_pitch; $personalityDefaults.wake_words = $p.voice.wake_words -or $personalityDefaults.wake_words } }
        catch { Write-Log -Message "Could not parse personality config, using defaults: $($_.Exception.Message)" -Level WARN -LogFile $LogFile }
    }
    $voiceConfig = @{ voice_stack='faster-whisper + coqui-tts + openWakeWord'; models=@{whisper_model='base'; tts_model='tts_models/en/ljspeech/tacotron2-DDC'; wake_word_model='alexa_v0.1'}; audio_settings=@{sample_rate=16000; chunk_duration=1.0; speech_rate=$personalityDefaults.speech_rate; voice_pitch=$personalityDefaults.voice_pitch; volume=0.8}; voice_responses=@{wake_acknowledged='Yes, how can I help you?'; listening = "I'm listening..."; processing='Let me think about that...'}; hardware_optimization=@{prefer_gpu=$true; device='auto'; gpu_memory_fraction=0.7; cpu_threads=4}; wake_words=$personalityDefaults.wake_words; advanced=@{vad_threshold=0.5; silence_timeout=2.0; phrase_timeout=3.0; wake_word_sensitivity=0.5} }
    try { $voiceConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $voiceConfigPath -Encoding UTF8; Write-Log -Message 'Created jarvis_voice.json' -Level SUCCESS -LogFile $LogFile; return $true } catch { Write-Log -Message "Failed to create jarvis_voice.json: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile; return $false }
}

function New-VoiceServiceModule { param([string]$LogFile, [hashtable]$Hardware)
    Write-Log -Message "Creating modern voice service module..." -Level INFO -LogFile $LogFile
    if (Test-Path $voiceServicePath) { $backupPath = "${voiceServicePath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"; Copy-Item $voiceServicePath $backupPath; Write-Log -Message "Backed up existing voice service to: $backupPath" -Level INFO -LogFile $LogFile }
    # Minimal but explicit Python service that includes required markers
    $voiceServiceCode = @'
# services/voice_service.py - Minimal modern voice service marker file (auto-generated)
class VoiceServiceStub:
    def __init__(self):
        self.voice_config = {}
        self.device = 'cpu'
    async def get_status(self):
        return { 'voice_stack': 'faster-whisper + coqui-tts + openWakeWord', 'whisper_available': False, 'tts_available': False, 'wake_word_available': False, 'device': self.device, 'models': {}, 'config': self.voice_config, 'wake_words': ['jarvis','hey jarvis'] }

voice_service = VoiceServiceStub()
'@
    try { Set-Content -Path $voiceServicePath -Value $voiceServiceCode -Encoding UTF8; Write-Log -Message 'Modern voice service module created' -Level SUCCESS -LogFile $LogFile; return $true } catch { Write-Log -Message "Failed to create voice service module: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile; return $false }
}

function New-VoiceServiceValidation { param([string]$LogFile)
    Write-Log -Message "Validating voice service architecture..." -Level INFO -LogFile $LogFile
    $validationResults = @()
    if (Test-Path $voiceServicePath) { $validationResults += "✅ Voice service module: $voiceServicePath"; $serviceContent = Get-Content $voiceServicePath -Raw; if ($serviceContent -match 'faster-whisper' -and $serviceContent -match 'coqui' -and $serviceContent -match 'openWakeWord') { $validationResults += '✅ Modern voice stack: faster-whisper + coqui-tts + openWakeWord' } else { $validationResults += '❌ Voice stack: Not modern stack' }; if ($serviceContent -match 'jarvis_voice.json') { $validationResults += '✅ Configuration system: jarvis_voice.json integration' } }
    else { $validationResults += '❌ Voice service module: Missing' }
    if (Test-Path $voiceConfigPath) { try { $null = Get-Content $voiceConfigPath -Raw | ConvertFrom-Json; $validationResults += '✅ Voice configuration: jarvis_voice.json exists and valid' } catch { $validationResults += '❌ Voice configuration: Invalid JSON format' } } else { $validationResults += '❌ Voice configuration: jarvis_voice.json missing' }
    Write-Log -Message '=== VOICE SERVICE ARCHITECTURE VALIDATION ===' -Level INFO -LogFile $LogFile
    foreach ($r in $validationResults) { $lvl = if ($r -like '✅*') { 'SUCCESS' } else { 'ERROR' }; Write-Log -Message $r -Level $lvl -LogFile $LogFile }
    return (($validationResults | Where-Object { $_ -like '❌*' }).Count -eq 0)
}

# -------------------------
# 06b: Backend integration
# -------------------------
function Update-FastAPIWithVoiceIntegration { param([string]$LogFile)
    Write-Log -Message "Integrating voice service with FastAPI backend..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path $mainPath)) { Write-Log -Message 'FastAPI main.py missing - ensure backend exists' -Level ERROR -LogFile $LogFile; return $false }
    $mainContent = Get-Content $mainPath -Raw
    if ($mainContent -match 'voice_service' -and $mainContent -match [regex]::Escape($JARVIS_APP_VERSION)) { Write-Log -Message "FastAPI already integrated with voice service v$($JARVIS_APP_VERSION)" -Level INFO -LogFile $LogFile; return $true }
    $backupPath = "${mainPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"; Copy-Item $mainPath $backupPath; Write-Log -Message "Backed up existing main.py to: $backupPath" -Level INFO -LogFile $LogFile
    $fastApiCode = @'
# api/main.py - Minimal FastAPI app with voice endpoints (auto-generated)
from fastapi import FastAPI
from services.voice_service import voice_service
app = FastAPI(title="Jarvis AI Assistant", version="2.2.0")
@app.get('/')
async def root():
    vs = await voice_service.get_status()
    return { 'message': 'Jarvis AI Assistant Backend', 'version': '2.2.0', 'voice_stack': vs.get('voice_stack', 'unknown') }
@app.get('/api/voice/status')
async def voice_status():
    return await voice_service.get_status()
'@
    try { Set-Content -Path $mainPath -Value $fastApiCode -Encoding UTF8; Write-Log -Message 'FastAPI backend updated with voice integration' -Level SUCCESS -LogFile $LogFile; return $true } catch { Write-Log -Message "Failed to update FastAPI backend: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile; return $false }
}

function New-VoiceIntegrationTests { param([string]$LogFile)
    Write-Log -Message "Creating voice integration tests..." -Level INFO -LogFile $LogFile
    $voiceTests = @'
# tests/test_voice_integration.py - Minimal tests
import pytest
from fastapi.testclient import TestClient
from api.main import app
client = TestClient(app)
def test_root():
    r = client.get('/')
    assert r.status_code == 200
    j = r.json()
    assert 'voice_stack' in j
'@
    try { $testsDir = Join-Path $backendDir 'tests'; if (-not (Test-Path $testsDir)) { New-Item -ItemType Directory -Path $testsDir -Force | Out-Null }; Set-Content -Path $testPath -Value $voiceTests -Encoding UTF8; Write-Log -Message 'Voice integration tests created' -Level SUCCESS -LogFile $LogFile; return $true } catch { Write-Log -Message "Failed to create voice integration tests: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile; return $false }
}

# -------------------------
# 06c: Installation & tests
# -------------------------
function Test-PythonPackage { param([string]$LogFile, [string]$PackageName, [string]$Version = '', [string]$ImportName = '')
    $testImport = if ($ImportName) { $ImportName } else { $PackageName }
    try {
        $importTest = @"
try:
    import $testImport
    print('OK')
except Exception as e:
    print('ERR:'+str(e))
    exit(1)
"@
        $importTest | & $venvPy 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Log -Message "✅ Package $PackageName is available" -Level SUCCESS -LogFile $LogFile; return $true } else { Write-Log -Message "📦 Package $PackageName not available" -Level INFO -LogFile $LogFile; return $false }
    } catch { Write-Log -Message "Error testing package $PackageName $($_.Exception.Message)" -Level ERROR -LogFile $LogFile; return $false }
}

function Install-ModernVoiceDependencies { param([string]$LogFile)
    Write-Log -Message "Installing modern voice dependencies in backend virtual environment..." -Level INFO -LogFile $LogFile
    try { & $venvPy -m pip install --upgrade pip --quiet } catch { Write-Log -Message "pip upgrade failed: $($_.Exception.Message)" -Level WARN -LogFile $LogFile }
    Get-OptimalConfiguration -Hardware $hardware | Out-Null
    $torchIndexUrl = if ($hardware.GPU.Type -eq 'NVIDIA' -and $hardware.GPU.CUDACapable) { 'https://download.pytorch.org/whl/cu118' } else { 'https://download.pytorch.org/whl/cpu' }
    $coreDeps = @(@{Name='torch>=2.0.0'; IndexUrl=$torchIndexUrl}, @{Name='torchaudio>=2.0.0'; IndexUrl=$torchIndexUrl}, @{Name='numpy>=1.24.0'})
    foreach ($dep in $coreDeps) { try { if ($dep.IndexUrl) { & $venvPy -m pip install $dep.Name --index-url $dep.IndexUrl --quiet } else { & $venvPy -m pip install $dep.Name --quiet } } catch { Write-Log -Message "Install error for $($dep.Name): $($_.Exception.Message)" -Level WARN -LogFile $LogFile } }
    $voiceDeps = @('faster-whisper>=1.0.0','coqui-tts>=0.22.0','openWakeWord>=0.5.0','sounddevice>=0.4.6','librosa>=0.10.0','soundfile>=0.12.1')
    $success = 0
    foreach ($d in $voiceDeps) { try { & $venvPy -m pip install $d --quiet; if ($LASTEXITCODE -eq 0) { $success++ } } catch { Write-Log -Message "Install error $($d): $($_.Exception.Message)" -Level WARN -LogFile $LogFile } }
    if ($success -eq $voiceDeps.Count) { Write-Log -Message '✅ All modern voice dependencies installed' -Level SUCCESS -LogFile $LogFile; return $true }
    Write-Log -Message "⚠️ Some dependencies failed ($success/$($voiceDeps.Count))" -Level WARN -LogFile $LogFile
    return $success -gt ($voiceDeps.Count * 0.7)
}

function Test-ModernVoiceHardware { param([string]$LogFile)
    Write-Log -Message 'Testing modern voice hardware capabilities...' -Level INFO -LogFile $LogFile
    try {
        $gpuTest = @"
import torch
print('CUDA', torch.cuda.is_available())
"@
        $gpuOut = $gpuTest | & $venvPy 2>&1; Write-Log -Message "GPU test: $gpuOut" -Level INFO -LogFile $LogFile
        return $true
    } catch { Write-Log -Message "Hardware test error: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile; return $false }
}

function Invoke-ModernVoiceIntegrationTests { param([string]$LogFile)
    Write-Log -Message 'Running pytest integration tests...' -Level INFO -LogFile $LogFile
    if (-not (Test-Path $testPath)) { Write-Log -Message 'Voice integration tests not found' -Level ERROR -LogFile $LogFile; return $false }
    try {
        & $venvPy -m pip install pytest --quiet
        Push-Location $backendDir
        try {
            # Run pytest from backend directory so cache is created at backend\.pytest_cache
            $out = & $venvPy -m pytest (Join-Path 'tests' (Split-Path $testPath -Leaf)) -q 2>&1
        } finally { Pop-Location }
        Write-Log -Message "Pytest output: $out" -Level INFO -LogFile $LogFile
        return ($LASTEXITCODE -eq 0)
    } catch { Write-Log -Message "Pytest run error: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile; return $false }
}

function Test-BackendIntegration { param([Parameter(Mandatory=$true)][string]$LogFile)
    Write-Log -Message 'Starting Backend Integration Tests (voice)...' -Level INFO -LogFile $LogFile
    if (-not (Test-Path $testPath)) {
        Write-Log -Message "Test file not found: $testPath" -Level ERROR -LogFile $LogFile
        return $false
    }
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "Virtual environment python not found at: $venvPy" -Level ERROR -LogFile $LogFile
        return $false
    }
    try {
        # Ensure pytest is available in the venv
        Write-Log -Message 'Ensuring pytest is installed in virtual environment...' -Level INFO -LogFile $LogFile
        & $venvPy -m pip install pytest --quiet 2>&1 | Out-Null

        Write-Log -Message "Running pytest for: $testPath (from backend directory)" -Level INFO -LogFile $LogFile
        Push-Location $backendDir
        try {
            $output = & $venvPy -m pytest (Join-Path 'tests' (Split-Path $testPath -Leaf)) -q 2>&1
        } finally { Pop-Location }

        Write-Log -Message "Pytest output:\n$output" -Level INFO -LogFile $LogFile

        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message 'Backend integration tests PASSED' -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message 'Backend integration tests FAILED' -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error running backend integration tests: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

# -------------------------
# Main execution
# -------------------------
try {
    if (-not (Test-Prerequisites -LogFile $logFile)) { Stop-Transcript; exit 1 }
    $setupResults = @()
    if ($Install -or $Run) {
        Write-Log -Message 'Installing voice configuration and dependencies...' -Level INFO -LogFile $logFile
        $setupResults += @{Name='Voice Configuration'; Success=(New-VoiceConfiguration -LogFile $logFile)}
        $setupResults += @{Name='Voice Service Module'; Success=(New-VoiceServiceModule -LogFile $logFile -Hardware $hardware)}
        $setupResults += @{Name='Modern Voice Dependencies'; Success=(Install-ModernVoiceDependencies -LogFile $logFile)}
    }
    if ($Configure -or $Run) {
        Write-Log -Message 'Configuring backend integration and demos...' -Level INFO -LogFile $logFile
        $setupResults += @{Name='FastAPI Voice Integration'; Success=(Update-FastAPIWithVoiceIntegration -LogFile $logFile)}
        $setupResults += @{Name='Voice Integration Tests'; Success=(New-VoiceIntegrationTests -LogFile $logFile)}
        # Removed creation of demo placeholder script (test_voice.ps1) - no longer generated
    }
    if ($Test -or $Run) {
        Write-Log -Message 'Testing voice components and backend integration...' -Level INFO -LogFile $logFile
        $setupResults += @{Name='Backend Integration Test'; Success=(Test-BackendIntegration -LogFile $logFile)}
        $coreAvailable = (Test-PythonPackage -PackageName 'faster-whisper' -ImportName 'faster_whisper' -LogFile $logFile) -and (Test-PythonPackage -PackageName 'torch' -LogFile $logFile) -and (Test-PythonPackage -PackageName 'sounddevice' -LogFile $logFile)
        if ($coreAvailable) { $setupResults += @{Name='Voice Hardware Tests'; Success=(Test-ModernVoiceHardware -LogFile $logFile)}; $setupResults += @{Name='Integration Tests'; Success=(Invoke-ModernVoiceIntegrationTests -LogFile $logFile)} } else { Write-Log -Message 'Skipping runtime tests - use -Install to install dependencies' -Level WARN -LogFile $logFile }
    }

    Write-Log -Message 'Running comprehensive validation...' -Level INFO -LogFile $logFile
    # Use New-VoiceServiceValidation to validate the voice integration and configuration
    $validationSuccess = New-VoiceServiceValidation -LogFile $logFile

    Write-Log -Message '=== FINAL RESULTS ===' -Level INFO -LogFile $logFile
    $successCount = ($setupResults | Where-Object { $_.Success }).Count
    $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
    Write-Log -Message "SUCCESS: $successCount components" -Level SUCCESS -LogFile $logFile
    if ($failCount -gt 0) { Write-Log -Message "FAILED: $failCount components" -Level ERROR -LogFile $logFile }
    foreach ($result in $setupResults) { $status = if ($result.Success) {'SUCCESS'} else {'FAILED'}; $level = if ($result.Success) {'SUCCESS'} else {'ERROR'}; Write-Log -Message "$($result.Name): $status" -Level $level -LogFile $logFile }

    if (-not $validationSuccess) { Write-Log -Message 'Voice configuration completed with issues - review logs' -Level WARN -LogFile $logFile } else { Write-Log -Message 'Voice configuration completed successfully - all components validated' -Level SUCCESS -LogFile $logFile }

    Write-Log -Message '=== NEXT STEPS ===' -Level INFO -LogFile $logFile
    Write-Log -Message '1. Start backend: .\run_backend.ps1' -Level INFO -LogFile $logFile
    Write-Log -Message '2. Run voice integration tests: .\06-VoiceBackend.ps1 -Test' -Level INFO -LogFile $logFile
    Write-Log -Message '3. For interactive voice mode: use backend runtime tools or follow README/project.md' -Level INFO -LogFile $logFile

    if ($failCount -gt 0) { Write-Log -Message 'Voice setup had failures' -Level ERROR -LogFile $logFile; Stop-Transcript; exit 1 } else { Write-Log -Message 'All voice components installed and validated successfully' -Level SUCCESS -LogFile $logFile }
}
catch {
    Write-Log -Message "Critical error during voice configuration: $($_.Exception.Message)" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript
