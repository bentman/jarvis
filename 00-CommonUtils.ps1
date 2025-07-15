# Common-Utils.ps1 - Shared utilities for JARVIS AI Assistant scripts
# Purpose: Contains logging, Python package management, tool checks, and hardware detection
# Last edit: 2025-07-14 - Added Get-AvailableHardware function

$scriptVersion = "2.3.0"

# Log system information with modular switches
function Write-SystemInfo {
    param(
        [Parameter(Mandatory = $true)] [string]$ScriptName,
        [Parameter(Mandatory = $true)] [string]$Version,
        [Parameter(Mandatory = $true)] [string]$ProjectRoot,
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [Parameter(Mandatory = $true)] [hashtable]$Switches
    )
    Write-Log -Message "=== SYSTEM INFORMATION ===" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "Script: $ScriptName (v$Version)" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "Timestamp: $(Get-Date)" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "Project Root: $ProjectRoot" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "OS Architecture: $env:PROCESSOR_ARCHITECTURE" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "User: $env:USERNAME" -Level "INFO" -LogFile $LogFile
    foreach ($switch in $Switches.GetEnumerator()) {
        Write-Log -Message "$($switch.Key) Mode: $($switch.Value)" -Level "INFO" -LogFile $LogFile
    }
    Write-Log -Message "=========================" -Level "INFO" -LogFile $LogFile
}

# Custom logging function with streamlined color output
function Write-Log {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Message = "",
        [string]$Level = "INFO",
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    if ([string]::IsNullOrWhiteSpace($Message)) {
        Write-Host ""
        Add-Content -Path $LogFile -Value "" -ErrorAction SilentlyContinue
        return
    }
    $logTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$logTimestamp] [$Level] $Message"
    $colorMap = @{
        "ERROR"   = "Red"
        "WARN"    = "Yellow"
        "SUCCESS" = "Green"
        "INFO"    = "Cyan"
    }
    Write-Host $logEntry -ForegroundColor ($colorMap[$Level] ?? "White")
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
}

function Test-PythonVersion {
    param(
        [Parameter(Mandatory = $true)] [int]$Major,
        [Parameter(Mandatory = $true)] [int]$Minor,
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    $pythonCmds = @("python", "python3")
    foreach ($cmd in $pythonCmds) {
        try {
            $verOutput = & $cmd --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $verOutput -match "Python (\d+)\.(\d+)\.(\d+)") {
                $foundMajor = [int]$Matches[1]
                $foundMinor = [int]$Matches[2]
                $foundPatch = [int]$Matches[3]
                if ($foundMajor -gt $Major -or ($foundMajor -eq $Major -and $foundMinor -ge $Minor)) {
                    Write-Log -Message "$cmd version $foundMajor.$foundMinor.$foundPatch meets requirement ($Major.$Minor+)" -Level SUCCESS -LogFile $LogFile
                    return $true
                }
                else {
                    Write-Log -Message "$cmd version $foundMajor.$foundMinor.$foundPatch found, but does not meet required version ($Major.$Minor+)" -Level WARN -LogFile $LogFile
                }
            }
        }
        catch {
            # Ignore missing python command
        }
    }
    Write-Log -Message "Python $Major.$Minor+ not found in PATH." -Level ERROR -LogFile $LogFile
    return $false
}

# Resolve Python command with version check
function Get-PythonCommand {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    if ($env:JARVIS_PYTHON_CMD) {
        Write-Log -Message "Using cached Python command: $env:JARVIS_PYTHON_CMD" -Level "INFO" -LogFile $LogFile
        return $env:JARVIS_PYTHON_CMD
    }
    $commands = @("py", "python", "python3")
    foreach ($cmd in $commands) {
        if ($command = Get-Command $cmd -ErrorAction SilentlyContinue) {
            try {
                $version = & $cmd --version 2>$null
                if ($version -match "Python (\d+\.\d+\.\d+)") {
                    $versionParts = $matches[1].Split('.')
                    if ([int]$versionParts[0] -ge 3 -and [int]$versionParts[1] -ge 8) {
                        $env:JARVIS_PYTHON_CMD = $cmd
                        Write-Log -Message "Resolved Python command: $cmd (v$($matches[1]))" -Level "SUCCESS" -LogFile $LogFile
                        return $cmd
                    }
                }
            }
            catch {
                Write-Log -Message "$cmd --version failed: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
            }
        }
    }
    Write-Log -Message "No suitable Python command found (requires >=3.8)" -Level "ERROR" -LogFile $LogFile
    return $null
}

