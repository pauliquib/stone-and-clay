## Obyvatelé Dukelčic – smyšlené postavy (jméno, věk, povolání, povaha, vzhled, oblíbená témata).
## Jména jsou vymyšlená a nesmí odkazovat na skutečné obyvatele obce (viz README → Právní zásady obsahu).
## Každý vesničan (Villager) dostane jednu postavu podle pořadí; povaha řídí pozdravy, odpovědi v rozhovoru
## (Dialog) i to, jak silně reaguje na pověst hráče (Reputation).
##
## Povahy (`trait`):
##   pratelsky  – usměvavý, rád pomůže          drbna    – ví všechno o všech, ráda to řekne
##   bruclavy   – nerudný, stěžuje si           prisny   – na pořádek, hned by volal policii
##   veselak    – vtipálek, rád si připije      plachy   – odpovídá krátce, nerad mluví s cizími
##   moudry     – starý, vypráví, jak bývalo    mlady    – mladý, mluví hovorově, spěchá
class_name Characters
extends RefCounted

const TRAITS := {
	"pratelsky": {"name": "přátelský", "tolerance": 1.2},
	"drbna": {"name": "drbna", "tolerance": 1.0},
	"bruclavy": {"name": "bručoun", "tolerance": 0.7},
	"prisny": {"name": "přísný", "tolerance": 0.5},
	"veselak": {"name": "veselá kopa", "tolerance": 1.5},
	"plachy": {"name": "plachý", "tolerance": 0.9},
	"moudry": {"name": "moudrý", "tolerance": 1.1},
	"mlady": {"name": "mladý", "tolerance": 1.3},
}

## Postavy. look: shirt, pants, hair (barvy), style (Humanoid.hair_style), female, moustache, beard, hat,
## fat (0..1), size (scale), sleeves (dlouhé rukávy), skin (0 světlá .. 1 opálená).
## speed = chůze m/s, topics = oblíbená témata (Dialog), hobby = krátká věta o sobě.
const PROFILES := [
	{"name": "Bohuslav Křemínek", "age": 71, "job": "důchodce, bývalý traktorista", "trait": "moudry",
		"hobby": "Za mých mladých let jsem oral celé JZD na starém strojáku.", "topics": ["pole", "traktor", "pocasi"],
		"look": {"shirt": Color(0.42, 0.4, 0.33), "pants": Color(0.22, 0.2, 0.17), "hair": Color(0.82, 0.82, 0.8), "style": 1,
			"moustache": true, "hat": true, "fat": 0.35, "size": 0.95, "sleeves": true, "skin": 0.6}, "speed": 1.0},
	{"name": "Anežka Pupíková", "age": 64, "job": "důchodkyně, zahrádkářka", "trait": "drbna",
		"hobby": "Mám nejhezčí jiřiny v celé vsi, to ví každý.", "topics": ["zahrada", "drby", "kostel"],
		"look": {"shirt": Color(0.7, 0.35, 0.45), "pants": Color(0.28, 0.24, 0.3), "hair": Color(0.75, 0.73, 0.7), "style": 2,
			"female": true, "fat": 0.45, "size": 0.93, "sleeves": true, "skin": 0.2}, "speed": 1.05},
	{"name": "Radek Šťovíček", "age": 38, "job": "zedník", "trait": "veselak",
		"hobby": "Po šichtě jedno orosený, to je základ.", "topics": ["pivo", "stavba", "fotbal"],
		"look": {"shirt": Color(0.85, 0.55, 0.15), "pants": Color(0.25, 0.28, 0.35), "hair": Color(0.2, 0.13, 0.07), "style": 3,
			"fat": 0.3, "size": 1.04, "skin": 0.7}, "speed": 1.5},
	{"name": "Květoslava Mrázková", "age": 52, "job": "účetní na obecním úřadě", "trait": "prisny",
		"hobby": "Pořádek musí být, i v papírech.", "topics": ["urad", "poradek", "policie"],
		"look": {"shirt": Color(0.3, 0.33, 0.55), "pants": Color(0.18, 0.18, 0.22), "hair": Color(0.3, 0.18, 0.1), "style": 2,
			"female": true, "fat": 0.15, "size": 0.97, "sleeves": true, "skin": 0.1}, "speed": 1.35},
	{"name": "Oldřich Pazderka", "age": 58, "job": "myslivec a včelař", "trait": "bruclavy",
		"hobby": "Divočáci mi zase rozryli louku. Holota.", "topics": ["les", "zver", "vcely"],
		"look": {"shirt": Color(0.3, 0.36, 0.22), "pants": Color(0.25, 0.22, 0.15), "hair": Color(0.45, 0.42, 0.38), "style": 0,
			"beard": true, "hat": true, "fat": 0.2, "size": 1.02, "sleeves": true, "skin": 0.5}, "speed": 1.25},
	{"name": "Veronika Bubeníková", "age": 29, "job": "učitelka v mateřské škole", "trait": "pratelsky",
		"hobby": "Děti jsou poklad, i když někdy řvou jak tur.", "topics": ["deti", "skola", "zahrada"],
		"look": {"shirt": Color(0.95, 0.75, 0.3), "pants": Color(0.2, 0.3, 0.5), "hair": Color(0.6, 0.45, 0.22), "style": 2,
			"female": true, "size": 0.96, "skin": 0.25}, "speed": 1.45},
	{"name": "Luboš Kadeřábek", "age": 45, "job": "řidič autobusu", "trait": "bruclavy",
		"hobby": "Ty silnice jsou samá díra, to vám povím.", "topics": ["auta", "silnice", "policie"],
		"look": {"shirt": Color(0.55, 0.6, 0.65), "pants": Color(0.2, 0.2, 0.24), "hair": Color(0.12, 0.09, 0.07), "style": 1,
			"moustache": true, "fat": 0.55, "size": 1.0, "skin": 0.35}, "speed": 1.15},
	{"name": "Tadeáš Holoubek", "age": 17, "job": "student (učeň automechanik)", "trait": "mlady",
		"hobby": "Jednou si koupím pořádnou káru, uvidíte.", "topics": ["auta", "motorka", "mobil"],
		"look": {"shirt": Color(0.1, 0.1, 0.12), "pants": Color(0.25, 0.3, 0.45), "hair": Color(0.25, 0.16, 0.08), "style": 0,
			"size": 0.98, "skin": 0.2}, "speed": 1.7},
	{"name": "Marie Šimáčková", "age": 77, "job": "důchodkyně", "trait": "moudry",
		"hobby": "Dřív se tady tancovalo na návsi každou neděli.", "topics": ["kostel", "zahrada", "pocasi"],
		"look": {"shirt": Color(0.35, 0.3, 0.4), "pants": Color(0.25, 0.2, 0.25), "hair": Color(0.88, 0.88, 0.86), "style": 2,
			"female": true, "fat": 0.3, "size": 0.9, "sleeves": true, "skin": 0.3}, "speed": 0.9},
	{"name": "Jaromír Ořech", "age": 49, "job": "vinař – hobby", "trait": "veselak",
		"hobby": "Letos bude ročník jak z pohádky!", "topics": ["vino", "pivo", "pocasi"],
		"look": {"shirt": Color(0.55, 0.12, 0.18), "pants": Color(0.22, 0.2, 0.2), "hair": Color(0.35, 0.3, 0.27), "style": 1,
			"moustache": true, "fat": 0.6, "size": 1.0, "skin": 0.65}, "speed": 1.2},
	{"name": "Ilona Kopřivová", "age": 41, "job": "pracovnice pošty v okresním městě", "trait": "drbna",
		"hobby": "Na poště se dozvíte všechno dřív než v novinách.", "topics": ["drby", "urad", "obchod"],
		"look": {"shirt": Color(0.2, 0.55, 0.55), "pants": Color(0.18, 0.18, 0.2), "hair": Color(0.08, 0.06, 0.05), "style": 2,
			"female": true, "fat": 0.2, "size": 0.97, "skin": 0.2}, "speed": 1.35},
	{"name": "Emil Prskavec", "age": 66, "job": "bývalý hasič", "trait": "pratelsky",
		"hobby": "U hasičů jsem byl čtyřicet let. Soutěže, to byla sláva.", "topics": ["hasici", "pivo", "fotbal"],
		"look": {"shirt": Color(0.7, 0.18, 0.12), "pants": Color(0.15, 0.17, 0.25), "hair": Color(0.7, 0.7, 0.68), "style": 0,
			"moustache": true, "fat": 0.4, "size": 1.02, "skin": 0.45}, "speed": 1.1},
	{"name": "Petra Hrušková", "age": 34, "job": "zdravotní sestra", "trait": "prisny",
		"hobby": "V nemocnici vidím, co dělá alkohol za volantem.", "topics": ["zdravi", "deti", "policie"],
		"look": {"shirt": Color(0.85, 0.87, 0.9), "pants": Color(0.3, 0.4, 0.55), "hair": Color(0.55, 0.38, 0.18), "style": 2,
			"female": true, "size": 0.99, "skin": 0.15}, "speed": 1.5},
	{"name": "Vavřinec Stonožka", "age": 55, "job": "zemědělec", "trait": "plachy",
		"hobby": "Pole se samo neobdělá.", "topics": ["pole", "traktor", "pocasi"],
		"look": {"shirt": Color(0.35, 0.45, 0.3), "pants": Color(0.3, 0.25, 0.15), "hair": Color(0.3, 0.25, 0.18), "style": 0,
			"beard": true, "hat": true, "fat": 0.15, "size": 1.05, "sleeves": true, "skin": 0.75}, "speed": 1.2},
	{"name": "Dominika Zelená", "age": 22, "job": "studentka vysoké školy", "trait": "mlady",
		"hobby": "Na víkend jezdím domů, jinak jsem v Brně.", "topics": ["skola", "mobil", "pocasi"],
		"look": {"shirt": Color(0.6, 0.35, 0.7), "pants": Color(0.1, 0.1, 0.14), "hair": Color(0.15, 0.1, 0.07), "style": 2,
			"female": true, "size": 0.95, "skin": 0.2}, "speed": 1.6},
	{"name": "Ctibor Ploužek", "age": 60, "job": "hospodský povaleč", "trait": "veselak",
		"hobby": "Život je krátkej a pivo je dobrý.", "topics": ["pivo", "drby", "fotbal"],
		"look": {"shirt": Color(0.5, 0.45, 0.35), "pants": Color(0.25, 0.23, 0.2), "hair": Color(0.5, 0.48, 0.45), "style": 1,
			"beard": true, "fat": 0.75, "size": 1.0, "skin": 0.55}, "speed": 1.0},
	{"name": "Hedvika Bartoňová", "age": 47, "job": "kadeřnice", "trait": "drbna",
		"hobby": "U mě v křesle se každá rozpovídá.", "topics": ["drby", "zahrada", "obchod"],
		"look": {"shirt": Color(0.9, 0.4, 0.55), "pants": Color(0.2, 0.2, 0.25), "hair": Color(0.65, 0.2, 0.15), "style": 2,
			"female": true, "fat": 0.25, "size": 0.96, "skin": 0.3}, "speed": 1.3},
	{"name": "Bořivoj Slámka", "age": 69, "job": "důchodce, rybář", "trait": "plachy",
		"hobby": "U vody je klid. Lidi moc mluví.", "topics": ["ryby", "pocasi", "les"],
		"look": {"shirt": Color(0.3, 0.4, 0.45), "pants": Color(0.28, 0.26, 0.2), "hair": Color(0.78, 0.78, 0.76), "style": 0,
			"hat": true, "fat": 0.2, "size": 0.97, "sleeves": true, "skin": 0.55}, "speed": 1.0},
	{"name": "Sabina Koláčková", "age": 36, "job": "cukrářka", "trait": "pratelsky",
		"hobby": "V sobotu peču koláče, přijďte ochutnat.", "topics": ["jidlo", "deti", "obchod"],
		"look": {"shirt": Color(0.95, 0.9, 0.8), "pants": Color(0.35, 0.25, 0.2), "hair": Color(0.8, 0.65, 0.35), "style": 2,
			"female": true, "fat": 0.35, "size": 0.95, "skin": 0.2}, "speed": 1.3},
	{"name": "Zbyněk Pivoňka", "age": 43, "job": "elektrikář", "trait": "bruclavy",
		"hobby": "Všechno je dneska z Číny a za rok to odejde.", "topics": ["prace", "auta", "urad"],
		"look": {"shirt": Color(0.25, 0.35, 0.6), "pants": Color(0.2, 0.22, 0.28), "hair": Color(0.2, 0.15, 0.1), "style": 3,
			"moustache": true, "fat": 0.25, "size": 1.03, "skin": 0.4}, "speed": 1.4},
	{"name": "Jindřiška Vlčková", "age": 81, "job": "nejstarší obyvatelka vsi", "trait": "moudry",
		"hobby": "Pamatuju si ještě, kdy tu jezdily jen koňské povozy.", "topics": ["kun", "kostel", "drby"],
		"look": {"shirt": Color(0.25, 0.25, 0.3), "pants": Color(0.2, 0.18, 0.2), "hair": Color(0.92, 0.92, 0.9), "style": 2,
			"female": true, "fat": 0.2, "size": 0.88, "sleeves": true, "skin": 0.3}, "speed": 0.8},
	{"name": "Matěj Rybníček", "age": 26, "job": "programátor z domova", "trait": "plachy",
		"hobby": "Internet tu občas vypadne, to je největší problém vsi.", "topics": ["mobil", "prace", "pocasi"],
		"look": {"shirt": Color(0.35, 0.35, 0.38), "pants": Color(0.18, 0.2, 0.3), "hair": Color(0.3, 0.2, 0.1), "style": 0,
			"beard": true, "size": 1.01, "skin": 0.1}, "speed": 1.45},
	{"name": "Blažena Hromádková", "age": 58, "job": "chovatelka slepic", "trait": "bruclavy",
		"hobby": "Zase mi liška vybrala kurník.", "topics": ["zvirata", "zahrada", "drby"],
		"look": {"shirt": Color(0.55, 0.5, 0.25), "pants": Color(0.3, 0.26, 0.2), "hair": Color(0.45, 0.3, 0.2), "style": 2,
			"female": true, "fat": 0.5, "size": 0.94, "sleeves": true, "skin": 0.45}, "speed": 1.1},
	{"name": "Leopold Čiháček", "age": 51, "job": "kostelník", "trait": "prisny",
		"hobby": "V neděli v deset je mše, přijďte.", "topics": ["kostel", "poradek", "pocasi"],
		"look": {"shirt": Color(0.15, 0.15, 0.17), "pants": Color(0.15, 0.15, 0.17), "hair": Color(0.25, 0.22, 0.2), "style": 1,
			"size": 0.99, "sleeves": true, "skin": 0.15}, "speed": 1.2},
	{"name": "Kristýna Mlynářová", "age": 31, "job": "maminka na mateřské", "trait": "pratelsky",
		"hobby": "Malý konečně spí, tak jsem si vyšla na vzduch.", "topics": ["deti", "obchod", "pocasi"],
		"look": {"shirt": Color(0.45, 0.7, 0.55), "pants": Color(0.25, 0.28, 0.4), "hair": Color(0.3, 0.2, 0.12), "style": 2,
			"female": true, "size": 0.97, "skin": 0.2}, "speed": 1.25},
	{"name": "Evžen Trnka", "age": 39, "job": "trenér místních fotbalistů", "trait": "veselak",
		"hobby": "V neděli hrajem se sousední vsí, přijď fandit!", "topics": ["fotbal", "pivo", "deti"],
		"look": {"shirt": Color(0.15, 0.45, 0.2), "pants": Color(0.1, 0.1, 0.12), "hair": Color(0.15, 0.1, 0.06), "style": 3,
			"size": 1.04, "skin": 0.5}, "speed": 1.6},
	{"name": "Svatopluk Žabka", "age": 62, "job": "bývalý starosta sousední vsi", "trait": "moudry",
		"hobby": "Politika? Ta mě už nebaví. Ale radu dám.", "topics": ["urad", "poradek", "drby"],
		"look": {"shirt": Color(0.4, 0.3, 0.25), "pants": Color(0.22, 0.2, 0.2), "hair": Color(0.65, 0.63, 0.6), "style": 1,
			"moustache": true, "fat": 0.45, "size": 1.0, "sleeves": true, "skin": 0.35}, "speed": 1.05},
	{"name": "Ladislav Hrubý", "age": 67, "job": "důchodce, zahrádkář na okraji lesa", "trait": "plachy",
		"hobby": "Záhon mám za chatou u lesa, chodím tam každý den, ať se nenudím.", "topics": ["zahrada", "les", "pocasi"],
		"look": {"shirt": Color(0.35, 0.5, 0.3), "pants": Color(0.3, 0.27, 0.2), "hair": Color(0.6, 0.6, 0.58), "style": 1,
			"beard": true, "hat": true, "fat": 0.3, "size": 0.98, "sleeves": true, "skin": 0.45}, "speed": 0.9},
	{"name": "Nikola Dřínková", "age": 19, "job": "brigádnice v sadu", "trait": "mlady",
		"hobby": "Trhám jablka a šetřím na řidičák.", "topics": ["jablka", "auta", "mobil"],
		"look": {"shirt": Color(0.9, 0.5, 0.3), "pants": Color(0.3, 0.35, 0.5), "hair": Color(0.7, 0.55, 0.3), "style": 2,
			"female": true, "size": 0.94, "skin": 0.3}, "speed": 1.55},
]


