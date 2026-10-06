## Místo ve vesnici (hospoda, obchod, pálenice, vinný sklep, chata, úřad, domov):
## cedule, obsluha u dveří, nabídka (co se podává na místě / co se kupuje s sebou),
## otevírací doba, u hospody zahrádka se štamgasty.
class_name Place
extends Node3D

## Nabídky: [id, cena, "serve" (hned vypít/sníst) | "buy" (do inventáře) | "sell" (výkup z inventáře za cenu / ks, M2.1)
## | "header" (M2.3: záhlaví sekce; místo id je text, cena se nepoužije)]
const OFFERS := {
	"hospoda": [["pivo_cepovane", 49, "serve"], ["pivo10", 39, "serve"], ["nealko", 39, "serve"],
		["panak_slivovice", 55, "serve"], ["panak_vodky", 45, "serve"], ["fernet", 50, "serve"],
		["vino_sklenka", 45, "serve"], ["kava", 35, "serve"], ["voda", 25, "serve"],
		["utopenec", 59, "serve"], ["tlacenka", 65, "serve"], ["chleba_sadlo", 45, "serve"],
		["gulas", 169, "serve"], ["smazak", 189, "serve"], ["pivo", 45, "buy"],
		# M2.7 výkup ryb hostinským (režim "sell", cena za kus; kapr v prosinci ×2 – `World.sell_items`; DOPLNIT: ceny odhad)
		["Výkup ryb", 0, "header"], ["ryba_kapr", 100, "sell"], ["ryba_lin", 90, "sell"], ["ryba_stika", 160, "sell"],
		["ryba_candat", 180, "sell"], ["ryba_pstruh", 70, "sell"], ["ryba_okoun", 40, "sell"], ["ryba_cejn", 30, "sell"],
		["ryba_perlin", 45, "sell"], ["ryba_plotice", 15, "sell"], ["ryba_jelec", 15, "sell"], ["ryba_klen", 30, "sell"],
		["ryba_uhor", 200, "sell"], ["ryba_sumec", 320, "sell"],
		# M2.9 výkup zvěřiny (jen legální, s dokladem o původu – `Hunting.sell_venison`; nelegální bokem u překupníka; DOPLNIT: ceny odhad)
		["Výkup zvěřiny (s dokladem o původu)", 0, "header"], ["zverina_srnci", 180, "sell"], ["zverina_divocak", 120, "sell"],
		["zverina_zajic", 150, "sell"], ["trofej_parozky", 100, "sell"]],
	"obchod": [["pivo", 25, "buy"], ["nealko", 22, "buy"], ["vino_bile", 129, "buy"], ["vino_cervene", 139, "buy"],
		["vodka", 229, "buy"], ["rum", 189, "buy"], ["becherovka", 259, "buy"], ["slivovice", 520, "buy"],
		["voda", 19, "buy"], ["rohlik", 8, "buy"], ["chipsy", 45, "buy"], ["jablko", 6, "buy"],
		["tlacenka", 49, "buy"], ["parek", 39, "buy"], ["cigarety", 165, "buy"], ["tabak_semena", 45, "buy"], ["papirky", 25, "buy"], ["konopi_semena", 60, "buy"], ["spacak", 890, "buy"],  # M4.8: semena jen při „Obsah pro dospělé“ (ItemsDB.hidden)
		["sirky", 12, "buy"], ["zapalovac", 39, "buy"], ["burt", 25, "buy"],
		# „Železářství“ – zatím v Potravinách, do M5.1 (stavebniny) se přesune
		["sekera_stara", 390, "buy"], ["sekera", 1290, "buy"], ["motorova_pila", 6900, "buy"],
		# M2.3 oblečení: sekce „Textil“, „Pracovní“, „Slavnostní“ (záhlaví = režim "header", jen text v nabídce)
		["Textil", 0, "header"], ["triko_modre", 199, "buy"], ["triko_zelene", 199, "buy"], ["mikina_seda", 690, "buy"],
		["platenka", 249, "buy"], ["vetrovka", 890, "buy"], ["bunda_zimni", 2490, "buy"], ["kratasy", 349, "buy"],
		["teplaky_zimni", 890, "buy"], ["plavky", 299, "buy"], ["tenisky", 990, "buy"], ["holinky", 549, "buy"],
		["zimni_boty", 1890, "buy"], ["cepice", 199, "buy"], ["cepice_zimni", 249, "buy"], ["klobouk", 599, "buy"],
		["rukavice_zimni", 349, "buy"],
		["Pracovní", 0, "header"], ["monterky", 699, "buy"], ["pracovni_boty", 1290, "buy"], ["reflexni_vesta", 129, "buy"],
		["rukavice_pracovni", 149, "buy"], ["ochranne_kalhoty", 2990, "buy"], ["helma_pila", 1490, "buy"],
		["Slavnostní", 0, "header"], ["kosile_slavnostni", 690, "buy"], ["sako", 2290, "buy"],
		["oblekove_kalhoty", 990, "buy"], ["polobotky", 1290, "buy"], ["prsiplast", 1990, "buy"],
		# M2.4 zahrada: nářadí a semena (DOPLNIT: semena jsou v nabídce celý rok, sezónu hlídá `Garden.CROPS.sow_months`;
		# později i ve stavebninách, M5.1) a výkup zeleniny (režim "sell": nižší cena než při prodeji)
		["Zahrada", 0, "header"], ["lopata", 320, "buy"], ["motyka", 280, "buy"], ["konev", 150, "buy"],
		["semena_brambory", 45, "buy"], ["semena_mrkev", 25, "buy"], ["semena_cibule", 35, "buy"], ["semena_salat", 25, "buy"],
		["semena_rajcata", 60, "buy"], ["semena_dyne", 30, "buy"], ["semena_cesnek", 40, "buy"],
		["Výkup zeleniny", 0, "header"], ["brambory", 5, "sell"], ["mrkev", 6, "sell"], ["cibule", 6, "sell"],
		["salat", 14, "sell"], ["rajce", 10, "sell"], ["dyne", 40, "sell"], ["cesnek", 8, "sell"],
		# M2.5 sazenice stromů (DOPLNIT: ovocné podle zadání jen sezónně III–V a X–XI, lesní přes práci / myslivce – zatím celý rok
		# a všechny v Potravinách; sezónu a lesní sazenice od myslivce doplní M3.3)
		["Sazenice stromů", 0, "header"], ["sazenice_jablon", 290, "buy"], ["sazenice_slivon", 260, "buy"],
		["sazenice_hrusen", 320, "buy"], ["sazenice_tresen", 350, "buy"], ["sazenice_dub", 180, "buy"],
		["sazenice_buk", 180, "buy"], ["sazenice_smrk", 150, "buy"], ["sazenice_borovice", 150, "buy"],
		["ochranny_obal", 45, "buy"],
		# M2.6 hospodářská zvířata: krmivo a nářadí (nákup zvířat řeší cedule u výběhu, `Farm.open_sign_menu`,
		# ne tahle nabídka – DOPLNIT: prompt čekal spíš inzerát na úřadě / u Potravin, zvoleno jednodušší řešení)
		["Hospodářství", 0, "header"], ["zrni", 15, "buy"], ["seno", 25, "buy"], ["granule", 20, "buy"],
		["kbelik", 150, "buy"], ["nuzky", 250, "buy"], ["nuz", 350, "buy"],
		["Výkup živočišných produktů", 0, "header"], ["vejce", 3, "sell"], ["mleko", 10, "sell"], ["vlna", 90, "sell"],
		["maso_drubez", 80, "sell"], ["maso_kralici", 90, "sell"], ["maso_veprove", 85, "sell"], ["sadlo", 35, "sell"],
		["maso_kozi", 95, "sell"], ["maso_skopove", 95, "sell"], ["maso_hovezi", 110, "sell"],
		["zverina_srnci", 150, "sell"], ["zverina_divocak", 100, "sell"], ["zverina_zajic", 125, "sell"],    # M2.9 (s dokladem o původu)
		# M2.7 rybaření: udice, návnady, podběrák (DOPLNIT: těstíčko = koupě, recept mouka + voda až s recepty; rybářský lístek
		# a povolenka budou na úřadě – M4.6)
		["Rybaření", 0, "header"], ["udice", 220, "buy"], ["udice_lepsi", 890, "buy"], ["navnada_zizaly", 20, "buy"],
		["navnada_testo", 15, "buy"], ["navnada_kukurice", 18, "buy"], ["podberak", 240, "buy"],
		# M2.8 zbraně (DOPLNIT: prompt čekal „Potraviny / stavebniny Sport“ – zatím v Potravinách, do M5.1 se přesune; puška a náboje
		# se prodají jen se zbrojním oprávněním, kontrola je ve `World.buy` přes `Weapons.PERMIT_ITEMS`; ceny luku a kuše dle promptu)
		["Sport a lov", 0, "header"], ["luk", 2900, "buy"], ["sipy", 25, "buy"], ["kuse", 5900, "buy"], ["sipky_kuse", 30, "buy"],
		["puska", 18000, "buy"], ["naboje", 40, "buy"],
		# M2.10 doprava nákladu: ruční vozík (po koupi stojí u domova hráče, DOPLNIT: později stavebniny M5.1) a plachta (schová náklad)
		["Doprava a náklad", 0, "header"], ["rucni_vozik", 2490, "buy"], ["plachta", 180, "buy"],
		# M6.1 drony: malý do 250 g (bez zkoušky, jen registrace ÚVL zdarma na PC), velký vyžaduje osvědčení A1/A3
		# (eTest „drony“). Nabíjení a opravy na počítači doma (Letectví – ÚVL). Ceny odhad (DOPLNIT: elektro M5.x?)
		["Drony a technika", 0, "header"], ["dron", 7990, "buy"], ["dron_velky", 32900, "buy"], ["dron_baterie", 1490, "buy"],
		# M6.4 paramotor: nový (i v eŠuplíku) a ojetý za polovinu; průkaz/registrace na PC → Letectví – ÚVL
		["Letectví", 0, "header"], ["paramotor", 180000, "buy"], ["paramotor_ojety", 90000, "buy"]],
	"palenice": [["slivovice", 450, "buy"], ["panak_slivovice", 40, "serve"], ["polena", 30, "sell"]],
	"sklep": [["vino_bile", 150, "buy"], ["vino_cervene", 170, "buy"], ["vino_sklenka", 40, "serve"],
		["chleba_sadlo", 40, "serve"], ["voda", 20, "serve"]],
	# M3.3: lesní sazenice od myslivce (lesní správa; DOPLNIT: ceny odhad, levnější než v Potravinách)
	"chata": [["Lesní sazenice", 0, "header"], ["sazenice_smrk", 90, "buy"], ["sazenice_buk", 110, "buy"],
		["sazenice_dub", 110, "buy"], ["sazenice_borovice", 90, "buy"]],
	"urad": [["pronajem_pole", 1500, "service"]],      # M2.4: pronájem pole na rok (režim "service" → `Garden.service`)
	"domov": [],
	# M3.2 statek (smyšlený „Statek Na Kopci“, vzniká za běhu – `Statek`, ne z pois.json): prodej ze dvora (DOPLNIT: ceny odhad)
	"statek": [["Prodej ze dvora", 0, "header"], ["vejce", 6, "buy"], ["mleko", 22, "buy"], ["seno", 20, "buy"], ["zrni", 12, "buy"]],
}
const HOURS := {"hospoda": [10, 26], "obchod": [6, 21], "palenice": [8, 22], "sklep": [12, 24],
	"chata": [0, 24], "urad": [8, 14], "domov": [0, 24], "statek": [5, 20]}
## Výjimky z otevírací doby podle dne v týdnu (0 = pondělí … 6 = neděle): [od, do] nebo [] = zavřeno.
## Svátky (Clock.holiday) mají obchod zavřený; svátky a události v obci mění hodiny přes VillageEvents.event_hours.
const WEEK_HOURS := {
	"obchod": {5: [7, 11], 6: []},                        # sobota jen dopoledne, v neděli zavřeno
	"hospoda": {4: [10, 27], 5: [10, 27], 6: [10, 24]},    # pá a so do 3:00, v neděli do půlnoci
	# A4-02: obecní úřad má úřední dny – Po a St déle, Út a Čt základní doba, v pátek krátce, víkend zavřeno
	"urad": {0: [7, 17], 2: [7, 17], 4: [8, 12], 5: [], 6: []},
}
const CLOSED_ON_HOLIDAY := ["obchod", "urad"]
const DAY_NAMES := ["po", "út", "st", "čt", "pá", "so", "ne"]
## V pátek večer sedí v hospodě u druhého stolu víc štamgastů
const FRIDAY_EXTRA := [["Standa", Color(0.45, 0.5, 0.3)], ["Vašek", Color(0.6, 0.35, 0.25)], ["Honza", Color(0.3, 0.4, 0.55)]]
const FRIDAY_HOURS := [17.0, 24.0]
const KEEPERS := {
	"hospoda": ["Hostinský Láďa", "bartender", Color(0.95, 0.95, 0.95)],
	"obchod": ["Prodavačka Jarka", "shopkeeper", Color(0.85, 0.45, 0.5)],
	"palenice": ["Palič Vojta", "", Color(0.45, 0.35, 0.25)],
	"sklep": ["Vinař Zdeněk", "", Color(0.5, 0.15, 0.2)],
	"chata": ["Myslivec Franta", "hunter", Color(0.25, 0.32, 0.2)],
	"urad": ["Starosta Novák", "", Color(0.3, 0.3, 0.45)],
	"statek": ["Hospodář Vladimír", "", Color(0.35, 0.42, 0.28)],      # M3.2 (smyšlený)
}
## Povaha obsluhy pro rozhovor (Persona / Dialog): [povaha, povolání, věk, o sobě, témata]
const KEEPER_PERSONA := {
	"hospoda": ["veselak", "hostinský v Hospodě U Hřiště", 52, "Točím tady dvacet let. Pivo musí mít čepici!", ["pivo", "fotbal", "drby"]],
	"obchod": ["pratelsky", "prodavačka v Potravinách", 46, "Rohlíky vozí v šest, kdo dřív přijde, ten dřív mele.", ["obchod", "jidlo", "drby"]],
	"palenice": ["bruclavy", "palič v Pálenici U Kotla", 63, "Slivovice se nepije, ta se vychutnává. Kdo chlastá, ať jde jinam.", ["pole", "jablka", "poradek"]],
	"sklep": ["veselak", "vinař", 55, "Víno je poezie v lahvi.", ["vino", "pocasi", "pole"]],
	"chata": ["bruclavy", "myslivec", 60, "V lese se chodí potichu, ať nevyplašíš zvěř.", ["les", "zver", "vcely"]],
	"urad": ["prisny", "starosta obce", 57, "Obec musí mít pořádek i rozpočet.", ["urad", "poradek", "silnice"]],
	"statek": ["bruclavy", "hospodář na Statku Na Kopci", 58, "Kráva nepočká, ta se dojí i na Štědrý den.", ["pole", "zvirata", "pocasi"]],
}
const REGULARS_PERSONA := [
	["veselak", "štamgast, důchodce", 67, "U tohohle stolu sedím od revoluce."],
	["plachy", "štamgast, lesní dělník", 48, "Po šichtě jedno a domů."],
	["bruclavy", "štamgast, automechanik", 54, "Dneska nikdo neumí seřídit karburátor."],
]

var key := ""
var data: Dictionary
var door := Vector3.ZERO
var park := Vector3.ZERO
var park_yaw := 0.0
var keeper: Npc
var regulars: Array[Npc] = []
var terrain: Terrain
var world: Node
var _table2 := Vector3.ZERO           # druhý stůl zahrádky (hospoda) – tam přisedají páteční hosté
var garden_tables: Array[Vector3] = []   # M3.1: středy stolů zahrádky (hospoda) – cíle pracovního úkolu „Uklidit stoly“ (`Jobs`)
var _fri_guests: Array[Npc] = []
var _fri_t := 1.0
## M1.5: hráč je uvnitř budovy → obsluha stojí za pultem (`keeper_inside_pos`), štamgasti a hosté sedí u stolů v interiéru.
var player_inside := false
var keeper_inside_pos := Vector3.INF
var keeper_inside_yaw := 0.0
var _keeper_home := Vector3.ZERO      # obsluha venku u dveří
var _keeper_home_yaw := 0.0
const HIDDEN_OFFSET := Vector3(0, -60, 0)   # M1.8: kam se schová host, když má sedět uvnitř a interiér ještě není postavený
var _reg_home: Array[Array] = []      # [pozice, yaw] štamgastů na zahrádce (paralelně k `regulars`)
var _fri_home: Array[Array] = []      # [pozice, yaw] pátečních hostů na zahrádce (paralelně k `_fri_guests`)


func setup(k: String, d: Dictionary, t: Terrain, w: Node) -> void:
	key = k
	data = d
	terrain = t
	world = w
	door = Vector3(d["door_x"], t.height_at(d["door_x"], d["door_z"]), d["door_z"])
	park = Vector3(d["park_x"], t.height_at(d["park_x"], d["park_z"]), d["park_z"])
	park_yaw = float(d.get("park_yaw", 0.0))
	name = "Misto_" + k


## Přesun místa (M1.7: „domov“ jde za nemovitostí, kterou hráč vlastní / má pronajatou – `World.apply_home`).
## Jen pro místa bez cedule a obsluhy (domov); `data` dostane nové dveře, parkování, `face_yaw` a název.
func relocate(door_: Vector3, park_: Vector3, park_yaw_: float, face_yaw: float, title: String) -> void:
	door = door_
	park = park_
	park_yaw = park_yaw_
	data["door_x"] = door.x
	data["door_z"] = door.z
	data["park_x"] = park.x
	data["park_z"] = park.z
	data["park_yaw"] = park_yaw
	data["face_yaw"] = face_yaw
	data["name"] = title


func _ready() -> void:
	var face: float = data.get("face_yaw", 0.0)
	# cedule
	if key != "domov":
		var sign_pos := door + Basis(Vector3.UP, face) * Vector3(2.4, 0, 0.6)
		var s := _sign(data["name"], _sign_color())
		s.position = sign_pos
		s.position.y = terrain.height_at(sign_pos.x, sign_pos.z)
		s.rotation.y = face
		add_child(s)
	# obsluha u dveří
	if KEEPERS.has(key):
		var kd: Array = KEEPERS[key]
		var kp := door + Basis(Vector3.UP, face) * Vector3(0.0, 0, 0.3)
		kp.y = terrain.height_at(kp.x, kp.z)
		keeper = Npc.make(kd[0], kd[1], kd[2], hash(key), kp, face, world)
		var kp_: Array = KEEPER_PERSONA.get(key, ["pratelsky", "", 45, "", []])
		keeper.persona = Persona.make({"name": kd[0], "trait": kp_[0], "job": kp_[1], "age": kp_[2], "hobby": kp_[3],
			"topics": kp_[4], "female": kd[1] == "shopkeeper"})
		keeper.role = "keeper"
		keeper.place = key
		if kd[1] == "shopkeeper":
			keeper.visual.female = true
			keeper.visual.hair_style = 2
			keeper.visual.moustache = false
			keeper.visual.beard = false
		add_child(keeper)
		_keeper_home = keeper.position
		_keeper_home_yaw = face
	if key == "hospoda":
		_beer_garden(face)


func _sign_color() -> Color:
	match key:
		"hospoda": return Color(0.45, 0.25, 0.1)
		"obchod": return Color(0.1, 0.4, 0.2)
		"palenice": return Color(0.35, 0.15, 0.4)
		"sklep": return Color(0.45, 0.08, 0.15)
		"chata": return Color(0.25, 0.3, 0.15)
	return Color(0.2, 0.25, 0.45)


func _sign(text: String, col: Color) -> Node3D:
	var root := Node3D.new()
	var k := MeshKit.new()
	var wood := Color(0.35, 0.22, 0.12)
	for s in [-1.0, 1.0]:
		k.box(Vector3(0.75 * s, 1.1, 0), Vector3(0.08, 2.2, 0.08), wood)
	k.box(Vector3(0, 1.9, 0), Vector3(1.8, 0.55, 0.06), col)
	k.box(Vector3(0, 2.2, 0), Vector3(1.9, 0.06, 0.1), wood)
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.8)))
	for side in [0.0, PI]:
		var l := Label3D.new()
		l.text = text
		l.font_size = 64
		l.pixel_size = 0.0045
		l.outline_size = 6
		l.modulate = Color(1.0, 0.95, 0.8)
		l.width = 380.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.position = Vector3(0, 1.9, 0.035 if side == 0.0 else -0.035)
		l.rotation.y = side
		l.double_sided = false
		root.add_child(l)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.9, 2.2, 0.15)
	cs.shape = bs
	cs.position.y = 1.1
	sb.add_child(cs)
	sb.set_meta("surface", "budova")
	root.add_child(sb)
	return root


## Zahrádka před hospodou: stoly, lavice, slunečník, štamgasti.
func _beer_garden(face: float) -> void:
	var b := Basis(Vector3.UP, face)
	var names := [["Pepa", Color(0.3, 0.5, 0.75)], ["Jarda", Color(0.6, 0.55, 0.3)], ["Mirek", Color(0.5, 0.25, 0.2)]]
	for t in 2:
		var c := door + b * Vector3(-3.5 - t * 3.2, 0, 4.0)
		c.y = terrain.height_at(c.x, c.z)
		garden_tables.append(c)
		if t == 1:
			_table2 = c
		var root := Node3D.new()
		root.position = c
		root.rotation.y = face
		add_child(root)
		var k := MeshKit.new()
		var wood := Color(0.55, 0.36, 0.2)
		k.box(Vector3(0, 0.74, 0), Vector3(0.8, 0.05, 1.9), wood)
		for s in [-1.0, 1.0]:
			k.box(Vector3(0, 0.37, 0.75 * s), Vector3(0.7, 0.74, 0.06), wood.darkened(0.2))
			k.box(Vector3(0.7 * s, 0.44, 0), Vector3(0.28, 0.05, 1.9), wood)
			k.box(Vector3(0.7 * s, 0.22, 0.75), Vector3(0.28, 0.44, 0.06), wood.darkened(0.2))
			k.box(Vector3(0.7 * s, 0.22, -0.75), Vector3(0.28, 0.44, 0.06), wood.darkened(0.2))
		if t == 0:
			k.cylinder(Vector3(0, 1.4, 0), 0.025, 0.025, 2.8, Color(0.8, 0.8, 0.8))
			k.cylinder(Vector3(0, 2.6, 0), 0.05, 1.4, 0.35, Color(0.85, 0.15, 0.1), Vector3.ZERO, 12)
		MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.85, 0.0, 0.0, false)))
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.7, 0.78, 1.9)
		cs.shape = bs
		cs.position.y = 0.39
		sb.add_child(cs)
		sb.set_meta("surface", "budova")
		root.add_child(sb)
		# půllitry na stole
		for m in 3:
			var mug := PropModels.drink_model("pivo_cepovane")
			mug.position = Vector3(randf_range(-0.2, 0.2), 0.765, -0.6 + m * 0.55)
			root.add_child(mug)
		if t == 0:
			for i in names.size():
				var side := -1.0 if i < 2 else 1.0
				var lp := Vector3(0.62 * side, 0.0, -0.45 + (i % 2) * 0.9)
				var wp := c + b * lp
				var npc := Npc.make(names[i][0], "", names[i][1], 50 + i, wp, face + (PI / 2 if side < 0 else -PI / 2),
					world, true)
				npc.position.y = c.y - 0.05
				var rp: Array = REGULARS_PERSONA[i % REGULARS_PERSONA.size()]
				npc.persona = Persona.make({"name": names[i][0], "trait": rp[0], "job": rp[1], "age": rp[2], "hobby": rp[3],
					"topics": ["pivo", "fotbal", "drby"]})
				npc.role = "regular"
				npc.place = key
				add_child(npc)
				regulars.append(npc)
				_reg_home.append([npc.position, npc.base_yaw])


## Hodiny [od, do] pro den `off` (0 dnes, −1 včera): základ HOURS → výjimka podle dne v týdnu → svátek → událost v obci.
## `do` může být přes půlnoc (26 = 2:00). Prázdné pole = zavřeno.
func _day_hours(off: int) -> Array:
	var h: Array = HOURS.get(key, [0, 24])
	var clock: Clock = world.get("clock") if world else null
	if clock == null:
		return h
	var wd := posmod(clock.weekday() + off, 7)
	if WEEK_HOURS.has(key) and WEEK_HOURS[key].has(wd):
		h = WEEK_HOURS[key][wd]
	if off == 0 and key in CLOSED_ON_HOLIDAY and clock.holiday() != "":
		h = []
	var ve = world.get("village_events")
	if ve:
		var eh: Array = ve.event_hours(key, clock.jd() + off)
		if not eh.is_empty():
			h = eh
	return h


func is_open(hour: float) -> bool:
	var t := _day_hours(0)
	if t.size() >= 2 and hour >= t[0] and hour < minf(t[1], 24.0):
		return true
	# po půlnoci ještě platí zavírací doba včerejšího dne
	var y := _day_hours(-1)
	return y.size() >= 2 and y[1] > 24 and hour < y[1] - 24.0


func hours_text() -> String:
	var h := _day_hours(0)
	if h.is_empty() or h[0] == h[1]:
		var clock: Clock = world.get("clock") if world else null
		return "dnes zavřeno (svátek)" if clock and clock.holiday() != "" and key in CLOSED_ON_HOLIDAY else "dnes zavřeno"
	if h[0] == 0 and h[1] == 24:
		return "nonstop"
	var txt := "%d:00–%d:00" % [h[0], int(h[1]) % 24]
	# A1-06: u míst s výjimkami podle dne (víkend, úřední dny) se vypíšou i ty
	if WEEK_HOURS.has(key):
		var parts := []
		for wd in range(7):
			if WEEK_HOURS[key].has(wd):
				var e: Array = WEEK_HOURS[key][wd]
				parts.append("%s %s" % [DAY_NAMES[wd], "zavřeno" if e.is_empty() else "%d:00–%d:00" % [e[0], int(e[1]) % 24]])
		txt += " (%s)" % ", ".join(parts)
	return txt


# ------------------------------------------------------------------ páteční hosté

func _process(delta: float) -> void:
	_fri_t -= delta
	if _fri_t > 0.0:
		return
	_fri_t = 4.0
	_place_people()                 # obsluha mimo otevírací dobu zmizí (A1-05); hospoda i hosté
	if key != "hospoda":
		return
	var clock: Clock = world.get("clock") if world else null
	var want := 0
	if clock and clock.weekday() == 4 and clock.hour() >= FRIDAY_HOURS[0] and clock.hour() < FRIDAY_HOURS[1] \
			and is_open(clock.hour()):
		want = FRIDAY_EXTRA.size()
	if want > 0 and _fri_guests.is_empty():
		_spawn_friday_guests()
	elif want == 0 and not _fri_guests.is_empty():
		for g in _fri_guests:
			regulars.erase(g)
			g.queue_free()
		_fri_guests.clear()
		_fri_home.clear()


func _spawn_friday_guests() -> void:
	if _table2 == Vector3.ZERO:
		return
	var face: float = data.get("face_yaw", 0.0)
	var b := Basis(Vector3.UP, face)
	for i in FRIDAY_EXTRA.size():
		var side := -1.0 if i < 2 else 1.0
		var wp := _table2 + b * Vector3(0.62 * side, 0.0, -0.45 + (i % 2) * 0.9)
		var npc := Npc.make(FRIDAY_EXTRA[i][0], "", FRIDAY_EXTRA[i][1], 80 + i, wp,
			face + (PI / 2 if side < 0 else -PI / 2), world, true)
		npc.position.y = _table2.y - 0.05
		var rp: Array = REGULARS_PERSONA[(i + 1) % REGULARS_PERSONA.size()]
		npc.persona = Persona.make({"name": FRIDAY_EXTRA[i][0], "trait": rp[0], "job": rp[1], "age": rp[2],
			"hobby": rp[3], "topics": ["pivo", "fotbal", "drby"]})
		npc.role = "regular"
		npc.place = key
		add_child(npc)
		regulars.append(npc)
		_fri_guests.append(npc)
		_fri_home.append([npc.position, npc.base_yaw])
	_place_people()


# ------------------------------------------------------------------ obsluha a hosté uvnitř (M1.5)

func _interior() -> Interior:
	var its = world.get("interiors") if world else null
	return its.get(key) if its is Dictionary else null


## Volá `World.interior_mark / interior_clear`: hráč vešel / vyšel. Obsluha se přesune za pult (nebo zpět ke dveřím).
func set_inside(on: bool, it: Interior) -> void:
	player_inside = on
	if on and it != null:
		keeper_inside_pos = it.keeper_spot
		keeper_inside_yaw = it.keeper_yaw
	_place_people()


## Je místo teď otevřené? (bez hodin světa vždy ano)
func _open_now() -> bool:
	var clock: Clock = world.get("clock") if world else null
	return clock == null or is_open(clock.hour())


## Zahrádka je venku jen v létě, za tepla, ve dne a bez deště; jinak štamgasti sedí uvnitř (zahrádka zůstane prázdná).
func _garden_open() -> bool:
	var clock: Clock = world.get("clock") if world else null
	if clock == null:
		return true
	if not is_open(clock.hour()):
		return false
	var w = world.get("weather")
	var dry: bool = w == null or (not w.is_raining() and w.temp >= 15.0)
	return clock.season() == "léto" and clock.hour() >= 10.0 and clock.hour() < 22.0 and dry


## Rozestaví obsluhu, štamgasty a hosty: interiér má přednost, když v něm je hráč, nebo když je zahrádka zavřená.
func _place_people() -> void:
	var it := _interior()
	if keeper:
		if player_inside and keeper_inside_pos != Vector3.INF:
			keeper.global_position = keeper_inside_pos
			keeper.base_yaw = keeper_inside_yaw
		elif _open_now():
			keeper.position = _keeper_home
			keeper.base_yaw = _keeper_home_yaw
		else:
			keeper.position = _keeper_home + HIDDEN_OFFSET     # zavřeno: obsluha není venku 24/7
			keeper.base_yaw = _keeper_home_yaw
	if key != "hospoda":
		return
	var garden := _garden_open() and not player_inside
	var reg_n := mini(regulars.size() - _fri_guests.size(), _reg_home.size())
	for i in reg_n:
		_seat(regulars[i], it, "reg", i, _reg_home[i], garden)
	var streamed: bool = world.get("interior_streamer") != null    # M1.8: interiér existuje, jen se staví až zblízka
	for i in _fri_guests.size():
		# páteční hosté sedí u druhého stolu v sále; bez interiéru (chybí data) na zahrádce
		_seat(_fri_guests[i], it, "fri", i, _fri_home[i] if i < _fri_home.size() else [], it == null and not streamed)


func _seat(n: Npc, it: Interior, group: String, i: int, home: Array, outdoor: bool) -> void:
	if outdoor and not home.is_empty():
		n.position = home[0]
		n.base_yaw = home[1]
	elif it != null and it.seats.has(group) and i < (it.seats[group] as Array).size():
		var sp: Array = it.seats[group][i]
		n.global_position = sp[0]
		n.base_yaw = sp[1]
	elif not outdoor and not home.is_empty():
		# M1.8: interiér se staví až zblízka (InteriorStreamer) – do té doby host „sedí uvnitř“ mimo dohled (pod zahrádkou)
		n.position = (home[0] as Vector3) + HIDDEN_OFFSET
