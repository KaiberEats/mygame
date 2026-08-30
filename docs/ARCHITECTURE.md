# アーキテクチャ (Architecture)

「どう作られているか」を規定する技術設計書。ゲーム仕様は [REQUIREMENTS.md](REQUIREMENTS.md)。

## 全体像

- エンジン: Godot 4.6 / Forward+、言語 GDScript。
- 形態: リアルタイム3D＋ネット対戦。試合の進行と判定はホストが行い、参加者（クライアント）は操作を要求として送る。
- 構成: ノード合成・signal・autoload・Resource を基本とする。ルールは機能ごとの System（Node）が担い、
  参加者ごとの状態はその参加者ノードのコンポーネントが保持する。`Match` は試合の構築と結線に限定する。

## 設計方針

1. 状態は持ち主が保持する。参加者ごとの状態（効果・クールダウン・アイテム・視界）は参加者ノードの
   コンポーネントが持つ。横断的な状態も専用の持ち主が持つ: 進行状態（残り時間・終了フラグ）は
   `GameStateManager`、参加者一覧・ローカルプレイヤー・スポーン地点は `Participants`、チェンジ権は
   `CombatSystem`、交換の長押し進行は `ExchangeSystem`、ローカル照準は `PlayerController`。`main` は状態を
   束ねない。
2. 依存は明示的に注入する。各 System は必要なものだけを `setup(...)` / コンストラクタで受け取る。`main`
   全体（神コンテキスト）を渡して内部を触る構造は禁止。依存の解決（構築・結線）は `main` に集約する。
3. 機能は合成で構成する（継承より合成）。共通の土台が要る場合のみ基底クラスにする
   （例: `Participant` が Player/Computer 共通のコンポーネント取得を提供）。
4. 分割単位は「同じ理由で変更される範囲」。相互に頻繁に呼び合うだけの細かい分割はしない。
5. 型は用途で選ぶ。tree常駐・signal・毎フレーム処理・RPC が要るものは Node、純粋な入力→出力の
   ロジックは RefCounted、定義・数値データは Resource / autoload の定数。
6. ルールは機能ごとの System（Node）が持つ。`main` はルール・状態・表示を持たない。
7. 表示は MVP（Passive View）。`game_hud` は描画専用で、状態→表示の変換は `HudPresenter` が担い、
   View からの逆参照はしない。
8. 型契約（interface）は導入しない。依存は具象型を明示的に注入し、抽象化の層は挟まない。

## 機能追加時の規約

機能を追加・変更するときに守る。

- 状態を足すとき: まず持ち主を決める。参加者ごとなら参加者のコンポーネント、横断的なら専用の
  Manager/System に持たせる（`main` や autoload に置かない）。同期が必要なら `game_state_codec.gd` に追加する。
- System / Manager を足すとき: `main._ready` で構築し、必要な依存だけを `setup(...)` で明示注入する
  （`main` 全体を渡さない）。
- 操作（入力）を足すとき: 入力は要求として送る。ネットではクライアントを信用せず、`net_sync.gd` の
  ホスト側で妥当性を確認してから適用する。System からネット送信・通知を行う場合は `NetGateway` 経由にする
  （@rpc 本体は `main`）。
- 能力を足すとき: `abilities/` に `ability_NN.gd` を追加し `ability_system.gd` に登録する（既存を
  書き換えない）。能力が触る依存は `AbilityContext` のフィールドとして渡す。
- 表示を足すとき: `game_hud` に受け口（setter）を足し、`hud_presenter.gd` が状態を読んで呼ぶ。
  `game_hud` にゲームロジックを書かない、状態を読ませない。
- 数値・定数: `game_config.gd`（autoload）の定数に置く。マジックナンバーを散らさない。
- 見た目を持つオブジェクト: コードで動的生成せず `.tscn` 資産にしてエディタで調整する
  （例: `ExchangeStation.tscn` / `Results.tscn`）。
- 依存の向き: 上位が下位を持つ。下位（コンポーネント / System）は上位（`main` / UI）を参照しない。
  通知は signal で上げる（例: `Participants.remote_respawn_requested`）。
- マップを足すとき: `Map` scene として作り、必要なマーカー（SpawnPoints / Stations）を持たせる。
  `Match` / System は特定のマップを参照しない。
- 置き場: フォルダは層に対応する。新しいスクリプトは責務に対応するフォルダに置く。

## シーン構成

`Match` はマップ非依存の「試合」。選択したマップは子シーンとして差し込む。

