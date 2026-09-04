# SPEC — main.gd 品質改修（実務レビューで通る形へ）

このドキュメントは**今回のリファクタの実行仕様**であり、「完了」と言える判定基準（受け入れ基準）を固定する。
日々の作業規約は [CLAUDE.md](CLAUDE.md)、現状の設計は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、ゲーム仕様は
[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)。本書は**あるべき姿**を書き、改修完了時に ARCHITECTURE.md へ反映する。

## 1. 目的（Objective）

`main.gd`（現 424行）は Composition Root でありながら、**神コンテキスト**と**状態の溜め込み**で実務品質に達していない。
これを次の3点で解消し、大規模開発のレビューで通る構造にする。

- **神コンテキスト/Service Locator の除去** — 各 System が `var _game: Node` を持ち `_game._x` / `_game.CONST` /
  `_game._other_system` で main 内部を触る構造をやめる。依存は**必要な分だけ**明示的に渡す。
- **状態を所有者へ** — main が抱える実行時状態を、それを使う所有者（Manager / System / コンポーネント）へ移す。
- **動的生成の .tscn 化** — コードで組み立てている見た目（交換台・リザルト）を .tscn 資産にし、**見た目は変えない**。

あわせて、可読性の底上げ（意味の通る単位・ヘルパ乱立の解消・コメントは要点のみ）を行う。

**動作維持は絶対条件ではない**（「動くと信じて進め、壊れたら直す」）。ただし**見た目の変更は不可**（.tscn 化で外観を変えない）。

## 2. コマンド（Commands）

Godot 本体: `G=/Applications/Godot.app/Contents/MacOS/Godot`

- パース/読み込み/null 検査（エディタスキャン）:
  ```
  "$G" --headless --editor --quit-after 300 2>&1 | grep -E "ERROR:|SCRIPT ERROR|Parse Error" | grep -vE "Case mismatch|open_internal"
  ```
- 本編起動時の実行時エラー検査:
  ```
  "$G" --headless "res://scenes/match/Match.tscn" --quit-after 250 2>&1 | grep -E "ERROR:|SCRIPT ERROR|Invalid|Nonexistent|null|Cannot|in base"
  ```
- 挙動（kill/能力/効果/交換）・オンライン同期は headless で検出不可 → **実機プレイテスト必須**、ネットは**2インスタンス**。

## 3. プロジェクト構造（Project Structure）

現状の層構成は維持。今回、状態の所有先を次のとおり確定する（`scripts/` 配下）。

| 所有者 | 移す状態 |
|---|---|
| `systems/game_state_manager.gd`（GameStateManager, Node・新規） | `time_left` / `is_ending` / `network_snapshot_time_left` |
| `entities/participants.gd`（Participants） | 参加者リスト / スポーン地点 / 参加者検索（by_name・nearest・is_computer・表示名） |
| `systems/combat_system.gd`（CombatSystem） | `change_killers`（チェンジ権の付与元） |
| `systems/exchange_system.gd`（ExchangeSystem） | 交換ホールドの進行（hold_time/target/card_index）・ロック・プレイヤー交換カード index |
| `systems/status_system.gd`（StatusSystem） | `was_stunned`（気絶明けバフ判定用） |
| `ui/player_controller.gd`（PlayerController） | ローカルの照準対象（kill/change/exchange）・チュートリアル overlay |

ゲーム調整定数（`KILL_DISTANCE` 等）は `config/game_config.gd`（GameConfig）へ集約し、System が main を介さず参照する。

`.tscn` 化する動的生成:

| 新規シーン | 由来（現在コードで生成している箇所） |
|---|---|
| `scenes/entities/ExchangeStation.tscn` | `ExchangeSystem.setup_stations()`（台座 + カードスロット Label3D + 当たり判定） |
| `scenes/ui/Results.tscn` | `GameFlow.show_results()`（結果表示のオーバーレイ一式） |

`GameHud.tscn` は既に資産化済み。@rpc 入口は NodePath 一致のため **main.gd に残す**（移動しない）。

## 4. コードスタイル（Code Style）

- **神コンテキスト禁止**。System は `main` 全体ではなく必要な依存だけを受け取る（`setup(...)` で明示注入）。`_game._x` で他層の内部を触らない。
- **状態は所有者が持つ**。横断的に必要な値は所有者の public フィールド/メソッド経由で読む。
- **ヘルパ乱立禁止**。1回しか使わない薄いラッパ・取り次ぎだけの関数を作らない。真に共有される accessor 以外は所有者に吸収する。
- **可読性優先**。コメントは「コードを読んでも分からない情報」がある時だけ1〜2行。自明・装飾コメント不可。
- **UI/オブジェクトは .tscn 資産**でエディタ調整。動的生成を .tscn 化する時は**見た目を変えない**。
- 型は用途で選ぶ（GDScript の `:=` 型推論が壊れる箇所は明示型を書く）。

## 5. テスト戦略（Testing Strategy）

- 各フェーズ完了ごとに **§2 のエディタスキャン + Match.tscn 起動**を通す（パース/null/実行時エラー 0）。
- headless で担保できない挙動（kill/能力/効果/交換/リザルト）は、区切りで**単体プレイテスト**。
- ネット関連（状態同期・@rpc）を触るフェーズは**2インスタンスのオンライン確認**をチェックポイントにする。
- **見た目**（HUD・交換台・リザルト）は .tscn 化の前後でスクリーンショット等で同一を確認。

## 6. 境界（Boundaries）

**Always（必ずやる）**
- 変更は小さく、フェーズ単位でコミット（メッセージは簡潔）。
- 構造・方針を変えたら docs（ARCHITECTURE.md / 必要なら CLAUDE.md）へ**現状のみ**反映（更新履歴・移行状況は書かない）。
- 各フェーズで §2 の検証を通してから次へ。

**Ask first（先に確認する）**
- 層の追加/削除やディレクトリ構成の変更など、合意済みの範囲を超える設計変更。
- 見た目を変えざるを得ない場合（原則不可のため）。

**Never（やらない）**
- リモートへ push（**すべてローカルで完結**）。
- `eos_credentials.local.cfg` のコミット。
- @rpc 関数を main.gd の外へ移す（NodePath 一致が壊れる）。
- .tscn 化に伴う**見た目の変更**。

## 7. 受け入れ基準（Definition of Done）

- [ ] どの System も `var _game: Node` を持たない。`_game._x` / `_game.CONST` / `_game._other_system` 参照が **0 件**（grep で確認）。
- [ ] §3 の状態が各所有者へ移り、main.gd の `var _*` 実行時状態フィールドが**構築・結線に必要なノード参照のみ**になっている。
- [ ] ゲーム調整定数が GameConfig に集約され、System が main 経由で定数を読まない。
- [ ] `ExchangeStation.tscn` / `Results.tscn` が存在し、対応する動的生成コードが削除され、**見た目が従来と同一**。
- [ ] main.gd が「構築・結線・tick 発火・@rpc 入口」に収まり、ヘルパ乱立が解消されている。
- [ ] §2 のエディタスキャン + Match.tscn 起動がエラー 0。
- [ ] 単体プレイテスト（kill/能力/効果/交換/リザルト）と 2インスタンスのオンライン確認が通る。
- [ ] ARCHITECTURE.md が改修後の現状を反映している。
