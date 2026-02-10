import express from 'express';
import cors from 'cors';
import { DCSFileWatcher } from './dcs/fileWatcher';
import { IADSWebSocketServer } from './websocket/wsServer';
import { createApiRouter } from './api/routes';
import { sessionManager } from './api/sessionManager';

const API_PORT = parseInt(process.env.API_PORT || '3001', 10);
const WS_PORT = parseInt(process.env.WS_PORT || '3002', 10);

async function main(): Promise<void> {
  console.log('='.repeat(60));
  console.log('IADS Bridge Server Starting...');
  console.log('='.repeat(60));

  // DCSファイル監視の初期化
  const dcsWatcher = new DCSFileWatcher({
    pollInterval: 500
  });

  // Express アプリケーション
  const app = express();

  // ミドルウェア
  app.use(cors({
    origin: ['http://localhost:3000', 'http://127.0.0.1:3000'],
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Session-Id'],
    exposedHeaders: ['X-Session-Id']
  }));
  app.use(express.json());

  // セッションマネージャー開始
  sessionManager.start();

  // ルートエンドポイント
  app.get('/', (req, res) => {
    res.json({
      name: 'IADS Bridge Server',
      version: '1.0.0',
      endpoints: {
        api: `http://localhost:${API_PORT}/api`,
        websocket: `ws://localhost:${WS_PORT}/ws`
      },
      documentation: '/api/docs'
    });
  });

  // APIドキュメント
  app.get('/api/docs', (req, res) => {
    res.json({
      endpoints: [
        // セッション
        { method: 'POST', path: '/api/session', description: 'セッション作成（ログイン）' },
        { method: 'GET', path: '/api/session', description: 'セッション情報取得' },
        { method: 'DELETE', path: '/api/session', description: 'セッション削除（ログアウト）' },
        { method: 'GET', path: '/api/sessions', description: '全セッション一覧（管理者用）' },
        // コアリション
        { method: 'GET', path: '/api/coalition/:id', description: 'コアリション別データ取得' },
        { method: 'GET', path: '/api/multiplayer', description: 'マルチプレイヤー情報取得' },
        // ステータス
        { method: 'GET', path: '/api/status', description: '全体ステータス取得' },
        { method: 'GET', path: '/api/state', description: '完全な状態データ取得' },
        { method: 'GET', path: '/api/sams', description: 'SAMサイト一覧' },
        { method: 'GET', path: '/api/sams/:name', description: '特定SAM詳細' },
        { method: 'POST', path: '/api/sams/:name/state', description: 'SAM状態変更' },
        { method: 'POST', path: '/api/sams/all/state', description: '全SAM状態変更' },
        { method: 'GET', path: '/api/threats', description: '脅威一覧' },
        { method: 'GET', path: '/api/threats/:id', description: '特定脅威詳細' },
        { method: 'GET', path: '/api/ewrs', description: 'EWRサイト一覧' },
        { method: 'GET', path: '/api/defcon', description: 'DEFCONレベル取得' },
        { method: 'POST', path: '/api/defcon', description: 'DEFCONレベル設定' },
        { method: 'GET', path: '/api/tactical', description: '戦術モード取得' },
        { method: 'POST', path: '/api/tactical', description: '戦術モード設定' },
        { method: 'POST', path: '/api/command', description: 'カスタムコマンド送信' },
        { method: 'POST', path: '/api/commands', description: '複数コマンド一括送信' },
        { method: 'GET', path: '/api/health', description: 'ヘルスチェック' }
      ],
      authentication: {
        header: 'X-Session-Id',
        description: 'セッション作成後、全てのリクエストにX-Session-Idヘッダーを含めてください'
      },
      websocket: {
        url: `ws://localhost:${WS_PORT}/ws`,
        events: [
          { event: 'state:update', direction: 'server→client', description: '状態更新' },
          { event: 'sam:stateChange', direction: 'server→client', description: 'SAM状態変更' },
          { event: 'threat:new', direction: 'server→client', description: '新規脅威検出' },
          { event: 'threat:update', direction: 'server→client', description: '脅威更新' },
          { event: 'threat:lost', direction: 'server→client', description: '脅威消失' },
          { event: 'defcon:change', direction: 'server→client', description: 'DEFCON変更' },
          { event: 'command:result', direction: 'server→client', description: 'コマンド結果' }
        ]
      }
    });
  });

  // API ルーター
  const apiRouter = createApiRouter(dcsWatcher);
  app.use('/api', apiRouter);

  // WebSocket サーバー
  const wsServer = new IADSWebSocketServer(dcsWatcher, {
    port: WS_PORT,
    path: '/ws'
  });

  // イベントリスナー設定
  dcsWatcher.on('state:update', (state) => {
    console.log(`[Main] State updated: ${state.missionTime}`);
  });

  dcsWatcher.on('error', (error) => {
    console.error('[Main] DCS Watcher error:', error);
  });

  // サーバー起動
  dcsWatcher.start();
  wsServer.start();

  const httpServer = app.listen(API_PORT, () => {
    console.log('');
    console.log('Server started successfully!');
    console.log('-'.repeat(60));
    console.log(`REST API:    http://localhost:${API_PORT}/api`);
    console.log(`WebSocket:   ws://localhost:${WS_PORT}/ws`);
    console.log(`API Docs:    http://localhost:${API_PORT}/api/docs`);
    console.log('-'.repeat(60));
    console.log('');
    console.log('Waiting for DCS connection...');
    console.log('');
  });

  // シャットダウンハンドラ
  const shutdown = (): void => {
    console.log('\nShutting down...');
    dcsWatcher.stop();
    wsServer.stop();
    sessionManager.stop();
    httpServer.close(() => {
      console.log('Server stopped');
      process.exit(0);
    });
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((error) => {
  console.error('Failed to start server:', error);
  process.exit(1);
});
