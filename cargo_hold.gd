## The boat's fish hold: a weight-limited list of fish dictionaries. No nodes, no signals.
## capacity_kg is the comfortable limit. Up to capacity * hard_limit_ratio fits, but the Boat
## pays for every kilo over capacity (extra drag, lazier turning).
class_name CargoHold
extends RefCounted

var capacity_kg := 40.0
var hard_limit_ratio := 1.3
var items: Array[Dictionary] = []
var total_kg := 0.0


func ratio() -> float:
	return total_kg / capacity_kg if capacity_kg > 0.0 else 0.0


func overload_ratio() -> float:
	return maxf(ratio() - 1.0, 0.0)


func can_fit(weight_kg: float) -> bool:
	return total_kg + weight_kg <= capacity_kg * hard_limit_ratio


func add(item: Dictionary) -> bool:
	var kg: float = item["weight_kg"]
	if not can_fit(kg):
		return false
	items.append(item)
	total_kg += kg
	return true


func remove_at(index: int) -> Dictionary:
	var item := items[index]
	items.remove_at(index)
	total_kg = maxf(total_kg - float(item["weight_kg"]), 0.0)
	return item


## Empties the hold and returns what was in it.
func clear() -> Array[Dictionary]:
	var out := items.duplicate()
	items.clear()
	total_kg = 0.0
	return out


## For loading a save.
func restore(saved: Array) -> void:
	items.clear()
	total_kg = 0.0
	for item: Dictionary in saved:
		items.append(item)
		total_kg += float(item["weight_kg"])
