# 全面改修 タスク一覧

順に実施。各タスク後に [検証標準](plan.md#検証標準毎タスク共通)（scan / シーン起動 / 手動確認）を行う。
コミットは**フェーズ単位**（各フェーズ完了時・簡潔メッセージ・既定は差分提示→OKで実行）。
レビュー関門は計2回（フェーズ3後・フェーズ7後）。

---

## フェーズ0：足場（ディレクトリ再編）

- [ ] **T0.1 フォルダ再編・既存ファイル移動**
  - 内容: `services/`（deck）, `map/`（mansion_builder）, `net/`（旧network + 今後の net_sync/codec 置き場）,
    `ui/effects/`（edge_status_effect）を作成し既存を移動。`systems/` `abilities/` `match/`
    `entities/components/` を新設（空でよい）。`main.gd` はまだ改名しない。
  - 参照更新: `project.godot` autoload、各 preload、`.tscn` のスクリプト参照、`.uid`。
  - 受入基準: 参照が全て新パス。ゲーム挙動は不変。
  - 検証: scan `ERROR:0` / Title・本編・待機室 起動 clean。
- **▶ フェーズ0 コミット**:「scripts をアーキテクチャ構成に再編」

## フェーズ1：状態を持ち主へ（コンポーネント）

- [ ] **T1.1 StatusComponent（時限効果）**
  - 移す: `_effects[p]` の保持、`_update_effects` の効果期限処理、`_is_effect_active`/`_has_extra_kill`/
    `_has_free_change`/`_has_ready_scythe`/`_has_ready_coin`、`_refresh_speed_multiplier` の効果読取。
  - 方法: 各参加者（Player.tscn / Computer.tscn）に `StatusComponent` 子ノードを追加。`main` は
    component 経由で読み書き（内側辞書は参照を返す accessor で既存の書き換えを維持）。
  - HUD: 状態枠（joker/無敵/バリア）は `hud_presenter` が component を読む意味APIに。
  - 受入基準: 無敵/バリア/透明/鎌/coin/counter/auto_cleanse/automatic_kill の付与・期限・見た目・状態枠が従来通り。
  - 手動確認: 能力3(無敵)→金アウトライン→時間解除、能力12(バリア)→球表示→kill1回吸収。
- [ ] **T1.2 CooldownComponent**
  - 移す: `_kill_cooldown_until`/`_ability_cooldown_until`、`_get_kill_cooldown_left`/`_get_ability_cooldown_left`。
  - HUD: kill/ability クールダウン表示を presenter 経由に。
  - 受入基準: kill/能力後のクールダウン表示・再使用可否が従来通り。
- [ ] **T1.3 ItemComponent**
  - 移す: `_items[p]`、`_passive_item_slot_for`、`_update_items` のアイテム時間処理。
  - HUD: アイテムスロット表示を presenter 経由に（`_sync_player_item_slot` の表示部）。
  - 受入基準: MISSILE/SWORD の付与・使用・時間切れ、パッシブ表示(SCYTHE/COIN/RAPIER/SHIELD)が従来通り。
- [ ] **T1.4 VisionComponent**
  - 移す: `_card_views`/`_map_reveals` とその期限、`_is_location_revealed`/`_is_hand_being_viewed`。
  - HUD: ミニマップ/覗き見手札/露出表示を presenter 経由に。
  - 受入基準: 能力5(覗き見)・11(マップ開示)の表示と期限が従来通り。
- **▶ フェーズ1 コミット**:「参加者の状態をコンポーネントに移行」

## フェーズ2：純サービス

- [ ] **T2.1 TargetingService（RefCounted）**
  - 移す: `_find_aimed_target`/`_find_kill_target`/`_find_change_target`/`_find_scythe_target`/
    `_find_coin_change_target`/`_find_visible_missile_target`/`_has_line_of_sight`/`_find_nearest_participant`。
  - 受入基準: 照準による kill/change/scythe/coin 対象選択・ミサイル対象が従来通り。
- **▶ フェーズ2 コミット**:「照準ロジックを TargetingService に分離」

## フェーズ3：ルール System

- [ ] **T3.1 CombatSystem（Node）**
  - 移す: `_perform_kill`/`_perform_kill_with_options`/`_perform_change`/`_use_scythe`/`_use_sword`/
    `_stun_without_change`/`_change_killers`/`on_missile_hit`/`_launch_missile`/`_spawn_missile`/
    `_clear_expired_change_rights`/`_update_automatic_kills`。Status/Cooldown/Targeting を利用。
  - 受入基準: kill/change/counter/barrier/invincible/scythe/sword/ミサイル/自動kill の全経路が従来通り。
- [ ] **T3.2 AbilitySystem（Node）＋ abilities/ Strategy**
  - 移す: `_try_use_pair`/`_activate_pair_ability`（→ `ability_01..13.gd` に分解）/`_is_valid_pair_slot`/
    `_get_ability_message`。`ability.gd`（基底）と `ability_context.gd`（deck/参加者/コンポーネント参照）を新設。
  - 受入基準: 全13能力＋各強化版が従来通り。1能力の追加/変更が他能力に影響しない。
- [ ] **T3.3 ItemSystem（Node）**
  - 移す: `grant_item`/`_use_item`/`_use_passive_item`/`_activate_item`。ItemComponent と連携。
  - 受入基準: アイテム使用経路（能動/パッシブ）が従来通り。
- [ ] **T3.4 ExchangeSystem（Node）**
  - 移す: `_setup_exchange_stations`/`_deal_exchange_station_cards`/`_station_cards`/`_set_station_cards`/
    `_exchange_with_station`/`_find_aimed_exchange_station`/`_exchange_hold*`/`_exchange_stations`。
  - 受入基準: 交換ステーションのホールド・実行・カード補充が従来通り。
- **▶ フェーズ3 コミット**:「ゲームルールを System 群に分離」
- **★レビュー1（フェーズ0〜3）** — ここまでをまとめてレビュー

## フェーズ4：ネット

- [ ] **T4.1 GameStateCodec（RefCounted）**
  - 移す: `_build_game_state`/`_receive_game_state`/`_apply_effect_state`/`_apply_card_view_state`/
    `_apply_map_reveal_state`/`_build_card_view_state`/`_build_map_reveal_state`/`_network_item_for`/`_same_cards`。
    コンポーネントを読み書きする。
  - 受入基準: full-state 同期の内容が従来と一致。
- [ ] **T4.2 NetSync（Node・固定名＝RPCホスト）**
  - 移す: RPC `_request_action`/`_request_exchange`/`_request_reorder`/`_request_full_state`、`_can_server_*`、
    `_request_local_action`/`_execute_player_action`、`_participant_for_peer`/`_peer_for_participant`/`_is_game_authority`。
  - 受入基準: online の kill/change/scythe/coin/exchange/reorder がホスト側検証込みで従来通り。
  - 手動確認: **2インスタンス（host+client）で対戦し操作同期を確認**。
- **▶ フェーズ4 コミット**:「ネット同期を Codec/NetSync に分離」

## フェーズ5：進行＋表示仕上げ

- [ ] **T5.1 GameFlow（Node）**
  - 移す: `_finish_game`/`_receive_game_finished`/`_calculate_standings`/`_show_results`/`_has_empty_hand`/
    `_time_left`、`_respawn_out_of_bounds_participants`/`_receive_respawn`。
  - 受入基準: 制限時間切れ・手札枯渇での終了とリザルト表示、場外リスポーンが従来通り。
- [ ] **T5.2 HudPresenter 意味API化（仕上げ）**
  - 内容: presenter が `main`/コンポーネントの内部データを直接読む箇所を全廃し、意味のある問い合わせAPI
    経由に統一。`_sync_player_item_slot`・通知・チェンジプレビューの振り分けを整理。
  - 受入基準: 全HUD要素が従来通り、かつ presenter が他の内部 private を直接参照しない。
- **▶ フェーズ5 コミット**:「進行を GameFlow に分離、HUD を Presenter に集約」

## フェーズ6：シーン骨格・改名

- [ ] **T6.1 participants.gd ＋ Participants 器**
  - 移す: `_participants`/`_participant_by_name`/`_configure_computers`/`_spawn_network_players`/
    `_refresh_network_player_profiles`/`_cache_participant_spawn_positions`/`_spawn_position_*`/`_default_spawn_for_participant`。
  - 内容: 参加者を `Participants` 配下へ。ハードコード Computer と実行時 spawn を統一。
  - 受入基準: 参加者生成・解決・spawn が従来通り。
- [ ] **T6.2 Map 分離**
  - 内容: 現 `Mansion.tscn` から マップ部分（WorldEnvironment/照明/Room/家具/SpawnPoints/Stations）を独立
    `Map` scene へ。`Match` が選択マップを instance。spawn地点/ステーションをマーカー化。
  - 受入基準: マップを差し込んで本編が従来通り動く。複数マップの読み込みが可能。
- [ ] **T6.3 器導入＋改名**
  - 内容: `Systems`/`Services`/`UI` の器で整理。`main.gd`→`match.gd`、`Mansion.tscn`→`Match.tscn`（＋map scene）、
    `Main.tscn`→`WaitingRoom.tscn`。参照を全更新（RPCノードパス維持に注意）。
  - 受入基準: 全シーンが従来通り。online のノードパス一致が保たれる。
- **▶ フェーズ6 コミット**:「シーンを Match/Map 構成に再編、命名整理」

## フェーズ7：仕上げ

- [ ] **T7.1 match.gd 薄化の確認**
  - 内容: `match.gd` に構築・結線・tick発火のみが残ることを確認。ルール/状態/表示が残っていないか点検。
    定数を `game_tuning.gd`(Resource) へ外出し（任意）。
  - 受入基準: `match.gd` が薄いエントリになっている。全検証標準を通過。
- **▶ フェーズ7 コミット**:「match.gd をエントリに縮小」
- **★レビュー2（フェーズ4〜7）** — 後半をまとめてレビュー
