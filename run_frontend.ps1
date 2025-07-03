# ------------------- run_frontend.ps1 -------------------
$Host.UI.RawUI.WindowTitle = "Jarvis - Front"
Write-Host "`n=== Starting Frontend (React) ===" -ForegroundColor Cyan

$frontendDir = "frontend"
$packageJson = Join-Path $frontendDir "package.json"
if (-not (Test-Path $packageJson)) {
    Write-Host "Frontend package.json not found at $packageJson" -ForegroundColor Red
    exit 1
}

# Check if frontend is already running
$Host.UI.RawUI.WindowTitle = "Jarvis - Front"
try {
    Invoke-WebRequest -Uri "http://localhost:3000" -TimeoutSec 2 -UseBasicParsing | Out-Null
    Write-Host "Frontend already running on port 3000" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop or close this window" -ForegroundColor Gray
    while ($true) { Start-Sleep -Seconds 10 }
}
catch {
    # Frontend not running, start it
    Push-Location $frontendDir
    try {
        if (-not (Test-Path "node_modules")) {
            Write-Host "node_modules not found. Running npm install..." -ForegroundColor Yellow
            npm install
            if ($LASTEXITCODE -ne 0) {
                Write-Host "npm install failed. Please check errors above." -ForegroundColor Red
                Pop-Location
                exit 1
            }
        }

        Write-Host "Starting React frontend..." -ForegroundColor Yellow
        Write-Host "Frontend will be available at http://localhost:3000" -ForegroundColor Green
        npm start
    }
    finally {
        Pop-Location
    }
}
