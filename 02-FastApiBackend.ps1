# 02-FastApiBackend.ps1 - FastAPI Backend Setup with Venv
# Purpose: Create backend venv, install dependencies, generate files, test, and run in isolated environment
# Last edit: 2025-07-10 - Correct venv logic, absolute paths, no context ambiguity, outputs API endpoints at completion

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
$transcriptFile = Join-Path $logsDir "${scriptPrefix}-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "${scriptPrefix}-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile
Write-Log -Message "=== $($MyInvocation.MyCommand.Name) v$scriptVersion ===" -Level INFO -LogFile $logFile

Write-SystemInfo -ScriptName $scriptPrefix -Version $scriptVersion -ProjectRoot $projectRoot -LogFile $logFile -Switches @{
    Install   = $Install
    Configure = $Configure
    Test      = $Test
    Run       = $Run
}

$backendDir = Join-Path $projectRoot "backend"
$venvDir = Join-Path $backendDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"

function Sync-Venv {
    param([string]$LogFile)
    if (!(Test-Path $venvDir)) {
        Write-Log -Message "Creating virtual environment in $venvDir..." -Level INFO -LogFile $LogFile
        $pyCmd = Get-PythonCommand -LogFile $LogFile
        if (-not $pyCmd) {
            Write-Log -Message "Python not found, cannot create venv." -Level ERROR -LogFile $LogFile
            exit 1
        }
        & $pyCmd -m venv $venvDir
        Write-Log -Message "Virtual environment created." -Level SUCCESS -LogFile $LogFile
    }
    else {
        Write-Log -Message "Virtual environment already exists." -Level INFO -LogFile $LogFile
    }
    $script:venvPyAbs = Join-Path $venvDir "Scripts\python.exe"
    if (!(Test-Path $script:venvPyAbs)) {
        Write-Log -Message "venv python executable not found at $script:venvPyAbs" -Level ERROR -LogFile $LogFile
        exit 1
    }
    Write-Log -Message "Using venv python: $script:venvPyAbs" -Level INFO -LogFile $LogFile
}

function Install-BackendDependencies-Venv {
    param([string]$LogFile)
    & $script:venvPyAbs -m pip install --upgrade pip
    & $script:venvPyAbs -m pip install -r (Join-Path $backendDir "requirements.txt")
    Write-Log -Message "Dependencies installed in venv." -Level SUCCESS -LogFile $LogFile
}

function Invoke-InVenv {
    param(
        [string]$Args,     # e.g. "-m pytest tests/ -v"
        [string]$Cwd = $backendDir
    )
    Push-Location $Cwd
    try {
        & $script:venvPyAbs $Args
    }
    finally { Pop-Location }
}

function New-BackendStructure {
    param([string]$LogFile)
    $dirs = @("backend", "backend\api", "backend\tests", "backend\services")
    New-DirectoryStructure -Directories $dirs -LogFile $LogFile
}

function New-RequirementsFile {
    param([string]$LogFile)
    $requirementsPath = Join-Path $backendDir "requirements.txt"
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
    if (!(Test-Path $requirementsPath) -or !(Get-Content $requirementsPath | Select-String -Pattern "fastapi")) {
        Set-Content -Path $requirementsPath -Value $req
        Write-Log -Message "Created backend requirements.txt." -Level SUCCESS -LogFile $LogFile
    }
    else {
        Write-Log -Message "requirements.txt already exists." -Level INFO -LogFile $LogFile
    }
}

function New-FastApiApplication {
    param([string]$LogFile)
    $mainPath = Join-Path $backendDir "api\main.py"
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
    if (!(Test-Path $mainPath)) {
        Set-Content -Path $mainPath -Value $mainApp
        Set-Content -Path (Join-Path $backendDir "api\__init__.py") -Value ""
        Write-Log -Message "Created main FastAPI application." -Level SUCCESS -LogFile $LogFile
    }
    else {
        Write-Log -Message "backend/api/main.py already exists." -Level INFO -LogFile $LogFile
    }
}

