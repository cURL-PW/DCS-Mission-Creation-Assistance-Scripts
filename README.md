# DCS World Mission Creation Assistance Scripts

DCS Worldミッション作成支援スクリプト集

**Required:** MIST 4.3.74以上

## 概要

このスクリプト集は、DCS Worldのミッション作成を支援するLuaスクリプトです。
主に以下の機能を提供します：

- **SEADシミュレーション**: 対レーダーミサイル発射時のSAMレーダー停波シミュレーション
- **統合防空システム(IADS)ネットワーク**: SAM同士を連携させた協調防空システム
- **弾薬管理**: ランチャーごとの残弾追跡と自動停波
- **動的レーダー運用(EMCON)**: 点滅モードやスケジュール運用
- **統計・ログ**: 交戦記録と効率統計
- **ポイントディフェンス**: 高価値目標の多層防護
- **データリンク**: EWR→SAM間のトラック共有とサイレントローンチ
- **航路予測**: 脅威の航路を予測し、SAMを事前アクティブ化
- **デコイ/おとり**: ARM誘引用の偽レーダー送信機
- **ジャマー対策**: ECCMとホームオンジャム
- **修復/再配置**: 損傷SAMの修復とシュート＆スクート
- **AIコマンダー**: 脅威に応じた自動IADS管理
- **F10マップ連携**: マップ上のステータス表示とラジオメニュー制御
- **マルチプレイヤー同期**: クライアント間IADS状態同期
- **陣営別フィルタ**: Red/Blue別の情報アクセス制御
- **Web UI**: ブラウザベースのリアルタイムIADS管理インターフェース

## ディレクトリ構造

```
DCS-Mission-Creation-Assistance-Scripts/
├── README.md
├── main.lua              # メインエントリーポイント
├── SamAutomation.lua     # 旧版SEADスクリプト（後方互換性のため維持）
├── core/
│   ├── config.lua        # SAM設定データ
│   ├── utils.lua         # 共通ユーティリティ
│   ├── sead.lua          # SEADシミュレーションシステム
│   ├── ammo.lua          # 弾薬管理システム (Phase 1)
│   ├── emcon.lua         # EMCONシステム (Phase 1)
│   └── logger.lua        # 統計・ログシステム (Phase 1)
├── iads/
│   ├── network.lua       # IADSネットワーク管理
│   ├── sector.lua        # 防空セクター管理
│   ├── threat.lua        # 脅威情報共有システム
│   ├── point_defense.lua # ポイントディフェンス (Phase 2)
│   ├── datalink.lua      # データリンク (Phase 2)
│   ├── predictor.lua     # 航路予測 (Phase 2)
│   └── maintenance.lua   # 修復/再配置 (Phase 3)
├── countermeasures/
│   ├── decoy.lua         # デコイ/おとり (Phase 3)
│   └── anti_jam.lua      # ジャマー対策 (Phase 3)
├── ai/
│   └── commander.lua     # AIコマンダー (Phase 4)
├── ui/
│   └── f10_map.lua       # F10マップ連携 (Phase 4)
├── multiplayer/
│   ├── sync.lua          # マルチプレイヤー同期 (Phase 5)
│   └── coalition.lua     # 陣営別フィルタ (Phase 5)
├── misc/
│   └── addSamlist.lua    # SAMユニット列挙ユーティリティ
└── web-ui/               # Web UI システム
    ├── DESIGN.md         # 設計書
    ├── dcs/
    │   ├── web_export.lua  # DCS→JSON出力
    │   └── web_import.lua  # JSON→DCSコマンド入力
    ├── server/           # Bridge Server (Node.js)
    │   ├── package.json
    │   └── src/
    │       ├── index.ts
    │       ├── api/
    │       │   ├── routes.ts
    │       │   └── sessionManager.ts
    │       ├── services/
    │       │   └── fileWatcher.ts
    │       └── types/
    │           └── iads.ts
    └── client/           # React SPA
        ├── package.json
        ├── vite.config.ts
        └── src/
            ├── App.tsx
            ├── components/
            ├── services/
            ├── store/
            └── types/
```

## クイックスタート

### 全機能を一括セットアップ

```lua
-- 全スクリプトをロード
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/config.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/utils.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/sead.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/ammo.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/emcon.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/logger.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/iads/network.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/iads/sector.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/iads/threat.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/main.lua")

-- 一括セットアップ
local systems = setupFullIADS("Red IADS", {
    debug = true,
    samPattern = "SAM_",        -- "SAM_"を含むグループを自動追加
    ewrPattern = "EWR_",        -- "EWR_"を含むグループを自動追加
    coalition = coalition.side.RED,
    linkDistance = 150000,      -- 150km以内を自動リンク
    emconLevel = SAM_EMCON.LEVEL.DELTA,
    emconMode = SAM_EMCON.MODE.BLINK,
    reloadEnabled = true
})

-- 全SAMをアクティブ化
systems.iads:activateAllSams()
```

## 使用方法

### 1. SEADシミュレーション（基本機能）

対レーダーミサイル（HARM, LD-10等）が発射された際、SAMのレーダーを一定時間停波させます。

```lua
SEAD_SYSTEM.init({debug = true})
```

**対応ミサイル:** KH-58, KH-25MPU, AGM-88 HARM, LD-10, ALARM

**対応SAMシステム:**
- ソ連/ロシア: S-125, S-75, SA-6 Kub, SA-8 Osa, S-300PS, SA-11 Buk, Tor
- 西側: Hawk, Patriot, Roland
- 早期警戒レーダー: 1L13 EWR, 55G6 EWR

### 2. 統合防空システム(IADS)ネットワーク

```lua
local redIADS = IADS_NETWORK.new("Red Force IADS")
redIADS:init({updateInterval = 5})

-- SAMとEWRを追加・リンク
redIADS:addSamSite(Group.getByName("SA-10_Battery_1"))
redIADS:addEWR(Group.getByName("EWR_South"))
redIADS:linkSamToEWR("SA-10_Battery_1", "EWR_South")

-- SEADシステムと連携
SEAD_SYSTEM.init({iadsNetwork = redIADS})
redIADS:activateAllSams()
```

### 3. 弾薬管理システム

各SAMランチャーの残弾を追跡し、弾切れ時に自動でダーク化します。

```lua
local ammo = SAM_AMMO.new()
ammo:init({
    iadsNetwork = redIADS,
    reloadEnabled = true,    -- 再装填シミュレーション
    reloadTime = 300,        -- 再装填時間（秒）
    autoGoGreen = true       -- 弾切れ時自動ダーク化
})

-- SAMグループのランチャーを登録
ammo:registerGroup(Group.getByName("SA-10_Battery_1"))

-- ステータス確認
ammo:printStatus()
```

**弾薬状態:**
| 状態 | 残弾率 | 動作 |
|------|--------|------|
| FULL | 100% | 通常運用 |
| HIGH | 75-99% | 通常運用 |
| MEDIUM | 50-74% | 通常運用 |
| LOW | 25-49% | 優先度低下 |
| CRITICAL | 1-24% | 優先度低下 |
| EMPTY | 0% | 自動ダーク化 |

### 4. 動的レーダー運用(EMCON)

レーダーの送波パターンを制御し、SEAD機による位置特定を困難にします。

```lua
local emcon = SAM_EMCON.new()
emcon:init({
    iadsNetwork = redIADS,
    level = SAM_EMCON.LEVEL.CHARLIE,  -- 制限送波
    mode = SAM_EMCON.MODE.BLINK       -- 点滅モード
})

-- SAMを登録
emcon:registerSam("SA-10_Battery_1")

-- 点滅プロファイルをカスタマイズ
emcon:setBlinkProfile("SA-10_Battery_1", {
    onDuration = 15,     -- 送波時間（秒）
    offDuration = 30,    -- 停波時間（秒）
    randomize = true,    -- ランダム化
    randomRange = 5      -- ランダム幅（±秒）
})
```

**EMCONレベル:**
| レベル | 説明 |
|--------|------|
| ALPHA | 全面送波禁止（完全沈黙） |
| BRAVO | 最小限送波（EWRのみ） |
| CHARLIE | 制限送波（点滅モード） |
| DELTA | 通常運用 |
| ECHO | 全面送波（最大警戒） |

**運用モード:**
| モード | 説明 |
|--------|------|
| STATIC | 固定状態 |
| BLINK | 点滅モード（送波⇔停波サイクル） |
| RANDOM | ランダム運用 |
| SCHEDULED | スケジュール運用 |
| THREAT_REACTIVE | 脅威検知時のみ送波 |

### 5. 統計・ログシステム

交戦記録を収集し、効率統計を生成します。

```lua
local logger = SAM_LOGGER.new()
logger:init({iadsNetwork = redIADS})

-- リアルタイム統計表示
logger:printStatistics()

-- ミッション終了レポート
logger:printReport()

-- カスタムイベントハンドラ
logger:addEventListener(SAM_LOGGER.EVENT_TYPE.TARGET_KILLED, function(data)
    trigger.action.outText("Kill confirmed: " .. data.target, 10)
end)
```

**収集される統計:**
- ミサイル発射数、命中数、撃墜数
- 命中率、撃墜率、1撃墜あたりのミサイル数
- 脅威検知数、交戦数
- SEAD攻撃による停波回数

### 6. 自動セットアップ機能

```lua
local iads = createIADS("My IADS", {debug = true})

-- パターンで自動追加
autoAddSamSites(iads, "SAM_", coalition.side.RED)
autoAddEWRs(iads, "EWR_", coalition.side.RED)

-- 距離ベースで自動リンク
autoLinkByDistance(iads, 150000)
```

### 7. セクター管理

```lua
local sector = createSectorWithSams(iads, "Sector_North",
    {x = 100000, z = 200000}, 80000)
```

## API リファレンス

### SAM_AMMO

| 関数 | 説明 |
|------|------|
| `new()` | 弾薬管理システムを作成 |
| `init(options)` | 初期化 |
| `registerLauncher(unit)` | ランチャーを登録 |
| `registerGroup(group)` | グループ内の全ランチャーを登録 |
| `canEngage(groupName)` | 交戦可能か判定 |
| `reloadNow(unitName)` | 即時再装填 |
| `printStatus()` | ステータス表示 |

### SAM_EMCON

| 関数 | 説明 |
|------|------|
| `new()` | EMCONシステムを作成 |
| `init(options)` | 初期化 |
| `setLevel(level)` | EMCONレベルを設定 |
| `setMode(mode)` | 運用モードを設定 |
| `registerSam(groupName)` | SAMを登録 |
| `setBlinkProfile(groupName, profile)` | 点滅プロファイルを設定 |
| `addSchedule(schedule)` | スケジュールを追加 |
| `printStatus()` | ステータス表示 |

### SAM_LOGGER

| 関数 | 説明 |
|------|------|
| `new()` | ロガーを作成 |
| `init(options)` | 初期化 |
| `logEvent(eventType, data)` | イベントを記録 |
| `addEventListener(type, handler)` | イベントハンドラを登録 |
| `getStatistics()` | 統計を取得 |
| `generateReport()` | レポートを生成 |
| `printStatistics()` | 統計を表示 |
| `printReport()` | レポートを表示 |

### 統合関数

| 関数 | 説明 |
|------|------|
| `setupFullIADS(name, options)` | 全システムを一括セットアップ |
| `createAmmoSystem(options)` | 弾薬管理システムを作成 |
| `createEmconSystem(options)` | EMCONシステムを作成 |
| `createLoggerSystem(options)` | ロガーを作成 |
| `printFullStatus()` | 全システムのステータスを表示 |
| `printMissionReport()` | ミッションレポートを表示 |

### IADS_POINT_DEFENSE (Phase 2)

| 関数 | 説明 |
|------|------|
| `new(network)` | ポイントディフェンスを作成 |
| `addTarget(unit, options)` | ユニットを防護対象に追加 |
| `addStaticTarget(id, position, options)` | 座標を防護対象に追加 |
| `addZoneTarget(zoneName, options)` | トリガーゾーンを防護対象に追加 |
| `addAirbase(airbaseName, options)` | 飛行場を防護対象に追加 |
| `printStatus()` | ステータス表示 |

### IADS_DATALINK (Phase 2)

| 関数 | 説明 |
|------|------|
| `new(network)` | データリンクを作成 |
| `shareTrack(track, sourceId)` | トラックを共有 |
| `canSilentLaunchAt(samName, trackId)` | サイレントローンチ可能か確認 |
| `getAvailableTracks(samName)` | 利用可能トラックを取得 |
| `printStatus()` | ステータス表示 |

### IADS_PREDICTOR (Phase 2)

| 関数 | 説明 |
|------|------|
| `new(network)` | 航路予測を作成 |
| `predictPath(threat)` | 脅威の航路を予測 |
| `getSamsToPreActivate()` | 事前アクティブ化が必要なSAMを取得 |
| `getPrediction(threatId)` | 特定脅威の予測を取得 |
| `printStatus()` | ステータス表示 |

### Phase 2 統合関数

| 関数 | 説明 |
|------|------|
| `setupAdvancedIADS(name, options)` | Phase 1+2全システムを一括セットアップ |
| `createPointDefenseSystem(network, options)` | ポイントディフェンスを作成 |
| `createDatalinkSystem(network, options)` | データリンクを作成 |
| `createPredictorSystem(network, options)` | 航路予測を作成 |
| `printAdvancedStatus()` | 全システムの詳細ステータスを表示 |

### SAM_DECOY (Phase 3)

| 関数 | 説明 |
|------|------|
| `new(network)` | デコイシステムを作成 |
| `init(options)` | 初期化 |
| `addDecoy(position, options)` | デコイを追加 |
| `deployAroundSam(samName, count, radius)` | SAM周辺にデコイを配置 |
| `activateDecoy(decoyId)` | デコイを送波開始 |
| `deactivateDecoy(decoyId)` | デコイを停波 |
| `activateAll()` | 全デコイを送波 |
| `deactivateAll()` | 全デコイを停波 |
| `checkArmAttraction(armPosition)` | ARM誘引チェック |
| `printStatus()` | ステータス表示 |

### SAM_ANTI_JAM (Phase 3)

| 関数 | 説明 |
|------|------|
| `new(network)` | ジャマー対策システムを作成 |
| `init(options)` | 初期化 |
| `detectJammer(position, options)` | ジャマーを検出登録 |
| `calculateJamEffect(samName)` | SAMへのジャミング効果を計算 |
| `setEccmMode(samName, mode)` | ECCMモードを設定 |
| `autoSelectEccm(samName)` | 自動ECCM選択 |
| `processHomeOnJam(samName)` | ホームオンジャム処理 |
| `triangulateJammer(jammerId)` | 三角測量でジャマー位置特定 |
| `getJammedPerformance(samName)` | ジャミング下での性能を取得 |
| `printStatus()` | ステータス表示 |

### SAM_MAINTENANCE (Phase 3)

| 関数 | 説明 |
|------|------|
| `new(network)` | 修復/再配置システムを作成 |
| `init(options)` | 初期化 |
| `applyDamage(samName, percent)` | SAMにダメージを適用 |
| `queueRepair(samName)` | 修復キューに追加 |
| `dispatchRepairTeam(samName)` | 修復チームを派遣 |
| `startRelocation(samName, targetPos)` | 再配置を開始 |
| `recordShot(samName)` | 発射をカウント（シュート＆スクート） |
| `useSpareUnit(unitType)` | スペアユニットを使用 |
| `addSpareUnits(unitType, count)` | スペアユニットを追加 |
| `printStatus()` | ステータス表示 |

### Phase 3 統合関数

| 関数 | 説明 |
|------|------|
| `setupFullCountermeasuresIADS(name, options)` | Phase 1+2+3全システムを一括セットアップ |
| `createDecoySystem(network, options)` | デコイシステムを作成 |
| `createAntiJamSystem(network, options)` | ジャマー対策システムを作成 |
| `createMaintenanceSystem(network, options)` | 修復/再配置システムを作成 |
| `deployDecoysAroundAllSams(iads, decoy, options)` | 全SAMにデコイを配置 |

### IADS_COMMANDER (Phase 4)

| 関数 | 説明 |
|------|------|
| `new(network)` | AIコマンダーを作成 |
| `init(options)` | 初期化 |
| `setDefenseCondition(condition)` | 防空態勢を設定 |
| `setTacticalMode(mode)` | 戦術モードを設定 |
| `setPriorityType(priority)` | 優先度タイプを設定 |
| `updateThreatAssessment()` | 脅威評価を更新 |
| `updateResourceStatus()` | リソース状態を更新 |
| `makeTacticalDecisions()` | 戦術的意思決定を実行 |
| `setCallback(event, handler)` | コールバックを設定 |
| `getStatus()` | ステータスを取得 |
| `printStatus()` | ステータス表示 |

### IADS_F10_MAP (Phase 4)

| 関数 | 説明 |
|------|------|
| `new(network)` | F10マップシステムを作成 |
| `init(options)` | 初期化 |
| `addMarker(id, type, position, text)` | マーカーを追加 |
| `updateMarker(id, type, position, text)` | マーカーを更新 |
| `removeMarker(id)` | マーカーを削除 |
| `refreshAllMarkers()` | 全マーカーを更新 |
| `toggleDisplay(setting)` | 表示設定を切り替え |
| `showAllStatus()` | 全ステータス表示 |
| `activateAllSams()` | 全SAMを起動 |
| `deactivateAllSams()` | 全SAMを停波 |
| `printStatus()` | ステータス表示 |

### Phase 4 統合関数

| 関数 | 説明 |
|------|------|
| `setupCompleteIADS(name, options)` | Phase 1+2+3+4全システムを一括セットアップ |
| `createCommanderSystem(network, options)` | AIコマンダーを作成 |
| `createF10MapSystem(network, options)` | F10マップシステムを作成 |

### IADS_MP_SYNC (Phase 5)

| 関数 | 説明 |
|------|------|
| `new(network)` | マルチプレイヤー同期システムを作成 |
| `init(options)` | 初期化 |
| `serializeState()` | 現在の状態をシリアライズ |
| `applyState(state)` | 状態を適用（クライアント） |
| `sendMessage(type, data, target)` | メッセージを送信 |
| `sendFullState(client)` | 完全状態を送信（ホスト） |
| `sendDelta()` | 差分を送信（ホスト） |
| `requestSync()` | 同期リクエスト（クライアント） |
| `sendCommand(cmd, params)` | コマンドを送信 |
| `printStatus()` | ステータス表示 |

### IADS_COALITION (Phase 5)

| 関数 | 説明 |
|------|------|
| `new()` | 陣営フィルタを作成 |
| `init(options)` | 初期化 |
| `getPlayerCoalition(playerId)` | プレイヤー陣営を取得 |
| `getPlayerAccessLevel(playerId)` | アクセスレベルを取得 |
| `canAccess(playerId, infoType, coalition)` | アクセス権限チェック |
| `setPlayerPermission(playerId, level)` | 権限を設定 |
| `addGameMaster(playerId)` | ゲームマスターを追加 |
| `getFilteredSamInfo(playerId, network)` | フィルタ済みSAM情報取得 |
| `createCoalitionRadioMenus(side)` | 陣営別メニュー作成 |
| `sendCoalitionMessage(side, msg)` | 陣営別メッセージ送信 |
| `printStatus()` | ステータス表示 |

### Phase 5 統合関数

| 関数 | 説明 |
|------|------|
| `setupMultiplayerIADS(name, options)` | Phase 1-5全システムを一括セットアップ |
| `setupDualCoalitionIADS(options)` | Red/Blue両陣営を同時セットアップ |
| `createMPSyncSystem(network, options)` | マルチプレイヤー同期を作成 |
| `createCoalitionFilter(options)` | 陣営フィルタを作成 |

## Phase 2 使用例

### ポイントディフェンス

```lua
local pd = createPointDefenseSystem(iads, {
    autoActivate = true,
    layeredDefense = true
})

-- 飛行場を防護
pd:addAirbase("Kutaisi", {priority = 1})

-- トリガーゾーンを防護
pd:addZoneTarget("HQ_Zone", {priority = 2})

-- ユニットを防護
pd:addTarget(Unit.getByName("Command_Post"), {
    priority = 1,
    protectionRadius = 30000
})
```

### データリンク（サイレントローンチ）

```lua
local datalink = createDatalinkSystem(iads, {
    silentLaunchEnabled = true,
    linkDelay = 1
})

-- SAMがダーク状態でもEWR情報で追跡可能か確認
if datalink:canSilentLaunchAt("SA-10_Battery", "TRK-0001") then
    -- サイレントローンチ可能
end
```

### 航路予測

