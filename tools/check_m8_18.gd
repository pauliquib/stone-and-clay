## M8.18: ověření bez hry – počet parametrů F3 skupin kroku a syntéza všech zvuků zvukové krajiny (délka, špička).
##   godot --headless --path . -s res://tools/check_m8_18.gd
extends SceneTree


func _initialize() -> void:
	DevTune.ensure()
	var total := 0
	for g in ["Příroda/Zvuková krajina", "Příroda/Zvuková krajina – druhy", "Zvěř/Hmyz a drobný život"]:
		var n := DevTune.ids(g).size()
		total += n
		print("%s: %d" % [g, n])
	print("M8.18 parametrů celkem: %d (všech v registru: %d)" % [total, DevTune.ids().size()])
	var t0 := Time.get_ticks_msec()
	for nm in NatureSfx.SYNTH_LOOPED:
		for v in 2:
			var s := NatureSfx.synth(String(nm), v)
			var peak := 0.0
			for x in s:
				peak = maxf(peak, absf(x))
			print("  %-14s v%d: %.2f s, špička %.2f%s" % [nm, v, float(s.size()) / Sfx.RATE, peak, "  ← ořez!" if peak > 1.0 else ""])
	print("syntéza: %d ms" % (Time.get_ticks_msec() - t0))
	var d := Soundscape.data()
	print("zdrojů v data/zvuky_prirody.json: %d" % (d.get("zdroje", []) as Array).size())
	quit()
