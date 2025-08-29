# Common-Utils.ps1 - Shared utilities for JARVIS AI Assistant scripts
# Purpose: Contains logging, Python package management, tool checks, and hardware detection
# Last edit: 2025-07-25 - Removed unused functions

$scriptVersion = "6.0.0"
$JARVIS_APP_VERSION = "2.3.0" # Centralized application version

# Global Ollama Model Configuration - Change this variable to switch models globally
$JARVIS_DEFAULT_MODEL = "phi3:mini"         # JARVIS System Development
# $JARVIS_CHAT_MODEL    = "gemma2:2b"         # Chat Tasks? Future State
# $JARVIS_VOICE_MODEL   = "llama3:8b"         # Conversation Model? Future State
# $JARVIS_SUMMARY_MODEL = "llama4:scout"      # Summary Tasks? Future State
# $JARVIS_CODING_MODEL  = "qwen2.5-coder:7b"  # Code Dev Tasks? Future State

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
    $color = if ($colorMap[$Level]) { $colorMap[$Level] } else { "White" }
    Write-Host $logEntry -ForegroundColor $color
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
}

# Capture command output to transcript for enhanced debugging
function Write-CommandOutput {
    param(
        [Parameter(Mandatory = $true)] [string]$Command,
        [string]$Output = "",
        [Parameter(Mandatory = $true)] [string]$TranscriptFile
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [STDOUT] $Command"
    if (-not [string]::IsNullOrWhiteSpace($Output)) {
        $entry += "`n$Output"
    }
    Add-Content -Path $TranscriptFile -Value $entry -ErrorAction SilentlyContinue
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
        Write-Log -Message "Python package $PackageName $(if ($installed) { 'found' } else { 'not found' })" -Level $(if ($installed) { "SUCCESS" } else { "WARN" }) -LogFile $LogFile
        return $installed
    }
    catch {
        Write-Log -Message "Error checking package $PackageName $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
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
        Write-Log -Message "Failed to install $PackageName $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Get current Ollama model (reads .env, falls back to global variable)
function Get-JarvisModel {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Getting Jarvis model configuration..." -Level "INFO" -LogFile $LogFile
    $envPath = Join-Path -Path (Get-Location) -ChildPath ".env"
    if (Test-Path $envPath) {
        try {
            $envContent = Get-Content $envPath -ErrorAction Stop
            $modelMatch = $envContent | Where-Object { $_ -match "^OLLAMA_MODEL\s*=\s*['`"]?([^'`"\s]+)['`"]?" } | Select-Object -First 1
            if ($modelMatch -and $matches[1]) {
                Write-Log -Message "Using model from .env: $($matches[1])" -Level "SUCCESS" -LogFile $LogFile
                return $matches[1]
            }
        }
        catch { Write-Log -Message "Error reading .env: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile }
    }
    Write-Log -Message "Using default model: $JARVIS_DEFAULT_MODEL" -Level "INFO" -LogFile $LogFile
    return $JARVIS_DEFAULT_MODEL
}

# Ensure correct Ollama model is installed (replaces existing model installation logic)
function Sync-JarvisModel {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    $targetModel = Get-JarvisModel -LogFile $LogFile
    Write-Log -Message "Synchronizing Ollama model: $targetModel" -Level "INFO" -LogFile $LogFile
    try {
        if (-not ($installedModels -match [regex]::Escape($targetModel))) {
            Write-Log -Message "Installing model: $targetModel" -Level "INFO" -LogFile $LogFile
            $pullResult = ollama pull $targetModel 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Message "Model $targetModel installed successfully" -Level "SUCCESS" -LogFile $LogFile
            }
            else {
                Write-Log -Message "Failed to install ${targetModel}: $pullResult" -Level "ERROR" -LogFile $LogFile
                return $false
            }
        }
        else { Write-Log -Message "Model $targetModel already installed" -Level "SUCCESS" -LogFile $LogFile }
        return $targetModel
    }
    catch {
        Write-Log -Message "Error syncing model: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return $false
    }
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
            Write-Log -Message "$Name found: $(if ($version) { $version } else { 'version unknown' })" -Level "SUCCESS" -LogFile $LogFile
            return $true
        }
        try {
            $wingetResult = winget list --id $Id --exact 2>&1
            if ($LASTEXITCODE -eq 0 -and $wingetResult -notlike "*No installed package found*") {
                Write-Log -Message "$Name installed but not in PATH" -Level "WARN" -LogFile $LogFile
                return $true
            }
        }
        catch { Write-Log -Message "Winget check failed for $($Name): $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile }
        Write-Log -Message "$Name not installed" -Level "ERROR" -LogFile $LogFile
        return $false
    }
    catch {
        Write-Log -Message "Error checking $($Name): $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
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
OLLAMA_MODEL=$JARVIS_DEFAULT_MODEL
ENVIRONMENT=development
DEBUG=true
LOG_LEVEL=DEBUG
API_HOST=0.0.0.0
API_PORT=8000
SECRET_KEY=dev_secret_key_$(Get-Random)
"@
        try {
            Set-Content -Path $envPath -Value $defaultContent -ErrorAction Stop
            Write-Log -Message ".env created with default OLLAMA_MODEL=$JARVIS_DEFAULT_MODEL" -Level "SUCCESS" -LogFile $LogFile
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
            Add-Content -Path $envPath -Value "OLLAMA_MODEL=$JARVIS_DEFAULT_MODEL" -ErrorAction Stop
            Write-Log -Message "Added OLLAMA_MODEL=$JARVIS_DEFAULT_MODEL to .env" -Level "SUCCESS" -LogFile $LogFile
        }
        else { Write-Log -Message "OLLAMA_MODEL already defined in .env" -Level "SUCCESS" -LogFile $LogFile }
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
        [Parameter(Mandatory = $true)] [string]$LogFile
    )
    Write-Log -Message "Running system checks..." -Level "INFO" -LogFile $LogFile
    $results = @()
    $tools = @(
        @{Id = "Python.Python.3.12"; Name = "Python 3.12"; Command = "python" },
        @{Id = "OpenJS.NodeJS"; Name = "Node.js"; Command = "node" },
        @{Id = "Ollama.Ollama"; Name = "Ollama"; Command = "ollama" }
    )
    foreach ($tool in $tools) {
        $status = Test-Tool -Id $tool.Id -Name $tool.Name -Command $tool.Command -LogFile $LogFile
        $results += "$(if ($status) { '✅' } else { '❌' }) $($tool.Name)"
    }
    $wslStatus = Test-Tool -Id "Microsoft.WSL" -Name "WSL" -Command "wsl" -LogFile $LogFile
    $results += "$(if ($wslStatus) { '✅' } else { '❌' }) WSL"
    Write-Log -Message "=== VALIDATION RESULTS ===" -Level "INFO" -LogFile $LogFile
    foreach ($result in $results) {
        Write-Log -Message $result -Level $(if ($result -like "✅*") { "SUCCESS" } else { "ERROR" }) -LogFile $LogFile
    }
    $successCount = ($results | Where-Object { $_ -like "✅*" }).Count
    Write-Log -Message "Validation: $successCount/$($results.Count) tools ready" -Level $(if ($successCount -eq $results.Count) { "SUCCESS" } else { "ERROR" }) -LogFile $LogFile
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
                Write-Log -Message "Failed to create directory $dir $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
            }
        }
        else {
            Write-Log -Message "Directory exists: $dir" -Level "INFO" -LogFile $LogFile
        }
    }
    Write-Log -Message "Directory creation complete: $created created" -Level "SUCCESS" -LogFile $LogFile
    return $true
}

# Install and verify Ollama with model downloading
function Install-OllamaAndModels {
    param(
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [string[]]$EssentialModels = @($JARVIS_DEFAULT_MODEL)
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
            Write-Log -Message "Could not verify/download $model $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
            Write-Log -Message "Run manually: ollama pull $model" -Level "INFO" -LogFile $LogFile
        }
    }
    return $true
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
            if ($gpu.Name -match "NVIDIA|RTX|GTX") {
                $hardware.GPU.Type = "NVIDIA"
                $hardware.GPU.CUDACapable = Test-Command -Command "nvidia-smi" -LogFile $LogFile
                if ($hardware.GPU.CUDACapable) {
                    try {
                        $nvidiaSmiOutput = (nvidia-smi --query-gpu=memory.total --format=noheader)
                        $vramMiB = [int]$nvidiaSmiOutput.Trim(' MiB')
                        $hardware.GPU.VRAM = [math]::Round($vramMiB / 1024, 2)
                        Write-Log -Message "NVIDIA VRAM detected via nvidia-smi: $($hardware.GPU.VRAM) GB" -Level "INFO" -LogFile $LogFile
                    }
                    catch {
                        Write-Log -Message "Failed to get NVIDIA VRAM from nvidia-smi: $($_.Exception.Message)" -Level "WARN" -LogFile $LogFile
                        $hardware.GPU.VRAM = [math]::Round($gpu.AdapterRAM / 1GB, 2)
                    }
                }
                else {
                    $hardware.GPU.VRAM = [math]::Round($gpu.AdapterRAM / 1GB, 2)
                    Write-Log -Message "NVIDIA VRAM detected via Win32_VideoController (nvidia-smi not found): $($hardware.GPU.VRAM) GB" -Level "WARN" -LogFile $LogFile
                }
                if (!$hardware.NPU.Available) { $hardware.OptimalConfig = "NVIDIA_GPU" }
            }
            elseif ($gpu.Name -match "AMD") {
                $hardware.GPU.Type = "AMD"
                if (!$hardware.NPU.Available) { $hardware.OptimalConfig = "AMD_GPU" }
            }
            elseif ($gpu.Name -match "Intel.*Arc") {
                $hardware.GPU.Type = "Intel_Arc"
                if (!$hardware.NPU.Available) { $hardware.OptimalConfig = "Intel_GPU" }
            }
            elseif ($gpu.Name -match "Qualcomm.*Adreno") {
                $hardware.GPU.Type = "Qualcomm_Adreno"
                if (!$hardware.NPU.Available) { $hardware.OptimalConfig = "Qualcomm_Adreno" }
            }
            else {
                # Unknown GPU - Enhanced detection for unrecognized hardware
                $hardware.GPU.Type = "Unknown"
                $hardware.GPU.DeviceID = if ($gpu.PNPDeviceID) { $gpu.PNPDeviceID } else { "N/A" }
                $hardware.GPU.Vendor = if ($gpu.Name) { ($gpu.Name -split ' ')[0] } else { "Unknown Vendor" }
                $hardware.GPU.Model = if ($gpu.Name) { $gpu.Name } else { "Unrecognized GPU" }
                # Estimate VRAM if not detected properly
                if ($hardware.GPU.VRAM -eq 0) {
                    $hardware.GPU.VRAM = [Math]::Min(($hardware.CPU.Cores * 0.5), 8)  # Conservative estimate
                }
                if (!$hardware.NPU.Available) { 
                    $hardware.OptimalConfig = if ($hardware.GPU.VRAM -ge 4) { "Unknown_GPU_Accelerated" } else { "Unknown_GPU_Conservative" }
                }
                Write-Log -Message "Unknown GPU detected: $($hardware.GPU.Name) (DeviceID: $($hardware.GPU.DeviceID))" -Level "WARN" -LogFile $LogFile
            }
            Write-Log -Message "GPU: $($hardware.GPU.Name) ($($hardware.GPU.VRAM) GB, CUDA: $($hardware.GPU.CUDACapable))" -Level "SUCCESS" -LogFile $LogFile
        }
        else {
            Write-Log -Message "No GPU detected" -Level "INFO" -LogFile $LogFile
        }
        # Enhanced NPU/AI accelerator detection for unknown hardware
        if (!$hardware.NPU.Available) {
            $aiDevices = Get-CimInstance Win32_PnPEntity | Where-Object { 
                $_.Name -match "NPU|Neural.*Processing|AI.*Accelerator|Hexagon.*NPU|VPU|Inference.*Engine" -and 
                $_.Status -eq "OK" -and 
                $_.Name -notlike "*Audio*" -and
                $_.Name -notlike "*USB*Input*" -and
                $_.Name -notlike "*Human*Interface*" -and
                $_.Name -notlike "*Mouse*" -and
                $_.Name -notlike "*Keyboard*" -and
                $_.PNPDeviceID -notlike "USB\*" -and
                $_.PNPDeviceID -notlike "HID\*"
            }
            if ($aiDevices) {
                $aiDevice = $aiDevices | Select-Object -First 1
                $hardware.NPU.Available = $true
                $hardware.NPU.Name = "Unknown NPU/AI Accelerator ($($aiDevice.Name))"
                $hardware.NPU.Type = "Unknown_NPU"
                $hardware.NPU.TOPS = 10  # Conservative estimate
                $hardware.NPU.DeviceID = if ($aiDevice.PNPDeviceID) { $aiDevice.PNPDeviceID } else { "N/A" }
                # Only override OptimalConfig if no known NPU was already detected
                if ($hardware.OptimalConfig -notmatch "NPU$") {
                    $hardware.OptimalConfig = "Unknown_NPU"
                }
                Write-Log -Message "Unknown NPU/AI accelerator detected: $($aiDevice.Name) (DeviceID: $($hardware.NPU.DeviceID))" -Level "WARN" -LogFile $LogFile
            }
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

# Generate optimal configuration using Ollama environment variables
function Get-OptimalConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Hardware
    )
    $config = @{ 
        EnvironmentVars      = @{}
        Instructions         = @()
        ModelRecommendations = @()
    }
    # Determine primary hardware type for optimization
    $primaryType = $Hardware.OptimalConfig
    $cores = $Hardware.CPU.Cores
    $vram = if ($Hardware.GPU.Available) { $Hardware.GPU.VRAM } else { 0 }
    $tops = if ($Hardware.NPU.Available) { $Hardware.NPU.TOPS } else { 0 }
    switch -Wildcard ($primaryType) {
        "*NPU*" {
            # NPU optimization - Using generic settings since NPU env vars are non-standard
            $config.EnvironmentVars = @{
                "OLLAMA_NUM_PARALLEL"      = "2"
                "OLLAMA_MAX_LOADED_MODELS" = "1"
                "OLLAMA_MAX_QUEUE"         = "64"
            }
            $config.Instructions += "NPU optimization applied ($($tops) TOPS)"
            $config.Instructions += "Note: Using conservative CPU settings as NPU environment variables are hardware-specific"
            $config.ModelRecommendations += @("phi3:mini", "gemma2:2b")
        }
        "NVIDIA_GPU" {
            if ($Hardware.GPU.CUDACapable) {
                # NVIDIA with CUDA environment variables
                $config.EnvironmentVars = @{
                    "CUDA_VISIBLE_DEVICES"     = "0"
                    "OLLAMA_FLASH_ATTENTION"   = "1"
                    "OLLAMA_NUM_PARALLEL"      = if ($vram -ge 12) { "4" } elseif ($vram -ge 8) { "2" } else { "1" }
                    "OLLAMA_MAX_LOADED_MODELS" = "1"
                    "OLLAMA_MAX_QUEUE"         = "128"
                }
                $config.Instructions += "NVIDIA GPU with CUDA acceleration enabled ($($vram) GB VRAM)"
                $config.Instructions += "CUDA Driver: Detected (nvidia-smi available)"
                $config.Instructions += "Ollama will auto-detect CUDA and manage GPU memory"
                $config.ModelRecommendations += if ($vram -ge 24) { @("llama3.1:70b", "codellama:34b", "mixtral:8x7b") }
                elseif ($vram -ge 16) { @("llama3.1:13b", "codellama:13b", "llama3.1:8b") }
                elseif ($vram -ge 8) { @("llama3.1:8b", "codellama:7b", "gemma2:9b") }
                else { @("phi3:mini", "gemma2:2b", "llama3.2:3b") }
            }
            else {
                # NVIDIA without CUDA environment variables
                $config.EnvironmentVars = @{
                    "OLLAMA_NUM_PARALLEL"      = "2"
                    "OLLAMA_MAX_LOADED_MODELS" = "1"
                }
                $config.Instructions += "NVIDIA GPU detected without CUDA ($($vram) GB VRAM)"
                $config.Instructions += "CUDA Driver: Not detected (nvidia-smi not found)"
                $config.Instructions += "PERFORMANCE IMPROVEMENT AVAILABLE:"
                $config.Instructions += "Install CUDA Toolkit for GPU acceleration"
                $config.Instructions += "Download: https://developer.nvidia.com/cuda-downloads"
                $config.ModelRecommendations += @("phi3:mini", "gemma2:2b")
            }
        }
        { $_ -match "AMD" } {
            # AMD GPU environment variables
            $config.EnvironmentVars = @{ "OLLAMA_NUM_PARALLEL" = "2" }
            # Set ROCm environment variables if needed
            $config.Instructions += "AMD GPU detected ($($vram) GB VRAM)"
            $config.Instructions += "Note: Use HIP_VISIBLE_DEVICES or ROCR_VISIBLE_DEVICES for GPU selection if needed"
            $config.Instructions += "Ollama will attempt ROCm acceleration if available"
            $config.ModelRecommendations += if ($vram -ge 8) { @("llama3.1:8b", "gemma2") } else { @("phi3:mini", "gemma2:2b") }
        }
        { $_ -match "Intel" } {
            # Intel Arc GPU environment variables
            $config.EnvironmentVars = @{ "OLLAMA_NUM_PARALLEL" = "1" }
            $config.Instructions += "Intel Arc GPU detected ($($vram) GB VRAM)"
            $config.Instructions += "Note: Limited Ollama support, using CPU fallback with conservative settings"
            $config.ModelRecommendations += @("phi3:mini", "gemma2:2b")
        }
        { $_ -match "Unknown.*GPU" } {
            # Unknown GPU environment variables
            $config.EnvironmentVars = @{
                "OLLAMA_NUM_PARALLEL"      = if ($vram -ge 8) { "2" } else { "1" }
                "OLLAMA_MAX_LOADED_MODELS" = "1"
                "OLLAMA_MAX_QUEUE"         = if ($vram -ge 8) { "128" } else { "64" }
            }
            $config.Instructions += "Unknown GPU detected ($($vram) GB VRAM)"
            $config.Instructions += "Using conservative CPU settings with GPU detection fallback"
            $config.Instructions += "Device: $($Hardware.GPU.Name)"
            $config.ModelRecommendations += if ($vram -ge 8) { @("llama3.2:7b", "phi3:mini") } else { @("phi3:mini", "gemma2:2b") }
        }
        default {
            # CPU optimization - Basic valid settings
            $threads = [Math]::Min($cores, 8)  # Conservative thread count
            $config.EnvironmentVars = @{
                "OLLAMA_NUM_PARALLEL"      = $threads.ToString()
                "OLLAMA_MAX_LOADED_MODELS" = "1"
            }
            $config.Instructions += "CPU optimization applied with $threads threads"
            $config.ModelRecommendations += @("phi3:mini", "gemma2:2b")
        }
    }
    # Add platform-specific optimizations if needed
    if ($Hardware.Platform -eq "ARM64") {
        $config.Instructions += "ARM64 platform detected - using ARM-optimized settings"
    }
    return $config
}

function Stop-OllamaService {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Stopping Ollama service..." -Level INFO -LogFile $LogFile
    try {
        Get-Process -Name "ollama" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Write-Log -Message "Ollama service stopped" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Error stopping Ollama service: $($_.Exception.Message)" -Level WARN -LogFile $LogFile
        return $false
    }
}

function Test-OllamaService {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing Ollama service availability..." -Level INFO -LogFile $LogFile
    try {
        # Test if Ollama service is running
        if (Test-OllamaRunning -LogFile $LogFile) {
            Write-Log -Message "Ollama service is running and accessible" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Ollama service is not running" -Level INFO -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error testing Ollama service: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Start-OllamaService {
    param( 
        [Parameter(Mandatory = $true)] [string]$LogFile,
        [switch]$ForceRestart
    )
    Write-Log -Message "Starting Ollama service..." -Level INFO -LogFile $LogFile
    if ($ForceRestart -and (Test-OllamaService -LogFile $LogFile)) {
        Write-Log -Message "Force restart requested - stopping existing service" -Level INFO -LogFile $LogFile
        Stop-OllamaService -LogFile $LogFile
    }
    if (Test-OllamaService -LogFile $LogFile) {
        Write-Log -Message "Ollama service already running - no action needed" -Level INFO -LogFile $LogFile
        return $true
    }
    try {
        Write-Log -Message "Attempting to start Ollama service..." -Level INFO -LogFile $LogFile
        $ollamaProcess = Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -PassThru -ErrorAction Stop
        # Wait for service to start
        $attempts = 0
        $maxAttempts = 15
        while (-not (Test-OllamaService -LogFile $LogFile) -and $attempts -lt $maxAttempts) {
            Start-Sleep -Seconds 2
            $attempts++
            Write-Log -Message "Waiting for Ollama service to start (attempt $attempts/$maxAttempts)..." -Level INFO -LogFile $LogFile
        }
        if (Test-OllamaService -LogFile $LogFile) {
            Write-Log -Message "Ollama service started successfully (PID: $($ollamaProcess.Id))" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Ollama service failed to start within timeout" -Level ERROR -LogFile $LogFile
            Write-Log -Message "REMEDIATION: Try running 'ollama serve' manually to check for errors" -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Error starting Ollama service: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Write-Log -Message "REMEDIATION: Ensure Ollama is properly installed and try manual startup" -Level ERROR -LogFile $LogFile
        return $false
    }
}