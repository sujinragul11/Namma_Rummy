class_name CoinLabel
extends HBoxContainer
## A gold coin with an amount beside it: the player's balance, or what a table is played for.
## The coin is drawn in code, like the cards, so it needs no image and looks the same everywhere.

const RIM := Color("f9a825")
const SHINE := Color("fff59d")

## How many coins to show.
var amount := 0:
	set(value):
		if value != amount and _label != null and is_inside_tree():
			Ui.pulse(self, 1.1)  # the number changed while on screen: let it be noticed
		amount = value
		_update()

## Words after the number, e.g. "coins".
var suffix := "":
	set(value):
		suffix = value
		_update()

var font_size := 22:
	set(value):
		font_size = value
		_update()

## Gold suits the felt; on a light panel pick something darker.
var text_color := Color("ffca28"):
	set(value):
		text_color = value
		_update()

var _coin: Control
var _label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	_coin = Control.new()
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin.draw.connect(_draw_coin)
	add_child(_coin)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_update()


func _ready() -> void:
	_label.add_theme_font_override("font", Ui.bold_font)


func _update() -> void:
	if _label == null:
		return
	_label.text = Ui.coins_text(amount) + ("" if suffix.is_empty() else " " + suffix)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	var side := roundf(font_size * 1.15)
	_coin.custom_minimum_size = Vector2(side, side)
	_coin.queue_redraw()
	pivot_offset = size / 2.0


func _draw_coin() -> void:
	var center := _coin.size / 2.0
	var radius := minf(center.x, center.y)
	_coin.draw_circle(center, radius, RIM, true, -1.0, true)
	_coin.draw_circle(center, radius * 0.8, Ui.GOLD, true, -1.0, true)
	# a glint on the upper left, so it reads as metal and not as a dot
	_coin.draw_arc(center, radius * 0.55, PI * 1.05, PI * 1.5, 10, SHINE, maxf(1.5, radius * 0.16), true)
