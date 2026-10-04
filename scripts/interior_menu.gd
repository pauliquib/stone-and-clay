## Obsluha interakce (E) s objekty v interiéru (M1.4): nabídky postele, ledničky, kafe, dřezu; vyjití ven;
## počítač (M3.4, `ComputerUI`). Volá se z `LocalClient._interact` pro položky `kind == "interior_obj"`.
## Nové druhy objektů (M1.5, M2.2, M2.3, M3.4) se doplňují do `open` – klíč je `key` z `Interior.add_object`.
## M1.8 (generované interiéry, `InteriorStreamer`): "flat:<n>", "stairs", "table", "resident", "tools", "mailbox".
class_name InteriorMenu
extends RefCounted


static func open(client: Node, it: Dictionary) -> void:
	var world: World = client.world
	var pid: int = client.pid
	var hud: Hud = client.hud
	var p: Player = client.player
	var key := String(it["key"])
	if key.begins_with("place:"):             # obsluha veřejné budovy (M1.5) = stejná nabídka jako u dveří
		_open_keeper(client, key.substr(6))
		return
	var iid := String(it.get("interior", ""))
	var st: InteriorStreamer = world.interior_streamer
	if key.begins_with("flat:") and st:       # M1.8: dveře bytu v chodbě bytového domu
		st.flat_door(pid, iid, int(key.substr(5)))
		return
	match key:
		"exit":
			world.exit_interior(pid)
		"bed":
			var h := world.clock.hour()
			var opts := [["Vyspat se (do 7:00 ráno)", func(): world.sleep(pid)],
				["Zdřímnout si (2 hodiny)", func(): world.rest(pid, 2.0)]]
			if h >= 7.0 and h < 17.0:
				opts.append(["Odpočívat do večera (18:00)", func(): world.rest(pid, 18.0 - h)])
			hud.open_menu("Postel", "Je %s. Promile %s ‰." % [world.clock.text(),
				("%.2f" % p.body.promile()).replace(".", ",")], opts)
		"fridge":
			hud.open_menu("Lednička", "Peníze: %d Kč." % p.money, [
				["Rohlíky (zdarma)", func(): world.serve(pid, "rohlik")],
				["Chleba se sádlem (zdarma)", func(): world.serve(pid, "chleba_sadlo")],
				["Sklenice vody", func(): world.serve(pid, "voda")]])
		"coffee":
			hud.open_menu("Kávovar", "", [["Uvařit si kafe", func(): world.serve(pid, "kava")]])
		"sink":
			var opts2 := [["Sklenice vody", func(): world.serve(pid, "voda")]]
			if p.body.stomach_alc > 3.0:
				opts2.append(["Vyzvracet se do dřezu (vyprázdní žaludek)", func(): world.vomit(pid)])
			hud.open_menu("Dřez", "", opts2)
		"stove":
			if world.fire_mgr:
				world.fire_mgr.open_stove_menu(pid)      # M2.2: zatopit / přiložit (2 polena = 3 herní hodiny)
			else:
				hud.show_message("Kamna na dřevo.", 2.0)
		"wardrobe":
			Wardrobe.open_home_menu(client)      # M2.3: převléknout po slotech (okamžitě)
		"pc":
			ComputerUI.open_for(client)          # M3.4: e-shop, bazar, práce, banka, web obce, pošta, eTesty, hry
		"stairs":                             # M1.8: schodiště bytového domu – výběr patra
			if st:
				st.stairs_menu(pid, iid)
		"table":                              # M1.8: posedět u stolu v cizím domě
			if st:
				st.sit(pid, iid)
		"resident":
			if st:
				st.talk(pid, iid)
		"tools":
			hud.show_message("Ponk s nářadím – práce se dřevem a opravy budou později (M3).", 3.0)
		"mailbox":
			hud.show_message("Poštovní schránky – jen reklamní letáky a výzva k odečtu vodoměru. (Vymyšlené.)", 3.5)
		"notice":
			hud.show_message("Úřední deska: svoz odpadu ve čtvrtek, sečení příkopů dle počasí, hody se blíží. (Vymyšlené oznámení.)", 4.5)
		_:
			hud.show_message(String(it.get("text", "")), 2.0)


## Obsluha veřejné budovy: postrach vsi je vyhozen (obsluha ho pošle ven), jinak se otevře běžná nabídka místa.
## Zavřeno uvnitř nastane jen krátce před vyhozením (`Interior._check_open`) – nabídka pak ukáže „ZAVŘENO“.
static func _open_keeper(client: Node, place_key: String) -> void:
	var world: World = client.world
	var pl: Place = world.places.get(place_key)
	var rep: Reputation = world.reputations.get(client.pid)
	if pl and rep and rep.refused_at(place_key):
		if pl.keeper:
			pl.keeper.say("Ven! Tobě tu nenalejou ani nepodají!", 3.0)
		world.notify(client.pid, "show_message", ["Vyhodili tě – špatná pověst (%s)." % rep.tier_name(), 3.0])
		await client.get_tree().create_timer(1.2).timeout
		world.exit_interior(client.pid)
		return
	client.open_place_menu(place_key)
