# 04-OllamaSetupAndTesting.ps1 - Setup Ollama service and verify AI integration
# Handles Ollama installation, model setup, and backend integration testing

param(
    [switch]$Setup,
    [switch]$Test,
    [switch]$StartBackend,
    [switch]$All
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

function Test-OllamaInstalled {
    try {
        $null = Get-Command ollama -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-OllamaRunning {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5
        return $true
    } catch {
        return $false
    }
}

function Test-BackendExists {
    return (Test-Path "backend/api/main.py") -and (Test-Path "backend/services/ai_service.py")
}

function Setup-OllamaService {
    Write-Step "Setting up Ollama service..."
    
    # Check if Ollama is installed
    if (-not (Test-OllamaInstalled)) {
        Write-Error "Ollama not found. Please run .\01-prerequisites.ps1 first to install it."
        return $false
    }
    
    Write-Success "Ollama is installed"
    
    # Check if Ollama is already running
    if (Test-OllamaRunning) {
        Write-Success "Ollama service is already running"
    } else {
        Write-Step "Starting Ollama service..."
        Write-Host "🚀 Starting Ollama service (this will run in background)..." -ForegroundColor Yellow
        
        # Start Ollama service in background
        Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
        
        # Wait for service to start
        Write-Host "⏱️  Waiting for Ollama service to start..." -ForegroundColor Yellow
        $attempts = 0
        while (-not (Test-OllamaRunning) -and $attempts -lt 15) {
            Start-Sleep -Seconds 2
            $attempts++
            Write-Host "." -NoNewline -ForegroundColor Gray
        }
        Write-Host ""
        
        if (Test-OllamaRunning) {
            Write-Success "Ollama service started successfully"
        } else {
            Write-Error "Failed to start Ollama service"
            return $false
        }
    }
    
    return $true
}

function Install-RecommendedModel {
    Write-Step "Installing recommended AI model..."
    
    # Check current models
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 10
        $models = $response.models
        
        # Check if llama3.1:8b is already installed
        $hasLlama31 = $models | Where-Object { $_.name -like "*llama3.1*8b*" -or $_.name -eq "llama3.1:8b" }
        
        if ($hasLlama31) {
            Write-Success "Llama 3.1:8b model already installed"
            return $true
        }
        
        Write-Host "📦 Installing llama3.1:8b model (this may take 5-10 minutes)..." -ForegroundColor Yellow
        Write-Host "💡 This model is ~4.7GB - ensure good internet connection" -ForegroundColor Cyan
        
        # Pull the model
        & ollama pull llama3.1:8b
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Llama 3.1:8b model installed successfully"
            return $true
        } else {
            Write-Error "Failed to install model"
            return $false
        }
        
    } catch {
        Write-Error "Could not check or install models: $_"
        return $false
    }
}

function Test-OllamaStandalone {
    Write-Step "Testing Ollama standalone functionality..."
    
    if (-not (Test-OllamaRunning)) {
        Write-Error "Ollama service not running"
        return $false
    }
    
    try {
        # Test API endpoints
        Write-Host "🧪 Testing Ollama API..." -ForegroundColor Cyan
        
        # Test model list
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 10
        $modelCount = $response.models.Count
        Write-Success "API responding - $modelCount models available"
        
        # Find a suitable model for testing
        $testModel = $null
        foreach ($model in $response.models) {
            if ($model.name -like "*llama*") {
                $testModel = $model.name
                break
            }
        }
        
        if (-not $testModel) {
            Write-Warning "No suitable model found for testing"
            return $false
        }
        
        Write-Host "🤖 Testing model: $testModel" -ForegroundColor Cyan
        
        # Test generation
        $testPrompt = @{
            model = $testModel
            prompt = "Hello! Respond with just 'AI Test Successful' and nothing else."
            stream = $false
        } | ConvertTo-Json
        
        $genResponse = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $testPrompt -ContentType "application/json" -TimeoutSec 30
        
        if ($genResponse.response) {
            Write-Success "Model generation test passed"
            Write-Host "  Response: $($genResponse.response.Trim())" -ForegroundColor Gray
            return $true
        } else {
            Write-Warning "Model responded but no content generated"
            return $false
        }
        
    } catch {
        Write-Error "Ollama standalone test failed: $_"
        return $false
    }
}

function Test-BackendIntegration {
    Write-Step "Testing backend AI integration..."
    
    if (-not (Test-BackendExists)) {
        Write-Error "Backend not found. Run scripts 02 and 03 first."
        return $false
    }
    
    Write-Host "🔍 Checking backend AI integration..." -ForegroundColor Cyan
    
    # Check if AI service file exists and has correct content
    if (Test-Path "backend/services/ai_service.py") {
        $aiServiceContent = Get-Content "backend/services/ai_service.py" -Raw
        if ($aiServiceContent -match "ollama" -and $aiServiceContent -match "AIService") {
            Write-Success "AI service module properly configured"
        } else {
            Write-Warning "AI service module exists but may not be properly configured"
        }
    } else {
        Write-Error "AI service module not found"
        return $false
    }
    
    # Check main.py for AI integration
    if (Test-Path "backend/api/main.py") {
        $mainContent = Get-Content "backend/api/main.py" -Raw
        if ($mainContent -match "ai_service" -and $mainContent -match "1\.1\.0") {
            Write-Success "Backend main.py has AI integration (v1.1.0)"
        } else {
            Write-Warning "Backend may not have AI integration"
            return $false
        }
    }
    
    return $true
}

function Start-EnhancedBackend {
    Write-Step "Starting AI-enhanced backend..."
    
    if (-not (Test-BackendExists)) {
        Write-Error "Backend not found. Run scripts 02 and 03 first."
        return
    }
    
    Write-Host ""
    Write-Host "🚀 Starting Jarvis AI Backend with Ollama Integration..." -ForegroundColor Green
    Write-Host ""
    Write-Host "📍 Endpoints available:" -ForegroundColor Cyan
    Write-Host "  • API Documentation: http://localhost:8000/docs" -ForegroundColor White
    Write-Host "  • Health Check: http://localhost:8000/api/health" -ForegroundColor White
    Write-Host "  • Chat Endpoint: http://localhost:8000/api/chat" -ForegroundColor White
    Write-Host "  • AI Status: http://localhost:8000/api/ai/status" -ForegroundColor White
    Write-Host "  • AI Test: http://localhost:8000/api/ai/test" -ForegroundColor White
    Write-Host ""
    
    if (Test-OllamaRunning) {
        Write-Host "✅ Ollama detected - AI responses will be enabled" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Ollama not running - will use fallback echo mode" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "💡 Test commands (run in another terminal):" -ForegroundColor Yellow
    Write-Host "  Invoke-RestMethod -Uri http://localhost:8000/api/ai/status" -ForegroundColor Gray
    Write-Host "  `$body = @{content = 'Hello Jarvis!'} | ConvertTo-Json" -ForegroundColor Gray
    Write-Host "  Invoke-RestMethod -Uri http://localhost:8000/api/chat -Method Post -Body `$body -ContentType 'application/json'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "🛑 Press Ctrl+C to stop the backend" -ForegroundColor Red
    Write-Host ""
    
    $confirm = Read-Host "Ready to start the backend? (Y/n)"
    if ($confirm -eq "" -or $confirm -eq "y" -or $confirm -eq "Y") {
        Write-Host "Starting backend in 3 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
        
        $originalLocation = Get-Location
        try {
            Set-Location backend
            python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
        } finally {
            Set-Location $originalLocation
        }
    } else {
        Write-Host "✅ Backend start cancelled. Run manually with: .\run_backend.ps1" -ForegroundColor Green
    }
}

function Run-ComprehensiveTest {
    Write-Step "Running comprehensive AI system test..."
    
    $testResults = @()
    
    # Test 1: Prerequisites
    Write-Host "🔍 Test 1: Prerequisites..." -ForegroundColor Cyan
    if (Test-OllamaInstalled) {
        $testResults += "✅ Ollama installed"
    } else {
        $testResults += "❌ Ollama not installed"
    }
    
    # Test 2: Service
    Write-Host "🔍 Test 2: Ollama service..." -ForegroundColor Cyan
    if (Test-OllamaRunning) {
        $testResults += "✅ Ollama service running"
    } else {
        $testResults += "❌ Ollama service not running"
    }
    
    # Test 3: Models
    Write-Host "🔍 Test 3: AI models..." -ForegroundColor Cyan
    if (Test-OllamaRunning) {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5
            $modelCount = $response.models.Count
            if ($modelCount -gt 0) {
                $testResults += "✅ $modelCount AI models available"
            } else {
                $testResults += "⚠️  Ollama running but no models installed"
            }
        } catch {
            $testResults += "❌ Could not check models"
        }
    }
    
    # Test 4: Backend
    Write-Host "🔍 Test 4: Backend integration..." -ForegroundColor Cyan
    if (Test-BackendExists) {
        $testResults += "✅ AI-enhanced backend exists"
    } else {
        $testResults += "❌ AI-enhanced backend not found"
    }
    
    # Test 5: Standalone functionality
    if (Test-OllamaRunning) {
        Write-Host "🔍 Test 5: Ollama functionality..." -ForegroundColor Cyan
        if (Test-OllamaStandalone) {
            $testResults += "✅ Ollama standalone test passed"
        } else {
            $testResults += "❌ Ollama standalone test failed"
        }
    }
    
    return $testResults
}

# Main execution
Write-Host "🤖 Ollama Setup and AI Integration Testing" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

if ($Setup -or $All) {
    Write-Host ""
    Write-Host "🚀 Setting up Ollama..." -ForegroundColor Yellow
    
    if (Setup-OllamaService) {
        if (Install-RecommendedModel) {
            Write-Success "Ollama setup completed successfully!"
        } else {
            Write-Warning "Ollama service ready, but model installation had issues"
        }
    } else {
        Write-Error "Ollama setup failed"
        exit 1
    }
}

if ($Test -or $All) {
    Write-Host ""
    Write-Host "🧪 Running comprehensive tests..." -ForegroundColor Yellow
    
    $testResults = Run-ComprehensiveTest
    
    Write-Host ""
    Write-Host "📋 Test Results:" -ForegroundColor Cyan
    foreach ($result in $testResults) {
        Write-Host $result
    }
}

# Always show validation regardless of parameters
Write-Host ""
Write-Host "🔍 Ollama & AI Integration Validation:" -ForegroundColor Cyan
Write-Host "-" * 60 -ForegroundColor Gray

$validationResults = @()

# Check Ollama installation
if (Test-OllamaInstalled) {
    try {
        $ollamaVersion = & ollama --version 2>$null
        $validationResults += "✅ Ollama: Installed ($ollamaVersion)"
    } catch {
        $validationResults += "✅ Ollama: Installed (version check failed)"
    }
} else {
    $validationResults += "❌ Ollama: Not installed"
}

# Check Ollama service
if (Test-OllamaRunning) {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5
        $modelCount = $response.models.Count
        $validationResults += "✅ Ollama Service: Running with $modelCount models"
        
        # Check for recommended model
        $hasLlama = $response.models | Where-Object { $_.name -like "*llama3.1*8b*" -or $_.name -eq "llama3.1:8b" }
        if ($hasLlama) {
            $validationResults += "✅ AI Model: llama3.1:8b ready"
        } else {
            $otherModels = $response.models | Where-Object { $_.name -like "*llama*" }
            if ($otherModels) {
                $modelName = $otherModels[0].name
                $validationResults += "✅ AI Model: $modelName available"
            } else {
                $validationResults += "⚠️  AI Model: No Llama models (run with -Setup to install)"
            }
        }
    } catch {
        $validationResults += "⚠️  Ollama Service: Running but API issues"
    }
} else {
    $validationResults += "❌ Ollama Service: Not running (run with -Setup to start)"
}

# Check backend integration
if (Test-BackendExists) {
    $validationResults += "✅ Backend: AI-enhanced backend ready"
    
    # Check if backend can potentially connect to Ollama
    if (Test-Path "backend/services/ai_service.py") {
        $aiContent = Get-Content "backend/services/ai_service.py" -Raw
        if ($aiContent -match "localhost:11434") {
            $validationResults += "✅ Integration: Backend configured for Ollama"
        } else {
            $validationResults += "⚠️  Integration: Backend AI service needs configuration"
        }
    }
} else {
    $validationResults += "❌ Backend: Run scripts 02 and 03 first"
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
    Write-Host "🎉 Ollama Integration Complete: $successCount/$totalChecks checks passed!" -ForegroundColor Green
    Write-Host "✅ Full AI capabilities ready - Jarvis can think!" -ForegroundColor Green
} elseif ($failureCount -eq 0) {
    Write-Host "⚠️  Ollama Integration: $successCount/$totalChecks ready, $warningCount minor issues" -ForegroundColor Yellow
    Write-Host "✅ Core AI functionality available" -ForegroundColor Green
} else {
    Write-Host "❗ Ollama Integration: $successCount/$totalChecks ready, $failureCount missing, $warningCount warnings" -ForegroundColor Red
    Write-Host "❌ Some AI components need setup" -ForegroundColor Red
}

if ($StartBackend -or $All) {
    Write-Host ""
    Start-EnhancedBackend
}

if (-not ($Setup -or $Test -or $StartBackend -or $All)) {
    Write-Host ""
    Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
    Write-Host "1. .\04-OllamaSetupAndTesting.ps1 -Setup       # Setup Ollama service & models" -ForegroundColor White
    Write-Host "2. .\04-OllamaSetupAndTesting.ps1 -Test        # Test AI functionality" -ForegroundColor White
    Write-Host "3. .\04-OllamaSetupAndTesting.ps1 -StartBackend # Start AI-enabled backend" -ForegroundColor White
    Write-Host ""
    Write-Host "Or run everything:" -ForegroundColor Yellow
    Write-Host ".\04-OllamaSetupAndTesting.ps1 -All" -ForegroundColor White
    Write-Host ""
    Write-Host "🤖 This script handles the complete AI setup and integration testing" -ForegroundColor Cyan
}