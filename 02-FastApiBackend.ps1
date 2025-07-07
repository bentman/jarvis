# 02-FastApiBackend.ps1 (v4.1) - Enhanced FastAPI Backend Setup
# JARVIS AI Assistant - Backend API development environment
# Optimized using shared utilities from 00-CommonUtils.ps1

param(
    [switch]$Install,
    [switch]$Run,
    [switch]$Test,
    [switch]$Configure,
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
$transcriptFile = Join-Path $logsDir "02-fastapi-backend-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "02-fastapi-backend-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile

# Create backend directory structure
function New-BackendStructure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    $directories = @(
        "backend",
        "backend/api",
        "backend/tests",
        "backend/services"
    )
    
    return New-DirectoryStructure -Directories $directories -LogFile $LogFile
}

# Create requirements.txt
function New-RequirementsFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating backend requirements.txt..." -Level "INFO" -LogFile $LogFile
    $requirementsPath = "backend/requirements.txt"
    
    if (Test-Path $requirementsPath) {
        $existing = Get-Content $requirementsPath -Raw
        if ($existing -match "fastapi>=0.104.1" -and $existing -match "uvicorn") {
            Write-Log -Message "Requirements.txt already exists and is current" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Updating existing requirements.txt" -Level "WARN" -LogFile $LogFile
    }
    
    $requirements = @"
# JARVIS AI Assistant Backend Requirements
fastapi>=0.104.1
uvicorn[standard]>=0.24.0
python-dotenv>=1.0.0
pydantic>=2.9.0
pydantic-settings>=2.1.0
httpx>=0.27.0
pytest>=7.4.3
ollama>=0.4.5
"@
    
    try {
        Set-Content -Path $requirementsPath -Value $requirements -ErrorAction Stop
        Write-Log -Message "Requirements.txt created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create requirements.txt: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Create main FastAPI application
function New-FastApiApplication {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating main FastAPI application..." -Level "INFO" -LogFile $LogFile
    $mainPath = "backend/api/main.py"
    
    if (Test-Path $mainPath) {
        $existing = Get-Content $mainPath -Raw
        if ($existing -match "Jarvis AI Assistant" -and $existing -match "FastAPI") {
            Write-Log -Message "Main application already exists and is current" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Updating main application" -Level "WARN" -LogFile $LogFile
    }
    
    $mainApp = @"
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
import os
from dotenv import load_dotenv

load_dotenv()
app = FastAPI(
    title="Jarvis AI Assistant",
    description="AI Assistant Backend API",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatMessage(BaseModel):
    content: str

class ChatResponse(BaseModel):
    response: str
    timestamp: str

@app.get("/")
async def root():
    return {
        "message": "Jarvis AI Assistant Backend",
        "status": "running",
        "version": "1.0.0",
        "docs": "/docs"
    }

@app.get("/api/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "jarvis-backend",
        "version": "1.0.0",
        "timestamp": datetime.now().isoformat()
    }

@app.post("/api/chat", response_model=ChatResponse)
async def chat(message: ChatMessage):
    response = f"Echo: {message.content}"
    return ChatResponse(
        response=response,
        timestamp=datetime.now().isoformat()
    )

@app.get("/api/status")
async def get_status():
    return {
        "backend": "running",
        "mode": "echo (test mode)",
        "features": {
            "chat": True,
            "health_check": True,
            "echo_mode": True
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
"@
    
    try {
        Set-Content -Path $mainPath -Value $mainApp -ErrorAction Stop
        Set-Content -Path "backend/api/__init__.py" -Value "" -ErrorAction Stop
        Write-Log -Message "Main FastAPI application created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create main application: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Create environment configuration
function New-EnvironmentConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Validating environment configuration..." -Level "INFO" -LogFile $LogFile
    $success = Test-EnvironmentConfig -LogFile $LogFile
    if ($success) {
        $ollamaModel = Get-OllamaModel -LogFile $LogFile
        Write-Log -Message "Using Ollama model: $ollamaModel" -Level "INFO" -LogFile $LogFile
    }
    return $success
}

# Create basic tests
function New-BasicTests {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating basic test suite..." -Level "INFO" -LogFile $LogFile
    $testPath = "backend/tests/test_main.py"
    
    if (Test-Path $testPath) {
        Write-Log -Message "Test suite already exists" -Level "INFO" -LogFile $LogFile
        return $true
    }
    
    $testMain = @"
import pytest
from fastapi.testclient import TestClient
from api.main import app

client = TestClient(app)

def test_root():
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "running"
    assert "Jarvis" in data["message"]

def test_health_check():
    """Test health check endpoint"""
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data

def test_chat_endpoint():
    """Test chat endpoint (echo mode)"""
    response = client.post("/api/chat", json={"content": "Hello"})
    assert response.status_code == 200
    data = response.json()
    assert "Echo: Hello" in data["response"]
    assert "timestamp" in data

def test_status_endpoint():
    """Test status endpoint"""
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert data["backend"] == "running"
    assert data["features"]["chat"] == True
"@
    
    try {
        Set-Content -Path $testPath -Value $testMain -ErrorAction Stop
        Set-Content -Path "backend/tests/__init__.py" -Value "" -ErrorAction Stop
        Write-Log -Message "Basic test suite created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create test suite: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Create run script
function New-RunScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Creating backend run script..." -Level "INFO" -LogFile $LogFile
    $runScriptPath = "run_backend.ps1"
    
    if (Test-Path $runScriptPath) {
        $existing = Get-Content $runScriptPath -Raw
        if ($existing -match "FastAPI" -and $existing -match "uvicorn") {
            Write-Log -Message "Run script already exists and is current" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
    }
    
    $runScript = @"
# run_backend.ps1 - Start the Jarvis AI Backend (v4.1)
param(
    [switch]`$Test,
    [switch]`$Health,
    [switch]`$QuickTest
)

. .\00-CommonUtils.ps1
`$logFile = Join-Path (Get-Location) "logs/run_backend_log_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

if (`$Health) {
    Write-Log -Message "Checking backend health..." -Level "INFO" -LogFile `$logFile
    try {
        `$response = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 5
        Write-Log -Message "Backend is healthy!" -Level "SUCCESS" -LogFile `$logFile
        Write-Host "Response: `$(`$response | ConvertTo-Json -Compress)" -ForegroundColor Green
        return
    }
    catch {
        Write-Log -Message "Backend not responding on port 8000: `$($_.Exception.Message)" -Level "ERROR" -LogFile `$logFile
        Write-Host "Start the backend first with: .\run_backend.ps1" -ForegroundColor Yellow
        return
    }
}

if (`$QuickTest) {
    Write-Log -Message "Running quick API tests..." -Level "INFO" -LogFile `$logFile
    try {
        `$health = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 5
        Write-Log -Message "Health check: PASSED" -Level "SUCCESS" -LogFile `$logFile
    }
    catch {
        Write-Log -Message "Health check: FAILED - Backend not running: `$($_.Exception.Message)" -Level "ERROR" -LogFile `$logFile
        return
    }
    
    try {
        `$body = @{content = "Hello Jarvis!"} | ConvertTo-Json
        `$chat = Invoke-RestMethod -Uri "http://localhost:8000/api/chat" -Method Post -Body `$body -ContentType "application/json" -TimeoutSec 5
        Write-Log -Message "Chat test: PASSED" -Level "SUCCESS" -LogFile `$logFile
        Write-Host "Response: `$(`$chat.response)" -ForegroundColor Green
    }
    catch {
        Write-Log -Message "Chat test: FAILED - `$($_.Exception.Message)" -Level "ERROR" -LogFile `$logFile
    }
    
    try {
        `$status = Invoke-RestMethod -Uri "http://localhost:8000/api/status" -TimeoutSec 5
        Write-Log -Message "Status check: PASSED" -Level "SUCCESS" -LogFile `$logFile
        Write-Host "Mode: `$(`$status.mode)" -ForegroundColor Green
    }
    catch {
        Write-Log -Message "Status check: FAILED - `$($_.Exception.Message)" -Level "ERROR" -LogFile `$logFile
    }
    return
}

if (`$Test) {
    Write-Log -Message "Running backend test suite..." -Level "INFO" -LogFile `$logFile
    if (-not (Test-Path "backend/tests/test_main.py")) {
        Write-Log -Message "Test files not found in backend/tests/" -Level "ERROR" -LogFile `$logFile
        return
    }
    
    Push-Location backend
    try {
        `$pythonCmd = Get-PythonCommand -LogFile `$logFile
        if (-not `$pythonCmd) {
            Write-Log -Message "No Python command found" -Level "ERROR" -LogFile `$logFile
            return
        }
        
        Write-Log -Message "Executing pytest with: `$pythonCmd" -Level "INFO" -LogFile `$logFile
        & `$pythonCmd -m pytest tests/ -v --tb=short
        if (`$LASTEXITCODE -eq 0) {
            Write-Log -Message "All tests passed!" -Level "SUCCESS" -LogFile `$logFile
        }
        else {
            Write-Log -Message "Some tests failed (exit code: `$LASTEXITCODE)" -Level "WARN" -LogFile `$logFile
        }
    }
    finally {
        Pop-Location
    }
    return
}

Write-Log -Message "Starting Jarvis AI Backend Server..." -Level "SUCCESS" -LogFile `$logFile
Write-Host "📍 Available Endpoints:" -ForegroundColor Cyan
Write-Host "  • API Documentation: http://localhost:8000/docs" -ForegroundColor White
Write-Host "  • Health Check: http://localhost:8000/api/health" -ForegroundColor White
Write-Host "  • Chat Endpoint: http://localhost:8000/api/chat" -ForegroundColor White
Write-Host "  • Status: http://localhost:8000/api/status" -ForegroundColor White
Write-Host "🧪 Quick Test Commands:" -ForegroundColor Yellow
Write-Host "  .\run_backend.ps1 -Health      # Check if running" -ForegroundColor Gray
Write-Host "  .\run_backend.ps1 -QuickTest   # Test all endpoints" -ForegroundColor Gray
Write-Host "  .\run_backend.ps1 -Test        # Run pytest suite" -ForegroundColor Gray
Write-Host "🛑 Press Ctrl+C to stop the server" -ForegroundColor Red

if (-not (Test-Path "backend/api/main.py")) {
    Write-Log -Message "Backend application not found!" -Level "ERROR" -LogFile `$logFile
    Write-Host "Run: .\02-FastApiBackend.ps1 first" -ForegroundColor Yellow
    return
}

Push-Location backend
try {
    `$pythonCmd = Get-PythonCommand -LogFile `$logFile
    if (-not `$pythonCmd) {
        Write-Log -Message "No Python command found" -Level "ERROR" -LogFile `$logFile
        return
    }
    
    Write-Log -Message "Starting uvicorn with: `$pythonCmd" -Level "INFO" -LogFile `$logFile
    Write-Host "Server starting in 3 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    & `$pythonCmd -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
}
finally {
    Pop-Location
}
"@
    
    try {
        Set-Content -Path $runScriptPath -Value $runScript -ErrorAction Stop
        Write-Log -Message "Backend run script created successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create run script: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Install backend dependencies
function Install-BackendDependencies {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Installing backend Python dependencies..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-Path "backend/requirements.txt")) {
        Write-Log -Message "Requirements file not found - creating structure first" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    try {
        Push-Location backend
        $packages = @("fastapi>=0.104.1", "uvicorn[standard]>=0.24.0", "python-dotenv>=1.0.0", 
            "pydantic>=2.9.0", "pydantic-settings>=2.1.0", "httpx>=0.27.0", 
            "pytest>=7.4.3", "ollama>=0.4.5")
        
        $successCount = 0
        foreach ($package in $packages) {
            if (Install-PythonPackage -PackageName $package -LogFile $LogFile) {
                $successCount++
            }
        }
        
        if ($successCount -eq $packages.Count) {
            Write-Log -Message "All backend dependencies installed successfully ($successCount/$($packages.Count))" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Some backend dependencies failed to install ($successCount/$($packages.Count))" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Exception during dependency installation: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    finally {
        Pop-Location
    }
}

# Run tests
function Invoke-BackendTests {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Running backend test suite..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-Path "backend/tests/test_main.py")) {
        Write-Log -Message "Test files not found" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    
    try {
        Push-Location backend
        $pythonCmd = Get-PythonCommand -LogFile $LogFile
        if (-not $pythonCmd) {
            Write-Log -Message "No Python command found for running tests" -Level "ERROR" -LogFile $LogFile
            return $false
        }
        
        Write-Log -Message "Executing test suite..." -Level "INFO" -LogFile $LogFile
        & $pythonCmd -m pytest tests/ -v
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "All tests passed successfully" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "Some tests failed (exit code: $LASTEXITCODE)" -Level "WARN" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Exception during test execution: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    finally {
        Pop-Location
    }
}

# Validate backend setup
# Patch for 02-FastApiBackend.ps1 to fix Test-BackendSetup (line 654 issue)
# Updated to allow periods in LogFile path

# Fixed Test-BackendSetup function for 02-FastApiBackend.ps1
# The issue was the regex pattern that was too restrictive for Windows file paths

function Test-BackendSetup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    # Removed the overly restrictive path validation that was causing issues
    # Windows paths can contain periods, colons, backslashes, etc.
    
    Write-Log -Message "Validating backend setup..." -Level "INFO" -LogFile $LogFile
    $validationResults = @()
    
    $requiredDirs = @("backend", "backend/api", "backend/tests", "backend/services")
    foreach ($dir in $requiredDirs) {
        $validationResults += "$(Test-Path $dir ? '✅' : '❌') Directory: $dir"
    }
    
    $requiredFiles = @(
        "backend/requirements.txt",
        "backend/api/main.py",
        "backend/api/__init__.py",
        "backend/tests/test_main.py",
        "backend/tests/__init__.py",
        ".env",
        "run_backend.ps1"
    )
    
    foreach ($file in $requiredFiles) {
        if (Test-Path $file) {
            $size = (Get-Item $file).Length
            $validationResults += "✅ File: $file ($size bytes)"
        }
        else {
            $validationResults += "❌ Missing: $file"
        }
    }
    
    $pythonPackages = @("fastapi", "uvicorn", "pydantic", "ollama")
    foreach ($package in $pythonPackages) {
        $status = Test-PythonPackageInstalled -PackageName $package -LogFile $LogFile
        $validationResults += "$($status ? '✅' : '❌') Python Package: $package"
    }
    
    Write-Log -Message "=== BACKEND VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $validationResults) {
        Write-Log -Message $result -Level ($result -like "✅*" ? "SUCCESS" : "ERROR") -LogFile $LogFile
    }
    
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    Write-Log -Message "Backend Validation: $successCount/$($validationResults.Count) passed, $failureCount failed" -Level ($failureCount -eq 0 ? "SUCCESS" : "ERROR") -LogFile $LogFile
    
    return $failureCount -eq 0
}

# Start backend server
function Test-BackendSetup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    Write-Log -Message "Validating backend setup..." -Level "INFO" -LogFile $LogFile
    $validationResults = @()
    
    $requiredDirs = @("backend", "backend/api", "backend/tests", "backend/services")
    foreach ($dir in $requiredDirs) {
        if (Test-Path $dir) {
            $validationResults += "✅ Directory: $dir"
        }
        else {
            $validationResults += "❌ Directory: $dir"
        }
    }
    
    $requiredFiles = @(
        "backend/requirements.txt",
        "backend/api/main.py",
        "backend/api/__init__.py",
        "backend/tests/test_main.py",
        "backend/tests/__init__.py",
        ".env",
        "run_backend.ps1"
    )
    
    foreach ($file in $requiredFiles) {
        if (Test-Path $file) {
            $size = (Get-Item $file).Length
            $validationResults += "✅ File: $file ($size bytes)"
        }
        else {
            $validationResults += "❌ Missing: $file"
        }
    }
    
    $pythonPackages = @("fastapi", "uvicorn", "pydantic", "ollama")
    foreach ($package in $pythonPackages) {
        $status = Test-PythonPackageInstalled -PackageName $package -LogFile $LogFile
        if ($status) {
            $validationResults += "✅ Python Package: $package"
        }
        else {
            $validationResults += "❌ Python Package: $package"
        }
    }
    
    Write-Log -Message "=== BACKEND VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $validationResults) {
        $level = if ($result -like "✅*") { "SUCCESS" } else { "ERROR" }
        Write-Log -Message $result -Level $level -LogFile $LogFile
    }
    
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    $level = if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }
    Write-Log -Message "Backend Validation: $successCount/$($validationResults.Count) passed, $failureCount failed" -Level $level -LogFile $LogFile
    
    return $failureCount -eq 0
}

# Main execution
Write-Log -Message "JARVIS FastAPI Backend Setup (v4.1) Starting..." -Level "SUCCESS" -LogFile $logFile
Write-SystemInfo -ScriptName "02-FastApiBackend.ps1" -Version "4.1" -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Install   = $Install
    Run       = $Run
    Test      = $Test
    Configure = $Configure
    All       = $All
}

$setupResults = @()
Write-Log -Message "Creating backend structure and files..." -Level "INFO" -LogFile $logFile
$setupResults += @{Name = "Backend Structure"; Success = (New-BackendStructure -LogFile $logFile) }
$setupResults += @{Name = "Requirements File"; Success = (New-RequirementsFile -LogFile $logFile) }
$setupResults += @{Name = "FastAPI Application"; Success = (New-FastApiApplication -LogFile $logFile) }
$setupResults += @{Name = "Environment Config"; Success = (New-EnvironmentConfig -LogFile $logFile) }
$setupResults += @{Name = "Test Suite"; Success = (New-BasicTests -LogFile $logFile) }
$setupResults += @{Name = "Run Script"; Success = (New-RunScript -LogFile $logFile) }

if ($Install -or $All) {
    Write-Log -Message "Installing dependencies..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "Dependencies"; Success = (Install-BackendDependencies -LogFile $logFile) }
}
elseif (-not (Test-PythonPackageInstalled -PackageName "fastapi" -LogFile $logFile) -or 
    -not (Test-PythonPackageInstalled -PackageName "uvicorn" -LogFile $logFile) -or 
    -not (Test-PythonPackageInstalled -PackageName "ollama" -LogFile $logFile)) {
    Write-Log -Message "Core FastAPI dependencies missing - installing automatically..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "Core Dependencies (Auto)"; Success = (Install-BackendDependencies -LogFile $logFile) }
}

if ($Configure -or $All) {
    Write-Log -Message "Updating environment configuration..." -Level "INFO" -LogFile $logFile
    $setupResults += @{Name = "Environment Update"; Success = (New-EnvironmentConfig -LogFile $logFile) }
}

if ($Test -or $All) {
    Write-Log -Message "Running tests..." -Level "INFO" -LogFile $logFile
    if (Test-PythonPackageInstalled -PackageName "fastapi" -LogFile $logFile) {
        $setupResults += @{Name = "Test Execution"; Success = (Invoke-BackendTests -LogFile $logFile) }
    }
    else {
        Write-Log -Message "Skipping tests - dependencies not installed (use -Install flag)" -Level "WARN" -LogFile $logFile
    }
}

Write-Log -Message "=== SETUP SUMMARY ===" -Level "INFO" -LogFile $logFile
$successfulSetups = ($setupResults | Where-Object { $_.Success }).Count
$failedSetups = ($setupResults | Where-Object { -not $_.Success }).Count
foreach ($result in $setupResults) {
    Write-Log -Message "$($result.Name) - $($result.Success ? 'SUCCESS' : 'FAILED')" -Level ($result.Success ? "SUCCESS" : "ERROR") -LogFile $logFile
}
Write-Log -Message "Setup Results: $successfulSetups successful, $failedSetups failed" -Level "INFO" -LogFile $logFile

Test-BackendSetup -LogFile $logFile | Out-Null

if ($Run -or $All) {
    if (Test-PythonPackageInstalled -PackageName "fastapi" -LogFile $logFile) {
        $confirm = Read-Host "Ready to start the FastAPI server? (Y/n)"
        if ($confirm -eq "" -or $confirm -eq "y" -or $confirm -eq "Y") {
            Start-BackendServer -LogFile $logFile
        }
        else {
            Write-Log -Message "Server start cancelled. Run manually with: .\run_backend.ps1" -Level "INFO" -LogFile $logFile
        }
    }
    else {
        Write-Log -Message "Cannot start server - dependencies not installed (use -Install flag)" -Level "WARN" -LogFile $logFile
    }
}

if (-not ($Install -or $Run -or $Test -or $Configure -or $All)) {
    Write-Log -Message "=== NEXT STEPS ===" -Level "INFO" -LogFile $logFile
    Write-Log -Message "1. .\02-FastApiBackend.ps1 -Configure   # Update environment" -Level "INFO" -LogFile $logFile
    Write-Log -Message "2. .\02-FastApiBackend.ps1 -Test       # Run test suite" -Level "INFO" -LogFile $logFile
    Write-Log -Message "3. .\02-FastApiBackend.ps1 -Run        # Start the server" -Level "INFO" -LogFile $logFile
    Write-Log -Message "Or run with full setup: .\02-FastApiBackend.ps1 -All" -Level "INFO" -LogFile $logFile
}

Write-Log -Message "Quick test commands (run in another terminal after starting server):" -Level "INFO" -LogFile $logFile
Write-Log -Message "Invoke-RestMethod -Uri http://localhost:8000/api/health" -Level "INFO" -LogFile $logFile
Write-Log -Message "`$body = @{content = 'Hello!'} | ConvertTo-Json" -Level "INFO" -LogFile $logFile
Write-Log -Message "Invoke-RestMethod -Uri http://localhost:8000/api/chat -Method Post -Body `$body -ContentType 'application/json'" -Level "INFO" -LogFile $logFile
Write-Log -Message "Log Files Created:" -Level "INFO" -LogFile $logFile
Write-Log -Message "Full transcript: $transcriptFile" -Level "INFO" -LogFile $logFile
Write-Log -Message "Structured log: $logFile" -Level "INFO" -LogFile $logFile
Write-Log -Message "JARVIS FastAPI Backend Setup (v4.1) Complete!" -Level "SUCCESS" -LogFile $logFile

Stop-Transcript