export interface Message {
  id: string;
  content: string;
  sender: 'user' | 'jarvis';
  timestamp: string;
  mode?: string;
  model?: string;
}

export interface AIStatus {
  ai_available: boolean;
  model: string;
  mode: string;
  ollama_url: string;
  available_models?: string[];
}

export interface AppState {
  messages: Message[];
  isConnected: boolean;
  aiStatus: AIStatus | null;
  isLoading: boolean;
  error: string | null;
}