```lua
local predictor = createPredictorSystem(iads, {
    predictionTime = 120,      -- 2分先まで予測
    autoPreActivate = true     -- 自動事前アクティブ化
})

-- 特定脅威の予測を取得
local prediction = predictor:getPrediction("enemy_fighter_1")
if prediction then
    -- 予測経路上のSAM交差を確認
    for samName, intersection in pairs(prediction.samIntersections) do
        print(samName .. " will be in range in " .. intersection.entryTimeOffset .. "s")
    end
end
```

### 高度なIADS一括セットアップ

```lua
local systems = setupAdvancedIADS("Red IADS", {
    -- Phase 1
    samPattern = "SAM_",
    ewrPattern = "EWR_",
    linkDistance = 150000,
    emconMode = SAM_EMCON.MODE.BLINK,

    -- Phase 2
    pointDefense = true,
    datalink = true,
    predictor = true,
    silentLaunch = true,

    -- 高価値目標
    hvTargets = {
        {type = "airbase", name = "Kutaisi", options = {priority = 1}},
        {type = "zone", name = "HQ_Zone", options = {priority = 2}}
    }
})
```

## Phase 3 使用例

### デコイ/おとりシステム

ARMから本物のSAMを守るためのおとり送信機をシミュレートします。

```lua
local decoy = createDecoySystem(iads, {
    autoActivate = true,           -- SAM停波時に自動送波
    attractionRadius = 5000,       -- ARM誘引半径（メートル）
    attractionProbability = 0.7    -- ARM誘引確率（70%）
})

-- SAMサイト周辺にデコイを配置
decoy:deployAroundSam("SA-10_Battery_1", 3, 3000)  -- 3基、半径3km

-- 全SAMに自動配置
deployDecoysAroundAllSams(iads, decoy, {
    count = 2,      -- SAMあたり2基
    radius = 3000   -- 3km半径
})

-- 手動でデコイを追加
decoy:addDecoy({x = 100000, y = 0, z = 200000}, {
    type = SAM_DECOY.TYPE.ELECTRONIC,
    linkedSam = "SA-10_Battery_1"
})

-- ステータス表示
decoy:printStatus()
```

**デコイタイプ:**
| タイプ | 説明 |
|--------|------|
| FIXED | 固定設置型 |
| MOBILE | 移動式 |
| INFLATABLE | 膨張式（安価） |
| ELECTRONIC | 電子式（送信機のみ） |

**デコイ状態:**
| 状態 | 説明 |
|------|------|
| STANDBY | 待機中 |
| EMITTING | 送波中 |
| ATTRACTING | ARM誘引中 |
| DESTROYED | 破壊済み |

### ジャマー対策システム

ECMジャマーに対するSAMの対抗措置をシミュレートします。

```lua
local antiJam = createAntiJamSystem(iads, {
    updateInterval = 3   -- 3秒ごとに更新
})

-- ジャマーを検出登録
antiJam:detectJammer({x = 150000, y = 5000, z = 250000}, {
    type = SAM_ANTI_JAM.JAMMER_TYPE.DRFM,
    power = 100,
    effectiveRange = 80000
})

-- SAMのECCMモードを手動設定
antiJam:setEccmMode("SA-10_Battery_1", SAM_ANTI_JAM.ECCM_MODE.FREQ_HOP)

-- ホームオンジャム処理
local hojTarget = antiJam:processHomeOnJam("SA-10_Battery_1")
if hojTarget then
    -- ジャマー位置に向けてミサイル発射可能
end

-- 三角測量でジャマー位置を特定
local location = antiJam:triangulateJammer("JAM-001")

-- ステータス表示
antiJam:printStatus()
```

**ジャマータイプ:**
| タイプ | 説明 |
|--------|------|
| NOISE | ノイズジャミング |
| DECEPTIVE | 欺瞞ジャミング |
| DRFM | デジタルRF記憶ジャミング |
| BARRAGE | バラージジャミング |
| SPOT | スポットジャミング |

**ECCMモード:**
| モード | 説明 | 能力必要 |
|--------|------|----------|
| PASSIVE | パッシブモード（停波） | なし |
| FREQ_HOP | 周波数ホッピング | freqHop |
| BURN_THROUGH | バーンスルー（高出力） | burnThrough |
| HOJ | ホームオンジャム | hoj |
| TRIANGULATION | 三角測量 | triangulation |

### 修復/再配置システム

損傷SAMの修復と戦術的再配置（シュート＆スクート）をシミュレートします。

```lua
local maintenance = createMaintenanceSystem(iads, {
    maxRepairTeams = 3,    -- 最大同時修復チーム数
    shootAndScoot = {
        enabled = true,
        shotsBeforeMove = 2,    -- 2発発射後に移動
        moveDistance = 3000,    -- 3km移動
        cooldownTime = 600      -- 再配置後のクールダウン
    },
    spareUnits = {
        launchers = 10,
        radars = 5,
        commandPosts = 2,
        powerUnits = 5
    }
})

-- ダメージを適用（自動で修復キューに入る）
maintenance:applyDamage("SA-10_Battery_1", 40)  -- 40%ダメージ

-- 手動で再配置を開始
maintenance:startRelocation("SA-11_Battery_1", {
    x = 110000, y = 0, z = 220000
})

-- 発射をカウント（シュート＆スクート用）
maintenance:recordShot("SA-11_Battery_1")

-- ステータス表示
maintenance:printStatus()
```

