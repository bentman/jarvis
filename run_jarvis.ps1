# ==================== run_jarvis.ps1 ====================
$Host.UI.RawUI.WindowTitle = "Jarvis Control Center"

function Test-Service {
    param(
        [string]$url,
        [int]$timeout = 2
    )
    try {
        Invoke-RestMethod -Uri $url -TimeoutSec $timeout | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-Web {
    param(
        [string]$url,
        [int]$timeout = 2
    )
    try {
        Invoke-WebRequest -Uri $url -TimeoutSec $timeout -UseBasicParsing | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-StatusAll {
    Write-Host "`n=== Jarvis Service Status ==="
    
    # Test each service with proper error handling
    Write-Host "Testing services..." -ForegroundColor Gray
    
    $ollama = $false
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3
        $ollama = $true
    }
    catch {
        $ollama = $false
    }
    
    $backend = $false  
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 3
        $backend = $true
    }
    catch {
        $backend = $false
    }
    
    $frontend = $false
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3000" -TimeoutSec 3 -UseBasicParsing
        $frontend = $true
    }
    catch {
        $frontend = $false
    }

    Write-Host "Ollama:   " -NoNewline
    Write-Host ($ollama ? "🟢 Running" : "🔴 Stopped") -ForegroundColor ($ollama ? "Green" : "Red")

    Write-Host "Backend:  " -NoNewline  
    Write-Host ($backend ? "🟢 Running" : "🔴 Stopped") -ForegroundColor ($backend ? "Green" : "Red")

    Write-Host "Frontend: " -NoNewline
    Write-Host ($frontend ? "🟢 Running" : "🔴 Stopped") -ForegroundColor ($frontend ? "Green" : "Red")

    Write-Host ""
    
    # Show access points if services are running
    if ($backend -and $frontend) {
        Write-Host "🌐 Access Points:" -ForegroundColor Cyan
        Write-Host "  • Chat Interface: http://localhost:3000" -ForegroundColor White
        Write-Host "  • API Docs: http://localhost:8000/docs" -ForegroundColor White
        Write-Host "  • Health Check: http://localhost:8000/api/health" -ForegroundColor White
    }
    elseif ($frontend -and -not $backend) {
        Write-Host "⚠️  Frontend running but backend stopped" -ForegroundColor Yellow
        Write-Host "  Chat will show 'Cannot connect to Jarvis backend'" -ForegroundColor Gray
    }
    elseif ($backend -and -not $frontend) {
        Write-Host "⚠️  Backend running but frontend stopped" -ForegroundColor Yellow  
        Write-Host "  API available at http://localhost:8000/docs" -ForegroundColor Gray
    }
    
    # Show what's needed
    if (-not $ollama) {
        Write-Host "💡 Start Ollama: .\run_backend.ps1 (includes Ollama)" -ForegroundColor Yellow
    }
    if (-not $backend) {
        Write-Host "💡 Start Backend: .\run_backend.ps1" -ForegroundColor Yellow
    }
    if (-not $frontend) {
        Write-Host "💡 Start Frontend: .\run_frontend.ps1" -ForegroundColor Yellow
    }
}

function Start-AllNewWindows {
    Write-Host "`nLaunching Backend and Frontend in new windows..." -ForegroundColor Cyan
    
    # Check if scripts exist
    if (-not (Test-Path "run_backend.ps1")) {
        Write-Host "Error: run_backend.ps1 not found" -ForegroundColor Red
        return
    }
    if (-not (Test-Path "run_frontend.ps1")) {
        Write-Host "Error: run_frontend.ps1 not found" -ForegroundColor Red
        return
    }
    
    # Start backend window
    Start-Process powershell -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-NoExit",
        "-Command", "Set-Location '$PWD'; .\run_backend.ps1"
    )
    
    # Wait a moment to ensure backend starts first
    Write-Host "Waiting for backend to initialize..." -ForegroundColor Yellow
    for ($i = 20; $i -gt 0; $i--) {
        Write-Host "Starting frontend in $i seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds 1
    }
    
    # Start frontend window
    Start-Process powershell -ArgumentList @(
        "-NoProfile", 
        "-ExecutionPolicy", "Bypass",
        "-NoExit",
        "-Command", "Set-Location '$PWD'; .\run_frontend.ps1"
    )
    
    Write-Host "Launched backend and frontend windows." -ForegroundColor Green
    Write-Host "Backend window title: 'Jarvis - Backend'" -ForegroundColor Gray
    Write-Host "Frontend window title: 'Jarvis - Frontend'" -ForegroundColor Gray
    Write-Host "It may take 10-30 seconds for services to be available." -ForegroundColor Yellow
}

