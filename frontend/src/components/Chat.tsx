import React, { useState, useRef, useEffect } from 'react';
import { Send, Bot, User, Wifi, WifiOff, Cpu } from 'lucide-react';
import { useChat } from '../hooks/useChat';
import { Message } from '../types';

interface MessageBubbleProps {
  message: Message;
}

function MessageBubble({ message }: MessageBubbleProps) {
  const isUser = message.sender === 'user';
  const isError = message.mode === 'error';
  const isAI = message.mode === 'ai';

  return (
    <div style={{
      marginBottom: '20px',
      display: 'flex',
      gap: '15px',
      alignItems: 'flex-start',
      width: '100%',
      flexDirection: isUser ? 'row-reverse' : 'row',
      justifyContent: isUser ? 'flex-start' : 'flex-start'
    }}>
      <div style={{
        width: '40px',
        height: '40px',
        borderRadius: '50%',
        backgroundColor: isUser ? '#3b82f6' : isError ? '#ef4444' : '#00d4ff',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexShrink: 0
      }}>
        {isUser ? <User size={20} color="white" /> : <Bot size={20} color={isUser || isError ? "white" : "#050810"} />}
      </div>
      <div style={{
        background: isUser ? '#3b82f6' : isError ? '#7f1d1d' : isAI ? '#1a2332' : '#1a2332',
        color: isUser ? '#ffffff' : isError ? '#fecaca' : isAI ? '#00d4ff' : '#ffffff',
        padding: '20px 25px',
        borderRadius: '20px',
        maxWidth: '70%',
        fontSize: '18px',
        lineHeight: '1.6',
        border: isAI ? '2px solid rgba(0, 212, 255, 0.4)' : isError ? '2px solid #ef4444' : 'none'
      }}>
        <p style={{ margin: 0, fontSize: '18px', lineHeight: '1.6' }}>{message.content}</p>
        <div style={{ fontSize: '14px', opacity: 0.8, marginTop: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span>{new Date(message.timestamp).toLocaleTimeString()}</span>
          {message.mode && message.mode !== 'system' && (
            <>
              <span>•</span>
              <span style={{ textTransform: 'capitalize' }}>{message.mode}</span>
            </>
          )}
          {message.model && message.model !== 'welcome' && (
            <>
              <span>•</span>
              <span>{message.model}</span>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

export function Chat() {
  const [input, setInput] = useState('');
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const { 
    messages, 
    isLoading, 
    aiStatus, 
    isConnected, 
    error, 
    sendMessage, 
    clearChat,
    checkStatus 
  } = useChat();

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    const message = input.trim();
    setInput('');
    await sendMessage(message);
  };

  return (
    <div style={{
      width: '100vw',
      height: '100vh',
      display: 'flex',
      flexDirection: 'column',
      background: '#050810',
      color: '#ffffff',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      margin: 0,
      padding: 0
    }}>
      {/* Header */}
      <div style={{
        background: '#0a0e1a',
        color: '#ffffff',
        padding: '25px',
        borderBottom: '1px solid #1a2332',
        width: '100%',
        flexShrink: 0
      }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
            <div style={{ position: 'relative' }}>
              <div style={{
                width: '50px',
                height: '50px',
                backgroundColor: '#00d4ff',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}>
                <Bot size={30} color="#050810" />
              </div>
              <div style={{
                position: 'absolute',
                bottom: '-2px',
                right: '-2px',
                width: '18px',
                height: '18px',
                borderRadius: '50%',
                border: '3px solid #0a0e1a',
                backgroundColor: isConnected ? '#10b981' : '#ef4444'
              }} />
            </div>
            <div>
              <h1 style={{
                color: '#00d4ff',
                fontSize: '32px',
                fontWeight: 'bold',
                margin: 0
              }}>J.A.R.V.I.S.</h1>
              <p style={{
                margin: '8px 0 0 0',
                fontSize: '18px',
                color: '#9ca3af'
              }}>
                {isConnected ? 'Connected' : 'Disconnected'} • {aiStatus?.mode || 'Unknown'}
              </p>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
            <button
              onClick={checkStatus}
              style={{
                background: 'none',
                border: 'none',
                color: '#ffffff',
                padding: '12px',
                cursor: 'pointer',
                borderRadius: '10px'
              }}
              title="Check Connection"
            >
              {isConnected ? (
                <Wifi size={24} color="#10b981" />
              ) : (
                <WifiOff size={24} color="#ef4444" />
              )}
            </button>

            {aiStatus && (
              <div style={{
                padding: '12px 18px',
                borderRadius: '10px',
                display: 'flex',
                alignItems: 'center',
                gap: '10px',
                background: aiStatus.ai_available ? '#065f46' : '#92400e',
                color: aiStatus.ai_available ? '#10b981' : '#fbbf24'
              }}>
                <Cpu size={18} />
                <span style={{ fontSize: '16px', fontWeight: '500' }}>
                  {aiStatus.ai_available ? 'AI Online' : 'Echo Mode'}
                </span>
              </div>
            )}

            <button
              onClick={clearChat}
              style={{
                background: '#1a2332',
                color: '#ffffff',
                border: 'none',
                padding: '12px 20px',
                borderRadius: '8px',
                cursor: 'pointer',
                fontSize: '16px'
              }}
            >
              Clear
            </button>
          </div>
        </div>

        {error && (
          <div style={{
            marginTop: '15px',
            padding: '15px',
            background: '#7f1d1d',
            border: '2px solid #ef4444',
            borderRadius: '10px',
            fontSize: '16px',
            color: '#fecaca'
          }}>
            {error}
          </div>
        )}
      </div>

      {/* Messages */}
      <div style={{
        flex: 1,
        padding: '25px',
        overflowY: 'auto',
        background: '#050810',
        width: '100%',
        minHeight: 0
      }}>
        {messages.map((message) => (
          <MessageBubble key={message.id} message={message} />
        ))}
        
        {isLoading && (
          <div style={{ display: 'flex', justifyContent: 'flex-start', marginBottom: '20px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
              <div style={{
                width: '40px',
                height: '40px',
                backgroundColor: '#00d4ff',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}>
                <Bot size={20} color="#050810" />
              </div>
              <div style={{
                backgroundColor: '#1a2332',
                borderRadius: '20px',
                padding: '15px 20px'
              }}>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <div style={{ width: '12px', height: '12px', backgroundColor: '#00d4ff', borderRadius: '50%' }} />
                  <div style={{ width: '12px', height: '12px', backgroundColor: '#00d4ff', borderRadius: '50%' }} />
                  <div style={{ width: '12px', height: '12px', backgroundColor: '#00d4ff', borderRadius: '50%' }} />
                </div>
              </div>
            </div>
          </div>
        )}
        
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <div style={{
        background: '#0a0e1a',
        padding: '25px',
        borderTop: '1px solid #1a2332',
        width: '100%',
        flexShrink: 0
      }}>
        <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '15px', width: '100%' }}>
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask Jarvis anything..."
            style={{
              flex: 1,
              background: '#1a2332',
              border: '2px solid rgba(0, 212, 255, 0.4)',
              borderRadius: '15px',
              padding: '20px 25px',
              color: '#ffffff',
              fontSize: '18px',
              outline: 'none'
            }}
            disabled={isLoading || !isConnected}
          />
          <button
            type="submit"
            disabled={isLoading || !isConnected || !input.trim()}
            style={{
              background: (!isLoading && isConnected && input.trim()) ? '#00d4ff' : '#6b7280',
              color: '#050810',
              border: 'none',
              borderRadius: '15px',
              padding: '20px 30px',
              cursor: (!isLoading && isConnected && input.trim()) ? 'pointer' : 'not-allowed',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}
          >
            <Send size={22} />
          </button>
        </form>
      </div>
    </div>
  );
}
