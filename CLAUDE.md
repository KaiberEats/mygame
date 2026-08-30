# CLAUDE.md

このリポジトリで作業する際の指針。詳細設計は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、ゲーム仕様は
[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)、ドキュメント一覧は [docs/README.md](docs/README.md)。

## プロジェクト
- **joker in the deck** … 人狼×ババ抜きの3D対戦ゲーム。Godot 4.6 / GDScript。
- エントリ: `Match.tscn`（本編）の `scripts/main.gd`（Composition Root）。メニュー入口は `Title.tscn`。

## アーキテクチャ（要点）
`main.gd` は薄いエントリ。各 System を構築し、必要な依存だけを注入して結線する（神コンテキストを渡さない）。
- 状態 = 参加者ノードのコンポーネント（`entities/components/`: status/cooldown/item/vision）。参加者は共通基底 `entities/participant`
- 進行状態 = `systems/game_state_manager`（残り時間・終了フラグ）、参加者一覧 = `entities/participants`（レジストリ）
- ルール = System群（`systems/`: combat / ability / item / exchange / status / game_flow）
- 能力 = Strategy（`abilities/ability_01..13` ＋ `ability_context`）
- ネット = `net/game_state_codec`（直列化）＋ `net/net_sync`（検証/peer）。**@rpc 入口は NodePath 一致のため `main.gd` に残す**。System からの送信は `net/net_gateway` 経由
- 表示 = `ui/hud_presenter`（`game_hud` は描画専用）
- 入力/メニュー = `ui/player_controller`（ローカル照準も保持）
- 定数 = `config/game_config`（autoload）に集約、時刻は `util/clock`

## 作業の規約
- **設計方針・機能追加時の規約は docs/ARCHITECTURE.md に従う**（状態は持ち主に / 合成 / 型は用途で選ぶ / 依存は下向き 等）。
- 変更は小さく。コミットメッセージは簡潔に（例「◯◯を△△に分離」）。
- 新しい System/コンポーネントは `main.gd` の `_ready` で構築し、**必要な依存だけを明示的に渡して**結線する（`main` 全体＝神コンテキストを渡さない）。状態はそれを使う所有者が持つ。
- **可読性優先**。コメントは「コードを読んでも分からない情報」がある時だけ1〜2行で簡潔に（自明なコメント・乱発は不可）。
- UI・オブジェクトは**コード動的生成でなく .tscn 資産**にしてエディタで調整する（既存の動的生成を .tscn 化する際は**見た目を変えない**）。

## 検証
headless では**読み込み・パース・null しか検出できない**。挙動（kill/能力/効果/オンライン同期）は**実機プレイテスト必須**。
```
G=/Applications/Godot.app/Contents/MacOS/Godot
"$G" --headless --editor --quit-after 300 2>&1 | grep -E "ERROR:|SCRIPT ERROR|Parse Error" | grep -vE "Case mismatch|open_internal"
"$G" --headless "res://scenes/match/Match.tscn" --quit-after 250 2>&1 | grep -E "ERROR:|SCRIPT ERROR|Invalid|Nonexistent|null|Cannot|in base"
```
- ネット関連の変更は **2インスタンスでのオンライン確認**が必要（headless不可）。

## ドキュメント運用
- **構造・方針を変えたら docs を更新する**（特に `docs/ARCHITECTURE.md` のディレクトリ/型/シーン構成）。
- ドキュメントの一覧・役割は `docs/README.md` で管理する。
