extends Control

func _ready() -> void:
	Game.player_id = "2"
	Game.socket.is_online = true
	Game.next_round_at = Time.get_ticks_msec() + 12000
	Game.state = {
		"gameId": "test", "status": "round_over", "round": 3, "gameType": "close_joker",
		"players": [{"id": "2", "username": "You", "totalScore": 240, "eliminated": true}],
		"rejoin": {"fee": 500, "score": 145},
		"lastResult": {"round": 3, "winner": "0", "players": []}
	}
	var card := ScoreCard.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(card)
	card.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = card.find_child("RejoinButton", true, false)
	assert(button.visible)
	assert(button.text.contains("500"))
	assert(not button.disabled)
	assert(card.find_child("NextRoundLabel", true, false).text.contains("145"))
	assert(not Ads._may_show(Ads.ROUND_BREAK))
	card._confirm_rejoin()
	var question: ConfirmationDialog = Ui.get_node("QuestionBox")
	assert(question.dialog_text.contains("500"))
	assert(question.dialog_text.contains("145"))
	question.hide()
	Game.next_round_at = Time.get_ticks_msec() - 1
	card._process(0)
	assert(button.disabled)
	Game.state["rejoin"] = null
	card.refresh()
	assert(not button.visible)
	print("PASS: rejoin button, fee, score, confirmation, countdown expiry and ad suppression")
	Sound.hush()
	get_tree().quit()
