# 07b-VoiceComponents.ps1 - Voice React UI Components
# Purpose: Create React voice control panel with comprehensive UI controls and device management
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
  Write-Log -Message "Testing prerequisites for voice components..." -Level INFO -LogFile $LogFile
    
  # Check React components directory
  if (-not (Test-Path "frontend/src/components")) {
    Write-Log -Message "React components directory not found. Complete frontend setup first." -Level ERROR -LogFile $LogFile
    
    return $false
  }
    
  # Check voice hooks created (from 07a script)
  if (-not (Test-Path "frontend/src/hooks/useVoicePanel.ts")) {
    Write-Log -Message "Voice hooks not found. Run 07a-VoiceHooks.ps1 first." -Level ERROR -LogFile $LogFile
    Write-Log -Message "REMEDIATION: Create voice hooks before UI components." -Level ERROR -LogFile $LogFile
    return $false
  }
    
  Write-Log -Message "All prerequisites verified for voice components" -Level SUCCESS -LogFile $LogFile
  return $true
}

function New-CompleteVoiceControlPanel {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Creating complete voice control panel with all features..." -Level INFO -LogFile $LogFile
    
  $panelPath = Join-Path "frontend/src/components" "VoiceControlPanel.tsx"
    
  # Check if panel already exists and is current
  if (Test-Path $panelPath) {
    $existingContent = Get-Content $panelPath -Raw
    if ($existingContent -match "AudioLevelMeter" -and $existingContent -match "Wake Word Editor" -and $existingContent -match "Reset to Default") {
      Write-Log -Message "Complete voice control panel already exists and is current" -Level INFO -LogFile $LogFile
      return $true
    }
    # Backup existing panel
    $backupPath = "${panelPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $panelPath $backupPath
    Write-Log -Message "Backed up existing voice panel to: $backupPath" -Level INFO -LogFile $LogFile
  }
    
  $controlPanel = @'
import React, { useState } from 'react';
import { Mic, MicOff, Volume2, VolumeX, Settings, TestTube, MessageSquare, Headphones, ChevronDown, ChevronUp, Play } from 'lucide-react';
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
    { value: 'British', label: 'British', description: 'Sophisticated, classic JARVIS' },
    { value: 'Australian', label: 'Australian', description: 'Friendly, approachable' },
    { value: 'American', label: 'American', description: 'Clear, professional' }
  ];

  const personalityOptions = [
    { value: 'Classic', label: 'Classic', description: 'Sophisticated British AI' },
    { value: 'Friendly', label: 'Friendly', description: 'Warm and approachable' },
    { value: 'Professional', label: 'Professional', description: 'Efficient and clear' }
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
      top: '80px',  // Fixed: Moved down to avoid button overlap
      right: '20px',
      width: isExpanded ? '380px' : '50px',
      background: '#0a0e1a',
      borderRadius: '15px',
      border: '1px solid #1a2332',
      padding: isExpanded ? '15px' : '8px',
      transition: 'all 0.3s ease',
      zIndex: 100,
      boxShadow: '0 8px 25px rgba(0, 212, 255, 0.15)',
      maxHeight: isExpanded ? 'calc(100vh - 100px)' : '50px',  // Fixed: Better height calculation
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
                {/* Comprehensive Wake Word Editor */}
                <div style={{ marginBottom: '12px' }}>
                  <label style={{ color: '#9ca3af', fontSize: '12px', display: 'block', marginBottom: '4px' }}>
                    Wake Word Editor
                  </label>
                  
                  {/* Add New Wake Word */}
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

                  {/* Wake Word Management Panel */}
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
                    
                    {/* Wake Word Guidelines */}
                    <div style={{ 
                      marginTop: '8px', 
                      padding: '6px', 
                      background: 'rgba(0, 212, 255, 0.1)',
                      border: '1px solid rgba(0, 212, 255, 0.3)',
                      borderRadius: '4px' 
                    }}>
                      <div style={{ color: '#00d4ff', fontSize: '10px', marginBottom: '2px' }}>
                        Tips:
                      </div>
                      <div style={{ color: '#9ca3af', fontSize: '10px', lineHeight: '1.3' }}>
                        - Use clear, distinct words (2-3 syllables work best)
                        - Avoid common words that might trigger accidentally
                        - Test sensitivity after adding new words
                      </div>
                    </div>
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

                {/* Timeouts */}
                <div style={{ display: 'flex', gap: '8px', marginBottom: '12px' }}>
                  <div style={{ flex: 1 }}>
                    <label style={{ color: '#9ca3af', fontSize: '11px', display: 'block', marginBottom: '2px' }}>
                      Phrase Timeout ({voiceConfig.phraseTimeout}s)
                    </label>
                    <input
                      type="range"
                      min="1.0"
                      max="10.0"
                      step="0.5"
                      value={voiceConfig.phraseTimeout}
                      onChange={(e) => updateVoiceConfig({ phraseTimeout: parseFloat(e.target.value) })}
                      style={{
                        width: '100%',
                        accentColor: '#00d4ff'
                      }}
                    />
                  </div>
                  <div style={{ flex: 1 }}>
                    <label style={{ color: '#9ca3af', fontSize: '11px', display: 'block', marginBottom: '2px' }}>
                      Silence Timeout ({voiceConfig.silenceTimeout}s)
                    </label>
                    <input
                      type="range"
                      min="0.5"
                      max="5.0"
                      step="0.5"
                      value={voiceConfig.silenceTimeout}
                      onChange={(e) => updateVoiceConfig({ silenceTimeout: parseFloat(e.target.value) })}
                      style={{
                        width: '100%',
                        accentColor: '#00d4ff'
                      }}
                    />
                  </div>
                </div>

                {/* Options */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
                    <input
                      type="checkbox"
                      checked={voiceConfig.pushToTalk}
                      onChange={(e) => updateVoiceConfig({ pushToTalk: e.target.checked })}
                      style={{ accentColor: '#00d4ff' }}
                    />
                    <span style={{ color: '#ffffff', fontSize: '12px' }}>Push-to-talk mode</span>
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
                    <input
                      type="checkbox"
                      checked={voiceConfig.quietHours}
                      onChange={(e) => updateVoiceConfig({ quietHours: e.target.checked })}
                      style={{ accentColor: '#00d4ff' }}
                    />
                    <span style={{ color: '#ffffff', fontSize: '12px' }}>Quiet hours mode</span>
                  </label>
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
                  {lastTestResult.success ? 'PASS' : 'FAIL'} {lastTestResult.type.toUpperCase()} Test Result
                </div>
                <div style={{ color: '#9ca3af', fontSize: '11px', marginBottom: '4px' }}>
                  {lastTestResult.message}
                </div>
                {lastTestResult.data && lastTestResult.data.transcript && (
                  <div style={{ color: '#ffffff', fontSize: '11px', fontStyle: 'italic' }}>
                    Detected: "{lastTestResult.data.transcript}"
                  </div>
                )}
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
    Write-Log -Message "Complete voice control panel created with all features" -Level SUCCESS -LogFile $LogFile
    return $true
  }
  catch {
    Write-Log -Message "Failed to create complete voice control panel: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    return $false
  }
}

