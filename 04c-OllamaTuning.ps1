# 04c-OllamaTuning.ps1 - Ollama Hardware Tuning and Configuration
# Purpose: Detects, prioritizes, and configures optimal hardware (NPU/GPU/CPU) for Ollama LLM inference.
# Last edit: 2025-07-14 - Integrated Get-AvailableHardware for simplified hardware detection

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "4.3.0"
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

# Personality traits import
function Import-PersonalityTraits {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Importing personality traits..." -Level "INFO" -LogFile $LogFile
    try {
        $personalityFile = Join-Path $projectRoot "jarvis_personality.json"
        if (Test-Path $personalityFile) {
            $traits = Get-Content $personalityFile -Raw | ConvertFrom-Json
            Write-Log -Message "Loaded personality: $($traits.identity.name)" -Level "SUCCESS" -LogFile $LogFile
            $env:OLLAMA_PERSONALITY = $traits.identity.name
            return $true
        }
        Write-Log -Message "No jarvis_personality.json found, using default JARVIS traits" -Level "INFO" -LogFile $LogFile
        $env:OLLAMA_PERSONALITY = "JARVIS"
        return $true
    }
    catch {
        Write-Log -Message "Failed to import personality: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        $env:OLLAMA_PERSONALITY = "JARVIS"
        return $false
    }
}

# CUDA installation check
function Test-CUDAInstallation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Checking CUDA status..." -Level "INFO" -LogFile $LogFile
    $cudaStatus = @{Installed = $false; Version = ""; Path = "" }
    
    if ($hardware.GPU.Type -eq "NVIDIA" -and $hardware.GPU.CUDACapable) {
        $cudaStatus.Installed = $true
        $cudaStatus.Version = "Detected"  # Version could be refined if Get-AvailableHardware provides it
        Write-Log -Message "CUDA capable NVIDIA GPU detected" -Level "SUCCESS" -LogFile $LogFile
    }
    return $cudaStatus
}

# Install CUDA
function Install-CUDAToolkit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Installing CUDA Toolkit..." -Level "INFO" -LogFile $LogFile
    try {
        if (Test-Command -Command "winget" -LogFile $LogFile) {
            winget install --id "NVIDIA.CUDA" --silent --accept-package-agreements --accept-source-agreements 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Message "CUDA installed via winget" -Level ‘SUCCESS’ -LogFile $LogFile
                return $true
            }
        }
        Write-Log -Message "Manual CUDA installation required: https://developer.nvidia.com/cuda-downloads" -Level "INFO" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "CUDA installation failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Ollama configuration
function Set-OllamaConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Hardware,
        [hashtable]$CudaStatus,
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Configuring Ollama for optimal performance..." -Level "INFO" -LogFile $LogFile
    $config = @{EnvironmentVars = @{}; RestartRequired = $false; Instructions = @() }
    
    switch ($Hardware.OptimalConfig) {
        "Qualcomm_NPU" {
            $config.EnvironmentVars = @{
                "OLLAMA_NPU"               = "1"
                "OLLAMA_USE_NPU"           = "1"
                "OLLAMA_PREFER_NPU"        = "1"
                "OLLAMA_NUM_PARALLEL"      = "2"
                "OLLAMA_MAX_LOADED_MODELS" = "1"
                "OLLAMA_KEEP_ALIVE"        = "2m"
                "OLLAMA_MAX_VRAM"          = "0"
                "OLLAMA_GPU_LAYERS"        = "0"
                "OLLAMA_FLASH_ATTENTION"   = "1"
                "OLLAMA_F16_KV"            = "1"
                "OLLAMA_CONTEXT_LENGTH"    = "2048"
                "OLLAMA_BATCH_SIZE"        = "128"
                "OLLAMA_N_BATCH"           = "128"
                "OLLAMA_ARM64_NATIVE"      = "1"
                "OLLAMA_LOW_MEM"           = "1"
                "OLLAMA_NPU_ONLY"          = "1"
                "OLLAMA_DISABLE_GPU"       = "1"
                "OLLAMA_CPU_FALLBACK"      = "0"
                "OLLAMA_NUM_THREAD"        = "8"
                "OMP_NUM_THREADS"          = "8"
            }
            $config.Instructions += "🚀 Qualcomm NPU optimized"
            $config.RestartRequired = $true
        }
        "NVIDIA_GPU" {
            if ($CudaStatus.Installed) {
                $config.EnvironmentVars = @{
                    "OLLAMA_CUDA"            = "1"
                    "OLLAMA_GPU_LAYERS"      = "-1"
                    "OLLAMA_NUM_PARALLEL"    = "4"
                    "OLLAMA_FLASH_ATTENTION" = if ($Hardware.GPU.VRAM -le 8) { "1" } else { "0" }
                    "OLLAMA_LOW_VRAM"        = if ($Hardware.GPU.VRAM -le 4) { "1" } else { "0" }
                }
                $config.Instructions += "✅ NVIDIA GPU acceleration enabled"
                $config.RestartRequired = $true
            }
            else {
                $config.Instructions += "❌ CUDA not installed"
            }
        }
        default {
            $optimalThreads = [Math]::Min($Hardware.CPU.Cores, ($Hardware.Platform -eq "ARM64" ? 8 : 12))
            $config.EnvironmentVars = @{
                "OLLAMA_NUM_PARALLEL"      = $optimalThreads.ToString()
                "OLLAMA_MAX_LOADED_MODELS" = "1"
                "OLLAMA_ARM64_OPTIMIZED"   = if ($Hardware.Platform -eq "ARM64") { "1" } else { "0" }
            }
            $config.Instructions += "🔧 CPU optimized with $optimalThreads threads"
            $config.RestartRequired = $true
        }
    }
    
    foreach ($var in $config.EnvironmentVars.GetEnumerator()) {
        try {
            [System.Environment]::SetEnvironmentVariable($var.Key, $var.Value, "User")
            Set-Item -Path "env:$($var.Key)" -Value $var.Value
            Write-Log -Message "Set $($var.Key) = $($var.Value)" -Level "INFO" -LogFile $LogFile
        }
        catch {
            Write-Log -Message "Failed to set $($var.Key): $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        }
    }
    
    return $config
}

