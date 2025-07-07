# 04a-OllamaSetup.ps1 (v4.1) - Installs Ollama, sets up phi3:mini model, and validates setup
# JARVIS AI Assistant - Robust Ollama installation and model setup for Windows
# Optimized using shared utilities from 00-CommonUtils.ps1

param(
    [switch]$Setup,
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
$transcriptFile = Join-Path $logsDir "04a-ollama-setup-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "04a-ollama-setup-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile

# Test if Ollama is installed
function Test-OllamaInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    $installed = Test-Command -Command "ollama" -LogFile $LogFile
    if ($installed) {
        $version = & ollama --version 2>&1
        Write-Log -Message "Ollama installed: $version" -Level "SUCCESS" -LogFile $LogFile
    }
    else {
        Write-Log -Message "Ollama not installed" -Level "ERROR" -LogFile $LogFile
    }
    return $installed
}

# Get Ollama executable path
function Get-OllamaPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    try {
        $command = Get-Command "ollama" -ErrorAction Stop
        Write-Log -Message "Ollama executable found: $($command.Source)" -Level "INFO" -LogFile $LogFile
        return $command.Source
    }
    catch {
        Write-Log -Message "Ollama executable not found: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $null
    }
}

# Test if Ollama service is running
function Test-OllamaRunning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
        Write-Log -Message "Ollama service running" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Ollama service not running: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Install Ollama via winget
function Install-Ollama {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Installing Ollama via winget..." -Level "INFO" -LogFile $LogFile
    try {
        $installResult = winget install --id "Ollama.Ollama" --silent --accept-package-agreements --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Ollama installed successfully" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Winget installation failed: $installResult" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Ollama installation failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Start Ollama service
function Start-OllamaService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Starting Ollama service..." -Level "INFO" -LogFile $LogFile
    $ollamaPath = Get-OllamaPath -LogFile $LogFile
    if (-not $ollamaPath) {
        return $false
    }
    
    try {
        $process = Start-Process -FilePath $ollamaPath -ArgumentList "serve" -WindowStyle Hidden -PassThru -ErrorAction Stop
        $attempts = 0
        $maxAttempts = 15
        while (-not (Test-OllamaRunning -LogFile $LogFile) -and $attempts -lt $maxAttempts) {
            Start-Sleep -Seconds 2
            $attempts++
            Write-Host "." -NoNewline -ForegroundColor Gray
            if ($attempts % 5 -eq 0) {
                Write-Log -Message "Waiting for Ollama ($attempts/$maxAttempts)" -Level "INFO" -LogFile $LogFile
            }
        }
        Write-Host ""
        if (Test-OllamaRunning -LogFile $LogFile) {
            Write-Log -Message "Ollama service started (PID: $($process.Id))" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Ollama failed to start after $maxAttempts attempts" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Failed to start Ollama: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Install phi3:mini model
function Install-Phi3Mini {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Installing phi3:mini model..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-OllamaRunning -LogFile $LogFile)) {
        Write-Log -Message "Ollama not running - cannot install model" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 10 -ErrorAction Stop
        if ($response.models.name -contains "phi3:mini") {
            Write-Log -Message "phi3:mini already installed" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        $output = & ollama pull phi3:mini 2>&1
        if ($LASTEXITCODE -eq 0) {
            $attempts = 0
            $maxAttempts = 5
            while ($attempts -lt $maxAttempts) {
                Start-Sleep -Seconds 2
                $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
                if ($response.models.name -contains "phi3:mini") {
                    Write-Log -Message "phi3:mini installed successfully" -Level "SUCCESS" -LogFile $LogFile
                    return $true
                }
                $attempts++
            }
            Write-Log -Message "phi3:mini installed but not registered" -Level "ERROR" -LogFile $LogFile
            return $false
        }
        Write-Log -Message "phi3:mini installation failed: $output" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Failed to install phi3:mini: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Test phi3:mini model
function Test-Phi3Mini {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Testing phi3:mini model..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-OllamaRunning -LogFile $LogFile)) {
        Write-Log -Message "Ollama not running - cannot test model" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    try {
        $output = "Hello" | & ollama run phi3:mini 2>&1
        if ($LASTEXITCODE -eq 0 -and $output) {
            Write-Log -Message "phi3:mini test passed: $output" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "phi3:mini test failed: $output" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "phi3:mini test failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Validate Ollama setup
function Test-OllamaSetup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Validating Ollama setup..." -Level "INFO" -LogFile $LogFile
    $results = @()
    
    $installed = Test-OllamaInstalled -LogFile $LogFile
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
    
    $testResult = Test-Phi3Mini -LogFile $LogFile
    $results += $testResult ? "✅ phi3:mini test passed" : "❌ phi3:mini test failed"
    
    Write-Log -Message "=== VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $results) {
        Write-Log -Message $result -Level ($result -like "✅*" ? "SUCCESS" : "ERROR") -LogFile $LogFile
    }
    
    $successCount = ($results | Where-Object { $_ -like "✅*" }).Count
    Write-Log -Message "Validation: $successCount/$($results.Count) checks passed" -Level ($successCount -eq $results.Count ? "SUCCESS" : "ERROR") -LogFile $LogFile
    return $successCount -eq $results.Count
}

# Main execution
Write-Log -Message "JARVIS Ollama Setup (v4.1) Starting..." -Level "SUCCESS" -LogFile $logFile
Write-SystemInfo -ScriptName "04a-OllamaSetup.ps1" -Version "4.1" -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Setup = $Setup
    Test  = $Test
    All   = $All
}

if (-not ($Setup -or $Test)) {
    $All = $true
}

$results = @()
if ($Setup -or $All) {
    Write-Log -Message "=== SETUP ===" -Level "INFO" -LogFile $logFile
    if (-not (Test-OllamaInstalled -LogFile $logFile)) {
        $results += @{Name = "Ollama Installation"; Success = (Install-Ollama -LogFile $logFile) }
    }
    else {
        $results += @{Name = "Ollama Installation"; Success = $true }
    }
    $results += @{Name = "Ollama Service"; Success = (Start-OllamaService -LogFile $logFile) }
    $results += @{Name = "phi3:mini Installation"; Success = (Install-Phi3Mini -LogFile $logFile) }
}

if ($Test -or $All) {
    Write-Log -Message "=== VALIDATION ===" -Level "INFO" -LogFile $logFile
    $results += @{Name = "System Validation"; Success = (Test-OllamaSetup -LogFile $logFile) }
}

Write-Log -Message "=== SUMMARY ===" -Level "INFO" -LogFile $logFile
$successCount = ($results | Where-Object { $_.Success }).Count
foreach ($result in $results) {
    Write-Log -Message "$($result.Name): $($result.Success ? 'SUCCESS' : 'FAILED')" -Level ($result.Success ? "SUCCESS" : "ERROR") -LogFile $logFile
}
Write-Log -Message "Ollama setup: $successCount/$($results.Count) tasks completed successfully" -Level ($successCount -eq $results.Count ? "SUCCESS" : "ERROR") -LogFile $logFile

if ($successCount -ne $results.Count) {
    Write-Log -Message "Review logs: $logFile" -Level "INFO" -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "Log Files: $transcriptFile, $logFile" -Level "INFO" -LogFile $logFile
Write-Log -Message "JARVIS Ollama Setup (v4.1) Complete!" -Level "SUCCESS" -LogFile $logFile

Stop-Transcript