function Start-AllBackground {
    Write-Host "`nStarting Backend and Frontend in background jobs..." -ForegroundColor Cyan
    
    # Check if scripts exist
    if (-not (Test-Path "run_backend.ps1") -or -not (Test-Path "run_frontend.ps1")) {
        Write-Host "Error: run_backend.ps1 or run_frontend.ps1 not found" -ForegroundColor Red
        return
    }
    
    $backendJob = Start-Job -ScriptBlock {
        param($projectPath)
        Set-Location $projectPath
        & .\run_backend.ps1
    } -ArgumentList $PWD
    
    $frontendJob = Start-Job -ScriptBlock {
        param($projectPath)
        Set-Location $projectPath
        & .\run_frontend.ps1
    } -ArgumentList $PWD
    
    Write-Host "Started backend (Job ID: $($backendJob.Id)) and frontend (Job ID: $($frontendJob.Id))" -ForegroundColor Green
    Write-Host "Use 'Get-Job' and 'Receive-Job $($backendJob.Id)' to monitor." -ForegroundColor Gray
}

function Stop-All {
    Write-Host "`nStopping all Jarvis-related services..." -ForegroundColor Cyan
    
    $stopped = 0
    
    # Stop backend (python/uvicorn processes)
    $pythonProcs = Get-Process -Name "python*" -ErrorAction SilentlyContinue | Where-Object { 
        $_.CommandLine -like "*uvicorn*" -or $_.CommandLine -like "*backend.api.main*" -or $_.CommandLine -like "*8000*"
    }
    foreach ($proc in $pythonProcs) {
        try {
            Stop-Process -Id $proc.Id -Force
            Write-Host "Stopped backend process (PID: $($proc.Id))" -ForegroundColor Yellow
            $stopped++
        }
        catch { }
    }
    
    # Stop frontend (node/react processes)
    $nodeProcs = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { 
        $_.CommandLine -like "*react-scripts*" -or $_.CommandLine -like "*3000*"
    }
    foreach ($proc in $nodeProcs) {
        try {
            Stop-Process -Id $proc.Id -Force
            Write-Host "Stopped frontend process (PID: $($proc.Id))" -ForegroundColor Yellow
            $stopped++
        }
        catch { }
    }
    
    # Stop background jobs
    $jobs = Get-Job -ErrorAction SilentlyContinue
    if ($jobs) {
        $jobs | Stop-Job -ErrorAction SilentlyContinue
        $jobs | Remove-Job -ErrorAction SilentlyContinue
        Write-Host "Stopped background jobs" -ForegroundColor Yellow
    }
    
    # Note about Ollama (don't stop it automatically as it might be used by other apps)
    if (Test-Service "http://localhost:11434/api/tags") {
        Write-Host "Ollama left running (shared service)" -ForegroundColor Gray
        Write-Host "To stop Ollama manually: Get-Process ollama | Stop-Process" -ForegroundColor Gray
    }
    
    if ($stopped -eq 0) {
        Write-Host "No Jarvis processes found to stop" -ForegroundColor Gray
    }
    else {
        Write-Host "Stopped $stopped processes" -ForegroundColor Green
    }
}

# Main menu loop
while ($true) {
    Write-Host @"
========================================
      Jarvis AI Assistant Control
========================================
[1] Check Status
[2] Start All (New Windows)
[3] Start All (Background)
[4] Stop All
[5] Exit
"@
    $choice = Read-Host "Select an option (1-5)"
    switch ($choice) {
        "1" { Test-StatusAll }
        "2" { Start-AllNewWindows }
        "3" { Start-AllBackground }
        "4" { Stop-All }
        "5" { Write-Host "Goodbye!"; break }
        default { Write-Host "Invalid option. Try again." -ForegroundColor Red }
    }
}
# ==================== END OF FILE ====================