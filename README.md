# DCS World Mission Creation Assistance Scripts

DCS Worldミッション作成支援スクリプト集

**Required:** MIST 4.3.74以上

## 概要

このスクリプト集は、DCS Worldのミッション作成を支援するLuaスクリプトです。
主に以下の機能を提供します：

- **SEADシミュレーション**: 対レーダーミサイル発射時のSAMレーダー停波シミュレーション
- **統合防空システム(IADS)ネットワーク**: SAM同士を連携させた協調防空システム

## ディレクトリ構造

```
DCS-Mission-Creation-Assistance-Scripts/
├── README.md
├── main.lua              # メインエントリーポイント
├── SamAutomation.lua     # 旧版SEADスクリプト（後方互換性のため維持）
├── core/
│   ├── config.lua        # SAM設定データ
│   ├── utils.lua         # 共通ユーティリティ
│   └── sead.lua          # SEADシミュレーションシステム
├── iads/
│   ├── network.lua       # IADSネットワーク管理
│   ├── sector.lua        # 防空セクター管理
│   └── threat.lua        # 脅威情報共有システム
└── misc/
    └── addSamlist.lua    # SAMユニット列挙ユーティリティ
```

## インストール

1. MISTをミッションにロードする
2. 必要なスクリプトファイルをロードする

### SEADシステムのみ使用する場合

```lua
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/config.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/utils.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/sead.lua")

-- SEADシステムを初期化
SEAD_SYSTEM.init({debug = false})
```

### IADSネットワークを使用する場合

```lua
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/config.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/utils.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/core/sead.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/iads/network.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/iads/sector.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/iads/threat.lua")
dofile(lfs.writedir() .. "Scripts/DCS-SAM/main.lua")
```

## 使用方法

### 1. SEADシミュレーション（基本機能）

対レーダーミサイル（HARM, LD-10等）が発射された際、SAMのレーダーを一定時間停波させます。

```lua
-- 基本的な初期化
SEAD_SYSTEM.init({debug = true})
```

**対応ミサイル:**
- KH-58
- KH-25MPU
- AGM-88 HARM
- LD-10
- ALARM

**対応SAMシステム:**
- ソ連/ロシア: S-125, S-75, SA-6 Kub, SA-8 Osa, S-300PS, SA-11 Buk, Tor
- 西側: Hawk, Patriot, Roland
- 早期警戒レーダー: 1L13 EWR, 55G6 EWR

### 2. 統合防空システム(IADS)ネットワーク

SAM同士を連携させ、協調した防空を実現します。

```lua
-- IADSネットワークを作成
local redIADS = IADS_NETWORK.new("Red Force IADS")
redIADS:init({updateInterval = 5})

-- SAMサイトを追加
redIADS:addSamSite(Group.getByName("SA-10_Battery_1"))
redIADS:addSamSite(Group.getByName("SA-6_Battery_1"))
redIADS:addSamSite(Group.getByName("SA-11_Battery_1"))

-- 早期警戒レーダー(EWR)を追加
redIADS:addEWR(Group.getByName("EWR_South"))

-- SAMとEWRをリンク
redIADS:linkSamToEWR("SA-10_Battery_1", "EWR_South")
redIADS:linkSamToEWR("SA-6_Battery_1", "EWR_South")

-- SAM同士をリンク（相互支援）
redIADS:linkSamToSam("SA-10_Battery_1", "SA-6_Battery_1")

-- SEADシステムとIADSを連携
SEAD_SYSTEM.init({
    debug = true,
    iadsNetwork = redIADS
})

-- 全SAMをアクティブ化
redIADS:activateAllSams()
```

#### IADSの主な機能

- **SAMネットワーク管理**: SAMサイトをネットワークとして管理
- **EWRからの情報配信**: 早期警戒レーダーの情報をSAMに配信
- **脅威情報共有**: 検知した脅威を全ノードで共有
- **協調レーダー運用**: 一部SAMが停波しても他のSAMがカバー
- **セクター管理**: 防空エリアをセクターに分割して管理

### 3. 自動セットアップ機能

グループ名のパターンを使って自動的にSAMやEWRを追加できます。

```lua
dofile(lfs.writedir() .. "Scripts/DCS-SAM/main.lua")

local iads = createIADS("My IADS", {debug = true})

-- "SAM_"で始まるグループを自動追加
autoAddSamSites(iads, "SAM_", coalition.side.RED)

-- "EWR_"で始まるグループを自動追加
autoAddEWRs(iads, "EWR_", coalition.side.RED)

-- 150km以内のユニットを自動リンク
autoLinkByDistance(iads, 150000)

-- SEADと連携
SEAD_SYSTEM.init({iadsNetwork = iads})
```

### 4. セクター管理

防空エリアをセクターに分割して、セクターごとに脅威レベルに応じた対応が可能です。

```lua
-- セクターを作成（中心座標と半径）
local sector1 = createSectorWithSams(iads, "Sector_North", {x = 100000, z = 200000}, 80000)

-- セクターの脅威レベルに応じて自動的にSAMがアクティブ化/停波される
```

### 5. 脅威情報共有システム

脅威を追跡し、優先度に基づいて対応します。

```lua
-- 脅威管理システムを作成
local threatMgr = IADS_THREAT.new(iads)
threatMgr:init()

-- 脅威を検出した場合
threatMgr:reportDetection(targetUnit, "EWR_South")

-- 優先度順のトラック一覧を取得
local tracks = threatMgr:getTracksByPriority()
```

## SAM設定のカスタマイズ

`core/config.lua`でSAMの動作パラメータを変更できます。

```lua
-- 例: SA-6の設定を変更
SAM_CONFIG.Types["Kub 1S91 str"] = {
    suppressionRate = 80,      -- 停波確率 80%
    minOffDelay = 10,          -- 停波までの最小時間
    maxOffDelay = 15,          -- 停波までの最大時間
    minOnDelay = 30,           -- 再起動までの最小時間
    maxOnDelay = 45,           -- 再起動までの最大時間
    suppressGroup = true,      -- グループ全体を停波
    category = "STR",
    trackingRange = 75,
    engagementRange = 24,
}
```

## API リファレンス

### SEAD_SYSTEM

| 関数 | 説明 |
|------|------|
| `init(options)` | SEADシステムを初期化 |
| `setIADSNetwork(network)` | IADSネットワークと連携 |
| `getSuppressedGroups()` | 現在停波中のグループを取得 |
| `isGroupSuppressed(groupName)` | グループが停波中か確認 |
| `manualSuppress(group, duration)` | 手動でグループを停波 |

### IADS_NETWORK

| 関数 | 説明 |
|------|------|
| `new(name)` | ネットワークを作成 |
| `init(options)` | ネットワークを初期化 |
| `addSamSite(group, options)` | SAMサイトを追加 |
| `addEWR(group, options)` | EWRを追加 |
| `linkSamToEWR(samName, ewrName)` | SAMとEWRをリンク |
| `linkSamToSam(sam1, sam2)` | SAM同士をリンク |
| `activateSam(groupName)` | SAMをアクティブ化 |
| `deactivateSam(groupName)` | SAMを停波 |
| `activateAllSams()` | 全SAMをアクティブ化 |
| `deactivateAllSams()` | 全SAMを停波 |
| `getStatus()` | ネットワーク状態を取得 |
| `printStatus()` | ステータスを画面に表示 |

### IADS_THREAT

| 関数 | 説明 |
|------|------|
| `new(network)` | 脅威管理システムを作成 |
| `reportDetection(unit, detectedBy)` | 脅威検出を報告 |
| `getTracksByPriority()` | 優先度順のトラック一覧を取得 |
| `getNearestThreat(pos)` | 最も近い脅威を取得 |
| `getThreatsInRange(pos, range)` | 範囲内の脅威を取得 |

## ライセンス

MIT License

## 貢献

バグ報告や機能リクエストはGitHub Issuesへお願いします。
