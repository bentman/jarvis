# Jarvis AI Assistant

A learning project for building a full-stack AI assistant with local AI capabilities. This is an educational implementation designed to be extended and built upon.

## Overview

Jarvis is a web-based AI assistant that combines a FastAPI backend with a React frontend and local AI processing through Ollama. The project demonstrates modern web development practices while providing a foundation for AI integration experiments.

## Architecture

- **Backend**: FastAPI with Python, providing REST API endpoints
- **Frontend**: React application with TypeScript for the chat interface  
- **AI Engine**: Ollama for local AI model execution
- **Database**: File-based configuration (expandable to databases)

## Features

- Real-time chat interface with AI responses
- Configurable AI personality through JSON configuration
- Fallback mode when AI services are unavailable
- RESTful API with automatic documentation
- Local AI processing (no external API dependencies)
- Cross-platform compatibility

## Prerequisites

- Node.js (v16 or higher)
- Python 3.11 or higher
- Git
- Ollama (for AI functionality)

## Quick Start

### Automated Setup

Run the setup scripts in order:

```powershell
.\01-Prerequisites.ps1
.\02-SimpleFastApiBackend.ps1 -All
.\03-OllamaIntegration.ps1 -All
.\04-OllamaSetupAndTesting.ps1 -All
.\05-ReactFrontend.ps1 -All
```

### Manual Setup

1. Install backend dependencies:
```powershell
cd backend
pip install -r requirements.txt
```

2. Install frontend dependencies:
```powershell
cd frontend
npm install
```

3. Install and setup Ollama:
```powershell
# Install Ollama (see ollama.com for instructions)
ollama serve
ollama pull llama3.1:8b
```

### Running the Application

#### Option 1: Control Center (Recommended)
```powershell
.\run_jarvis.ps1
```
Select option 2 to start all services in separate windows.

#### Option 2: Manual Startup
Start backend:
```powershell
.\run_backend.ps1
```

Start frontend (in new terminal):
```powershell
.\run_frontend.ps1
```

## Usage

1. Start the application using one of the methods above
2. Open your browser to http://localhost:3000
3. Begin chatting with the AI assistant
4. The AI will respond using the configured personality

## Configuration

### Personality Configuration

Edit `jarvis_personality.json` to customize the AI's behavior:

```json
{
  "identity": {
    "name": "Jarvis",
    "display_name": "J.A.R.V.I.S."
  },
  "personality": {
    "base_personality": "You are Jarvis, an AI assistant...",
    "tone": "professional yet friendly"
  }
}
```

Restart the backend after making changes.

### Environment Variables

Backend configuration in `.env`:
- `API_HOST`: Backend host (default: 0.0.0.0)
- `API_PORT`: Backend port (default: 8000)
- `OLLAMA_URL`: Ollama service URL (default: http://localhost:11434)

## API Endpoints

### Core Endpoints
- `GET /` - Service information
- `GET /api/health` - Health check with system status
- `POST /api/chat` - Send message to AI assistant
- `GET /api/status` - Detailed service status

### AI-Specific Endpoints  
- `GET /api/ai/status` - AI service status and available models
- `GET /api/ai/test` - Test AI connectivity

## Project Structure

```
jarvis/
├── jarvis_personality.json    # AI personality configuration
├── backend/                   # FastAPI backend
│   ├── api/                  
│   │   └── main.py           # Main application
│   ├── services/
│   │   └── ai_service.py     # AI integration service
│   ├── tests/                # Backend tests
│   └── requirements.txt      # Python dependencies
├── frontend/                 # React frontend
│   ├── src/
│   │   ├── components/       # React components
│   │   ├── services/         # API services
│   │   └── hooks/           # Custom React hooks
│   └── package.json         # Node dependencies
├── run_backend.ps1          # Backend startup script
├── run_frontend.ps1         # Frontend startup script
└── run_jarvis.ps1          # Application control center
```

## Learning Objectives

This project demonstrates:

- Full-stack web application development
- REST API design and implementation
- React application development with TypeScript
- AI integration and fallback handling
- Configuration management
- Testing strategies for AI applications
- Local AI deployment and management

## Extending the Project

### Potential Enhancements

- Voice recognition and text-to-speech
- Multi-user support with authentication
- Database integration for conversation history
- Plugin system for extended functionality
- Mobile application development
- Cloud deployment and scaling
- Advanced AI model fine-tuning

### Development Guidelines

- Follow existing code structure and naming conventions
- Add tests for new functionality
- Update documentation for new features
- Consider backwards compatibility when making changes
- Use the personality configuration system for AI behavior changes

## Troubleshooting

### Common Issues

**AI responses not working**: Ensure Ollama is running and a model is installed
**Frontend cannot connect**: Verify backend is running on port 8000
**Import errors**: Check that you're running commands from the correct directory
**Port conflicts**: Ensure ports 3000 and 8000 are available

### Getting Help

- Check the application logs in the terminal windows
- Visit http://localhost:8000/docs for API documentation
- Test individual components using the provided scripts
- Review the personality configuration for AI behavior issues

## Contributing

This is a learning project. Feel free to:

- Fork and experiment with different features
- Try different AI models and configurations
- Implement additional frontend components
- Explore different deployment strategies
- Share improvements and lessons learned

## License

This project is for educational purposes. Use and modify as needed for learning and development.

## Acknowledgments

Built as a learning exercise for exploring modern web development and AI integration technologies.