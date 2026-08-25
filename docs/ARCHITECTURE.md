# アーキテクチャ (Architecture)

「どう作られているか」を規定する技術設計書。ゲーム仕様は [REQUIREMENTS.md](REQUIREMENTS.md)。

## 全体像

- エンジン: Godot 4.6 / Forward+、言語 GDScript。
- 形態: リアルタイム3D＋ネット対戦。試合の進行と判定はホストが行い、参加者（クライアント）は操作を要求として送る。
- 構成: ノード合成・signal・autoload・Resource を基本とする。ルールは機能ごとの System（Node）が担い、
  参加者ごとの状態はその参加者ノードのコンポーネントが保持する。`Match` は試合の構築と結線に限定する。

## 設計方針

1. 状態は持ち主が保持する。参加者ごとの状態（効果・クールダウン・アイテム・視界）は参加者ノードの
   コンポーネントが持ち、`Match` が集約辞書で束ねない。
2. 機能は合成で構成する（継承より合成）。
3. 分割単位は「同じ理由で変更される範囲」。相互に頻繁に呼び合うだけの細かい分割はしない。
4. 型は用途で選ぶ。tree常駐・signal・毎フレーム処理・RPC が要るものは Node、純粋な入力→出力の
   ロジックは RefCounted、定義・数値データは Resource。
5. ルールは機能ごとの System（Node）が持つ。`Match` はルール・状態・表示を持たない。
6. 表示は MVP（Passive View）。`game_hud` は描画専用で、状態→表示の変換は `HudPresenter` が担い、
   View からの逆参照はしない。
7. 型契約（interface/DI）は導入しない。必要な所（ネット同期など）だけ明示的に固める。

## 機能追加時の規約

機能を追加・変更するときに守る。

- 状態を足すとき: 参加者のコンポーネントに持たせる（`Match` や autoload に置かない）。同期が必要なら
  `game_state_codec.gd` に追加する。
- 操作（入力）を足すとき: 入力は要求として送る。ネットではクライアントを信用せず、`net_sync.gd` の
  ホスト側で妥当性を確認してから適用する。
- 能力を足すとき: `abilities/` に `ability_NN.gd` を追加し `ability_system.gd` に登録する（既存を
  書き換えない）。
- 表示を足すとき: `game_hud` に受け口（setter）を足し、`hud_presenter.gd` が状態を読んで呼ぶ。
  `game_hud` にゲームロジックを書かない、状態を読ませない。
- 数値・定数: `game_tuning.gd`（Resource）または定数に置く。マジックナンバーを散らさない。
- 依存の向き: 上位が下位を持つ。下位（コンポーネント / System）は上位（`Match` / UI）を参照しない。
  通知は signal で上げる。
- マップを足すとき: `Map` scene として作り、必要なマーカー（SpawnPoints / Stations）を持たせる。
  `Match` / System は特定のマップを参照しない。
- 置き場: フォルダは層に対応する。新しいスクリプトは責務に対応するフォルダに置く。

## シーン構成

`Match` はマップ非依存の「試合」。選択したマップは子シーンとして差し込む。

```
Match (Node3D, match.gd)              構築・結線・System の tick 発火
├─ Map                               選択したマップ scene を差し込む
│    WorldEnvironment / 照明 / Room(壁・家具) / SpawnPoints(Marker3D) / Stations をマップが持つ
├─ Participants (Node3D)             参加者の親。spawn 親・iteration の基準
│    ├─ Player   (CharacterBody3D)
│    └─ Computer1..N (CharacterBody3D)
├─ Systems (Node)
│    ├─ CombatSystem
│    ├─ AbilitySystem
│    ├─ ItemSystem
│    ├─ ExchangeSystem
│    ├─ NetSync                      RPC ホスト（固定名）
│    └─ GameFlow                     開始 / 終了 / リザルト
├─ Services (Node)
│    └─ Deck
└─ UI (CanvasLayer)
     ├─ GameHud
     ├─ PauseMenu
     └─ Settings
```

各参加者（Player / Computer）の内部：

```
Player (CharacterBody3D, player.gd)
├─ Camera / Mesh / Collision
├─ StatusComponent    (Node)   時限効果（無敵/バリア/透明/鎌 等）の保持・期限処理・問い合わせ・変化 signal
├─ CooldownComponent  (Node)   kill / ability クールダウン
├─ ItemComponent      (Node)   所持アイテム・パッシブスロット算出
└─ VisionComponent    (Node)   覗き見 / マップ開示の時限状態
```

- マップは子シーンに分離し、`Match` はマップを参照しない（複数マップに対応）。照明・壁・家具・スポーン地点・
  交換ステーションはマップ側の実ノードとして宣言する。
- `Participants` / `Systems` / `Services` / `UI` の器を設け、ノードパスを安定させる。

## スクリプトと型

### Node

