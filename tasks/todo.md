# TODO — main.gd 品質改修

計画: [plan.md](plan.md) / 仕様: [../SPEC.md](../SPEC.md)。全フェーズ完了（headless スキャン+起動は各フェーズで通過）。

## Phase 0 — 共有基盤
- [x] 0a. 調整定数を GameConfig へ集約
- [x] 0b. `util/clock.gd`（`Clock.now()`）新設、`_now()` を置換
- [x] 0c. `entities/participant.gd` 基底新設・継承化・component getters/自己 attach、main 側アクセサ撤去
- [x] 0d. Participants をレジストリ化（all/local_player/spawn/by_name/nearest 所有）
- [x] 0e. GameStateManager 結線（time_left/is_ending/snapshot 所有）
- [x] 0f. NetGateway facade 定義

## Phase 1–9 — 各層の依存注入
- [x] 1. StatusSystem（was_stunned 所有）
- [x] 2. CombatSystem（change_killers 所有）
- [x] 3. ExchangeSystem ＋ ExchangeStation.tscn（hold 状態所有・見た目不変）
- [x] 4. ItemSystem
- [x] 5. AbilitySystem ＋ AbilityContext（refill/computer free-change を移設）
- [x] 6. GameFlow ＋ Results.tscn（見た目不変）
- [x] 7. NetSync ＋ GameStateCodec
- [x] 8. HudPresenter
- [x] 9. PlayerController（ローカル照準・tutorial overlay 所有）

## Phase 10 — main 仕上げ＋ドキュメント
- [x] main を構築・結線・tick・@rpc 入口に整理（424→312行、`_game` 全廃）
- [x] docs/ARCHITECTURE.md・CLAUDE.md を現状反映

## 残: 実機確認（headless 不可）
- [ ] 単体プレイテスト（kill / 能力 / 効果 / 交換 / リザルトの見た目・挙動）
- [ ] 2インスタンスのオンライン同期確認
