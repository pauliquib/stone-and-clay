## Obrazovka cvičného testu (M3.4, eTesty na počítači doma) – rámec pro testy autoškoly (M4.1), zbrojní, lovecké a rybářské
## zkoušky (M4.6) a drony (M6.1). Otázky jsou v `data/testy/<id>.json`:
##   {nazev, popis, prah (kolik správně = prošel), poznamka, otazky: [{otazka, odpovedi: [3 texty], spravna: index 0–2}]}
## Otázky jsou vlastní formulace (NEKOPÍROVAT oficiální testové otázky). Na konci signál `finished(score, total, passed)`.
class_name TestUI
extends VBoxContainer

signal finished(score: int, total: int, passed: bool)

const TEXT := Color(0.08, 0.08, 0.1)
const OK_COL := Color(0.1, 0.5, 0.15)
const BAD_COL := Color(0.7, 0.12, 0.1)

var data: Dictionary
var _q: Array = []
var _i := 0
var _score := 0
var _answered := false
var _head: Label
var _question: Label
var _buttons: Array[Button] = []
var _feedback: Label
var _next: Button


func setup(d: Dictionary) -> void:
	data = d
	_q = d.get("otazky", [])
	add_theme_constant_override("separation", 10)
	_head = _lbl(17)
	_question = _lbl(18)
	for k in 3:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_answer.bind(k))
		add_child(b)
		_buttons.append(b)
	_feedback = _lbl(16)
	_next = Button.new()
	_next.text = "Další otázka →"
	_next.add_theme_font_size_override("font_size", 16)
	_next.pressed.connect(_on_next)
	add_child(_next)
	_show()


func _lbl(fsize: int) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", TEXT)
	add_child(l)
	return l


func _show() -> void:
	_answered = false
	_feedback.text = ""
	_next.visible = false
	if _i >= _q.size():
		_finish()
		return
	var q: Dictionary = _q[_i]
	_head.text = "%s – otázka %d / %d   (správně zatím %d)" % [data.get("nazev", "Test"), _i + 1, _q.size(), _score]
	_question.text = String(q.get("otazka", ""))
	var ans: Array = q.get("odpovedi", [])
	for k in _buttons.size():
		var b := _buttons[k]
		b.visible = k < ans.size()
		b.disabled = false
		b.text = "%s)  %s" % [["A", "B", "C"][k], String(ans[k]) if k < ans.size() else ""]
		b.remove_theme_color_override("font_disabled_color")


func _answer(k: int) -> void:
	if _answered or _i >= _q.size():
		return
	_answered = true
	var q: Dictionary = _q[_i]
	var ok_i := int(q.get("spravna", 0))
	for j in _buttons.size():
		_buttons[j].disabled = true
		if j == ok_i:
			_buttons[j].add_theme_color_override("font_disabled_color", OK_COL)
		elif j == k:
			_buttons[j].add_theme_color_override("font_disabled_color", BAD_COL)
	if k == ok_i:
		_score += 1
		_feedback.text = "Správně."
		_feedback.add_theme_color_override("font_color", OK_COL)
	else:
		_feedback.text = "Špatně – správně je %s." % ["A", "B", "C"][clampi(ok_i, 0, 2)]
		_feedback.add_theme_color_override("font_color", BAD_COL)
	var why := String(q.get("vysvetleni", ""))
	if why != "":
		_feedback.text += "  " + why
	_next.text = "Další otázka →" if _i + 1 < _q.size() else "Vyhodnotit test"
	_next.visible = true


func _on_next() -> void:
	_i += 1
	_show()


func _finish() -> void:
	var total := _q.size()
	var need := int(data.get("prah", ceili(total * 0.8)))
	var passed := _score >= need
	_head.text = "%s – hotovo" % data.get("nazev", "Test")
	_question.text = "Výsledek: %d / %d správně (k úspěchu je potřeba %d). %s" % [_score, total, need,
		"PROŠEL JSI." if passed else "Tentokrát to nevyšlo – zkus to znovu."]
	for b in _buttons:
		b.visible = false
	_feedback.text = String(data.get("poznamka", ""))
	_feedback.add_theme_color_override("font_color", TEXT)
	_next.visible = false
	finished.emit(_score, total, passed)
