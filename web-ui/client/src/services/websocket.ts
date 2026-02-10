import { useIADSStore } from '../store/iadsStore';
import { WebSocketEvent, IADSState } from '../types/iads';

const WS_URL = 'ws://localhost:3002/ws';
const RECONNECT_DELAY = 3000;
const MAX_RECONNECT_ATTEMPTS = 10;

class WebSocketService {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private reconnectTimeout: number | null = null;

  public connect(): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      return;
    }

    console.log('[WebSocket] Connecting to', WS_URL);
    this.ws = new WebSocket(WS_URL);

    this.ws.onopen = () => {
      console.log('[WebSocket] Connected');
      this.reconnectAttempts = 0;
      useIADSStore.getState().setConnected(true);
    };

    this.ws.onclose = () => {
      console.log('[WebSocket] Disconnected');
      useIADSStore.getState().setConnected(false);
      this.scheduleReconnect();
    };

    this.ws.onerror = (error) => {
      console.error('[WebSocket] Error:', error);
      useIADSStore.getState().setError('WebSocket connection error');
    };

    this.ws.onmessage = (event) => {
      this.handleMessage(event.data);
    };
  }

  public disconnect(): void {
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }

    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
      console.log('[WebSocket] Max reconnect attempts reached');
      useIADSStore.getState().setError('Failed to connect to server');
      return;
    }

    this.reconnectAttempts++;
    console.log(`[WebSocket] Reconnecting in ${RECONNECT_DELAY}ms (attempt ${this.reconnectAttempts})`);

    this.reconnectTimeout = window.setTimeout(() => {
      this.connect();
    }, RECONNECT_DELAY);
  }

  private handleMessage(data: string): void {
    try {
      const event = JSON.parse(data) as WebSocketEvent;

      switch (event.type) {
        case 'state:update':
          useIADSStore.getState().setState(event.data as IADSState);
          break;

        case 'sam:stateChange':
          console.log('[WebSocket] SAM state changed:', event.data);
          break;

        case 'threat:new':
          console.log('[WebSocket] New threat:', event.data);
          break;

        case 'threat:update':
          console.log('[WebSocket] Threat updated:', event.data);
          break;

        case 'threat:lost':
          console.log('[WebSocket] Threat lost:', event.data);
          break;

        case 'defcon:change':
          console.log('[WebSocket] DEFCON changed:', event.data);
          break;

        case 'command:result':
          console.log('[WebSocket] Command result:', event.data);
          break;

        default:
          console.log('[WebSocket] Unknown event:', event);
      }
    } catch (error) {
      console.error('[WebSocket] Failed to parse message:', error);
    }
  }

  public send(data: unknown): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    } else {
      console.warn('[WebSocket] Cannot send - not connected');
    }
  }

  public sendCommand(command: unknown): void {
    this.send({
      type: 'command',
      command
    });
  }
}

export const wsService = new WebSocketService();
