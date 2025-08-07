# 04b-OllamaDiag.ps1 - Ollama Hardware Diagnostics and Capability Detection
# Purpose: Identify NPU/GPU/CPU for Ollama/AI and report best available path, with graceful fallback
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

function Get-OllamaDiagSummary {
    $used = ""
    if ($hardware.NPU.Available) {
        Write-Log -Message "NPU detected: $($hardware.NPU.Name) -- using NPU for acceleration." -Level SUCCESS -LogFile $logFile
        $used = "NPU"
    }
    elseif ($hardware.GPU.Available) {
        Write-Log -Message "GPU detected: $($hardware.GPU.Name) ($($hardware.GPU.VRAM) GB) -- using GPU for acceleration." -Level SUCCESS -LogFile $logFile
        $used = "GPU"
    }
    else {
        Write-Log -Message "No NPU or GPU detected. Using CPU: $($hardware.CPU.Name) [$($hardware.CPU.Cores) logical cores] -- performance may be degraded." -Level WARN -LogFile $logFile
        $used = "CPU"
    }
    Write-Log -Message "Result: $used will be prioritized for Ollama/AI workload." -Level SUCCESS -LogFile $logFile
    return $used
}

$used = $null
$setupResults = @()
if ($Test -or $Run) {
    $used = Get-OllamaDiagSummary
    $setupResults += @{Name = "Ollama Hardware Diag"; Success = $true; Used = $used }
}
if ($Install -or $Run) {
    # No installs for diagnostics—add here if required
    Write-Log -Message "Install phase complete (no install steps for diagnostics)." -Level SUCCESS -LogFile $logFile
    $setupResults += @{Name = "Install Phase"; Success = $true }
}
if ($Configure -or $Run) {
    # No config for diagnostics—add here if required
    Write-Log -Message "Configure phase complete (no config steps for diagnostics)." -Level SUCCESS -LogFile $logFile
    $setupResults += @{Name = "Configure Phase"; Success = $true }
}
try {
    # === Standardized completion summary ===
    Write-Log -Message "=== FINAL RESULTS ===" -Level INFO -LogFile $logFile
    $successCount = ($setupResults | Where-Object { $_.Success }).Count
    $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
    Write-Log -Message "SUCCESS: $successCount components" -Level SUCCESS -LogFile $logFile
    if ($failCount -gt 0) {
        Write-Log -Message "FAILED: $failCount components" -Level ERROR -LogFile $logFile
    }
    foreach ($result in $setupResults) {
        $msg = if ($result.Used) { " (Intent: use $($result.Used))" } else { "" }
        $status = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }
        $level = if ($result.Success) { "SUCCESS" } else { "ERROR" }
        Write-Log -Message "$($result.Name): $status$msg" -Level $level -LogFile $logFile
    }
    # Hardware acceleration summary
    if ($used) { 
        Write-Log -Message "Ollama/AI will prioritize: $used (per hardware detection)" -Level INFO -LogFile $logFile 
    }
    else { 
        Write-Log -Message "No acceleration hardware found. CPU will be used (expect reduced performance)." -Level WARN -LogFile $logFile 
    }
    Write-Log -Message "Diagnostics complete." -Level SUCCESS -LogFile $logFile
}
catch {
    Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}
Write-Log -Message "$scriptPrefix v$scriptVersion complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript
