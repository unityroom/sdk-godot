extends Control

@onready var scoreboard_id_input := %ScoreboardIdInput as SpinBox
@onready var score_input := %ScoreInput as SpinBox
@onready var send_button := %SendButton as Button
@onready var result_label := %ResultLabel as RichTextLabel

var _client: UnityroomClient

@export var config: UnityroomConfig

func _ready() -> void:
	send_button.pressed.connect(_on_send_pressed)

func _on_send_pressed() -> void:
	send_button.disabled = true
	result_label.text = ""

	if config == null or config.hmac_key.is_empty():
		result_label.text = "[color=red]エラー\nHMAC Keyが設定されていません。[/color]"
		send_button.disabled = false
		return

	_client = UnityroomClient.new(config.hmac_key)
	_client.score_uploaded.connect(_on_score_uploaded)
	add_child(_client)

	var scoreboard_id := int(scoreboard_id_input.value)
	var score := score_input.value

	result_label.text = "[color=yellow]送信中...[/color]"
	_client.send_score(scoreboard_id, score)

func _on_score_uploaded(success: bool, response: UnityroomClient.Response) -> void:
	if not success:
		var err := response as UnityroomClient.ErrorResponse
		result_label.text = (
			"[color=red]エラー[/color]\n"
			+"コード: %d\n" % err.code
			+"種類: %s\n" % err.type
			+"メッセージ: %s" % err.message
		)
		_cleanup()
		return

	var res := response as UnityroomClient.ScoreUploadResponse
	var updated := "あり" if res.score_updated else "なし"
	result_label.text = (
		"[color=green]送信成功[/color]\n"
		+"スコア更新: %s" % updated
	)
	_cleanup()

func _cleanup() -> void:
	if is_instance_valid(_client):
		_client.queue_free()
	_client = null
	send_button.disabled = false
