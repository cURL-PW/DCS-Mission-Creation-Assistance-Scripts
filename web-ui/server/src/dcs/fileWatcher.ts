import * as fs from 'fs';
import * as path from 'path';
import * as chokidar from 'chokidar';
import { EventEmitter } from 'events';
import { v4 as uuidv4 } from 'uuid';
import { IADSState, CommandBatch, CommandResponse, Command } from '../types/iads';

export interface DCSFileWatcherConfig {
  statePath: string;
  commandPath: string;
  responsePath: string;
  pollInterval: number;
}

const DEFAULT_CONFIG: DCSFileWatcherConfig = {
  statePath: '',
  commandPath: '',
  responsePath: '',
  pollInterval: 500
};

export class DCSFileWatcher extends EventEmitter {
  private config: DCSFileWatcherConfig;
  private watcher: chokidar.FSWatcher | null = null;
  private currentState: IADSState | null = null;
  private previousState: IADSState | null = null;
  private pendingCommands: Map<string, { resolve: (value: CommandResponse) => void; reject: (reason: Error) => void; timeout: NodeJS.Timeout }> = new Map();

  constructor(config: Partial<DCSFileWatcherConfig> = {}) {
    super();

    // DCS Saved Games パスを自動検出
    const dcsPath = this.detectDCSPath();

    this.config = {
      ...DEFAULT_CONFIG,
      statePath: path.join(dcsPath, 'iads_state.json'),
      commandPath: path.join(dcsPath, 'iads_commands.json'),
      responsePath: path.join(dcsPath, 'iads_response.json'),
      ...config
    };
  }

  private detectDCSPath(): string {
    const userProfile = process.env.USERPROFILE || process.env.HOME || '';

    // Windows DCS paths
    const possiblePaths = [
      path.join(userProfile, 'Saved Games', 'DCS.openbeta'),
      path.join(userProfile, 'Saved Games', 'DCS'),
      path.join(userProfile, 'Saved Games', 'DCS.stable'),
      // Linux/macOS for testing
      '/tmp/dcs'
    ];

    for (const p of possiblePaths) {
      if (fs.existsSync(p)) {
        return p;
      }
    }

    // Default to first option even if it doesn't exist
    return possiblePaths[0];
  }

  public getConfig(): DCSFileWatcherConfig {
    return { ...this.config };
  }

  public getCurrentState(): IADSState | null {
    return this.currentState;
  }

  public start(): void {
    console.log(`[DCSFileWatcher] Starting file watcher`);
    console.log(`[DCSFileWatcher] State path: ${this.config.statePath}`);
    console.log(`[DCSFileWatcher] Command path: ${this.config.commandPath}`);

    // 状態ファイルの監視
    this.watcher = chokidar.watch(this.config.statePath, {
      persistent: true,
      ignoreInitial: false,
      usePolling: true,
      interval: this.config.pollInterval
    });

    this.watcher.on('add', (path) => this.onStateFileChange(path));
    this.watcher.on('change', (path) => this.onStateFileChange(path));
    this.watcher.on('error', (error) => {
      console.error(`[DCSFileWatcher] Watcher error:`, error);
      this.emit('error', error);
    });

    // レスポンスファイルの監視（コマンド結果用）
    const responseWatcher = chokidar.watch(this.config.responsePath, {
      persistent: true,
      ignoreInitial: true,
      usePolling: true,
      interval: this.config.pollInterval
    });

    responseWatcher.on('add', (path) => this.onResponseFileChange(path));
    responseWatcher.on('change', (path) => this.onResponseFileChange(path));
  }

  public stop(): void {
    console.log(`[DCSFileWatcher] Stopping file watcher`);
    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
    }

    // Pending commands のタイムアウトをクリア
    for (const [commandId, pending] of this.pendingCommands) {
      clearTimeout(pending.timeout);
      pending.reject(new Error('Watcher stopped'));
    }
    this.pendingCommands.clear();
  }

  private onStateFileChange(filePath: string): void {
    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      const state = JSON.parse(content) as IADSState;

      // 差分検出
      if (this.previousState) {
        this.detectChanges(this.previousState, state);
      }

      this.previousState = this.currentState;
      this.currentState = state;

      this.emit('state:update', state);
    } catch (error) {
      console.error(`[DCSFileWatcher] Error reading state file:`, error);
    }
  }

  private onResponseFileChange(filePath: string): void {
    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      const response = JSON.parse(content) as CommandResponse;

      // Delete response file after reading
      fs.unlinkSync(filePath);

      const pending = this.pendingCommands.get(response.commandId);
      if (pending) {
        clearTimeout(pending.timeout);
        this.pendingCommands.delete(response.commandId);
        pending.resolve(response);
      }

      this.emit('command:result', response);
    } catch (error) {
      console.error(`[DCSFileWatcher] Error reading response file:`, error);
    }
  }

  private detectChanges(oldState: IADSState, newState: IADSState): void {
    // DEFCON変更検出
    if (oldState.defcon !== newState.defcon) {
      this.emit('defcon:change', {
        oldLevel: oldState.defcon,
        newLevel: newState.defcon
      });
    }

    // SAM状態変更検出
    for (const [name, newSam] of Object.entries(newState.samSites)) {
      const oldSam = oldState.samSites[name];
      if (oldSam && oldSam.state !== newSam.state) {
        this.emit('sam:stateChange', {
          samName: name,
          oldState: oldSam.state,
          newState: newSam.state
        });
      }
    }

    // 新規脅威検出
    for (const [id, threat] of Object.entries(newState.threats)) {
      if (!oldState.threats[id]) {
        this.emit('threat:new', threat);
      } else {
        // 脅威更新
        const oldThreat = oldState.threats[id];
        if (JSON.stringify(oldThreat) !== JSON.stringify(threat)) {
          this.emit('threat:update', threat);
        }
      }
    }

    // 脅威消失検出
    for (const id of Object.keys(oldState.threats)) {
      if (!newState.threats[id]) {
        this.emit('threat:lost', { id });
      }
    }
  }

  public async sendCommand(command: Command): Promise<CommandResponse> {
    return this.sendCommands([command]);
  }

  public async sendCommands(commands: Command[]): Promise<CommandResponse> {
    const commandId = uuidv4();
    const batch: CommandBatch = {
      commandId,
      timestamp: Date.now(),
      commands
    };

    return new Promise((resolve, reject) => {
      // タイムアウト設定（10秒）
      const timeout = setTimeout(() => {
        this.pendingCommands.delete(commandId);
        reject(new Error('Command timeout'));
      }, 10000);

      this.pendingCommands.set(commandId, { resolve, reject, timeout });

      // コマンドファイル書き込み
      try {
        fs.writeFileSync(this.config.commandPath, JSON.stringify(batch, null, 2));
        console.log(`[DCSFileWatcher] Command sent: ${commandId}`);
      } catch (error) {
        clearTimeout(timeout);
        this.pendingCommands.delete(commandId);
        reject(error);
      }
    });
  }
}
