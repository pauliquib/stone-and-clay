## Procedurální modely nástrojů a zbraní v ruce (M0.4). Rám modelu: +Y = osa rukojeti k hlavě nástroje,
## ostří / hlaveň / špička míří do +Z. Kam se model v ruce přiloží a jak se natočí, určuje tabulka `GRIPS` (M3D oprava).
## Rozměry v metrech, barvy z vrcholů.
## Když existuje `assets/models/nastroje/<id>.glb` (AssetLib), použije se místo procedurálního modelu.
class_name ToolModels
extends RefCounted

const WOOD := Color(0.5, 0.34, 0.18)
const STEEL := Color(0.62, 0.64, 0.68)
const DARK := Color(0.2, 0.2, 0.22)


## Úchop nástrojů v ruce (konvence viz `Humanoid`, komentář u HAND_FIST): id → {"rot": stupně Euler XYZ v rámu ruky,
## "grip": bod modelu sevřený v pěsti}. Model: +Y = osa rukojeti k hlavě nástroje, +Z = ostří / hlaveň / špička.
## rot.x = náklon osy rukojeti od předloktí: 0 = podél předloktí, 90 = kolmo dopředu (při vodorovném předloktí svisle).
## Ladění: měnit jen tuto tabulku (DOPLNIT: ručně doladit podle vzhledu ve hře).
const GRIPS := {
	"": {"rot": Vector3(55, 0, 0), "grip": Vector3(0, 0.1, 0)},                  # výchozí hůl
	"sekera": {"rot": Vector3(55, 0, 0), "grip": Vector3(0, 0.05, 0)},           # topůrko nahoru-dopředu, ostří dopředu
	"sekera_stara": {"rot": Vector3(55, 0, 0), "grip": Vector3(0, 0.05, 0)},
	"motorova_pila": {"rot": Vector3(0, 0, 0), "grip": Vector3(0, 0.2, -0.04)},  # horní madlo, lišta vodorovně dopředu
	"lopata": {"rot": Vector3(35, 0, 0), "grip": Vector3(0, 0.35, 0)},           # držení v polovině násady, list dolů
	"motyka": {"rot": Vector3(35, 0, 0), "grip": Vector3(0, 0.35, 0)},
	"vidle": {"rot": Vector3(35, 0, 0), "grip": Vector3(0, 0.35, 0)},            # M3.2: jako lopata, hroty dolů
	"hrabe": {"rot": Vector3(35, 0, 0), "grip": Vector3(0, 0.35, 0)},
	"kosa": {"rot": Vector3(35, 0, 0), "grip": Vector3(0, 0.4, 0)},
	"kladivo": {"rot": Vector3(55, 0, 0), "grip": Vector3(0, 0.03, 0)},          # jako sekera, hlava nahoru-dopředu
	"konev": {"rot": Vector3(0, 0, 0), "grip": Vector3(0, 0.2, 0)},              # horní držadlo podél Z
	"konev_plna": {"rot": Vector3(0, 0, 0), "grip": Vector3(0, 0.2, 0)},
	"hnuj": {"rot": Vector3(0, 0, 0), "grip": Vector3(0, 0.28, 0)},              # držadlo kbelíku nad náplní
	"udice": {"rot": Vector3(12, 0, 0), "grip": Vector3(0, 0.06, 0.03)},         # pažba prutu, špička ~45° nahoru
	"udice_lepsi": {"rot": Vector3(12, 0, 0), "grip": Vector3(0, 0.06, 0.03)},
	"luk": {"rot": Vector3(60, 0, 0), "grip": Vector3(0, 0, 0)},                 # svislé držadlo luku, tětiva k tělu
	"kuse": {"rot": Vector3(60, 0, 0), "grip": Vector3(0, -0.08, -0.05)},        # pistolové držadlo
	"puska": {"rot": Vector3(60, 0, 0), "grip": Vector3(0, -0.06, -0.06)},       # krček pažby
	"nuz": {"rot": Vector3(70, 0, 0), "grip": Vector3(0, 0, 0)},                 # čepel dopředu
	"sirky": {"rot": Vector3(20, 0, 0), "grip": Vector3(0, 0.015, 0)},
	"zapalovac": {"rot": Vector3(20, 0, 0), "grip": Vector3(0, 0.03, 0)},
}


## Model nástroje podle id předmětu z ItemsDB, už s úchopem (`GRIPS`) jako transformací kořene – `Humanoid.set_tool`
## ho jen přidá do ruky. Kořen nese meta `grip_x` (náklon úchopu v rad, pro míření). Neznámé id → hůl v barvě předmětu.
static func model_for(id: String) -> Node3D:
	var holder := Node3D.new()
	holder.add_child(_model(id))
	var g: Dictionary = GRIPS.get(id, GRIPS[""])
	holder.transform = Humanoid.grip_transform(g)
	holder.set_meta("grip_x", deg_to_rad(float((g["rot"] as Vector3).x)))
	return holder


static func _model(id: String) -> Node3D:
	var path := "models/nastroje/%s.glb" % id
	if AssetLib.has(path):
		var m := AssetLib.load_model(path)
		if m:
			return m
	var col: Color = ItemsDB.info(id).get("color", WOOD) if ItemsDB.exists(id) else WOOD
	match id:
		"sekera", "sekera_stara":
			return axe(id == "sekera_stara")
		"motorova_pila":
			return saw()
		"lopata":
			return shovel()
		"motyka":
			return hoe()
		"vidle":
			return pitchfork()
		"hrabe":
			return rake()
		"kosa":
			return scythe()
		"kladivo":
			return hammer()
		"konev", "konev_plna":
			return watering_can()
		"hnuj":
			return manure_bucket()
		"udice", "udice_lepsi":
			return rod()
		"luk":
			return bow()
		"kuse":
			return crossbow()
		"puska":
			return rifle()
		"nuz":
			return knife()
		"sirky", "zapalovac":
			return matches(id == "zapalovac")
		_:
			var k := MeshKit.new()
			k.cylinder(Vector3(0, 0.2, 0), 0.015, 0.015, 0.5, col, Vector3.ZERO, 8)
			return _finish(k)


static func _finish(k: MeshKit, rough := 0.7, metal := 0.0) -> Node3D:
	var root := Node3D.new()
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(rough, metal)))
	return root


## Sekera: topůrko 0,7 m, klín ostří dopředu.
static func axe(old := false) -> Node3D:
	var k := MeshKit.new()
	var wood := WOOD if not old else Color(0.38, 0.27, 0.15)
	k.cylinder(Vector3(0, 0.25, 0), 0.016, 0.02, 0.7, wood, Vector3.ZERO, 8)
	k.box(Vector3(0, 0.56, 0.05), Vector3(0.035, 0.07, 0.1), DARK)
	k.box(Vector3(0, 0.56, 0.12), Vector3(0.012, 0.15, 0.07), STEEL if not old else Color(0.5, 0.48, 0.45))
	return _finish(k)


## Motorová pila: tělo, vodicí lišta dopředu, rukojeť.
static func saw() -> Node3D:
	var k := MeshKit.new()
	k.box(Vector3(0, 0.08, 0), Vector3(0.11, 0.2, 0.28), Color(0.9, 0.5, 0.1))
	k.box(Vector3(0, 0.2, -0.04), Vector3(0.1, 0.05, 0.16), Color(0.15, 0.15, 0.15))
	k.box(Vector3(0, 0.1, 0.4), Vector3(0.03, 0.09, 0.5), STEEL)
	k.box(Vector3(0, 0.1, 0.4), Vector3(0.036, 0.02, 0.5), DARK)
	return _finish(k, 0.6, 0.1)


static func shovel() -> Node3D:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.3, 0), 0.015, 0.015, 0.9, WOOD, Vector3.ZERO, 8)
	k.box(Vector3(0, 0.78, 0), Vector3(0.09, 0.03, 0.03), WOOD)          # držadlo (T)
	k.box(Vector3(0, -0.28, 0.02), Vector3(0.2, 0.28, 0.012), STEEL, Vector3(-0.08, 0, 0))
	return _finish(k, 0.5, 0.3)


static func hoe() -> Node3D:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.3, 0), 0.015, 0.015, 1.0, WOOD, Vector3.ZERO, 8)
	k.box(Vector3(0, -0.2, 0.09), Vector3(0.16, 0.14, 0.012), STEEL, Vector3(0.5, 0, 0))
	return _finish(k, 0.5, 0.3)


## M3.2 Vidle: násada 1,2 m, příčka a čtyři hroty dolů (−Y).
static func pitchfork() -> Node3D:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.3, 0), 0.015, 0.015, 1.2, WOOD, Vector3.ZERO, 8)
	k.box(Vector3(0, -0.3, 0.0), Vector3(0.2, 0.025, 0.025), STEEL)
	for i in 4:
		k.box(Vector3(-0.075 + i * 0.05, -0.45, 0.02), Vector3(0.012, 0.3, 0.012), STEEL, Vector3(-0.12, 0, 0))
	return _finish(k, 0.5, 0.3)


## M3.2 Hrábě: násada a příčný hřeben s krátkými zuby.
static func rake() -> Node3D:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.3, 0), 0.014, 0.014, 1.3, WOOD, Vector3.ZERO, 8)
	k.box(Vector3(0, -0.35, 0.02), Vector3(0.45, 0.035, 0.035), WOOD.darkened(0.15))
	for i in 9:
		k.box(Vector3(-0.2 + i * 0.05, -0.35, 0.07), Vector3(0.008, 0.008, 0.08), WOOD.darkened(0.3))
	return _finish(k)


## M3.2 Kosa: dlouhá násada, rukojeť a čepel napříč u spodního konce.
static func scythe() -> Node3D:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.3, 0), 0.016, 0.016, 1.4, WOOD, Vector3.ZERO, 8)
	k.box(Vector3(0.08, 0.35, 0), Vector3(0.16, 0.025, 0.025), WOOD)                       # rukojeť (klouček)
	k.box(Vector3(0.3, -0.38, 0.03), Vector3(0.62, 0.012, 0.07), STEEL, Vector3(0, 0, -0.15))
	return _finish(k, 0.45, 0.35)


## M3.2 Kladivo: krátká rukojeť, ocelová hlava.
static func hammer() -> Node3D:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.12, 0), 0.014, 0.016, 0.32, WOOD, Vector3.ZERO, 8)
	k.box(Vector3(0, 0.29, 0.02), Vector3(0.035, 0.035, 0.12), DARK)
	return _finish(k, 0.5, 0.3)


static func watering_can() -> Node3D:
	var k := MeshKit.new()
	var c := Color(0.3, 0.55, 0.7)
	k.cylinder(Vector3(0, 0.0, 0), 0.09, 0.1, 0.2, c, Vector3.ZERO, 14)
	k.cylinder(Vector3(0, 0.02, 0.17), 0.012, 0.012, 0.3, c, Vector3(PI / 2 - 0.5, 0, 0), 8)
	k.cylinder(Vector3(0, 0.15, 0.3), 0.03, 0.03, 0.02, c, Vector3(PI / 2 - 0.5, 0, 0), 10)
	k.box(Vector3(0, 0.12, -0.09), Vector3(0.02, 0.2, 0.03), Color(0.22, 0.4, 0.5))
	k.box(Vector3(0, 0.2, 0.0), Vector3(0.02, 0.02, 0.2), Color(0.22, 0.4, 0.5))        # horní držadlo (úchop, osa Z)
	k.box(Vector3(0, 0.15, -0.09), Vector3(0.02, 0.08, 0.02), Color(0.22, 0.4, 0.5))
	k.box(Vector3(0, 0.15, 0.09), Vector3(0.02, 0.1, 0.02), Color(0.22, 0.4, 0.5))
	return _finish(k, 0.5, 0.3)


## Fáze 8: kbelík hnoje z kompostu – pozinkované vedro, hnědá náplň, drátěné držadlo.
static func manure_bucket() -> Node3D:
	var k := MeshKit.new()
	var zinek := Color(0.6, 0.62, 0.65)
	k.cylinder(Vector3(0, 0.12, 0), 0.11, 0.085, 0.24, zinek, Vector3.ZERO, 12)
	k.cylinder(Vector3(0, 0.235, 0), 0.095, 0.095, 0.02, Color(0.28, 0.18, 0.1), Vector3.ZERO, 12)   # náplň
	for sx in [-0.1, 0.1]:
		k.box(Vector3(sx, 0.24, 0), Vector3(0.015, 0.02, 0.015), zinek.darkened(0.2))
	k.box(Vector3(0, 0.32, 0), Vector3(0.015, 0.015, 0.24), zinek.darkened(0.2))                    # držadlo přes okraj
	return _finish(k, 0.5, 0.4)


## Udice: bambusový prut 2 m dopředu-vzhůru s očky.
static func rod() -> Node3D:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.1, 0.0), 0.014, 0.012, 0.22, Color(0.25, 0.2, 0.15), Vector3.ZERO, 8)
	k.cylinder(Vector3(0, 0.5, 0.8), 0.008, 0.004, 1.9, Color(0.4, 0.3, 0.15), Vector3(1.0, 0, 0), 6)
	k.cylinder(Vector3(0, 0.02, 0.0), 0.03, 0.03, 0.03, STEEL, Vector3(0, 0, PI / 2), 10)   # naviják
	return _finish(k)


static func bow() -> Node3D:
	var k := MeshKit.new()
	for i in 8:
		var a0 := -1.15 + i * 0.3286
		var a1 := a0 + 0.3286
		var p0 := Vector3(0.0, 0.42 * sin(a0), 0.12 * cos(a0) - 0.12)
		var p1 := Vector3(0.0, 0.42 * sin(a1), 0.12 * cos(a1) - 0.12)
		k.cylinder((p0 + p1) * 0.5, 0.011, 0.011, p0.distance_to(p1) + 0.01, WOOD,
			Vector3(atan2(p1.z - p0.z, p1.y - p0.y), 0, 0), 6)
	k.box(Vector3(0, 0.0, 0.0), Vector3(0.03, 0.12, 0.04), Color(0.3, 0.2, 0.1))
	k.box(Vector3(0, 0.0, -0.14), Vector3(0.004, 0.76, 0.004), Color(0.9, 0.88, 0.8))   # tětiva
	return _finish(k)


## Nůž: rukojeť kolem počátku (úchop), čepel podél +Y, ostří dopředu (+Z).
static func knife() -> Node3D:
	var k := MeshKit.new()
	k.cylinder(Vector3(0, 0.0, 0), 0.014, 0.012, 0.11, Color(0.3, 0.2, 0.12), Vector3.ZERO, 8)
	k.box(Vector3(0, 0.06, 0), Vector3(0.05, 0.012, 0.022), DARK)                        # záštita
	k.box(Vector3(0, 0.15, 0.002), Vector3(0.004, 0.17, 0.03), STEEL)
	return _finish(k, 0.4, 0.5)


static func crossbow() -> Node3D:
	var k := MeshKit.new()
	k.box(Vector3(0, -0.08, -0.05), Vector3(0.035, 0.1, 0.04), Color(0.3, 0.2, 0.12))    # pistolové držadlo (úchop)
	k.box(Vector3(0, 0.0, 0.1), Vector3(0.05, 0.06, 0.6), Color(0.35, 0.25, 0.15))
	k.box(Vector3(0, 0.03, 0.34), Vector3(0.5, 0.025, 0.025), DARK)                    # ramena
	k.box(Vector3(0, 0.035, 0.28), Vector3(0.46, 0.004, 0.004), Color(0.9, 0.88, 0.8))
	k.box(Vector3(0, 0.045, 0.1), Vector3(0.012, 0.012, 0.4), STEEL)                   # žlábek
	return _finish(k)


static func rifle() -> Node3D:
	var k := MeshKit.new()
	k.box(Vector3(0, -0.06, -0.06), Vector3(0.035, 0.08, 0.04), Color(0.4, 0.26, 0.14))    # krček pažby (úchop)
	k.box(Vector3(0, -0.02, -0.15), Vector3(0.05, 0.11, 0.32), Color(0.4, 0.26, 0.14))     # pažba
	k.box(Vector3(0, 0.0, 0.2), Vector3(0.04, 0.05, 0.5), Color(0.4, 0.26, 0.14))          # předpažbí
	k.cylinder(Vector3(0, 0.03, 0.42), 0.011, 0.011, 0.9, Color(0.15, 0.15, 0.17), Vector3(PI / 2, 0, 0), 8)
	k.cylinder(Vector3(0, 0.075, 0.1), 0.017, 0.017, 0.3, Color(0.1, 0.1, 0.12), Vector3(PI / 2, 0, 0), 8)  # optika
	return _finish(k, 0.5, 0.2)


static func matches(lighter := false) -> Node3D:
	var k := MeshKit.new()
	if lighter:
		k.box(Vector3(0, 0.03, 0), Vector3(0.025, 0.06, 0.012), Color(0.3, 0.5, 0.8))
		k.box(Vector3(0, 0.065, 0), Vector3(0.02, 0.01, 0.01), STEEL)
	else:
		k.box(Vector3(0, 0.015, 0), Vector3(0.05, 0.03, 0.035), Color(0.8, 0.7, 0.4))
		k.box(Vector3(0, 0.03, 0), Vector3(0.048, 0.003, 0.033), Color(0.55, 0.15, 0.1))
	return _finish(k)
