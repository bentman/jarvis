# 05-ReactFrontend.ps1 (v4) - React Frontend Setup for Jarvis AI Assistant
# JARVIS AI Assistant - Modern chat interface with real-time AI communication
# Enhanced with comprehensive logging and improved error handling following v4 standards
# Builds upon existing backend structure from scripts 01-04

param(
  [switch]$Install,
  [switch]$Build,
  [switch]$Run,
  [switch]$All
)

# Requires PowerShell 7+
#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# Get current directory as project root
$projectRoot = Get-Location

# Setup logging
$logsDir = "$projectRoot\logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptFile = "$logsDir\05-react-frontend-transcript-$timestamp.txt"
$logFile = "$logsDir\05-react-frontend-log-$timestamp.txt"

# Start PowerShell transcript
Start-Transcript -Path $transcriptFile

# Custom logging function with empty message handling
function Write-Log {
  param(
    [Parameter(Mandatory = $false)]
    [string]$Message = "",
    [string]$Level = "INFO"
  )
    
  # Handle empty messages (for spacing)
  if ([string]::IsNullOrWhiteSpace($Message)) {
    Write-Host ""
    Add-Content -Path $logFile -Value ""
    return
  }
    
  $logTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $logEntry = "[$logTimestamp] [$Level] $Message"
    
  # Write to console with appropriate color
  switch ($Level) {
    "ERROR" { Write-Host $logEntry -ForegroundColor Red }
    "WARN" { Write-Host $logEntry -ForegroundColor Yellow }
    "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
    "INFO" { Write-Host $logEntry -ForegroundColor Cyan }
    default { Write-Host $logEntry }
  }
    
  # Write to log file
  Add-Content -Path $logFile -Value $logEntry
}

# Log system information
function Write-SystemInfo {
  Write-Log "=== SYSTEM INFORMATION ===" "INFO"
  Write-Log "Script Version: 05-ReactFrontend.ps1 (v4)" "INFO"
  Write-Log "Timestamp: $(Get-Date)" "INFO"
  Write-Log "Project Root: $projectRoot" "INFO"
  Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" "INFO"
  Write-Log "User: $env:USERNAME" "INFO"
  Write-Log "Install Mode: $Install" "INFO"
  Write-Log "Build Mode: $Build" "INFO"
  Write-Log "Run Mode: $Run" "INFO"
  Write-Log "All Mode: $All" "INFO"
  Write-Log "=========================" "INFO"
}

# Function to check if command exists
function Test-Command {
  param([string]$Command)
  try {
    $null = Get-Command $Command -ErrorAction Stop
    return $true
  }
  catch {
    return $false
  }
}

# Function to test if Node.js is installed
function Test-NodeInstalled {
  return Test-Command "node"
}

# Function to test if backend exists
function Test-BackendExists {
  return (Test-Path "backend/api/main.py") -and (Test-Path "backend/services/ai_service.py") -and (Test-Path "run_backend.ps1")
}

# Function to get Node.js version
function Get-NodeVersion {
  try {
    $version = node --version 2>$null
    return $version
  }
  catch {
    return "version check failed"
  }
}

# Function to create frontend directory structure
function New-FrontendStructure {
  Write-Log "Creating React frontend structure..." "INFO"
    
  if (Test-Path "frontend") {
    Write-Log "Frontend directory already exists - checking for updates needed" "INFO"
        
    # Check if it's a valid React app
    if (-not (Test-Path "frontend/package.json")) {
      Write-Log "Invalid frontend directory found - recreating" "WARN"
      Remove-Item "frontend" -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
      Write-Log "Valid React app structure detected" "SUCCESS"
    }
  }
    
  if (-not (Test-Path "frontend")) {
    Write-Log "Creating new React app..." "INFO"
    Write-Log "This may take 2-5 minutes..." "WARN"
        
    try {
      # First, try with TypeScript template
      Write-Log "Attempting to create TypeScript React app..." "INFO"
            
      # Use cmd /c to execute npx properly on Windows
      $result = cmd /c "echo y | npx create-react-app frontend --template typescript 2>&1"
            
      if (-not (Test-Path "frontend/package.json")) {
        Write-Log "TypeScript template failed, trying basic React app..." "WARN"
                
        # Clean up any partial installation
        if (Test-Path "frontend") {
          Remove-Item "frontend" -Recurse -Force
        }
                
        # Try basic React app
        Write-Log "Creating basic React app..." "INFO"
        $result = cmd /c "echo y | npx create-react-app frontend 2>&1"
                
        if (-not (Test-Path "frontend/package.json")) {
          Write-Log "Failed to create React app. Output: $result" "ERROR"
          return $false
        }
      }
            
      Write-Log "React app created successfully" "SUCCESS"
    }
    catch {
      Write-Log "Failed to create React app: $($_.Exception.Message)" "ERROR"
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
    
  $createdCount = 0
  $existingCount = 0
    
  foreach ($dir in $directories) {
    if (!(Test-Path $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
      Write-Log "Created directory: $dir" "SUCCESS"
      $createdCount++
    }
    else {
      Write-Log "Directory exists: $dir" "INFO"
      $existingCount++
    }
  }
    
  Write-Log "Frontend structure ready: $createdCount created, $existingCount existing" "SUCCESS"
  return $true
}

# Function to install frontend dependencies
function Install-FrontendDependencies {
  Write-Log "Installing additional frontend dependencies..." "INFO"
    
  Push-Location
  try {
    Set-Location frontend
        
    # Check if dependencies are already installed
    if (Test-Path "node_modules") {
      $packageJson = Get-Content "package.json" | ConvertFrom-Json
      $hasRequiredDeps = $packageJson.dependencies."axios" -and $packageJson.dependencies."lucide-react"
            
      if ($hasRequiredDeps) {
        Write-Log "Required dependencies already installed" "SUCCESS"
        return $true
      }
    }
        
    # Install only essential dependencies (no Tailwind to avoid PostCSS issues)
    $packages = @(
      "@types/react",
      "@types/react-dom", 
      "axios",
      "lucide-react",
      "react-markdown"
    )
        
    Write-Log "Installing packages: $($packages -join ', ')" "INFO"
    $installResult = npm install @($packages) 2>&1
        
    if ($LASTEXITCODE -eq 0) {
      Write-Log "Frontend dependencies installed successfully" "SUCCESS"
      return $true
    }
    else {
      Write-Log "Some dependencies may have had issues but continuing..." "WARN"
      Write-Log "Install output: $installResult" "INFO"
            
      # Check if critical packages were installed
      $packageJson = Get-Content "package.json" | ConvertFrom-Json
      if ($packageJson.dependencies."axios" -and $packageJson.dependencies."lucide-react") {
        Write-Log "Critical dependencies installed successfully" "SUCCESS"
        return $true
      }
      else {
        Write-Log "Critical dependencies missing" "ERROR"
        return $false
      }
    }
  }
  catch {
    Write-Log "Failed to install frontend dependencies: $($_.Exception.Message)" "ERROR"
    return $false
  }
  finally {
    Pop-Location
  }
}

# Function to create styling and components (PRESERVE EXACT CSS)
function New-StylingAndComponents {
  Write-Log "Creating minimal CSS (inline styles used in components)..." "INFO"
    
  # CRITICAL: Preserve exact CSS from working version - DO NOT MODIFY
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
    
  try {
    Set-Content -Path "frontend/src/styles/index.css" -Value $minimalCSS
    Write-Log "Minimal CSS created (components use inline styles)" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Failed to create CSS file: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

# Function to create API service
function New-ApiService {
  Write-Log "Creating API service..." "INFO"
    
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
    Write-Log "API service created successfully" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Failed to create API service: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

# Function to create TypeScript types
function New-TypeDefinitions {
  Write-Log "Creating TypeScript types..." "INFO"
    
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
    Write-Log "TypeScript types created successfully" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Failed to create TypeScript types: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

# Function to create chat hook
function New-ChatHook {
  Write-Log "Creating chat hook..." "INFO"
    
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
    Write-Log "Chat hook created successfully" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Failed to create chat hook: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

# Function to create chat component (PRESERVE EXACT INLINE STYLES)
function New-ChatComponent {
  Write-Log "Creating chat component with inline styles..." "INFO"
    
  # CRITICAL: Preserve exact inline styles from working version - DO NOT MODIFY
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
    Write-Log "Full-screen inline-styled chat component created" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Failed to create chat component: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

# Function to create main App component
function New-AppComponent {
  Write-Log "Creating main App component..." "INFO"
    
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
    Write-Log "Main App component created successfully" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Failed to create main App component: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

# Function to create environment configuration
function New-EnvironmentConfig {
  Write-Log "Creating environment configuration..." "INFO"
    
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
    Write-Log "Environment file created successfully" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Failed to create environment file: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

# Function to update package.json scripts
function Update-PackageJsonScripts {
  Write-Log "Updating package.json scripts..." "INFO"
    
  Push-Location
  try {
    Set-Location frontend
        
    # Read existing package.json
    $packageJsonContent = Get-Content "package.json" -Raw
    $packageJson = $packageJsonContent | ConvertFrom-Json
        
    # Add custom scripts if they don't exist
    if (-not $packageJson.scripts."build:prod") {
      $packageJson.scripts | Add-Member -Type NoteProperty -Name "build:prod" -Value "npm run build" -Force
    }
    if (-not $packageJson.scripts."preview") {
      $packageJson.scripts | Add-Member -Type NoteProperty -Name "preview" -Value "npm run build && npx serve -s build -l 3000" -Force
    }
        
    # Convert back to JSON and save
    $updatedJson = $packageJson | ConvertTo-Json -Depth 10
    Set-Content "package.json" -Value $updatedJson
        
    Write-Log "Package.json scripts updated successfully" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Could not update package.json scripts: $($_.Exception.Message)" "WARN"
    return $false
  }
  finally {
    Pop-Location
  }
}

# Function to create frontend run script
function New-FrontendRunScript {
  Write-Log "Creating frontend run script..." "INFO"
    
  $runScript = @"
# run_frontend.ps1 - Start the React frontend (v4)
param(
    [switch]`$Build,
    [switch]`$Install,
    [switch]`$Dev
)

function Write-FrontendLog {
    param([string]`$Message, [string]`$Level = "INFO")
    `$timestamp = Get-Date -Format "HH:mm:ss"
    switch (`$Level) {
        "ERROR" { Write-Host "[`$timestamp] ❌ `$Message" -ForegroundColor Red }
        "WARN" { Write-Host "[`$timestamp] ⚠️  `$Message" -ForegroundColor Yellow }
        "SUCCESS" { Write-Host "[`$timestamp] ✅ `$Message" -ForegroundColor Green }
        "INFO" { Write-Host "[`$timestamp] 📍 `$Message" -ForegroundColor Cyan }
        default { Write-Host "[`$timestamp] `$Message" }
    }
}

if (`$Install) {
    Write-FrontendLog "Installing frontend dependencies..." "INFO"
    if (-not (Test-Path "frontend")) {
        Write-FrontendLog "Frontend directory not found" "ERROR"
        return
    }
    
    Push-Location frontend
    try {
        npm install
        if (`$LASTEXITCODE -eq 0) {
            Write-FrontendLog "Dependencies installed successfully" "SUCCESS"
        } else {
            Write-FrontendLog "Dependency installation had issues" "WARN"
        }
    } finally {
        Pop-Location
    }
    return
}

if (`$Build) {
    Write-FrontendLog "Building frontend for production..." "INFO"
    if (-not (Test-Path "frontend")) {
        Write-FrontendLog "Frontend directory not found" "ERROR"
        return
    }
    
    Push-Location frontend
    try {
        npm run build
        if (`$LASTEXITCODE -eq 0) {
            Write-FrontendLog "Build complete - files in frontend/build/" "SUCCESS"
        } else {
            Write-FrontendLog "Build failed" "ERROR"
        }
    } finally {
        Pop-Location
    }
    return
}

Write-FrontendLog "Starting Jarvis AI Frontend..." "SUCCESS"
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
    Write-FrontendLog "Backend detected - full functionality available" "SUCCESS"
} catch {
    Write-FrontendLog "Backend not detected - start it for full functionality" "WARN"
}

Write-Host ""

if (-not (Test-Path "frontend")) {
    Write-FrontendLog "Frontend directory not found - run .\05-ReactFrontend.ps1 -Install first" "ERROR"
    return
}

Write-FrontendLog "Starting React development server..." "INFO"

Push-Location frontend
try {
    npm start
} finally {
    Pop-Location
}
"@
    
  try {
    Set-Content -Path "run_frontend.ps1" -Value $runScript
    Write-Log "Frontend run script created successfully" "SUCCESS"
    return $true
  }
  catch {
    Write-Log "Failed to create frontend run script: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

# Function to build frontend for production
function Build-FrontendProduction {
  Write-Log "Building frontend for production..." "INFO"
    
  if (-not (Test-Path "frontend/package.json")) {
    Write-Log "Frontend not found - run setup first" "ERROR"
    return $false
  }
    
  Push-Location
  try {
    Set-Location frontend
        
    Write-Log "Running production build..." "INFO"
    $buildResult = npm run build 2>&1
        
    if ($LASTEXITCODE -eq 0) {
      Write-Log "Frontend production build completed successfully" "SUCCESS"
            
      # Check build output
      if (Test-Path "build") {
        $buildSize = (Get-ChildItem "build" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
        Write-Log "Build output: $('{0:N2}' -f $buildSize) MB in build/ directory" "INFO"
      }
      return $true
    }
    else {
      Write-Log "Frontend build failed" "ERROR"
      Write-Log "Build output: $buildResult" "ERROR"
      return $false
    }
  }
  catch {
    Write-Log "Exception during frontend build: $($_.Exception.Message)" "ERROR"
    return $false
  }
  finally {
    Pop-Location
  }
}

# Function to start development server
function Start-DevelopmentServer {
  Write-Log "Starting React development server..." "INFO"
    
  if (-not (Test-Path "frontend/package.json")) {
    Write-Log "Frontend not found - run setup first" "ERROR"
    return
  }
    
  Write-Log ""
  Write-Log "Starting Jarvis AI Frontend..." "SUCCESS"
  Write-Log ""
  Write-Log "Frontend URL: http://localhost:3000" "INFO"
  Write-Log "Backend URL: http://localhost:8000 (required for full functionality)" "INFO"
  Write-Log ""
    
  # Check if backend is running
  try {
    $response = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -TimeoutSec 3
    Write-Log "Backend detected - full functionality available" "SUCCESS"
  }
  catch {
    Write-Log "Backend not detected - start it for full functionality" "WARN"
    Write-Log "Run in another terminal: .\run_backend.ps1" "INFO"
  }
    
  Write-Log ""
  Write-Log "The development server will start and block this terminal." "WARN"
  Write-Log "Press Ctrl+C to stop the frontend server" "WARN"
  Write-Log ""
    
  $confirm = Read-Host "Ready to start the frontend development server? (Y/n)"
  if ($confirm -eq "" -or $confirm -eq "y" -or $confirm -eq "Y") {
    Write-Log "Starting development server in 3 seconds..." "INFO"
    Start-Sleep -Seconds 3
        
    Push-Location
    try {
      Set-Location frontend
      npm start
    }
    catch {
      Write-Log "Failed to start development server: $($_.Exception.Message)" "ERROR"
    }
    finally {
      Pop-Location
    }
  }
  else {
    Write-Log "Development server start cancelled. Run manually with: .\run_frontend.ps1" "SUCCESS"
  }
}

# Function to validate frontend setup
function Test-FrontendSetup {
  Write-Log "Validating frontend setup..." "INFO"
    
  $validationResults = @()
    
  # Check Node.js
  if (Test-NodeInstalled) {
    $nodeVersion = Get-NodeVersion
    $validationResults += "✅ Node.js: $nodeVersion"
  }
  else {
    $validationResults += "❌ Node.js: Not installed"
  }
    
  # Check backend dependencies
  if (Test-BackendExists) {
    $validationResults += "✅ Backend: AI-enhanced backend ready"
  }
  else {
    $validationResults += "❌ Backend: Missing (run scripts 02-04 first)"
  }
    
  # Check frontend structure
  $frontendChecks = @{
    "Frontend Directory"   = "frontend"
    "Package.json"         = "frontend/package.json"
    "Source Directory"     = "frontend/src"
    "Components Directory" = "frontend/src/components"
    "Chat Component"       = "frontend/src/components/Chat.tsx"
    "API Service"          = "frontend/src/services/api.ts"
    "Chat Hook"            = "frontend/src/hooks/useChat.ts"
    "Types"                = "frontend/src/types/index.ts"
    "Styles"               = "frontend/src/styles/index.css"
    "App Component"        = "frontend/src/App.tsx"
    "Index Component"      = "frontend/src/index.tsx"
    "Environment Config"   = "frontend/.env"
    "Frontend Run Script"  = "run_frontend.ps1"
  }
    
  foreach ($check in $frontendChecks.GetEnumerator()) {
    if (Test-Path $check.Value) {
      if (Test-Path $check.Value -PathType Leaf) {
        $size = (Get-Item $check.Value).Length
        $validationResults += "✅ $($check.Key): Ready ($size bytes)"
      }
      else {
        $validationResults += "✅ $($check.Key): Ready"
      }
    }
    else {
      $validationResults += "❌ $($check.Key): Missing"
    }
  }
    
  # Check npm dependencies if frontend exists
  if (Test-Path "frontend/package.json") {
    Push-Location
    try {
      Set-Location frontend
            
      # Check if node_modules exists
      if (Test-Path "node_modules") {
        $validationResults += "✅ Dependencies: node_modules installed"
                
        # Check critical packages
        $packageJson = Get-Content "package.json" | ConvertFrom-Json
        $criticalPackages = @("react", "axios", "lucide-react")
                
        foreach ($package in $criticalPackages) {
          if ($packageJson.dependencies.$package) {
            $validationResults += "✅ Package: $package"
          }
          else {
            $validationResults += "❌ Package: $package missing"
          }
        }
      }
      else {
        $validationResults += "❌ Dependencies: node_modules not found (run -Install)"
      }
    }
    catch {
      $validationResults += "⚠️  Dependencies: Could not verify packages"
    }
    finally {
      Pop-Location
    }
  }
    
  # Display results
  Write-Log ""
  Write-Log "=== FRONTEND VALIDATION RESULTS ===" "INFO"
  foreach ($result in $validationResults) {
    if ($result -like "✅*") {
      Write-Log $result "SUCCESS"
    }
    elseif ($result -like "⚠️*") {
      Write-Log $result "WARN"
    }
    else {
      Write-Log $result "ERROR"
    }
  }
    
  $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
  $warningCount = ($validationResults | Where-Object { $_ -like "⚠️*" }).Count
  $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
  $totalChecks = $validationResults.Count
    
  Write-Log ""
  Write-Log "=== VALIDATION SUMMARY ===" "INFO"
  if ($failureCount -eq 0 -and $warningCount -eq 0) {
    Write-Log "Frontend Validation Complete: $successCount/$totalChecks checks passed!" "SUCCESS"
    Write-Log "React frontend fully ready for Jarvis AI" "SUCCESS"
  }
  elseif ($failureCount -eq 0) {
    Write-Log "Frontend Validation: $successCount/$totalChecks ready, $warningCount warnings" "WARN"
    Write-Log "Core frontend functionality available" "SUCCESS"
  }
  else {
    Write-Log "Frontend Validation: $successCount/$totalChecks passed, $failureCount failed, $warningCount warnings" "ERROR"
    Write-Log "Some frontend components need attention" "ERROR"
  }
    
  return $failureCount -eq 0
}

# Main execution
Write-Log "JARVIS React Frontend Setup (v4) Starting..." "SUCCESS"
Write-SystemInfo

# Check prerequisites
if (-not (Test-NodeInstalled)) {
  Write-Log "Node.js not found. Please run 01-Prerequisites.ps1 first to install it." "ERROR"
  Stop-Transcript
  exit 1
}

if (-not (Test-BackendExists)) {
  Write-Log "Backend not found. Please run scripts 02-04 first to set up the backend." "ERROR"
  Stop-Transcript
  exit 1
}

# Check if frontend already exists and is complete
$frontendComplete = $false
if ((Test-Path "frontend/package.json") -and 
  (Test-Path "frontend/src/components/Chat.tsx") -and 
  (Test-Path "frontend/src/services/api.ts") -and 
  (Test-Path "run_frontend.ps1")) {
  Write-Log "Frontend already exists and appears complete" "SUCCESS"
  $frontendComplete = $true
}

# Default behavior: Setup frontend unless already complete OR specific switches used
$shouldSetup = $false
if ($Install -or $All) {
  $shouldSetup = $true
  Write-Log "Frontend setup requested via switches" "INFO"
}
elseif (-not $frontendComplete) {
  $shouldSetup = $true
  Write-Log "Frontend not complete - running default setup" "INFO"
}

# Setup operations (default behavior like scripts 01-04)
if ($shouldSetup) {
  Write-Log ""
  Write-Log "Setting up React frontend..." "INFO"
    
  $setupResults = @()
    
  $setupResults += @{Name = "Frontend Structure"; Success = (New-FrontendStructure) }
    
  if ($setupResults[-1].Success) {
    $setupResults += @{Name = "Frontend Dependencies"; Success = (Install-FrontendDependencies) }
    $setupResults += @{Name = "CSS Styling"; Success = (New-StylingAndComponents) }
    $setupResults += @{Name = "API Service"; Success = (New-ApiService) }
    $setupResults += @{Name = "TypeScript Types"; Success = (New-TypeDefinitions) }
    $setupResults += @{Name = "Chat Hook"; Success = (New-ChatHook) }
    $setupResults += @{Name = "Chat Component"; Success = (New-ChatComponent) }
    $setupResults += @{Name = "App Component"; Success = (New-AppComponent) }
    $setupResults += @{Name = "Environment Config"; Success = (New-EnvironmentConfig) }
    $setupResults += @{Name = "Package Scripts"; Success = (Update-PackageJsonScripts) }
    $setupResults += @{Name = "Run Script"; Success = (New-FrontendRunScript) }
        
    # Clean up any conflicting packages after component creation
    Push-Location
    try {
      Set-Location frontend
      Write-Log "Final cleanup of conflicting packages..." "INFO"
      $cleanupResult = npm uninstall tailwindcss @tailwindcss/typography @tailwindcss/postcss autoprefixer postcss framer-motion --silent 2>$null
      Remove-Item "tailwind.config.js" -Force -ErrorAction SilentlyContinue
      Remove-Item "postcss.config.js" -Force -ErrorAction SilentlyContinue
      Write-Log "Package cleanup completed" "SUCCESS"
    }
    catch {
      Write-Log "Package cleanup had minor issues (this is normal)" "INFO"
    }
    finally {
      Pop-Location
    }
  }
    
  # Setup summary
  Write-Log ""
  Write-Log "=== SETUP SUMMARY ===" "INFO"
    
  $successfulSetups = 0
  $failedSetups = 0
    
  foreach ($result in $setupResults) {
    if ($result.Success) {
      Write-Log "$($result.Name) - SUCCESS" "SUCCESS"
      $successfulSetups++
    }
    else {
      Write-Log "$($result.Name) - FAILED" "ERROR"
      $failedSetups++
    }
  }
    
  Write-Log ""
  Write-Log "Setup Results: $successfulSetups successful, $failedSetups failed" "INFO"
    
  if ($successfulSetups -gt 0 -and $failedSetups -eq 0) {
    Write-Log "Frontend setup completed with inline-styled components!" "SUCCESS"
  }
  elseif ($successfulSetups -gt 0) {
    Write-Log "Frontend setup completed with some issues" "WARN"
  }
  else {
    Write-Log "Frontend setup failed" "ERROR"
    Stop-Transcript
    exit 1
  }
}

# Build operations
if ($Build -or $All) {
  Write-Log ""
  if ($shouldSetup -or (Test-Path "frontend/package.json")) {
    Build-FrontendProduction | Out-Null
  }
  else {
    Write-Log "Skipping build - frontend not available" "WARN"
  }
}

# Always show comprehensive validation
Write-Log ""
Test-FrontendSetup | Out-Null

# Run operations (like 02-SimpleFastApiBackend.ps1)
if ($Run -or $All) {
  Write-Log ""
  if ($shouldSetup -or (Test-Path "frontend/package.json")) {
    Start-DevelopmentServer
  }
  else {
    Write-Log "Cannot start server - frontend not available" "WARN"
  }
}

# Next steps guidance (only show if no setup was performed and switches weren't used)
if (-not $shouldSetup -and -not ($Build -or $Run -or $All)) {
  Write-Log ""
  Write-Log "=== NEXT STEPS ===" "INFO"
  Write-Log "Frontend is already set up. Available actions:" "INFO"
  Write-Log "1. .\05-ReactFrontend.ps1 -Build        # Build for production" "INFO"
  Write-Log "2. .\05-ReactFrontend.ps1 -Run          # Start frontend server" "INFO"
  Write-Log ""
  Write-Log "Daily usage scripts:" "INFO"
  Write-Log "   .\run_backend.ps1   # Terminal 1" "INFO"
  Write-Log "   .\run_frontend.ps1  # Terminal 2" "INFO"
}
else {
  # Show next steps after setup (like 02-SimpleFastApiBackend.ps1)
  if (-not ($Run -or $All)) {
    Write-Log ""
    Write-Log "=== NEXT STEPS ===" "INFO"
    Write-Log "1. .\05-ReactFrontend.ps1 -Build        # Build for production" "INFO"
    Write-Log "2. .\05-ReactFrontend.ps1 -Run          # Start frontend server" "INFO"
    Write-Log ""
    Write-Log "Or run everything:" "INFO"
    Write-Log ".\05-ReactFrontend.ps1 -All" "INFO"
    Write-Log ""
    Write-Log "Daily usage scripts:" "INFO"
    Write-Log "   .\run_backend.ps1   # Terminal 1" "INFO"
    Write-Log "   .\run_frontend.ps1  # Terminal 2" "INFO"
  }
}

# Show system ready status if everything looks good
$currentValidation = Test-FrontendSetup
if ($currentValidation -and (Test-Path "frontend/src/components/Chat.tsx")) {
  Write-Log ""
  Write-Log "System Ready - Quick Start Commands:" "SUCCESS"
  Write-Log "# Start both servers (use separate terminals):" "INFO"
  Write-Log ".\run_backend.ps1" "INFO"
  Write-Log ".\run_frontend.ps1" "INFO"
  Write-Log ""
  Write-Log "# Then visit:" "INFO"
  Write-Log "http://localhost:3000    # Chat Interface" "INFO"
  Write-Log "http://localhost:8000/docs # API Documentation" "INFO"
}

Write-Log ""
Write-Log "Log Files Created:" "INFO"
Write-Log "Full transcript: $transcriptFile" "INFO"
Write-Log "Structured log: $logFile" "INFO"

Write-Log ""
Write-Log "JARVIS React Frontend Setup (v4) Complete!" "SUCCESS"

# Stop transcript
Stop-Transcript