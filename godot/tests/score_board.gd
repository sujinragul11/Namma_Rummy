extends Control

func _ready() -> void:
	Game.player_id = "a"
	Game.state = {
		"status": "playing", "round": 2,
		"players": [{"id": "a", "username": "Alice", "totalScore": 0}, {"id": "b", "username": "Bob", "totalScore": 20}],
		"scoreHistory": [{"round": 1, "players": [{"id": "a", "points": 0}, {"id": "b", "points": 20}]}]
	}
	var board := preload("res://scenes/score_board.gd").new()
	add_child(board)
	await get_tree().process_frame
	var grid: GridContainer = board.find_child("ScoreHistoryGrid", true, false)
	assert(grid.columns == 3)
	assert(grid.get_child_count() == 12)
	assert(grid.get_child(1).get_child(0).text == "YOU")
	assert(grid.get_child(5).get_child(0).text == "20")
	assert(grid.get_child(8).get_child(0).text == "—")
	for i in 4:
		Game.state.players.append({"id": str(i + 10), "username": "Player %d" % i, "totalScore": 0})
	board.refresh()
	assert(grid.columns == 7)
	assert(grid.get_child_count() == 28)
	Game.state["deals"] = 2
	board.refresh()
	assert(grid.get_child_count() == 35)
	board.close()
	await get_tree().process_frame
	assert(get_tree().get_first_node_in_group("score_board") == null)
	print("PASS: scoreboard rows, totals, pending scores and close")
	Sound.hush()
	get_tree().quit()
