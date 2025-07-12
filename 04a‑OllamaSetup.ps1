# 04a-OllamaSetup.ps1 - Ollama installation and model setup
# Purpose: Ensure Ollama runtime, required models, service config (J.A.R.V.I.S. AI)
# Last edit: 2025-07-11 - Standardized for J.A.R.V.I.S. scripting project

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

function Test-OllamaInstalled {
    param([string]$LogFile)
    Write-Log -Message "Testing for Ollama installation..." -Level INFO -LogFile $LogFile
    $ollamaCmd = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($ollamaCmd) {
        Write-Log -Message "Ollama is installed: $($ollamaCmd.Source)" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    else {
        Write-Log -Message "Ollama not found in PATH." -Level WARN -LogFile $LogFile
        return $false
    }
}
    
function Test-OllamaModels {
    param([string]$LogFile)
    $requiredModels = @("phi3:mini")
    $installedModels = @()
    $ollamaModelsOk = $true
    foreach ($model in $requiredModels) {
        $result = & ollama list 2>$null | Select-String $model
        if ($result) {
            $installedModels += $model
        }
        else {
            $ollamaModelsOk = $false
            Write-Log -Message "Required Ollama model '$model' is not installed." -Level WARN -LogFile $LogFile
        }
    }
    if ($ollamaModelsOk) {
        Write-Log -Message "All required Ollama models are installed." -Level SUCCESS -LogFile $LogFile
    }
    return $ollamaModelsOk
}
    
function Install-Ollama {
    param([string]$LogFile)
    Write-Log -Message "Attempting to install Ollama..." -Level INFO -LogFile $LogFile
    if (Test-OllamaInstalled -LogFile $LogFile) {
        Write-Log -Message "Ollama already installed." -Level SUCCESS -LogFile $LogFile
        return $true
    }
    try {
        # Windows example using winget, add Linux/Mac logic as needed
        if ($IsWindows) {
            $winget = Get-Command "winget" -ErrorAction SilentlyContinue
            if ($winget) {
                & winget install Ollama.Ollama -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements
                if (Test-OllamaInstalled -LogFile $LogFile) {
                    Write-Log -Message "Ollama installed via winget." -Level SUCCESS -LogFile $LogFile
                    return $true
                }
                else {
                    Write-Log -Message "Ollama installation failed." -Level ERROR -LogFile $LogFile
                    return $false
                }
            }
            else {
                Write-Log -Message "winget not available, manual installation required." -Level ERROR -LogFile $LogFile
                return $false
            }
        }
        else {
            Write-Log -Message "Please install Ollama manually for your OS." -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Exception during Ollama installation: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Install-OllamaModels {
    param([string]$LogFile)
    $requiredModels = @("phi3:mini")
    $allOk = $true
    foreach ($model in $requiredModels) {
        $result = & ollama list 2>$null | Select-String $model
        if (-not $result) {
            Write-Log -Message "Pulling Ollama model: $model" -Level INFO -LogFile $LogFile
            try {
                & ollama pull $model
                Write-Log -Message "Model $model pulled successfully." -Level SUCCESS -LogFile $LogFile
            }
            catch {
                $allOk = $false
                Write-Log -Message "Failed to pull model ${$model}: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
            }
        }
        else {
            Write-Log -Message "Model $model already present." -Level SUCCESS -LogFile $LogFile
        }
    }
    return $allOk
}

# === PHASES ===

try {
    if ($Test -or $Run) {
        $setupResults += @{Name = "Ollama Installed"; Success = (Test-OllamaInstalled -LogFile $logFile) }
        $setupResults += @{Name = "Ollama Models"; Success = (Test-OllamaModels -LogFile $logFile) }
    }
    if ($Install -or $Run) {
        if (-not (Test-OllamaInstalled -LogFile $logFile)) {
            $setupResults += @{Name = "Install Ollama"; Success = (Install-Ollama -LogFile $logFile) }
        }
        else {
            $setupResults += @{Name = "Install Ollama"; Success = $true }
        }
        $setupResults += @{Name = "Install Ollama Models"; Success = (Install-OllamaModels -LogFile $logFile) }
    }
    if ($Configure -or $Run) {
        # Any additional configuration steps for Ollama service here
        Write-Log -Message "Configure phase complete (no custom config implemented)." -Level SUCCESS -LogFile $logFile
        $setupResults += @{Name = "Configure Phase"; Success = $true }
    }

    # === SUMMARY ===
    $successCount = ($setupResults | Where-Object { $_.Success }).Count
    $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
    Write-Host "SUCCESS: $successCount" -ForegroundColor Green
    Write-Host "FAILED: $failCount" -ForegroundColor Red
    foreach ($result in $setupResults) {
        $fg = if ($result.Success) { "Green" } else { "Red" }
        Write-Host "$($result.Name): $($result.Success ? 'SUCCESS' : 'FAILED')" -ForegroundColor $fg
    }

    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    Write-Host "Next: Integrate models/config in backend or run: .\\03-IntegrateOllama.ps1 -Run" -ForegroundColor Cyan
}
catch {
    Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "$scriptPrefix v$scriptVersion complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript
