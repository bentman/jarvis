# J.A.R.V.I.S. AI Assistant

A personal AI assistant inspired by Tony Stark's JARVIS, featuring local AI processing with modern voice capabilities and hardware acceleration for NPU/GPU devices.

## Overview

JARVIS (Just A Rather Very Intelligent System) is a full-stack AI assistant that combines a FastAPI backend with a React frontend, local AI processing through Ollama, and modern voice integration. Built with a focus on performance, portability, and personality, it provides a witty, capable AI assistant with voice interaction that runs entirely on your local machine.

## Key Features

- 🤖 **Local AI Processing**: Runs entirely on your machine using Ollama - no cloud dependencies
- 🎤 **Modern Voice Stack**: Speech-to-text (faster-whisper), text-to-speech (coqui-tts), and wake word detection (openWakeWord)
- 🚀 **Hardware Acceleration**: Automatic NPU/GPU detection and optimization (NVIDIA, AMD, Intel, Qualcomm)
- 💬 **Personality System**: Configurable AI personality inspired by MCU's JARVIS with voice responses
- ⚡ **Cross-Platform**: Optimized for both x64 (Intel/AMD) and ARM64 (Snapdragon X)
- 🔄 **Fallback Mode**: Continues working even when AI services are unavailable
- 📊 **Performance Benchmarking**: Built-in benchmarking to measure AI response times
- 🎨 **Modern UI**: React-based chat interface with real-time updates

## Prerequisites

### Required Software
- **Windows 11** (x64 or ARM64)
- **PowerShell 7+** 
- **Python 3.8+** (3.12+ recommended)
- **Node.js 16+**
- **Git**

### Hardware Support
- **NPU**: Qualcomm Hexagon (Snapdragon X), Intel AI Boost (Core Ultra)
- **GPU**: NVIDIA (CUDA), AMD, Intel Arc, Qualcomm Adreno
- **CPU**: Falls back to CPU if no acceleration available

## Installation

### Automated Setup

Clone the repository and run the setup scripts in order:

```powershell
# Clone the repository
git clone https://github.com/bentman/jarvis.git
pushd jarvis

# Run setup scripts in sequence
.\01-Prerequisites.ps1             # Install system dependencies
.\02-FastApiBackend.ps1            # Setup backend with virtual environment
.\03-IntegrateOllama.ps1           # Integrate AI services with personality
.\04a-OllamaSetup.ps1              # Install Ollama and models
.\04c-OllamaTuning.ps1             # Optimize for your hardware
.\05-ReactFrontend.ps1             # Setup React frontend

# Voice integration (optional but recommended)
.\06a-VoiceSetup.ps1               # Setup voice service architecture
.\06b-VoiceBackendIntegration.ps1  # Integrate voice with FastAPI
.\06c-VoiceInstall.ps1             # Install voice dependencies
```

### Hardware Optimization

The system automatically detects and optimizes for your hardware:

```powershell
# Run hardware detection and optimization
.\04c-OllamaTuning.ps1

# For NVIDIA GPUs - installs CUDA if needed
.\04c-OllamaTuning.ps1 -Install

# Benchmark your system
.\04c-OllamaTuning.ps1 -Benchmark
```

## Usage

### Starting JARVIS

Start backend and frontend in separate terminals:

```powershell
# Terminal 1 - Start backend
.\run_backend.ps1

# Terminal 2 - Start frontend  
.\run_frontend.ps1
```

Quick health checks:
```powershell
# Test backend functionality
.\run_backend.ps1 -QuickTest

# Check system health
.\run_backend.ps1 -Health

# Test voice integration (if installed)
.\test_voice.ps1 -ShowConfig -TestAPI
```

### Accessing JARVIS

1. Open your browser to **http://localhost:3000**
2. JARVIS will greet you with personality
3. Start chatting - responses are powered by local AI
4. If voice is enabled, say "jarvis" or "hey jarvis" to activate voice mode

### API Access

- **Interactive API Docs**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/api/health
- **AI Status**: http://localhost:8000/api/ai/status
- **Voice Status**: http://localhost:8000/api/voice/status (if voice enabled)

### Voice Features

With voice integration enabled, JARVIS supports:

```powershell
# Test microphone (speech-to-text)
.\test_voice.ps1 -TestMic

# Test text-to-speech
.\test_voice.ps1 -TestTTS

# Test all voice APIs
.\test_voice.ps1 -TestAPI

# Interactive voice mode
.\test_voice.ps1 -Interactive
```

**Wake Words**: "jarvis" or "hey jarvis"

## Configuration

### Personality Customization

Edit/Create `.\jarvis_personality.json` to customize JARVIS's behavior:

```json
{
  "personality": {
    "base_personality": "You are Jarvis, inspired by Tony Stark's AI...",
    "tone": "formal British restraint with occasional dry wit",
    "formality": "always 'Sir' or 'Mr. [Name]', never casual"
  },
  "voice_settings": {
    "voice_stack": "faster-whisper + coqui-tts + openWakeWord",
    "wake_words": ["jarvis", "hey jarvis"],
    "speech_rate": 1.0,
    "voice_pitch": 0.5,
    "responses": {
      "wake_acknowledged": "Yes, how can I help you?",
      "listening": "I'm listening...",
      "processing": "Let me think about that...",
      "error_no_speech": "I didn't hear anything. Please try again."
    }
  }
}
```

Changes take effect after restarting the backend.

### Environment Settings

The `.env` file controls system settings:
```env
OLLAMA_MODEL=phi3:mini        # AI model to use
API_HOST=0.0.0.0             # Backend host
API_PORT=8000                # Backend port

# Voice settings (if voice integration enabled)
JARVIS_WAKE_WORDS=jarvis,hey jarvis
FASTER_WHISPER_MODEL=base
COQUI_TTS_MODEL=tts_models/en/ljspeech/tacotron2-DDC
VOICE_SAMPLE_RATE=16000
```

### Supported AI Models

Recommended models by hardware:
- **NPU/Mobile**: `phi3:mini`, `gemma2:2b`, `llama3.2:3b`
- **GPU (4-8GB)**: `phi3:mini`, `llama3.1:8b`, `mistral:7b`
- **GPU (8GB+)**: `llama3.1:8b`, `codellama:13b`, `mixtral:8x7b`

## Performance Benchmarks

Example benchmarks from real hardware:

| Hardware | Model | Avg Response | Tokens/sec | Category |
|----------|-------|--------------|------------|----------|
| GTX 1650 SUPER | phi3:mini | 4.9s | 15-29 | Acceptable |
| Snapdragon X NPU | phi3:mini | 4.5s | 27-28 | Acceptable |
| RTX 4090 | llama3.1:8b | 0.8s | 60-80 | Excellent |

Run your own benchmark:
```powershell
.\04c-OllamaTuning.ps1 -Benchmark
```

## Development

### Core Scripts
- `00-CommonUtils.ps1` - Shared utilities and logging
- `01-Prerequisites.ps1` - System dependency installer  
- `02-FastApiBackend.ps1` - Backend setup with virtual environment
- `03-IntegrateOllama.ps1` - AI service integration
- `04a-OllamaSetup.ps1` - Ollama installation
- `04b-OllamaDiag.ps1` - Hardware diagnostics
- `04c-OllamaTuning.ps1` - Performance optimization
- `05-ReactFrontend.ps1` - Frontend setup
- `06a-VoiceSetup.ps1` - Voice service architecture
- `06b-VoiceBackendIntegration.ps1` - Voice FastAPI integration
- `06c-VoiceInstall.ps1` - Voice dependencies installation

### Quick Commands

```powershell
# Frontend dependency install
.\run_frontend.ps1 -Install

# Frontend production build
.\run_frontend.ps1 -Build

# Backend tests
.\run_backend.ps1 -Test

# Voice integration tests
.\test_voice.ps1 -TestMic -TestTTS -TestAPI
```

### Extending JARVIS

Future enhancements to explore:
- 🔍 Web search integration
- 📊 Data visualization  
- 🔌 Plugin system for custom commands
- 📱 Mobile app development
- 🏠 Smart home integration
- 📧 Email and calendar integration

## System Requirements

### Minimum
- Windows 11 (22H2 or later)
- 8GB RAM
- 20GB free disk space
- Internet for initial setup

### Recommended
- 16GB+ RAM
- NPU or dedicated GPU
- SSD storage
- Persistent internet for model updates

## Security

- All AI processing is local - no data leaves your machine
- API runs on localhost only by default
- No authentication implemented (add for production use)
- Personality configuration has local system access

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by JARVIS from the Marvel Cinematic Universe
- Built with Ollama for local AI processing
- FastAPI and React for modern web architecture

---

*"Sometimes you gotta run before you can walk." - Tony Stark*