# Test Python package installation
function Test-PythonPackageInstalled {
    param(
        [Parameter(Mandatory = $true)] [string]$PackageName,
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    $pythonCmd = Get-PythonCommand -LogFile $LogFile
    if (-not $pythonCmd) {
        Write-Log -Message "No Python command available to check package: $PackageName" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    try {
        $basePackageName = $PackageName.Split('[')[0]
        $result = & $pythonCmd -m pip list --disable-pip-version-check 2>$null | Select-String -Pattern "^$basePackageName\s"
        $installed = $null -ne $result
        Write-Log -Message "Python package $PackageName $(if ($installed) { 'found' } else { 'not found' })" -Level ($installed ? "SUCCESS" : "WARN") -LogFile $LogFile
        return $installed
    }
    catch {
        Write-Log -Message "Error checking package ${$PackageName}: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Install Python package with streamlined pip handling
function Install-PythonPackage {
    param(
        [Parameter(Mandatory = $true)] [string]$PackageName,
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    if (Test-PythonPackageInstalled -PackageName $PackageName -LogFile $LogFile) {
        Write-Log -Message "$PackageName already installed" -Level "INFO" -LogFile $LogFile
        return $true
    }
    $pythonCmd = Get-PythonCommand -LogFile $LogFile
    if (-not $pythonCmd) {
        Write-Log -Message "No Python command found for installing $PackageName" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    try {
        Write-Log -Message "Installing Python package: $PackageName" -Level "INFO" -LogFile $LogFile
        & $pythonCmd -m pip install --upgrade $PackageName --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "$PackageName installed successfully" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "$PackageName installation failed" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Failed to install ${$PackageName}: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Detect active Ollama model with optimized .env parsing
function Get-OllamaModel {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Detecting active Ollama model..." -Level "INFO" -LogFile $LogFile
    $defaultModel = "phi3:mini"
    $envPath = Join-Path -Path (Get-Location) -ChildPath ".env"
    if (Test-Path $envPath) {
        try {
            $envContent = Get-Content $envPath -ErrorAction Stop
            $modelMatch = $envContent | Where-Object { $_ -match "^OLLAMA_MODEL\s*=\s*['`"]?([^'`"\s]+)['`"]?" } | Select-Object -First 1
            if ($modelMatch -and $matches[1]) {
                Write-Log -Message "OLLAMA_MODEL from .env: $($matches[1])" -Level "SUCCESS" -LogFile $LogFile
                return $matches[1]
            }
        }
        catch {
            Write-Log -Message "Error reading .env: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
        }
    }
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3 -ErrorAction Stop
        if ($response.models -and $response.models.Count -gt 0) {
            $model = $response.models[0].name
            Write-Log -Message "Detected Ollama model: $model" -Level "SUCCESS" -LogFile $LogFile
            return $model
        }
    }
    catch {
        Write-Log -Message "Ollama API not available: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
    }
    Write-Log -Message "Defaulting to $defaultModel" -Level "INFO" -LogFile $LogFile
    return $defaultModel
}

# Test if tool is installed with optimized command checking
function Test-Tool {
    param(
        [Parameter(Mandatory = $true)] [string]$Id,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [string]$Command,
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [string]$VersionFlag = "--version"
    )
    try {
        if ($commandPath = Get-Command $Command -ErrorAction SilentlyContinue) {
            $version = & $Command $VersionFlag 2>$null | Select-Object -First 1
            Write-Log -Message "$Name found: $($version ?? 'version unknown')" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        if (winget list --id $Id --exact 2>$null -and $LASTEXITCODE -eq 0) {
            Write-Log -Message "$Name installed but not in PATH" -Level "WARN" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "$Name not installed" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Error checking ${$Name}: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Install tool via winget with silent operation
function Install-Tool {
    param(
        [Parameter(Mandatory = $true)] [string]$Id,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [string]$Command,
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [bool]$Optional = $false
    )
    if ($Optional -and $script:SkipOptional) {
        Write-Log -Message "Skipping optional tool: $Name" -Level "WARN" -LogFile $LogFile
        return $true
    }
    if (Test-Tool -Id $Id -Name $Name -Command $Command -LogFile $LogFile) {
        return $true
    }
    Write-Log -Message "Installing $Name..." -Level "INFO" -LogFile $LogFile
    try {
        winget install --id $Id --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "$Name installed successfully" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        Write-Log -Message "$Name installation failed" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "$Name installation failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Validate environment configuration with streamlined .env handling
function Test-EnvironmentConfig {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Validating environment configuration..." -Level "INFO" -LogFile $LogFile
    $envPath = Join-Path -Path (Get-Location) -ChildPath ".env"
    if (-not (Test-Path $envPath)) {
        Write-Log -Message ".env file not found, creating with defaults" -Level "WARN" -LogFile $LogFile
        $defaultContent = @"
OLLAMA_MODEL=phi3:mini
ENVIRONMENT=development
DEBUG=true
LOG_LEVEL=DEBUG
API_HOST=0.0.0.0
API_PORT=8000
SECRET_KEY=dev_secret_key_$(Get-Random)
"@
        try {
            Set-Content -Path $envPath -Value $defaultContent -ErrorAction Stop
            Write-Log -Message ".env created with default OLLAMA_MODEL=phi3:mini" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        catch {
            Write-Log -Message "Failed to create .env: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
            return $false
        }
    }
    try {
        # Read the entire file content
        $envContent = Get-Content $envPath -Raw -ErrorAction Stop
        # Check if OLLAMA_MODEL is defined anywhere in the file
        if ($envContent -notmatch "OLLAMA_MODEL\s*=") {
            Write-Log -Message "OLLAMA_MODEL not defined, adding to .env" -Level "WARN" -LogFile $LogFile
            # Add a newline if file doesn't end with one
            if (-not $envContent.EndsWith("`n")) {
                Add-Content -Path $envPath -Value "" -ErrorAction Stop
            }
            Add-Content -Path $envPath -Value "OLLAMA_MODEL=phi3:mini" -ErrorAction Stop
            Write-Log -Message "Added OLLAMA_MODEL=phi3:mini to .env" -Level "SUCCESS" -LogFile $LogFile
        }
        else {
            Write-Log -Message "OLLAMA_MODEL already defined in .env" -Level "SUCCESS" -LogFile $LogFile
        }
        
        Write-Log -Message "Environment configuration valid" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Error validating .env: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Comprehensive prerequisite checks with optimized output
function Test-Prerequisites {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [switch]$IncludeDocker
    )
    Write-Log -Message "Running system checks..." -Level "INFO" -LogFile $LogFile
    $results = @()
    $tools = @(
        @{Id = "Git.Git"; Name = "Git"; Command = "git" },
        @{Id = "Python.Python.3.11"; Name = "Python 3.11"; Command = "python" },
        @{Id = "OpenJS.NodeJS"; Name = "Node.js"; Command = "node" },
        @{Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code"; Command = "code" },
        @{Id = "Ollama.Ollama"; Name = "Ollama"; Command = "ollama" }
    )
    if ($IncludeDocker) {
        $tools += @{Id = "Docker.DockerDesktop"; Name = "Docker Desktop"; Command = "docker" }
    }
    foreach ($tool in $tools) {
        $status = Test-Tool -Id $tool.Id -Name $tool.Name -Command $tool.Command -LogFile $LogFile
        $results += "$($status ? '✅' : '❌') $($tool.Name)"
    }
    $wslStatus = Test-Tool -Id "Microsoft.WSL" -Name "WSL" -Command "wsl" -LogFile $LogFile
    $results += "$($wslStatus ? '✅' : '❌') WSL"
    Write-Log -Message "=== VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $results) {
        Write-Log -Message $result -Level ($result -like "✅*" ? "SUCCESS" : "ERROR") -LogFile $LogFile
    }
    $successCount = ($results | Where-Object { $_ -like "✅*" }).Count
    Write-Log -Message "Validation: $successCount/$($results.Count) tools ready" -Level ($successCount -eq $results.Count ? "SUCCESS" : "ERROR") -LogFile $LogFile
    return $successCount -eq $results.Count
}

function Test-Command {
    param(
        [Parameter(Mandatory = $true)] [string]$Command,
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    try {
        $null = Get-Command $Command -ErrorAction Stop
        Write-Log -Message "Command '$Command' found in PATH" -Level "INFO" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Command '$Command' not found in PATH" -Level "WARN" -LogFile $LogFile
        return $false
    }
}

function Test-OllamaRunning {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
        Write-Log -Message "Ollama service is running" -Level "INFO" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Ollama service is not running" -Level "WARN" -LogFile $LogFile
        return $false
    }
}

# Create directory structure with batch creation
function New-DirectoryStructure {
    param(
        [Parameter(Mandatory = $true)] [string[]]$Directories,
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    Write-Log -Message "Creating directory structure..." -Level "INFO" -LogFile $LogFile
    $created = 0
    foreach ($dir in $Directories) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
                Write-Log -Message "Created directory: $dir" -Level "SUCCESS" -LogFile $LogFile
                $created++
            }
            catch {
                Write-Log -Message "Failed to create directory ${$dir}: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
            }
        }
        else {
            Write-Log -Message "Directory exists: $dir" -Level "INFO" -LogFile $LogFile
        }
    }
    Write-Log -Message "Directory creation complete: $created created" -Level "SUCCESS" -LogFile $LogFile
    return $true
}

# Install Visual C++ Build Tools
function Install-VisualCppBuildTools {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Checking Visual C++ Build Tools..." -Level "INFO" -LogFile $LogFile
    try {
        $vcInstalled = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\*\VC\*" -ErrorAction SilentlyContinue) -or
        (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -like "*Visual Studio*Build Tools*" -or $_.DisplayName -like "*Microsoft Visual C++*" })
        if ($vcInstalled) {
            Write-Log -Message "Visual C++ Build Tools found" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
    }
    catch {
        Write-Log -Message "Error checking Visual C++ Build Tools: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
    }
    Write-Log -Message "Installing Visual C++ Build Tools (required for PyAudio)..." -Level "INFO" -LogFile $LogFile
    $success = Install-Tool -Id "Microsoft.VisualStudio.2022.BuildTools" -Name "Visual C++ Build Tools" -Command "cl" -LogFile $LogFile
    if (-not $success) {
        Write-Log -Message "PyAudio installation may fail without Visual C++ Build Tools" -Level "WARN" -LogFile $LogFile
        Write-Log -Message "Manually install from: https://visualstudio.microsoft.com/visual-cpp-build-tools/" -Level "INFO" -LogFile $LogFile
    }
    return $success
}

# Install and verify Ollama with model downloading
function Install-OllamaAndModels {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [string[]]$EssentialModels = @("phi3:mini")
    )
    Write-Log -Message "Checking Ollama installation..." -Level "INFO" -LogFile $LogFile
    if (-not (Test-Tool -Id "Ollama.Ollama" -Name "Ollama" -Command "ollama" -LogFile $LogFile)) {
        $success = Install-Tool -Id "Ollama.Ollama" -Name "Ollama" -Command "ollama" -LogFile $LogFile
        if (-not $success) {
            Write-Log -Message "Ollama is required for local LLM support" -Level "ERROR" -LogFile $LogFile
            return $false
        }
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        Start-Sleep -Seconds 3
    }
    try {
        $testResponse = ollama list 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "Starting Ollama service..." -Level "INFO" -LogFile $LogFile
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
            Start-Sleep -Seconds 8
            $testResponse = ollama list 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Message "Ollama service may not have started properly" -Level "WARN" -LogFile $LogFile
                Write-Log -Message "Try manually: ollama serve" -Level "INFO" -LogFile $LogFile
                return $true
            }
        }
        Write-Log -Message "Ollama service is running" -Level "SUCCESS" -LogFile $LogFile
    }
    catch {
        Write-Log -Message "Could not test Ollama service: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
        return $true
    }
    foreach ($model in $EssentialModels) {
        Write-Log -Message "Checking model: $model" -Level "INFO" -LogFile $LogFile
        try {
            $existingModels = ollama list 2>$null
            if ($LASTEXITCODE -eq 0 -and $existingModels -match $model) {
                Write-Log -Message "Model $model already available" -Level "SUCCESS" -LogFile $LogFile
            }
            elseif ($LASTEXITCODE -eq 0) {
                Write-Log -Message "Downloading $model (this may take several minutes)..." -Level "INFO" -LogFile $LogFile
                $pullResult = ollama pull $model 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log -Message "Model $model downloaded successfully" -Level "SUCCESS" -LogFile $LogFile
                }
                else {
                    Write-Log -Message "Model $model download failed" -Level "WARN" -LogFile $LogFile
                    Write-Log -Message "Run manually: ollama pull $model" -Level "INFO" -LogFile $LogFile
                }
            }
            else {
                Write-Log -Message "Could not check models - Ollama service may not be ready" -Level "WARN" -LogFile $LogFile
                Write-Log -Message "Run manually: ollama pull $model" -Level "INFO" -LogFile $LogFile
            }
        }
        catch {
            Write-Log -Message "Could not verify/download ${$model}: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
            Write-Log -Message "Run manually: ollama pull $model" -Level "INFO" -LogFile $LogFile
        }
    }
    return $true
}

# Install VS Code extensions
function Install-VSCodeExtensions {
    param(
        [Parameter(Mandatory = $true)] [string[]]$Extensions,
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    Write-Log -Message "Installing VS Code Extensions..." -Level "INFO" -LogFile $LogFile
    $success = $true
    foreach ($ext in $Extensions) {
        try {
            code --install-extension $ext --force 2>$null
            Write-Log -Message "Installed VS Code extension: $ext" -Level "SUCCESS" -LogFile $LogFile
        }
        catch {
            Write-Log -Message "Failed to install VS Code extension ${$ext}: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
            $success = $false
        }
    }
    return $success
}

# Install winget if not available
function Install-Winget {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    if (Test-Tool -Id "Microsoft.AppInstaller" -Name "winget" -Command "winget" -LogFile $LogFile) {
        return $true
    }
    Write-Log -Message "Installing Windows Package Manager (winget)..." -Level "INFO" -LogFile $LogFile
    try {
        $progressPreference = 'silentlyContinue'
        $tempFile = "$env:TEMP\winget.msixbundle"
        Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile $tempFile
        Add-AppxPackage $tempFile
        Remove-Item $tempFile -Force
        Write-Log -Message "winget installed successfully" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "winget installation failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        Write-Log -Message "Install manually from Microsoft Store or https://github.com/microsoft/winget-cli/releases" -Level "INFO" -LogFile $LogFile
        return $false
    }
}

# Install WSL
function Install-WSL {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    if (Test-Tool -Id "Microsoft.WSL" -Name "WSL" -Command "wsl" -LogFile $LogFile) {
        return $true
    }
    Write-Log -Message "Installing WSL (Windows Subsystem for Linux)..." -Level "INFO" -LogFile $LogFile
    try {
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
        wsl --install --no-distribution
        Write-Log -Message "WSL installed successfully" -Level "SUCCESS" -LogFile $LogFile
        Write-Log -Message "A reboot may be required for WSL to function properly" -Level "WARN" -LogFile $LogFile
        Write-Log -Message "Run 'wsl --install -d Ubuntu' after reboot to install Ubuntu" -Level "INFO" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to install WSL: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Detect available hardware (CPU/GPU/NPU) with prioritization
function Get-AvailableHardware {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    Write-Log -Message "Detecting available hardware..." -Level "INFO" -LogFile $LogFile
    $hardware = @{
        CPU           = @{Name = ""; Cores = 0; Architecture = "" }
        GPU           = @{Available = $false; Name = ""; VRAM = 0; Type = "None"; CUDACapable = $false }
        NPU           = @{Available = $false; Name = ""; Type = "None"; TOPS = 0 }
        Platform      = ""
        OptimalConfig = "CPU"
    }

    try {
        # CPU Detection
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $hardware.CPU.Name = $cpu.Name
        $hardware.CPU.Cores = $cpu.NumberOfLogicalProcessors
        $hardware.CPU.Architecture = $cpu.Architecture
        $hardware.Platform = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $cpu.Name -like "*Snapdragon*") { "ARM64" } else { "x64" }
        Write-Log -Message "CPU: $($hardware.CPU.Name) [$($hardware.CPU.Cores) logical cores]" -Level "SUCCESS" -LogFile $LogFile

        # NPU Detection
        $npus = @()
        if ($cpu.Name -like "*Snapdragon*" -and $cpu.Name -like "*X*") {
            $npus += [PSCustomObject]@{
                Name = "Qualcomm Hexagon NPU ($($cpu.Name))"
                Type = "Qualcomm_Hexagon"
                TOPS = 45
            }
        }
        elseif ($cpu.Name -like "*Core*Ultra*" -and ($cpu.Name -like "*125*" -or $cpu.Name -like "*155*" -or $cpu.Name -like "*165*")) {
            $npus += [PSCustomObject]@{
                Name = "Intel AI Boost NPU ($($cpu.Name))"
                Type = "Intel_AI_Boost"
                TOPS = 34
            }
        }

        if ($npus) {
            $hardware.NPU.Available = $true
            $hardware.NPU.Name = $npus[0].Name
            $hardware.NPU.Type = $npus[0].Type
            $hardware.NPU.TOPS = $npus[0].TOPS
            $hardware.OptimalConfig = if ($hardware.NPU.Type -eq "Qualcomm_Hexagon") { "Qualcomm_NPU" } else { "Intel_NPU" }
            Write-Log -Message "NPU: $($hardware.NPU.Name) ($($hardware.NPU.TOPS) TOPS)" -Level "SUCCESS" -LogFile $LogFile
        }
        else {
            Write-Log -Message "No NPU detected" -Level "INFO" -LogFile $LogFile
        }

        # GPU Detection
        $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notlike "*Microsoft Remote Display Adapter*" }
        if ($gpus) {
            $hardware.GPU.Available = $true
            $gpu = $gpus | Sort-Object -Property AdapterRAM -Descending | Select-Object -First 1
            $hardware.GPU.Name = $gpu.Name
            $hardware.GPU.VRAM = [math]::Round($gpu.AdapterRAM / 1GB, 2)
            
            if ($gpu.Name -match "NVIDIA|RTX|GTX") {
                $hardware.GPU.Type = "NVIDIA"
                $hardware.GPU.CUDACapable = Test-Command -Command "nvidia-smi" -LogFile $LogFile
                if (!$npus) { $hardware.OptimalConfig = "NVIDIA_GPU" }
            }
            elseif ($gpu.Name -match "AMD") {
                $hardware.GPU.Type = "AMD"
                if (!$npus) { $hardware.OptimalConfig = "AMD_GPU" }
            }
            elseif ($gpu.Name -match "Intel.*Arc") {
                $hardware.GPU.Type = "Intel_Arc"
                if (!$npus) { $hardware.OptimalConfig = "Intel_GPU" }
            }
            elseif ($gpu.Name -match "Qualcomm.*Adreno") {
                $hardware.GPU.Type = "Qualcomm_Adreno"
                if (!$npus) { $hardware.OptimalConfig = "Qualcomm_Adreno" }
            }
            Write-Log -Message "GPU: $($hardware.GPU.Name) ($($hardware.GPU.VRAM) GB, CUDA: $($hardware.GPU.CUDACapable))" -Level "SUCCESS" -LogFile $LogFile
        }
        else {
            Write-Log -Message "No GPU detected" -Level "INFO" -LogFile $LogFile
        }

        if (!$hardware.GPU.Available -and !$hardware.NPU.Available) {
            Write-Log -Message "No acceleration hardware detected, falling back to CPU" -Level "WARN" -LogFile $LogFile
        }

        Write-Log -Message "Platform: $($hardware.Platform), Optimal Config: $($hardware.OptimalConfig)" -Level "SUCCESS" -LogFile $LogFile
        return $hardware
    }
    catch {
        Write-Log -Message "Hardware detection failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        Write-Log -Message "Falling back to CPU: $($hardware.CPU.Name)" -Level "WARN" -LogFile $LogFile
        return $hardware
    }
}