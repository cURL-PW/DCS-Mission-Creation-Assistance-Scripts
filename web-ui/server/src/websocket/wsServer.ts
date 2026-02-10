import { WebSocket, WebSocketServer } from 'ws';
import { IncomingMessage } from 'http';
import { DCSFileWatcher } from '../dcs/fileWatcher';
import { WebSocketEvent, IADSState, Command } from '../types/iads';

export interface WSServerConfig {
  port: number;
  path: string;
}

const DEFAULT_CONFIG: WSServerConfig = {
  port: 3001,
  path: '/ws'
};

interface ExtendedWebSocket extends WebSocket {
  isAlive: boolean;
  clientId: string;
}

export class IADSWebSocketServer {
  private config: WSServerConfig;
  private wss: WebSocketServer | null = null;
  private dcsWatcher: DCSFileWatcher;
  private clients: Map<string, ExtendedWebSocket> = new Map();
  private pingInterval: NodeJS.Timeout | null = null;

  constructor(dcsWatcher: DCSFileWatcher, config: Partial<WSServerConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.dcsWatcher = dcsWatcher;
  }

  public start(httpServer?: unknown): void {
    console.log(`[WSServer] Starting WebSocket server on port ${this.config.port}`);

    this.wss = new WebSocketServer({
      port: this.config.port,
      path: this.config.path
    });

    this.wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
      this.handleConnection(ws as ExtendedWebSocket, req);
    });

    this.wss.on('error', (error) => {
      console.error('[WSServer] Server error:', error);
    });

    // Ping interval for connection health check
    this.pingInterval = setInterval(() => {
      this.pingClients();
    }, 30000);

    // DCSイベントのリレー設定
    this.setupDCSEventRelay();

    console.log(`[WSServer] WebSocket server started on ws://localhost:${this.config.port}${this.config.path}`);
  }

  public stop(): void {
    console.log('[WSServer] Stopping WebSocket server');

    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }

    if (this.wss) {
      this.wss.close();
      this.wss = null;
    }

    this.clients.clear();
  }

  private handleConnection(ws: ExtendedWebSocket, req: IncomingMessage): void {
    const clientId = this.generateClientId();
    ws.clientId = clientId;
    ws.isAlive = true;

    this.clients.set(clientId, ws);
    console.log(`[WSServer] Client connected: ${clientId} (total: ${this.clients.size})`);

    // 初期状態を送信
    const currentState = this.dcsWatcher.getCurrentState();
    if (currentState) {
      this.sendToClient(ws, 'state:update', currentState);
    }

    ws.on('pong', () => {
      ws.isAlive = true;
    });

    ws.on('message', (data) => {
      this.handleMessage(ws, data.toString());
    });

    ws.on('close', () => {
      console.log(`[WSServer] Client disconnected: ${clientId}`);
      this.clients.delete(clientId);
    });

    ws.on('error', (error) => {
      console.error(`[WSServer] Client error (${clientId}):`, error);
      this.clients.delete(clientId);
    });
  }

  private handleMessage(ws: ExtendedWebSocket, message: string): void {
    try {
      const data = JSON.parse(message);

      switch (data.type) {
        case 'ping':
          this.sendToClient(ws, 'pong' as any, { timestamp: Date.now() });
          break;

        case 'command':
          this.handleCommand(ws, data.command as Command);
          break;

        case 'subscribe':
          // Future: implement subscription filtering
          break;

        default:
          console.warn(`[WSServer] Unknown message type: ${data.type}`);
      }
    } catch (error) {
      console.error('[WSServer] Error parsing message:', error);
    }
  }

  private async handleCommand(ws: ExtendedWebSocket, command: Command): Promise<void> {
    try {
      const response = await this.dcsWatcher.sendCommand(command);
      this.sendToClient(ws, 'command:result', response);
    } catch (error) {
      this.sendToClient(ws, 'command:result', {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  }

  private setupDCSEventRelay(): void {
    this.dcsWatcher.on('state:update', (state: IADSState) => {
      this.broadcast('state:update', state);
    });

    this.dcsWatcher.on('sam:stateChange', (data) => {
      this.broadcast('sam:stateChange', data);
    });

    this.dcsWatcher.on('threat:new', (threat) => {
      this.broadcast('threat:new', threat);
    });

    this.dcsWatcher.on('threat:update', (threat) => {
      this.broadcast('threat:update', threat);
    });

    this.dcsWatcher.on('threat:lost', (data) => {
      this.broadcast('threat:lost', data);
    });

    this.dcsWatcher.on('defcon:change', (data) => {
      this.broadcast('defcon:change', data);
    });

    this.dcsWatcher.on('command:result', (response) => {
      this.broadcast('command:result', response);
    });
  }

  private sendToClient<T>(ws: ExtendedWebSocket, type: string, data: T): void {
    if (ws.readyState === WebSocket.OPEN) {
      const event: WebSocketEvent<T> = {
        type: type as any,
        timestamp: Date.now(),
        data
      };
      ws.send(JSON.stringify(event));
    }
  }

  private broadcast<T>(type: string, data: T): void {
    const event: WebSocketEvent<T> = {
      type: type as any,
      timestamp: Date.now(),
      data
    };
    const message = JSON.stringify(event);

    for (const [clientId, ws] of this.clients) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message);
      }
    }
  }

  private pingClients(): void {
    for (const [clientId, ws] of this.clients) {
      if (!ws.isAlive) {
        console.log(`[WSServer] Terminating unresponsive client: ${clientId}`);
        ws.terminate();
        this.clients.delete(clientId);
        continue;
      }

      ws.isAlive = false;
      ws.ping();
    }
  }

  private generateClientId(): string {
    return `client_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  public getClientCount(): number {
    return this.clients.size;
  }
}
