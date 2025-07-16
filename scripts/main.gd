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
@onready var audio_player = $AudioStreamPlayer
@onready var voice_delay_timer = $VoiceDelayTimer
@onready var countdown_audio_player = $CountdownAudioPlayer

# --- Constants ---
const SERVER_URL = "https://server-production-2c92.up.railway.app"
const WORD_COUNT_LIMIT = 7

# --- Voice Resources ---
var voice_resources = {
	"success": [
		preload("res://assets/sounds/voice_あら少しは話せるのね_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_いい発音しているじゃない_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_すこしはやるじゃないの_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_やるじゃない_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_Great_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_すごーい_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_すごいすごーい_シャルロッテ.mp3")
	],
	"failure": [
		preload("res://assets/sounds/voice_あらえっ_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_えそれは_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_えっええーーー_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_ふふふあら英語なのかしら_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_まったく_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_信じられないわ_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_庶民ねぇまったく_シャルロッテ.mp3")
	],
	"misc": [
		preload("res://assets/sounds/voice_かわったイントネーションね_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_上流階級ではこう言うのよ_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_下町って感じね_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_いい気にならないのっ_シャルロッテ.mp3"),
		preload("res://assets/sounds/voice_はぁなんでこんなことを_シャルロッテ.mp3")
	]
}

var countdown_sounds = {
	3: preload("res://assets/countDown/voice_3_シャルロッテ.mp3"),
	2: preload("res://assets/countDown/voice_2_シャルロッテ.mp3"),
	1: preload("res://assets/countDown/voice_1_シャルロッテ.mp3"),
	0: preload("res://assets/countDown/voice_0_シャルロッテ.mp3")
}
var game_over_sound = preload("res://assets/countDown/voice_ゲームオーバよ_シャルロッテ.mp3")

# --- Game State ---
var game_mode = GameMode.WORD_COUNT_CHALLENGE
var active_request_type = RequestType.NONE
var current_word_count = 1
var current_challenge = ""
var pending_voice_type = ""  # "success" or "failure"
var last_countdown_played = -1  # Track which countdown was last played
var stored_next_prompt = ""  # Store the next prompt from server
var required_word = ""  # Store the required word from the prompt

# --- Godot Functions ---
func _ready():
	# Connect signals
	game_timer.connect("timeout", _on_game_timer_timeout)
	http_request.connect("request_completed", _on_request_completed)
	next_turn_timer.connect("timeout", start_turn)
	voice_delay_timer.connect("timeout", _on_voice_delay_timeout)

	# Connect all static keyboard buttons
	_connect_keyboard_signals()
	
	# Debug: Check if input_box is accessible
	print("InputBox found: ", input_box != null)
	if input_box:
		print("InputBox editable: ", input_box.editable)
		# Connect input events
		input_box.text_changed.connect(_on_input_text_changed)
		input_box.text_submitted.connect(_on_input_text_submitted)

	start_turn()

func _process(delta):
	if !game_timer.is_stopped():
		var time_left = game_timer.time_left
		timer_label.text = "Time: %.2f" % time_left
		
		# Play countdown sounds
		var countdown_num = int(time_left)
		# Play "3" early (between 4-4.5 seconds)
		if time_left <= 4.5 and time_left > 4.0 and last_countdown_played != 3:
			countdown_audio_player.stream = countdown_sounds[3]
			countdown_audio_player.play()
			last_countdown_played = 3
		elif countdown_num <= 2 and countdown_num >= 0 and countdown_num != last_countdown_played:
			if countdown_sounds.has(countdown_num):
				countdown_audio_player.stream = countdown_sounds[countdown_num]
				countdown_audio_player.play()
				last_countdown_played = countdown_num

# --- Game Logic ---
func start_turn():
	input_box.text = ""
	set_keyboard_enabled(true)
	input_box.grab_focus()  # Ensure input box has focus
	last_countdown_played = -1  # Reset countdown tracker
	game_timer.start()

	if game_mode == GameMode.WORD_COUNT_CHALLENGE:
		if current_word_count == 1:
			dialogue_label.text = "Hi! あら失礼、つい英語をしゃべってしまいましたわ。あなた、英語はお出来になって？まずは1語でお答えなさい。"
		else:
			# Use the stored next prompt if available
			if stored_next_prompt != "":
				dialogue_label.text = stored_next_prompt
				stored_next_prompt = ""
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
	
	print("Submitting answer: ", text)
	game_timer.stop()
	set_keyboard_enabled(false)
	dialogue_label.text = "通信中ですわ..."

	if game_mode == GameMode.WORD_COUNT_CHALLENGE:
		var headers = ["Content-Type: application/json"]
		var body_data = {
			"sentence": text,
			"word_count": current_word_count
		}
		# Add required word if there is one
		if required_word != "":
			body_data["required_word"] = required_word
		var body = JSON.stringify(body_data)
		print("Sending validation request with body: ", body)
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
	input_box.editable = enabled
	if enabled:
		input_box.grab_focus()  # Grab focus when enabling keyboard
	for button in keyboard.find_children("*", "Button"):
		button.disabled = !enabled

# --- Signal Callbacks ---
func _on_game_timer_timeout():
	dialogue_label.text = "GAME OVER..."
	set_keyboard_enabled(false)
	# Play game over sound
	audio_player.stream = game_over_sound
	audio_player.play()
	
	# Wait for sound to finish then transition to result
	await audio_player.finished
	
	# Save score and transition to result screen
	GameManager.final_score = current_word_count - 1  # -1 because we increment before checking
	get_tree().change_scene_to_file("res://scenes/result.tscn")

func _on_request_completed(result, response_code, headers, body):
	var response_string = body.get_string_from_utf8()
	print("Server response: ", response_string)  # Debug log
	var response_data = JSON.parse_string(response_string)
	var request_type = active_request_type
	active_request_type = RequestType.NONE

	if response_code != 200 or response_data == null:
		dialogue_label.text = "あら、サーバーとの通信に失敗したようですわ。"
		print("Error - Response code: ", response_code, ", Data: ", response_data)
		set_keyboard_enabled(true)
		return

	match request_type:
		RequestType.VALIDATE_WORD:
			print("Validation response data: ", response_data)  # Debug
			var comment = response_data.get("comment", "")
			print("Comment from server: '", comment, "'")  # Debug
			
			if response_data.get("valid", false) == true:
				if comment != "":
					dialogue_label.text = comment
					print("Setting dialogue to comment: ", comment)
				else:
					dialogue_label.text = "ふむ、なかなかやりますわね。"
					print("Using default success message")
				pending_voice_type = "success"
				voice_delay_timer.start()
				
				# Store the next prompt for the next turn
				var next_prompt = response_data.get("next_prompt", "")
				if next_prompt != "":
					stored_next_prompt = next_prompt
					# Extract word count and required word from the prompt
					var regex = RegEx.new()
					regex.compile("\\d+")
					var regex_result = regex.search(next_prompt)
					if regex_result:
						current_word_count = int(regex_result.get_string())
						print("Next word count from prompt: ", current_word_count)
					else:
						# If no number found, increment normally
						current_word_count += 1
					
					# Extract required word (look for text between「」)
					regex.compile("「([^」]+)」")
					regex_result = regex.search(next_prompt)
					if regex_result:
						required_word = regex_result.get_string(1)
						print("Required word: ", required_word)
					else:
						required_word = ""
					
					# Check if we've reached the limit after extracting
					if current_word_count >= WORD_COUNT_LIMIT:
						game_mode = GameMode.IDIOM_CHALLENGE
						stored_next_prompt = "...素晴らしいですわ。単語数だけでは、あなたの英語力は測れませんわね。"
				else:
					# No next prompt, increment normally
					current_word_count += 1
					if current_word_count >= WORD_COUNT_LIMIT:
						game_mode = GameMode.IDIOM_CHALLENGE
						dialogue_label.text = "...素晴らしいですわ。単語数だけでは、あなたの英語力は測れませんわね。"
				next_turn_timer.start()
			else:
				if comment != "":
					dialogue_label.text = comment
					print("Setting dialogue to error comment: ", comment)
				else:
					dialogue_label.text = "あら、その英語、間違っていますわ。"
					print("Using default error message")
				pending_voice_type = "failure"
				voice_delay_timer.start()
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
				pending_voice_type = "success"
				voice_delay_timer.start()
				next_turn_timer.start() # Fetch next challenge
			else:
				dialogue_label.text = "ふむ...その文章では、わたくしは感心しませんわね。もう一度どうぞ。"
				pending_voice_type = "failure"
				voice_delay_timer.start()
				set_keyboard_enabled(true)

# --- Button Callbacks ---
func _on_letter_button_pressed(letter):
	print("Letter button pressed: ", letter)
	print("Input box editable: ", input_box.editable)
	print("Input box has focus: ", input_box.has_focus())
	game_timer.start()
	input_box.text += letter
	input_box.grab_focus()  # Re-grab focus after button press

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

# --- Voice Playback ---
func _on_voice_delay_timeout():
	if pending_voice_type == "success":
		var voice = voice_resources["success"][randi() % voice_resources["success"].size()]
		audio_player.stream = voice
		audio_player.play()
	elif pending_voice_type == "failure":
		var voice = voice_resources["failure"][randi() % voice_resources["failure"].size()]
		audio_player.stream = voice
		audio_player.play()
	pending_voice_type = ""

# --- Input Event Handlers ---
func _on_input_text_changed(new_text):
	print("Input text changed: ", new_text)
	# Reset timer when typing
	if game_timer.time_left > 0:
		game_timer.start()

func _on_input_text_submitted(text):
	print("Input text submitted: ", text)
	_submit_answer()
