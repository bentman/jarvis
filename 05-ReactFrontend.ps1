# 05-ReactFrontend.ps1 - Create React frontend for Jarvis AI Assistant
# Creates a modern chat interface with real-time communication to the AI backend
# Builds upon existing backend structure from scripts 01-04

param(
    [switch]$Install,
    [switch]$Build,
    [switch]$Run,
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

function Test-NodeInstalled {
    try {
        $null = Get-Command node -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-BackendExists {
    return (Test-Path "backend/api/main.py") -and (Test-Path "backend/services/ai_service.py") -and (Test-Path "run_backend.ps1")
}

function Create-FrontendStructure {
    Write-Step "Creating React frontend structure..."
    
    if (Test-Path "frontend") {
        Write-Warning "Frontend directory already exists - checking for updates needed"
    } else {
        Write-Host "Creating new React app..." -ForegroundColor Cyan
        Write-Host "This may take 2-5 minutes..." -ForegroundColor Yellow
        
        # Create React app using cmd /c to handle npx properly
        try {
            # First, try with TypeScript template
            Write-Host "Attempting to create TypeScript React app..." -ForegroundColor Gray
            
            # Use cmd /c to execute npx properly on Windows
            $result = cmd /c "echo y | npx create-react-app frontend --template typescript 2>&1"
            
            if (-not (Test-Path "frontend/package.json")) {
                Write-Warning "TypeScript template failed, trying basic React app..."
                
                # Clean up any partial installation
                if (Test-Path "frontend") {
                    Remove-Item "frontend" -Recurse -Force
                }
                
                # Try basic React app
                $result = cmd /c "echo y | npx create-react-app frontend 2>&1"
                
                if (-not (Test-Path "frontend/package.json")) {
                    Write-Error "Failed to create React app. Output: $result"
                    return $false
                }
            }
            
            Write-Success "React app created successfully"
        } catch {
            Write-Error "Failed to create React app: $_"
            return $false
        }
    }
    
    # Create additional directories for our Jarvis components
    $directories = @(
        "frontend/src/components",
        "frontend/src/services",
        "frontend/src/types",
        "frontend/src/hooks",
        "frontend/src/styles"
    )
    
    foreach ($dir in $directories) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "  Created: $dir" -ForegroundColor DarkGreen
        }
    }
    
    Write-Success "Frontend structure ready"
    return $true
}

function Install-FrontendDependencies {
    Write-Step "Installing additional frontend dependencies..."
    
    $originalLocation = Get-Location
    Set-Location frontend
    
    try {
        # Install only essential dependencies (no Tailwind to avoid PostCSS issues)
        $packages = @(
            "@types/react",
            "@types/react-dom", 
            "axios",
            "lucide-react",
            "react-markdown"
        )
        
        Write-Host "Installing packages: $($packages -join ', ')" -ForegroundColor Cyan
        npm install @($packages)
        
        Write-Success "Frontend dependencies installed"
        return $true
    } catch {
        Write-Error "Failed to install frontend dependencies: $_"
        return $false
    } finally {
        Set-Location $originalLocation
    }
}

function Create-StylingAndComponents {
    Write-Step "Creating minimal CSS (inline styles used in components)..."
    
    # Create minimal CSS that won't conflict with inline styles
    $minimalCSS = @"
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html, body, #root, .App {
  width: 100%;
  height: 100%;
  margin: 0;
  padding: 0;
  background: #050810;
  color: #ffffff;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

/* Input focus placeholder fix */
input::placeholder {
  color: #9ca3af;
}

input:focus::placeholder {
  opacity: 0.7;
}

/* Button hover effects */
button:hover {
  transition: all 0.2s ease;
}

/* Scrollbar styling */
::-webkit-scrollbar {
  width: 12px;
}

::-webkit-scrollbar-track {
  background: #0a0e1a;
}

::-webkit-scrollbar-thumb {
  background: #1a2332;
  border-radius: 6px;
}

::-webkit-scrollbar-thumb:hover {
  background: #00d4ff;
}
"@
    
    Set-Content -Path "frontend/src/styles/index.css" -Value $minimalCSS
    Write-Success "Minimal CSS created (components use inline styles)"
}

function Create-ApiService {
    Write-Step "Creating API service..."
    
    $apiService = @"
import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8000';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

export interface ChatMessage {
  content: string;
}

export interface ChatResponse {
  response: string;
  mode: string;
  model: string;
  timestamp: string;
}

export interface AIStatus {
  ai_available: boolean;
  model: string;
  mode: string;
  ollama_url: string;
  available_models?: string[];
}

export interface HealthStatus {
  status: string;
  service: string;
  version: string;
  ai_integration: AIStatus;
  timestamp: string;
}

export class ApiService {
  static async sendMessage(content: string): Promise<ChatResponse> {
    const response = await api.post<ChatResponse>('/api/chat', { content });
    return response.data;
  }

  static async getHealth(): Promise<HealthStatus> {
    const response = await api.get<HealthStatus>('/api/health');
    return response.data;
  }

  static async getAIStatus(): Promise<AIStatus> {
    const response = await api.get<AIStatus>('/api/ai/status');
    return response.data;
  }

  static async testAI(): Promise<any> {
    const response = await api.get('/api/ai/test');
    return response.data;
  }

  static async getStatus(): Promise<any> {
    const response = await api.get('/api/status');
    return response.data;
  }
}

export default ApiService;
"@
    
    Set-Content -Path "frontend/src/services/api.ts" -Value $apiService
    Write-Success "API service created"
}

function Create-Types {
    Write-Step "Creating TypeScript types..."
    
    $types = @"
export interface Message {
  id: string;
  content: string;
  sender: 'user' | 'jarvis';
  timestamp: string;
  mode?: string;
  model?: string;
}

export interface AIStatus {
  ai_available: boolean;
  model: string;
  mode: string;
  ollama_url: string;
  available_models?: string[];
}

export interface AppState {
  messages: Message[];
  isConnected: boolean;
  aiStatus: AIStatus | null;
  isLoading: boolean;
  error: string | null;
}
"@
    
    Set-Content -Path "frontend/src/types/index.ts" -Value $types
    Write-Success "TypeScript types created"
}

function Create-ChatHook {
    Write-Step "Creating chat hook..."
    
    $chatHook = @"
import { useState, useCallback, useEffect } from 'react';
import { ApiService } from '../services/api';
import { Message, AIStatus } from '../types';

export function useChat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [aiStatus, setAIStatus] = useState<AIStatus | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Check connection and AI status
  const checkStatus = useCallback(async () => {
    try {
      await ApiService.getHealth();
      const aiStat = await ApiService.getAIStatus();
      
      setIsConnected(true);
      setAIStatus(aiStat);
      setError(null);
    } catch (err) {
      setIsConnected(false);
      setError('Cannot connect to Jarvis backend');
      console.error('Status check failed:', err);
    }
  }, []);

  // Send message to AI
  const sendMessage = useCallback(async (content: string) => {
    if (!content.trim()) return;

    const userMessage: Message = {
      id: Date.now().toString(),
      content,
      sender: 'user',
      timestamp: new Date().toISOString(),
    };

    setMessages(prev => [...prev, userMessage]);
    setIsLoading(true);
    setError(null);

    try {
      const response = await ApiService.sendMessage(content);
      
      const jarvisMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: response.response,
        sender: 'jarvis',
        timestamp: response.timestamp,
        mode: response.mode,
        model: response.model,
      };

      setMessages(prev => [...prev, jarvisMessage]);
    } catch (err) {
      setError('Failed to get response from Jarvis');
      console.error('Send message failed:', err);
      
      // Add error message
      const errorMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: 'I apologize, but I am experiencing technical difficulties. Please check the backend connection.',
        sender: 'jarvis',
        timestamp: new Date().toISOString(),
        mode: 'error',
        model: 'fallback',
      };
      
      setMessages(prev => [...prev, errorMessage]);
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Clear chat
  const clearChat = useCallback(() => {
    setMessages([]);
    setError(null);
  }, []);

  // Initial status check
  useEffect(() => {
    checkStatus();
    
    // Add welcome message
    const welcomeMessage: Message = {
      id: 'welcome',
      content: 'Hello! I am Jarvis, your AI assistant. How can I help you today?',
      sender: 'jarvis',
      timestamp: new Date().toISOString(),
      mode: 'system',
      model: 'welcome',
    };
    
    setMessages([welcomeMessage]);
  }, [checkStatus]);

  return {
    messages,
    isLoading,
    aiStatus,
    isConnected,
    error,
    sendMessage,
    clearChat,
    checkStatus,
  };
}
"@
    
    Set-Content -Path "frontend/src/hooks/useChat.ts" -Value $chatHook
    Write-Success "Chat hook created"
}

function Create-ChatComponent {
    Write-Step "Creating chat component with inline styles..."
    
    $chatComponent = @"
import React, { useState, useRef, useEffect } from 'react';
import { Send, Bot, User, Wifi, WifiOff, Cpu } from 'lucide-react';
import { useChat } from '../hooks/useChat';
import { Message } from '../types';

interface MessageBubbleProps {
  message: Message;
}

function MessageBubble({ message }: MessageBubbleProps) {
  const isUser = message.sender === 'user';
  const isError = message.mode === 'error';
  const isAI = message.mode === 'ai';

  return (
    <div style={{
      marginBottom: '20px',
      display: 'flex',
      gap: '15px',
      alignItems: 'flex-start',
      width: '100%',
      flexDirection: isUser ? 'row-reverse' : 'row',
      justifyContent: isUser ? 'flex-start' : 'flex-start'
    }}>
      <div style={{
        width: '40px',
        height: '40px',
        borderRadius: '50%',
        backgroundColor: isUser ? '#3b82f6' : isError ? '#ef4444' : '#00d4ff',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexShrink: 0
      }}>
        {isUser ? <User size={20} color="white" /> : <Bot size={20} color={isUser || isError ? "white" : "#050810"} />}
      </div>
      <div style={{
        background: isUser ? '#3b82f6' : isError ? '#7f1d1d' : isAI ? '#1a2332' : '#1a2332',
        color: isUser ? '#ffffff' : isError ? '#fecaca' : isAI ? '#00d4ff' : '#ffffff',
        padding: '20px 25px',
        borderRadius: '20px',
        maxWidth: '70%',
        fontSize: '18px',
        lineHeight: '1.6',
        border: isAI ? '2px solid rgba(0, 212, 255, 0.4)' : isError ? '2px solid #ef4444' : 'none'
      }}>
        <p style={{ margin: 0, fontSize: '18px', lineHeight: '1.6' }}>{message.content}</p>
        <div style={{ fontSize: '14px', opacity: 0.8, marginTop: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span>{new Date(message.timestamp).toLocaleTimeString()}</span>
          {message.mode && message.mode !== 'system' && (
            <>
              <span>•</span>
              <span style={{ textTransform: 'capitalize' }}>{message.mode}</span>
            </>
          )}
          {message.model && message.model !== 'welcome' && (
            <>
              <span>•</span>
              <span>{message.model}</span>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

export function Chat() {
  const [input, setInput] = useState('');
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const { 
    messages, 
    isLoading, 
    aiStatus, 
    isConnected, 
    error, 
    sendMessage, 
    clearChat,
    checkStatus 
  } = useChat();

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    const message = input.trim();
    setInput('');
    await sendMessage(message);
  };

  return (
    <div style={{
      width: '100vw',
      height: '100vh',
      display: 'flex',
      flexDirection: 'column',
      background: '#050810',
      color: '#ffffff',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      margin: 0,
      padding: 0
    }}>
      {/* Header */}
      <div style={{
        background: '#0a0e1a',
        color: '#ffffff',
        padding: '25px',
        borderBottom: '1px solid #1a2332',
        width: '100%',
        flexShrink: 0
      }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
            <div style={{ position: 'relative' }}>
              <div style={{
                width: '50px',
                height: '50px',
                backgroundColor: '#00d4ff',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}>
                <Bot size={30} color="#050810" />
              </div>
              <div style={{
                position: 'absolute',
                bottom: '-2px',
                right: '-2px',
                width: '18px',
                height: '18px',
                borderRadius: '50%',
                border: '3px solid #0a0e1a',
                backgroundColor: isConnected ? '#10b981' : '#ef4444'
              }} />
            </div>
            <div>
              <h1 style={{
                color: '#00d4ff',
                fontSize: '32px',
                fontWeight: 'bold',
                margin: 0
              }}>J.A.R.V.I.S.</h1>
              <p style={{
                margin: '8px 0 0 0',
                fontSize: '18px',
                color: '#9ca3af'
              }}>
                {isConnected ? 'Connected' : 'Disconnected'} • {aiStatus?.mode || 'Unknown'}
              </p>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
            <button
              onClick={checkStatus}
              style={{
                background: 'none',
                border: 'none',
                color: '#ffffff',
                padding: '12px',
                cursor: 'pointer',
                borderRadius: '10px'
              }}
              title="Check Connection"
            >
              {isConnected ? (
                <Wifi size={24} color="#10b981" />
              ) : (
                <WifiOff size={24} color="#ef4444" />
              )}
            </button>

            {aiStatus && (
              <div style={{
                padding: '12px 18px',
                borderRadius: '10px',
                display: 'flex',
                alignItems: 'center',
                gap: '10px',
                background: aiStatus.ai_available ? '#065f46' : '#92400e',
                color: aiStatus.ai_available ? '#10b981' : '#fbbf24'
              }}>
                <Cpu size={18} />
                <span style={{ fontSize: '16px', fontWeight: '500' }}>
                  {aiStatus.ai_available ? 'AI Online' : 'Echo Mode'}
                </span>
              </div>
            )}

            <button
              onClick={clearChat}
              style={{
                background: '#1a2332',
                color: '#ffffff',
                border: 'none',
                padding: '12px 20px',
                borderRadius: '8px',
                cursor: 'pointer',
                fontSize: '16px'
              }}
            >
              Clear
            </button>
          </div>
        </div>

        {error && (
          <div style={{
            marginTop: '15px',
            padding: '15px',
            background: '#7f1d1d',
            border: '2px solid #ef4444',
            borderRadius: '10px',
            fontSize: '16px',
            color: '#fecaca'
          }}>
            {error}
          </div>
        )}
      </div>

      {/* Messages */}
      <div style={{
        flex: 1,
        padding: '25px',
        overflowY: 'auto',
        background: '#050810',
        width: '100%',
        minHeight: 0
      }}>
        {messages.map((message) => (
          <MessageBubble key={message.id} message={message} />
        ))}
        
        {isLoading && (
          <div style={{ display: 'flex', justifyContent: 'flex-start', marginBottom: '20px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
              <div style={{
                width: '40px',
                height: '40px',
                backgroundColor: '#00d4ff',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}>
                <Bot size={20} color="#050810" />
              </div>
              <div style={{
                backgroundColor: '#1a2332',
                borderRadius: '20px',
                padding: '15px 20px'
              }}>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <div style={{ width: '12px', height: '12px', backgroundColor: '#00d4ff', borderRadius: '50%' }} />
                  <div style={{ width: '12px', height: '12px', backgroundColor: '#00d4ff', borderRadius: '50%' }} />
                  <div style={{ width: '12px', height: '12px', backgroundColor: '#00d4ff', borderRadius: '50%' }} />
                </div>
              </div>
            </div>
          </div>
        )}
        
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <div style={{
        background: '#0a0e1a',
        padding: '25px',
        borderTop: '1px solid #1a2332',
        width: '100%',
        flexShrink: 0
      }}>
        <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '15px', width: '100%' }}>
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask Jarvis anything..."
            style={{
              flex: 1,
              background: '#1a2332',
              border: '2px solid rgba(0, 212, 255, 0.4)',
              borderRadius: '15px',
              padding: '20px 25px',
              color: '#ffffff',
              fontSize: '18px',
              outline: 'none'
            }}
            disabled={isLoading || !isConnected}
          />
          <button
            type="submit"
            disabled={isLoading || !isConnected || !input.trim()}
            style={{
              background: (!isLoading && isConnected && input.trim()) ? '#00d4ff' : '#6b7280',
              color: '#050810',
              border: 'none',
              borderRadius: '15px',
              padding: '20px 30px',
              cursor: (!isLoading && isConnected && input.trim()) ? 'pointer' : 'not-allowed',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}
          >
            <Send size={22} />
          </button>
        </form>
      </div>
    </div>
  );
}
"@
    
    Set-Content -Path "frontend/src/components/Chat.tsx" -Value $chatComponent
    Write-Success "Full-screen inline-styled chat component created"
}

function Create-AppComponent {
    Write-Step "Creating main App component..."
    
    $appComponent = @"
import React from 'react';
import { Chat } from './components/Chat';
import './styles/index.css';

function App() {
  return (
    <div className="App">
      <Chat />
    </div>
  );
}

export default App;
"@
    
    Set-Content -Path "frontend/src/App.tsx" -Value $appComponent
    
    # Update index.tsx to import our styles
    $indexTSX = @"
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
"@
    
    Set-Content -Path "frontend/src/index.tsx" -Value $indexTSX
    Write-Success "Main App component created"
}

function Create-EnvFile {
    Write-Step "Creating environment configuration..."
    
    $envContent = @"
# React App Environment Configuration
REACT_APP_API_URL=http://localhost:8000
REACT_APP_NAME=Jarvis AI Assistant
REACT_APP_VERSION=1.0.0

# Development settings
GENERATE_SOURCEMAP=true
"@
    
    Set-Content -Path "frontend/.env" -Value $envContent
    Write-Success "Environment file created"
}

function Update-PackageJson {
    Write-Step "Updating package.json scripts..."
    
    $originalLocation = Get-Location
    Set-Location frontend
    
    try {
        # Read existing package.json
        $packageJson = Get-Content "package.json" | ConvertFrom-Json
        
        # Add custom scripts
        $packageJson.scripts | Add-Member -Type NoteProperty -Name "build:prod" -Value "npm run build" -Force
        $packageJson.scripts | Add-Member -Type NoteProperty -Name "preview" -Value "npm run build && npx serve -s build -l 3000" -Force
        
        # Convert back to JSON and save
        $packageJson | ConvertTo-Json -Depth 10 | Set-Content "package.json"
        
        Write-Success "Package.json updated"
    } catch {
        Write-Warning "Could not update package.json scripts"
    } finally {
        Set-Location $originalLocation
    }
}

function Create-FrontendRunScript {
    Write-Step "Creating frontend run script..."
    
    $runScript = @"
# run_frontend.ps1 - Start the React frontend
param(
    [switch]`$Build,
    [switch]`$Install,
    [switch]`$Dev
)

if (`$Install) {
    Write-Host "📦 Installing frontend dependencies..." -ForegroundColor Yellow
    Set-Location frontend
    npm install
    Set-Location ..
    Write-Host "✅ Dependencies installed" -ForegroundColor Green
    return
}

if (`$Build) {
    Write-Host "🏗️  Building frontend for production..." -ForegroundColor Yellow
    Set-Location frontend
    npm run build
    Set-Location ..
    Write-Host "✅ Build complete - files in frontend/build/" -ForegroundColor Green
    return
}

Write-Host "🚀 Starting Jarvis AI Frontend..." -ForegroundColor Green
Write-Host ""
Write-Host "📍 Frontend URL: http://localhost:3000" -ForegroundColor Cyan
Write-Host "🔗 Make sure backend is running on: http://localhost:8000" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 To start backend: .\run_backend.ps1" -ForegroundColor Yellow
Write-Host "🛑 Press Ctrl+C to stop the frontend" -ForegroundColor Red
Write-Host ""

# Check if backend is running
try {
    `$response = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 3
    Write-Host "✅ Backend detected - full functionality available" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Backend not detected - start it for full functionality" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Starting React development server..." -ForegroundColor Green

Set-Location frontend
npm start
"@
    
    Set-Content -Path "run_frontend.ps1" -Value $runScript
    Write-Success "Frontend run script created"
}

# Main execution
Write-Host "🎨 Creating React Frontend for Jarvis AI Assistant" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

# Check prerequisites
if (-not (Test-NodeInstalled)) {
    Write-Error "Node.js not found. Please run .\01-Prerequisites.ps1 first."
    exit 1
}

if (-not (Test-BackendExists)) {
    Write-Error "Backend not found. Please run scripts 02-04 first to set up the backend."
    exit 1
}

# Create frontend structure and components
if ($Install -or $All) {
    Write-Host ""
    Write-Host "🚀 Setting up React frontend..." -ForegroundColor Yellow
    
    if (Create-FrontendStructure) {
        if (Install-FrontendDependencies) {
            Create-StylingAndComponents
            Create-ApiService
            Create-Types
            Create-ChatHook
            Create-ChatComponent
            Create-AppComponent
            Create-EnvFile
            Update-PackageJson
            Create-FrontendRunScript
            
            # Clean up any Tailwind conflicts after component creation
            $originalLocation = Get-Location
            Set-Location frontend
            try {
                Write-Host "  Final cleanup of conflicting packages..." -ForegroundColor Yellow
                npm uninstall tailwindcss @tailwindcss/typography @tailwindcss/postcss autoprefixer postcss framer-motion --silent 2>$null
                Remove-Item "tailwind.config.js" -Force -ErrorAction SilentlyContinue
                Remove-Item "postcss.config.js" -Force -ErrorAction SilentlyContinue
            } finally {
                Set-Location $originalLocation
            }
            
            Write-Success "Frontend setup completed with inline-styled components!"
        } else {
            Write-Error "Frontend dependency installation failed"
            exit 1
        }
    } else {
        Write-Error "Frontend structure creation failed"
        exit 1
    }
}

if ($Build -or $All) {
    Write-Host ""
    Write-Host "🏗️  Building frontend for production..." -ForegroundColor Yellow
    
    $originalLocation = Get-Location
    Set-Location frontend
    try {
        npm run build
        Write-Success "Frontend build completed!"
    } catch {
        Write-Error "Frontend build failed: $_"
        return $false
    } finally {
        Set-Location $originalLocation
    }
}

# Always show comprehensive validation regardless of parameters
Write-Host ""
Write-Host "🔍 Complete System Validation - Frontend + Backend + AI:" -ForegroundColor Cyan
Write-Host "-" * 60 -ForegroundColor Gray

$validationResults = @()

# Check backend components (from previous scripts)
$backendChecks = @{
    "Backend Directory" = "backend"
    "FastAPI Main" = "backend/api/main.py"
    "AI Service" = "backend/services/ai_service.py"
    "Backend Requirements" = "backend/requirements.txt"
    "Backend Tests" = "backend/tests/test_main.py"
    "AI Tests" = "backend/tests/test_ai_integration.py"
    "Environment Config" = ".env"
    "Backend Run Script" = "run_backend.ps1"
}

foreach ($check in $backendChecks.GetEnumerator()) {
    if (Test-Path $check.Value) {
        $size = if (Test-Path $check.Value -PathType Leaf) { " ($((Get-Item $check.Value).Length) bytes)" } else { "" }
        $validationResults += "✅ Backend: $($check.Key)$size"
    } else {
        $validationResults += "❌ Backend: $($check.Key) - missing"
    }
}

# Check frontend components
$frontendChecks = @{
    "Frontend Directory" = "frontend"
    "Package.json" = "frontend/package.json"
    "Source Directory" = "frontend/src"
    "Components" = "frontend/src/components"
    "Chat Component" = "frontend/src/components/Chat.tsx"
    "API Service" = "frontend/src/services/api.ts"
    "Chat Hook" = "frontend/src/hooks/useChat.ts"
    "Types" = "frontend/src/types/index.ts"
    "Styles" = "frontend/src/styles/index.css"
    "Frontend Env" = "frontend/.env"
    "Frontend Run Script" = "run_frontend.ps1"
}

foreach ($check in $frontendChecks.GetEnumerator()) {
    if (Test-Path $check.Value) {
        $size = if (Test-Path $check.Value -PathType Leaf) { " ($((Get-Item $check.Value).Length) bytes)" } else { "" }
        $validationResults += "✅ Frontend: $($check.Key)$size"
    } else {
        $validationResults += "❌ Frontend: $($check.Key) - missing"
    }
}

# Check Node.js and dependencies
if (Test-NodeInstalled) {
    try {
        $nodeVersion = node --version 2>$null
        $validationResults += "✅ Node.js: $nodeVersion installed"
        
        # Check npm packages if frontend exists
        if (Test-Path "frontend/package.json") {
            $originalLocation = Get-Location
            Set-Location frontend
            try {
                $npmList = npm list --depth=0 2>$null
                if ($npmList -match "react@") {
                    $validationResults += "✅ React: Installed with dependencies"
                } else {
                    $validationResults += "❌ React: Not installed (run with -Install)"
                }
            } catch {
                $validationResults += "⚠️  React: Could not verify packages"
            } finally {
                Set-Location $originalLocation
            }
        }
    } catch {
        $validationResults += "⚠️  Node.js: Version check failed"
    }
} else {
    $validationResults += "❌ Node.js: Not installed"
}

# Check backend Python dependencies
$originalLocation = Get-Location
try {
    Set-Location backend
    $pipList = pip list 2>$null
    
    $pythonPackages = @("fastapi", "uvicorn", "ollama")
    foreach ($package in $pythonPackages) {
        if ($pipList -match $package) {
            $validationResults += "✅ Python: $package installed"
        } else {
            $validationResults += "❌ Python: $package missing"
        }
    }
    
    Set-Location $originalLocation
} catch {
    $validationResults += "⚠️  Python: Could not verify packages"
    Set-Location $originalLocation -ErrorAction SilentlyContinue
}

# Check project structure completeness
$projectFiles = @(
    "01-Prerequisites.ps1",
    "02-SimpleFastApiBackend.ps1", 
    "03-OllamaIntegration.ps1",
    "04-OllamaSetupAndTesting.ps1",
    "05-ReactFrontend.ps1"
)

$foundScripts = 0
foreach ($file in $projectFiles) {
    if (Test-Path $file) {
        $foundScripts++
        if ($file -eq "05-ReactFrontend.ps1") {
            $validationResults += "✅ Script: $file (this script)"
        } else {
            $validationResults += "✅ Script: $file"
        }
    } else {
        if ($file -eq "05-ReactFrontend.ps1") {
            $validationResults += "⚠️  Script: $file (running now)"
        } else {
            $validationResults += "❌ Script: $file - missing"
        }
    }
}

# Display results
foreach ($result in $validationResults) {
    Write-Host $result
}

# Summary with intelligent messaging
$successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
$warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
$failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
$totalChecks = $validationResults.Count

Write-Host ""
if ($failureCount -eq 0 -and $warningCount -le 1) {
    Write-Host "🎉 Complete System Validation: $successCount/$totalChecks checks passed!" -ForegroundColor Green
    Write-Host "✅ Full-stack Jarvis AI Assistant ready!" -ForegroundColor Green
} elseif ($failureCount -le 2) {
    Write-Host "⚠️  System Validation: $successCount/$totalChecks ready, $failureCount missing, $warningCount warnings" -ForegroundColor Yellow
    Write-Host "✅ Core system operational, some components need setup" -ForegroundColor Green
} else {
    Write-Host "❗ System Validation: $successCount/$totalChecks ready, $failureCount missing, $warningCount warnings" -ForegroundColor Red
    Write-Host "❌ Several components need attention" -ForegroundColor Red
}

if ($Run -or $All) {
    Write-Host ""
    Write-Host "🎯 Starting Frontend Server:" -ForegroundColor Yellow
    
    # Check if backend is running
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 3
        Write-Host "✅ Backend detected - full functionality available" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Backend not detected - start it for full functionality" -ForegroundColor Yellow
        Write-Host "💡 Run in another terminal: .\run_backend.ps1" -ForegroundColor Cyan
    }
    
    Write-Host ""
    $confirm = Read-Host "Ready to start the frontend? (Y/n)"
    if ($confirm -eq "" -or $confirm -eq "y" -or $confirm -eq "Y") {
        Write-Host "Starting frontend in 3 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
        
        $originalLocation = Get-Location
        try {
            Set-Location frontend
            npm start
        } finally {
            Set-Location $originalLocation
        }
    } else {
        Write-Host "✅ Frontend start cancelled. Run manually with: .\run_frontend.ps1" -ForegroundColor Green
    }
}

if (-not ($Install -or $Build -or $Run -or $All)) {
    Write-Host ""
    Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
    Write-Host "1. .\05-ReactFrontend.ps1 -Install     # Install and setup frontend" -ForegroundColor White
    Write-Host "2. .\05-ReactFrontend.ps1 -Run         # Start frontend server" -ForegroundColor White
    Write-Host ""
    Write-Host "Or run everything:" -ForegroundColor Yellow
    Write-Host ".\05-ReactFrontend.ps1 -All" -ForegroundColor White
    Write-Host ""
    Write-Host "💡 After setup, use daily run scripts:" -ForegroundColor Yellow
    Write-Host "   .\run_backend.ps1   # Terminal 1" -ForegroundColor Gray
    Write-Host "   .\run_frontend.ps1  # Terminal 2" -ForegroundColor Gray
}

# Quick test instructions (always show if components exist)
if ((Test-Path "frontend/src/components/Chat.tsx") -and ($successCount -gt 10)) {
    Write-Host ""
    Write-Host "🚀 System Ready - Quick Start Commands:" -ForegroundColor Cyan
    Write-Host "# Start both servers (use separate terminals):" -ForegroundColor Gray
    Write-Host ".\run_backend.ps1" -ForegroundColor White
    Write-Host ".\run_frontend.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "# Then visit:" -ForegroundColor Gray
    Write-Host "http://localhost:3000    # Chat Interface" -ForegroundColor White
    Write-Host "http://localhost:8000/docs # API Documentation" -ForegroundColor White
}