```
Match (Node3D, main.gd)              構築・結線・System の tick 発火・@rpc 入口
├─ Map                               選択したマップ scene を差し込む
│    WorldEnvironment / 照明 / Room(壁・家具) / SpawnPoints(Marker3D) をマップが持つ
├─ Participants (Node3D)             参加者の親。spawn 親・iteration の基準
│    ├─ Player   (CharacterBody3D, Participant 継承)
│    └─ Computer1..N (CharacterBody3D, Participant 継承)
├─ ExchangeStation × 2               ExchangeStation.tscn を ExchangeSystem が生成・配置
├─ Systems (Node)                    System 群をシーンに配置（main が @onready で参照・結線・tick）
│    ├─ CombatSystem / AbilitySystem / ItemSystem / ExchangeSystem / StatusSystem
│    ├─ GameFlow / GameStateManager / NetSync / PlayerController
├─ Services (Node)
│    └─ Deck
└─ UI (CanvasLayer)
     ├─ GameHud
     ├─ PauseMenu
     └─ Settings
```

- System 群と `GameStateManager` は `Match.tscn` に子ノードとして配置し、`main` は `@onready` で参照する
  （`main` が `new()` で生成しない）。依存注入は `main._ready` が明示的に行う。
- メニュー/HUD の signal（ポーズ/設定/チュートリアル/並べ替え等）は `Match.tscn` の接続で結線する。
  実行時に相手が決まる接続（`peers_changed` / ローカルプレイヤーの `hand_changed` / リスポーン）だけコードで行う。

各参加者（Player / Computer）は共通基底 `Participant`（`CharacterBody3D` 継承）を継承し、内部に状態
コンポーネントを自己 attach する：

```
Player (CharacterBody3D → Participant, player.gd)
├─ Camera / Mesh / Collision
├─ StatusComponent    (Node)   時限効果（無敵/バリア/透明/鎌 等）の保持・期限処理・問い合わせ・変化 signal
├─ CooldownComponent  (Node)   kill / ability クールダウン（残り時間の算出も持つ）
├─ ItemComponent      (Node)   所持アイテム・パッシブスロット算出
└─ VisionComponent    (Node)   覗き見 / マップ開示の時限状態
```

- `Participant` 基底が `status()/cooldown()/item()/vision()` の型付きゲッターと `is_computer()` /
  `get_display_name()` を提供し、コンポーネントを `_ready` で自己 attach する。
- マップは子シーンに分離し、`main` はマップを参照しない（複数マップに対応）。交換ステーションは
  `ExchangeStation.tscn` を `ExchangeSystem` が実行時に生成・配置する。
- `Systems` / `Participants` / `Services` / `UI` の器を設け、ノードパスを安定させる。`NetGateway` /
  `HudPresenter` / `Participants` は RefCounted のためシーンに置けず、`main` が生成して保持する。

## スクリプトと型

### Node

| スクリプト | 付く場所 | 責務 |
|---|---|---|
| `main.gd` | Match(root) | オーケストレーター。構築・結線・`_process` で各層の tick 発火・@rpc 入口 |
| `game_state_manager.gd` | Systems | 進行状態（残り時間・終了フラグ・スナップショットタイマー）の保持 |
| `participant.gd` | Player/Computer の基底 | コンポーネントの自己 attach と型付きゲッター・`is_computer`/`get_display_name` |
| `status_component.gd` | 参加者の子 | 時限効果の保持・期限処理・問い合わせ・変化 signal |
| `cooldown_component.gd` | 参加者の子 | kill / ability クールダウン（残り時間の算出も持つ） |
| `item_component.gd` | 参加者の子 | 所持アイテム・パッシブスロット算出 |
| `vision_component.gd` | 参加者の子 | 覗き見 / マップ開示の時限状態 |
| `combat_system.gd` | Systems | kill / change / scythe / sword / barrier / counter。チェンジ権(change_rights)を所有 |
| `ability_system.gd` | Systems | ペア判定・rank→Ability の選択・発動 |
| `item_system.gd` | Systems | アイテムの付与 / 使用 / 更新 |
| `exchange_system.gd` | Systems | 交換ステーションの生成/処理・長押し進行の保持 |
| `net_sync.gd` | Systems | RPC の受け口・操作の妥当性確認（ホスト側）。RPC を受けるため固定名の Node にする |
| `status_system.gd` | Systems | 効果の期限処理(tick)・状態問い合わせ・視界(覗き見/開示)クエリ |
| `game_flow.gd` | Systems | 制限時間・終了条件・リザルト |
| `game_hud.gd` / `pause_menu.gd` / `settings.gd` | UI | 表示 |
| `player_controller.gd` | Systems | ローカル入力受付・メニュー・行動要求への変換・ローカル照準の保持 |
| `deck.gd` | Services | 山札・カード配布 |
| `player.gd` / `computer.gd` / `homing_missile.gd` | Entities | 移動・見た目・手札。`computer.gd` は AI の意思決定を持つ |

