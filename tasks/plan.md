# PLAN — main.gd 品質改修

仕様は [SPEC.md](../SPEC.md)。本書は実装計画（依存グラフ・縦スライス・受け入れ/検証・チェックポイント）。
実装は**この計画のレビュー後**に着手する。コードは push せずローカル完結、フェーズ単位でコミット。

## 現状の結合面（grep 実測）

各 System が `var _game: Node` を持ち、main 内部を `_game.X` で触っている（総計 ~340 箇所）。到達先の内訳:

- **参加者アクセス**: `player`(47) / `_participants`(30) / `_participant_by_name`(15) / `_is_computer`(3) / `_participant_name`(4) / `_participant_spawn_positions`(3) / `_find_aimed_target`(5)
- **コンポーネント**: `_vision`(22) / `_status`(19) / `_item`(16) / `_cooldown`(5)
- **他 System**: `_status_system`(20) / `_item_system`(10) / `_combat`(10) / `_ability`(2) / `_net`(6) / `_exchange`(4)
- **表示/通知/ネット入口**: `game_hud`(29) / `notify_participant`(6) / `_show_change_preview_for_participant`(3) / `respawn_remote` / `broadcast_game_finished` / `_launch_missile` ほか
- **状態**: `_change_killers`(15) / 交換ホールド系(hold_time/target/card_index/locked/exchange_card_index) / `_game_ending`(6) / `_time_left`(4) / `_player_*_target`(15) / `_tutorial_overlay`(9) / `_was_stunned`(2)
- **定数/時刻**: `_now`(15) / `KILL_DISTANCE`(8) / `STUN_SECONDS`(4) / `EXCHANGE_CARD_COUNT`(4) / その他定数
- **サービス**: `deck`(5) / `pause_menu`(6) / `settings_menu`(6)

## 解消アプローチ（結合を下向き依存に置き換える）

| 結合 | 置き換え先 |
|---|---|
| 定数 `KILL_DISTANCE` 等 | **GameConfig（autoload）へ集約**。System は `GameConfig.X` を直接参照（autoload は設定であり神コンテキストではない） |
| `_now()` | **`util/clock.gd` の `Clock.now()`（static）** に集約 |
| `_status/_cooldown/_item/_vision`, `_is_computer`, `_participant_name` | **`entities/participant.gd`（`class_name Participant extends CharacterBody3D`）基底**を新設。Player/Computer が継承し、型付きゲッター（`status()`/`cooldown()`/`item()`/`vision()`）と `is_computer()`/`display_name()` を提供。コンポーネントは基底の `_ready` で自己 attach（main の `_attach_components` を廃止） |
| `player`/`_participants`/`by_name`/`nearest`/spawn | **Participants を参加者レジストリに**。`local_player` / `all` / `by_name()` / `nearest()` / spawn を所有。System は Participants を注入で受け取る |
| `_time_left`/`_game_ending`/`network_snapshot_time_left` | **GameStateManager**（作成済み）を結線して所有 |
| `_change_killers` | **CombatSystem** が所有 |
| 交換ホールド系・交換カード index・ロック | **ExchangeSystem** が所有 |
| `_was_stunned` | **StatusSystem** が所有 |
| `_player_*_target`・`_tutorial_overlay` | **PlayerController** が所有 |
| `game_hud`・`notify_*`・`@rpc` 入口 | @rpc は main に残す。System からの通知/ネット送信は **NetGateway（main が公開する狭い facade）を注入**。main 全体は渡さない |
| 他 System 参照（combat/status/item/… 間） | `setup(...)` で**必要な System 参照だけ**を明示注入 |

> 注: DI リファクタは横断的なので Phase 0 の共有基盤（Config/Clock/Participant/Participants/GameStateManager/NetGateway）が先に要る。
> これらが揃ってから、各 System を1つずつ縦に移行（＝各 System が `_game` 無しで単体で成立する状態にして検証）する。

## 依存グラフ（下ほど土台）

```
GameConfig(定数)  Clock(now)  Participant(基底/component getters)
        \            |            /
         Participants(レジストリ)      GameStateManager(進行状態)
                       \                 /
                    NetGateway(main の @rpc facade)
                       /   |   |   |   \
   StatusSystem  CombatSystem  ExchangeSystem  ItemSystem  AbilitySystem
              \        |            |            /            /
               GameFlow   NetSync / GameStateCodec   HudPresenter
                                   \
                               PlayerController
```

