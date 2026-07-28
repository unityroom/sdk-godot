# unityroom SDK for Godot

## 要件

- Godot 4.5 以上

## インストール

### Asset Library

Godot Asset Libraryへ登録していますが、現在審査中です。
公開後はエディタの「AssetLib」から `unityroom SDK` を検索してインストールできます。

### Releasesからダウンロード

GitHubのReleasesからアドオンを直接ダウンロードできます。

1. [Releases](https://github.com/unityroom/sdk-godot/releases)から最新のリリースを選択し、`unityroom_sdk.zip`をダウンロードします。
2. 展開したフォルダを導入先のGodotプロジェクトの`addons/`以下にコピーします。
3. エディタでプロジェクトを開きます。すでに開いている場合は、プロジェクトを再読み込みします。

```text
your-project/
└── addons/
    └── unityroom_sdk/
        ├── client.gd
        ├── plugin.cfg
        └── unityroom_sdk.gd
```

### セットアップ

1. [こちら](https://unityroom-help.notion.site/4fae458305a948818b90e50dcad6a3f3?pvs=4)の手順に従い、unityroom側でのセットアップを行う
2. APIキー画面からHMAC認証用キーを取得
    * ![img3](docs/img3.png)

## クイックスタート

```gdscript
# クライアントの生成
var client = UnityroomClient.new("your-base64-hmac-key")
add_child(client)

# シグナルの接続
client.score_uploaded.connect(_on_score_uploaded)

# スコアの送信
client.send_score(1, 100.0)  # スコアボードID, スコア

# コールバック関数
func _on_score_uploaded(success: bool, response: UnityroomClient.Response) -> void:
	if success:
        # 成功時の処理
		var res := response as UnityroomClient.ScoreUploadResponse
		print("スコア更新: " + res.score_updated)
	else:
        # 成功時の処理
		var err := response as UnityroomClient.ErrorResponse
		print("エラー: " + err.message)
```

## API

### UnityroomClient

#### `_init(hmac_key: String, options: Dictionary = {})`

| 引数       | 型           | 説明                                |
| ---------- | ------------ | ----------------------------------- |
| `hmac_key` | `String`     | unityroomの設定から取得したHMACキー |
| `options`  | `Dictionary` | オプション（下記参照）              |

optionsキー:

| キー          | 型      | デフォルト | 説明                               |
| ------------- | ------- | ---------- | ---------------------------------- |
| `timeout`     | `float` | `600.0`    | HTTPリクエストのタイムアウト（秒） |
| `max_retries` | `int`   | `2`        | レート制限時の最大再試行回数       |
| `request_interval` | `float` | `5.0` | スコア送信間の最小間隔（秒）。`0.0`で無効 |

#### `send_score(scoreboard_id: int, score: float) -> void`

スコアをunityroomのスコアボードに非同期で送信します。完了時に `score_uploaded` シグナルを発行します。

初回送信時にスコアボード情報を取得してキャッシュします。
送信中にさらにスコアが送られた場合はスコアボードの並び順に応じた良いスコアを残します。
破棄されたスコアは `throttled` エラーとして通知されます。

| 引数            | 型      | 説明                      |
| --------------- | ------- | ------------------------- |
| `scoreboard_id` | `int`   | unityroomのスコアボードID |
| `score`         | `float` | 送信するスコア値          |

#### `get_scoreboard(board_no: int) -> void`

スコアボードのメタ情報を非同期で取得します。完了時に `scoreboard_received` シグナルを発行します。
取得した情報はクライアント内にキャッシュされ、同じスコアボードへの2回目以降の呼び出しでは通信せずに返されます。

| 引数       | 型    | 説明                      |
| ---------- | ----- | ------------------------- |
| `board_no` | `int` | unityroomのスコアボード番号 |

#### シグナル

**`score_uploaded(success: bool, response: Response)`**

| 引数       | 型         | 説明                                         |
| ---------- | ---------- | -------------------------------------------- |
| `success`  | `bool`     | 成功時は `true`、失敗時は `false`            |
| `response` | `Response` | `ScoreUploadResponse` または `ErrorResponse` |

**`scoreboard_received(success: bool, response: Response)`**

| 引数       | 型         | 説明                                             |
| ---------- | ---------- | ------------------------------------------------ |
| `success`  | `bool`     | 成功時は `true`、失敗時は `false`                |
| `response` | `Response` | `ScoreboardResponse` または `ErrorResponse`      |

### レスポンス型

#### `UnityroomClient.ScoreUploadResponse`

| プロパティ      | 型     | 説明                            |
| --------------- | ------ | ------------------------------- |
| `score_updated` | `bool` | スコアが更新された場合は `true` |

#### `UnityroomClient.ScoreboardResponse`

| プロパティ    | 型       | 説明                         |
| ------------- | -------- | ---------------------------- |
| `board_no`    | `int`    | スコアボード番号             |
| `title`       | `String` | タイトル                     |
| `unit`        | `String` | スコアの単位                 |
| `order`       | `String` | 並び順                       |
| `update_rule` | `String` | スコア更新ルール             |
| `format`      | `String` | スコアの表示形式             |

#### `UnityroomClient.ErrorResponse`

| プロパティ | 型       | 説明             |
| ---------- | -------- | ---------------- |
| `code`     | `int`    | エラーコード     |
| `type`     | `String` | エラーの種類     |
| `message`  | `String` | エラーメッセージ |

## ライセンス

このライブラリは[MITライセンス](LICENSE)の下で公開されています。
