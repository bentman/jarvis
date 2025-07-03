import { useState, useCallback, useEffect } from 'react';
import { ApiService } from '../services/api';
import { Message, AIStatus } from '../types';

export function useChat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [aiStatus, setAIStatus] = useState<AIStatus | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Check connection and AI status
  const checkStatus = useCallback(async () => {
    try {
      await ApiService.getHealth();
      const aiStat = await ApiService.getAIStatus();
      
      setIsConnected(true);
      setAIStatus(aiStat);
      setError(null);
    } catch (err) {
      setIsConnected(false);
      setError('Cannot connect to Jarvis backend');
      console.error('Status check failed:', err);
    }
  }, []);

  // Send message to AI
  const sendMessage = useCallback(async (content: string) => {
    if (!content.trim()) return;

    const userMessage: Message = {
      id: Date.now().toString(),
      content,
      sender: 'user',
      timestamp: new Date().toISOString(),
    };

    setMessages(prev => [...prev, userMessage]);
    setIsLoading(true);
    setError(null);

    try {
      const response = await ApiService.sendMessage(content);
      
      const jarvisMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: response.response,
        sender: 'jarvis',
        timestamp: response.timestamp,
        mode: response.mode,
        model: response.model,
      };

      setMessages(prev => [...prev, jarvisMessage]);
    } catch (err) {
      setError('Failed to get response from Jarvis');
      console.error('Send message failed:', err);
      
      // Add error message
      const errorMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: 'I apologize, but I am experiencing technical difficulties. Please check the backend connection.',
        sender: 'jarvis',
        timestamp: new Date().toISOString(),
        mode: 'error',
        model: 'fallback',
      };
      
      setMessages(prev => [...prev, errorMessage]);
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Clear chat
  const clearChat = useCallback(() => {
    setMessages([]);
    setError(null);
  }, []);

  // Initial status check
  useEffect(() => {
    checkStatus();
    
    // Add welcome message
    const welcomeMessage: Message = {
      id: 'welcome',
      content: 'Hello! I am Jarvis, your AI assistant. How can I help you today?',
      sender: 'jarvis',
      timestamp: new Date().toISOString(),
      mode: 'system',
      model: 'welcome',
    };
    
    setMessages([welcomeMessage]);
  }, [checkStatus]);

  return {
    messages,
    isLoading,
    aiStatus,
    isConnected,
    error,
    sendMessage,
    clearChat,
    checkStatus,
  };
}
