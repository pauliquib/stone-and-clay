## Skupina zvířat (srnčí rodina, tlupa divočáků). Vůdce (obvykle nejstarší samice) vybírá cíle,
## ostatní se drží na svých místech kolem něj. Poplach jednoho člena (štěknutí, útěk) se přenese na všechny.
class_name Herd
extends RefCounted

var members: Array = []              # Array[Animal]
var leader: Node = null
var home := Vector3.ZERO
var alarm_pos := Vector3.INF         # odkud přišlo nebezpečí
var alarm_until := 0.0               # do kdy (s od startu hry) skupina prchá
var has_young := false
var transient := false               # spawnutá kvůli hráči (Fauna._encounter_scan) – zmizí, až odejde


func add(a: Node) -> void:
	members.append(a)
	if leader == null:
		leader = a


## Vůdce – když uhyne, převezme vedení jiný dospělý člen.
func get_leader() -> Node:
	if leader == null or not is_instance_valid(leader) or leader.dead:
		leader = null
		for m in members:
			if is_instance_valid(m) and not m.dead and not m.young:
				leader = m
				break
		if leader == null:
			for m in members:
				if is_instance_valid(m) and not m.dead:
					leader = m
					break
	return leader


## Poplach: všichni členové utíkají od `pos` aspoň `dur` sekund.
func alarm(pos: Vector3, dur := 8.0) -> void:
	alarm_pos = pos
	alarm_until = maxf(alarm_until, Time.get_ticks_msec() / 1000.0 + dur)


func alarmed() -> bool:
	return Time.get_ticks_msec() / 1000.0 < alarm_until


## Místo člena `i` ve skupině vůči vůdci (v jeho souřadnicích: +Z dopředu).
func slot(i: int) -> Vector3:
	if i == 0:
		return Vector3.ZERO
	var row := (i + 1) / 2
	var side := 1.0 if i % 2 == 1 else -1.0
	return Vector3(side * (1.6 + row * 0.6), 0.0, -row * 2.4)
