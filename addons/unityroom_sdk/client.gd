class_name UnityroomClient extends Node

class Response:
	pass

class ScoreUploadResponse extends Response:
	var score_updated: bool
	func _init(score_updated: bool):
		self.score_updated = score_updated

class ErrorResponse extends Response:
	var code: int
	var type: String
	var message: String
	func _init(code: int, type: String, message: String):
		self.code = code
		self.type = type
		self.message = message

signal score_uploaded(success: bool, response: Response)

var _timeout: float = 600.0
var _max_retries: int = 2
var _hmac_key_bytes: PackedByteArray
var _http: HTTPRequest
var _is_busy := false

var timeout: float:
	get:
		return _timeout

var max_retries: int:
	get:
		return _max_retries

func _init(hmac_key: String, options: Dictionary = {}) -> void:
	if typeof(hmac_key) != TYPE_STRING or hmac_key.is_empty():
		push_error("HMAC key is not set.")
		return
	_hmac_key_bytes = Marshalls.base64_to_raw(hmac_key)
	_timeout = options.get("timeout", 600.0)
	_max_retries = options.get("max_retries", 2)
	_http = HTTPRequest.new()
	add_child(_http)

func _exit_tree() -> void:
	if _http != null:
		_http.cancel_request()

static var _crypto := Crypto.new()

func send_score(scoreboard_id: int, score: float) -> void:
	if _hmac_key_bytes.is_empty():
		push_error("UnityroomClient: HMAC key not initialized. send_score aborted.")
		score_uploaded.emit(false, ErrorResponse.new(0, "not_initialized", "Client not initialized with a valid HMAC key."))
		return

	if _is_busy:
		push_error("UnityroomClient: A request is already in progress.")
		score_uploaded.emit(false, ErrorResponse.new(0, "busy", "A request is already in progress. Wait for the previous request to complete."))
		return
	var path := "/gameplay_api/v1/scoreboards/%d/scores" % scoreboard_id
	var unix_time := str(int(Time.get_unix_time_from_system()))
	var score_text := str(score)

	var hmac_input := "POST\n%s\n%s\n%s" % [path, unix_time, score_text]
	var signature := _hmac(hmac_input, _hmac_key_bytes)

	var headers := PackedStringArray([
		"X-Unityroom-Signature: %s" % signature,
		"X-Unityroom-Timestamp: %s" % unix_time,
	])

	var body := "score=%s" % score_text
	var retry := _max_retries

	while true:
		var result := await _post(path, headers, body)

		if result is ErrorResponse:
			if result.type == "rate_limit_exceeded" and retry > 0:
				retry -= 1
				await get_tree().create_timer(5.0).timeout
				continue

			score_uploaded.emit(false, result)
			return

		score_uploaded.emit(true, result as ScoreUploadResponse)
		return

func _post(path: String, headers: PackedStringArray, body: String) -> Response:
	_is_busy = true

	var timed_out := false
	var on_timeout := func():
		timed_out = true
		_http.cancel_request()

	var timer: SceneTreeTimer = null
	if not Engine.is_editor_hint():
		timer = get_tree().create_timer(_timeout)
		timer.timeout.connect(on_timeout)

	var err := _http.request(_base_url() + path, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_is_busy = false
		if timer != null and timer.timeout.is_connected(on_timeout):
			timer.timeout.disconnect(on_timeout)
		return ErrorResponse.new(0, "request_failed", "Failed to start request, error code: %d" % err)

	var response: Array = await _http.request_completed
	_is_busy = false

	if timer != null and timer.timeout.is_connected(on_timeout):
		timer.timeout.disconnect(on_timeout)

	if timed_out:
		return ErrorResponse.new(0, "timeout", "Request timed out after %.1f seconds." % _timeout)

	var result: int = response[0]
	var status_code: int = response[1]
	var body_raw: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return ErrorResponse.new(0, "request_failed", "HTTP request failed, result code: %d" % result)

	var body_text := body_raw.get_string_from_utf8()
	if body_text.is_empty():
		return ErrorResponse.new(0, "empty_response", "Empty response from server.")

	var json := JSON.new()
	var parse_err := json.parse(body_text)
	if parse_err != OK:
		return ErrorResponse.new(0, "parse_error", "Failed to parse response JSON: %s" % json.get_error_message())

	var data: Dictionary = json.data
	if data.is_empty():
		return ErrorResponse.new(0, "empty_response", "Empty JSON data in response.")

	if status_code >= 400:
		return ErrorResponse.new(
			int(data.get("code", 0)),
			str(data.get("type", "")),
			str(data.get("message", "")),
		)

	return ScoreUploadResponse.new(data.get("saved", false))

static func _base_url() -> String:
	if OS.get_name() == "Web":
		var hostname := JavaScriptBridge.eval("window.location.hostname")
		return "https://" + hostname
	return "https://unityroom.com"

static func _hmac(data: String, key: PackedByteArray) -> String:
	var data_bytes := data.to_utf8_buffer()
	var hash := _crypto.hmac_digest(HashingContext.HASH_SHA256, key, data_bytes)
	return hash.hex_encode()