## フェーズ（縦スライス）

各フェーズ末に **§2 エディタスキャン + Match.tscn 起動（エラー0）**。コミット1つ。

### Phase 0 — 共有基盤
- 0a. 調整定数を GameConfig へ移し、参照を `GameConfig.X` に張り替え（main の `const` 群を削除）。
- 0b. `util/clock.gd`（`Clock.now()`）新設、`_now()` を置換。
- 0c. `entities/participant.gd` 基底新設。Player/Computer を `extends Participant` に。component getters・`is_computer()`・`display_name()` を移設、コンポーネント自己 attach。main の `_attach_components`/`_status`/`_cooldown`/`_item`/`_vision`/`_is_computer`/`_participant_name` を撤去。
- 0d. Participants をレジストリ化（`local_player`/`all`/`by_name()`/`nearest()`/spawn 所有）。main の `_participants`/`_participant_by_name`/`_find_nearest_participant`/`_participant_spawn_positions` を撤去。
- 0e. GameStateManager を結線（time_left/is_ending/network_snapshot_time_left 所有）。main と `_process` を張り替え。
- 0f. NetGateway facade を定義（main の @rpc 入口を薄く公開）。まだ System は注入せず、main 内で利用のみ。
- **チェックポイント C0**: スキャン + 起動。

### Phase 1 — StatusSystem
`_game` 撤去、必要依存を注入（Participants/Clock/GameConfig/item_system/NetGateway）。`_was_stunned` を所有。

### Phase 2 — CombatSystem
`_game` 撤去、依存注入。`_change_killers` を所有。`_find_aimed_target` を targeting 直呼びへ。

### Phase 3 — ExchangeSystem ＋ ExchangeStation.tscn
`_game` 撤去、依存注入。交換ホールド/ロック/交換カード index を所有。`setup_stations()` の動的生成を **`scenes/entities/ExchangeStation.tscn`** に置換（**見た目不変**）。
- **チェックポイント C1**: 単体プレイテスト（kill / change / 交換の見た目・挙動）。

### Phase 4 — ItemSystem
`_game` 撤去、依存注入。

### Phase 5 — AbilitySystem
`_game` 撤去、依存注入（combat/status/item を明示）。

### Phase 6 — GameFlow ＋ Results.tscn
`_game` 撤去、依存注入。`show_results()` の動的生成を **`scenes/ui/Results.tscn`** に置換（**見た目不変**）。

### Phase 7 — NetSync ＋ GameStateCodec
`_game`/`game` 撤去、依存注入（Participants/各 System/GameStateManager）。
- **チェックポイント C2**: 2インスタンスのオンライン確認（状態同期・@rpc）。

### Phase 8 — HudPresenter
`_game` 撤去、依存注入（game_hud/GameStateManager/StatusSystem/Participants/CombatSystem/GameConfig）。

### Phase 9 — PlayerController
`_game` 撤去、依存注入。`_player_kill/change/exchange_target`・`_tutorial_overlay` を所有。

### Phase 10 — main 仕上げ＋ドキュメント
main を「構築・結線・tick 発火・@rpc 入口」だけに整理（残ヘルパ吸収、`_ready` 結線の可読化）。ARCHITECTURE.md / 必要なら CLAUDE.md を現状反映。
- **チェックポイント C3**: スキャン + 起動 + 単体プレイテスト + 2インスタンス + SPEC §7 の DoD 全チェック。

## 検証（各フェーズ共通）
- スキャン: `"$G" --headless --editor --quit-after 300` のエラー0。
- 起動: `"$G" --headless "res://scenes/match/Match.tscn" --quit-after 250` のエラー0。
- DoD の grep: `grep -rn "_game\.\|[^_]game\." scripts` が最終的に @rpc 経路以外 0。
- 挙動/見た目/オンラインは各チェックポイントで実機確認。

## リスクと方針
- Player/Computer の `extends` 変更（Phase 0c）は影響が広い → 0c 直後に必ず起動確認。
- .tscn 化は**見た目不変**が条件 → 変換前後でスクリーンショット比較。
- NetGateway の設計が甘いと結合が残る → 「main への上向き依存はネット入口のみ」に限定し、それ以外は注入で解決。
- 動作維持は絶対条件ではない（壊れたらその場で修正）。ただし見た目は変えない。
