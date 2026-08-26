# CLAUDE.md

このリポジトリで作業する際の指針。詳細設計は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、ゲーム仕様は
[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)、ドキュメント一覧は [docs/README.md](docs/README.md)。

## プロジェクト
- **joker in the deck** … 人狼×ババ抜きの3D対戦ゲーム。Godot 4.6 / GDScript。
- エントリ: `Match.tscn`（本編）の `scripts/main.gd`（Composition Root）。メニュー入口は `Title.tscn`。

## アーキテクチャ（要点）
`main.gd` は薄いエントリで、各層に委譲する。
- 状態 = 参加者ノードのコンポーネント（`entities/components/`: status/cooldown/item/vision）
- ルール = System群（`systems/`: combat / ability / item / exchange / status / game_flow）
- 能力 = Strategy（`abilities/ability_01..13` ＋ `ability_context`）
- ネット = `net/game_state_codec`（直列化）＋ `net/net_sync`（検証/peer）。**@rpc 入口は NodePath 一致のため `main.gd` に残す**
- 表示 = `ui/hud_presenter`（`game_hud` は描画専用）
- 入力/メニュー = `ui/player_controller`
- 参加者管理 = `entities/participants`

## 作業の規約
- **設計方針・機能追加時の規約は docs/ARCHITECTURE.md に従う**（状態は持ち主に / 合成 / 型は用途で選ぶ / 依存は下向き 等）。
- 振る舞いを変えるリファクタは避け、変更は小さく。コミットメッセージは簡潔に（例「◯◯を△△に分離」）。
- 新しい System/コンポーネントは `main.gd` の `_ready` で構築・`setup(self)` で結線する。

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
