extends Node

# --- Enums for State Management ---
enum GameMode { WORD_COUNT_CHALLENGE, IDIOM_CHALLENGE }
enum RequestType { NONE, VALIDATE_WORD, GET_CHALLENGE, VALIDATE_SENTENCE }

# --- Nodes ---
@onready var dialogue_label = $VBoxContainer/DialogueLabel
@onready var input_box = $VBoxContainer/InputBox
@onready var timer_label = $VBoxContainer/TimerLabel
@onready var game_timer = $GameTimer
@onready var http_request = $HTTPRequest
@onready var next_turn_timer = $NextTurnTimer
@onready var keyboard = $VBoxContainer/Keyboard

# --- Constants ---
const SERVER_URL = "https://server-production-2c92.up.railway.app"
const WORD_COUNT_LIMIT = 10

# --- Game State ---
var game_mode = GameMode.WORD_COUNT_CHALLENGE
var active_request_type = RequestType.NONE
var current_word_count = 1
var current_challenge = ""

# --- Godot Functions ---
func _ready():
	# Connect signals
	game_timer.connect("timeout", _on_game_timer_timeout)
	http_request.connect("request_completed", _on_request_completed)
	next_turn_timer.connect("timeout", start_turn)

	# Connect all static keyboard buttons
	_connect_keyboard_signals()

	start_turn()

func _process(delta):
	if !game_timer.is_stopped():
		timer_label.text = "Time: %.2f" % game_timer.time_left

# --- Game Logic ---
func start_turn():
	input_box.text = ""
	set_keyboard_enabled(true)
	game_timer.start()

	if game_mode == GameMode.WORD_COUNT_CHALLENGE:
		if current_word_count == 1:
			dialogue_label.text = "Hi! あら失礼、つい英語をしゃべってしまいましたわ。あなた、英語はお出来になって？"
		else:
			dialogue_label.text = "よろしいですわ。では次は %d 語でお話あそばせ。" % current_word_count
		input_box.placeholder_text = "%d 語で入力して" % current_word_count
	
	elif game_mode == GameMode.IDIOM_CHALLENGE:
		_fetch_new_challenge()

func _fetch_new_challenge():
	dialogue_label.text = "新しいお題を取得中ですわ..."
	set_keyboard_enabled(false)
	active_request_type = RequestType.GET_CHALLENGE
	http_request.request(SERVER_URL + "/get-challenge", [], HTTPClient.METHOD_GET, "")

func _submit_answer():
	var text = input_box.text.strip_edges()
	if text.is_empty():
		return
	
	game_timer.stop()
	set_keyboard_enabled(false)
	dialogue_label.text = "通信中ですわ..."

	if game_mode == GameMode.WORD_COUNT_CHALLENGE:
		var words = text.split(" ", false)
		if words.size() != current_word_count:
			dialogue_label.text = "%d 語で話してくださる？と言ったはずですわ。" % current_word_count
			set_keyboard_enabled(true)
			return
		
		var word_to_validate = words[0].replace("'", "").to_lower()
		var headers = ["Content-Type: application/json"]
		var body = JSON.stringify({"word": word_to_validate})
		active_request_type = RequestType.VALIDATE_WORD
		http_request.request(SERVER_URL + "/validate", headers, HTTPClient.METHOD_POST, body)

	elif game_mode == GameMode.IDIOM_CHALLENGE:
		var headers = ["Content-Type: application/json"]
		var body = JSON.stringify({"challenge": current_challenge, "sentence": text})
		active_request_type = RequestType.VALIDATE_SENTENCE
		http_request.request(SERVER_URL + "/validate-sentence", headers, HTTPClient.METHOD_POST, body)

# --- Keyboard Management ---
func _connect_keyboard_signals():
	# Letter buttons
	for row in [keyboard.get_node("Row1"), keyboard.get_node("Row2"), keyboard.get_node("Row3")]:
		for button in row.get_children():
			button.pressed.connect(_on_letter_button_pressed.bind(button.text))

	# Action buttons
	keyboard.get_node("ActionButtons/ButtonSpace").pressed.connect(_on_space_pressed)
	keyboard.get_node("ActionButtons/ButtonApostrophe").pressed.connect(_on_apostrophe_pressed)
	keyboard.get_node("ActionButtons/ButtonDelete").pressed.connect(_on_delete_button_pressed)
	keyboard.get_node("ActionButtons/ButtonSubmit").pressed.connect(_submit_answer)

func set_keyboard_enabled(enabled):
	for button in keyboard.find_children("*", "Button"):
		button.disabled = !enabled

# --- Signal Callbacks ---
func _on_game_timer_timeout():
	dialogue_label.text = "GAME OVER..."
	set_keyboard_enabled(false)

func _on_request_completed(result, response_code, headers, body):
	var response_data = JSON.parse_string(body.get_string_from_utf8())
	var request_type = active_request_type
	active_request_type = RequestType.NONE

	if response_code != 200 or response_data == null:
		dialogue_label.text = "あら、サーバーとの通信に失敗したようですわ。"
		set_keyboard_enabled(true)
		return

	match request_type:
		RequestType.VALIDATE_WORD:
			if response_data.get("valid", false) == true:
				dialogue_label.text = "ふむ、「%s」と。なかなかやりますわね。" % input_box.text
				current_word_count += 1
				if current_word_count >= WORD_COUNT_LIMIT:
					game_mode = GameMode.IDIOM_CHALLENGE
					dialogue_label.text = "...素晴らしいですわ。単語数だけでは、あなたの英語力は測れませんわね。"
				next_turn_timer.start()
			else:
				dialogue_label.text = "あら、その最初の単語、存在しませんわ。出直していらっしゃい。"
				set_keyboard_enabled(true)

		RequestType.GET_CHALLENGE:
			current_challenge = response_data.get("challenge", "")
			if current_challenge == "":
				dialogue_label.text = "お題の取得に失敗しましたわ。もう一度試します。"
				next_turn_timer.start()
			else:
				dialogue_label.text = "では、このお題で文章を作ってごらんなさいな: \n\"%s\"" % current_challenge
				input_box.placeholder_text = "お題を使って文章を作成して"
				set_keyboard_enabled(true)
				game_timer.start()

		RequestType.VALIDATE_SENTENCE:
			if response_data.get("valid", false) == true:
				dialogue_label.text = "お見事ですわ！その表現、気に入りましたわ。"
				next_turn_timer.start() # Fetch next challenge
			else:
				dialogue_label.text = "ふむ...その文章では、わたくしは感心しませんわね。もう一度どうぞ。"
				set_keyboard_enabled(true)

# --- Button Callbacks ---
func _on_letter_button_pressed(letter):
	game_timer.start()
	input_box.text += letter

func _on_delete_button_pressed():
	game_timer.start()
	if !input_box.text.is_empty():
		input_box.text = input_box.text.substr(0, input_box.text.length() - 1)

func _on_space_pressed():
	game_timer.start()
	input_box.text += " "

func _on_apostrophe_pressed():
	game_timer.start()
	input_box.text += "'"