**損傷レベル:**
| レベル | HP | 動作 |
|--------|-----|------|
| NONE | 90-100% | 通常運用 |
| LIGHT | 60-89% | 修復キュー |
| MODERATE | 30-59% | 修復キュー |
| HEAVY | 1-29% | 修復キュー |
| DESTROYED | 0% | 修復不可 |

**再配置状態:**
| 状態 | 説明 |
|------|------|
| STATIC | 静止中 |
| PACKING | 撤収中 |
| MOVING | 移動中 |
| DEPLOYING | 展開中 |
| READY | 展開完了 |

### カウンターメジャー付きIADS一括セットアップ

```lua
local systems = setupFullCountermeasuresIADS("Red IADS", {
    -- Phase 1
    samPattern = "SAM_",
    ewrPattern = "EWR_",
    linkDistance = 150000,
    emconMode = SAM_EMCON.MODE.BLINK,

    -- Phase 2
    pointDefense = true,
    datalink = true,
    predictor = true,
    silentLaunch = true,
    hvTargets = {
        {type = "airbase", name = "Kutaisi", options = {priority = 1}}
    },

    -- Phase 3
    decoy = true,
    antiJam = true,
    maintenance = true,
    decoyCount = 2,
    decoyRadius = 3000,
    shootAndScoot = {
        enabled = true,
        shotsBeforeMove = 2,
        moveDistance = 3000
    }
})
```

## Phase 4 使用例

### AIコマンダー

脅威レベルに応じて自動的にIADSを管理するAIコマンダーです。

```lua
local commander = createCommanderSystem(iads, {
    tacticalMode = IADS_COMMANDER.TACTICAL_MODE.BALANCED,
    defenseCondition = IADS_COMMANDER.DEFENSE_CONDITION.ELEVATED,
    updateInterval = 5
})

-- 戦術モードを変更
commander:setTacticalMode(IADS_COMMANDER.TACTICAL_MODE.AMBUSH)

-- 防空態勢を手動設定
commander:setDefenseCondition(IADS_COMMANDER.DEFENSE_CONDITION.SEVERE)

-- コールバックを設定
commander:setCallback("onDefconChange", function(oldLevel, newLevel)
    trigger.action.outText("DEFCON changed: " .. newLevel, 10)
end)

-- ステータス表示
commander:printStatus()
```

**防空態勢レベル（DEFCON相当）:**
| レベル | 説明 | 動作 |
|--------|------|------|
| PEACE | 平時 | 最小警戒、ほとんどのSAMがダーク |
| ELEVATED | 警戒 | 一部SAM起動 |
| HIGH | 高警戒 | 多くのSAM起動 |
| SEVERE | 厳戒 | ほぼ全SAM起動 |
| CRITICAL | 最大警戒 | 全SAM稼働 |

**戦術モード:**
| モード | 説明 |
|--------|------|
| CONSERVATIVE | SAM温存、弾薬/HP低下時は停波 |
| BALANCED | バランス重視、脅威に応じて起動 |
| AGGRESSIVE | 積極的、脅威検知で即座に全起動 |
| AMBUSH | 待ち伏せ、射程内に入るまでダーク維持 |

### F10マップ連携

F10マップ上にIADS情報を表示し、ラジオメニューで制御できます。

```lua
local f10Map = createF10MapSystem(iads, {
    updateInterval = 10,
    displaySettings = {
        showSamSites = true,
        showEwrSites = true,
        showThreats = true,
        showDetailedInfo = true
    }
})

-- 表示設定を切り替え
f10Map:toggleDisplay("showThreats")

-- 全マーカーを更新
f10Map:refreshAllMarkers()
```

**ラジオメニューコマンド:**
| メニュー | コマンド | 説明 |
|----------|----------|------|
| Status | Show All Status | 全システムステータス表示 |
| Status | Show SAM Status | SAMステータス表示 |
| Status | Show Threat Status | 脅威ステータス表示 |
| DEFCON | PEACE/ELEVATED/HIGH/SEVERE/CRITICAL | 防空態勢設定 |
| Tactics | Conservative/Balanced/Aggressive/Ambush | 戦術モード設定 |
| SAM Control | Activate All | 全SAM起動 |
| SAM Control | Deactivate All | 全SAM停波 |
| Display | Toggle SAMs/Threats/EWRs | 表示切り替え |
| Display | Refresh Map | マーカー更新 |

**マーカーコマンド（マップ上に入力）:**
```
IADS STATUS       - 位置のステータス表示
IADS ACTIVATE     - 近くのSAMを起動
IADS DEACTIVATE   - 近くのSAMを停波
IADS DEFCON HIGH  - DEFCON設定
```

### 完全なIADS一括セットアップ

