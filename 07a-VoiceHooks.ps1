# 07a-VoiceHooks.ps1 - Voice TypeScript Hooks and Interfaces
# Purpose: Create React hooks for voice control with device management and real-time monitoring
# Last edit: 2025-08-06 - Manual inpection and alignments

param(
  [switch]$Install,
  [switch]$Configure,
  [switch]$Test,
  [switch]$Run
)

$ErrorActionPreference = "Stop"
. .\00-CommonUtils.ps1

$scriptVersion = "3.0.0"
$scriptPrefix = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$projectRoot = Get-Location
$logsDir = Join-Path $projectRoot "logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcriptFile = Join-Path $logsDir "${scriptPrefix}-transcript-$timestamp.txt"
$logFile = Join-Path $logsDir "${scriptPrefix}-log-$timestamp.txt"

New-DirectoryStructure -Directories @($logsDir) -LogFile $logFile
Start-Transcript -Path $transcriptFile
Write-Log -Message "=== $($MyInvocation.MyCommand.Name) v$scriptVersion ===" -Level INFO -LogFile $logFile

# Set default mode
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
  Write-Log -Message "Testing prerequisites for voice hooks..." -Level INFO -LogFile $LogFile
    
  # Check React frontend setup
  if (-not (Test-Path "frontend/package.json")) {
    Write-Log -Message "React frontend not found. Run 05-ReactFrontend.ps1." -Level ERROR -LogFile $LogFile
    return $false
  }
    
  # Check hooks directory exists
  if (-not (Test-Path "frontend/src/hooks")) {
    New-DirectoryStructure -Directories @("frontend/src/hooks") -LogFile $LogFile
  }
    
  Write-Log -Message "All prerequisites verified for voice hooks" -Level SUCCESS -LogFile $LogFile
  return $true
}

