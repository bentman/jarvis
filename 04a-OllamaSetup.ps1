# 04a-OllamaSetup.ps1 - Ollama Installation and Model Setup with Enhanced Validation
# Purpose: Ensure Ollama runtime, required models, service config with comprehensive validation and hardware optimization
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

# Set default mode
if (-not ($Install -or $Configure -or $Test)) { $Run = $true }

Write-SystemInfo -ScriptName $scriptPrefix -Version $scriptVersion -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Install   = $Install
    Configure = $Configure
    Test      = $Test
    Run       = $Run
}

$hardware = Get-AvailableHardware -LogFile $logFile

function Test-Prerequisites {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing prerequisites for Ollama setup..." -Level INFO -LogFile $LogFile
    # Check if winget is available for installation
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
            # Test if Ollama is functional
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
            # Refresh PATH environment variable
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 3
            # Verify installation
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
            # Verify model installation
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
        # Test environment configuration
        $envValid = Test-EnvironmentConfig -LogFile $LogFile
        if (-not $envValid) {
            Write-Log -Message "Environment configuration needs update" -Level WARN -LogFile $LogFile
            return $false
        }
        # Test model configuration
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
        # Simple test prompt
        $testPrompt = "Hello"
        $body = @{
            model  = $targetModel
            prompt = $testPrompt
            stream = $false
        } | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30
        Write-Log -Message "Raw response type: $($response.GetType().Name)" -Level INFO -LogFile $LogFile
        Write-Log -Message "Response has 'response' field: $($response.response -ne $null)" -Level INFO -LogFile $LogFile
        if ($response -and $response.response -and $response.response.Length -gt 0) {
            Write-Log -Message "Ollama functionality test passed - generated response" -Level SUCCESS -LogFile $LogFile
            Write-Log -Message "Test response: $($response.response.Substring(0, [Math]::Min(50, $response.response.Length)))..." -Level INFO -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Ollama functionality test failed - no response generated" -Level ERROR -LogFile $LogFile
            Write-Log -Message "Response object: $($response | ConvertTo-Json -Compress)" -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Ollama functionality test failed: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Write-Log -Message "Check winget functionality or try manual installation." -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-OllamaValidationSummary {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    $validationResults = @()
    # Check installation
    if (Test-OllamaInstallation -LogFile $LogFile) { 
        $validationResults += "✅ Ollama Application: Installed and functional" 
    }
    else { $validationResults += "❌ Ollama Application: Not installed or not functional" }
    # Check service
    if (Test-OllamaService -LogFile $LogFile) { 
        $validationResults += "✅ Ollama Service: Running and accessible" 
    }
    else { $validationResults += "❌ Ollama Service: Not running or not accessible" }
    # Check models
    if (Test-OllamaModels -LogFile $LogFile) {
        $targetModel = Get-JarvisModel -LogFile $LogFile
        $validationResults += "✅ Model Available: $targetModel"
    }
    else { $validationResults += "❌ Model Missing: Required model not available" }
    # Check configuration
    if (Test-OllamaConfiguration -LogFile $LogFile) {
        $validationResults += "✅ Configuration: Environment and model config valid"
    }
    else { $validationResults += "❌ Configuration: Issues detected" }
    # Check functionality
    if (Test-OllamaFunctionality -LogFile $LogFile) {
        $validationResults += "✅ Functionality: Basic inference working"
    }
    else { $validationResults += "❌ Functionality: Inference test failed" }
    # Hardware optimization status
    $hwConfig = Get-OptimalConfiguration -Hardware $hardware
    $validationResults += "INFO Hardware: $($hardware.OptimalConfig) optimization active"
    return $validationResults
}

# Main execution
try {
    if (-not (Test-Prerequisites -LogFile $logFile)) {
        Write-Log -Message "Prerequisites check failed - cannot proceed with Ollama setup" -Level ERROR -LogFile $logFile
        Stop-Transcript
        exit 1
    }
    $setupResults = @()
    if ($Install -or $Run) {
        Write-Log -Message "Installing Ollama components..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Ollama Application"; Success = (Install-OllamaApplication -LogFile $logFile) }
        $setupResults += @{Name = "Ollama Models"; Success = (Install-OllamaModels -LogFile $logFile) }
    }
    if ($Configure -or $Run) {
        Write-Log -Message "Configuring Ollama..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Ollama Configuration"; Success = (Test-OllamaConfiguration -LogFile $logFile) }
        # Ensure environment configuration is updated
        Test-EnvironmentConfig -LogFile $logFile | Out-Null
        # Restart Ollama service to apply hardware optimization environment variables
        Write-Log -Message "Restarting Ollama service to apply hardware optimization settings..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Ollama Service"; Success = (Start-OllamaService -LogFile $logFile -ForceRestart) }
    }
    if ($Test -or $Run) {
        Write-Log -Message "Testing Ollama functionality..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Ollama Functionality"; Success = (Test-OllamaFunctionality -LogFile $logFile) }
    }
    # Always run validation summary
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
        Write-Log -Message "Ollama setup completed with issues - review logs for remediation steps" -Level WARN -LogFile $logFile 
    }
    else { 
        Write-Log -Message "Ollama setup completed successfully - all components validated" -Level SUCCESS -LogFile $LogFile 
    }
    # Hardware optimization summary
    Write-Log -Message "=== HARDWARE OPTIMIZATION ===" -Level INFO -LogFile $logFile
    Write-Log -Message "Platform: $($hardware.Platform)" -Level INFO -LogFile $logFile
    Write-Log -Message "Optimal Configuration: $($hardware.OptimalConfig)" -Level INFO -LogFile $logFile
    # Next steps
    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    if ($validationSuccess) {
        Write-Log -Message "1. For detailed hardware diagnostics: .\04b-OllamaDiag.ps1" -Level INFO -LogFile $logFile
        Write-Log -Message "2. For advanced hardware optimization: .\04c-OllamaTuning.ps1" -Level INFO -LogFile $logFile
    }
    else {
        Write-Log -Message "1. Review error logs above for specific issues." -Level INFO -LogFile $logFile
        Write-Log -Message "2. Try manual Ollama installation if automated installation failed." -Level INFO -LogFile $logFile
        Write-Log -Message "3. Re-run this script with -Install -Test flags after resolving issues." -Level INFO -LogFile $logFile
    }
}
catch {
    Write-Log -Message "Critical error during Ollama setup: $($_.Exception.Message)" -Level ERROR -LogFile $logFile
    Write-Log -Message "Check PowerShell execution policy and administrator privileges." -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript