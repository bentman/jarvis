import ollama
import asyncio
import json
import os
from typing import Optional
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

class AIService:
    def __init__(self, model: str = "llama3.1:8b", ollama_url: str = "http://localhost:11434"):
        self.model = model
        self.ollama_url = ollama_url
        self.client = None
        self.personality_config = self._load_personality_config()
        self._initialize_client()
    
    def _load_personality_config(self):
        """Load personality configuration from jarvis_personality.json"""
        config_path = "../../jarvis_personality.json"  # Go up two levels from backend/services/
        fallback_config_path = "../jarvis_personality.json"  # Try backend/ directory as fallback
        fallback_config_path2 = "jarvis_personality.json"  # Try current directory as last resort
        
        try:
            # Try project root first (normal case when run from backend/services/)
            if os.path.exists(config_path):
                with open(config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    logger.info("Loaded personality config from ../../jarvis_personality.json")
                    return config
            # Try backend directory as fallback
            elif os.path.exists(fallback_config_path):
                with open(fallback_config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    logger.info("Loaded personality config from ../jarvis_personality.json")
                    return config
            # Try current directory as last resort
            elif os.path.exists(fallback_config_path2):
                with open(fallback_config_path2, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    logger.info("Loaded personality config from jarvis_personality.json")
                    return config
            else:
                logger.warning("Personality config file not found, using defaults")
                return self._get_default_personality()
        except Exception as e:
            logger.error(f"Failed to load personality config: {e}")
            return self._get_default_personality()
    
    def _get_default_personality(self):
        """Default personality configuration if file is missing"""
        return {
            "identity": {
                "name": "Jarvis",
                "display_name": "J.A.R.V.I.S.",
                "role": "AI Assistant"
            },
            "personality": {
                "base_personality": "You are Jarvis, an AI assistant inspired by Tony Stark's AI. Be helpful, intelligent, and slightly witty."
            }
        }
    
    def _get_system_prompt(self):
        """Build system prompt from personality configuration"""
        config = self.personality_config
        
        # Start with base personality
        system_prompt = config.get("personality", {}).get(
            "base_personality", 
            "You are Jarvis, an AI assistant. Be helpful and intelligent."
        )
        
        # Add personality traits
        personality = config.get("personality", {})
        if personality.get("tone"):
            system_prompt += f" Your tone should be {personality['tone']}."
        if personality.get("humor_level"):
            system_prompt += f" Use {personality['humor_level']}."
        if personality.get("confidence"):
            system_prompt += f" Be {personality['confidence']}."
        
        # Add behavior guidelines
        behavior = config.get("behavior", {})
        if behavior.get("response_style"):
            system_prompt += f" Keep responses {behavior['response_style']}."
        if behavior.get("problem_solving"):
            system_prompt += f" Approach problems in an {behavior['problem_solving']} way."
        
        # Add interaction style
        interaction = config.get("interaction_style", {})
        if interaction.get("explanation_method"):
            system_prompt += f" When explaining complex topics, {interaction['explanation_method']}."
        
        return system_prompt
    
    def _initialize_client(self):
        """Initialize Ollama client"""
        try:
            # Test if Ollama is available
            import httpx
            response = httpx.get(f"{self.ollama_url}/api/tags", timeout=5)
            if response.status_code == 200:
                self.client = ollama.Client(host=self.ollama_url)
                logger.info(f"Ollama client initialized successfully with personality: {self.personality_config.get('identity', {}).get('name', 'Unknown')}")
            else:
                logger.warning(f"Ollama not available at {self.ollama_url}")
        except Exception as e:
            logger.warning(f"Failed to initialize Ollama client: {e}")
            self.client = None
    
    async def is_available(self) -> bool:
        """Check if AI service is available"""
        if not self.client:
            return False
        
        try:
            # Test with a simple request
            response = await asyncio.get_event_loop().run_in_executor(
                None, 
                lambda: self.client.list()
            )
            return True
        except Exception as e:
            logger.warning(f"AI service not available: {e}")
            return False
    
    async def generate_response(self, message: str) -> dict:
        """Generate AI response with personality configuration"""
        
        # Try AI first
        if self.client:
            try:
                ai_response = await self._generate_ai_response(message)
                if ai_response:
                    return {
                        "response": ai_response,
                        "mode": "ai",
                        "model": self.model,
                        "personality": self.personality_config.get("identity", {}).get("name", "AI"),
                        "timestamp": datetime.now().isoformat()
                    }
            except Exception as e:
                logger.error(f"AI generation failed: {e}")
        
        # Fallback to echo mode with personality
        name = self.personality_config.get("identity", {}).get("name", "Assistant")
        return {
            "response": f"Echo from {name}: {message}",
            "mode": "echo",
            "model": "fallback",
            "personality": name,
            "timestamp": datetime.now().isoformat()
        }
    
    async def _generate_ai_response(self, message: str) -> Optional[str]:
        """Generate response using Ollama with personality"""
        try:
            system_prompt = self._get_system_prompt()
            
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.client.chat(
                    model=self.model,
                    messages=[
                        {
                            'role': 'system',
                            'content': system_prompt
                        },
                        {
                            'role': 'user',
                            'content': message
                        }
                    ]
                )
            )
            return response['message']['content']
        except Exception as e:
            logger.error(f"Ollama generation error: {e}")
            return None
    
    async def get_status(self) -> dict:
        """Get AI service status with personality info"""
        is_available = await self.is_available()
        
        status = {
            "ai_available": is_available,
            "model": self.model if is_available else "unavailable",
            "mode": "ai" if is_available else "echo",
            "ollama_url": self.ollama_url,
            "personality": {
                "name": self.personality_config.get("identity", {}).get("name", "Unknown"),
                "display_name": self.personality_config.get("identity", {}).get("display_name", "AI Assistant"),
                "config_loaded": self.personality_config is not None
            }
        }
        
        if is_available and self.client:
            try:
                models = await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: self.client.list()
                )
                status["available_models"] = [model['name'] for model in models.get('models', [])]
            except:
                pass
        
        return status

# Global AI service instance
ai_service = AIService()