# 04b-OllamaDiag.ps1 (v4.1) - Diagnoses hardware for Ollama compatibility
# JARVIS AI Assistant - Detects and prioritizes NPU/GPU/CPU for optimal performance

param(
    [switch]$Diagnose,
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
$transcriptFile = Join-Path $logsDir "04b-ollama-diag-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "04b-ollama-diag-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile

# Get GPU/NPU/CPU information
function Get-GPUInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Detecting hardware for Ollama..." -Level "INFO" -LogFile $LogFile
    try {
        # GPU Detection
        $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notlike "*Microsoft Remote Display Adapter*" }
        
        # NPU Detection
        $processors = Get-CimInstance Win32_Processor
        $npus = @()
        foreach ($proc in $processors) {
            $procName = $proc.Name
            if ($procName -like "*Snapdragon*" -and $procName -like "*X*") {
                $npus += [PSCustomObject]@{
                    Name          = "Qualcomm Hexagon NPU ($procName)"
                    DriverVersion = "N/A"
                    PNPDeviceID   = "QUALCOMM_NPU"
                }
            }
            elseif ($procName -like "*Core*Ultra*" -and ($procName -like "*125*" -or $procName -like "*155*" -or $procName -like "*165*")) {
                $npus += [PSCustomObject]@{
                    Name          = "Intel AI Boost NPU ($procName)"
                    DriverVersion = "N/A"
                    PNPDeviceID   = "INTEL_NPU"
                }
            }
        }

        # Log detected devices
        Write-Log -Message "Detected Devices:" -Level "INFO" -LogFile $LogFile
        if ($npus) {
            foreach ($npu in $npus) {
                Write-Log -Message "  - NPU: $($npu.Name) (Driver: $($npu.DriverVersion))" -Level "INFO" -LogFile $LogFile
            }
        }
        else {
            Write-Log -Message "  - No NPUs detected" -Level "INFO" -LogFile $LogFile
        }
        if ($gpus) {
            foreach ($gpu in $gpus) {
                Write-Log -Message "  - GPU: $($gpu.Name) (Driver: $($gpu.DriverVersion))" -Level "INFO" -LogFile $LogFile
            }
        }
        else {
            Write-Log -Message "  - No GPUs detected" -Level "INFO" -LogFile $LogFile
        }

        # Prioritize devices: NPU > Discrete GPU (NVIDIA/AMD) > Integrated GPU > CPU
        $allDevices = @()
        foreach ($npu in $npus) {
            $allDevices += [PSCustomObject]@{
                Type          = "NPU"
                Name          = $npu.Name
                DriverVersion = $npu.DriverVersion
                Priority      = 1
            }
        }
        foreach ($gpu in $gpus) {
            $priority = if ($gpu.Name -match "NVIDIA|AMD") { 2 }
            elseif ($gpu.Name -match "Intel|Qualcomm.*Adreno") { 3 }
            else { 4 }
            $allDevices += [PSCustomObject]@{
                Type          = "GPU"
                Name          = $gpu.Name
                DriverVersion = $gpu.DriverVersion
                Priority      = $priority
            }
        }

        # Add CPU as fallback
        if (-not $allDevices) {
            $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            $allDevices += [PSCustomObject]@{
                Type          = "CPU"
                Name          = $cpu.Name
                DriverVersion = "N/A"
                Priority      = 5
            }
            Write-Log -Message "No NPU or GPU detected, falling back to CPU (performance may be poor)" -Level "WARN" -LogFile $LogFile
        }

        # Select highest-priority device
        $selectedDevice = $allDevices | Sort-Object Priority | Select-Object -First 1
        if ($selectedDevice) {
            $name = $selectedDevice.Name
            $driverVersion = $selectedDevice.DriverVersion
            $deviceType = $selectedDevice.Type
            $cudaAvailable = if ($deviceType -eq "GPU" -and $name -match "NVIDIA" -and (Test-Command -Command "nvidia-smi" -LogFile $LogFile)) { "Yes" } else { "No" }
            Write-Log -Message "Selected ${deviceType}: $name (Driver: $driverVersion, CUDA: $cudaAvailable)" -Level "SUCCESS" -LogFile $LogFile
            return @{Name = $name; DriverVersion = $driverVersion; CudaAvailable = $cudaAvailable; Type = $deviceType }
        }
        Write-Log -Message "No valid device selected" -Level "ERROR" -LogFile $LogFile
        return $null
    }
    catch {
        Write-Log -Message "Device detection failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        Write-Log -Message "Falling back to CPU: $($cpu.Name) (performance may be poor)" -Level "WARN" -LogFile $LogFile
        return @{Name = $cpu.Name; DriverVersion = "N/A"; CudaAvailable = "No"; Type = "CPU" }
    }
}

# Test Ollama compatibility
function Test-OllamaCompatibility {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Testing Ollama compatibility..." -Level "INFO" -LogFile $LogFile
    $results = @()
    
    # Check Ollama installation
    $installed = Test-Command -Command "ollama" -LogFile $LogFile
    $results += $installed ? "✅ Ollama installed" : "❌ Ollama not installed"
    
    # Check Ollama service
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
        $results += "✅ Ollama service running"
        $phi3Installed = $response.models.name -contains "phi3:mini"
        $results += $phi3Installed ? "✅ phi3:mini model available" : "❌ phi3:mini model not installed"
    }
    catch {
        $results += "❌ Ollama service not running: $($_.Exception.Message)"
        $results += "❌ phi3:mini model check skipped"
    }
    
    # Check hardware compatibility
    $deviceInfo = Get-GPUInfo -LogFile $LogFile
    $deviceType = $deviceInfo.Type
    if ($deviceType -eq "NPU") {
        $results += "✅ Optimal hardware (NPU) detected: $($deviceInfo.Name)"
    }
    elseif ($deviceType -eq "GPU" -and $deviceInfo.CudaAvailable -eq "Yes") {
        $results += "✅ Good hardware (CUDA-capable GPU) detected: $($deviceInfo.Name)"
    }
    elseif ($deviceType -eq "GPU") {
        $results += "⚠️  GPU detected but CUDA not available: $($deviceInfo.Name)"
    }
    else {
        $results += "⚠️  CPU-only detected (performance may be poor): $($deviceInfo.Name)"
    }
    
    Write-Log -Message "=== COMPATIBILITY RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $results) {
        Write-Log -Message $result -Level ($result -like "✅*" ? "SUCCESS" : ($result -like "⚠️*" ? "WARN" : "ERROR")) -LogFile $LogFile
    }
    
    $successCount = ($results | Where-Object { $_ -like "✅*" }).Count
    $warningCount = ($results | Where-Object { $_ -like "⚠️*" }).Count
    Write-Log -Message "Compatibility: $successCount/$($results.Count) checks passed, $warningCount warnings" -Level ($successCount -eq $results.Count ? "SUCCESS" : "WARN") -LogFile $LogFile
    return $successCount -eq $results.Count
}

# Main execution
Write-Log -Message "JARVIS Ollama Diagnostics (v4.1) Starting..." -Level "SUCCESS" -LogFile $logFile
Write-SystemInfo -ScriptName "04b-OllamaDiag.ps1" -Version "4.1" -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Diagnose = $Diagnose
    Test     = $Test
    All      = $All
}

if (-not ($Diagnose -or $Test)) {
    $All = $true
}

$results = @()
if ($Diagnose -or $All) {
    Write-Log -Message "=== HARDWARE DIAGNOSTICS ===" -Level "INFO" -LogFile $logFile
    $deviceInfo = Get-GPUInfo -LogFile $logFile
    $results += @{Name = "Hardware Detection"; Success = $null -ne $deviceInfo }
}

if ($Test -or $All) {
    Write-Log -Message "=== COMPATIBILITY TEST ===" -Level "INFO" -LogFile $logFile
    $results += @{Name = "Ollama Compatibility"; Success = (Test-OllamaCompatibility -LogFile $logFile) }
}

Write-Log -Message "=== SUMMARY ===" -Level "INFO" -LogFile $logFile
$successCount = ($results | Where-Object { $_.Success }).Count
foreach ($result in $results) {
    Write-Log -Message "$($result.Name): $($result.Success ? 'SUCCESS' : 'FAILED')" -Level ($result.Success ? "SUCCESS" : "ERROR") -LogFile $logFile
}
Write-Log -Message "Diagnostics: $successCount/$($results.Count) tasks completed successfully" -Level ($successCount -eq $results.Count ? "SUCCESS" : "ERROR") -LogFile $logFile

if ($successCount -ne $results.Count) {
    Write-Log -Message "Review logs: $logFile" -Level "INFO" -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "Log Files: $transcriptFile, $logFile" -Level "INFO" -LogFile $logFile
Write-Log -Message "JARVIS Ollama Diagnostics (v4.1) Complete!" -Level "SUCCESS" -LogFile $logFile

Stop-Transcript