function New-ComprehensiveVoiceHook {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Creating comprehensive voice control hook with device management..." -Level INFO -LogFile $LogFile
    
  $hookPath = Join-Path "frontend/src/hooks" "useVoicePanel.ts"
    
  # Check if hook already exists - reconfigure if needed
  if (Test-Path $hookPath) {
    $existingContent = Get-Content $hookPath -Raw
    if ($existingContent -match "realTimeLevel" -and $existingContent -match "enumerateDevices" -and $existingContent -match "updateWakeWords") {
      # Check if it needs reconfiguration for device label support
      if ($existingContent -match "await navigator\.mediaDevices\.getUserMedia\(\{ audio: true \}\);" -or
          $existingContent -notmatch "device_id: voiceConfig\.selectedInputDevice" -or
          $existingContent -notmatch "device_id: voiceConfig\.selectedOutputDevice" -or
          $existingContent -notmatch "device\.label \|\|") {
        Write-Log -Message "Voice hook exists but needs reconfiguration for device label support" -Level INFO -LogFile $LogFile
        # Backup existing hook
        $backupPath = "${hookPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $hookPath $backupPath
        Write-Log -Message "Backed up existing voice hook to: $backupPath" -Level INFO -LogFile $LogFile
      } else {
        Write-Log -Message "Voice hook already exists and has device label support" -Level INFO -LogFile $LogFile
        return $true
      }
    } else {
      # Backup existing hook for major update
      $backupPath = "${hookPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
      Copy-Item $hookPath $backupPath
      Write-Log -Message "Backed up existing voice hook to: $backupPath" -Level INFO -LogFile $LogFile
    }
  }
    
  $voiceHook = @'
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

// User preference override (Australian female)
const userPreferenceConfig: Partial<VoiceConfig> = {
  accent: 'Australian',
  gender: 'Female',
  speed: 1.1,
  personality: 'Friendly'
};

export function useVoicePanel() {
  const [voiceConfig, setVoiceConfig] = useState<VoiceConfig>({
    ...defaultVoiceConfig,
    ...userPreferenceConfig  // Apply user preferences
  });
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
      // Direct enumeration without requesting permissions - labels may be limited until user grants permission through other means
      const devices = await navigator.mediaDevices.enumerateDevices();
      const audioDevices: AudioDevice[] = devices
        .filter(device => device.kind === 'audioinput' || device.kind === 'audiooutput')
        .map(device => ({
          deviceId: device.label || (device.deviceId === 'default' ? 'default' : `${device.kind === 'audioinput' ? 'Microphone' : 'Speaker'} ${device.deviceId.substring(0, 8)}`),
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
        // Stop existing stream
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
      
      // Send configuration to backend
      const response = await fetch('/api/voice/configure', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          command: 'configure',
          params: updates
        })
      });
      
      if (!response.ok) {
        throw new Error('Failed to update voice configuration');
      }
      
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
      
      const response = await fetch('/api/voice/listen', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          timeout: 10,
          device_id: voiceConfig.selectedInputDevice 
        })
      });
      const result = await response.json();
      
      const testResult: TestResult = {
        type: 'mic',
        success: result.success,
        message: result.message || 'Microphone test completed',
        data: result.data,
        timestamp: new Date()
      };
      
      setLastTestResult(testResult);
      
      if (result.success) {
        const transcript = result.data?.transcript || '';
        if (transcript.trim()) {
          setError(null);
        } else {
          setError('No speech detected. Try speaking louder or check microphone.');
        }
      } else {
        setError(`Mic test failed: ${result.message || 'Unknown error'}`);
      }
      
      return result.success;
    } catch (err) {
      const errorMessage = 'Failed to connect to voice service';
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
  }, [voiceConfig.selectedInputDevice]);

  const testSpeaker = useCallback(async () => {
    try {
      setTestStates(prev => ({ ...prev, voiceTesting: true }));
      setVoiceStatus(prev => ({ ...prev, isSpeaking: true }));
      setError(null);
      
      const testMessage = voiceConfig.accent === 'Australian' 
        ? "G'day! Voice test successful."
        : "Voice test successful.";
      
      const response = await fetch('/api/voice/speak', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          content: testMessage,
          device_id: voiceConfig.selectedOutputDevice 
        })
      });
      const result = await response.json();
      
      const testResult: TestResult = {
        type: 'voice',
        success: result.success,
        message: result.message || 'Voice test completed',
        data: result.data,
        timestamp: new Date()
      };
      
      setLastTestResult(testResult);
      
      if (result.success) {
        setError(null);
      } else {
        setError(`Voice test failed: ${result.message || 'Unknown error'}`);
      }
      
      return result.success;
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
  }, [voiceConfig.accent, voiceConfig.selectedOutputDevice]);

  const previewVoice = useCallback(async () => {
    try {
      setVoiceStatus(prev => ({ ...prev, isSpeaking: true }));
      
      let previewText = "Hello, I am Jarvis.";
      if (voiceConfig.accent === 'Australian') {
        previewText = "G'day, I'm Jarvis, your AI assistant.";
      } else if (voiceConfig.accent === 'American') {
        previewText = "Hi there, I'm Jarvis, your AI assistant.";
      }
      
      const response = await fetch('/api/voice/speak', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          content: previewText,
          device_id: voiceConfig.selectedOutputDevice,
          preview_settings: {
            accent: voiceConfig.accent,
            gender: voiceConfig.gender,
            speed: voiceConfig.speed,
            personality: voiceConfig.personality
          }
        })
      });
      const result = await response.json();
      return result.success;
    } catch (err) {
      setError('Voice preview failed');
      return false;
    } finally {
      setVoiceStatus(prev => ({ ...prev, isSpeaking: false }));
    }
  }, [voiceConfig.accent, voiceConfig.gender, voiceConfig.speed, voiceConfig.personality, voiceConfig.selectedOutputDevice]);

  const testFullVoice = useCallback(async () => {
    try {
      setTestStates(prev => ({ ...prev, chatTesting: true }));
      setError(null);
      
      const response = await fetch('/api/voice/chat', { method: 'POST' });
      const result = await response.json();
      
      const testResult: TestResult = {
        type: 'chat',
        success: result.success,
        message: result.message || 'Voice chat test completed',
        data: result.data,
        timestamp: new Date()
      };
      
      setLastTestResult(testResult);
      
      if (result.success) {
        const transcript = result.data?.transcript || '';
        const aiResponse = result.data?.ai_response || '';
        if (transcript || aiResponse) {
          setError(null);
        } else {
          setError('Chat test completed but no speech was detected. Try speaking during the listening phase.');
        }
      } else {
        setError(`Chat test failed: ${result.message || 'Unknown error'}`);
      }
      
      return result.success;
    } catch (err) {
      const errorMessage = 'Failed to connect to voice service';
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
    
    // Check status every 30 seconds
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
    Set-Content -Path $hookPath -Value $voiceHook -Encoding UTF8
    Write-Log -Message "Comprehensive voice panel hook created with device management and real-time monitoring" -Level SUCCESS -LogFile $LogFile
    return $true
  }
  catch {
    Write-Log -Message "Failed to create comprehensive voice panel hook: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
}

function Test-VoiceHookCreation {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Validating voice hook creation..." -Level INFO -LogFile $LogFile
    
  $validationResults = @()
    
  # Check hook file
  $hookPath = Join-Path "frontend/src/hooks" "useVoicePanel.ts"
  if (Test-Path $hookPath) {
    $hookContent = Get-Content $hookPath -Raw
    $hookSize = $hookContent.Length
    $validationResults += "✅ Voice Hook: Created ($hookSize bytes)"
        
    # Check for specific features
    $features = @("AudioDevice", "VoiceConfig", "realTimeLevel", "enumerateDevices", "updateWakeWords")
    foreach ($feature in $features) {
      if ($hookContent -match [regex]::Escape($feature)) {
        $validationResults += "✅   Feature: $feature implemented"
      }
      else {
        $validationResults += "❌   Feature: $feature missing"
      }
    }
  }
  else {
    $validationResults += "❌ Voice Hook: Missing"
  }
    
  # Display results
  Write-Log -Message "=== VOICE HOOK VALIDATION ===" -Level INFO -LogFile $LogFile
  foreach ($result in $validationResults) {
    $level = if ($result -like "✅*") { "SUCCESS" } else { "ERROR" }
    Write-Log -Message $result -Level $level -LogFile $LogFile
  }
    
  $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
  $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    
  Write-Log -Message "Voice Hook: $successCount/$($validationResults.Count) passed, $failureCount failed" -Level $(if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }) -LogFile $LogFile
    
  return $failureCount -eq 0
}

# Main execution
try {
  if (-not (Test-Prerequisites -LogFile $logFile)) {
    Stop-Transcript
    exit 1
  }
    
  $setupResults = @()
    
  if ($Install -or $Run) {
    Write-Log -Message "Creating voice hooks..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "Voice Hook"; Success = (New-ComprehensiveVoiceHook -LogFile $logFile) }
  }
    
  if ($Configure -or $Run) {
    Write-Log -Message "Voice hook configuration complete (handled in creation)" -Level INFO -LogFile $logFile
  }
    
  if ($Test -or $Run) {
    Write-Log -Message "Testing voice hooks..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "Hook Validation"; Success = (Test-VoiceHookCreation -LogFile $logFile) }
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
    
  if ($failCount -gt 0) {
    Write-Log -Message "Voice hooks setup had failures" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
  }
    
  Write-Log -Message "=== VOICE HOOKS CREATED ===" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "🎤 Voice Hook: Device management with real-time audio level monitoring" -Level INFO -LogFile $logFile
  Write-Log -Message "🔧 Interfaces: AudioDevice, VoiceConfig, VoiceStatus, TestResult" -Level INFO -LogFile $logFile
  Write-Log -Message "📱 Device Functions: enumerateDevices, startAudioLevelMonitoring" -Level INFO -LogFile $logFile
  Write-Log -Message "🎛️ Voice Functions: testMicrophone, testSpeaker, previewVoice, testFullVoice" -Level INFO -LogFile $logFile
    
  Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
  Write-Log -Message "1. To create React UI components: .\07b-VoiceComponents.ps1" -Level INFO -LogFile $logFile
  Write-Log -Message "2. To complete API integration: .\07c-VoiceIntegration.ps1" -Level INFO -LogFile $logFile
}
catch {
  Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
  Stop-Transcript
  exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript