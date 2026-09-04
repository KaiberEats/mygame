# joker in the deck

人狼ゲームとババ抜きを混ぜた、3D対戦パーティゲーム。Godot 4.6 製。

死んでも復帰でき、役職（＝能力）がカード番号で流動的に決まることで、人狼の「死んだら暇」「役無し村人が暇」という問題を解消することを狙っている。

- **ゲーム内容・ルール・能力一覧** → [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- **技術構成・処理フロー・拡張ポイント** → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## 必要環境

| 項目 | バージョン / 備考 |
|---|---|
| Godot | **4.6**（Forward+ レンダラ） |
| Blender | 4.4.3 以上（`.blend` を編集/インポートする場合のみ。詳細は下記） |
| プラットフォーム | Windows / macOS / Linux（EOSネイティブライブラリは各OS用が `addons/` に同梱） |

## 起動方法

1. Godot 4.6 でプロジェクト（`project.godot`）を開く。
2. 実行（F5）。メインシーンは `res://scenes/Title.tscn`。
3. タイトル → `gamestart` → **シングルプレイ** で1人プレイ可能（オンライン設定なしで動く）。

## オンライン対戦（EOS）のセットアップ ※任意

オンライン機能は Epic Online Services (EOS) を使う。**認証情報ファイルが無くてもシングル/LAN対戦は動作する**（オンライン機能のみ無効になる）。

有効化するには、プロジェクト直下に `eos_credentials.local.cfg` を作成する（このファイルは秘密情報を含むため `.gitignore` 済み。**平文をコミットしないこと**）：

```ini
[product]
product_id="..."
sandbox_id="..."
deployment_id="..."

[client]
client_id="..."
client_secret="..."
```

値は Epic Developer Portal で取得する。

> 秘密情報の共有方法・本番運用の方針は**未決定（TODO）**。

## アセットについて（Blender / glTF）

事実として把握しておくべき点（運用方針は未決定・TODO）：

- Godot は `.blend` を直接読めず、インポート時に **各自のPCの Blender 本体**を起動して変換する（`.blend` を扱う人は Blender が必要）。`.glb`(glTF) は Blender なしで読める。
- 現状 `assets/blender/assets_1.blend` は Blender 4.4.3 で読めない（より新しい版で保存されている）ため、インポートを無効化してある（未使用アセット）。

## ディレクトリ構成（概要）

```
scenes/     … 各シーン(.tscn)。エントリは Title.tscn
scripts/    … GDScript（役割別。詳細は docs/ARCHITECTURE.md）
  main.gd / config/ network/ managers/ ui/ entities/ effects/ util/
assets/     … 画像・シェーダ・3Dモデル
addons/epic-online-services-godot/ … EOS用GDExtension（各OSバイナリ同梱）
docs/       … 本ドキュメント群
```

## ドキュメント

| ファイル | 内容 |
|---|---|
| [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) | コンセプト / ルール / 能力仕様 / 世界観 / 実装状況 / 演出要件 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | ディレクトリ構成 / Autoload / シーン構成 / 処理フロー / 状態モデル / ネットワーク / 主要ファイル |