| スクリプト | 付く場所 | 責務 |
|---|---|---|
| `match.gd` | Match(root) | 構築・`_process` で System の `tick()` を発火・結線 |
| `participants.gd` | Participants | 参加者リスト・名前/peer 解決・spawn 配置 |
| `status_component.gd` | 参加者の子 | 時限効果の保持・期限処理・問い合わせ・変化 signal |
| `cooldown_component.gd` | 参加者の子 | kill / ability クールダウン |
| `item_component.gd` | 参加者の子 | 所持アイテム・パッシブスロット算出 |
| `vision_component.gd` | 参加者の子 | 覗き見 / マップ開示の時限状態 |
| `combat_system.gd` | Systems | kill / change / scythe / sword / barrier / counter / ミサイル命中 |
| `ability_system.gd` | Systems | ペア判定・rank→Ability の選択・発動 |
| `item_system.gd` | Systems | アイテムの付与 / 使用 / 更新 |
| `exchange_system.gd` | Systems | 交換ステーションの処理 |
| `net_sync.gd` | Systems | RPC の受け口・操作の妥当性確認（ホスト側）。RPC を受けるため固定名の Node にする |
| `game_flow.gd` | Systems | 制限時間・終了条件・リザルト |
| `game_hud.gd` / `pause_menu.gd` / `settings.gd` | UI | 表示 |
| `deck.gd` | Services | 山札・カード配布 |
| `player.gd` / `computer.gd` / `homing_missile.gd` | Entities | 移動・見た目・手札。`computer.gd` は AI の意思決定を持つ |

### RefCounted

| スクリプト | 責務 |
|---|---|
| `targeting_service.gd` | 照準（視線・中心ドット判定でのターゲット探索） |
| `game_state_codec.gd` | ネット状態の直列化 / 復元 |
| `ability.gd` ＋ `ability_01..13.gd` ＋ `ability_context.gd` | 能力の Strategy 群と発動コンテキスト |
| `hud_presenter.gd` | 状態→表示の変換（MVP の Presenter） |
| `hand_sorter.gd` | 手札整列 |

### Resource

| スクリプト | 責務 |
|---|---|
| `game_tuning.gd` | `STUN_SECONDS` / `KILL_DISTANCE` / 各クールダウン等の定数 |

能力（rank 1〜13）は Strategy として `ability_01..13.gd` に個別実装し、`ability_system.gd` が rank から選び
`ability_context.gd`（deck・参加者・コンポーネント等への参照）を渡して実行する。AI の意思決定は
`computer.gd` が持ち、中央の System は設けない。

## ディレクトリ構成（scripts/）

フォルダはアーキテクチャの層に対応する。

```
scripts/
  match.gd                     Composition Root
  match/          participants.gd  game_flow.gd
  systems/        combat_system  ability_system  item_system  exchange_system
  abilities/      ability(基底)  ability_context  ability_01..13
  entities/       player  computer  homing_missile
     components/  status_component  cooldown_component  item_component  vision_component
  net/            net_sync  game_state_codec  network_manager  eos_manager  eos_lobby_manager
  ui/             game_hud  hud_presenter  minimap  item_slot  card_view
                  pause_menu  settings  title  tutorial  lobby  waiting_room
     effects/     edge_status_effect
  services/       deck
  map/            mansion_builder
  config/         game_config(autoload)  game_tuning(Resource)
  util/           hand_sorter  targeting_service
```

- `services/` は試合中の共有サービス、`map/` はマップ生成、`net/` は通信と同期。
- ルール System は `systems/`、能力の Strategy は `abilities/`、参加者コンポーネントは
  `entities/components/`。

## Autoload

`project.godot` の `[autoload]` に登録する。横断サービスのみを置き、試合ごとの状態は置かない。

| Autoload | 実体 | 役割 |
|---|---|---|
| `GameConfig` | `scripts/config/game_config.gd` | 設定・多言語テキスト・ゲームパラメータ（マップ, CPU数, デッキ枚数, 制限時間 等） |
| `NetworkManager` | `scripts/net/network_manager.gd` | ENet による host/join（LAN直結） |
| `EOSManager` | `scripts/net/eos_manager.gd` | EOS 初期化・ログイン |
| `EOSLobbyManager` | `scripts/net/eos_lobby_manager.gd` | EOS ロビーの作成/検索/参加 |
| `HPlatform`, `HAuth`, `HLobbies`, `HP2P` … | EOSアドオン | Epic Online Services SDK ラッパー（`addons/epic-online-services-godot`） |

## ネットワーク

- 進行と判定はホストが行う。クライアントの操作は `net_sync.gd` の RPC 入口へ送り、ホスト側で妥当性を
  確認してから適用する。状態は `game_state_codec.gd` が直列化して配信する。
- RPC の制約: RPC は NodePath が全ピアで一致する Node にしか届かないため、ネットの入口 `NetSync` は
  固定名の子 Node とする。直列化ロジック `game_state_codec.gd` は RefCounted。
- トランスポート: `NetworkManager`（ENet, LAN直結）、`EOSManager` ＋ `EOSLobbyManager`（EOSロビー）。
  認証情報が無い環境では EOS を無効化し、シングル / LAN は動作する。
- CPU（AI）参加者はローカルで処理する。

## 秘密情報の扱い

`eos_credentials.local.cfg` は `.gitignore` 済み。`eos_manager.gd` がこのファイルを読み込み、無ければ
EOS を無効化する（シングル / LAN は動作する）。
