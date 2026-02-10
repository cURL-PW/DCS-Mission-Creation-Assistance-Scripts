import { v4 as uuidv4 } from 'uuid';
import { Session, Coalition, AccessLevel } from '../types/iads';

export interface SessionManagerConfig {
  sessionTimeout: number;  // ミリ秒
  cleanupInterval: number; // ミリ秒
}

const DEFAULT_CONFIG: SessionManagerConfig = {
  sessionTimeout: 30 * 60 * 1000,  // 30分
  cleanupInterval: 5 * 60 * 1000   // 5分
};

export class SessionManager {
  private sessions: Map<string, Session> = new Map();
  private config: SessionManagerConfig;
  private cleanupTimer: NodeJS.Timeout | null = null;

  constructor(config: Partial<SessionManagerConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  public start(): void {
    this.cleanupTimer = setInterval(() => {
      this.cleanupExpiredSessions();
    }, this.config.cleanupInterval);
  }

  public stop(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = null;
    }
  }

  public createSession(
    coalition: Coalition,
    accessLevel: AccessLevel = AccessLevel.VIEW,
    playerName: string = 'Anonymous'
  ): Session {
    const session: Session = {
      id: uuidv4(),
      coalition,
      accessLevel,
      playerName,
      createdAt: Date.now(),
      lastActivity: Date.now()
    };

    this.sessions.set(session.id, session);
    console.log(`[SessionManager] Session created: ${session.id} (${playerName}, coalition=${coalition})`);

    return session;
  }

  public getSession(sessionId: string): Session | undefined {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.lastActivity = Date.now();
    }
    return session;
  }

  public validateSession(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    const isExpired = Date.now() - session.lastActivity > this.config.sessionTimeout;
    if (isExpired) {
      this.destroySession(sessionId);
      return false;
    }

    session.lastActivity = Date.now();
    return true;
  }

  public updateSession(sessionId: string, updates: Partial<Session>): Session | undefined {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return undefined;
    }

    Object.assign(session, updates, { lastActivity: Date.now() });
    return session;
  }

  public destroySession(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (session) {
      console.log(`[SessionManager] Session destroyed: ${sessionId}`);
      this.sessions.delete(sessionId);
      return true;
    }
    return false;
  }

  public getSessionsByCoalition(coalition: Coalition): Session[] {
    const result: Session[] = [];
    for (const session of this.sessions.values()) {
      if (session.coalition === coalition || coalition === Coalition.ALL) {
        result.push(session);
      }
    }
    return result;
  }

  public getSessionCount(): number {
    return this.sessions.size;
  }

  public getAllSessions(): Session[] {
    return Array.from(this.sessions.values());
  }

  private cleanupExpiredSessions(): void {
    const now = Date.now();
    let cleanedCount = 0;

    for (const [sessionId, session] of this.sessions) {
      if (now - session.lastActivity > this.config.sessionTimeout) {
        this.sessions.delete(sessionId);
        cleanedCount++;
      }
    }

    if (cleanedCount > 0) {
      console.log(`[SessionManager] Cleaned up ${cleanedCount} expired sessions`);
    }
  }

  // 認可チェック
  public checkAccess(
    sessionId: string,
    requiredLevel: AccessLevel,
    targetCoalition?: Coalition
  ): { authorized: boolean; reason?: string } {
    const session = this.getSession(sessionId);

    if (!session) {
      return { authorized: false, reason: 'Invalid or expired session' };
    }

    // アクセスレベルチェック
    if (session.accessLevel < requiredLevel) {
      return {
        authorized: false,
        reason: `Insufficient access level (required: ${requiredLevel}, have: ${session.accessLevel})`
      };
    }

    // コアリションチェック（ターゲットが指定されている場合）
    if (targetCoalition !== undefined && session.coalition !== Coalition.ALL) {
      if (session.coalition !== targetCoalition) {
        return {
          authorized: false,
          reason: 'Cannot access enemy coalition resources'
        };
      }
    }

    return { authorized: true };
  }
}

// シングルトンインスタンス
export const sessionManager = new SessionManager();
