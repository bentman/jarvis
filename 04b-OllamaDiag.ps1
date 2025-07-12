# 04b-OllamaDiag.ps1 - Ollama Hardware Diagnostics and Capability Detection
# Purpose: Identify NPU/GPU/CPU for Ollama/AI and report best available path, with graceful fallback
# Last edit: 2025-07-11 - J.A.R.V.I.S. standards; preserves original detection/intent logic

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

function Get-NpuInfo {
    Write-Log -Message "Checking for NPU presence..." -Level INFO -LogFile $logFile
    try {
        $npus = Get-CimInstance -Namespace "root\\CIMV2" -ClassName Win32_Processor | Where-Object { $_.Description -match "NPU" }
        if ($npus) {
            foreach ($npu in $npus) {
                Write-Log -Message "NPU detected: $($npu.Description) [Socket: $($npu.SocketDesignation)] -- using NPU for acceleration." -Level SUCCESS -LogFile $logFile
            }
            return $true
        }
        else {
            Write-Log -Message "No NPU detected. Will check for GPU..." -Level WARN -LogFile $logFile
            return $false
        }
    }
    catch {
        Write-Log -Message "NPU check failed: $($_.Exception.Message). Will check for GPU..." -Level ERROR -LogFile $logFile
        return $false
    }
}

function Get-GpuInfo {
    Write-Log -Message "Checking for GPU(s)..." -Level INFO -LogFile $logFile
    try {
        $gpus = Get-CimInstance Win32_VideoController
        if ($gpus) {
            foreach ($gpu in $gpus) {
                if ($gpu.Name -match "NVIDIA|RTX|GTX") {
                    Write-Log -Message "GPU detected: $($gpu.Name) ($($gpu.AdapterRAM/1MB) MB) -- using GPU for acceleration if supported (CUDA recommended)." -Level SUCCESS -LogFile $logFile
                }
                else {
                    Write-Log -Message "GPU detected: $($gpu.Name) ($($gpu.AdapterRAM/1MB) MB) -- may be used for acceleration if supported." -Level SUCCESS -LogFile $logFile
                }
            }
            return $true
        }
        else {
            Write-Log -Message "No GPU detected. Will use CPU fallback..." -Level WARN -LogFile $logFile
            return $false
        }
    }
    catch {
        Write-Log -Message "GPU check failed: $($_.Exception.Message). Will use CPU fallback..." -Level ERROR -LogFile $logFile
        return $false
    }
}

function Get-CpuInfo {
    Write-Log -Message "Checking for CPU(s)..." -Level INFO -LogFile $logFile
    try {
        $cpus = Get-CimInstance Win32_Processor
        foreach ($cpu in $cpus) {
            Write-Log -Message "CPU: $($cpu.Name) [$($cpu.NumberOfLogicalProcessors) logical cores] -- using CPU for fallback compute (performance may be degraded)." -Level SUCCESS -LogFile $logFile
        }
        return $true
    }
    catch {
        Write-Log -Message "CPU check failed: $($_.Exception.Message)" -Level ERROR -LogFile $logFile
        return $false
    }
}

function Get-OllamaDiagSummary {
    $used = ""
    $resultNPU = Get-NpuInfo
    $resultGPU = $false
    $resultCPU = $false
    if (-not $resultNPU) {
        $resultGPU = Get-GpuInfo
        if (-not $resultGPU) {
            $resultCPU = Get-CpuInfo
            $used = "CPU"
        }
        else {
            $used = "GPU"
        }
    }
    else {
        $used = "NPU"
    }
    if ($used) {
        Write-Log -Message "Result: $used will be prioritized for Ollama/AI workload." -Level SUCCESS -LogFile $logFile
    }
    else {
        Write-Log -Message "No compatible hardware detected for AI acceleration; defaulting to basic CPU mode (performance will be limited)." -Level ERROR -LogFile $logFile
    }
    return $used
}

$used = $null
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
    # === Colorized summary output ===
    $successCount = ($setupResults | Where-Object { $_.Success }).Count
    $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
    Write-Host "SUCCESS: $successCount" -ForegroundColor Green
    Write-Host "FAILED: $failCount" -ForegroundColor Red
    foreach ($result in $setupResults) {
        $fg = if ($result.Success) { "Green" } else { "Red" }
        $msg = if ($result.Used) { " (Intent: use $($result.Used))" } else { "" }
        Write-Host "$($result.Name): $($result.Success ? 'SUCCESS' : 'FAILED')$msg" -ForegroundColor $fg
    }

    if ($used) {
        Write-Host ">> Ollama/AI will prioritize: $used (per hardware detection)" -ForegroundColor Cyan
    }
    else {
        Write-Host ">> No acceleration hardware found. CPU will be used (expect reduced performance)." -ForegroundColor Yellow
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
