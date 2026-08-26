# TODO — main.gd 品質改修

計画: [plan.md](plan.md) / 仕様: [../SPEC.md](../SPEC.md)。各フェーズ末にスキャン+起動、コミット1つ。

## Phase 0 — 共有基盤
- [ ] 0a. 調整定数を GameConfig へ移設し参照を張り替え（main の `const` 群削除）
- [ ] 0b. `util/clock.gd`（`Clock.now()`）新設、`_now()` を置換
- [ ] 0c. `entities/participant.gd` 基底新設、Player/Computer を継承化、component getters/is_computer/display_name 移設、コンポーネント自己 attach、main 側アクセサ撤去
- [ ] 0d. Participants をレジストリ化（local_player/all/by_name/nearest/spawn 所有）、main 側撤去
- [ ] 0e. GameStateManager 結線（time_left/is_ending/network_snapshot_time_left 所有）
- [ ] 0f. NetGateway facade 定義（@rpc 入口の薄い公開）
- [ ] **C0**: スキャン + Match.tscn 起動（エラー0）

## Phase 1 — StatusSystem
- [ ] `_game` 撤去 / 依存注入 / `_was_stunned` 所有 / スキャン

## Phase 2 — CombatSystem
- [ ] `_game` 撤去 / 依存注入 / `_change_killers` 所有 / `_find_aimed_target` 整理 / スキャン

## Phase 3 — ExchangeSystem ＋ ExchangeStation.tscn
- [ ] `_game` 撤去 / 依存注入 / 交換ホールド・ロック・カード index 所有
- [ ] `setup_stations()` → `scenes/entities/ExchangeStation.tscn`（見た目不変）
- [ ] **C1**: 単体プレイテスト（kill / change / 交換）

## Phase 4 — ItemSystem
- [ ] `_game` 撤去 / 依存注入 / スキャン

## Phase 5 — AbilitySystem
- [ ] `_game` 撤去 / 依存注入（combat/status/item 明示）/ スキャン

## Phase 6 — GameFlow ＋ Results.tscn
- [ ] `_game` 撤去 / 依存注入
- [ ] `show_results()` → `scenes/ui/Results.tscn`（見た目不変）/ スキャン

## Phase 7 — NetSync ＋ GameStateCodec
- [ ] `_game`/`game` 撤去 / 依存注入
- [ ] **C2**: 2インスタンスのオンライン確認（状態同期・@rpc）

## Phase 8 — HudPresenter
- [ ] `_game` 撤去 / 依存注入 / スキャン

## Phase 9 — PlayerController
- [ ] `_game` 撤去 / 依存注入 / `_player_*_target`・`_tutorial_overlay` 所有 / スキャン

## Phase 10 — main 仕上げ＋ドキュメント
- [ ] main を構築・結線・tick・@rpc 入口だけに整理
- [ ] ARCHITECTURE.md（必要なら CLAUDE.md）を現状反映
- [ ] **C3**: スキャン + 起動 + 単体プレイテスト + 2インスタンス + DoD 全チェック
