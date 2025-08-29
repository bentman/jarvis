# 04-OllamaConfig.ps1 - Combined Ollama Setup, Diagnostics and Tuning
# Purpose: Consolidated script combining 04a-OllamaSetup, 04b-OllamaDiag, and 04c-OllamaTuning
# Last edit: 2025-08-26 - Fixed syntax errors, GPU memory configuration, and duplicate execution

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "5.0.2"
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
if (-not ($Install -or $Configure -or $Test)) { $Run = $true }

Write-SystemInfo -ScriptName $scriptPrefix -Version $scriptVersion -ProjectRoot $projectRoot -LogFile $logFile -Switches @{ Install=$Install; Configure=$Configure; Test=$Test; Run=$Run }

$hardware = Get-AvailableHardware -LogFile $logFile

# -------------------------
# Functions (merged from 04a/04b/04c with fixes)
# -------------------------

function Test-Prerequisites {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing prerequisites for Ollama setup..." -Level INFO -LogFile $LogFile
    if (-not (Test-Command -Command "winget" -LogFile $LogFile)) {
        Write-Log -Message "winget not available. Run 01-Prerequisites.ps1 to install." -Level ERROR -LogFile $LogFile
        return $false
    }
    Write-Log -Message "All prerequisites verified for Ollama setup" -Level SUCCESS -LogFile $LogFile
    return $true
}

