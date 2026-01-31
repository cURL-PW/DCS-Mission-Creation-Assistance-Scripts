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
│   ├── ammo.lua          # 弾薬管理システム
│   ├── emcon.lua         # EMCONシステム
│   └── logger.lua        # 統計・ログシステム
├── iads/
│   ├── network.lua       # IADSネットワーク管理
│   ├── sector.lua        # 防空セクター管理
│   └── threat.lua        # 脅威情報共有システム
└── misc/
    └── addSamlist.lua    # SAMユニット列挙ユーティリティ
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

## 開発ロードマップ

### Phase 1 (完了)
- ✅ 弾薬管理システム
- ✅ 動的レーダー運用(EMCON)
- ✅ 統計・ログシステム

### Phase 2 (予定)
- ポイントディフェンス連携
- データリンクシミュレーション
- 航路予測システム

### Phase 3 (予定)
- デコイ/おとりシステム
- ジャマー対策
- 修復/再配置システム

### Phase 4 (予定)
- AIコマンダー
- F10マップ連携

### Phase 5 (予定)
- マルチプレイヤー対応

## ライセンス

MIT License

## 貢献

バグ報告や機能リクエストはGitHub Issuesへお願いします。
