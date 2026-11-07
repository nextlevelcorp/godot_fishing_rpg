## A small picture of a species for lists such as the journal: the painted sprite when one exists,
## otherwise the RealFish drawing. Unknown species show as a dark silhouette.
class_name FishIcon
extends Control

var species := ""
var known := true


func _init(id: String = "", is_known: bool = true) -> void:
	species = id
	known = is_known
	custom_minimum_size = Vector2(150.0, 64.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not known:
		self_modulate = Color(0.05, 0.08, 0.12, 0.85)


func _draw() -> void:
	if species == "" or (FightView.CREATURES.has(species) and RealFish.sprite(species) == null):
		return
	var length := size.x * 0.9
	var sprite := RealFish.sprite(species)
	if sprite != null:
		# keep tall fish inside the box
		length = minf(length, size.y * 0.95 * float(sprite.get_width()) / float(sprite.get_height()))
	RealFish.draw(self, species, size * 0.5, length, 0.0, 1.0, 0.0, 0.0, 1.0, 0.4)
