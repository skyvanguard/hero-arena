class_name Regions
extends RefCounted
## Region table (Phase 5, directive: region table with LATAM priority).
## Table order IS the widen order: the queue widens from the preferred
## region outward along this list (LATAM regions first per directive §23).
## Infrastructure data (not gameplay balance), hence a const table here.

const TABLE: Array = [
	{"code": "latam_saopaulo", "name": "SÃO PAULO (LATAM)"},
	{"code": "latam_bogota", "name": "BOGOTÁ (LATAM)"},
	{"code": "latam_mexico", "name": "CDMX (LATAM)"},
	{"code": "north_america", "name": "NORTH AMERICA"},
	{"code": "europe", "name": "EUROPE"},
	{"code": "asia", "name": "ASIA"},
]

static func all() -> Array:
	return TABLE

static func by_code(code: String) -> Dictionary:
	for r in TABLE:
		if str(r.code) == code:
			return r
	return {}

## Widen order for a preferred region: the preferred region first, then the
## rest of the table in order (LATAM before NA/EU/ASIA when the preferred is
## a LATAM region - the table order encodes the LATAM-priority policy).
static func widen_order(preferred: String) -> Array:
	var out: Array = []
	if preferred != "":
		out.append(preferred)
	for r in TABLE:
		if str(r.code) != preferred:
			out.append(str(r.code))
	return out

static func rank_in_order(order: Array, code: String) -> int:
	for i in order.size():
		if order[i] == code:
			return i
	return order.size()

static func is_valid(code: String) -> bool:
	return by_code(code) != {}

static func display(code: String) -> String:
	var r := by_code(code)
	return str(r.get("name", code))
