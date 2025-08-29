# J.A.R.V.I.S. AI Assistant

A personal AI assistant inspired by Tony Stark's JARVIS, featuring local AI processing with modern voice capabilities and hardware acceleration for NPU/GPU devices.

## Overview

JARVIS (Just A Rather Very Intelligent System) is a full-stack AI assistant that combines a FastAPI backend with a React frontend, local AI processing through Ollama, and modern voice integration. Built with a focus on performance, portability, and personality, it provides a witty, capable AI assistant with voice interaction that runs entirely on your local machine.

## Key Features

- 📊 **Performance Benchmarking**: Built-in benchmarking to measure AI response times
- 🚀 **Hardware Acceleration**: Automatic NPU/GPU detection and optimization (NVIDIA, AMD, Intel, Qualcomm)
- 🤖 **Local AI Processing**: Runs entirely on your machine using Ollama - no cloud dependencies
- 💬 **Personality System**: Configurable AI personality inspired by MCU's JARVIS with voice responses
- ⚡ **Cross-Platform**: Optimized for both x64 (Intel/AMD) and ARM64 (Snapdragon X)
- 🔄 **Fallback Mode**: Continues working even when AI services are unavailable
- 🎨 **Modern UI**: React-based chat interface with real-time updates
- 🎤 **Modern Voice Stack**: STT (faster-whisper), TTS (Kokoro-82M), wake word (openWakeWord)

## Prerequisites

### Required Software
- **Windows 11** (x64 or ARM64)
- **PowerShell 5+** (7+ recommended)
- **Python 3.12+** (required for voice integration)
- **Node.js 16+** (LTS recommended)

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
.\00-CommonUtils.ps1     # Shared utilities and logging
.\01-Prerequisites.ps1   # System dependency installer  
.\02-FastApiBackend.ps1  # Backend setup with virtual environment
.\03-IntegrateOllama.ps1 # AI service integration
.\04-OllamaConfig.ps1    # Ollama Configuration
.\05-ReactFrontend.ps1   # Frontend setup

# Voice integration (optional but recommended)
.\06-VoiceBackend.ps1      # Voice service backend
.\07-VoiceIntegration.ps1  # Voice hooks, components, and API integration
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
```

### Accessing JARVIS

1. Open your browser to **http://localhost:3000**
2. Start chatting - responses are powered by local AI

### API Access

- **Interactive API Docs**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/api/health
- **AI Status**: http://localhost:8000/api/ai/status
- **Voice Status**: http://localhost:8000/api/voice/status (if voice enabled)
- **TTS Preview**: http://localhost:8000/api/voice/tts (POST)

## Configuration

### Environment Settings

The `.env` file controls system settings:
```env
OLLAMA_MODEL=phi3:mini       # AI model to use
API_HOST=0.0.0.0             # Backend host
API_PORT=8000                # Backend port

# Voice settings (if voice integration enabled)
JARVIS_WAKE_WORDS=jarvis,hey jarvis
FASTER_WHISPER_MODEL=base
KOKORO_TTS_MODEL=kokoro-82M
VOICE_SAMPLE_RATE=24000
```

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
    "voice_stack": "faster-whisper + kokoro-tts + openWakeWord",
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

## Performance Benchmarks

Example benchmarks from real hardware:

| Hardware | Model | Avg Response | Tokens/sec | Category |
|----------|-------|--------------|------------|----------|
| RTX 3060 (12GB) | phi3:mini | 2.7s | 106-132 | Good |
| Snapdragon X NPU | phi3:mini | 3.9s | 27-31 | Acceptable |
| GTX 1650 (4GB) | phi3:mini | 4.9s | 25-29 | Acceptable |

*Performance varies based on system optimization and load

## Development

### Extending JARVIS

Future enhancements to explore:
- 🔍 Web search integration
- 📊 Data visualization  
- 🔌 Plugin system for custom commands
- 📱 Mobile app development
- 📧 Email and calendar integration

## System Requirements

### Minimum
- Windows 11, 8GB RAM, 20GB free disk space, Internet for initial setup

### Recommended
- 16GB+ RAM, NPU or dedicated GPU, SSD storage, Internet for model updates

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