extends Node3D
class_name DvurStavebnin

## Venkovní dvůr stavebnin a pily (M5.1 pokračování): hromady písku, štěrku, cihel, prken a dříví,
## kulatina a piliny u pily. Jen vizuál bez kolizí (hráč si materiál bere z nabídky / nákladem).
## Souřadnice z `data/buildings.json` (hala 279052827 je pro stavebniny, pila 279052820 severně od ní) –
## hromady leží mimo půdorysy obou budov (hala z jihu ~z 800+, pila z jihu/severu z-688…714).
## Výška terénu se bere z `Terrain.height_at`.

## [druh, x, z, délka, šířka, výška] – druh: pisek / sterk (kužel), cihly / prkna / poleno / rezivo (hromada na paletě),
## kulatina (kulatina ležící), piliny (kužel)
const PILES := [
	["pisek", -326.0, 803.0, 6.0, 4.0, 1.0],     # stavebniny: písek
	["sterk", -316.0, 806.0, 6.0, 4.0, 1.2],     # stavebniny: štěrk
	["cihly", -304.0, 803.0, 4.0, 2.0, 1.1],     # stavebniny: cihly na paletě
	["prkna", -290.0, 802.0, 8.0, 3.0, 1.6],     # stavebniny: prkna (stoh)
	["poleno", -276.0, 800.0, 5.0, 2.0, 1.0],    # stavebniny: palivové dříví
	["kulatina", -236.0, 694.0, 12.0, 4.0, 1.2], # pila: kulatina na dvoře
	["rezivo", -218.0, 698.0, 6.0, 4.0, 1.5],    # pila: řezivo (hranoly)
	["rezivo", -214.0, 712.0, 5.0, 3.0, 1.4],    # pila: řezivo (desky)
	["piliny", -226.0, 690.0, 4.0, 3.0, 0.8],    # pila: piliny
	["poleno", -250.0, 688.0, 7.0, 3.0, 1.1],    # pila: štípané dříví
]

const COLORS := {
	"pisek": Color(0.78, 0.68, 0.48), "sterk": Color(0.55, 0.55, 0.52), "cihly": Color(0.6, 0.28, 0.2),
	"prkna": Color(0.88, 0.74, 0.5), "poleno": Color(0.5, 0.36, 0.22), "kulatina": Color(0.45, 0.3, 0.18),
	"rezivo": Color(0.8, 0.66, 0.42), "piliny": Color(0.85, 0.75, 0.55),
}
const PALLET := Color(0.5, 0.38, 0.22)


## Postaví celý dvůr jako jeden uzel s jedním meshem (nízký počet draw callů).
static func build(terrain: Terrain) -> Node3D:
	var root := DvurStavebnin.new()
	root.name = "DvurStavebnin"
	var k := MeshKit.new()
	for p in PILES:
		_pile(k, terrain, p)
	MeshKit.mesh_instance(root, k.commit(MeshKit.vc_material(0.95)), 260.0)
	return root


static func _pile(k: MeshKit, terrain: Terrain, p: Array) -> void:
	var kind: String = p[0]
	var x: float = p[1]
	var z: float = p[2]
	var ln: float = p[3]
	var wd: float = p[4]
	var h: float = p[5]
	var col: Color = COLORS[kind]
	var base := Vector3(x, terrain.height_at(x, z), z)
	if kind == "pisek" or kind == "sterk" or kind == "piliny":
		# sypaný kužel
		k.cylinder(base + Vector3(0, h * 0.5, 0), 0.3, ln * 0.5, h, col)
		return
	if kind == "kulatina":
		# kulatina: vrstvy ležících kmenů, poleno-kulatina na podkladu
		var r := 0.45
		for row in range(2):
			for i in range(3):
				var off := Vector3((i - 1) * 0.95, 0.25 + row * 0.9, 0)
				k.cylinder(base + off, r, r, ln, col, Vector3(0, 0, PI * 0.5))
		return
	# hromada na paletě: podklad + stoh
	k.box(base + Vector3(0, 0.06, 0), Vector3(ln, 0.12, wd), PALLET)
	k.box(base + Vector3(0, 0.12 + h * 0.5, 0), Vector3(ln * 0.92, h, wd * 0.92), col)