```lua
local systems = setupCompleteIADS("Red IADS", {
    -- Phase 1
    samPattern = "SAM_",
    ewrPattern = "EWR_",
    linkDistance = 150000,
    emconMode = SAM_EMCON.MODE.BLINK,

    -- Phase 2
    pointDefense = true,
    datalink = true,
    predictor = true,
    silentLaunch = true,
    hvTargets = {
        {type = "airbase", name = "Kutaisi", options = {priority = 1}}
    },

    -- Phase 3
    decoy = true,
    antiJam = true,
    maintenance = true,
    shootAndScoot = {enabled = true, shotsBeforeMove = 2},

    -- Phase 4
    commander = true,
    f10Map = true,
    tacticalMode = IADS_COMMANDER.TACTICAL_MODE.BALANCED,
    defenseCondition = IADS_COMMANDER.DEFENSE_CONDITION.ELEVATED
})
```

## Phase 5 使用例

### マルチプレイヤー同期

クライアント間でIADS状態を同期します。

```lua
local mpSync = createMPSyncSystem(iads, {
    updateInterval = 1,        -- 1秒ごとに差分同期
    fullSyncInterval = 30      -- 30秒ごとに完全同期
})

-- 同期モードを確認
local status = mpSync:getStatus()
print("Mode: " .. status.mode)  -- HOST/CLIENT/STANDALONE

-- リモートコマンド送信（クライアント→ホスト）
mpSync:sendCommand("ACTIVATE_SAM", {samName = "SA-10_Battery_1"})
mpSync:sendCommand("SET_DEFCON", {level = "HIGH"})

-- ステータス表示
mpSync:printStatus()
```

**同期モード:**
| モード | 説明 |
|--------|------|
| HOST | ホスト（権威サーバー、状態を配信） |
| CLIENT | クライアント（状態を受信） |
| STANDALONE | シングルプレイヤー |

### 陣営別情報フィルタ

プレイヤーの陣営に応じて情報アクセスを制御します。

```lua
local coalitionFilter = createCoalitionFilter({
    redNetwork = redIADS,
    blueNetwork = blueIADS,
    gameMasterEnabled = true
})

-- ゲームマスターを追加
coalitionFilter:addGameMaster(playerId)

-- プレイヤー権限を設定
coalitionFilter:setPlayerPermission(playerId, IADS_COALITION.ACCESS_LEVEL.ELEVATED)

-- 陣営別ラジオメニューを作成
coalitionFilter:createCoalitionRadioMenus(IADS_COALITION.SIDE.RED)
coalitionFilter:createCoalitionRadioMenus(IADS_COALITION.SIDE.BLUE)

-- フィルタリングされたSAM情報を取得
local samInfo = coalitionFilter:getFilteredSamInfo(playerId, targetNetwork)
```

**アクセスレベル:**
| レベル | 説明 |
|--------|------|
| NONE | アクセス不可 |
| BASIC | 基本情報のみ |
| STANDARD | 自軍詳細、敵は検出分のみ |
| ELEVATED | 詳細な敵情報 |
| FULL | ゲームマスター（全情報） |
| ADMIN | 管理者（設定変更可能） |

### マルチプレイヤーIADS一括セットアップ

```lua
local systems = setupMultiplayerIADS("Red IADS", {
    -- Phase 1-4 オプション（省略）
    samPattern = "SAM_",
    ewrPattern = "EWR_",

    -- Phase 5
    multiplayer = true,
    coalitionFilter = true,
    gameMaster = true,
    mpSyncInterval = 1
})
```

### 両陣営対称セットアップ

Red/Blue両方のIADSを同時にセットアップします。

```lua
local dualSystems = setupDualCoalitionIADS({
    sharedOptions = {
        linkDistance = 150000,
        emconMode = SAM_EMCON.MODE.BLINK,
        commander = true,
        f10Map = true
    },
    redOptions = {
        samPattern = "RED_SAM_",
        ewrPattern = "RED_EWR_"
    },
    blueOptions = {
        samPattern = "BLUE_SAM_",
        ewrPattern = "BLUE_EWR_"
    },
    multiplayer = true,
    gameMaster = true
})

-- 各陣営のシステムにアクセス
local redIADS = dualSystems.red.iads
local blueIADS = dualSystems.blue.iads
```

## Web UI システム

ブラウザベースのリアルタイムIADS管理インターフェースです。DCSゲーム外からSAMサイトの監視・制御が可能です。

### アーキテクチャ

```
┌──────────────────┐    JSON Files    ┌──────────────────┐    WebSocket/REST    ┌──────────────────┐
│   DCS World      │ ←─────────────→  │  Bridge Server   │ ←─────────────────→  │   React Client   │
│  (Lua Scripts)   │                  │   (Node.js)      │                      │   (Browser)      │
└──────────────────┘                  └──────────────────┘                      └──────────────────┘
  web_export.lua                        Express + WS                              React + Zustand
  web_import.lua                        Session Manager                           Tailwind CSS
```

### インストール

#### 1. Bridge Server のセットアップ

```bash
cd web-ui/server
npm install
npm run build
npm start
```

サーバーは `http://localhost:3000` で起動します。

#### 2. React Client のセットアップ

```bash
cd web-ui/client
npm install
npm run dev
```

開発サーバーは `http://localhost:5173` で起動します。

#### 3. DCS スクリプトの設定

ミッションエディタのトリガーで以下を読み込みます：

