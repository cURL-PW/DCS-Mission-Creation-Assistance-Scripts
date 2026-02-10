import { Router, Request, Response, NextFunction } from 'express';
import { DCSFileWatcher } from '../dcs/fileWatcher';
import { sessionManager } from './sessionManager';
import {
  SAMState,
  DEFCONLevel,
  TacticalMode,
  SetSAMStateCommand,
  SetAllSAMsStateCommand,
  SetDEFCONCommand,
  SetTacticalModeCommand,
  Command,
  Coalition,
  AccessLevel,
  Session
} from '../types/iads';

// セッション付きリクエスト型
interface AuthenticatedRequest extends Request {
  session?: Session;
}

export function createApiRouter(dcsWatcher: DCSFileWatcher): Router {
  const router = Router();

  // ========== セッション/認証 ==========

  /**
   * POST /api/session
   * 新規セッション作成（ログイン）
   */
  router.post('/session', (req: Request, res: Response) => {
    const { coalition, playerName, accessLevel } = req.body as {
      coalition: Coalition;
      playerName?: string;
      accessLevel?: AccessLevel;
    };

    if (coalition === undefined || ![Coalition.RED, Coalition.BLUE, Coalition.NEUTRAL, Coalition.ALL].includes(coalition)) {
      return res.status(400).json({
        error: 'Invalid coalition',
        validCoalitions: ['RED (1)', 'BLUE (2)', 'NEUTRAL (0)', 'ALL (-1, for Game Master)']
      });
    }

    const session = sessionManager.createSession(
      coalition,
      accessLevel || AccessLevel.OPERATOR,
      playerName || 'Anonymous'
    );

    res.json({
      sessionId: session.id,
      coalition: session.coalition,
      accessLevel: session.accessLevel,
      playerName: session.playerName,
      expiresIn: 30 * 60 * 1000 // 30分
    });
  });

  /**
   * GET /api/session
   * 現在のセッション情報取得
   */
  router.get('/session', (req: Request, res: Response) => {
    const sessionId = req.headers['x-session-id'] as string;

    if (!sessionId) {
      return res.status(401).json({ error: 'No session ID provided' });
    }

    const session = sessionManager.getSession(sessionId);
    if (!session) {
      return res.status(401).json({ error: 'Invalid or expired session' });
    }

    res.json({
      sessionId: session.id,
      coalition: session.coalition,
      accessLevel: session.accessLevel,
      playerName: session.playerName,
      createdAt: session.createdAt
    });
  });

  /**
   * DELETE /api/session
   * セッション削除（ログアウト）
   */
  router.delete('/session', (req: Request, res: Response) => {
    const sessionId = req.headers['x-session-id'] as string;

    if (!sessionId) {
      return res.status(401).json({ error: 'No session ID provided' });
    }

    const destroyed = sessionManager.destroySession(sessionId);
    res.json({ success: destroyed });
  });

  /**
   * GET /api/sessions
   * 全セッション一覧（管理者用）
   */
  router.get('/sessions', (req: Request, res: Response) => {
    const sessionId = req.headers['x-session-id'] as string;
    const session = sessionManager.getSession(sessionId);

    // 管理者権限チェック
    if (!session || session.accessLevel < AccessLevel.ADMIN) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const sessions = sessionManager.getAllSessions();
    res.json({
      count: sessions.length,
      sessions: sessions.map(s => ({
        id: s.id,
        coalition: s.coalition,
        accessLevel: s.accessLevel,
        playerName: s.playerName,
        createdAt: s.createdAt,
        lastActivity: s.lastActivity
      }))
    });
  });

  // ========== コアリション別データ ==========

  /**
   * GET /api/coalition/:id
   * コアリション別のデータを取得
   */
  router.get('/coalition/:id', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    const coalitionId = parseInt(req.params.id, 10);
    if (isNaN(coalitionId) || ![Coalition.RED, Coalition.BLUE].includes(coalitionId)) {
      return res.status(400).json({
        error: 'Invalid coalition ID',
        validIds: ['1 (RED)', '2 (BLUE)']
      });
    }

    // セッションのコアリションチェック
    const sessionId = req.headers['x-session-id'] as string;
    if (sessionId) {
      const session = sessionManager.getSession(sessionId);
      if (session && session.coalition !== Coalition.ALL && session.coalition !== coalitionId) {
        return res.status(403).json({ error: 'Cannot access enemy coalition data' });
      }
    }

    const coalitionKey = coalitionId === Coalition.RED ? 'red' : 'blue';
    const coalitionData = state.coalitionData?.[coalitionKey];

    if (!coalitionData) {
      return res.status(404).json({ error: 'Coalition data not available' });
    }

    res.json({
      coalition: coalitionId,
      coalitionName: coalitionKey.toUpperCase(),
      ...coalitionData
    });
  });

  /**
   * GET /api/multiplayer
   * マルチプレイヤー情報を取得
   */
  router.get('/multiplayer', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    res.json(state.multiplayer || {
      isMultiplayer: false,
      isServer: false,
      serverName: '',
      players: [],
      coalitions: {
        red: { name: 'Red', playerCount: 0 },
        blue: { name: 'Blue', playerCount: 0 }
      }
    });
  });

  // ========== ステータス ==========

  /**
   * GET /api/status
   * 全体ステータスを取得
   */
  router.get('/status', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({
        error: 'No state available',
        message: 'DCS is not connected or no data has been received yet'
      });
    }

    res.json({
      connected: true,
      timestamp: state.timestamp,
      missionTime: state.missionTime,
      defcon: state.defcon,
      tacticalMode: state.tacticalMode,
      statistics: state.statistics
    });
  });

  /**
   * GET /api/state
   * 完全な状態データを取得
   */
  router.get('/state', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({
        error: 'No state available'
      });
    }
    res.json(state);
  });

  // ========== SAMサイト ==========

  /**
   * GET /api/sams
   * SAMサイト一覧を取得
   */
  router.get('/sams', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    let sams = Object.values(state.samSites);

    // セッションによるコアリションフィルタリング
    const sessionId = req.headers['x-session-id'] as string;
    if (sessionId) {
      const session = sessionManager.getSession(sessionId);
      if (session && session.coalition !== Coalition.ALL) {
        sams = sams.filter(s => s.coalition === session.coalition);
      }
    }

    // クエリによるフィルタリング
    const { state: stateFilter, type: typeFilter, coalition: coalitionFilter } = req.query;
    let filtered = sams;

    if (stateFilter) {
      filtered = filtered.filter(s => s.state === stateFilter);
    }
    if (typeFilter) {
      filtered = filtered.filter(s => s.type === typeFilter);
    }
    if (coalitionFilter) {
      const coalId = parseInt(coalitionFilter as string, 10);
      if (!isNaN(coalId)) {
        filtered = filtered.filter(s => s.coalition === coalId);
      }
    }

    res.json({
      count: filtered.length,
      sams: filtered
    });
  });

  /**
   * GET /api/sams/:name
   * 特定SAMの詳細を取得
   */
  router.get('/sams/:name', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    const sam = state.samSites[req.params.name];
    if (!sam) {
      return res.status(404).json({
        error: 'SAM not found',
        samName: req.params.name
      });
    }

    res.json(sam);
  });

  /**
   * POST /api/sams/:name/state
   * SAMの状態を変更
   */
  router.post('/sams/:name/state', async (req: Request, res: Response) => {
    const { name } = req.params;
    const { state: newState } = req.body as { state: SAMState };

    if (!newState || !['GREEN', 'DARK', 'TRACKING'].includes(newState)) {
      return res.status(400).json({
        error: 'Invalid state',
        validStates: ['GREEN', 'DARK', 'TRACKING']
      });
    }

    const command: SetSAMStateCommand = {
      type: 'SET_SAM_STATE',
      samName: name,
      state: newState
    };

    try {
      const response = await dcsWatcher.sendCommand(command);
      res.json(response);
    } catch (error) {
      res.status(500).json({
        error: 'Command failed',
        message: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  });

  /**
   * POST /api/sams/all/state
   * 全SAMの状態を変更
   */
  router.post('/sams/all/state', async (req: Request, res: Response) => {
    const { state: newState } = req.body as { state: SAMState };

    if (!newState || !['GREEN', 'DARK'].includes(newState)) {
      return res.status(400).json({
        error: 'Invalid state',
        validStates: ['GREEN', 'DARK']
      });
    }

    const command: SetAllSAMsStateCommand = {
      type: 'SET_ALL_SAMS_STATE',
      state: newState
    };

    try {
      const response = await dcsWatcher.sendCommand(command);
      res.json(response);
    } catch (error) {
      res.status(500).json({
        error: 'Command failed',
        message: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  });

  // ========== 脅威 ==========

  /**
   * GET /api/threats
   * 脅威一覧を取得
   */
  router.get('/threats', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    const threats = Object.values(state.threats);

    // フィルタリング
    const { category, level } = req.query;
    let filtered = threats;

    if (category) {
      filtered = filtered.filter(t => t.category === category);
    }
    if (level) {
      filtered = filtered.filter(t => t.threatLevel === level);
    }

    res.json({
      count: filtered.length,
      threats: filtered
    });
  });

  /**
   * GET /api/threats/:id
   * 特定脅威の詳細を取得
   */
  router.get('/threats/:id', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    const threat = state.threats[req.params.id];
    if (!threat) {
      return res.status(404).json({
        error: 'Threat not found',
        threatId: req.params.id
      });
    }

    res.json(threat);
  });

  // ========== EWR ==========

  /**
   * GET /api/ewrs
   * EWRサイト一覧を取得
   */
  router.get('/ewrs', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    res.json({
      count: Object.keys(state.ewrSites).length,
      ewrs: Object.values(state.ewrSites)
    });
  });

  // ========== DEFCON ==========

  /**
   * GET /api/defcon
   * 現在のDEFCONレベルを取得
   */
  router.get('/defcon', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    res.json({
      level: state.defcon,
      validLevels: ['PEACE', 'ELEVATED', 'HIGH', 'SEVERE', 'CRITICAL']
    });
  });

  /**
   * POST /api/defcon
   * DEFCONレベルを設定
   */
  router.post('/defcon', async (req: Request, res: Response) => {
    const { level } = req.body as { level: DEFCONLevel };

    const validLevels: DEFCONLevel[] = ['PEACE', 'ELEVATED', 'HIGH', 'SEVERE', 'CRITICAL'];
    if (!level || !validLevels.includes(level)) {
      return res.status(400).json({
        error: 'Invalid DEFCON level',
        validLevels
      });
    }

    const command: SetDEFCONCommand = {
      type: 'SET_DEFCON',
      level
    };

    try {
      const response = await dcsWatcher.sendCommand(command);
      res.json(response);
    } catch (error) {
      res.status(500).json({
        error: 'Command failed',
        message: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  });

  // ========== 戦術モード ==========

  /**
   * GET /api/tactical
   * 現在の戦術モードを取得
   */
  router.get('/tactical', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    if (!state) {
      return res.status(503).json({ error: 'No state available' });
    }

    res.json({
      mode: state.tacticalMode,
      validModes: ['CONSERVATIVE', 'BALANCED', 'AGGRESSIVE', 'AMBUSH']
    });
  });

  /**
   * POST /api/tactical
   * 戦術モードを設定
   */
  router.post('/tactical', async (req: Request, res: Response) => {
    const { mode } = req.body as { mode: TacticalMode };

    const validModes: TacticalMode[] = ['CONSERVATIVE', 'BALANCED', 'AGGRESSIVE', 'AMBUSH'];
    if (!mode || !validModes.includes(mode)) {
      return res.status(400).json({
        error: 'Invalid tactical mode',
        validModes
      });
    }

    const command: SetTacticalModeCommand = {
      type: 'SET_TACTICAL_MODE',
      mode
    };

    try {
      const response = await dcsWatcher.sendCommand(command);
      res.json(response);
    } catch (error) {
      res.status(500).json({
        error: 'Command failed',
        message: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  });

  // ========== カスタムコマンド ==========

  /**
   * POST /api/command
   * カスタムコマンドを送信
   */
  router.post('/command', async (req: Request, res: Response) => {
    const command = req.body as Command;

    if (!command || !command.type) {
      return res.status(400).json({
        error: 'Invalid command',
        message: 'Command must have a type property'
      });
    }

    try {
      const response = await dcsWatcher.sendCommand(command);
      res.json(response);
    } catch (error) {
      res.status(500).json({
        error: 'Command failed',
        message: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  });

  /**
   * POST /api/commands
   * 複数コマンドを一括送信
   */
  router.post('/commands', async (req: Request, res: Response) => {
    const { commands } = req.body as { commands: Command[] };

    if (!commands || !Array.isArray(commands) || commands.length === 0) {
      return res.status(400).json({
        error: 'Invalid commands',
        message: 'Commands must be a non-empty array'
      });
    }

    try {
      const response = await dcsWatcher.sendCommands(commands);
      res.json(response);
    } catch (error) {
      res.status(500).json({
        error: 'Commands failed',
        message: error instanceof Error ? error.message : 'Unknown error'
      });
    }
  });

  // ========== ヘルスチェック ==========

  /**
   * GET /api/health
   * サーバーヘルスチェック
   */
  router.get('/health', (req: Request, res: Response) => {
    const state = dcsWatcher.getCurrentState();
    const config = dcsWatcher.getConfig();

    res.json({
      status: 'ok',
      dcsConnected: state !== null,
      lastUpdate: state?.timestamp || null,
      config: {
        statePath: config.statePath,
        pollInterval: config.pollInterval
      }
    });
  });

  return router;
}
