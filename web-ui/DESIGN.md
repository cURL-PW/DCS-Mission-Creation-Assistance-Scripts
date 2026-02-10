# IADS Web UI 設計書

## 1. 概要

DCS World IADSシステムをWebブラウザから管理・操作するためのUIシステム。
リアルタイムでSAM状態を監視し、コマンドを送信できる。

## 2. システムアーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│                        Web Browser                               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    IADS Web UI                            │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │   │
│  │  │  Map View   │ │Status Panel │ │   Control Panel     │ │   │
│  │  │  (Leaflet)  │ │  (React)    │ │    (React)          │ │   │
│  │  └─────────────┘ └─────────────┘ └─────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │ WebSocket/REST                    │
└──────────────────────────────┼───────────────────────────────────┘
                               │
┌──────────────────────────────┼───────────────────────────────────┐
│                    Bridge Server (Node.js)                       │
│  ┌─────────────────┐ ┌─────────────────┐ ┌────────────────────┐ │
│  │  REST API       │ │ WebSocket Server│ │  State Manager     │ │
│  │  /api/*         │ │  Real-time      │ │  Cache & Sync      │ │
│  └─────────────────┘ └─────────────────┘ └────────────────────┘ │
│                              │ File I/O / Socket                 │
└──────────────────────────────┼───────────────────────────────────┘
                               │
┌──────────────────────────────┼───────────────────────────────────┐
│                    DCS World (Lua)                               │
│  ┌─────────────────┐ ┌─────────────────┐ ┌────────────────────┐ │
│  │ IADS_WEB_EXPORT │ │ IADS_WEB_IMPORT │ │  IADS Systems      │ │
│  │ State → JSON    │ │ JSON → Commands │ │  (既存システム)     │ │
│  └─────────────────┘ └─────────────────┘ └────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## 3. コンポーネント詳細

### 3.1 DCS側 (Lua)

#### 3.1.1 IADS_WEB_EXPORT
- 定期的にIADS状態をJSONファイルにエクスポート
- 出力先: `Saved Games/DCS/iads_state.json`
- 更新間隔: 1秒

```lua
-- エクスポートデータ構造
{
    "timestamp": 12345.67,
    "missionTime": "01:23:45",
    "defcon": "ELEVATED",
    "tacticalMode": "BALANCED",
    "samSites": {
        "SA-10_Battery_1": {
            "state": "GREEN",
            "position": {"x": 100000, "z": 200000, "lat": 42.5, "lon": 41.2},
            "ammo": 85,
            "health": 100,
            "range": 80000,
            "type": "S-300"
        }
    },
    "ewrSites": {...},
    "threats": {...},
    "statistics": {...}
}
```

#### 3.1.2 IADS_WEB_IMPORT
- コマンドファイルを監視
- 入力元: `Saved Games/DCS/iads_commands.json`
- コマンド実行後にファイルを削除

```lua
-- コマンドデータ構造
{
    "commandId": "cmd-12345",
    "timestamp": 1234567890,
    "commands": [
        {"type": "SET_SAM_STATE", "samName": "SA-10_Battery_1", "state": "DARK"},
        {"type": "SET_DEFCON", "level": "HIGH"},
        {"type": "SET_TACTICAL_MODE", "mode": "AMBUSH"}
    ]
}
```

### 3.2 Bridge Server (Node.js)

#### 3.2.1 機能
- DCS状態ファイルの監視（chokidar）
- REST APIの提供
- WebSocketによるリアルタイム配信
- コマンドのキュー管理

#### 3.2.2 API エンドポイント

| Method | Endpoint | 説明 |
|--------|----------|------|
| GET | /api/status | 全体ステータス取得 |
| GET | /api/sams | SAMサイト一覧 |
| GET | /api/sams/:name | 特定SAM詳細 |
| POST | /api/sams/:name/state | SAM状態変更 |
| GET | /api/threats | 脅威一覧 |
| GET | /api/defcon | DEFCON取得 |
| POST | /api/defcon | DEFCON設定 |
| GET | /api/tactical | 戦術モード取得 |
| POST | /api/tactical | 戦術モード設定 |
| POST | /api/command | カスタムコマンド送信 |

#### 3.2.3 WebSocket イベント

| Event | Direction | 説明 |
|-------|-----------|------|
| state:update | Server→Client | 状態更新 |
| sam:stateChange | Server→Client | SAM状態変更 |
| threat:new | Server→Client | 新規脅威検出 |
| threat:update | Server→Client | 脅威更新 |
| threat:lost | Server→Client | 脅威消失 |
| defcon:change | Server→Client | DEFCON変更 |
| command:result | Server→Client | コマンド結果 |

### 3.3 Web UI (React + TypeScript)

#### 3.3.1 ページ構成

```
/                    - ダッシュボード（マップ + サマリー）
/sams                - SAMサイト一覧・管理
/sams/:name          - SAM詳細
/threats             - 脅威モニター
/commander           - AIコマンダー設定
/settings            - システム設定
```

#### 3.3.2 コンポーネント

**MapView**
- Leaflet.jsを使用
- SAMサイトをマーカーで表示
- 射程範囲を円で表示
- 脅威を移動マーカーで表示
- クリックでSAM詳細ポップアップ

**StatusPanel**
- DEFCON表示・変更
- 戦術モード表示・変更
- 全体統計（アクティブSAM数、脅威数など）

**SAMList**
- SAMサイト一覧テーブル
- フィルタリング・ソート機能
- 一括操作（全起動/全停波）

**SAMDetail**
- 個別SAMの詳細情報
- 状態変更ボタン
- 弾薬・HP表示
- 交戦履歴

**ThreatMonitor**
- リアルタイム脅威表示
- 脅威タイプ別フィルタ
- 脅威トラック履歴

**CommanderPanel**
- AIコマンダー設定
- 戦術パラメータ調整
- ログ表示

## 4. 技術スタック

### 4.1 DCS側
- Lua標準ライブラリ
- LFS（ファイルシステムアクセス）
- JSON（テーブル↔JSON変換）

### 4.2 Bridge Server
- Node.js 18+
- Express.js（REST API）
- ws（WebSocket）
- chokidar（ファイル監視）
- cors（CORS対応）

### 4.3 Web UI
- React 18
- TypeScript
- Vite（ビルドツール）
- TailwindCSS（スタイリング）
- Leaflet.js（マップ）
- React Query（データフェッチ）
- Zustand（状態管理）
- Recharts（グラフ）

## 5. ディレクトリ構造

```
web-ui/
├── DESIGN.md              # この設計書
├── package.json           # ルートパッケージ
├── dcs/                   # DCS側スクリプト
│   ├── web_export.lua     # 状態エクスポート
│   └── web_import.lua     # コマンドインポート
├── server/                # Bridge Server
│   ├── package.json
│   ├── src/
│   │   ├── index.ts       # エントリーポイント
│   │   ├── api/           # REST API
│   │   ├── websocket/     # WebSocket
│   │   ├── dcs/           # DCSファイル監視
│   │   └── types/         # 型定義
│   └── tsconfig.json
└── client/                # Web UI
    ├── package.json
    ├── src/
    │   ├── main.tsx       # エントリーポイント
    │   ├── App.tsx        # ルートコンポーネント
    │   ├── components/    # UIコンポーネント
    │   │   ├── map/       # マップ関連
    │   │   ├── status/    # ステータス表示
    │   │   ├── sam/       # SAM管理
    │   │   ├── threat/    # 脅威表示
    │   │   └── commander/ # コマンダー設定
    │   ├── hooks/         # カスタムフック
    │   ├── services/      # API・WebSocket
    │   ├── store/         # 状態管理
    │   ├── types/         # 型定義
    │   └── utils/         # ユーティリティ
    ├── index.html
    └── vite.config.ts
```

## 6. セキュリティ考慮事項

### 6.1 ローカル使用前提
- デフォルトでlocalhostのみアクセス可能
- 外部公開する場合は認証が必要

### 6.2 認証オプション（将来実装）
- Basic認証
- JWT認証
- APIキー

### 6.3 入力検証
- コマンドパラメータのバリデーション
- SAM名の存在確認
- DEFCON/戦術モードの値検証

## 7. 画面モックアップ

### 7.1 ダッシュボード

```
┌─────────────────────────────────────────────────────────────────────┐
│  IADS Control Center                          [DEFCON: ELEVATED ▼]  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────┐  ┌──────────────────────┐ │
│  │                                     │  │ Status               │ │
│  │                                     │  │ ──────────────────── │ │
│  │           Map View                  │  │ SAMs: 12 (8 active)  │ │
│  │     (SAMs, EWRs, Threats)           │  │ EWRs: 4              │ │
│  │                                     │  │ Threats: 3           │ │
│  │                                     │  │ ──────────────────── │ │
│  │     [●] SA-10_Battery_1 (GREEN)     │  │ Mode: BALANCED       │ │
│  │     [○] SA-6_Battery_1 (DARK)       │  │                      │ │
│  │     [▲] EWR_South                   │  │ [All ON] [All OFF]   │ │
│  │     [✕] Threat: F-16 (SEAD)         │  └──────────────────────┘ │
│  │                                     │                           │
│  │                                     │  ┌──────────────────────┐ │
│  │                                     │  │ Recent Events        │ │
│  │                                     │  │ ──────────────────── │ │
│  └─────────────────────────────────────┘  │ 10:23 SAM-1 → DARK   │ │
│                                           │ 10:22 Threat detected │ │
│                                           │ 10:20 DEFCON → HIGH  │ │
│                                           └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.2 SAM管理画面

```
┌─────────────────────────────────────────────────────────────────────┐
│  SAM Sites                                    [Filter ▼] [Search]   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ Name              │ Type    │ State  │ Ammo │ HP  │ Actions    ││
│  ├───────────────────┼─────────┼────────┼──────┼─────┼────────────┤│
│  │ SA-10_Battery_1   │ S-300   │ ●GREEN │ 85%  │100% │ [ON][OFF]  ││
│  │ SA-10_Battery_2   │ S-300   │ ○DARK  │ 100% │100% │ [ON][OFF]  ││
│  │ SA-6_Battery_1    │ SA-6    │ ●GREEN │ 60%  │ 75% │ [ON][OFF]  ││
│  │ SA-11_Battery_1   │ Buk     │ ○DARK  │ 100% │100% │ [ON][OFF]  ││
│  │ Hawk_Battery_1    │ Hawk    │ ●GREEN │ 40%  │ 50% │ [ON][OFF]  ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  Selected: SA-10_Battery_1                                          │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ Position: 42.5°N, 41.2°E                                        ││
│  │ Range: 80km                                                     ││
│  │ Missiles Remaining: 17/20                                       ││
│  │ Last Engagement: 10:15:32                                       ││
│  │ Linked EWRs: EWR_South, EWR_North                               ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

## 8. 実装フェーズ

### Phase 1: 基盤構築
- [ ] DCS状態エクスポート (web_export.lua)
- [ ] DCSコマンドインポート (web_import.lua)
- [ ] Bridge Serverセットアップ
- [ ] REST API基本実装
- [ ] WebSocket基本実装

### Phase 2: Web UI基本機能
- [ ] React プロジェクトセットアップ
- [ ] 基本レイアウト
- [ ] 状態表示コンポーネント
- [ ] SAM一覧表示
- [ ] SAM状態変更

### Phase 3: マップ機能
- [ ] Leaflet統合
- [ ] SAMマーカー表示
- [ ] 射程範囲表示
- [ ] 脅威表示
- [ ] リアルタイム更新

### Phase 4: 高度な機能
- [ ] AIコマンダー設定UI
- [ ] 統計・グラフ表示
- [ ] イベントログ
- [ ] フィルタリング・検索

### Phase 5: 最適化・改善
- [ ] パフォーマンス最適化
- [ ] モバイル対応
- [ ] 認証機能（オプション）
- [ ] 多言語対応

## 9. 依存関係・前提条件

### 9.1 必要なソフトウェア
- Node.js 18以上
- npm または yarn
- モダンブラウザ（Chrome, Firefox, Edge）

### 9.2 DCS環境
- DCS World インストール済み
- MISTライブラリ読み込み済み
- IADSスクリプト読み込み済み

### 9.3 ネットワーク
- localhost:3000 (Web UI)
- localhost:3001 (API Server)
- ファイアウォール許可必要

## 10. 今後の拡張案

- マルチプレイヤー対応（複数クライアント同時接続）
- モバイルアプリ版
- 音声通知
- キーボードショートカット
- カスタムテーマ
- プラグインシステム