function New-EnvConfig {
    param([string]$LogFile)
    $envFile = Join-Path $backendDir ".env"
    if (!(Test-Path $envFile)) {
        Set-Content -Path $envFile -Value "EXAMPLE_KEY=yourvalue"
        Write-Log -Message "Created backend/.env config." -Level SUCCESS -LogFile $LogFile
    }
    else {
        Write-Log -Message "backend/.env already exists." -Level INFO -LogFile $LogFile
    }
}

function New-BasicTests {
    param([string]$LogFile)
    $testPath = Join-Path $backendDir "tests\test_main.py"
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
    if (!(Test-Path $testPath)) {
        Set-Content -Path $testPath -Value $testMain
        Set-Content -Path (Join-Path $backendDir "tests\__init__.py") -Value ""
        Write-Log -Message "Created basic backend test suite." -Level SUCCESS -LogFile $LogFile
    }
    else {
        Write-Log -Message "backend/tests/test_main.py already exists." -Level INFO -LogFile $LogFile
    }
}

function New-RunScript {
    param([string]$LogFile)
    $runScript = "run_backend.ps1"
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
        Write-Host "Backend not responding on port 8000: `$($_.Exception.Message)" -ForegroundColor Yellow
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
        Write-Host "Health check: FAILED - Backend not running: `$($_.Exception.Message)" -ForegroundColor Red
        Stop-Transcript
        return
    }
    try {
        `$body = @{content = "Hello Jarvis!"} | ConvertTo-Json
        `$chat = Invoke-RestMethod -Uri 'http://localhost:8000/api/chat' -Method Post -Body `$body -ContentType 'application/json' -TimeoutSec 5
        Write-Host 'Chat test: PASSED' -ForegroundColor Green
        Write-Host "Response: `$(`$chat.response)" -ForegroundColor Green
    } catch {
        Write-Host "Chat test: FAILED - `$($_.Exception.Message)" -ForegroundColor Red
    }
    try {
        `$status = Invoke-RestMethod -Uri 'http://localhost:8000/api/status' -TimeoutSec 5
        Write-Host 'Status check: PASSED' -ForegroundColor Green
        Write-Host "Mode: `$(`$status.mode)" -ForegroundColor Green
    } catch {
        Write-Host "Status check: FAILED - `$($_.Exception.Message)" -ForegroundColor Red
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
    Set-Content -Path $runScript -Value $content
    Write-Log -Message "Created backend run script." -Level SUCCESS -LogFile $LogFile
}

# ---- MAIN EXECUTION FLOW ----
New-BackendStructure -LogFile $logFile
New-RequirementsFile -LogFile $logFile
New-FastApiApplication -LogFile $logFile
New-EnvConfig -LogFile $logFile
New-BasicTests -LogFile $logFile
New-RunScript -LogFile $logFile

Sync-Venv -LogFile $logFile

if ($Install -or (-not ($Install -or $Configure -or $Test -or $Run))) {
    Install-BackendDependencies-Venv -LogFile $logFile
}

if ($Test) {
    Invoke-InVenv "-m pytest tests/ -v"
}

if ($Run) {
    Write-Log -Message "Starting FastAPI backend in venv..." -Level INFO -LogFile $logFile
    Invoke-InVenv "-m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000"
}

# --- Output API endpoint URLs in logs ---
Write-Log -Message "=== API ENDPOINTS ===" -Level INFO -LogFile $logFile
Write-Log -Message "Root:           http://localhost:8000/" -Level INFO -LogFile $logFile
Write-Log -Message "API Docs:       http://localhost:8000/docs" -Level INFO -LogFile $logFile
Write-Log -Message "Health Check:   http://localhost:8000/api/health" -Level INFO -LogFile $logFile
Write-Log -Message "Chat Endpoint:  http://localhost:8000/api/chat" -Level INFO -LogFile $logFile
Write-Log -Message "Status:         http://localhost:8000/api/status" -Level INFO -LogFile $logFile

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript
