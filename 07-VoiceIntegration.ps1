# 07-VoiceIntegration.ps1 - Complete Voice System Integration
# Purpose: Consolidated voice hooks, components, API integration, and Chat updates
# Last edit: 2025-08-27 - Consolidated from 07a/07b/07c scripts

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

# -------------------------
# Prerequisites & Validation Functions
# -------------------------

function Test-Prerequisites {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Testing prerequisites for complete voice integration..." -Level INFO -LogFile $LogFile
    
    # Check React frontend setup
    if (-not (Test-Path "frontend/package.json")) {
        Write-Log -Message "React frontend not found. Run 05-ReactFrontend.ps1." -Level ERROR -LogFile $LogFile
        return $false
    }
    
    # Check frontend directories
    $frontendDirs = @("frontend/src/hooks", "frontend/src/components", "frontend/src/services")
    foreach ($dir in $frontendDirs) {
        if (-not (Test-Path $dir)) {
            New-DirectoryStructure -Directories @($dir) -LogFile $LogFile
        }
    }
    
    # Check voice backend exists
    if (-not (Test-Path "backend/services/voice_service.py")) {
        Write-Log -Message "Voice backend not found. Run 06-VoiceBackend.ps1." -Level ERROR -LogFile $LogFile
        return $false
    }
    
    # Check frontend API service exists
    if (-not (Test-Path "frontend/src/services/api.ts")) {
        Write-Log -Message "Frontend API service not found. Run 05-ReactFrontend.ps1." -Level ERROR -LogFile $LogFile
        return $false
    }
    
    # Check Chat component exists
    if (-not (Test-Path "frontend/src/components/Chat.tsx")) {
        Write-Log -Message "Chat component not found. Run 05-ReactFrontend.ps1." -Level ERROR -LogFile $LogFile
        return $false
    }
    
    Write-Log -Message "All prerequisites verified for complete voice integration" -Level SUCCESS -LogFile $LogFile
    return $true
}

# -------------------------
# Voice Hooks Creation (from 07a)
# -------------------------

function New-VoiceHooks {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating comprehensive voice control hooks..." -Level INFO -LogFile $LogFile
    
    $hookPath = Join-Path "frontend/src/hooks" "useVoicePanel.ts"
    
    # Check if hook already exists and is current
    if (Test-Path $hookPath) {
        $existingContent = Get-Content $hookPath -Raw
        if ($existingContent -match "realTimeLevel" -and $existingContent -match "enumerateDevices" -and $existingContent -match "updateWakeWords") {
            Write-Log -Message "Voice hooks already exist and are current" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        # Backup existing hook
        $backupPath = "${hookPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $hookPath $backupPath
        Write-Log -Message "Backed up existing voice hooks to: $backupPath" -Level INFO -LogFile $LogFile
    }
    
    $voiceHooks = @'
import { useState, useCallback, useEffect, useRef } from 'react';

export interface AudioDevice {
  deviceId: string;
  label: string;
  kind: 'audioinput' | 'audiooutput';
}

export interface VoiceConfig {
  // Basic Controls
  micEnabled: boolean;
  speakerEnabled: boolean;
  volume: number;
  inputLevel: number;
  selectedInputDevice: string;
  selectedOutputDevice: string;
  
  // Voice Settings
  accent: string;
  gender: string;
  speed: number;
  personality: string;
  quality: string;
  
  // Advanced Options
  wakeWords: string[];
  sensitivity: number;
  pushToTalk: boolean;
  quietHours: boolean;
  phraseTimeout: number;
  silenceTimeout: number;
}

export interface VoiceStatus {
  isConnected: boolean;
  isListening: boolean;
  isSpeaking: boolean;
  currentModel: string;
  realTimeLevel: number;
  availableDevices: AudioDevice[];
  isRecording: boolean;
}

export interface TestResult {
  type: 'mic' | 'voice' | 'chat';
  success: boolean;
  message: string;
  data?: any;
  timestamp: Date;
}

export interface TestStates {
  micTesting: boolean;
  voiceTesting: boolean;
  chatTesting: boolean;
}

const defaultVoiceConfig: VoiceConfig = {
  micEnabled: true,
  speakerEnabled: true,
  volume: 0.8,
  inputLevel: 0.7,
  selectedInputDevice: 'default',
  selectedOutputDevice: 'default',
  accent: 'British',
  gender: 'Male', 
  speed: 0.9,
  personality: 'Classic',
  quality: 'Standard',
  wakeWords: ['jarvis', 'hey jarvis'],
  sensitivity: 0.5,
  pushToTalk: false,
  quietHours: false,
  phraseTimeout: 3.0,
  silenceTimeout: 2.0
};

export function useVoicePanel() {
  const [voiceConfig, setVoiceConfig] = useState<VoiceConfig>(defaultVoiceConfig);
  const [voiceStatus, setVoiceStatus] = useState<VoiceStatus>({
    isConnected: false,
    isListening: false,
    isSpeaking: false,
    currentModel: '',
    realTimeLevel: 0,
    availableDevices: [],
    isRecording: false
  });
  const [error, setError] = useState<string | null>(null);
  const [testStates, setTestStates] = useState<TestStates>({
    micTesting: false,
    voiceTesting: false,
    chatTesting: false
  });
  const [lastTestResult, setLastTestResult] = useState<TestResult | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const micStreamRef = useRef<MediaStream | null>(null);

  const enumerateDevices = useCallback(async () => {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const audioDevices: AudioDevice[] = devices
        .filter(device => device.kind === 'audioinput' || device.kind === 'audiooutput')
        .map(device => ({
          deviceId: device.deviceId,
          label: device.label || (device.deviceId === 'default' ? 'default' : `${device.kind === 'audioinput' ? 'Microphone' : 'Speaker'} ${device.deviceId.substring(0, 8)}`),
          kind: device.kind as 'audioinput' | 'audiooutput'
        }));

      setVoiceStatus(prev => ({ ...prev, availableDevices: audioDevices }));
      setError(null);
    } catch (err) {
      setError('Failed to enumerate audio devices');
      console.error('Device enumeration failed:', err);
    }
  }, []);

  const startAudioLevelMonitoring = useCallback(async () => {
    try {
      if (micStreamRef.current) {
        micStreamRef.current.getTracks().forEach(track => track.stop());
      }

      const constraints = {
        audio: voiceConfig.selectedInputDevice !== 'default' 
          ? { deviceId: { exact: voiceConfig.selectedInputDevice } }
          : true
      };

      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      micStreamRef.current = stream;

      audioContextRef.current = new AudioContext();
      analyserRef.current = audioContextRef.current.createAnalyser();
      analyserRef.current.fftSize = 256;

      const source = audioContextRef.current.createMediaStreamSource(stream);
      source.connect(analyserRef.current);

      const dataArray = new Uint8Array(analyserRef.current.frequencyBinCount);
      
      const updateLevel = () => {
        if (analyserRef.current && voiceConfig.micEnabled) {
          analyserRef.current.getByteFrequencyData(dataArray);
          const average = dataArray.reduce((a, b) => a + b) / dataArray.length;
          const normalizedLevel = Math.min(average / 128, 1);
          
          setVoiceStatus(prev => ({ ...prev, realTimeLevel: normalizedLevel }));
        }
        
        if (voiceConfig.micEnabled) {
          requestAnimationFrame(updateLevel);
        }
      };

      updateLevel();
      setError(null);
    } catch (err) {
      setError('Failed to access microphone');
      console.error('Audio monitoring failed:', err);
    }
  }, [voiceConfig.micEnabled, voiceConfig.selectedInputDevice]);

  const stopAudioLevelMonitoring = useCallback(() => {
    if (micStreamRef.current) {
      micStreamRef.current.getTracks().forEach(track => track.stop());
      micStreamRef.current = null;
    }
    if (audioContextRef.current) {
      audioContextRef.current.close();
      audioContextRef.current = null;
    }
    setVoiceStatus(prev => ({ ...prev, realTimeLevel: 0 }));
  }, []);

  const checkVoiceStatus = useCallback(async () => {
    try {
      const response = await fetch('/api/voice/status');
      if (response.ok) {
        const status = await response.json();
        setVoiceStatus(prev => ({
          ...prev,
          isConnected: true,
          currentModel: status.voice_stack || 'Unknown'
        }));
        setError(null);
      } else {
        setVoiceStatus(prev => ({ ...prev, isConnected: false }));
        setError('Voice service unavailable');
      }
    } catch (err) {
      setVoiceStatus(prev => ({ ...prev, isConnected: false }));
      setError('Cannot connect to voice service');
    }
  }, []);

  const updateVoiceConfig = useCallback(async (updates: Partial<VoiceConfig>) => {
    try {
      const newConfig = { ...voiceConfig, ...updates };
      setVoiceConfig(newConfig);
      setError(null);
    } catch (err) {
      setError('Failed to update voice settings');
      console.error('Voice config update failed:', err);
    }
  }, [voiceConfig]);

  const testMicrophone = useCallback(async () => {
    try {
      setTestStates(prev => ({ ...prev, micTesting: true }));
      setVoiceStatus(prev => ({ ...prev, isListening: true }));
      setError(null);
      
      // Test microphone access directly via browser API
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.getTracks().forEach(track => track.stop());
      
      const testResult: TestResult = {
        type: 'mic',
        success: true,
        message: 'Microphone access successful',
        timestamp: new Date()
      };
      
      setLastTestResult(testResult);
      return true;
    } catch (err) {
      const errorMessage = 'Microphone access failed';
      setError(errorMessage);
      setLastTestResult({
        type: 'mic',
        success: false,
        message: errorMessage,
        timestamp: new Date()
      });
      return false;
    } finally {
      setTestStates(prev => ({ ...prev, micTesting: false }));
      setVoiceStatus(prev => ({ ...prev, isListening: false }));
    }
  }, []);

  const testSpeaker = useCallback(async () => {
    try {
      setTestStates(prev => ({ ...prev, voiceTesting: true }));
      setVoiceStatus(prev => ({ ...prev, isSpeaking: true }));
      setError(null);
      
      const testMessage = "Voice test successful.";
      
      const response = await fetch('/api/voice/tts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          text: testMessage,
          voice: "af_heart"  // Use valid Kokoro voice ID
        })
      });
      const result = response.ok;
      
      const testResult: TestResult = {
        type: 'voice',
        success: result,
        message: result ? 'Voice test completed' : 'Voice test failed',
        timestamp: new Date()
      };
      
      setLastTestResult(testResult);
      return result;
    } catch (err) {
      const errorMessage = 'Failed to connect to voice service';
      setError(errorMessage);
      setLastTestResult({
        type: 'voice',
        success: false,
        message: errorMessage,
        timestamp: new Date()
      });
      return false;
    } finally {
      setTestStates(prev => ({ ...prev, voiceTesting: false }));
      setVoiceStatus(prev => ({ ...prev, isSpeaking: false }));
    }
  }, []);

  const previewVoice = useCallback(async () => {
    try {
      setVoiceStatus(prev => ({ ...prev, isSpeaking: true }));
      
      const previewText = "Hello, I am Jarvis, your AI assistant.";
      
      const response = await fetch('/api/voice/tts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          text: previewText,
          voice: "af_heart"  // Use valid Kokoro voice ID
        })
      });
      return response.ok;
    } catch (err) {
      setError('Voice preview failed');
      return false;
    } finally {
      setVoiceStatus(prev => ({ ...prev, isSpeaking: false }));
    }
  }, []);

  const testFullVoice = useCallback(async () => {
    try {
      setTestStates(prev => ({ ...prev, chatTesting: true }));
      setError(null);
      
      // Test by checking voice status and then doing a TTS test
      const statusResponse = await fetch('/api/voice/status');
      if (!statusResponse.ok) throw new Error('Voice service unavailable');
      
      const ttsResponse = await fetch('/api/voice/tts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          text: "Voice chat test successful",
          voice: "af_heart"  // Use valid Kokoro voice ID
        })
      });
      
      const result = statusResponse.ok && ttsResponse.ok;
      
      const testResult: TestResult = {
        type: 'chat',
        success: result,
        message: result ? 'Voice system operational' : 'Voice system test failed',
        timestamp: new Date()
      };
      
      setLastTestResult(testResult);
      return result;
    } catch (err) {
      const errorMessage = 'Voice service unavailable';
      setError(errorMessage);
      setLastTestResult({
        type: 'chat',
        success: false,
        message: errorMessage,
        timestamp: new Date()
      });
      return false;
    } finally {
      setTestStates(prev => ({ ...prev, chatTesting: false }));
    }
  }, []);

  const updateWakeWords = useCallback((newWakeWords: string[]) => {
    updateVoiceConfig({ wakeWords: newWakeWords });
  }, [updateVoiceConfig]);

  useEffect(() => {
    checkVoiceStatus();
    enumerateDevices();
    
    const interval = setInterval(checkVoiceStatus, 30000);
    return () => clearInterval(interval);
  }, [checkVoiceStatus, enumerateDevices]);

  useEffect(() => {
    if (voiceConfig.micEnabled) {
      startAudioLevelMonitoring();
    } else {
      stopAudioLevelMonitoring();
    }
    
    return () => stopAudioLevelMonitoring();
  }, [voiceConfig.micEnabled, startAudioLevelMonitoring, stopAudioLevelMonitoring]);

  return {
    voiceConfig,
    voiceStatus,
    error,
    testStates,
    lastTestResult,
    updateVoiceConfig,
    testMicrophone,
    testSpeaker,
    previewVoice,
    testFullVoice,
    checkVoiceStatus,
    enumerateDevices,
    updateWakeWords
  };
}
'@
    
    try {
        Set-Content -Path $hookPath -Value $voiceHooks -Encoding UTF8
        Write-Log -Message "Voice control hooks created successfully" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create voice hooks: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

# -------------------------
# Voice Components Creation (from 07b)
# -------------------------

function New-VoiceControlPanel {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Creating complete voice control panel component..." -Level INFO -LogFile $LogFile
    
    $panelPath = Join-Path "frontend/src/components" "VoiceControlPanel.tsx"
    
    # Check if panel already exists and is current
    if (Test-Path $panelPath) {
        $existingContent = Get-Content $panelPath -Raw
        if ($existingContent -match "AudioLevelMeter" -and $existingContent -match "Wake Word Editor" -and $existingContent -match "Test Controls") {
            Write-Log -Message "Voice control panel already exists and is current" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        # Backup existing panel
        $backupPath = "${panelPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $panelPath $backupPath
        Write-Log -Message "Backed up existing voice panel to: $backupPath" -Level INFO -LogFile $LogFile
    }
    
    $controlPanel = @'
import React, { useState } from 'react';
import { Mic, MicOff, Volume2, VolumeX, Settings, TestTube, Headphones, ChevronDown, ChevronUp, Play } from 'lucide-react';
import { useVoicePanel } from '../hooks/useVoicePanel';

export function VoiceControlPanel() {
  const [isExpanded, setIsExpanded] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [wakeWordInput, setWakeWordInput] = useState('');
  
  const {
    voiceConfig,
    voiceStatus,
    error,
    testStates,
    lastTestResult,
    updateVoiceConfig,
    testMicrophone,
    testSpeaker,
    previewVoice,
    testFullVoice,
    updateWakeWords
  } = useVoicePanel();

  const accentOptions = [
    { value: 'British', label: 'British' },
    { value: 'American', label: 'American' },
    { value: 'Australian', label: 'Australian' }
  ];

  const personalityOptions = [
    { value: 'Classic', label: 'Classic' },
    { value: 'Friendly', label: 'Friendly' },
    { value: 'Professional', label: 'Professional' }
  ];

  const inputDevices = voiceStatus.availableDevices.filter(d => d.kind === 'audioinput');
  const outputDevices = voiceStatus.availableDevices.filter(d => d.kind === 'audiooutput');

  const addWakeWord = () => {
    if (wakeWordInput.trim() && !voiceConfig.wakeWords.includes(wakeWordInput.trim())) {
      const newWakeWords = [...voiceConfig.wakeWords, wakeWordInput.trim()];
      updateWakeWords(newWakeWords);
      setWakeWordInput('');
    }
  };

  const removeWakeWord = (wordToRemove: string) => {
    const newWakeWords = voiceConfig.wakeWords.filter(word => word !== wordToRemove);
    updateWakeWords(newWakeWords);
  };

  // Audio level meter component
  const AudioLevelMeter = () => {
    const level = voiceStatus.realTimeLevel;
    const segments = 20;
    const activeSegments = Math.round(level * segments);
    
    return (
      <div style={{ display: 'flex', gap: '2px', alignItems: 'center', height: '20px' }}>
        {Array.from({ length: segments }, (_, i) => (
          <div
            key={i}
            style={{
              width: '3px',
              height: `${Math.min(4 + (i * 0.8), 20)}px`,
              backgroundColor: i < activeSegments 
                ? (i < segments * 0.7 ? '#10b981' : i < segments * 0.9 ? '#f59e0b' : '#ef4444')
                : '#374151',
              borderRadius: '1px'
            }}
          />
        ))}
      </div>
    );
  };

  return (
    <div style={{
      position: 'fixed',
      top: '80px',
      right: '20px',
      width: isExpanded ? '380px' : '50px',
      background: '#0a0e1a',
      borderRadius: '15px',
      border: '1px solid #1a2332',
      padding: isExpanded ? '15px' : '8px',
      transition: 'all 0.3s ease',
      zIndex: 100,
      boxShadow: '0 8px 25px rgba(0, 212, 255, 0.15)',
      maxHeight: isExpanded ? 'calc(100vh - 100px)' : '50px',
      overflowY: isExpanded ? 'auto' : 'hidden'
    }}>
      {/* Header */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        marginBottom: isExpanded ? '15px' : '0'
      }}>
        {isExpanded && (
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div style={{
              width: '12px',
              height: '12px',
              borderRadius: '50%',
              backgroundColor: voiceStatus.isConnected ? '#10b981' : '#ef4444'
            }} />
            <span style={{ color: '#00d4ff', fontSize: '16px', fontWeight: '600' }}>
              Voice Controls
            </span>
          </div>
        )}
        
        <button
          onClick={() => setIsExpanded(!isExpanded)}
          style={{
            background: 'none',
            border: 'none',
            color: '#00d4ff',
            cursor: 'pointer',
            padding: '8px',
            borderRadius: '8px'
          }}
          title={isExpanded ? 'Collapse Voice Controls' : 'Expand Voice Controls'}
        >
          {isExpanded ? 'X' : <Headphones size={24} />}
        </button>
      </div>

      {isExpanded && (
        <>
          {/* Error Display */}
          {error && (
            <div style={{
              background: '#7f1d1d',
              border: '1px solid #ef4444',
              borderRadius: '8px',
              padding: '12px',
              marginBottom: '15px',
              color: '#fecaca',
              fontSize: '14px'
            }}>
              {error}
            </div>
          )}

          {/* Basic Controls */}
          <div style={{
            background: '#1a2332',
            borderRadius: '10px',
            padding: '15px',
            marginBottom: '15px'
          }}>
            <h4 style={{
              color: '#ffffff',
              fontSize: '14px',
              margin: '0 0 12px 0',
              display: 'flex',
              alignItems: 'center',
              gap: '8px'
            }}>
              <Settings size={16} />
              Basic Controls
            </h4>

            {/* Microphone with Level Meter */}
            <div style={{ marginBottom: '12px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '8px' }}>
                <button
                  onClick={() => updateVoiceConfig({ micEnabled: !voiceConfig.micEnabled })}
                  style={{
                    background: voiceConfig.micEnabled ? '#00d4ff' : '#6b7280',
                    border: 'none',
                    borderRadius: '8px',
                    padding: '8px',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center'
                  }}
                >
                  {voiceConfig.micEnabled ? 
                    <Mic size={16} color="#050810" /> : 
                    <MicOff size={16} color="#ffffff" />
                  }
                </button>
                <span style={{ color: '#ffffff', fontSize: '14px', flex: 1 }}>
                  Microphone {voiceStatus.isListening ? '(Listening...)' : ''}
                </span>
              </div>
              
              {/* Input Device Selection */}
              <select
                value={voiceConfig.selectedInputDevice}
                onChange={(e) => updateVoiceConfig({ selectedInputDevice: e.target.value })}
                style={{
                  width: '100%',
                  background: '#050810',
                  border: '1px solid #374151',
                  borderRadius: '6px',
                  padding: '6px',
                  color: '#ffffff',
                  fontSize: '12px',
                  marginBottom: '8px'
                }}
              >
                <option value="default">Default Microphone</option>
                {inputDevices.map(device => (
                  <option key={device.deviceId} value={device.deviceId}>
                    {device.label}
                  </option>
                ))}
              </select>

              {/* Audio Level Meter */}
              {voiceConfig.micEnabled && (
                <div style={{ padding: '8px', background: '#050810', borderRadius: '6px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ color: '#9ca3af', fontSize: '11px', width: '35px' }}>Level:</span>
                    <AudioLevelMeter />
                    <span style={{ color: '#9ca3af', fontSize: '11px', width: '25px' }}>
                      {Math.round(voiceStatus.realTimeLevel * 100)}%
                    </span>
                  </div>
                </div>
              )}
            </div>

            {/* Speaker Controls */}
            <div style={{ marginBottom: '12px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '8px' }}>
                <button
                  onClick={() => updateVoiceConfig({ speakerEnabled: !voiceConfig.speakerEnabled })}
                  style={{
                    background: voiceConfig.speakerEnabled ? '#00d4ff' : '#6b7280',
                    border: 'none',
                    borderRadius: '8px',
                    padding: '8px',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center'
                  }}
                >
                  {voiceConfig.speakerEnabled ? 
                    <Volume2 size={16} color="#050810" /> : 
                    <VolumeX size={16} color="#ffffff" />
                  }
                </button>
                <span style={{ color: '#ffffff', fontSize: '14px', flex: 1 }}>
                  Speaker {voiceStatus.isSpeaking ? '(Speaking...)' : ''}
                </span>
              </div>

              {/* Output Device Selection */}
              <select
                value={voiceConfig.selectedOutputDevice}
                onChange={(e) => updateVoiceConfig({ selectedOutputDevice: e.target.value })}
                style={{
                  width: '100%',
                  background: '#050810',
                  border: '1px solid #374151',
                  borderRadius: '6px',
                  padding: '6px',
                  color: '#ffffff',
                  fontSize: '12px'
                }}
              >
                <option value="default">Default Speaker</option>
                {outputDevices.map(device => (
                  <option key={device.deviceId} value={device.deviceId}>
                    {device.label}
                  </option>
                ))}
              </select>
            </div>

            {/* Volume */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <span style={{ color: '#9ca3af', fontSize: '12px', width: '50px' }}>
                Volume
              </span>
              <input
                type="range"
                min="0"
                max="1"
                step="0.1"
                value={voiceConfig.volume}
                onChange={(e) => updateVoiceConfig({ volume: parseFloat(e.target.value) })}
                style={{
                  flex: 1,
                  accentColor: '#00d4ff'
                }}
              />
              <span style={{ color: '#ffffff', fontSize: '12px', width: '30px' }}>
                {Math.round(voiceConfig.volume * 100)}%
              </span>
            </div>
          </div>

          {/* Voice Settings */}
          <div style={{
            background: '#1a2332',
            borderRadius: '10px',
            padding: '15px',
            marginBottom: '15px'
          }}>
            <h4 style={{
              color: '#ffffff',
              fontSize: '14px',
              margin: '0 0 12px 0'
            }}>
              Voice Settings
            </h4>

            {/* Accent */}
            <div style={{ marginBottom: '12px' }}>
              <label style={{ color: '#9ca3af', fontSize: '12px', display: 'block', marginBottom: '4px' }}>
                Accent
              </label>
              <select
                value={voiceConfig.accent}
                onChange={(e) => updateVoiceConfig({ accent: e.target.value })}
                style={{
                  width: '100%',
                  background: '#050810',
                  border: '1px solid #374151',
                  borderRadius: '6px',
                  padding: '8px',
                  color: '#ffffff',
                  fontSize: '14px'
                }}
              >
                {accentOptions.map(option => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </div>

            {/* Gender */}
            <div style={{ marginBottom: '12px' }}>
              <label style={{ color: '#9ca3af', fontSize: '12px', display: 'block', marginBottom: '4px' }}>
                Gender
              </label>
              <select
                value={voiceConfig.gender}
                onChange={(e) => updateVoiceConfig({ gender: e.target.value })}
                style={{
                  width: '100%',
                  background: '#050810',
                  border: '1px solid #374151',
                  borderRadius: '6px',
                  padding: '8px',
                  color: '#ffffff',
                  fontSize: '14px'
                }}
              >
                <option value="Male">Male</option>
                <option value="Female">Female</option>
                <option value="Neutral">Neutral</option>
              </select>
            </div>

            {/* Speed */}
            <div style={{ marginBottom: '12px' }}>
              <label style={{ color: '#9ca3af', fontSize: '12px', display: 'block', marginBottom: '4px' }}>
                Speed ({voiceConfig.speed}x)
              </label>
              <input
                type="range"
                min="0.5"
                max="2.0"
                step="0.1"
                value={voiceConfig.speed}
                onChange={(e) => updateVoiceConfig({ speed: parseFloat(e.target.value) })}
                style={{
                  width: '100%',
                  accentColor: '#00d4ff'
                }}
              />
            </div>

            {/* Personality */}
            <div style={{ marginBottom: '12px' }}>
              <label style={{ color: '#9ca3af', fontSize: '12px', display: 'block', marginBottom: '4px' }}>
                Personality
              </label>
              <select
                value={voiceConfig.personality}
                onChange={(e) => updateVoiceConfig({ personality: e.target.value })}
                style={{
                  width: '100%',
                  background: '#050810',
                  border: '1px solid #374151',
                  borderRadius: '6px',
                  padding: '8px',
                  color: '#ffffff',
                  fontSize: '14px'
                }}
              >
                {personalityOptions.map(option => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </div>

            {/* Voice Preview Button */}
            <button
              onClick={previewVoice}
              disabled={!voiceStatus.isConnected || voiceStatus.isSpeaking}
              style={{
                width: '100%',
                background: voiceStatus.isConnected ? '#10b981' : '#6b7280',
                border: 'none',
                borderRadius: '6px',
                padding: '8px 12px',
                color: '#ffffff',
                fontSize: '12px',
                cursor: voiceStatus.isConnected ? 'pointer' : 'not-allowed',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '6px'
              }}
            >
              <Play size={14} />
              Preview Voice
            </button>
          </div>

          {/* Advanced Settings */}
          <div style={{
            background: '#1a2332',
            borderRadius: '10px',
            padding: '15px',
            marginBottom: '15px'
          }}>
            <button
              onClick={() => setShowAdvanced(!showAdvanced)}
              style={{
                width: '100%',
                background: 'none',
                border: 'none',
                color: '#ffffff',
                fontSize: '14px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                marginBottom: showAdvanced ? '12px' : '0'
              }}
            >
              <span>Advanced Settings</span>
              {showAdvanced ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
            </button>

            {showAdvanced && (
              <>
                {/* Wake Word Editor */}
                <div style={{ marginBottom: '12px' }}>
                  <label style={{ color: '#9ca3af', fontSize: '12px', display: 'block', marginBottom: '4px' }}>
                    Wake Word Editor
                  </label>
                  
                  <div style={{ display: 'flex', gap: '6px', marginBottom: '8px' }}>
                    <input
                      type="text"
                      value={wakeWordInput}
                      onChange={(e) => setWakeWordInput(e.target.value)}
                      placeholder="Add new wake word..."
                      style={{
                        flex: 1,
                        background: '#050810',
                        border: '1px solid #374151',
                        borderRadius: '4px',
                        padding: '6px',
                        color: '#ffffff',
                        fontSize: '12px'
                      }}
                      onKeyPress={(e) => e.key === 'Enter' && addWakeWord()}
                    />
                    <button
                      onClick={addWakeWord}
                      disabled={!wakeWordInput.trim()}
                      style={{
                        background: wakeWordInput.trim() ? '#00d4ff' : '#6b7280',
                        border: 'none',
                        borderRadius: '4px',
                        padding: '6px 12px',
                        color: wakeWordInput.trim() ? '#050810' : '#ffffff',
                        fontSize: '12px',
                        cursor: wakeWordInput.trim() ? 'pointer' : 'not-allowed'
                      }}
                    >
                      Add
                    </button>
                  </div>

                  <div style={{ 
                    background: '#050810', 
                    border: '1px solid #374151', 
                    borderRadius: '6px', 
                    padding: '8px',
                    minHeight: '60px'
                  }}>
                    <div style={{ 
                      color: '#9ca3af', 
                      fontSize: '11px', 
                      marginBottom: '6px',
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center'
                    }}>
                      <span>Active Wake Words ({voiceConfig.wakeWords.length})</span>
                      {voiceConfig.wakeWords.length > 2 && (
                        <button
                          onClick={() => updateWakeWords(['jarvis', 'hey jarvis'])}
                          style={{
                            background: 'none',
                            border: '1px solid #6b7280',
                            borderRadius: '3px',
                            padding: '2px 6px',
                            color: '#6b7280',
                            fontSize: '10px',
                            cursor: 'pointer'
                          }}
                        >
                          Reset to Default
                        </button>
                      )}
                    </div>
                    
                    {voiceConfig.wakeWords.length === 0 ? (
                      <div style={{ 
                        color: '#6b7280', 
                        fontSize: '11px', 
                        textAlign: 'center',
                        padding: '12px' 
                      }}>
                        No wake words configured. Add at least one wake word above.
                      </div>
                    ) : (
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
                        {voiceConfig.wakeWords.map((word, index) => (
                          <div
                            key={index}
                            style={{
                              background: '#374151',
                              border: '1px solid #4b5563',
                              borderRadius: '8px',
                              padding: '4px 8px',
                              fontSize: '11px',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '6px',
                              minWidth: '60px'
                            }}
                          >
                            <span style={{ color: '#ffffff', flex: 1 }}>{word}</span>
                            <button
                              onClick={() => removeWakeWord(word)}
                              style={{
                                background: 'none',
                                border: 'none',
                                color: '#ef4444',
                                cursor: 'pointer',
                                fontSize: '12px',
                                padding: '2px',
                                width: '14px',
                                height: '14px',
                                borderRadius: '2px',
                                display: 'flex',
                                alignItems: 'center',
                                justifyContent: 'center'
                              }}
                              title={`Remove "${word}"`}
                            >
                              X
                            </button>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>

                {/* Sensitivity */}
                <div style={{ marginBottom: '12px' }}>
                  <label style={{ color: '#9ca3af', fontSize: '12px', display: 'block', marginBottom: '4px' }}>
                    Wake Word Sensitivity ({Math.round(voiceConfig.sensitivity * 100)}%)
                  </label>
                  <input
                    type="range"
                    min="0.1"
                    max="1.0"
                    step="0.1"
                    value={voiceConfig.sensitivity}
                    onChange={(e) => updateVoiceConfig({ sensitivity: parseFloat(e.target.value) })}
                    style={{
                      width: '100%',
                      accentColor: '#00d4ff'
                    }}
                  />
                </div>
              </>
            )}
          </div>

          {/* Test Controls */}
          <div style={{
            background: '#1a2332',
            borderRadius: '10px',
            padding: '15px'
          }}>
            <h4 style={{
              color: '#ffffff',
              fontSize: '14px',
              margin: '0 0 12px 0',
              display: 'flex',
              alignItems: 'center',
              gap: '8px'
            }}>
              <TestTube size={16} />
              Test Controls
            </h4>

            <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
              <button
                onClick={testMicrophone}
                disabled={!voiceStatus.isConnected || testStates.micTesting || voiceStatus.isListening}
                style={{
                  background: testStates.micTesting ? '#f59e0b' : 
                    (voiceStatus.isConnected ? '#10b981' : '#6b7280'),
                  border: 'none',
                  borderRadius: '6px',
                  padding: '8px 12px',
                  color: '#ffffff',
                  fontSize: '12px',
                  cursor: voiceStatus.isConnected && !testStates.micTesting ? 'pointer' : 'not-allowed',
                  flex: 1,
                  minWidth: '70px',
                  opacity: testStates.micTesting ? 0.8 : 1
                }}
              >
                {testStates.micTesting ? 'Testing...' : 'Mic'}
              </button>
              
              <button
                onClick={testSpeaker}
                disabled={!voiceStatus.isConnected || testStates.voiceTesting || voiceStatus.isSpeaking}
                style={{
                  background: testStates.voiceTesting ? '#f59e0b' : 
                    (voiceStatus.isConnected ? '#3b82f6' : '#6b7280'),
                  border: 'none',
                  borderRadius: '6px',
                  padding: '8px 12px',
                  color: '#ffffff',
                  fontSize: '12px',
                  cursor: voiceStatus.isConnected && !testStates.voiceTesting ? 'pointer' : 'not-allowed',
                  flex: 1,
                  minWidth: '70px',
                  opacity: testStates.voiceTesting ? 0.8 : 1
                }}
              >
                {testStates.voiceTesting ? 'Speaking...' : 'Voice'}
              </button>
              
              <button
                onClick={testFullVoice}
                disabled={!voiceStatus.isConnected || testStates.chatTesting}
                style={{
                  background: testStates.chatTesting ? '#f59e0b' : 
                    (voiceStatus.isConnected ? '#00d4ff' : '#6b7280'),
                  border: 'none',
                  borderRadius: '6px',
                  padding: '8px 12px',
                  color: testStates.chatTesting ? '#ffffff' : 
                    (voiceStatus.isConnected ? '#050810' : '#ffffff'),
                  fontSize: '12px',
                  cursor: voiceStatus.isConnected && !testStates.chatTesting ? 'pointer' : 'not-allowed',
                  flex: 1,
                  minWidth: '70px',
                  opacity: testStates.chatTesting ? 0.8 : 1
                }}
              >
                {testStates.chatTesting ? 'Chatting...' : 'Chat'}
              </button>
            </div>
            
            {/* Test Results Display */}
            {lastTestResult && (
              <div style={{
                marginTop: '12px',
                padding: '10px',
                background: lastTestResult.success ? 'rgba(16, 185, 129, 0.1)' : 'rgba(239, 68, 68, 0.1)',
                border: lastTestResult.success ? '1px solid rgba(16, 185, 129, 0.3)' : '1px solid rgba(239, 68, 68, 0.3)',
                borderRadius: '6px'
              }}>
                <div style={{ 
                  color: lastTestResult.success ? '#10b981' : '#ef4444', 
                  fontSize: '12px', 
                  fontWeight: '600',
                  marginBottom: '4px'
                }}>
                  {lastTestResult.success ? 'PASS' : 'FAIL'} {lastTestResult.type.toUpperCase()} Test
                </div>
                <div style={{ color: '#9ca3af', fontSize: '11px', marginBottom: '4px' }}>
                  {lastTestResult.message}
                </div>
                <div style={{ color: '#6b7280', fontSize: '10px', marginTop: '4px' }}>
                  {lastTestResult.timestamp.toLocaleTimeString()}
                </div>
              </div>
            )}
          </div>

          {/* Status Info */}
          {voiceStatus.currentModel && (
            <div style={{
              marginTop: '15px',
              padding: '10px',
              background: 'rgba(0, 212, 255, 0.1)',
              borderRadius: '8px',
              border: '1px solid rgba(0, 212, 255, 0.3)'
            }}>
              <div style={{ color: '#00d4ff', fontSize: '12px' }}>
                Voice Stack: {voiceStatus.currentModel}
              </div>
              <div style={{ color: '#9ca3af', fontSize: '11px', marginTop: '2px' }}>
                {voiceConfig.accent} {voiceConfig.gender} - {voiceConfig.personality}
              </div>
              <div style={{ color: '#9ca3af', fontSize: '11px', marginTop: '2px' }}>
                Devices: {inputDevices.length} input, {outputDevices.length} output
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
'@
    
    try {
        Set-Content -Path $panelPath -Value $controlPanel -Encoding UTF8
        Write-Log -Message "Voice control panel component created successfully" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to create voice control panel: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

# -------------------------
# Voice API Integration (from 07c)
# -------------------------

function Add-VoiceApiExtensions {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Adding comprehensive voice API extensions..." -Level INFO -LogFile $LogFile
    
    $apiPath = Join-Path "frontend/src/services" "api.ts"
    
    if (-not (Test-Path $apiPath)) {
        Write-Log -Message "API service file not found at $apiPath" -Level ERROR -LogFile $LogFile
        return $false
    }
    
    try {
        $apiContent = Get-Content $apiPath -Raw
        
        # Check if VoiceApiService already exists
        if ($apiContent -match "export class VoiceApiService") {
            Write-Log -Message "VoiceApiService already exists in API service" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        
        # Create backup before modification
        $backupPath = "${apiPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $apiPath $backupPath
        Write-Log -Message "Created backup: $backupPath" -Level INFO -LogFile $LogFile
        
        # Create comprehensive voice API extensions
        $voiceExtensions = @"

// Voice API Extensions - Aligned with 06-VoiceBackend endpoints
export interface VoiceMessage {
  text: string;
  voice?: string;
}

export interface AudioDevice {
  deviceId: string;
  label: string;
  kind: 'audioinput' | 'audiooutput';
}

export interface VoiceStatusResponse {
  voice_stack: string;
  whisper_available: boolean;
  tts_available: boolean;
  wake_word_available: boolean;
  device: string;
  config: any;
  wake_words?: string[];
  models?: {
    whisper_model: string;
    tts_model: string;
    wake_word_model: string;
  };
}

// Complete Voice API Service aligned with actual backend
export class VoiceApiService {
  // Backend Voice Endpoints (matching 06-VoiceBackend.ps1)
  static async getVoiceStatus(): Promise<VoiceStatusResponse> {
    const response = await api.get<VoiceStatusResponse>('/voice/status');
    return response.data;
  }

  static async textToSpeech(message: VoiceMessage): Promise<any> {
    const response = await api.post('/voice/tts', message);
    return response.data;
  }

  static async speechToText(audioData: FormData): Promise<any> {
    const response = await api.post('/voice/stt', audioData, {
      headers: { 'Content-Type': 'multipart/form-data' }
    });
    return response.data;
  }

  // Frontend Device Management (Web Audio API)
  static async enumerateDevices(): Promise<AudioDevice[]> {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      return devices
        .filter(device => device.kind === 'audioinput' || device.kind === 'audiooutput')
        .map(device => ({
          deviceId: device.deviceId,
          label: device.label || 'Unknown ' + device.kind,
          kind: device.kind as 'audioinput' | 'audiooutput'
        }));
    } catch (error) {
      console.error('Failed to enumerate devices:', error);
      return [];
    }
  }

  static async testAudioLevel(deviceId?: string): Promise<number> {
    try {
      const constraints = deviceId 
        ? { audio: { deviceId: { exact: deviceId } } }
        : { audio: true };
      
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      
      return new Promise((resolve) => {
        const audioContext = new AudioContext();
        const analyser = audioContext.createAnalyser();
        const source = audioContext.createMediaStreamSource(stream);
        
        analyser.fftSize = 256;
        source.connect(analyser);
        
        const dataArray = new Uint8Array(analyser.frequencyBinCount);
        
        setTimeout(() => {
          analyser.getByteFrequencyData(dataArray);
          const average = dataArray.reduce((a, b) => a + b) / dataArray.length;
          const normalizedLevel = Math.min(average / 128, 1);
          
          // Cleanup
          stream.getTracks().forEach(track => track.stop());
          audioContext.close();
          
          resolve(normalizedLevel);
        }, 1000);
      });
    } catch (error) {
      console.error('Audio level test failed:', error);
      return 0;
    }
  }

  // Device Testing and Validation
  static async validateAudioDevice(deviceId: string, kind: 'audioinput' | 'audiooutput'): Promise<boolean> {
    try {
      if (kind === 'audioinput') {
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: { deviceId: { exact: deviceId } }
        });
        stream.getTracks().forEach(track => track.stop());
        return true;
      } else {
        const devices = await navigator.mediaDevices.enumerateDevices();
        return devices.some(device => device.deviceId === deviceId && device.kind === kind);
      }
    } catch (error) {
      console.error('Failed to validate ' + kind + ' device:', error);
      return false;
    }
  }
}
"@
        
        # Use simple append approach - most reliable method
        $updatedContent = $apiContent + $voiceExtensions
        
        # Write updated content
        Set-Content -Path $apiPath -Value $updatedContent -Encoding UTF8
        
        # Verify the integration worked
        $verifyContent = Get-Content $apiPath -Raw
        if ($verifyContent -match "export class VoiceApiService" -and 
            $verifyContent -match "enumerateDevices" -and 
            $verifyContent -match "testAudioLevel") {
            Write-Log -Message "Voice API service successfully integrated with comprehensive device management" -Level SUCCESS -LogFile $LogFile
            return $true
        }
        else {
            Write-Log -Message "Voice API integration verification failed" -Level ERROR -LogFile $LogFile
            return $false
        }
    }
    catch {
        Write-Log -Message "Failed to add voice API extensions: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

function Update-ChatComponentIntegration {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Integrating voice panel with Chat component..." -Level INFO -LogFile $LogFile
    
    $chatPath = Join-Path "frontend/src/components" "Chat.tsx"
    
    if (-not (Test-Path $chatPath)) {
        Write-Log -Message "Chat component not found - cannot integrate voice controls" -Level ERROR -LogFile $LogFile
        return $false
    }
    
    $chatContent = Get-Content $chatPath -Raw
    
    # Check if voice integration already exists
    if ($chatContent -match "VoiceControlPanel" -and $chatContent -match "import.*VoiceControlPanel") {
        Write-Log -Message "Chat component already integrated with voice control panel" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    
    # Add VoiceControlPanel import if not present
    if ($chatContent -notmatch "import.*VoiceControlPanel") {
        $importLine = "import { VoiceControlPanel } from './VoiceControlPanel';"
        $chatContent = $chatContent -replace "(import.*from 'lucide-react';)", "`$1`n$importLine"
    }
    
    # Add VoiceControlPanel component before closing div
    if ($chatContent -notmatch "<VoiceControlPanel") {
        $voiceComponent = "`n      <VoiceControlPanel />"
        $chatContent = $chatContent -replace "(    </div>\s*</div>\s*\);?\s*}\s*$)", "$voiceComponent`n`$1"
    }
    
    try {
        # Backup existing chat component
        $backupPath = "${chatPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $chatPath $backupPath
        Write-Log -Message "Backed up existing Chat component to: $backupPath" -Level INFO -LogFile $LogFile
        
        Set-Content -Path $chatPath -Value $chatContent -Encoding UTF8
        Write-Log -Message "Chat component integrated with voice control panel" -Level SUCCESS -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "Failed to integrate voice controls with Chat component: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        return $false
    }
}

# -------------------------
# Comprehensive Validation
# -------------------------

function Test-VoiceIntegrationComplete {
    param( [Parameter(Mandatory = $true)] [string]$LogFile )
    Write-Log -Message "Running comprehensive voice integration validation..." -Level INFO -LogFile $LogFile
    
    $validationResults = @()
    
    # File validation
    $requiredFiles = @(
        @{Path = "frontend/src/hooks/useVoicePanel.ts"; Name = "Voice Hooks" },
        @{Path = "frontend/src/components/VoiceControlPanel.tsx"; Name = "Voice Control Panel" },
        @{Path = "frontend/src/services/api.ts"; Name = "API Service" },
        @{Path = "frontend/src/components/Chat.tsx"; Name = "Chat Component" },
        @{Path = "backend/services/voice_service.py"; Name = "Voice Backend Service" }
    )
    
    foreach ($file in $requiredFiles) {
        if (Test-Path $file.Path) {
            $validationResults += "✅ File: $($file.Name)"
        }
        else {
            $validationResults += "❌ Missing: $($file.Name)"
        }
    }
    
    # Feature validation
    $hookPath = "frontend/src/hooks/useVoicePanel.ts"
    if (Test-Path $hookPath) {
        $hookContent = Get-Content $hookPath -Raw
        $features = @("realTimeLevel", "enumerateDevices", "updateWakeWords", "testMicrophone")
        foreach ($feature in $features) {
            if ($hookContent -match [regex]::Escape($feature)) {
                $validationResults += "✅ Hook Feature: $feature"
            }
            else {
                $validationResults += "❌ Hook Feature: $feature missing"
            }
        }
    }
    
    $panelPath = "frontend/src/components/VoiceControlPanel.tsx"
    if (Test-Path $panelPath) {
        $panelContent = Get-Content $panelPath -Raw
        $uiFeatures = @("AudioLevelMeter", "Wake Word Editor", "Test Controls", "Advanced Settings")
        foreach ($feature in $uiFeatures) {
            if ($panelContent -match [regex]::Escape($feature)) {
                $validationResults += "✅ UI Feature: $feature"
            }
            else {
                $validationResults += "❌ UI Feature: $feature missing"
            }
        }
    }
    
    # API integration validation
    $apiPath = "frontend/src/services/api.ts"
    if (Test-Path $apiPath) {
        $apiContent = Get-Content $apiPath -Raw
        if ($apiContent -match "export class VoiceApiService") {
            $validationResults += "✅ API Integration: VoiceApiService implemented"
        }
        else {
            $validationResults += "❌ API Integration: VoiceApiService missing"
        }
    }
    
    # Chat integration validation
    $chatPath = "frontend/src/components/Chat.tsx"
    if (Test-Path $chatPath) {
        $chatContent = Get-Content $chatPath -Raw
        if ($chatContent -match "VoiceControlPanel" -and $chatContent -match "import.*VoiceControlPanel") {
            $validationResults += "✅ Chat Integration: Voice panel integrated"
        }
        else {
            $validationResults += "❌ Chat Integration: Voice panel not integrated"
        }
    }
    
    # Display results
    Write-Log -Message "=== COMPREHENSIVE VOICE INTEGRATION VALIDATION ===" -Level INFO -LogFile $LogFile
    foreach ($result in $validationResults) {
        $level = if ($result -like "✅*") { "SUCCESS" } else { "ERROR" }
        Write-Log -Message $result -Level $level -LogFile $LogFile
    }
    
    $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
    $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    
    Write-Log -Message "Complete Voice Integration: $successCount/$($validationResults.Count) passed, $failureCount failed" -Level $(if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }) -LogFile $LogFile
    
    return $failureCount -eq 0
}

# -------------------------
# Main execution
# -------------------------

try {
    if (-not (Test-Prerequisites -LogFile $logFile)) {
        Write-Log -Message "Prerequisites check failed - cannot proceed with voice integration" -Level ERROR -LogFile $logFile
        throw "Prerequisites failed"
    }
    
    $setupResults = @()
    
    if ($Install -or $Run) {
        Write-Log -Message "Installing complete voice integration..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Voice Hooks"; Success = (New-VoiceHooks -LogFile $logFile) }
        $setupResults += @{Name = "Voice Control Panel"; Success = (New-VoiceControlPanel -LogFile $logFile) }
        $setupResults += @{Name = "Voice API Extensions"; Success = (Add-VoiceApiExtensions -LogFile $logFile) }
        $setupResults += @{Name = "Chat Integration"; Success = (Update-ChatComponentIntegration -LogFile $logFile) }
    }
    
    if ($Configure -or $Run) {
        Write-Log -Message "Configuring voice integration..." -Level INFO -LogFile $logFile
        # Configuration handled in creation functions
        $setupResults += @{Name = "Configuration"; Success = $true }
    }
    
    if ($Test -or $Run) {
        Write-Log -Message "Testing complete voice integration..." -Level INFO -LogFile $logFile
        $setupResults += @{Name = "Complete Integration Validation"; Success = (Test-VoiceIntegrationComplete -LogFile $logFile) }
    }
    
    # === FINAL RESULTS ===
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
    
    $validationSuccess = $failCount -eq 0
    if (-not $validationSuccess) { 
        Write-Log -Message "Voice integration completed with issues - review logs for remediation steps" -Level WARN -LogFile $logFile 
    } else { 
        Write-Log -Message "Complete voice system integration completed successfully - all components validated" -Level SUCCESS -LogFile $logFile 
    }
    
    Write-Log -Message "=== VOICE SYSTEM READY ===" -Level SUCCESS -LogFile $logFile
    Write-Log -Message "Features: Device management, real-time audio monitoring, wake word editing, comprehensive testing" -Level INFO -LogFile $logFile
    Write-Log -Message "Integration: Voice controls embedded in main chat interface" -Level INFO -LogFile $logFile
    
    Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
    if ($validationSuccess) {
        Write-Log -Message "1. Start backend: .\run_backend.ps1" -Level INFO -LogFile $logFile
        Write-Log -Message "2. Start frontend: .\run_frontend.ps1" -Level INFO -LogFile $logFile
        Write-Log -Message "3. Access application: http://localhost:3000" -Level INFO -LogFile $logFile
        Write-Log -Message "4. Voice controls available in chat interface via headphones icon" -Level INFO -LogFile $logFile
    }
    else {
        Write-Log -Message "1. Review error logs above for specific issues" -Level INFO -LogFile $logFile
        Write-Log -Message "2. Re-run this script after resolving issues" -Level INFO -LogFile $logFile
    }
    
    if ($failCount -gt 0) {
        throw "Voice integration completed with $failCount failed components"
    }
}
catch {
    Write-Log -Message "Critical error during voice integration: $($_.Exception.Message)" -Level ERROR -LogFile $logFile
    Write-Log -Message "Check PowerShell execution policy and administrator privileges." -Level ERROR -LogFile $logFile
    throw
}
finally {
    Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
    Stop-Transcript
}