# Model optimization
function Optimize-OllamaModels {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Hardware,
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Optimizing Ollama models..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-OllamaRunning -LogFile $LogFile)) {
        Write-Log -Message "Ollama not running - cannot optimize models" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 10 -ErrorAction Stop
        $installedModels = $response.models
        $recommendedModels = switch ($Hardware.OptimalConfig) {
            "Qualcomm_NPU" { @("phi3:mini", "gemma2:2b", "llama3.2:3b") }
            "NVIDIA_GPU" { if ($Hardware.GPU.VRAM -ge 8) { @("llama3.1:8b", "codellama:7b") } else { @("phi3:mini", "gemma2") } }
            default { @("phi3:mini", "gemma2:2b") }
        }
        
        if ($InstallOptimalModels -or -not $installedModels) {
            Write-Log -Message "Installing recommended models..." -Level "INFO" -LogFile $LogFile
            foreach ($model in $recommendedModels) {
                try {
                    & ollama pull $model 2>&1
                    Write-Log -Message "Installed $model" -Level "SUCCESS" -LogFile $LogFile
                }
                catch {
                    Write-Log -Message "Failed to install ${$model}: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
                }
            }
        }
        
        if ($OptimizeExisting -or -not $InstallOptimalModels) {
            Write-Log -Message "Checking for non-optimal models..." -Level "INFO" -LogFile $LogFile
            $largeModels = $installedModels | Where-Object { $_.size -gt 4GB -and $_.name -notlike "*phi3:mini*" -and $_.name -notlike "*gemma2:2b*" }
            foreach ($model in $largeModels) {
                Write-Log -Message "Consider removing large model: $($model.name) ($('{0:N1}' -f ($model.size / 1GB)) GB)" -Level "INFO" -LogFile $LogFile
            }
        }
        
        return $true
    }
    catch {
        Write-Log -Message "Model optimization failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Performance benchmark
function Test-OllamaPerformance {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Hardware,
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Running performance benchmark..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-OllamaRunning -LogFile $LogFile)) {
        Write-Log -Message "Ollama not running - cannot benchmark" -Level "ERROR" -LogFile $LogFile
        return $null
    }
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 10 -ErrorAction Stop
        if (-not $response.models) {
            Write-Log -Message "No models available for benchmarking" -Level "ERROR" -LogFile $LogFile
            return $null
        }
        
        $preferredModels = switch ($Hardware.OptimalConfig) {
            "Qualcomm_NPU" { @("phi3:mini", "gemma2:2b", "llama3.2:3b") }
            "NVIDIA_GPU" { @("llama3.1:8b", "gemma2", "phi3:mini") }
            default { @("phi3:mini", "gemma2:2b") }
        }
        
        $testModel = $null
        foreach ($preferred in $preferredModels) {
            $found = $response.models | Where-Object { $_.name -eq $preferred -or $_.name -like "*$($preferred.Split(':')[0])*" }
            if ($found) {
                $testModel = $found[0].name
                break
            }
        }
        if (-not $testModel) {
            $testModel = ($response.models | Sort-Object size | Select-Object -First 1).name
        }
        
        Write-Log -Message "Benchmarking with $testModel" -Level "INFO" -LogFile $LogFile
        $prompts = @(
            @{Name = "Arithmetic"; Prompt = "What is 7 + 8?"; Timeout = 45 },
            @{Name = "Reasoning"; Prompt = "List 3 colors quickly."; Timeout = 45 },
            @{Name = "Complex"; Prompt = "Explain AI in 50 words."; Timeout = 90 }
        )
        
        $results = @()
        foreach ($p in $prompts) {
            $body = @{model = $testModel; prompt = $p.Prompt; stream = $false } | ConvertTo-Json
            $startTime = Get-Date
            $result = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $p.Timeout
            $time = [int](($endTime = Get-Date) - $startTime).TotalMilliseconds
            $tokensPerSecond = if ($result.eval_count -and $result.eval_duration) { [math]::Round(($result.eval_count / ($result.eval_duration / 1E9)), 2) } else { "Unknown" }
            $results += @{Name = $p.Name; Time = $time; TokensPerSecond = $tokensPerSecond }
        }
        
        $avgTime = [int](($results | Measure-Object Time -Average).Average)
        $category = switch ($Hardware.OptimalConfig) {
            "Qualcomm_NPU" { if ($avgTime -lt 1500) { "Excellent" } elseif ($avgTime -lt 3000) { "Good" } else { "Acceptable" } }
            "NVIDIA_GPU" { if ($avgTime -lt 1000) { "Excellent" } elseif ($avgTime -lt 3000) { "Good" } else { "Acceptable" } }
            default { if ($avgTime -lt 2000) { "Excellent" } elseif ($avgTime -lt 6000) { "Good" } else { "Acceptable" } }
        }
        
        $benchmark = @{
            Model       = $testModel
            Hardware    = $Hardware.OptimalConfig
            Platform    = $Hardware.Platform
            Tests       = $results
            AverageTime = $avgTime
            Category    = $category
        }
        
        Write-Log -Message "Benchmark Results: $avgTime ms ($category)" -Level "SUCCESS" -LogFile $LogFile
        foreach ($r in $results) {
            Write-Log -Message "$($r.Name): $($r.Time)ms" -Level "INFO" -LogFile $LogFile
            if ($r.TokensPerSecond -ne "Unknown") {
                Write-Log -Message "Speed: $($r.TokensPerSecond) tokens/sec" -Level "INFO" -LogFile $LogFile
            }
        }
        
        try {
            $benchmark | ConvertTo-Json -Depth 4 | Set-Content "$logsDir\benchmark-$timestamp.json"
            Write-Log -Message "Benchmark saved: $logsDir\benchmark-$timestamp.json" -Level "INFO" -LogFile $LogFile
        }
        catch {
            Write-Log -Message "Failed to save benchmark: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        }
        
        return $benchmark
    }
    catch {
        Write-Log -Message "Benchmark failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $null
    }
}

