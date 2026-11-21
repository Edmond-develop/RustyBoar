extends Node3D
## Шаг 72–73: уступ на Пике для ботов (группа coop_gate, как подъёмный мост и «Живые зеркала»).
##   оба внизу — бот встаёт к камню и подсаживает (держит E), хозяин разбегается и прыгает рядом;
##   хозяин наверху — бот держит E у лестницы (лезет, когда хозяин держит лестницу);
##   бот наверху, хозяин внизу — бот держит лестницу.

var mtn: Node
var idx := 0
var is_open := false


func _ob() -> Dictionary:
	return mtn.obstacles[idx]


func _near(p: Vector3) -> bool:
	var o := _ob()
	return p.distance_to(o["foot"]) < 32.0 or p.distance_to(o["top_exit"]) < 32.0


func _below(p: Vector3) -> bool:
	var o := _ob()
	return p.y < (float(o["y0"]) + float(o["y1"])) * 0.5


func bot_target(bot: Node3D, owner_node: Node3D) -> Vector3:
	if bot.get("snow") != null and bot.snow.busy():
		return Vector3.INF
	var b := bot.global_position
	var o := owner_node.global_position
	if not _near(b) or not _near(o):
		return Vector3.INF
	var ob := _ob()
	if ob.has("no_ladder"):
		# ниша с деталью канатки: подсаживаю, только если хозяин рядом и деталь ещё не поставлена
		var rw: Node = mtn.get("ropeway")
		if o.distance_to(ob["boost"]) > 8.0 or (rw != null and rw.has_method("niche_taken") and rw.niche_taken()):
			return Vector3.INF
	var bb := _below(b)
	var ow := _below(o)
	if bb and ow:
		return ob["boost"]
	if ob.has("no_ladder"):
		return Vector3.INF               # ниша: лестницы нет — хозяин спрыгнет сам
	if bb and not ow:
		return ob["ladder_foot"]
	if not bb and ow:
		return ob["anchor"]
	return Vector3.INF


func bot_crank(bot: Node3D, owner_node: Node3D) -> bool:
	var t := bot_target(bot, owner_node)
	if t == Vector3.INF:
		return false
	var b := bot.global_position
	return Vector2(t.x - b.x, t.z - b.z).length() < 0.9 and absf(t.y - b.y) < 1.6
