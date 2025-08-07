# 02-FastApiBackend.ps1 - FastAPI Backend Setup with Virtual Environment
# Purpose: Create backend venv, install dependencies, generate files, test, and run in isolated environment
# Last edit: 2025-08-06 - Manual inpection and alignments

param(
    [switch]$Install,
    [switch]$Configure,
    [switch]$Test,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "5.1.0"
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

$backendDir = Join-Path $projectRoot "backend"
$venvDir = Join-Path $backendDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"

function Test-Prerequisites {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing prerequisites..." -Level INFO -LogFile $LogFile
    $pythonCmd = Get-PythonCommand -LogFile $LogFile
    if (-not $pythonCmd) {
        Write-Log -Message "Python not found. Run 01-Prerequisites.ps1 first." -Level ERROR -LogFile $LogFile
        return $false
    }
    return $true
}

function New-BackendStructure {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating backend directory structure..." -Level INFO -LogFile $LogFile
    $dirs = @("backend", "backend\api", "backend\tests", "backend\services")
    return New-DirectoryStructure -Directories $dirs -LogFile $LogFile
}

function New-RequirementsFile {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating requirements.txt..." -Level INFO -LogFile $LogFile
    $requirementsPath = Join-Path $backendDir "requirements.txt"
    if (Test-Path $requirementsPath) {
        $existing = Get-Content $requirementsPath -Raw
        if ($existing -match "fastapi" -and $existing -match "uvicorn") {
            Write-Log -Message "requirements.txt already exists and is current" -Level SUCCESS -LogFile $LogFile
            return $true
        }
    }
    
    $req = @"
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
        Set-Content -Path $requirementsPath -Value $req -ErrorAction Stop
        Write-Log -Message "Created backend requirements.txt" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create requirements.txt: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-FastApiApplication {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating FastAPI application..." -Level INFO -LogFile $LogFile
    $mainPath = Join-Path $backendDir "api\main.py"
    if (Test-Path $mainPath) {
        Write-Log -Message "FastAPI application already exists" -Level SUCCESS -LogFile $LogFile
        return $true
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
    title='Jarvis AI Assistant',
    description='AI Assistant Backend API',
    version='$scriptVersion'
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)

class ChatMessage(BaseModel):
    content: str

class ChatResponse(BaseModel):
    response: str
    timestamp: str

@app.get('/')
async def root():
    return {
        'message': 'Jarvis AI Assistant Backend',
        'status': 'running',
        'version': '$scriptVersion',
        'docs': '/docs'
    }

@app.get('/api/health')
async def health_check():
    return {
        'status': 'healthy',
        'service': 'jarvis-backend',
        'version': '$scriptVersion',
        'timestamp': datetime.now().isoformat()
    }

@app.post('/api/chat', response_model=ChatResponse)
async def chat(message: ChatMessage):
    response = f'Echo: {message.content}'
    return ChatResponse(
        response=response,
        timestamp=datetime.now().isoformat()
    )

@app.get('/api/status')
async def get_status():
    return {
        'backend': 'running',
        'mode': 'echo (test mode)',
        'features': {
            'chat': True,
            'health_check': True,
            'echo_mode': True
        }
    }

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=8000)
"@
    
    try {
        Set-Content -Path $mainPath -Value $mainApp -ErrorAction Stop
        Set-Content -Path (Join-Path $backendDir "api\__init__.py") -Value "" -ErrorAction Stop
        Write-Log -Message "Created main FastAPI application" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create FastAPI application: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-EnvConfig {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating environment configuration..." -Level INFO -LogFile $LogFile
    $envFile = Join-Path $backendDir ".env"
    
    if (Test-Path $envFile) {
        Write-Log -Message "Backend .env already exists" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    
    try {
        Set-Content -Path $envFile -Value "EXAMPLE_KEY=yourvalue" -ErrorAction Stop
        Write-Log -Message "Created backend/.env config" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create .env config: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-BasicTests {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating basic test suite..." -Level INFO -LogFile $LogFile
    $testPath = Join-Path $backendDir "tests\test_main.py"
    
    if (Test-Path $testPath) {
        Write-Log -Message "Basic test suite already exists" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    
    $testMain = @"
import pytest
from fastapi.testclient import TestClient
from api.main import app

client = TestClient(app)

def test_root():
    response = client.get('/')
    assert response.status_code == 200
    data = response.json()
    assert data['status'] == 'running'
    assert 'Jarvis' in data['message']

def test_health_check():
    response = client.get('/api/health')
    assert response.status_code == 200
    data = response.json()
    assert data['status'] == 'healthy'
    assert 'timestamp' in data

def test_chat_endpoint():
    response = client.post('/api/chat', json={'content': 'Hello'})
    assert response.status_code == 200
    data = response.json()
    assert 'Echo: Hello' in data['response']
    assert 'timestamp' in data

def test_status_endpoint():
    response = client.get('/api/status')
    assert response.status_code == 200
    data = response.json()
    assert data['backend'] == 'running'
    assert data['features']['chat'] is True
"@
    
    try {
        Set-Content -Path $testPath -Value $testMain -ErrorAction Stop
        Set-Content -Path (Join-Path $backendDir "tests\__init__.py") -Value "" -ErrorAction Stop
        Write-Log -Message "Created basic backend test suite" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create test suite: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function New-VirtualEnvironment {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Setting up virtual environment..." -Level INFO -LogFile $LogFile
    if (Test-Path $venvDir) {
        Write-Log -Message "Virtual environment already exists" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    $pyCmd = Get-PythonCommand -LogFile $LogFile
    if (-not $pyCmd) {
        Write-Log -Message "Python not found, cannot create virtual environment" -Level ERROR -LogFile $LogFile
        return $false
    }
    try {
        Write-Log -Message "Creating virtual environment in $venvDir..." -Level INFO -LogFile $LogFile
        & $pyCmd -m venv $venvDir
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Virtual environment created successfully" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Failed to create virtual environment" -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error creating virtual environment: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Install-BackendDependencies {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Installing backend dependencies..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "Virtual environment Python not found at $venvPy" -Level ERROR -LogFile $LogFile
        return $false
    }
    try {
        Write-Log -Message "Upgrading pip..." -Level INFO -LogFile $LogFile
        & $venvPy -m pip install --upgrade pip --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "pip upgraded successfully" -Level SUCCESS -LogFile $LogFile
        }
        Write-Log -Message "Installing requirements..." -Level INFO -LogFile $LogFile
        & $venvPy -m pip install -r (Join-Path $backendDir "requirements.txt") --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "Dependencies installed successfully" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Failed to install dependencies" -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error installing dependencies: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Invoke-BackendTests {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Running backend tests..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path "backend/tests/test_main.py")) {
        Write-Log -Message "Test files not found" -Level ERROR -LogFile $LogFile
        return $false
    }
    Push-Location
    try {
        Set-Location backend
        & $venvPy -m pytest tests/ -v --tb=short
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "All backend tests passed" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Some backend tests failed" -Level WARN -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error running tests: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
    finally { Pop-Location }
}

function New-RunScript {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating backend run script..." -Level INFO -LogFile $LogFile
    $runScript = "run_backend.ps1"
    if (Test-Path $runScript) {
        Write-Log -Message "Backend run script already exists" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    
    $content = @"
# run_backend.ps1 - Start the Jarvis AI Backend (venv)
param(
    [switch]`$Test,
    [switch]`$Health,
    [switch]`$QuickTest
)

. .\00-CommonUtils.ps1
`$backendLogsDir = Join-Path (Get-Location) 'backend\logs'
if (!(Test-Path `$backendLogsDir)) { New-Item -ItemType Directory -Path `$backendLogsDir | Out-Null }
`$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
`$logFile = Join-Path `$backendLogsDir "run_backend-log-`${timestamp}.txt"
Start-Transcript -Path (Join-Path `$backendLogsDir "run_backend-transcript-`${timestamp}.txt")

`$venvPy = Resolve-Path 'backend\.venv\Scripts\python.exe' -ErrorAction Stop

if (`$Health) {
    try {
        `$response = Invoke-RestMethod -Uri 'http://localhost:8000/api/health' -TimeoutSec 5
        Write-Host 'Backend is healthy!' -ForegroundColor Green
        Write-Host "Response: `$(`$response | ConvertTo-Json -Compress)" -ForegroundColor Green
        Stop-Transcript
        return
    } catch {
        Write-Host "Backend not responding on port 8000: `$(`$_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Start the backend first with: .\run_backend.ps1" -ForegroundColor Yellow
        Stop-Transcript
        return
    }
}
if (`$QuickTest) {
    try {
        `$health = Invoke-RestMethod -Uri 'http://localhost:8000/api/health' -TimeoutSec 5
        Write-Host 'Health check: PASSED' -ForegroundColor Green
    } catch {
        Write-Host "Health check: FAILED - Backend not running: `$(`$_.Exception.Message)" -ForegroundColor Red
        Stop-Transcript
        return
    }
    try {
        `$body = @{content = "Hello Jarvis!"} | ConvertTo-Json
        `$chat = Invoke-RestMethod -Uri 'http://localhost:8000/api/chat' -Method Post -Body `$body -ContentType 'application/json' -TimeoutSec 5
        Write-Host 'Chat test: PASSED' -ForegroundColor Green
        Write-Host "Response: `$(`$chat.response)" -ForegroundColor Green
    } catch {
        Write-Host "Chat test: FAILED - `$(`$_.Exception.Message)" -ForegroundColor Red
    }
    try {
        `$status = Invoke-RestMethod -Uri 'http://localhost:8000/api/status' -TimeoutSec 5
        Write-Host 'Status check: PASSED' -ForegroundColor Green
        Write-Host "Mode: `$(`$status.mode)" -ForegroundColor Green
    } catch {
        Write-Host "Status check: FAILED - `$(`$_.Exception.Message)" -ForegroundColor Red
    }
    Stop-Transcript
    return
}
if (`$Test) {
    if (-not (Test-Path 'backend\tests\test_main.py')) {
        Write-Host 'Test files not found in backend/tests/' -ForegroundColor Red
        Stop-Transcript
        return
    }
    Push-Location backend
    try {
        & `$venvPy -m pytest tests/ -v --tb=short
    } finally {
        Pop-Location
    }
    Stop-Transcript
    return
}
Write-Host 'Starting Jarvis AI Backend Server...' -ForegroundColor Cyan
if (-not (Test-Path 'backend\api\main.py')) {
    Write-Host 'Backend application not found! Run: .\02-FastApiBackend.ps1 first' -ForegroundColor Yellow
    Stop-Transcript
    return
}
Push-Location backend
try {
    Write-Host 'Server starting in 3 seconds...' -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    & `$venvPy -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
} finally {
    Pop-Location
    Stop-Transcript
}
"@
    
    try {
        Set-Content -Path $runScript -Value $content -ErrorAction Stop
        Write-Log -Message "Created backend run script" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create run script: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Test-BackendServer {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing FastAPI backend server..." -Level INFO -LogFile $LogFile
    if (-not (Test-Path $venvPy)) {
        Write-Log -Message "Virtual environment not found - cannot test server" -Level ERROR -LogFile $LogFile
        return $false
    }
    if (-not (Test-Path "backend/api/main.py")) {
        Write-Log -Message "FastAPI application not found - cannot test server" -Level ERROR -LogFile $LogFile
        return $false
    }
    Push-Location
    try {
        Set-Location backend
        Write-Log -Message "Starting server temporarily for testing..." -Level INFO -LogFile $LogFile
        
        # Start server in background
        $serverProcess = Start-Process -FilePath $venvPy -ArgumentList "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000" -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 8  # Wait for server to start
        
        # Test endpoints
        $testsPassed = 0
        $totalTests = 3
        
        try {
            $health = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 10
            Write-Log -Message "Health endpoint test: PASSED" -Level SUCCESS -LogFile $LogFile
            $testsPassed++
        } catch {
            Write-Log -Message "Health endpoint test: FAILED - $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        }
        
        try {
            $status = Invoke-RestMethod -Uri "http://localhost:8000/api/status" -TimeoutSec 10
            Write-Log -Message "Status endpoint test: PASSED" -Level SUCCESS -LogFile $LogFile
            $testsPassed++
        } catch {
            Write-Log -Message "Status endpoint test: FAILED - $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        }
        
        try {
            $body = @{content = "Test message"} | ConvertTo-Json
            $chat = Invoke-RestMethod -Uri "http://localhost:8000/api/chat" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10
            Write-Log -Message "Chat endpoint test: PASSED" -Level SUCCESS -LogFile $LogFile
            $testsPassed++
        } catch {
            Write-Log -Message "Chat endpoint test: FAILED - $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        }
        
        # Stop server
        try {
            Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
            Write-Log -Message "Server stopped after testing" -Level INFO -LogFile $LogFile
        } catch {
            Write-Log -Message "Note: Server may still be running (PID: $($serverProcess.Id))" -Level WARN -LogFile $LogFile
        }
        
        Write-Log -Message "Server tests completed: $testsPassed/$totalTests passed" -Level $(if ($testsPassed -eq $totalTests) { "SUCCESS" } else { "WARN" }) -LogFile $LogFile
        return $testsPassed -ge 2  # Pass if at least 2/3 tests work
    }
    catch {
        Write-Log -Message "Error testing server: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
    finally { Pop-Location }
}

# Main execution
try {
    if (-not (Test-Prerequisites -LogFile $logFile)) {
        Stop-Transcript
        exit 1
    }

    $setupResults = @()

    # Setup phase - always run
    Write-Log -Message "Setting up backend structure..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "Backend Structure"; Success = (New-BackendStructure -LogFile $logFile) }
    $setupResults += @{Name = "Requirements File"; Success = (New-RequirementsFile -LogFile $logFile) }
    $setupResults += @{Name = "FastAPI Application"; Success = (New-FastApiApplication -LogFile $logFile) }
    $setupResults += @{Name = "Environment Config"; Success = (New-EnvConfig -LogFile $logFile) }
    $setupResults += @{Name = "Basic Tests"; Success = (New-BasicTests -LogFile $logFile) }
    $setupResults += @{Name = "Virtual Environment"; Success = (New-VirtualEnvironment -LogFile $logFile) }
    $setupResults += @{Name = "Run Script"; Success = (New-RunScript -LogFile $logFile) }

    if ($Install -or $Run) {
        Write-Log -Message "Installing dependencies..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Dependencies"; Success = (Install-BackendDependencies -LogFile $logFile) }
    }

    if ($Configure -or $Run) {
        Write-Log -Message "Configuring backend..." -Level INFO -LogFile $logFile
        Test-EnvironmentConfig -LogFile $logFile | Out-Null
        $setupResults += @{Name = "Configuration"; Success = $true }
    }

    if ($Test -or $Run) {
        Write-Log -Message "Testing backend..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Backend Tests"; Success = (Invoke-BackendTests -LogFile $logFile) }
    }

    # Summary
    Write-Log -Message "=== SETUP SUMMARY ===" -Level INFO -LogFile $logFile
    $successCount = 0
    $failCount = 0
    foreach ($result in $setupResults) {
        if ($result.Success) {
            Write-Log -Message "$($result.Name) - SUCCESS" -Level SUCCESS -LogFile $logFile
            $successCount++
        }
        else {
            Write-Log -Message "$($result.Name) - FAILED" -Level ERROR -LogFile $logFile
            $failCount++
        }
    }
    Write-Log -Message "Setup Results: $successCount successful, $failCount failed" -Level INFO -LogFile $logFile

    if ($failCount -gt 0) {
        Write-Log -Message "Backend setup had failures" -Level ERROR -LogFile $logFile
        Stop-Transcript
        exit 1
    }

    # Output API endpoint URLs
    Write-Log -Message "=== API ENDPOINTS ===" -Level INFO -LogFile $logFile
    Write-Log -Message "Root:           http://localhost:8000/" -Level INFO -LogFile $logFile
    Write-Log -Message "API Docs:       http://localhost:8000/docs" -Level INFO -LogFile $logFile
    Write-Log -Message "Health Check:   http://localhost:8000/api/health" -Level INFO -LogFile $logFile
    Write-Log -Message "Chat Endpoint:  http://localhost:8000/api/chat" -Level INFO -LogFile $logFile
    Write-Log -Message "Status:         http://localhost:8000/api/status" -Level INFO -LogFile $logFile

    if ($Run) { 
        $setupResults += @{Name = "Backend Server Test"; Success = (Test-BackendServer -LogFile $logFile) }
    }
    else {
        Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
        Write-Log -Message "1. .\02-FastApiBackend.ps1 -Run     # Start development server" -Level INFO -LogFile $logFile
        Write-Log -Message "2. .\run_backend.ps1                # Quick start script" -Level INFO -LogFile $logFile
        Write-Log -Message "3. Continue with: .\03-IntegrateOllama.ps1" -Level INFO -LogFile $logFile
    }
}
catch {
    Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript
