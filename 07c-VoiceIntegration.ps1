# 07c-VoiceIntegration.ps1 - Voice API Integration and Chat Component Updates  
# Purpose: Complete voice API service integration, Chat component updates, and comprehensive validation
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
  Write-Log -Message "Testing prerequisites for voice integration..." -Level INFO -LogFile $LogFile
    
  # Check React frontend API service exists
  if (-not (Test-Path "frontend/src/services/api.ts")) {
    Write-Log -Message "Frontend API service not found. Run 05-ReactFrontend.ps1." -Level ERROR -LogFile $LogFile
    return $false
  }
    
  # Check voice components created (from 07a and 07b scripts)
  if (-not (Test-Path "frontend/src/hooks/useVoicePanel.ts")) {
    Write-Log -Message "Voice hooks not found. Run 07a-VoiceHooks.ps1." -Level ERROR -LogFile $LogFile
    return $false
  }
    
  if (-not (Test-Path "frontend/src/components/VoiceControlPanel.tsx")) {
    Write-Log -Message "Voice components not found. Run 07b-VoiceComponents.ps1." -Level ERROR -LogFile $LogFile
    return $false
  }
    
  # Check voice backend exists
  if (-not (Test-Path "backend/services/voice_service.py")) {
    Write-Log -Message "Voice backend not found. Run 06a-06c voice backend scripts." -Level ERROR -LogFile $LogFile
    return $false
  }
    
  Write-Log -Message "All prerequisites verified for voice integration" -Level SUCCESS -LogFile $LogFile
  return $true
}

function Add-VoiceApiExtensions {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Adding comprehensive voice API extensions..." -Level INFO -LogFile $LogFile
    
  $apiPath = Join-Path "frontend/src/services" "api.ts"
    
  if (-not (Test-Path $apiPath)) {
    Write-Log -Message "API service file not found at $apiPath" -Level ERROR -LogFile $LogFile
    return $false
  }
    
  try {
    # Read current API service content
    $apiContent = Get-Content $apiPath -Raw
        
    # Check if VoiceApiService already exists and needs reconfiguration
    if ($apiContent -match "export class VoiceApiService") {
      # Check if it has the problematic getUserMedia call in enumerateDevices
      if ($apiContent -match "await navigator\.mediaDevices\.getUserMedia\(\{ audio: true \}\);") {
        Write-Log -Message "VoiceApiService exists but needs reconfiguration to fix device enumeration" -Level INFO -LogFile $LogFile
        # Remove existing VoiceApiService to regenerate with fix
        $apiContent = $apiContent -replace "(?s)// Voice API Extensions.*?export class VoiceApiService.*?}\s*$", ""
      } else {
        Write-Log -Message "VoiceApiService already exists in API service and is current" -Level INFO -LogFile $LogFile
        return $true
      }
    }
        
    # Create backup before modification
    $backupPath = "${apiPath}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $apiPath $backupPath
    Write-Log -Message "Created backup: $backupPath" -Level INFO -LogFile $LogFile
        
    # Create comprehensive voice API extensions
    $voiceExtensions = @"

// Voice API Extensions - Comprehensive Device Management and Voice Control
export interface VoiceMessage {
  content: string;
  preview_settings?: {
    accent: string;
    gender: string;
    speed: number;
    personality: string;
  };
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

// Complete Voice API Service with Device Management
export class VoiceApiService {
  // Backend Voice Endpoints
  static async getVoiceStatus(): Promise<VoiceStatusResponse> {
    const response = await api.get<VoiceStatusResponse>('/voice/status');
    return response.data;
  }

  static async speak(content: string, previewSettings?: any): Promise<any> {
    const payload: VoiceMessage = { content };
    if (previewSettings) {
      payload.preview_settings = previewSettings;
    }
    const response = await api.post('/voice/speak', payload);
    return response.data;
  }

  static async listen(timeout: number = 10): Promise<any> {
    const response = await api.post('/voice/listen', { timeout });
    return response.data;
  }

  static async detectWakeWord(timeout: number = 30): Promise<any> {
    const response = await api.post('/voice/wake', { timeout });
    return response.data;
  }

  static async configureVoice(command: string, params: any): Promise<any> {
    const response = await api.post('/voice/configure', { command, params });
    return response.data;
  }

  static async testVoiceChat(): Promise<any> {
    const response = await api.post('/voice/chat');
    return response.data;
  }

  static async stopVoice(): Promise<any> {
    const response = await api.post('/voice/stop');
    return response.data;
  }

  // Frontend Device Management (Web Audio API)
  static async enumerateDevices(): Promise<AudioDevice[]> {
    try {
      // Direct enumeration without requesting permissions - labels may be limited until user grants permission through other means
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
        // Output device validation (limited browser support)
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
  Write-Log -Message "Ensuring Chat component integration with voice panel..." -Level INFO -LogFile $LogFile
    
  $chatPath = Join-Path "frontend/src/components" "Chat.tsx"
    
  if (-not (Test-Path $chatPath)) {
    Write-Log -Message "Chat component not found - cannot integrate voice controls" -Level ERROR -LogFile $LogFile
    return $false
  }
    
  $chatContent = Get-Content $chatPath -Raw
    
  # Check if voice integration already exists
  if ($chatContent -match "VoiceControlPanel" -and $chatContent -match "import.*VoiceControlPanel") {
    Write-Log -Message "Chat component already integrated with voice control panel" -Level INFO -LogFile $LogFile
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

function Test-VoiceIntegrationComplete {
  param( [Parameter(Mandatory = $true)] [string]$LogFile )
  Write-Log -Message "Running comprehensive voice integration validation..." -Level INFO -LogFile $LogFile
    
  $validationResults = @()
    
  # Test Chat integration
  if (Test-Path "frontend/src/components/Chat.tsx") {
    $chatContent = Get-Content "frontend/src/components/Chat.tsx" -Raw
    if ($chatContent -match "VoiceControlPanel") {
      $validationResults += "✅ Chat Integration: Voice panel integrated"
    }
    else {
      $validationResults += "❌ Chat Integration: Voice panel missing"
    }
  }
  else {
    $validationResults += "❌ Chat Integration: Chat component not found"
  }
    
  # Test hook integration (should exist from 07a)
  if (Test-Path "frontend/src/hooks/useVoicePanel.ts") {
    $validationResults += "✅ Hook Integration: Voice panel hook available"
  }
  else {
    $validationResults += "❌ Hook Integration: Voice panel hook missing"
  }
    
  # Test component integration (should exist from 07b)
  if (Test-Path "frontend/src/components/VoiceControlPanel.tsx") {
    $validationResults += "✅ Component Integration: Voice control panel available"
  }
  else {
    $validationResults += "❌ Component Integration: Voice control panel missing"
  }
    
  # Display results
  Write-Log -Message "=== COMPLETE VOICE INTEGRATION VALIDATION ===" -Level INFO -LogFile $LogFile
  foreach ($result in $validationResults) {
    $level = if ($result -like "✅*") { "SUCCESS" } else { "ERROR" }
    Write-Log -Message $result -Level $level -LogFile $LogFile
  }
    
  $successCount = ($validationResults | Where-Object { $_ -like "✅*" }).Count
  $failureCount = ($validationResults | Where-Object { $_ -like "❌*" }).Count
    
  Write-Log -Message "Complete Voice Integration: $successCount/$($validationResults.Count) passed, $failureCount failed" -Level $(if ($failureCount -eq 0) { "SUCCESS" } else { "ERROR" }) -LogFile $LogFile
    
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
    Write-Log -Message "Installing voice integration..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "Voice API Extensions"; Success = (Add-VoiceApiExtensions -LogFile $logFile) }
    $setupResults += @{Name = "Chat Integration"; Success = (Update-ChatComponentIntegration -LogFile $logFile) }
  }
    
  if ($Configure -or $Run) {
    Write-Log -Message "Configuring voice integration..." -Level INFO -LogFile $logFile
    # Configuration handled in creation functions
  }
    
  if ($Test -or $Run) {
    Write-Log -Message "Testing voice integration..." -Level INFO -LogFile $logFile
    $setupResults += @{Name = "Complete Integration Test"; Success = (Test-VoiceIntegrationComplete -LogFile $logFile) }
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
    Write-Log -Message "Voice integration setup had failures" -Level ERROR -LogFile $logFile
    Stop-Transcript
    exit 1
  }
    
  Write-Log -Message "=== COMPLETE VOICE SYSTEM READY ===" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "Chat Integration: Voice controls embedded in main chat interface" -Level INFO -LogFile $logFile
    
  Write-Log -Message "=== READY TO USE ===" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "1. Start backend: .\run_backend.ps1" -Level INFO -LogFile $logFile
  Write-Log -Message "2. Start frontend: .\run_frontend.ps1" -Level INFO -LogFile $logFile
  Write-Log -Message "3. Access the application at: http://localhost:3000" -Level INFO -LogFile $logFile
  Write-Log -Message "4. Voice controls should now be visible in the chat interface." -Level INFO -LogFile $logFile
    
  Write-Log -Message "=== VOICE SYSTEM CAPABILITIES ===" -Level INFO -LogFile $logFile
  Write-Log -Message "✅ Device enumeration and selection" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "✅ Real-time audio level monitoring" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "✅ Wake word management and editing" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "✅ Voice preview and testing" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "✅ Complete voice chat pipeline" -Level SUCCESS -LogFile $logFile
  Write-Log -Message "✅ Hardware-optimized backend integration" -Level SUCCESS -LogFile $logFile
}
catch {
  Write-Log -Message "Error: $_" -Level ERROR -LogFile $logFile
  Stop-Transcript
  exit 1
}

Write-Log -Message "${scriptPrefix} v${scriptVersion} complete." -Level SUCCESS -LogFile $logFile
Stop-Transcript