```lua
-- IADSシステムのセットアップ後に追加
dofile(lfs.writedir() .. "Scripts/DCS-SAM/web-ui/dcs/web_export.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/web-ui/dcs/web_import.lua")

-- Web UIエクスポートを初期化
IADS_WEB_EXPORT:init({
    iadsNetwork = redIADS,
    exportPath = lfs.writedir() .. "Scripts/DCS-SAM/web-ui/data/",
    updateInterval = 1,
    coalition = 1  -- RED
})

-- Web UIインポートを初期化
IADS_WEB_IMPORT:init({
    iadsNetwork = redIADS,
    importPath = lfs.writedir() .. "Scripts/DCS-SAM/web-ui/data/",
    pollInterval = 0.5
})
```

### Web UI 使用方法

#### ログイン

1. ブラウザで `http://localhost:5173` を開く
2. プレイヤー名を入力
3. 陣営（RED / BLUE）を選択
4. アクセスレベルを選択
5. 「Enter Control Center」をクリック

**Game Master モード**: 全陣営の情報にアクセス可能な管理者モード

#### ダッシュボード

- **DEFCON レベル**: 現在の防空態勢を表示・変更
- **戦術モード**: CONSERVATIVE / BALANCED / AGGRESSIVE / AMBUSH
- **SAM サイトサマリー**: 状態別のSAM数を表示
- **脅威サマリー**: 脅威レベル別の件数を表示

#### SAM サイト管理

- SAMサイト一覧の表示
- 状態フィルタ（GREEN / DARK / TRACKING / ENGAGING）
- 個別SAMの状態変更
- 全SAM一括制御

#### 脅威モニター

- リアルタイム脅威追跡
- 脅威レベル別表示（CRITICAL / HIGH / MEDIUM / LOW）
- SEAD脅威の強調表示

### Web UI API リファレンス

#### REST API エンドポイント

| エンドポイント | メソッド | 説明 |
|---------------|---------|------|
| `/api/health` | GET | ヘルスチェック |
| `/api/status` | GET | 接続状態 |
| `/api/state` | GET | 完全なIADS状態 |
| `/api/session` | POST | セッション作成（ログイン） |
| `/api/session` | GET | セッション情報取得 |
| `/api/session` | DELETE | セッション削除（ログアウト） |
| `/api/sams` | GET | SAMサイト一覧 |
| `/api/sams/:name` | GET | 特定SAMの詳細 |
| `/api/sams/:name/state` | POST | SAM状態変更 |
| `/api/sams/all/state` | POST | 全SAM状態変更 |
| `/api/threats` | GET | 脅威一覧 |
| `/api/defcon` | GET | DEFCONレベル取得 |
| `/api/defcon` | POST | DEFCONレベル設定 |
| `/api/tactical` | GET | 戦術モード取得 |
| `/api/tactical` | POST | 戦術モード設定 |
| `/api/multiplayer` | GET | マルチプレイヤー情報 |
| `/api/coalition/:id` | GET | 陣営別データ |

#### WebSocket イベント

| イベント | 方向 | 説明 |
|---------|------|------|
| `state:update` | サーバー→クライアント | 状態更新 |
| `sam:updated` | サーバー→クライアント | SAM状態変更通知 |
| `threat:new` | サーバー→クライアント | 新規脅威検出 |
| `threat:updated` | サーバー→クライアント | 脅威情報更新 |
| `defcon:changed` | サーバー→クライアント | DEFCON変更通知 |

#### セッション認証

リクエストヘッダーに `X-Session-Id` を含めて認証します：

```typescript
fetch('/api/sams', {
  headers: {
    'Content-Type': 'application/json',
    'X-Session-Id': 'your-session-id'
  }
});
```

### 陣営別アクセス制御

| 陣営 | アクセス範囲 |
|------|-------------|
| RED | RED陣営のSAM・脅威のみ |
| BLUE | BLUE陣営のSAM・脅威のみ |
| ALL (Game Master) | 全陣営のSAM・脅威 |

| アクセスレベル | 権限 |
|---------------|------|
| VIEW | 閲覧のみ |
| OPERATOR | SAM状態変更可 |
| COMMANDER | DEFCON/戦術モード変更可 |
| ADMIN | 全権限（Game Master用） |

## 開発ロードマップ

### Phase 1 (完了)
- ✅ 弾薬管理システム
- ✅ 動的レーダー運用(EMCON)
- ✅ 統計・ログシステム

### Phase 2 (完了)
- ✅ ポイントディフェンス連携
- ✅ データリンクシミュレーション
- ✅ 航路予測システム

### Phase 3 (完了)
- ✅ デコイ/おとりシステム
- ✅ ジャマー対策（ECCM、HOJ、三角測量）
- ✅ 修復/再配置システム（シュート＆スクート）

### Phase 4 (完了)
- ✅ AIコマンダー（自動IADS管理、戦術モード）
- ✅ F10マップ連携（ステータス表示、ラジオメニュー制御）

### Phase 5 (完了)
- ✅ マルチプレイヤー同期（状態同期、ホスト/クライアント管理）
- ✅ 陣営別情報フィルタ（Red/Blue別アクセス制御）

### Web UI (完了)
- ✅ DCS↔サーバー間ファイルベース通信
- ✅ Bridge Server（Node.js + Express + WebSocket）
- ✅ React SPA（Zustand + Tailwind CSS）
- ✅ マルチプレイヤー対応（セッション管理、陣営別アクセス制御）

## ライセンス

MIT License

## 貢献

バグ報告や機能リクエストはGitHub Issuesへお願いします。