static func count() -> int:
	return PROFILES.size()


static func profile(i: int) -> Dictionary:
	return PROFILES[i % PROFILES.size()]


static func trait_name(t: String) -> String:
	return TRAITS.get(t, {}).get("name", t)


## Jak moc postavě vadí špatná pověst hráče (1 = normálně, < 1 citlivější).
static func tolerance(t: String) -> float:
	return float(TRAITS.get(t, {}).get("tolerance", 1.0))


## Křestní jméno (první slovo).
static func first_name(p: Dictionary) -> String:
	return String(p["name"]).split(" ")[0]


## Nastaví vzhled postavy (Humanoid) podle profilu – volat před přidáním do stromu.
static func apply_look(h: Humanoid, p: Dictionary) -> void:
	var l: Dictionary = p.get("look", {})
	h.shirt = l.get("shirt", h.shirt)
	h.pants = l.get("pants", h.pants)
	h.hair = l.get("hair", h.hair)
	h.hair_style = int(l.get("style", 0))
	h.female = bool(l.get("female", false))
	h.moustache = bool(l.get("moustache", false))
	h.beard = bool(l.get("beard", false))
	h.hat = bool(l.get("hat", false))
	h.long_sleeves = bool(l.get("sleeves", false))
	h.fat = float(l.get("fat", 0.0))
	h.scale_factor = float(l.get("size", 1.0))
	h.skin = Color(0.97, 0.8, 0.68).lerp(Color(0.82, 0.58, 0.42), float(l.get("skin", 0.3)))
