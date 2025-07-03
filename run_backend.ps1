# ------------------- run_backend.ps1 -------------------
$Host.UI.RawUI.WindowTitle = "Jarvis - Back"
Write-Host "`n=== Starting Backend (Ollama + API) ===" -ForegroundColor Cyan

function Test-Ollama {
    try {
        Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# 1. Ensure Ollama is running
if (-not (Test-Ollama)) {
    Write-Host "Ollama not running. Attempting to start..." -ForegroundColor Yellow
    try {
        Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 4
        
        # Wait a bit longer and test again
        $attempts = 0
        while (-not (Test-Ollama) -and $attempts -lt 10) {
            Start-Sleep -Seconds 1
            $attempts++
        }
    }
    catch {
        Write-Host "Failed to start Ollama: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Ollama)) {
        Write-Host "Ollama still not running after attempt. Please check installation." -ForegroundColor Red
        exit 1
    }
    Write-Host "Ollama started successfully." -ForegroundColor Green
}
else {
    Write-Host "Ollama is running." -ForegroundColor Green
}

# 2. Start FastAPI backend
$backendMain = "backend/api/main.py"
if (-not (Test-Path $backendMain)) {
    Write-Host "Backend main.py not found at $backendMain" -ForegroundColor Red
    exit 1
}

# Check if backend is already running
$Host.UI.RawUI.WindowTitle = "Jarvis - Back"
try {
    Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 2 | Out-Null
    Write-Host "Backend already running on port 8000" -ForegroundColor Yellow
    Write-Host "API Docs: http://localhost:8000/docs" -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop or close this window" -ForegroundColor Gray
    while ($true) { Start-Sleep -Seconds 10 }
}
catch {
    # Backend not running, start it
    Write-Host "Starting backend: uvicorn backend.api.main:app --reload" -ForegroundColor Yellow
    
    # Check if we're in the right directory structure
    if (-not (Test-Path $backendMain)) {
        Write-Host "Error: $backendMain not found. Run from project root." -ForegroundColor Red
        exit 1
    }
    
    # Check if dependencies are installed
    Push-Location backend
    try {
        $pipList = pip list 2>$null
        if (-not ($pipList -match "fastapi" -and $pipList -match "uvicorn")) {
            Write-Host "Installing backend dependencies..." -ForegroundColor Yellow
            pip install -r requirements.txt
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to install dependencies" -ForegroundColor Red
                Pop-Location
                exit 1
            }
        }
        
        Write-Host "Backend will be available at:" -ForegroundColor Green
        Write-Host "  • API: http://localhost:8000" -ForegroundColor White
        Write-Host "  • Docs: http://localhost:8000/docs" -ForegroundColor White
        Write-Host "  • Health: http://localhost:8000/api/health" -ForegroundColor White
        Write-Host ""
        
        # Start uvicorn from backend directory so imports work
        python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
    }
    finally {
        Pop-Location
    }
}