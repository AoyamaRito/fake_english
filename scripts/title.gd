extends Node

@onready var start_button = $VBoxContainer/StartButton
@onready var audio_player = $AudioStreamPlayer

# Title voice lines
var title_voices = [
	preload("res://assets/sounds/voice_ふふふあら英語なのかしら_シャルロッテ.mp3"),
	preload("res://assets/sounds/voice_庶民ねぇまったく_シャルロッテ.mp3"),
	preload("res://assets/sounds/voice_上流階級ではこう言うのよ_シャルロッテ.mp3")
]

func _ready():
	# Connect button
	start_button.pressed.connect(_on_start_button_pressed)
	
	# Play a random title voice
	var voice = title_voices[randi() % title_voices.size()]
	audio_player.stream = voice
	audio_player.play()
	
	# Add hover effect to button
	start_button.mouse_entered.connect(_on_button_hover)

func _on_start_button_pressed():
	# Play button click sound if available
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_button_hover():
	# Optional: Play a hover sound or voice line
	pass