### RefCounted

| スクリプト | 責務 |
|---|---|
| `participants.gd` | 参加者レジストリ（一覧・ローカルプレイヤー・スポーン地点）と生成・配置・リスポーン。`main` が保持 |
| `net_gateway.gd` | System から試合のネット入口（通知・アクション送信・ミサイル）へアクセスする窓口。@rpc 本体は `main` |
| `targeting_service.gd` | 照準（視線・中心ドット判定でのターゲット探索・最近傍） |
| `game_state_codec.gd` | ネット状態の直列化 / 復元 |
| `ability.gd` ＋ `ability_01..13.gd` ＋ `ability_context.gd` | 能力の Strategy 群と発動コンテキスト |
| `hud_presenter.gd` | 状態→表示の変換（MVP の Presenter） |
| `hand_sorter.gd` | 手札整列 |
| `clock.gd` | 経過秒 `Clock.now()`（時限効果の期限判定に使う共有時刻） |

### 定数

ゲーム調整値（`STUN_SECONDS` / `KILL_DISTANCE` / 各クールダウン等）は autoload の `game_config.gd` に定数
（`const`）として集約し、各層は `GameConfig.X` で参照する。

能力（rank 1〜13）は Strategy として `ability_01..13.gd` に個別実装し、`ability_system.gd` が rank から選び
`ability_context.gd`（deck・参加者・触る System への参照）を渡して実行する。AI の意思決定は
`computer.gd` が持ち、中央の System は設けない。

## ディレクトリ構成（scripts/）

フォルダはアーキテクチャの層に対応する。

```
scripts/
  main.gd                      Composition Root（エントリ。scripts/ 直下の単独ファイル）
  systems/        combat_system  ability_system  item_system  exchange_system  status_system  game_flow
                  game_state_manager
  abilities/      ability(基底)  ability_context  ability_01..13
  entities/       participant(基底)  player  computer  homing_missile  participants
     components/  status_component  cooldown_component  item_component  vision_component
  net/            net_sync  net_gateway  game_state_codec  network_manager  eos_manager  eos_lobby_manager
  ui/             game_hud  hud_presenter  player_controller  minimap  item_slot  card_view
                  pause_menu  settings  title  tutorial  lobby  waiting_room
     effects/     edge_status_effect
  services/       deck
  map/            mansion_builder
  config/         game_config(autoload)
  util/           hand_sorter  targeting_service  clock
```

- `services/` は試合中の共有サービス、`map/` はマップ生成、`net/` は通信と同期。
- ルール System は `systems/`、能力の Strategy は `abilities/`、参加者コンポーネントは
  `entities/components/`。

## Autoload

`project.godot` の `[autoload]` に登録する。横断サービスのみを置き、試合ごとの状態は置かない。

| Autoload | 実体 | 役割 |
|---|---|---|
| `GameConfig` | `scripts/config/game_config.gd` | 設定・多言語テキスト・ゲームパラメータ（マップ, CPU数, デッキ枚数, 制限時間 等）・調整定数（`KILL_DISTANCE` 等） |
| `NetworkManager` | `scripts/net/network_manager.gd` | ENet による host/join（LAN直結） |
| `EOSManager` | `scripts/net/eos_manager.gd` | EOS 初期化・ログイン |
| `EOSLobbyManager` | `scripts/net/eos_lobby_manager.gd` | EOS ロビーの作成/検索/参加 |
| `HPlatform`, `HAuth`, `HLobbies`, `HP2P` … | EOSアドオン | Epic Online Services SDK ラッパー（`addons/epic-online-services-godot`） |

## ネットワーク

- 進行と判定はホストが行う。クライアントの操作は要求として送り、`net_sync.gd` がホスト側で妥当性を
  確認してから適用する。状態は `game_state_codec.gd` が直列化して配信する。
- RPC の制約: RPC は NodePath が全ピアで一致する Node にしか届かないため、@rpc 入口は `Match`(root, `main.gd`)
  に置く。System からの通知・アクション送信・ミサイルは `NetGateway`（`main` の @rpc を呼ぶ窓口）経由にする。
  検証・dispatch・peer 解決は `net_sync.gd`、直列化 `game_state_codec.gd` は RefCounted。
- トランスポート: `NetworkManager`（ENet, LAN直結）、`EOSManager` ＋ `EOSLobbyManager`（EOSロビー）。
  認証情報が無い環境では EOS を無効化し、シングル / LAN は動作する。
- CPU（AI）参加者はローカルで処理する。

## 秘密情報の扱い

`eos_credentials.local.cfg` は `.gitignore` 済み。`eos_manager.gd` がこのファイルを読み込み、無ければ
EOS を無効化する（シングル / LAN は動作する）。
