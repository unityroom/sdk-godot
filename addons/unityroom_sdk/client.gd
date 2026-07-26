class_name UnityroomClient extends Node

class Response:
	pass

class ScoreUploadResponse extends Response:
	var score_updated: bool
	func _init(score_updated: bool):
		self.score_updated = score_updated

class ScoreboardResponse extends Response:
	var board_no: int
	var title: String
	var unit: String
	var order: String
	var update_rule: String
	var format: String
	func _init(scoreboard: Dictionary):
		board_no = int(scoreboard.get("board_no", 0))
		title = str(scoreboard.get("title", ""))
		unit = str(scoreboard.get("unit", ""))
		order = str(scoreboard.get("order", ""))
		update_rule = str(scoreboard.get("update_rule", ""))
		format = str(scoreboard.get("format", ""))

class ErrorResponse extends Response:
	var code: int
	var type: String
	var message: String
	func _init(code: int, type: String, message: String):
		self.code = code
		self.type = type
		self.message = message

signal score_uploaded(success: bool, response: Response)
signal scoreboard_received(success: bool, response: Response)

var _timeout: float = 600.0
var _max_retries: int = 2
var _request_interval: float = 5.0
var _hmac_key_bytes: PackedByteArray
var _http: HTTPRequest
var _is_busy := false
var _last_score_request_at_msec := -1
var _scoreboard_cache: Dictionary = {}
var _pending_scores: Array[Dictionary] = []
var _active_scoreboard_id := 0

var timeout: float:
	get:
		return _timeout

var max_retries: int:
	get:
		return _max_retries

var request_interval: float:
	get:
		return _request_interval

func _init(hmac_key: String, options: Dictionary = {}) -> void:
	if typeof(hmac_key) != TYPE_STRING or hmac_key.is_empty():
		push_error("[unityroom] HMAC key is not set.")
		return
	_hmac_key_bytes = Marshalls.base64_to_raw(hmac_key)
	if _hmac_key_bytes.is_empty():
		push_error("[unityroom] HMAC key is not valid base64.")
		return
	_timeout = options.get("timeout", 600.0)
	_max_retries = options.get("max_retries", 2)
	_request_interval = maxf(options.get("request_interval", 5.0), 0.0)
	_http = HTTPRequest.new()
	add_child(_http)

func _exit_tree() -> void:
	if _http != null:
		_http.cancel_request()

static var _crypto := Crypto.new()

func send_score(scoreboard_id: int, score: float) -> void:
	if _hmac_key_bytes.is_empty():
		push_error("[unityroom] HMAC key not initialized. send_score aborted.")
		score_uploaded.emit(false, ErrorResponse.new(0, "not_initialized", "Client not initialized with a valid HMAC key."))
		return

	if _is_busy:
		_enqueue_score(scoreboard_id, score)
		return
	_is_busy = true
	_process_score_queue({"scoreboard_id": scoreboard_id, "score": score})

func _enqueue_score(scoreboard_id: int, score: float) -> void:
	var candidate := {"scoreboard_id": scoreboard_id, "score": score}
	if scoreboard_id != _active_scoreboard_id:
		score_uploaded.emit(false, ErrorResponse.new(0, "busy", "A score for another scoreboard is already being processed."))
		return
	if _pending_scores.is_empty():
		_pending_scores.append(candidate)
		return

	var pending := _pending_scores[0]
	if not _scoreboard_cache.has(scoreboard_id):
		# The order is not known until the first metadata request completes.
		# Candidates are collapsed immediately after it is cached.
		_pending_scores.append(candidate)
		return

	_keep_better_pending_score(candidate, _scoreboard_cache[scoreboard_id].order)

func _keep_better_pending_score(candidate: Dictionary, order: String) -> void:
	var pending := _pending_scores[0]
	var candidate_is_better := (
		float(candidate.score) < float(pending.score)
		if order == "asc"
		else float(candidate.score) > float(pending.score)
	)
	var throttled := ErrorResponse.new(0, "throttled", "The score was dropped because the pending request queue is full.")

	if candidate_is_better:
		_pending_scores[0] = candidate
		score_uploaded.emit(false, throttled)
	else:
		score_uploaded.emit(false, throttled)

func _collapse_pending_scores(scoreboard_id: int) -> void:
	if _pending_scores.size() <= 1:
		return

	var candidates := _pending_scores.duplicate()
	_pending_scores.clear()
	_pending_scores.append(candidates.pop_front())
	var order: String = _scoreboard_cache[scoreboard_id].order
	for candidate in candidates:
		_keep_better_pending_score(candidate, order)

func _process_score_queue(current: Dictionary) -> void:
	while not current.is_empty():
		var scoreboard_id := int(current.scoreboard_id)
		_active_scoreboard_id = scoreboard_id
		if not _scoreboard_cache.has(scoreboard_id):
			var scoreboard_result := await _fetch_scoreboard(scoreboard_id)
			if scoreboard_result is ErrorResponse:
				score_uploaded.emit(false, scoreboard_result)
				current = _take_pending_score()
				continue
			_scoreboard_cache[scoreboard_id] = scoreboard_result
			_collapse_pending_scores(scoreboard_id)

		var result := await _post_score(scoreboard_id, float(current.score))
		if result is ErrorResponse:
			score_uploaded.emit(false, result)
		else:
			score_uploaded.emit(true, result as ScoreUploadResponse)
		current = _take_pending_score()

	_is_busy = false
	_active_scoreboard_id = 0

func _take_pending_score() -> Dictionary:
	if _pending_scores.is_empty():
		return {}
	return _pending_scores.pop_front()

func _post_score(scoreboard_id: int, score: float) -> Response:
	var path := "/gameplay_api/v1/scoreboards/%d/scores" % scoreboard_id
	var score_text := str(score)
	var retry := _max_retries

	while true:
		await _wait_for_score_slot()
		var unix_time := str(int(Time.get_unix_time_from_system()))
		var hmac_input := "POST\n%s\n%s\n%s" % [path, unix_time, score_text]
		var signature := _hmac(hmac_input, _hmac_key_bytes)
		var headers := PackedStringArray([
			"X-Unityroom-Signature: %s" % signature,
			"X-Unityroom-Timestamp: %s" % unix_time,
		])
		_last_score_request_at_msec = Time.get_ticks_msec()
		var result := await _request(path, headers, HTTPClient.METHOD_POST, "score=%s" % score_text)
		if result is ErrorResponse and result.type == "rate_limit_exceeded" and retry > 0:
			retry -= 1
			continue
		return result
	return ErrorResponse.new(0, "request_failed", "Score request ended unexpectedly.")

func get_scoreboard(board_no: int) -> void:
	if _hmac_key_bytes.is_empty():
		push_error("[unityroom] HMAC key not initialized. get_scoreboard aborted.")
		scoreboard_received.emit(false, ErrorResponse.new(0, "not_initialized", "Client not initialized with a valid HMAC key."))
		return

	if _scoreboard_cache.has(board_no):
		scoreboard_received.emit(true, _scoreboard_cache[board_no] as ScoreboardResponse)
		return

	if _is_busy:
		push_error("[unityroom] A request is already in progress.")
		scoreboard_received.emit(false, ErrorResponse.new(0, "busy", "A request is already in progress. Wait for the previous request to complete."))
		return
	_is_busy = true
	var result := await _fetch_scoreboard(board_no)
	_is_busy = false
	if result is ErrorResponse:
		scoreboard_received.emit(false, result)
		return
	_scoreboard_cache[board_no] = result
	scoreboard_received.emit(true, result as ScoreboardResponse)

func _fetch_scoreboard(board_no: int) -> Response:
	if _scoreboard_cache.has(board_no):
		return _scoreboard_cache[board_no]

	var path := "/gameplay_api/v1/scoreboards/%d" % board_no
	var unix_time := str(int(Time.get_unix_time_from_system()))
	var hmac_input := "GET\n%s\n%s" % [path, unix_time]
	var signature := _hmac(hmac_input, _hmac_key_bytes)
	var headers := PackedStringArray([
		"X-Unityroom-Signature: %s" % signature,
		"X-Unityroom-Timestamp: %s" % unix_time,
	])
	var retry := _max_retries

	while true:
		var result := await _request(path, headers, HTTPClient.METHOD_GET)
		if result is ErrorResponse and result.type == "rate_limit_exceeded" and retry > 0:
			retry -= 1
			await get_tree().create_timer(5.0).timeout
			continue
		return result
	return ErrorResponse.new(0, "request_failed", "Scoreboard request ended unexpectedly.")

func _request(path: String, headers: PackedStringArray, method: HTTPClient.Method, body := "") -> Response:
	var timed_out := false
	var on_timeout := func():
		timed_out = true
		_http.cancel_request()

	var timer: SceneTreeTimer = null
	if not Engine.is_editor_hint():
		timer = get_tree().create_timer(_timeout)
		timer.timeout.connect(on_timeout)

	var err := _http.request(_base_url() + path, headers, method, body)
	if err != OK:
		if timer != null and timer.timeout.is_connected(on_timeout):
			timer.timeout.disconnect(on_timeout)
		return ErrorResponse.new(0, "request_failed", "Failed to start request, error code: %d" % err)

	var response: Array = await _http.request_completed

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

	if method == HTTPClient.METHOD_GET:
		var scoreboard: Variant = data.get("scoreboard")
		if typeof(scoreboard) != TYPE_DICTIONARY:
			return ErrorResponse.new(0, "invalid_response", "Response does not contain scoreboard data.")
		return ScoreboardResponse.new(scoreboard)

	return ScoreUploadResponse.new(data.get("saved", false))

func _wait_for_score_slot() -> void:
	if _last_score_request_at_msec < 0 or _request_interval <= 0.0:
		return

	var elapsed := (Time.get_ticks_msec() - _last_score_request_at_msec) / 1000.0
	var wait_time := _request_interval - elapsed
	if wait_time > 0.0:
		await get_tree().create_timer(wait_time).timeout

static func _base_url() -> String:
	if OS.get_name() == "Web":
		var hostname := JavaScriptBridge.eval("window.location.hostname")
		return "https://" + hostname
	return "https://unityroom.com"

static func _hmac(data: String, key: PackedByteArray) -> String:
	var data_bytes := data.to_utf8_buffer()
	var hash := _crypto.hmac_digest(HashingContext.HASH_SHA256, key, data_bytes)
	return hash.hex_encode()
