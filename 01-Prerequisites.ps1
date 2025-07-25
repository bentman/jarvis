# 01-Prerequisites.ps1 - Install and validate all core system dependencies for JARVIS AI Assistant
# Purpose: Idempotently install Git, Node.js, VSCode, Visual C++ Build Tools, Python 3.12+, Ollama (no Docker/WSL/VSCode ext)
# Last edit: 2025-07-14 - add Get-AvailableHardware call to determine hardware info

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

try {
    if ($Run -or $Install) {
        # --- Ensure winget is available, install if possible (never as a function)
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Log -Message "winget not found. Attempting to install or enable winget..." -Level WARN -LogFile $logFile
            $wingetAttempt = $false
            try {
                Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1" -WindowStyle Hidden
                Write-Log -Message "Please install 'App Installer' (winget) from the Microsoft Store, then re-run this script." -Level WARN -LogFile $logFile
                Start-Sleep -Seconds 30
                if (Get-Command winget -ErrorAction SilentlyContinue) { $wingetAttempt = $true }
            }
            catch {}
            if (-not $wingetAttempt -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
                Write-Log -Message "winget could not be installed automatically. Please install 'App Installer' (winget) from the Microsoft Store or https://github.com/microsoft/winget-cli/releases, then re-run this script." -Level ERROR -LogFile $logFile
                Stop-Transcript
                exit 1
            }
            Write-Log -Message "winget is now available." -Level SUCCESS -LogFile $logFile
        }
        # --- Install Git, Node.js, VSCode
        $tools = @(
            @{Id = "Git.Git"; Name = "Git"; Command = "git" },
            @{Id = "OpenJS.NodeJS"; Name = "Node.js"; Command = "node" },
            @{Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code"; Command = "code" }
        )
        foreach ($tool in $tools) {
            Install-Tool -Id $tool.Id -Name $tool.Name -Command $tool.Command -LogFile $logFile | Out-Null
        }
        # --- Install Visual C++ Build Tools (nVidia CUDA Support)
        Install-VisualCppBuildTools -LogFile $logFile | Out-Null
        # --- Ensure Python 3.12+ is installed (cross-architecture compatible)
        if (-not (Test-PythonVersion -Major 3 -Minor 12 -LogFile $logFile)) {
            Write-Log -Message "Python 3.12+ not detected. Installing Python..." -Level WARN -LogFile $logFile
            # Cross-architecture Python installation
            if ($hardware.Platform -eq "ARM64") {
                Write-Log -Message "ARM64 detected - installing Microsoft Store Python for compatibility..." -Level INFO -LogFile $logFile
                $pythonInstall = Install-Tool -Id "9NCVDN91XZQP" -Name "Python 3.12 (Microsoft Store)" -Command "python" -LogFile $logFile
                if (-not $pythonInstall) {
                    Write-Log -Message "Microsoft Store Python failed, trying standard Python.org package..." -Level WARN -LogFile $logFile
                    $pythonInstall = Install-Tool -Id "Python.Python.3.12" -Name "Python 3.12" -Command "python" -LogFile $logFile
                }
            }
            else {
                Write-Log -Message "Installing Python 3.12 via winget..." -Level INFO -LogFile $logFile
                $pythonInstall = Install-Tool -Id "Python.Python.3.12" -Name "Python 3.12" -Command "python" -LogFile $logFile
            }
            
            if (-not $pythonInstall) {
                Write-Log -Message "Python 3.12 installation failed. Please install manually from https://www.python.org/downloads/" -Level ERROR -LogFile $logFile
                Stop-Transcript
                exit 1
            }
            # Refresh PATH and verify installation
            Write-Log -Message "Refreshing system PATH..." -Level INFO -LogFile $logFile
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 5
            # Final verification - if still not found, recommend terminal restart
            if (-not (Test-PythonVersion -Major 3 -Minor 12 -LogFile $logFile)) {
                Write-Log -Message "Python 3.12+ was installed but not found in current PATH." -Level WARN -LogFile $logFile
                Write-Log -Message "RECOMMENDATION: Close this terminal and open a new one, then re-run this script." -Level WARN -LogFile $logFile
                Write-Log -Message "This is often required after Python installation to refresh PATH variables." -Level INFO -LogFile $logFile
                Stop-Transcript
                exit 1
            }
            Write-Log -Message "Python 3.12+ installed and verified." -Level SUCCESS -LogFile $logFile
        }
        else {
            Write-Log -Message "Python 3.12+ detected in system PATH." -Level SUCCESS -LogFile $logFile
        }
        # --- Install Python pip, virtualenv, pipenv if needed
        Write-Log -Message "Setting up Python environment packages..." -Level INFO -LogFile $logFile
        $pythonPackages = @("pip", "virtualenv", "pipenv")
        foreach ($pkg in $pythonPackages) { Install-PythonPackage -PackageName $pkg -LogFile $logFile | Out-Null }
        # --- Install Ollama and sync model
        Sync-JarvisModel -LogFile $logFile | Out-Null
        Write-Log -Message "=== Installation Complete ===" -Level SUCCESS -LogFile $logFile
    }

    # --- No-op for these modes
    if ($Configure) { Write-Log -Message "There is nothing to configure here" -Level "INFO" -LogFile $logFile }
    if ($Test) { Write-Log -Message "There is nothing to test here" -Level "INFO" -LogFile $logFile }
    if ($Run) { Write-Log -Message "There is nothing to run here" -Level "INFO" -LogFile $logFile }
}
catch {
    Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
}
# --- Finish up and log completion
Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript
