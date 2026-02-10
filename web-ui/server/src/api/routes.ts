import { Router, Request, Response } from 'express';
import { DCSFileWatcher } from '../dcs/fileWatcher';
import {
  SAMState,
  DEFCONLevel,
  TacticalMode,
  SetSAMStateCommand,
  SetAllSAMsStateCommand,
  SetDEFCONCommand,
  SetTacticalModeCommand,
  Command
} from '../types/iads';

export function createApiRouter(dcsWatcher: DCSFileWatcher): Router {
  const router = Router();

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

    const sams = Object.values(state.samSites);

    // フィルタリング
    const { state: stateFilter, type: typeFilter } = req.query;
    let filtered = sams;

    if (stateFilter) {
      filtered = filtered.filter(s => s.state === stateFilter);
    }
    if (typeFilter) {
      filtered = filtered.filter(s => s.type === typeFilter);
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