function Test-OllamaInstallation {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing Ollama installation status..." -Level INFO -LogFile $LogFile
    try {
        $ollamaCmd = Get-Command "ollama" -ErrorAction SilentlyContinue
        if ($ollamaCmd) {
            $versionOutput = & ollama --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Message "Ollama is installed and functional: $($ollamaCmd.Source)" -Level SUCCESS -LogFile $LogFile
                Write-Log -Message "Version: $versionOutput" -Level INFO -LogFile $LogFile
                return $true
            }
            else {
                Write-Log -Message "Ollama found but not functional" -Level WARN -LogFile $LogFile
                return $false
            }
        }
        else {
            Write-Log -Message "Ollama not found in PATH" -Level INFO -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error testing Ollama installation: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Install-OllamaApplication {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Installing Ollama application..." -Level INFO -LogFile $LogFile
    if (Test-OllamaInstallation -LogFile $LogFile) {
        Write-Log -Message "Ollama already installed - skipping installation" -Level INFO -LogFile $LogFile
        return $true
    }
    try {
        Write-Log -Message "Installing Ollama via winget..." -Level INFO -LogFile $LogFile
        $installResult = winget install --id "Ollama.Ollama" --exact --silent --accept-package-agreements --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Ollama installed successfully via winget" -Level SUCCESS -LogFile $LogFile
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 3
            if (Test-OllamaInstallation -LogFile $LogFile) {
                Write-Log -Message "Ollama installation verified successfully" -Level SUCCESS -LogFile $LogFile
                return $true
            }
            else {
                Write-Log -Message "Ollama installed but verification failed. Try restarting terminal or manually add Ollama to PATH." -Level WARN -LogFile $LogFile
                return $false
            }
        }
        else {
            Write-Log -Message "Ollama installation failed: $installResult" -Level ERROR -LogFile $LogFile
            Write-Log -Message "Try manual installation from https://ollama.ai/download." -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Exception during Ollama installation: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Write-Log -Message "Check winget functionality or try manual installation." -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Test-OllamaModels {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing Ollama model availability..." -Level INFO -LogFile $LogFile
    $targetModel = Get-JarvisModel -LogFile $LogFile
    Write-Log -Message "Target model: $targetModel" -Level INFO -LogFile $LogFile
    try {
        $modelList = ollama list 2>$null
        if ($LASTEXITCODE -eq 0) {
            if ($modelList -match [regex]::Escape($targetModel)) {
                Write-Log -Message "Required model $targetModel is available" -Level SUCCESS -LogFile $LogFile
                return $true
            }
            else {
                Write-Log -Message "Required model $targetModel not found in available models" -Level WARN -LogFile $LogFile
                return $false
            }
        }
        else {
            Write-Log -Message "Failed to list Ollama models" -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error testing Ollama models: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Install-OllamaModels {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Installing required Ollama models..." -Level INFO -LogFile $LogFile
    if (Test-OllamaModels -LogFile $LogFile) {
        Write-Log -Message "Required models already available - skipping installation" -Level INFO -LogFile $LogFile
        return $true
    }
    $targetModel = Get-JarvisModel -LogFile $LogFile
    try {
        Write-Log -Message "Downloading model: $targetModel (this may take several minutes)..." -Level INFO -LogFile $LogFile
        $pullResult = ollama pull $targetModel 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Model $targetModel downloaded successfully" -Level SUCCESS -LogFile $LogFile
            if (Test-OllamaModels -LogFile $LogFile) {
                Write-Log -Message "Model installation verified successfully" -Level SUCCESS -LogFile $LogFile
                return $true
            }
            else {
                Write-Log -Message "Model downloaded but verification failed" -Level WARN -LogFile $LogFile
                return $false
            }
        }
        else {
            Write-Log -Message "Model download failed: $pullResult" -Level ERROR -LogFile $LogFile
            Write-Log -Message "Check internet connection and try: ollama pull $targetModel." -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Exception during model installation: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Write-Log -Message "Ensure Ollama service is running and try manual model pull." -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Test-OllamaConfiguration {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing Ollama configuration..." -Level INFO -LogFile $LogFile
    try {
        $envValid = Test-EnvironmentConfig -LogFile $LogFile
        if (-not $envValid) {
            Write-Log -Message "Environment configuration needs update" -Level WARN -LogFile $LogFile
            return $false
        }
        $targetModel = Get-JarvisModel -LogFile $LogFile
        if (-not $targetModel) {
            Write-Log -Message "Model configuration invalid" -Level ERROR -LogFile $LogFile
            return $false
        }
        Write-Log -Message "Ollama configuration is valid" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Error testing Ollama configuration: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Test-OllamaFunctionality {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing Ollama functionality with basic inference..." -Level INFO -LogFile $LogFile
    if (-not (Test-OllamaService -LogFile $LogFile)) {
        Write-Log -Message "Ollama service not available for functionality test" -Level ERROR -LogFile $LogFile
        return $false
    }
    $targetModel = Get-JarvisModel -LogFile $LogFile
    try {
        Write-Log -Message "Testing inference with model: $targetModel" -Level INFO -LogFile $LogFile
        $testPrompt = "Hello"
        $body = @{ model = $targetModel; prompt = $testPrompt; stream = $false } | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30
        Write-Log -Message "Raw response type: $($response.GetType().Name)" -Level INFO -LogFile $LogFile
        Write-Log -Message "Response has 'response' field: $($null -ne $response.response)" -Level INFO -LogFile $LogFile
        
        # Check for actual response content (not just empty string)
        if ($response -and $response.response -and $response.response.Length -gt 0 -and $response.response.Trim() -ne "") {
            Write-Log -Message "Ollama functionality test passed - generated response" -Level SUCCESS -LogFile $LogFile
            Write-Log -Message "Test response: $($response.response.Substring(0, [Math]::Min(50, $response.response.Length)))..." -Level INFO -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Ollama functionality test failed - empty or no response generated" -Level ERROR -LogFile $LogFile
            Write-Log -Message "Response object: $($response | ConvertTo-Json -Compress)" -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Ollama functionality test failed: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        if ($_.Exception.Message -match "more system memory.*than is available") {
            Write-Log -Message "GPU memory configuration issue detected - will adjust settings" -Level WARN -LogFile $LogFile
        }
        return $false
    }
}

function New-OllamaValidationSummary {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    $validationResults = @()
    if (Test-OllamaInstallation -LogFile $LogFile) { $validationResults += "✅ Ollama Application: Installed and functional" } else { $validationResults += "❌ Ollama Application: Not installed or not functional" }
    if (Test-OllamaService -LogFile $LogFile) { $validationResults += "✅ Ollama Service: Running and accessible" } else { $validationResults += "❌ Ollama Service: Not running or not accessible" }
    if (Test-OllamaModels -LogFile $LogFile) { $targetModel = Get-JarvisModel -LogFile $LogFile; $validationResults += "✅ Model Available: $targetModel" } else { $validationResults += "❌ Model Missing: Required model not available" }
    if (Test-OllamaConfiguration -LogFile $LogFile) { $validationResults += "✅ Configuration: Environment and model config valid" } else { $validationResults += "❌ Configuration: Issues detected" }
    if (Test-OllamaFunctionality -LogFile $LogFile) { $validationResults += "✅ Functionality: Basic inference working" } else { $validationResults += "❌ Functionality: Inference test failed" }
    Get-OptimalConfiguration -Hardware $hardware | Out-Null
    $validationResults += "ℹ️ Hardware: $($hardware.OptimalConfig) optimization active"
    return $validationResults
}

function Import-PersonalityTraits {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
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

function Test-CUDAInstallation {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Checking CUDA status..." -Level "INFO" -LogFile $LogFile
    $cudaStatus = @{Installed = $false; Version = ""; Path = "" }
    if ($hardware.GPU.Type -eq "NVIDIA" -and $hardware.GPU.CUDACapable) {
        $cudaStatus.Installed = $true
        $cudaStatus.Version = "Detected"
        Write-Log -Message "CUDA capable NVIDIA GPU detected" -Level "SUCCESS" -LogFile $LogFile
    }
    return $cudaStatus
}

function Install-CUDAToolkit {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Installing CUDA Toolkit..." -Level "INFO" -LogFile $LogFile
    try {
        if (Test-Command -Command "winget" -LogFile $LogFile) {
            winget install --id "NVIDIA.CUDA" --silent --accept-package-agreements --accept-source-agreements 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Message "CUDA installed via winget" -Level 'SUCCESS' -LogFile $LogFile
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

function Set-OllamaConfiguration {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [Parameter(Mandatory = $true)] [hashtable]$Hardware,
        [hashtable]$CudaStatus
    )
    Write-Log -Message "Configuring Ollama for optimal performance..." -Level "INFO" -LogFile $LogFile
    
    # Get the optimal configuration from 00-CommonUtils.ps1 (the single source of truth)
    $config = Get-OptimalConfiguration -Hardware $Hardware
    
    # Apply the environment variables
    foreach ($var in $config.EnvironmentVars.GetEnumerator()) {
        try {
            [System.Environment]::SetEnvironmentVariable($var.Key, $var.Value, "Process")
            Set-Item -Path "env:$($var.Key)" -Value $var.Value
            Write-Log -Message "Set $($var.Key) = $($var.Value)" -Level "INFO" -LogFile $LogFile
        }
        catch { 
            Write-Log -Message "Failed to set $($var.Key): $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile 
        }
    }
    
    # Display the instructions
    foreach ($instruction in $config.Instructions) { 
        Write-Log -Message $instruction -Level "INFO" -LogFile $LogFile 
    }
    Write-Log -Message "Ollama Environment Variables`n$(Get-ChildItem Env:ollama_*)`n" -Level "INFO" -LogFile $LogFile
    return $config
}

function Optimize-OllamaModels {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [Parameter(Mandatory = $true)] [hashtable]$Hardware
    )
    Write-Log -Message "Optimizing Ollama models..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-OllamaRunning -LogFile $LogFile)) {
        Write-Log -Message "Ollama not running - cannot optimize models" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 10 -ErrorAction Stop
        $installedModels = $response.models
        
        Write-Log -Message "Checking for non-optimal models..." -Level "INFO" -LogFile $logFile
        if ($installedModels) {
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

function Test-OllamaPerformance {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [Parameter(Mandatory = $true)] [hashtable]$Hardware
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
        
        $optimalConfig = Get-OptimalConfiguration -Hardware $Hardware
        $preferredModels = $optimalConfig.ModelRecommendations
        $preferredModels += @("phi3:mini", "gemma2:2b")
        $preferredModels = $preferredModels | Select-Object -Unique
        
        $testModel = $null
        foreach ($preferred in $preferredModels) {
            $found = $response.models | Where-Object { $_.name -eq $preferred -or $_.name -like "*$($preferred.Split(':')[0])*" }
            if ($found) { $testModel = $found[0].name; break }
        }
        if (-not $testModel) { $testModel = ($response.models | Sort-Object size | Select-Object -First 1).name }
        
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
            $time = [int]((Get-Date) - $startTime).TotalMilliseconds
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
        
        Write-Log -Message "Benchmark Results: $avgTime ms ($category)" -Level SUCCESS -LogFile $logFile
        foreach ($r in $results) {
            Write-Log -Message "$($r.Name): $($r.Time)ms" -Level "INFO" -LogFile $logFile
            if ($r.TokensPerSecond -ne "Unknown") { Write-Log -Message "Speed: $($r.TokensPerSecond) tokens/sec" -Level "INFO" -LogFile $logFile }
        }
        
        try {
            $benchmark | ConvertTo-Json -Depth 4 | Set-Content "$logsDir\benchmark-$timestamp.json"
            Write-Log -Message "Benchmark saved: $logsDir\benchmark-$timestamp.json" -Level "INFO" -LogFile $logFile
        }
        catch { 
            Write-Log -Message "Failed to save benchmark: $($_.Exception.Message)" -Level "ERROR" -LogFile $logFile 
        }
        
        return $benchmark
    }
    catch {
        Write-Log -Message "Benchmark failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $logFile
        return $null
    }
}

function Test-OllamaSetup {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [Parameter(Mandatory = $true)] [hashtable]$Hardware
    )
    Write-Log -Message "Validating Ollama setup..." -Level "INFO" -LogFile $LogFile
    $results = @()
    
    $installed = Test-Command -Command "ollama" -LogFile $LogFile
    $results += if ($installed) { "✅ Ollama installed" } else { "❌ Ollama not installed" }
    
    $running = Test-OllamaRunning -LogFile $LogFile
    $results += if ($running) { "✅ Ollama service running" } else { "❌ Ollama service not running" }
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
        $defaultModel = Get-JarvisModel -LogFile $LogFile
        if ($response.models.name -contains $defaultModel) { 
            $results += "✅ $defaultModel model available" 
        } else { 
            $results += "❌ $defaultModel model not installed" 
        }
    }
    catch { 
        $results += "❌ Model check failed: $($_.Exception.Message)" 
    }
    
    $deviceType = $Hardware.OptimalConfig
    $results += if ($deviceType -eq "Qualcomm_NPU" -or $deviceType -eq "Intel_NPU") { 
        "✅ Optimal hardware (NPU) detected" 
    } elseif ($deviceType -eq "NVIDIA_GPU") { 
        "✅ Good hardware (GPU) detected" 
    } else { 
        "⚠️ Suboptimal hardware (CPU) detected" 
    }
    
    Write-Log -Message "=== VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $results) {
        Write-Log -Message $result -Level ($result -like "✅*" ? "SUCCESS" : ($result -like "⚠️*" ? "WARN" : "ERROR")) -LogFile $LogFile
    }
    
    $successCount = ($results | Where-Object { $_ -like "✅*" }).Count
    Write-Log -Message "Validation: $successCount/$($results.Count) checks passed" -Level ($successCount -eq $results.Count ? "SUCCESS" : "ERROR") -LogFile $LogFile
    return $successCount -eq $results.Count
}

# -------------------------
# Main execution (single execution flow to prevent duplicates)
# -------------------------
try {
    if (-not (Test-Prerequisites -LogFile $logFile)) {
        Write-Log -Message "Prerequisites check failed - cannot proceed with Ollama configuration" -Level ERROR -LogFile $logFile
        throw "Prerequisites failed"
    }

    $setupResults = @()

    # Install Phase
    if ($Install -or $Run) {
        Write-Log -Message "Installing Ollama components..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Ollama Application"; Success = (Install-OllamaApplication -LogFile $logFile) }
        $setupResults += @{Name = "Ollama Models"; Success = (Install-OllamaModels -LogFile $logFile) }
        
        # CUDA installation for NVIDIA GPUs only
        if ($hardware.GPU.Type -eq "NVIDIA") {
            $cudaStatus = Test-CUDAInstallation -LogFile $logFile
            if (-not $cudaStatus.Installed) {
                $cudaInstall = Install-CUDAToolkit -LogFile $logFile
                $setupResults += @{Name = "CUDA Toolkit"; Success = $cudaInstall }
            }
            else { 
                $setupResults += @{Name = "CUDA Toolkit"; Success = $true } 
            }
        }
    }

    # Configure Phase
    if ($Configure -or $Run) {
        Write-Log -Message "Configuring Ollama for hardware optimization..." -Level INFO -LogFile $logFile
        $cudaStatus = if ($hardware.GPU.Type -eq "NVIDIA") { Test-CUDAInstallation -LogFile $logFile } else { @{Installed = $false} }
        $config = Set-OllamaConfiguration -Hardware $hardware -CudaStatus $cudaStatus -LogFile $logFile
        $setupResults += @{Name = "Ollama Configuration"; Success = (Test-OllamaConfiguration -LogFile $logFile) }
        
        Write-Log -Message "Restarting Ollama service to apply optimization settings..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Ollama Service"; Success = (Start-OllamaService -LogFile $logFile -ForceRestart) }
    }

    # Test Phase
    if ($Test -or $Run) {
        Write-Log -Message "Testing Ollama functionality and performance..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Ollama Functionality"; Success = (Test-OllamaFunctionality -LogFile $logFile) }
        
        # Performance benchmark
        $benchmarkResult = Test-OllamaPerformance -Hardware $hardware -LogFile $logFile
        $setupResults += @{Name = "Performance Benchmark"; Success = ($null -ne $benchmarkResult) }
        $setupResults += @{Name = "Ollama Setup Validation"; Success = (Test-OllamaSetup -Hardware $hardware -LogFile $logFile) }
    }

    # Optimization Phase
    if ($Run -or $Configure) {
        Write-Log -Message "Applying personality and model optimization..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Personality Import"; Success = (Import-PersonalityTraits -LogFile $logFile) }
        $setupResults += @{Name = "Model Optimization"; Success = (Optimize-OllamaModels -Hardware $hardware -LogFile $logFile) }
    }

    # Final validation
    Write-Log -Message "Running comprehensive validation..." -Level INFO -LogFile $logFile
    $validationResults = New-OllamaValidationSummary -LogFile $logFile

    # === FINAL RESULTS ===
    Write-Log -Message "=== FINAL RESULTS ===" -Level INFO -LogFile $logFile
    $successCount = ($setupResults | Where-Object { $_.Success }).Count
    $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
    Write-Log -Message "SUCCESS: $successCount components" -Level SUCCESS -LogFile $logFile
    if ($failCount -gt 0) { 
        Write-Log -Message "FAILED: $failCount components" -Level ERROR -LogFile $logFile 
    }
    
    foreach ($result in $setupResults) {
        $status = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }
        $level = if ($result.Success) { "SUCCESS" } else { "ERROR" }
        Write-Log -Message "$($result.Name): $status" -Level $level -LogFile $logFile
    }

    $validationSuccess = ($validationResults | Where-Object { $_ -like "✅*" }).Count -eq ($validationResults | Where-Object { $_ -like "✅*" -or $_ -like "❌*" }).Count
    if (-not $validationSuccess) { 
        Write-Log -Message "Ollama configuration completed with issues - review logs for remediation steps" -Level WARN -LogFile $logFile 
    } else { 
        Write-Log -Message "Ollama configuration completed successfully - all components validated" -Level SUCCESS -LogFile $logFile 
    }

    Write-Log -Message "=== HARDWARE OPTIMIZATION ===" -Level INFO -LogFile $logFile
    Write-Log -Message "Platform: $($hardware.Platform)" -Level INFO -LogFile $logFile
    Write-Log -Message "Optimal Configuration: $($hardware.OptimalConfig)" -Level INFO -LogFile $logFile

    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    if ($validationSuccess) {
        Write-Log -Message "1. Continue with frontend setup: .\05-ReactFrontend.ps1" -Level INFO -LogFile $logFile
        Write-Log -Message "2. For voice integration: .\06-VoiceBackend.ps1" -Level INFO -LogFile $logFile
        Write-Log -Message "3. Test the system: .\run_backend.ps1 then .\run_frontend.ps1" -Level INFO -LogFile $logFile
    }
    else {
        Write-Log -Message "1. Review error logs above for specific issues." -Level INFO -LogFile $logFile
        Write-Log -Message "2. For GPU memory issues, try reducing OLLAMA_GPU_MEMORY_FRACTION" -Level INFO -LogFile $logFile
        Write-Log -Message "3. Re-run this script after resolving issues." -Level INFO -LogFile $logFile
    }

    if ($failCount -gt 0) {
        throw "Ollama configuration completed with $failCount failed components"
    }
}
catch {
    Write-Log -Message "Critical error during Ollama configuration: $($_.Exception.Message)" -Level ERROR -LogFile $logFile
    Write-Log -Message "Check PowerShell execution policy and administrator privileges." -Level ERROR -LogFile $logFile
    throw
}
finally {
    Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
    Stop-Transcript
}
