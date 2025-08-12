# 05-ReactFrontend.ps1 - React Frontend Setup and Components
# Purpose: Set up Vite-based React TypeScript frontend with chat UI for JARVIS
# Last edit: 2025-08-06 - Manual inpection and alignments

param(
  [switch]$Install,
  [switch]$Configure,
  [switch]$Test,
  [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "5.0.0"
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
  Write-Log -Message "Testing prerequisites..." -Level INFO -LogFile $LogFile
  if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
    Write-Log -Message "Node.js not found in PATH." -Level ERROR -LogFile $LogFile
    return $false
  }
  if (-not (Get-Command "npm" -ErrorAction SilentlyContinue)) {
    Write-Log -Message "npm not found. Ensure Node.js is installed correctly." -Level ERROR -LogFile $LogFile
    return $false
  }
  Write-Log -Message "All prerequisites verified" -Level SUCCESS -LogFile $LogFile
  return $true
}

function Initialize-Frontend {
  param( [Parameter(Mandatory = $true)] [string]$FrontendDir, [string]$LogFile )
  if (-not (Test-Path $FrontendDir)) {
    Write-Log -Message "Creating Vite React TypeScript project..." -Level INFO -LogFile $LogFile
    try {
      $env:npm_config_yes = "true"
      npm create vite@latest frontend -- --template react-ts 2>&1 | Out-File -FilePath (Join-Path $logsDir "${scriptPrefix}-npm-$timestamp.log") -Append
      Write-Log -Message "Vite project created successfully" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create Vite project. Clear npm cache with 'npm cache clean --force' and retry." -Level ERROR -LogFile $logFile
      return $false
    }
  }
  else { Write-Log -Message "Frontend directory exists, skipping creation" -Level INFO -LogFile $LogFile }
  return $true
}

function Install-Frontend {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Installing frontend dependencies..." -Level INFO -LogFile $LogFile
  $frontendDir = Join-Path $projectRoot "frontend"
  if (-not (Initialize-Frontend -FrontendDir $frontendDir -LogFile $LogFile)) { return $false }
  $packageJson = Join-Path $frontendDir "package.json"
  $nodeModules = Join-Path $frontendDir "node_modules"
  if (Test-Path $packageJson) {
    # Test if dependencies exist, if not exist - install, if exist skip install - re-configure
    if (-not (Test-Path $nodeModules)) {
      Write-Log -Message "Installing base Vite dependencies..." -Level INFO -LogFile $LogFile
      try {
        # Install base Vite dependencies from package.json (working pattern)
        npm install --prefix frontend 2>&1 | Out-File -FilePath (Join-Path $logsDir "${scriptPrefix}-npm-$timestamp.log") -Append
        # Add JARVIS-specific dependencies (working pattern)
        npm install --prefix frontend axios lucide-react 2>&1 | Out-File -FilePath (Join-Path $logsDir "${scriptPrefix}-npm-$timestamp.log") -Append
        Write-Log -Message "Dependencies installed successfully" -Level SUCCESS -LogFile $LogFile
      }
      catch {
        Write-Log -Message "Failed to install dependencies. Check npm log at $logsDir\${scriptPrefix}-npm-$timestamp.log." -Level ERROR -LogFile $LogFile
        return $false
      }
    }
    else { Write-Log -Message "Dependencies installed, skipping npm install" -Level INFO -LogFile $LogFile }
  }
  else {
    Write-Log -Message "package.json not found, setup incomplete" -Level ERROR -LogFile $LogFile
    return $false
  }
  # Configure package.json with tsc script
  $packageJsonContent = Get-Content $packageJson -Raw | ConvertFrom-Json
  if (-not $packageJsonContent.scripts.tsc) {
    $packageJsonContent.scripts | Add-Member -Name "tsc" -Value "tsc" -MemberType NoteProperty -Force
    $packageJsonContent | ConvertTo-Json -Depth 10 | Set-Content $packageJson -Encoding UTF8
    Write-Log -Message "package.json updated with tsc script" -Level SUCCESS -LogFile $LogFile
  }
  else { Write-Log -Message "package.json tsc script already configured" -Level INFO -LogFile $LogFile }
  # Configure tsconfig.json
  $tsConfigContent = @"
{
  "compilerOptions": {
    "target": "ESNext",
    "lib": ["DOM", "DOM.Iterable", "ESNext"],
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "jsx": "react-jsx",
    "strict": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "allowImportingTsExtensions": true
  },
  "include": ["src"]
}
"@
  $tsConfigPath = Join-Path $frontendDir "tsconfig.json"
  if (-not (Test-Path $tsConfigPath) -or (Get-Content $tsConfigPath -Raw) -ne $tsConfigContent) {
    try {
      Set-Content -Path $tsConfigPath -Value $tsConfigContent -Encoding UTF8
      Write-Log -Message "tsconfig.json configured" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to configure tsconfig.json: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "tsconfig.json already correctly configured" -Level INFO -LogFile $LogFile }
  # Configure tsconfig.node.json
  $tsConfigNodeContent = @"
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "allowSyntheticDefaultImports": true,
    "composite": true,
    "tsBuildInfoFile": "./node_modules/.cache/tsbuildinfo",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": false
  },
  "include": ["vite.config.ts"]
}
"@
  $tsConfigNodePath = Join-Path $frontendDir "tsconfig.node.json"
  if (-not (Test-Path $tsConfigNodePath) -or (Get-Content $tsConfigNodePath -Raw) -ne $tsConfigNodeContent) {
    try {
      Set-Content -Path $tsConfigNodePath -Value $tsConfigNodeContent -Encoding UTF8
      Write-Log -Message "tsconfig.node.json configured" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to configure tsconfig.node.json: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "tsconfig.node.json already correctly configured" -Level INFO -LogFile $LogFile }
  return $true
}

function New-FrontendFiles {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Creating frontend files..." -Level INFO -LogFile $LogFile
  $frontendDir = Join-Path $projectRoot "frontend"
  $srcDir = Join-Path $frontendDir "src"
  $componentsDir = Join-Path $srcDir "components"
  $hooksDir = Join-Path $srcDir "hooks"
  $servicesDir = Join-Path $srcDir "services"
  $typesDir = Join-Path $srcDir "types"
  New-DirectoryStructure -Directories @($componentsDir, $hooksDir, $servicesDir, $typesDir) -LogFile $LogFile
  # index.html
  $indexHtmlContent = @"
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>JARVIS AI Assistant</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
"@
  $indexHtmlPath = Join-Path $frontendDir "index.html"
  if (-not (Test-Path $indexHtmlPath) -or (Get-Content $indexHtmlPath -Raw) -ne $indexHtmlContent) {
    try {
      Set-Content -Path $indexHtmlPath -Value $indexHtmlContent -Encoding UTF8
      Write-Log -Message "index.html created" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create index.html: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "index.html already correctly configured" -Level INFO -LogFile $LogFile }
  # vite.config.ts
  $viteConfigContent = @"
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
});
"@
  $viteConfigPath = Join-Path $frontendDir "vite.config.ts"
  if (-not (Test-Path $viteConfigPath) -or (Get-Content $viteConfigPath -Raw) -ne $viteConfigContent) {
    try {
      Set-Content -Path $viteConfigPath -Value $viteConfigContent -Encoding UTF8
      Write-Log -Message "vite.config.ts created" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create vite.config.ts: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "vite.config.ts already correctly configured" -Level INFO -LogFile $LogFile }
  # types/index.ts
  $typesContent = @"
export interface Message {
  id: string;
  content: string;
  sender: 'user' | 'jarvis';
  timestamp: string;
  mode?: 'system' | 'ai' | 'error';
  model?: string;
}

export interface AIStatus {
  ai_available: boolean;
  mode: string;
  model?: string;
}

export interface ChatResponse {
  response: string;
  timestamp: string;
  mode: string;
  model: string;
}
"@
  $typesPath = Join-Path $typesDir "index.ts"
  if (-not (Test-Path $typesPath) -or (Get-Content $typesPath -Raw) -ne $typesContent) {
    try {
      Set-Content -Path $typesPath -Value $typesContent -Encoding UTF8
      Write-Log -Message "types/index.ts created" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create types/index.ts: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "types/index.ts already correctly configured" -Level INFO -LogFile $LogFile }
  # services/api.ts
  $apiServiceContent = @"
import axios from 'axios';
import type { AIStatus, ChatResponse } from '../types/index.ts';

const api = axios.create({
  baseURL: '/api',
});

export class ApiService {
  static async getHealth(): Promise<void> {
    await api.get('/health');
  }

  static async getAIStatus(): Promise<AIStatus> {
    const response = await api.get('/status');
    return response.data;
  }

  static async sendMessage(content: string): Promise<ChatResponse> {
    const response = await api.post('/chat', { content });
    return response.data;
  }
}
"@
  $apiServicePath = Join-Path $servicesDir "api.ts"
  if (-not (Test-Path $apiServicePath) -or (Get-Content $apiServicePath -Raw) -ne $apiServiceContent) {
    try {
      Set-Content -Path $apiServicePath -Value $apiServiceContent -Encoding UTF8
      Write-Log -Message "services/api.ts created" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create services/api.ts: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "services/api.ts already correctly configured" -Level INFO -LogFile $LogFile }
  # hooks/useChat.ts
  $chatHookContent = @"
import { useState, useCallback, useEffect } from 'react';
import { ApiService } from '../services/api.ts';
import type { Message, AIStatus } from '../types/index.ts';

export function useChat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [aiStatus, setAIStatus] = useState<AIStatus | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const checkStatus = useCallback(async () => {
    try {
      await ApiService.getHealth();
      const aiStat = await ApiService.getAIStatus();
      setIsConnected(true);
      setAIStatus(aiStat);
      setError(null);
    } catch {
      setIsConnected(false);
      setError('Cannot connect to backend');
    }
  }, []);

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
    } catch {
      setError('Failed to get response');
      const errorMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: 'I apologize, but I am experiencing technical difficulties.',
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

  const clearChat = useCallback(() => {
    setMessages([]);
    setError(null);
  }, []);

  useEffect(() => {
    checkStatus();
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
  $chatHookPath = Join-Path $hooksDir "useChat.ts"
  if (-not (Test-Path $chatHookPath) -or (Get-Content $chatHookPath -Raw) -ne $chatHookContent) {
    try {
      Set-Content -Path $chatHookPath -Value $chatHookContent -Encoding UTF8
      Write-Log -Message "hooks/useChat.ts created" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create hooks/useChat.ts: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "hooks/useChat.ts already correctly configured" -Level INFO -LogFile $LogFile }
  # components/Chat.tsx
  $chatComponentContent = @"
import { useState, useRef, useEffect } from 'react';
import { Send, Bot, User, Wifi, WifiOff, Cpu } from 'lucide-react';
import { useChat } from '../hooks/useChat.ts';
import type { Message } from '../types/index.ts';

interface MessageBubbleProps {
  message: Message;
}

function MessageBubble({ message }: MessageBubbleProps) {
  const isUser = message.sender === 'user';
  const isError = message.mode === 'error';
  const isAI = message.mode === 'ai';

  return (
    <div style={{ marginBottom: '20px', display: 'flex', gap: '15px', alignItems: 'flex-start', width: '100%', flexDirection: isUser ? 'row-reverse' : 'row', justifyContent: isUser ? 'flex-start' : 'flex-start' }}>
      <div style={{ width: '40px', height: '40px', borderRadius: '50%', backgroundColor: isUser ? '#3b82f6' : isError ? '#ef4444' : '#00d4ff', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        {isUser ? <User size={20} color="white" /> : <Bot size={20} color={isUser || isError ? "white" : "#050810"} />}
      </div>
      <div style={{ background: isUser ? '#3b82f6' : isError ? '#7f1d1d' : isAI ? '#1a2332' : '#1a2332', color: isUser ? '#ffffff' : isError ? '#fecaca' : isAI ? '#00d4ff' : '#ffffff', padding: '20px 25px', borderRadius: '20px', maxWidth: '70%', fontSize: '18px', lineHeight: '1.6', border: isAI ? '2px solid rgba(0, 212, 255, 0.4)' : isError ? '2px solid #ef4444' : 'none' }}>
        <p style={{ margin: 0, fontSize: '18px', lineHeight: '1.6' }}>{message.content}</p>
        <div style={{ fontSize: '14px', opacity: 0.8, marginTop: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span>{new Date(message.timestamp).toLocaleTimeString()}</span>
          {message.mode && message.mode !== 'system' && (<><span>•</span><span style={{ textTransform: 'capitalize' }}>{message.mode}</span></>)}
          {message.model && message.model !== 'welcome' && (<><span>•</span><span>{message.model}</span></>)}
        </div>
      </div>
    </div>
  );
}

export function Chat() {
  const [input, setInput] = useState('');
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const { messages, isLoading, aiStatus, isConnected, error, sendMessage, clearChat, checkStatus } = useChat();

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
    <div style={{ width: '100%', maxWidth: '100vw', height: '100vh', display: 'flex', flexDirection: 'column', background: '#050810', color: '#ffffff', fontFamily: '-apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif', position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, margin: 0, padding: 0, overflow: 'hidden' }}>
      <div style={{ background: '#0a0e1a', color: '#ffffff', padding: '25px', borderBottom: '1px solid #1a2332', width: '100%', flexShrink: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
            <div style={{ position: 'relative' }}>
              <div style={{ width: '50px', height: '50px', backgroundColor: '#00d4ff', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Bot size={30} color="#050810" />
              </div>
              <div style={{ position: 'absolute', bottom: '-2px', right: '-2px', width: '18px', height: '18px', borderRadius: '50%', border: '3px solid #0a0e1a', backgroundColor: isConnected ? '#10b981' : '#ef4444' }} />
            </div>
            <div>
              <h1 style={{ color: '#00d4ff', fontSize: '32px', fontWeight: 'bold', margin: 0 }}>J.A.R.V.I.S.</h1>
              <p style={{ margin: '8px 0 0 0', fontSize: '18px', color: '#9ca3af' }}>{isConnected ? 'Connected' : 'Disconnected'} • {aiStatus?.mode || 'Unknown'}</p>
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '15px', flexShrink: 0 }}>
            <button onClick={checkStatus} style={{ background: 'none', border: 'none', color: '#ffffff', padding: '12px', cursor: 'pointer', borderRadius: '10px', flexShrink: 0 }} title="Check Connection">
              {isConnected ? <Wifi size={24} color="#10b981" /> : <WifiOff size={24} color="#ef4444" />}
            </button>
            {aiStatus && (
              <div style={{ padding: '12px 18px', borderRadius: '10px', display: 'flex', alignItems: 'center', gap: '10px', background: aiStatus.ai_available ? '#065f46' : '#92400e', color: aiStatus.ai_available ? '#10b981' : '#fbbf24', flexShrink: 0 }}>
                <Cpu size={18} />
                <span style={{ fontSize: '16px', fontWeight: '500' }}>{aiStatus.ai_available ? 'AI Online' : 'Echo Mode'}</span>
              </div>
            )}
            <button onClick={clearChat} style={{ background: '#1a2332', color: '#ffffff', border: 'none', padding: '12px 20px', borderRadius: '8px', cursor: 'pointer', fontSize: '16px', flexShrink: 0 }}>Clear</button>
          </div>
        </div>
        {error && (
          <div style={{ marginTop: '15px', padding: '15px', background: '#7f1d1d', border: '2px solid #ef4444', borderRadius: '10px', fontSize: '16px', color: '#fecaca' }}>
            {error}
          </div>
        )}
      </div>
      <div style={{ flex: 1, padding: '25px', overflowY: 'auto', background: '#050810', width: '100%', minHeight: 0 }}>
        {messages.map((message) => (
          <MessageBubble key={message.id} message={message} />
        ))}
        {isLoading && (
          <div style={{ display: 'flex', justifyContent: 'flex-start', marginBottom: '20px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
              <div style={{ width: '40px', height: '40px', backgroundColor: '#00d4ff', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Bot size={20} color="#050810" />
              </div>
              <div style={{ backgroundColor: '#1a2332', borderRadius: '20px', padding: '15px 20px' }}>
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
      <div style={{ background: '#0a0e1a', padding: '25px', borderTop: '1px solid #1a2332', width: '100%', flexShrink: 0 }}>
        <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '15px', width: '100%' }}>
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask Jarvis anything..."
            style={{ flex: 1, background: '#1a2332', border: '2px solid rgba(0, 212, 255, 0.4)', borderRadius: '15px', padding: '20px 25px', color: '#ffffff', fontSize: '18px', outline: 'none' }}
            disabled={isLoading || !isConnected}
          />
          <button
            type="submit"
            disabled={isLoading || !isConnected || !input.trim()}
            style={{ background: (!isLoading && isConnected && input.trim()) ? '#00d4ff' : '#6b7280', color: '#050810', border: 'none', borderRadius: '15px', padding: '20px 30px', cursor: (!isLoading && isConnected && input.trim()) ? 'pointer' : 'not-allowed', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}
          >
            <Send size={22} />
          </button>
        </form>
      </div>
    </div>
  );
}
"@
  $chatComponentPath = Join-Path $componentsDir "Chat.tsx"
  if (-not (Test-Path $chatComponentPath) -or (Get-Content $chatComponentPath -Raw) -ne $chatComponentContent) {
    try {
      Set-Content -Path $chatComponentPath -Value $chatComponentContent -Encoding UTF8
      Write-Log -Message "components/Chat.tsx created" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create components/Chat.tsx: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "components/Chat.tsx already correctly configured" -Level INFO -LogFile $LogFile }
  # App.tsx
  $appComponentContent = @"
import { Chat } from './components/Chat.tsx';

function App() {
  return <Chat />;
}

export default App;
"@
  $appComponentPath = Join-Path $srcDir "App.tsx"
  if (-not (Test-Path $appComponentPath) -or (Get-Content $appComponentPath -Raw) -ne $appComponentContent) {
    try {
      Set-Content -Path $appComponentPath -Value $appComponentContent -Encoding UTF8
      Write-Log -Message "App.tsx created" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create App.tsx: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "App.tsx already correctly configured" -Level INFO -LogFile $LogFile }
  # main.tsx
  $mainComponentContent = @"
import ReactDOM from 'react-dom/client';
import App from './App.tsx';

const root = document.getElementById('root');
if (root) {
  ReactDOM.createRoot(root).render(<App />);
} else {
  console.error('Root element not found');
}
"@
  $mainComponentPath = Join-Path $srcDir "main.tsx"
  if (-not (Test-Path $mainComponentPath) -or (Get-Content $mainComponentPath -Raw) -ne $mainComponentContent) {
    try {
      Set-Content -Path $mainComponentPath -Value $mainComponentContent -Encoding UTF8
      Write-Log -Message "main.tsx created" -Level SUCCESS -LogFile $LogFile
    }
    catch {
      Write-Log -Message "Failed to create main.tsx: $_" -Level ERROR -LogFile $LogFile
      return $false
    }
  }
  else { Write-Log -Message "main.tsx already correctly configured" -Level INFO -LogFile $LogFile }
  # run_frontend.ps1
  $runScriptContent = @"
# run_frontend.ps1 - Start React Frontend
# Purpose: Start Vite development server for JARVIS frontend
# Last edit: 2025-07-28 - Fixed syntax errors
`$ErrorActionPreference = "Stop"
`$frontendDir = Join-Path (Get-Location) "frontend"
if (-not (Test-Path (Join-Path `$frontendDir "package.json"))) {
    Write-Host "Frontend project not found. Run 05-ReactFrontend.ps1 first." -ForegroundColor Red
    exit 1
}
Push-Location `$frontendDir
try { npm run dev }
finally { Pop-Location }
"@
  $runScriptPath = Join-Path $projectRoot "run_frontend.ps1"
  if (-not (Test-Path $runScriptPath) -or (Get-Content $runScriptPath -Raw) -ne $runScriptContent) {
    try {
      Set-Content -Path $runScriptPath -Value $runScriptContent -Encoding UTF8
      Write-Log -Message "run_frontend.ps1 created" -Level SUCCESS -LogFile $logFile
    }
    catch {
      Write-Log -Message "Failed to create run_frontend.ps1: $_" -Level ERROR -LogFile $logFile
      return $false
    }
  }
  else { Write-Log -Message "run_frontend.ps1 already correctly configured" -Level INFO -LogFile $logFile }
  return $true
}

# Main execution
try {
  if (-not (Test-Prerequisites -LogFile $logFile)) {
    Stop-Transcript
    exit 1
  }
  $setupResults = @()
  if ($Install -or $Run) {
    $success = Install-Frontend -LogFile $logFile
    $setupResults += @{Name = "Frontend Setup"; Success = $success }
    if (-not $success) {
      Write-Log -Message "Frontend setup failed. Stopping execution." -Level ERROR -LogFile $logFile
      throw "Setup failed"
    }
    $setupResults += @{Name = "Frontend Files"; Success = (New-FrontendFiles -LogFile $logFile) }
  }
  Write-Log -Message "=== FINAL RESULTS ===" -Level INFO -LogFile $logFile
  $successCount = ($setupResults | Where-Object { $_.Success }).Count
  $failCount = ($setupResults | Where-Object { -not $_.Success }).Count
  Write-Log -Message "SUCCESS: $successCount components" -Level SUCCESS -LogFile $logFile
  if ($failCount -gt 0) {
    Write-Log -Message "FAILED: $failCount components" -Level ERROR -LogFile $logFile
  }
  foreach ($result in $setupResults) {
    $status = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }
    $level = if ($result.Success) { "SUCCESS" } else { "ERROR" }
    Write-Log -Message "$($result.Name): $status" -Level $level -LogFile $logFile
  }

  Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
  Write-Log -Message "1. To start the backend server: .\run_backend.ps1" -Level INFO -LogFile $logFile
  Write-Log -Message "2. To start the frontend server: .\run_frontend.ps1" -Level INFO -LogFile $logFile
}
catch {
  Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
  Stop-Transcript
  exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript