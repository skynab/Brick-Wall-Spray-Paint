extends CanvasLayer
class_name Hud

## Small top-left status overlay: current nozzle + color swatch and a one-line
## key legend. Dismissible with [H]. Built in code.

const LEGEND := "[Space] spray  [Tab] nozzle  [C]/1-6 color  [X] clear  [Ctrl+Z] undo  [Ctrl+S] save  [M] menu  [H] hud  [V] cursor  [T] aim  [P] projector"

var _swatch: ColorRect
var _state: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(18, 18)
	row.add_child(_swatch)
	_state = Label.new()
	row.add_child(_state)
	vbox.add_child(row)

	var legend := Label.new()
	legend.text = LEGEND
	legend.add_theme_font_size_override("font_size", 11)
	legend.modulate = Color(1, 1, 1, 0.55)
	vbox.add_child(legend)


func set_state(nozzle_name: String, shape_name: String, color: Color) -> void:
	if _swatch != null:
		_swatch.color = color
	if _state != null:
		_state.text = "%s · %s   #%s" % [nozzle_name, shape_name, color.to_html(false)]


func toggle() -> void:
	visible = not visible
