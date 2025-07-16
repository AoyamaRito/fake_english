extends Node

# --- Nodes ---
@onready var title_label = $VBoxContainer/TitleLabel
@onready var result_label = $VBoxContainer/ResultLabel
@onready var score_label = $VBoxContainer/ScoreLabel
@onready var retry_button = $VBoxContainer/RetryButton
@onready var audio_player = $AudioStreamPlayer

# --- Ending Voice Resources ---
var ending_voices = [
	preload("res://assets/ending/voice_ななによあなた庶民なのに_シャルロッテ.mp3"),
	preload("res://assets/ending/voice_なんだやっぱりこの程度なんだ期待_シャルロッテ.mp3"),
	preload("res://assets/ending/voice_結構やるとおもったのにまだまだね_シャルロッテ.mp3")
]

func _ready():
	# Connect retry button
	retry_button.pressed.connect(_on_retry_button_pressed)
	
	# Display score
	var score = GameManager.final_score
	score_label.text = "Score: %d" % score
	
	# Set result message based on score
	if score < 3:
		result_label.text = "まあ、庶民の英語力なんてこんなものですわね..."
		title_label.text = "GAME OVER"
	elif score < 7:
		result_label.text = "少しは頑張ったようですけど、まだまだですわ。"
		title_label.text = "そこそこね"
	else:
		result_label.text = "意外とやるじゃない...でも調子に乗らないでくださる？"
		title_label.text = "なかなかやるわね"
	
	# Play random ending voice
	var voice = ending_voices[randi() % ending_voices.size()]
	audio_player.stream = voice
	audio_player.play()

func _on_retry_button_pressed():
	# Reset game and return to main scene
	GameManager.reset_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")