import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8000';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

export interface ChatMessage {
  content: string;
}

export interface ChatResponse {
  response: string;
  mode: string;
  model: string;
  timestamp: string;
}

export interface AIStatus {
  ai_available: boolean;
  model: string;
  mode: string;
  ollama_url: string;
  available_models?: string[];
}

export interface HealthStatus {
  status: string;
  service: string;
  version: string;
  ai_integration: AIStatus;
  timestamp: string;
}

export class ApiService {
  static async sendMessage(content: string): Promise<ChatResponse> {
    const response = await api.post<ChatResponse>('/api/chat', { content });
    return response.data;
  }

  static async getHealth(): Promise<HealthStatus> {
    const response = await api.get<HealthStatus>('/api/health');
    return response.data;
  }

  static async getAIStatus(): Promise<AIStatus> {
    const response = await api.get<AIStatus>('/api/ai/status');
    return response.data;
  }

  static async testAI(): Promise<any> {
    const response = await api.get('/api/ai/test');
    return response.data;
  }

  static async getStatus(): Promise<any> {
    const response = await api.get('/api/status');
    return response.data;
  }
}

export default ApiService;
