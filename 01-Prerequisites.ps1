# 01-prerequisites.ps1 - Install all prerequisites for Jarvis AI Assistant
# Run as Administrator for best results

param(
    [switch]$SkipOptional,
    [switch]$DevOnly,
    [switch]$CheckOnly
)

function Write-Step($message) {
    Write-Host "🔧 $message" -ForegroundColor Green
}

function Write-Success($message) {
    Write-Host "✅ $message" -ForegroundColor Green
}

function Write-Warning($message) {
    Write-Host "⚠️  $message" -ForegroundColor Yellow
}

function Write-Error($message) {
    Write-Host "❌ $message" -ForegroundColor Red
}

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Winget {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Install-WingetIfNeeded {
    if (Test-Winget) {
        Write-Success "Winget is already installed"
        return $true
    }
    
    Write-Step "Installing Winget (Windows Package Manager)..."
    try {
        # Try to install via Microsoft Store
        Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" -Wait
        Write-Warning "Please install 'Windows Package Manager' from the Microsoft Store and re-run this script"
        return $false
    } catch {
        Write-Error "Failed to open Microsoft Store. Please install Winget manually."
        Write-Host "Download from: https://github.com/microsoft/winget-cli/releases" -ForegroundColor Cyan
        return $false
    }
}

function Test-PackageInstalled($packageId) {
    try {
        $result = winget list --id $packageId --exact 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Install-Package($packageId, $name, $optional = $false) {
    if (Test-PackageInstalled $packageId) {
        Write-Success "$name is already installed"
        return $true
    }
    
    if ($optional -and $SkipOptional) {
        Write-Warning "Skipping optional package: $name"
        return $true
    }
    
    Write-Step "Installing $name..."
    try {
        winget install --id $packageId --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$name installed successfully"
            return $true
        } else {
            Write-Error "Failed to install $name (Exit code: $LASTEXITCODE)"
            return $false
        }
    } catch {
        Write-Error "Failed to install $name : $_"
        return $false
    }
}

function Install-PythonPackages {
    Write-Step "Installing Python packages..."
    
    $packages = @(
        "pip",
        "virtualenv",
        "pipenv"
    )
    
    try {
        # Upgrade pip first
        python -m pip install --upgrade pip
        
        foreach ($package in $packages) {
            Write-Host "  Installing $package..." -ForegroundColor Cyan
            python -m pip install $package
        }
        
        Write-Success "Python packages installed"
        return $true
    } catch {
        Write-Error "Failed to install Python packages: $_"
        return $false
    }
}

function Test-WSL {
    try {
        $wslStatus = wsl --status 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Install-WSL {
    if (Test-WSL) {
        Write-Success "WSL is already installed"
        return $true
    }
    
    Write-Step "Installing WSL (Windows Subsystem for Linux)..."
    try {
        # Enable WSL feature
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
        
        # Install WSL
        wsl --install --no-distribution
        
        Write-Warning "WSL installed. A reboot may be required."
        Write-Host "Run 'wsl --install -d Ubuntu' after reboot to install Ubuntu." -ForegroundColor Cyan
        return $true
    } catch {
        Write-Error "Failed to install WSL: $_"
        return $false
    }
}

function Show-InstallationSummary($results) {
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "📋 Installation Summary" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    $successful = 0
    $failed = 0
    
    foreach ($result in $results) {
        if ($result.Success) {
            Write-Host "✅ $($result.Name)" -ForegroundColor Green
            $successful++
        } else {
            Write-Host "❌ $($result.Name)" -ForegroundColor Red
            $failed++
        }
    }
    
    Write-Host "`nTotal: $successful successful, $failed failed" -ForegroundColor Cyan
    
    if ($failed -gt 0) {
        Write-Host "`n⚠️  Some installations failed. You may need to:" -ForegroundColor Yellow
        Write-Host "  - Run as Administrator" -ForegroundColor White
        Write-Host "  - Check your internet connection" -ForegroundColor White
        Write-Host "  - Manually install failed packages" -ForegroundColor White
    }
}

function Test-Prerequisites {
    Write-Step "Checking current system state..."
    
    $tools = @(
        @{Id="Git.Git"; Name="Git"; Command="git"},
        @{Id="Python.Python.3.11"; Name="Python 3.11"; Command="python"},
        @{Id="OpenJS.NodeJS"; Name="Node.js"; Command="node"},
        @{Id="Docker.DockerDesktop"; Name="Docker Desktop"; Command="docker"},
        @{Id="Microsoft.AzureCLI"; Name="Azure CLI"; Command="az"},
        @{Id="Ollama.Ollama"; Name="Ollama"; Command="ollama"},
        @{Id="Microsoft.VisualStudioCode"; Name="VS Code"; Command="code"}
    )
    
    foreach ($tool in $tools) {
        $installed = Test-PackageInstalled $tool.Id
        $inPath = Get-Command $tool.Command -ErrorAction SilentlyContinue
        
        if ($installed -or $inPath) {
            Write-Success "$($tool.Name) is installed"
        } else {
            Write-Warning "$($tool.Name) is NOT installed"
        }
    }
}

# Main installation function
function Install-Prerequisites {
    $results = @()
    
    Write-Host "🚀 Installing Jarvis AI Assistant Prerequisites" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    # Check if running as admin
    if (-not (Test-IsAdmin)) {
        Write-Warning "Not running as Administrator. Some installations may fail."
        Write-Host "Consider running: Start-Process PowerShell -Verb RunAs" -ForegroundColor Cyan
    }
    
    # Essential Development Tools
    Write-Host "`n📦 Essential Development Tools" -ForegroundColor Yellow
    
    $results += @{Name="Git"; Success=(Install-Package "Git.Git" "Git")}
    $results += @{Name="Python 3.11"; Success=(Install-Package "Python.Python.3.11" "Python 3.11")}
    $results += @{Name="Node.js"; Success=(Install-Package "OpenJS.NodeJS" "Node.js")}
    $results += @{Name="Visual Studio Code"; Success=(Install-Package "Microsoft.VisualStudioCode" "Visual Studio Code")}
    
    # Containerization & Cloud
    Write-Host "`n🐳 Containerization & Cloud Tools" -ForegroundColor Yellow
    
    $results += @{Name="Docker Desktop"; Success=(Install-Package "Docker.DockerDesktop" "Docker Desktop")}
    $results += @{Name="Azure CLI"; Success=(Install-Package "Microsoft.AzureCLI" "Azure CLI")}
    
    # AI & ML Tools
    Write-Host "`n🤖 AI & ML Tools" -ForegroundColor Yellow
    
    $results += @{Name="Ollama"; Success=(Install-Package "Ollama.Ollama" "Ollama")}
    
    # Development Tools
    if (-not $DevOnly) {
        Write-Host "`n🛠️  Additional Development Tools" -ForegroundColor Yellow
        
        $results += @{Name="Windows Terminal"; Success=(Install-Package "Microsoft.WindowsTerminal" "Windows Terminal" $true)}
        $results += @{Name="PowerShell 7"; Success=(Install-Package "Microsoft.PowerShell" "PowerShell 7" $true)}
        $results += @{Name="GitHub CLI"; Success=(Install-Package "GitHub.cli" "GitHub CLI" $true)}
        $results += @{Name="Terraform"; Success=(Install-Package "Hashicorp.Terraform" "Terraform" $true)}
        $results += @{Name="Postman"; Success=(Install-Package "Postman.Postman" "Postman" $true)}
    }
    
    # WSL Setup
    if (-not $DevOnly) {
        Write-Host "`n🐧 Linux Subsystem" -ForegroundColor Yellow
        $results += @{Name="WSL"; Success=(Install-WSL)}
    }
    
    # Python packages
    Write-Host "`n🐍 Python Environment" -ForegroundColor Yellow
    $results += @{Name="Python Packages"; Success=(Install-PythonPackages)}
    
    # VS Code Extensions
    Write-Host "`n📝 VS Code Extensions" -ForegroundColor Yellow
    $extensions = @(
        "ms-python.python",
        "ms-vscode.vscode-typescript-next", 
        "bradlc.vscode-tailwindcss",
        "ms-vscode.vscode-docker",
        "hashicorp.terraform",
        "ms-vscode.azure-account"
    )
    
    foreach ($ext in $extensions) {
        try {
            code --install-extension $ext --force 2>$null
        } catch {
            # Extensions are optional
        }
    }
    $results += @{Name="VS Code Extensions"; Success=$true}
    
    # Show summary
    Show-InstallationSummary $results
    
    # Next steps
    Write-Host "`n🎯 Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Restart your terminal to refresh PATH" -ForegroundColor White
    Write-Host "2. Run: docker version  (to verify Docker)" -ForegroundColor White
    Write-Host "3. Run: python --version  (to verify Python)" -ForegroundColor White
    Write-Host "4. Run: node --version  (to verify Node.js)" -ForegroundColor White
    Write-Host "5. Run: git --version  (to verify Git)" -ForegroundColor White
    Write-Host "6. Configure Git:" -ForegroundColor White
    Write-Host "   git config --global user.name 'Your Name'" -ForegroundColor Gray
    Write-Host "   git config --global user.email 'your.email@example.com'" -ForegroundColor Gray
    Write-Host "7. Login to Azure: az login" -ForegroundColor White
    Write-Host "8. Run your project setup script" -ForegroundColor White
    
    if (-not $DevOnly) {
        Write-Host "`n💡 Optional:" -ForegroundColor Cyan
        Write-Host "- Restart your computer if Docker or WSL were installed" -ForegroundColor White
        Write-Host "- Install Ubuntu in WSL: wsl --install -d Ubuntu" -ForegroundColor White
    }
}

# Main execution
if (-not (Test-Winget)) {
    if (-not (Install-WingetIfNeeded)) {
        Write-Error "Winget is required but not available. Exiting."
        exit 1
    }
}

if ($CheckOnly) {
    Test-Prerequisites
} else {
    Install-Prerequisites
}

# Always show comprehensive validation regardless of parameters
Write-Host ""
Write-Host "🔍 System Validation - Current Tool Status:" -ForegroundColor Cyan
Write-Host "-" * 60 -ForegroundColor Gray

$validationResults = @()

# Core development tools with version checking
$coreTools = @(
    @{Name="Git"; Command="git"; Package="Git.Git"; VersionFlag="--version"},
    @{Name="Python"; Command="python"; Package="Python.Python.3.11"; VersionFlag="--version"},
    @{Name="Node.js"; Command="node"; Package="OpenJS.NodeJS"; VersionFlag="--version"},
    @{Name="VS Code"; Command="code"; Package="Microsoft.VisualStudioCode"; VersionFlag="--version"}
)

foreach ($tool in $coreTools) {
    try {
        $command = Get-Command $tool.Command -ErrorAction SilentlyContinue
        if ($command) {
            try {
                $version = & $tool.Command $tool.VersionFlag 2>$null | Select-Object -First 1
                $path = $command.Source
                $validationResults += "✅ Tool: $($tool.Name) ($path) - $version"
            } catch {
                $validationResults += "✅ Tool: $($tool.Name) - installed (version check failed)"
            }
        } else {
            $packageCheck = Test-PackageInstalled $tool.Package
            if ($packageCheck) {
                $validationResults += "⚠️  Tool: $($tool.Name) - installed via winget but not in PATH"
            } else {
                $validationResults += "❌ Tool: $($tool.Name) - not installed"
            }
        }
    } catch {
        $validationResults += "❌ Tool: $($tool.Name) - error checking status"
    }
}

# Container and cloud tools
$cloudTools = @(
    @{Name="Docker Desktop"; Command="docker"; Package="Docker.DockerDesktop"},
    @{Name="Azure CLI"; Command="az"; Package="Microsoft.AzureCLI"},
    @{Name="Ollama"; Command="ollama"; Package="Ollama.Ollama"}
)

foreach ($tool in $cloudTools) {
    try {
        $command = Get-Command $tool.Command -ErrorAction SilentlyContinue
        if ($command) {
            # Special check for Docker to see if it's running
            if ($tool.Name -eq "Docker Desktop") {
                try {
                    $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
                    if ($dockerVersion) {
                        $validationResults += "✅ Tool: $($tool.Name) - running (v$dockerVersion)"
                    } else {
                        $validationResults += "⚠️  Tool: $($tool.Name) - installed but not running"
                    }
                } catch {
                    $validationResults += "⚠️  Tool: $($tool.Name) - installed but status unknown"
                }
            } else {
                $validationResults += "✅ Tool: $($tool.Name) - installed"
            }
        } else {
            $validationResults += "❌ Tool: $($tool.Name) - not installed or not in PATH"
        }
    } catch {
        $validationResults += "❌ Tool: $($tool.Name) - error checking status"
    }
}

# System features
try {
    $wslStatus = wsl --status 2>$null
    if ($LASTEXITCODE -eq 0) {
        $validationResults += "✅ Feature: WSL - installed and configured"
    } else {
        $validationResults += "❌ Feature: WSL - not installed or not configured"
    }
} catch {
    $validationResults += "❌ Feature: WSL - not available"
}

# Winget validation
if (Test-Winget) {
    try {
        $wingetVersion = winget --version 2>$null
        $validationResults += "✅ Package Manager: Winget - $wingetVersion"
    } catch {
        $validationResults += "✅ Package Manager: Winget - installed (version check failed)"
    }
} else {
    $validationResults += "❌ Package Manager: Winget - not available"
}

# Display results
foreach ($result in $validationResults) {
    Write-Host $result
}

# Summary
$successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
$warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
$failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
$totalChecks = $validationResults.Count

Write-Host ""
if ($failureCount -eq 0 -and $warningCount -eq 0) {
    Write-Host "🎉 System Validation Complete: $successCount/$totalChecks tools ready!" -ForegroundColor Green
    Write-Host "✅ Development environment fully configured" -ForegroundColor Green
} elseif ($failureCount -eq 0) {
    Write-Host "⚠️  System Validation: $successCount/$totalChecks ready, $warningCount warnings" -ForegroundColor Yellow
    Write-Host "✅ Core development tools available, some minor issues" -ForegroundColor Green
} else {
    Write-Host "❗ System Validation: $successCount/$totalChecks ready, $failureCount missing, $warningCount warnings" -ForegroundColor Red
    Write-Host "❌ Some essential tools need installation" -ForegroundColor Red
}

# Quick verification commands
if ($successCount -gt 0) {
    Write-Host ""
    Write-Host "🚀 Quick Verification Commands:" -ForegroundColor Cyan
    Write-Host "# Test core tools:" -ForegroundColor Gray
    Write-Host "python --version && node --version && git --version" -ForegroundColor White
    if ($validationResults | Where-Object { $_ -like "*Docker*running*" }) {
        Write-Host "docker version" -ForegroundColor White
    }
    if ($validationResults | Where-Object { $_ -like "*Azure CLI*" }) {
        Write-Host "az --version" -ForegroundColor White
    }
    if ($validationResults | Where-Object { $_ -like "*Ollama*" }) {
        Write-Host "ollama --version" -ForegroundColor White
    }
}

# Installation recommendations
if ($failureCount -gt 0) {
    Write-Host ""
    Write-Host "💡 Installation Recommendations:" -ForegroundColor Yellow
    $missingTools = $validationResults | Where-Object { $_ -like "❌*" }
    foreach ($missing in $missingTools) {
        $toolName = ($missing -split ":")[1].Trim().Split(" ")[0]
        Write-Host "   winget install $toolName" -ForegroundColor Gray
    }
}

Write-Host "`n🎉 Prerequisites setup completed!" -ForegroundColor Green
Write-Host "You're ready to build your Jarvis AI Assistant!" -ForegroundColor Green