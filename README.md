# unityroom SDK for Godot

## 要件

- Godot 4.5 以上

## インストール

### Asset Library

TODO:

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

#### `send_score(scoreboard_id: int, score: float) -> void`

スコアをunityroomのスコアボードに非同期で送信します。完了時に `score_uploaded` シグナルを発行します。

| 引数            | 型      | 説明                      |
| --------------- | ------- | ------------------------- |
| `scoreboard_id` | `int`   | unityroomのスコアボードID |
| `score`         | `float` | 送信するスコア値          |

#### シグナル

**`score_uploaded(success: bool, response: Response)`**

| 引数       | 型         | 説明                                         |
| ---------- | ---------- | -------------------------------------------- |
| `success`  | `bool`     | 成功時は `true`、失敗時は `false`            |
| `response` | `Response` | `ScoreUploadResponse` または `ErrorResponse` |

### レスポンス型

#### `UnityroomClient.ScoreUploadResponse`

| プロパティ      | 型     | 説明                            |
| --------------- | ------ | ------------------------------- |
| `score_updated` | `bool` | スコアが更新された場合は `true` |

#### `UnityroomClient.ErrorResponse`

| プロパティ | 型       | 説明             |
| ---------- | -------- | ---------------- |
| `code`     | `int`    | エラーコード     |
| `type`     | `String` | エラーの種類     |
| `message`  | `String` | エラーメッセージ |

## ライセンス

このライブラリは[MITライセンス](LICENSE)の下で公開されています。