function Test-VoiceComponentsCreation {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Validating voice components creation..." -Level INFO -LogFile $LogFile
    
  $validationResults = @()
    
  # Check component file
  $panelPath = Join-Path "frontend/src/components" "VoiceControlPanel.tsx"
  if (Test-Path $panelPath) {
    $panelContent = Get-Content $panelPath -Raw
    $panelSize = $panelContent.Length
    $validationResults += "✅ Voice Control Panel: Created ($panelSize bytes)"
        
    # Check for specific features
    $features = @("AudioLevelMeter", "Wake Word Editor", "Reset to Default", "Advanced Settings", "Test Controls")
    foreach ($feature in $features) {
      if ($panelContent -match [regex]::Escape($feature)) {
        $validationResults += "✅   Feature: $feature implemented"
      }
      else {
        $validationResults += "❌   Feature: $feature missing"
      }
    }
        
    # Check JARVIS design preservation
    if ($panelContent -match "#050810" -and $panelContent -match "#00d4ff") {
      $validationResults += "✅ Design: JARVIS color scheme preserved"
    }
  }
  else {
    $validationResults += "❌ Voice Control Panel: Missing"
  }
    
  # Display results
  Write-Log -Message "=== VOICE COMPONENTS VALIDATION ===" -Level INFO -LogFile $LogFile
  foreach ($result in $validationResults) {
    $level = if ($result -like "✅*") { "SUCCESS" } else { "ERROR" }
    Write-Log -Message $result -Level $level -LogFile $LogFile
  }
    
  $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
  $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    
  Write-Log -Message "Voice Components: $successCount/$($validationResults.Count) passed, $failureCount failed" -Level $(if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }) -LogFile $LogFile
    
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
    Write-Log -Message "Creating voice components..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "Voice Control Panel"; Success = (New-CompleteVoiceControlPanel -LogFile $logFile) }
  }
    
  if ($Configure -or $Run) {
    Write-Log -Message "Voice components configuration complete (handled in creation)" -Level INFO -LogFile $logFile
  }
    
  if ($Test -or $Run) {
    Write-Log -Message "Testing voice components..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "Components Validation"; Success = (Test-VoiceComponentsCreation -LogFile $logFile) }
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
    Write-Log -Message "Voice components setup had failures" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
  }
    
  Write-Log -Message "=== VOICE UI COMPONENTS CREATED ===" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "🎛️ Control Panel: Comprehensive voice settings with wake word editor" -Level INFO -LogFile $logFile
  Write-Log -Message "🔊 Audio Controls: Device selection with real-time level monitoring" -Level INFO -LogFile $logFile
  Write-Log -Message "🎨 JARVIS Design: Preserved styling with collapsible floating panel (fixed positioning)" -Level INFO -LogFile $logFile
  Write-Log -Message "🧪 Test Controls: Microphone, speaker, and full voice chat testing" -Level INFO -LogFile $logFile
  Write-Log -Message "⚙️ Advanced Settings: Wake word management, sensitivity, timeouts" -Level INFO -LogFile $logFile
    
  Write-Log -Message "=== NEXT STEPS ===" -Level INFO -LogFile $logFile
  Write-Log -Message "1. To complete API integration and Chat updates: .\07c-VoiceIntegration.ps1" -Level INFO -LogFile $logFile
}
catch {
  Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
  Stop-Transcript
  exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript