# 05-ReactFrontend.ps1 - React Frontend Build and Integration
# Purpose: Create React frontend with inline-styled components for Jarvis AI
# Last edit: 2025-07-24 - Replaced server startup with health validation in -Run mode

param(
  [switch]$Install,
  [switch]$Configure,
  [switch]$Test,
  [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "4.4.0"
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

function Test-Prerequisites {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  if (-not (Test-Command -Command "node" -LogFile $LogFile)) {
    Write-Log -Message "Node.js not found. Run 01-Prerequisites.ps1 first." -Level ERROR -LogFile $LogFile
    return $false
  }
  if (-not (Test-Path "backend/api/main.py") -or -not (Test-Path "backend/services/ai_service.py")) {
    Write-Log -Message "Backend not found. Run scripts 02-04 first." -Level ERROR -LogFile $LogFile
    return $false
  }
  return $true
}

function New-ReactApp {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  if (Test-Path "frontend/package.json") {
    Write-Log -Message "React app already exists" -Level SUCCESS -LogFile $LogFile
    return $true
  }
  Write-Log -Message "Creating React app (this may take 2-5 minutes)..." -Level INFO -LogFile $LogFile
  try {
    $result = cmd /c "echo y | npx create-react-app frontend --template typescript 2>&1"
    if (-not (Test-Path "frontend/package.json")) {
      Write-Log -Message "TypeScript template failed, trying basic React..." -Level WARN -LogFile $LogFile
      if (Test-Path "frontend") { Remove-Item "frontend" -Recurse -Force }
      $result = cmd /c "echo y | npx create-react-app frontend 2>&1"
    }
    if (Test-Path "frontend/package.json") {
      Write-Log -Message "React app created successfully" -Level SUCCESS -LogFile $LogFile
      return $true
    }
    Write-Log -Message "Failed to create React app: $result" -Level ERROR -LogFile $LogFile
    return $false
  }
  catch {
    Write-Log -Message "React app creation failed: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
}

function Install-Dependencies {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Push-Location
  try {
    Set-Location frontend
    $packageJson = Get-Content "package.json" | ConvertFrom-Json
    $hasRequiredDeps = $packageJson.dependencies."axios" -and $packageJson.dependencies."lucide-react"
    if ($hasRequiredDeps) {
      Write-Log -Message "Dependencies already installed" -Level SUCCESS -LogFile $LogFile
      return $true
    }
    Write-Log -Message "Installing frontend dependencies..." -Level INFO -LogFile $LogFile
    $packages = @("@types/react", "@types/react-dom", "axios", "lucide-react", "react-markdown")
    npm install @($packages) 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Log -Message "Dependencies installed successfully" -Level SUCCESS -LogFile $LogFile
      return $true
    }
    Write-Log -Message "Some dependencies had issues but continuing..." -Level WARN -LogFile $LogFile
    return $true
  }
  catch {
    Write-Log -Message "Failed to install dependencies: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
  finally { Pop-Location }
}

function New-FrontendFiles {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  # Create directory structure
  $directories = @("frontend/src/components", "frontend/src/services", "frontend/src/types", "frontend/src/hooks", "frontend/src/styles")
  New-DirectoryStructure -Directories $directories -LogFile $LogFile
  # Create CSS file (PRESERVE EXACT FORMATTING)
  $cssContent = @"
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
  try {
    Set-Content -Path "frontend/src/styles/index.css" -Value $cssContent
    Write-Log -Message "CSS file created" -Level SUCCESS -LogFile $LogFile
  }
  catch {
    Write-Log -Message "Failed to create CSS: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
  # Create API service
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
  try {
    Set-Content -Path "frontend/src/services/api.ts" -Value $apiService
    Write-Log -Message "API service created" -Level SUCCESS -LogFile $LogFile
  }
  catch {
    Write-Log -Message "Failed to create API service: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
  # Create TypeScript types
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
  try {
    Set-Content -Path "frontend/src/types/index.ts" -Value $types
    Write-Log -Message "TypeScript types created" -Level SUCCESS -LogFile $LogFile
  }
  catch {
    Write-Log -Message "Failed to create types: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
  # Create chat hook
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
  try {
    Set-Content -Path "frontend/src/hooks/useChat.ts" -Value $chatHook
    Write-Log -Message "Chat hook created" -Level SUCCESS -LogFile $LogFile
  }
  catch {
    Write-Log -Message "Failed to create chat hook: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
  # Create chat component (PRESERVE EXACT INLINE STYLES)
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
  try {
    Set-Content -Path "frontend/src/components/Chat.tsx" -Value $chatComponent
    Write-Log -Message "Chat component created with preserved inline styles" -Level SUCCESS -LogFile $LogFile
  }
  catch {
    Write-Log -Message "Failed to create chat component: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
  # Create App component
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
    
  try {
    Set-Content -Path "frontend/src/App.tsx" -Value $appComponent
    Write-Log -Message "App component created" -Level SUCCESS -LogFile $LogFile
  }
  catch {
    Write-Log -Message "Failed to create App component: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
    
  # Update index.tsx
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
  try {
    Set-Content -Path "frontend/src/index.tsx" -Value $indexTSX
    Write-Log -Message "Index component updated" -Level SUCCESS -LogFile $LogFile
  }
  catch {
    Write-Log -Message "Failed to update index component: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
  # Create environment config
  $envContent = @"
# React App Environment Configuration
REACT_APP_API_URL=http://localhost:8000
REACT_APP_NAME=Jarvis AI Assistant
REACT_APP_VERSION=1.0.0

# Development settings
GENERATE_SOURCEMAP=true
"@
    
  try {
    Set-Content -Path "frontend/.env" -Value $envContent
    Write-Log -Message "Environment configuration created" -Level SUCCESS -LogFile $LogFile
  }
  catch {
    Write-Log -Message "Failed to create environment config: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
    
  return $true
}

function New-RunScript {
  param([string]$LogFile)
  $runScript = @"
# run_frontend.ps1 - Start the React Development Server
# Simple development server startup - use npm commands directly for build/install

Write-Host "Starting Jarvis AI Frontend..." -ForegroundColor Green
Write-Host "Frontend URL: http://localhost:3000" -ForegroundColor Cyan
Write-Host "Backend URL: http://localhost:8000 (ensure backend is running)" -ForegroundColor Cyan

if (-not (Test-Path "frontend")) {
    Write-Host "Frontend directory not found - run .\05-ReactFrontend.ps1 first" -ForegroundColor Red
    return
}

Push-Location frontend
try {
    npm start
} finally {
    Pop-Location
}
"@
  try {
    Set-Content -Path "run_frontend.ps1" -Value $runScript
    Write-Log -Message "Frontend run script created" -Level SUCCESS -LogFile $LogFile
    return $true
  }
  catch {
    Write-Log -Message "Failed to create run script: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
}

function Test-FrontendSetup {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Validating frontend setup..." -Level INFO -LogFile $LogFile
  $checks = @(
    @{Name = "Node.js"; Path = "node"; IsCommand = $true },
    @{Name = "Frontend Directory"; Path = "frontend" },
    @{Name = "Package.json"; Path = "frontend/package.json" },
    @{Name = "Chat Component"; Path = "frontend/src/components/Chat.tsx" },
    @{Name = "API Service"; Path = "frontend/src/services/api.ts" },
    @{Name = "Chat Hook"; Path = "frontend/src/hooks/useChat.ts" },
    @{Name = "Types"; Path = "frontend/src/types/index.ts" },
    @{Name = "Styles"; Path = "frontend/src/styles/index.css" },
    @{Name = "App Component"; Path = "frontend/src/App.tsx" },
    @{Name = "Environment Config"; Path = "frontend/.env" },
    @{Name = "Run Script"; Path = "run_frontend.ps1" }
  )
  $results = @()
  foreach ($check in $checks) {
    if ($check.IsCommand) { $status = Test-Command -Command $check.Path -LogFile $LogFile }
    else { $status = Test-Path $check.Path }
    $results += "$($status ? '✅' : '❌') $($check.Name)"
  }
  # Check dependencies if package.json exists
  if (Test-Path "frontend/package.json") {
    Push-Location
    try {
      Set-Location frontend
      if (Test-Path "node_modules") {
        $packageJson = Get-Content "package.json" | ConvertFrom-Json
        $hasAxios = $packageJson.dependencies."axios"
        $hasLucide = $packageJson.dependencies."lucide-react"
                
        $results += "$($hasAxios ? '✅' : '❌') Package: axios"
        $results += "$($hasLucide ? '✅' : '❌') Package: lucide-react"
        $results += "✅ Dependencies: node_modules installed"
      }
      else { $results += "❌ Dependencies: node_modules not found" }
    }
    catch { $results += "⚠️ Dependencies: Could not verify" }
    finally { Pop-Location }
  }
  Write-Log -Message "=== FRONTEND VALIDATION RESULTS ===" -Level INFO -LogFile $LogFile
  foreach ($result in $results) {
    $level = if ($result -like "✅*") { "SUCCESS" } elseif ($result -like "⚠️*") { "WARN" } else { "ERROR" }
    Write-Log -Message $result -Level $level -LogFile $LogFile
  }
  $successCount = ($results | Where-Object { $_ -like "✅*" }).Count
  $failureCount = ($results | Where-Object { $_ -like "❌*" }).Count
  Write-Log -Message "Validation: $successCount/$($results.Count) checks passed" -Level ($failureCount -eq 0 ? "SUCCESS" : "ERROR") -LogFile $LogFile
  return $failureCount -eq 0
}

function Test-FrontendHealth {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Validating frontend health..." -Level INFO -LogFile $LogFile
  if (-not (Test-Path "frontend")) {
    Write-Log -Message "Frontend directory not found - cannot validate" -Level ERROR -LogFile $LogFile
    return $false
  }
  if (-not (Test-Path "frontend/package.json")) {
    Write-Log -Message "Frontend package.json not found - cannot validate" -Level ERROR -LogFile $LogFile
    return $false
  }
  $serverProcess = $null
  Push-Location frontend
  try {
    Write-Log -Message "Starting temporary frontend server for validation..." -Level INFO -LogFile $LogFile
    # Start development server in background
    $serverProcess = Start-Process -PassThru -WindowStyle Hidden -FilePath "npm" -ArgumentList "start"
    # Wait for server to start
    Start-Sleep -Seconds 10
    # Test if frontend is responding
    $response = Invoke-WebRequest -Uri "http://localhost:3000" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    if ($response.StatusCode -eq 200) { Write-Log -Message "Frontend health check passed - server responding" -Level SUCCESS -LogFile $LogFile }
    # Check if it can reach backend (optional)
    try {
      $backendHealth = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 3
      Write-Log -Message "Backend connectivity confirmed - full functionality available" -Level SUCCESS -LogFile $LogFile
    }
    catch { Write-Log -Message "Backend not available - frontend validated but backend integration unavailable" -Level WARN -LogFile $LogFile }
    Write-Log -Message "Frontend validation successful - use .\run_frontend.ps1 to start server" -Level SUCCESS -LogFile $LogFile
    return $true
  }
  catch {
    Write-Log -Message "Frontend health validation failed: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
  finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
      Write-Log -Message "Stopping validation server..." -Level INFO -LogFile $LogFile
      Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
      # Also kill any child npm processes
      Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.Parent.Id -eq $serverProcess.Id } | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
  }
}

# Main execution
try {
  if (-not (Test-Prerequisites -LogFile $logFile)) {
    Stop-Transcript
    exit 1
  }
  $setupResults = @()
  if ($Install -or $Run) {
    Write-Log -Message "Setting up React frontend..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "React App Creation"; Success = (New-ReactApp -LogFile $logFile) }
    if ($setupResults[-1].Success) {
      $setupResults += @{Name = "Dependencies"; Success = (Install-Dependencies -LogFile $logFile) }
      $setupResults += @{Name = "Frontend Files"; Success = (New-FrontendFiles -LogFile $logFile) }
      $setupResults += @{Name = "Run Script"; Success = (New-RunScript -LogFile $logFile) }
    }
    # Summary
    Write-Log -Message "=== SETUP SUMMARY ===" -Level INFO -LogFile $logFile
    $successCount = 0
    $failCount = 0
    foreach ($result in $setupResults) {
      if ($result.Success) {
        Write-Log -Message "$($result.Name) - SUCCESS" -Level SUCCESS -LogFile $logFile
        $successCount++
      }
      else {
        Write-Log -Message "$($result.Name) - FAILED" -Level ERROR -LogFile $logFile
        $failCount++
      }
    }
    Write-Log -Message "Setup Results: $successCount successful, $failCount failed" -Level INFO -LogFile $logFile
    if ($failCount -gt 0) {
      Write-Log -Message "Frontend setup had failures" -Level ERROR -LogFile $logFile
      Stop-Transcript
      exit 1
    }
  }
  if ($Configure -or $Run) {
    Write-Log -Message "Configuring frontend environment..." -Level INFO -LogFile $logFile
    Test-EnvironmentConfig -LogFile $logFile | Out-Null
  }
  if ($Test -or $Run) { Test-FrontendSetup -LogFile $logFile | Out-Null }
  # Cleanup .git folder and .gitignore if all setup is complete
  $gitFolderPath = ".\frontend\.git\"
  if (Test-Path $gitFolderPath) {
    try {
      Remove-Item -Path $gitFolderPath -Recurse -Force -ErrorAction Stop
      Write-Log -Message "Removed .git folder from frontend directory" -Level "SUCCESS" -LogFile $logFile
    }
    catch { Write-Log -Message "Failed to remove .git folder: $_" -Level "WARN" -LogFile $logFile }
  }
  $gitIgnorePath = ".\frontend\.gitignore"
  if (Test-Path $gitIgnorePath) {
    try {
      Remove-Item -Path $gitIgnorePath -Force -ErrorAction Stop
      Write-Log -Message "Removed .gitignore file from frontend directory" -Level "SUCCESS" -LogFile $logFile
    }
    catch { Write-Log -Message "Failed to remove .gitignore file: $_" -Level "WARN" -LogFile $logFile }
  }
  if ($Run) { Test-FrontendHealth -LogFile $logFile }
  else {
    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    Write-Log -Message "1. .\05-ReactFrontend.ps1 -Run        # Validate frontend health" -Level INFO -LogFile $logFile
    Write-Log -Message "2. .\run_frontend.ps1                 # Start development server" -Level INFO -LogFile $logFile
    Write-Log -Message "3. .\run_backend.ps1                  # Start backend (separate terminal)" -Level INFO -LogFile $logFile
    Write-Log -Message "" -Level INFO -LogFile $logFile
    Write-Log -Message "URLs:" -Level INFO -LogFile $logFile
    Write-Log -Message "Frontend: http://localhost:3000" -Level INFO -LogFile $logFile
    Write-Log -Message "Backend:  http://localhost:8000/docs" -Level INFO -LogFile $logFile
  }
}
catch {
  Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
  Stop-Transcript
  exit 1
}
Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript