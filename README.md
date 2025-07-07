# J.A.R.V.I.S. AI Assistant

A personal AI assistant inspired by Tony Stark's JARVIS, featuring local AI processing, multi-platform support, and hardware acceleration for NPU/GPU devices.

## Overview

JARVIS (Just A Rather Very Intelligent System) is a full-stack AI assistant that combines a FastAPI backend with a React frontend and local AI processing through Ollama. Built with a focus on performance, portability, and personality, it provides a witty, capable AI assistant that runs entirely on your local machine.

## Key Features

- 🤖 **Local AI Processing**: Runs entirely on your machine using Ollama - no cloud dependencies
- 🚀 **Hardware Acceleration**: Automatic NPU/GPU detection and optimization (NVIDIA, AMD, Intel, Qualcomm)
- 💬 **Personality System**: Configurable AI personality inspired by MCU's JARVIS
- ⚡ **Cross-Platform**: Optimized for both x64 (Intel/AMD) and ARM64 (Snapdragon X)
- 🔄 **Fallback Mode**: Continues working even when AI services are unavailable
- 📊 **Performance Benchmarking**: Built-in benchmarking to measure AI response times
- 🎨 **Modern UI**: React-based chat interface with real-time updates

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  React Frontend │────▶│ FastAPI Backend │────▶│   Ollama AI     │
│   (Port 3000)   │◀────│   (Port 8000)   │◀────│  (Port 11434)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Personality JSON │
                    └─────────────────┘
```

## Prerequisites

### Required Software
- **Windows 11** (x64 or ARM64)
- **PowerShell 7+** 
- **Python 3.8+** (3.11 recommended)
- **Node.js 16+**
- **Git**

### Hardware Support
- **NPU**: Qualcomm Hexagon (Snapdragon X), Intel AI Boost (Core Ultra)
- **GPU**: NVIDIA (CUDA), AMD, Intel Arc, Qualcomm Adreno
- **CPU**: Falls back to CPU if no acceleration available

## Installation

### Automated Setup (Recommended)

Clone the repository and run the setup scripts in order:

```powershell
# Clone the repository
git clone https://github.com/yourusername/jarvis.git
cd jarvis

# Run setup scripts in sequence
.\01-Prerequisites.ps1        # Install system dependencies
.\02-FastApiBackend.ps1 -All  # Setup backend
.\03-AIIntegration.ps1 -All   # Integrate AI services
.\04a-OllamaSetup.ps1         # Install Ollama and models
.\04c-OllamaTuning.ps1        # Optimize for your hardware
.\05-ReactFrontend.ps1 -All   # Setup frontend
```

### Hardware-Specific Optimization

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

Option 1: Use individual run scripts
```powershell
# Terminal 1 - Start backend
.\run_backend.ps1

# Terminal 2 - Start frontend
.\run_frontend.ps1
```

Option 2: Quick commands after setup
```powershell
# Quick backend test
.\run_backend.ps1 -QuickTest

# Check system health
.\run_backend.ps1 -Health
```

### Accessing JARVIS

1. Open your browser to http://localhost:3000
2. JARVIS will greet you with personality
3. Start chatting - responses are powered by local AI

### API Documentation

- **Interactive API Docs**: http://localhost:8000/docs
- **API Health Check**: http://localhost:8000/api/health

## Configuration

### Personality Customization

Edit `jarvis_personality.json` to customize JARVIS's behavior:

```json
{
  "personality": {
    "base_personality": "You are Jarvis, inspired by Tony Stark's AI...",
    "tone": "witty, professional, with dry humor",
    "formality": "address user as 'sir' with British politeness"
  }
}
```

Changes take effect after restarting the backend.

### Environment Configuration

The `.env` file controls system settings:
```env
OLLAMA_MODEL=phi3:mini        # AI model to use
API_HOST=0.0.0.0             # Backend host
API_PORT=8000                # Backend port
OLLAMA_URL=http://localhost:11434
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

## Project Structure

```
jarvis/
├── 00-CommonUtils.ps1         # Shared utilities
├── 01-Prerequisites.ps1       # System dependency installer
├── 02-FastApiBackend.ps1      # Backend setup
├── 03-AIIntegration.ps1       # AI service integration
├── 04a-OllamaSetup.ps1        # Ollama installation
├── 04b-OllamaDiag.ps1         # Hardware diagnostics
├── 04c-OllamaTuning.ps1       # Performance optimization
├── 05-ReactFrontend.ps1       # Frontend setup
├── jarvis_personality.json    # AI personality config
├── .env                       # Environment variables
├── backend/                   # FastAPI backend
│   ├── api/                  
│   │   └── main.py           # Main API application
│   ├── services/
│   │   └── ai_service.py     # Ollama integration
│   └── requirements.txt      # Python dependencies
├── frontend/                 # React frontend
│   ├── src/
│   │   ├── components/       # React components
│   │   ├── services/         # API integration
│   │   └── hooks/           # Custom React hooks
│   └── package.json         # Node dependencies
├── logs/                    # Application logs
├── run_backend.ps1          # Backend launcher
└── run_frontend.ps1         # Frontend launcher
```

## Troubleshooting

### Common Issues

**"Ollama service not running"**
```powershell
# Start Ollama manually
ollama serve

# Or restart with optimization script
.\04c-OllamaTuning.ps1
```

**"Backend not responding"**
```powershell
# Check if backend is running
.\run_backend.ps1 -Health

# Check Python packages
py -m pip list | Select-String "fastapi|uvicorn|ollama"
```

**"NPU/GPU not detected"**
```powershell
# Run hardware diagnostics
.\04b-OllamaDiag.ps1

# Force hardware redetection
.\04c-OllamaTuning.ps1 -Detect -Configure
```

**"Slow AI responses"**
```powershell
# Try a smaller model
ollama pull gemma2:2b

# Update .env file
# OLLAMA_MODEL=gemma2:2b

# Restart backend
```

### Checking Logs

All operations are logged with timestamps:
```powershell
# View latest logs
Get-ChildItem logs/*.txt | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# View specific operation logs
Get-Content logs/*backend*.txt -Tail 50
Get-Content logs/*benchmark*.json
```

## Development

### Extending JARVIS

Future enhancements to explore:
- 🎤 Voice input/output (speech_recognition, pyttsx3)
- 🔍 Web search integration (Google/Bing APIs)
- 📊 Data visualization capabilities
- 🔌 Plugin system for custom commands
- 📱 Mobile app development
- ☁️ Cloud deployment options

### Contributing Guidelines

1. Follow the existing PowerShell patterns in scripts
2. Use the Write-Log function for all output
3. Test on both x64 and ARM64 if possible
4. Update personality config for behavior changes
5. Add benchmarks for performance changes

## System Requirements

### Minimum Requirements
- Windows 11 (version 22H2 or later)
- 8GB RAM
- 20GB free disk space
- Internet for initial setup

### Recommended Specifications
- 16GB+ RAM
- NPU or dedicated GPU
- SSD storage
- Persistent internet for model updates

## Security Considerations

- All AI processing is local - no data leaves your machine
- API runs on localhost only by default
- No authentication implemented (add for production use)
- Personality configuration can access local system

## License

This project is provided as-is for educational and personal use. Feel free to modify and extend as needed.

## Acknowledgments

- Inspired by JARVIS from the Marvel Cinematic Universe
- Built with Ollama for local AI processing
- FastAPI and React for modern web architecture
- Community contributions and feedback

---

*"Sometimes you gotta run before you can walk." - Tony Stark*