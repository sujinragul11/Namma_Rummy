extends Control
## Live round history. Scores come from the server; opening this never pauses the clock.

var _grid: GridContainer
var _summary: Label

func _ready() -> void:
	name = "ScoreBoard"
	add_to_group("score_board")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 90
	frame.offset_right = -90
	frame.offset_top = 48
	frame.offset_bottom = -48
	var box := Ui.box(Color("fff9e9"), 16, 18, 16)
	box.border_color = Color("19a68b")
	box.set_border_width_all(4)
	frame.add_theme_stylebox_override("panel", box)
	add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var title := Label.new()
	title.text = "Score Board"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Ui.bold_font)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("1d564c"))
	bar.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(90, 52)
	Ui.tint_button(close_button, Ui.TEAL)
	close_button.pressed.connect(close)
	bar.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.name = "ScoreHistoryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "ScoreHistoryGrid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(_grid)
	_summary = Label.new()
	_summary.add_theme_color_override("font_color", Color("1d564c"))
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_font_size_override("font_size", 20)
	column.add_child(_summary)
	Game.state_changed.connect(refresh)
	refresh()

func close() -> void:
	queue_free()

func refresh() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var players: Array = Game.players().duplicate()
	# Keep the local player first, as in the reference scoreboard.
	for i in players.size():
		if str(players[i].get("id", "")) == Game.player_id:
			players.push_front(players.pop_at(i))
			break
	_grid.columns = players.size() + 1
	_cell("Deal #" if Game.deals() > 0 else "Round #", Color("3c1909"))
	for player: Dictionary in players:
		_cell("YOU" if str(player.get("id")) == Game.player_id else str(player.get("username", "Player")), Color("3c1909"))
	var history: Array = Game.state.get("scoreHistory", []).duplicate()
	# Older saved matches can supply their last result, but earlier scores cannot be reconstructed.
	var last: Variant = Game.state.get("lastResult")
	if history.is_empty() and last is Dictionary:
		history.append(last)
	for round_score: Dictionary in history:
		var rejoined: bool = round_score.get("type", "") == "rejoin"
		_cell("Rejoin" if rejoined else str(round_score.get("round", 1)), Color("75482e"))
		for player: Dictionary in players:
			var value := "—"
			for entry: Dictionary in round_score.get("players", []):
				if str(entry.get("id")) == str(player.get("id")):
					value = "→ %d" % int(entry.get("rejoinScore", 0)) if rejoined else str(int(entry.get("points", 0)))
			_cell(value, Color("75482e"))
	if Game.status() == "playing":
		_cell(str(Game.state.get("round", 1)), Color("075244"))
		for _player in players:
			_cell("—", Color("075244"))
	_cell("Total points", Color("159c41"))
	for player: Dictionary in players:
		_cell(str(int(player.get("totalScore", 0))), Color("159c41"))
	if Game.deals() > 0:
		_cell("Chips", Color("087764"))
		for player: Dictionary in players:
			_cell(str(int(player.get("chips", 0))), Color("087764"))
	_summary.text = "Round scores are points. — means pending or not played."
	if Game.status() == "playing":
		_summary.text += "  The turn timer continues."

func _cell(text: String, color: Color) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 52)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Ui.box(color, 0, 12, 8))
	var label := Label.new()
	label.text = text
	label.tooltip_text = text
	label.custom_minimum_size.x = 116
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 24)
	panel.add_child(label)
	_grid.add_child(panel)