# Stop Ollama
function Stop-OllamaService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Stopping Ollama processes..." -Level "INFO" -LogFile $LogFile
    try {
        $processes = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
        if ($processes) {
            $processes | ForEach-Object { $_.Kill(); $_.WaitForExit(5000) }
            Write-Log -Message "Ollama processes stopped" -Level "SUCCESS" -LogFile $LogFile
        }
        return $true
    }
    catch {
        Write-Log -Message "Error stopping Ollama: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Start Ollama
function Start-OllamaService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Starting Ollama..." -Level "INFO" -LogFile $LogFile
    try {
        $ollamaPath = Get-Command "ollama" -ErrorAction Stop | Select-Object -ExpandProperty Source
        $process = Start-Process -FilePath $ollamaPath -ArgumentList "serve" -WindowStyle Hidden -PassThru -ErrorAction Stop
        $attempts = 0
        while (-not (Test-OllamaRunning -LogFile $LogFile) -and $attempts -lt 15) {
            Start-Sleep -Seconds 2
            $attempts++
        }
        if (Test-OllamaRunning -LogFile $LogFile) {
            Write-Log -Message "Ollama started (PID: $($process.Id))" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Ollama failed to start" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Failed to start Ollama: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Validate Ollama setup
function Test-OllamaSetup {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Hardware,
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Validating Ollama setup..." -Level "INFO" -LogFile $LogFile
    $results = @()
    
    $installed = Test-Command -Command "ollama" -LogFile $LogFile
    $results += $installed ? "✅ Ollama installed" : "❌ Ollama not installed"
    
    $running = Test-OllamaRunning -LogFile $LogFile
    $results += $running ? "✅ Ollama service running" : "❌ Ollama service not running"
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
        $results += ($response.models.name -contains "phi3:mini") ? 
        "✅ phi3:mini model available" : 
        "❌ phi3:mini model not installed"
    }
    catch {
        $results += "❌ Model check failed: $($_.Exception.Message)"
    }
    
    $deviceType = $Hardware.OptimalConfig
    $results += if ($deviceType -eq "Qualcomm_NPU" -or $deviceType -eq "Intel_NPU") { 
        "✅ Optimal hardware (NPU) detected" 
    }
    elseif ($deviceType -eq "NVIDIA_GPU") { 
        "✅ Good hardware (GPU) detected" 
    }
    else { 
        "⚠️  Suboptimal hardware (CPU) detected" 
    }
    
    Write-Log -Message "=== VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $results) {
        Write-Log -Message $result -Level ($result -like "✅*" ? "SUCCESS" : ($result -like "⚠️*" ? "WARN" : "ERROR")) -LogFile $LogFile
    }
    
    $successCount = ($results | Where-Object { $_ -like "✅*" }).Count
    Write-Log -Message "Validation: $successCount/$($results.Count) checks passed" -Level ($successCount -eq $results.Count ? "SUCCESS" : "ERROR") -LogFile $LogFile
    return $successCount -eq $results.Count
}

try {
    # Main execution
    Write-Log -Message "JARVIS Ollama Tuning (v$scriptVersion) Starting..." -Level "SUCCESS" -LogFile $logFile
    
    if (-not (Test-Command -Command "ollama" -LogFile $logFile)) {
        Write-Log -Message "Ollama not installed. Run 04a-OllamaSetup.ps1 first." -Level "ERROR" -LogFile $logFile
        Stop-Transcript
        exit 1
    }

    $results = @()
    $shouldOptimize = $Run -or (-not ($Install -or $Configure -or $Test))

    if ($Install -or $shouldOptimize) {
        Write-Log -Message "=== ACCELERATION INSTALLATION ===" -Level "INFO" -LogFile $logFile
        $cudaStatus = if ($hardware.GPU.Type -eq "NVIDIA") { Test-CUDAInstallation -LogFile $logFile } else { @{Installed = $false } }
        $installSuccess = if ($hardware.GPU.Type -eq "NVIDIA" -and -not $cudaStatus.Installed) {
            Install-CUDAToolkit -LogFile $logFile
        }
        else {
            Write-Log -Message "No acceleration installation needed" -Level "INFO" -LogFile $logFile
            $true
        }
        $results += @{Name = "CUDA Installation"; Success = $installSuccess }
    }

    if ($Configure -or $shouldOptimize) {
        Write-Log -Message "=== HARDWARE CONFIGURATION ===" -Level "INFO" -LogFile $logFile
        $cudaStatus = if ($hardware.GPU.Type -eq "NVIDIA") { Test-CUDAInstallation -LogFile $logFile } else { @{Installed = $false } }
        $config = Set-OllamaConfiguration -Hardware $hardware -CudaStatus $cudaStatus -LogFile $logFile
        foreach ($inst in $config.Instructions) { Write-Log -Message $inst -Level "INFO" -LogFile $logFile }
        if ($config.RestartRequired) { Write-Log -Message "⚠️ Ollama restart required" -Level "WARN" -LogFile $logFile }
        $results += @{Name = "Ollama Configuration"; Success = $true }
    }

    if ($Test -or $shouldOptimize) {
        Write-Log -Message "=== PERFORMANCE TESTING ===" -Level "INFO" -LogFile $logFile
        $restartSuccess = if (Stop-OllamaService -LogFile $logFile) { Start-OllamaService -LogFile $logFile } else { $false }
        $benchmarkResult = if ($restartSuccess) { Test-OllamaPerformance -Hardware $hardware -LogFile $logFile } else { $null }
        $results += @{Name = "Performance Benchmark"; Success = $null -ne $benchmarkResult }
        
        Write-Log -Message "=== VALIDATION ===" -Level "INFO" -LogFile $logFile
        $results += @{Name = "Ollama Setup Validation"; Success = (Test-OllamaSetup -Hardware $hardware -LogFile $logFile) }
    }

    if ($shouldOptimize) {
        Write-Log -Message "=== PERSONALITY IMPORT ===" -Level "INFO" -LogFile $logFile
        $results += @{Name = "Personality Import"; Success = (Import-PersonalityTraits -LogFile $logFile) }
        
        Write-Log -Message "=== MODEL OPTIMIZATION ===" -Level "INFO" -LogFile $logFile
        $results += @{Name = "Model Optimization"; Success = (Optimize-OllamaModels -Hardware $hardware -LogFile $logFile) }
    }

    Write-Log -Message "=== SUMMARY ===" -Level "INFO" -LogFile $logFile
    $successCount = ($results | Where-Object { $_.Success }).Count
    foreach ($result in $results) {
        Write-Log -Message "$($result.Name): $($result.Success ? 'SUCCESS' : 'FAILED')" -Level ($result.Success ? "SUCCESS" : "ERROR") -LogFile $logFile
    }
    Write-Log -Message "Tuning: $successCount/$($results.Count) tasks completed successfully" -Level ($successCount -eq $results.Count ? "SUCCESS" : "ERROR") -LogFile $logFile

    if ($successCount -ne $results.Count) {
        Write-Log -Message "Review logs: $logFile" -Level "INFO" -LogFile $logFile
        Stop-Transcript
        exit 1
    }

    Write-Log -Message "Log Files: $transcriptFile, $logFile" -Level "INFO" -LogFile $logFile
    if ($hardware.Platform -eq "ARM64") {
        Write-Log -Message "ARM64 optimizations active for NPU" -Level "SUCCESS" -LogFile $logFile
    }
    Write-Log -Message "JARVIS Ollama Tuning (v$scriptVersion) Complete!" -Level "SUCCESS" -LogFile $logFile

    # === Colorized summary output ===
    $successCount = ($results | Where-Object { $_.Success }).Count
    $failCount = ($results | Where-Object { -not $_.Success }).Count
    Write-Host "SUCCESS: $successCount" -ForegroundColor Green
    Write-Host "FAILED: $failCount" -ForegroundColor Red
    foreach ($result in $results) {
        $fg = if ($result.Success) { "Green" } else { "Red" }
        Write-Host "$($result.Name): $($result.Success ? 'SUCCESS' : 'FAILED')" -ForegroundColor $fg
    }
    Write-Log -Message "Tuning complete." -Level SUCCESS -LogFile $logFile
}
catch {
    Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}
Write-Log -Message "$scriptPrefix v$scriptVersion complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript