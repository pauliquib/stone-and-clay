## Rozhovor s postavami – odpovědi na volný text, který hráč „řekne“ na ulici (T), pozdravy a drby.
## Bez sítě a bez jazykového modelu: text se normalizuje (malá písmena, bez diakritiky), rozpozná se
## záměr podle klíčových slov (pozdrav, otázka na cestu, čas, počasí, policii, urážka…) a odpověď se
## složí podle povahy postavy (Characters.TRAITS), její nálady vůči hráči (Persona), pověsti hráče
## (Reputation), jeho promile a stavu světa (čas, počasí, otevírací doby, silniční kontrola).
##
## ctx (staví World.dialog_context): persona, mood, met, attitude (−100..100), rep, tier, promile, in_car,
## shout, hour, time_text, weather, raining, snowing, temp, places {klíč → {name, open, hours, dir, dist}},
## friendship (0..100), respect (−100..100 komunity postavy), police_cp, police_dir, quest_offers [texty], quest_active (název nebo ""), last_offense, role, place
## Výsledek respond(): {text, intent, mood (změna nálady), rep (změna pověsti), rep_text, police_hint,
## fine (Kč), call_police}
## Rozšířený rozhovor: data v `DialogData` (slova navíc, rady „jak na to“, drby o sousedech, otázky zpět, vtipy)
## a `DialogThemes` (témata s odpověďmi podle povahy, podmínek a ročního období). Krátká paměť rozhovoru
## (Persona.talk) hlídá, aby se postava neopakovala, a umožní navazující „a proč?“, „a dál?“, „a ty?“.
## Další pole ctx pro rozšíření (World._talk_context): now_min, day, season, weekday, holiday, fog, wind,
## snow_cover, cloud, daylight, money, events, carry, recent
class_name Dialog
extends RefCounted

const _DIA := {"á": "a", "č": "c", "ď": "d", "é": "e", "ě": "e", "í": "i", "ň": "n", "ó": "o", "ř": "r",
	"š": "s", "ť": "t", "ú": "u", "ů": "u", "ý": "y", "ž": "z", "ä": "a", "ö": "o", "ü": "u"}

## Klíčová slova (bez diakritiky, začátek slova). Pořadí v INTENT_ORDER = priorita.
const WORDS := {
	"threat": ["zabiju", "zabiji", "zmlatim", "nabiju", "rozbiju ti", "podpalim", "podrezu", "zabit te", "dam ti par"],
	"insult": ["debil", "kreten", "idiot", "blbec", "kurv", "hovad", "vul ", "prdel", "sracka", "zmrd", "pica", "picus", "picovin",
		"kokot", "hajzl", "cune", "trotl", "magor", "dement", "buzn", "cumil", "sraci", "vyser", "posr", "smrad",
		"osklivy", "osklivk", "nemehl", "tupec", "jdi do haje", "drz hubu", "zavri hubu", "sklapni", "vypadni"],
	"sorry": ["promin", "omlouv", "pardon", "sorry", "nezlob", "nechtel jsem"],
	"name": ["jak se jmenuj", "kdo jsi", "kdo jste", "tve jmeno", "vase jmeno", "jmenujes", "jmenujete", "jak ti rikaj",
		"jak vam rikaj", "predstav"],
	"introduce": ["jmenuju se", "jmenuji se", "ja jsem ", "rikaji mi", "rikaj mi"],
	"howareyou": ["jak se mas", "jak se mate", "jak se vede", "jak se dari", "jak to jde", "jak zije", "co ty",
		"jak se citis", "jak se citite"],
	"age": ["kolik ti je", "kolik je vam", "kolik mate let", "kolik mas let", "jak jsi stary", "jak jste stary",
		"jak jsi stara", "jak jste stara"],
	"job": ["co delas", "co delate", "kde pracuj", "pracujes", "pracujete", "zamestnan", "cim jsi", "cim jste",
		"tvoje prace", "vase prace", "cim se zivi"],
	"time": ["kolik je hodin", "kolik je ted", "kolik mame hodin", "cas ", "jaky je cas", "hodin je"],
	"hours": ["otevren", "oteviraj", "zavira", "zavren", "do kolika", "od kolika", "oteviraci"],
	"where": ["kde je", "kde najdu", "jak se dostanu", "kudy", "cesta do", "cesta k", "kde mate", "kde bych", "kam mam",
		"navigu", "ukaz mi cestu", "jak se dojde", "jak dojdu", "kde se da"],
	"lost": ["ztratil jsem se", "zabloudil", "kde to jsem", "kde jsem", "nevim kde", "jak se dostanu domu", "cesta domu"],
	"sleep": ["vyspat", "vyspim", "prespat", "prespim", "nocleh", "kde spat", "kde se da spat", "spacak", "postel",
		"unaven", "ospal"],
	"police": ["polic", "fizl", "benga", "kontrol", "hlidk", "radar", "foukat", "fouka"],
	"news": ["co je noveho", "novink", "drb", "co se deje", "co se povida", "co se rika", "vis neco", "slysel",
		"slysela", "zajimaveho", "co noveho"],
	"quest": ["pomoc", "pomuz", "potrebuj", "ukol", "muzu pro", "muzu vam", "muzu ti", "nejakou praci", "chces neco",
		"chcete neco", "neco sehnat"],
	"invite": ["pojd na pivo", "pojdte na pivo", "dame pivo", "dame si", "zvu te", "zvu vas", "pozvu", "napijem se",
		"dame panaka", "pojd se napit"],
	"drink": ["pivo", "pivko", "napit", "slivovic", "panak", "chlast", "vino", "kalit", "pit ", "hospod", "zizen",
		"alkohol", "rum", "vodk"],
	"food": ["hlad", "jidlo", "najist", "jist ", "rohlik", "gulas", "obed", "vecere", "snidan"],
	"money": ["pujc", "penize", "penez", "prachy", "kacky", "dej mi", "daruj", "korun", "dluh"],
	"joke": ["vtip", "zasmat", "srand", "pobav", "rekni neco vesel"],
	"flirt": ["miluju", "miluji", "rande", "pusu", "libis se mi", "libite se mi", "krask", "sexy", "chodit se mnou",
		"vezmes si me"],
	"reputation": ["co si o mne mysli", "co si o me mysli", "jakou mam povest", "co o mne rikaj", "co o me rikaj",
		"mas me rad", "mate me rad", "znas me", "znate me", "jak me lidi berou", "povest"],
	"drunk_admit": ["jsem opil", "jsem namazan", "jsem nametenej", "mam v sobe", "mam upito", "jsem v lihu",
		"jsem ozral"],
	"compliment": ["hezk", "pekn", "krasn", "sikovn", "fajn", "super", "mas pravdu", "mate pravdu", "sympat", "bezva",
		"skvel", "hodny", "hodna", "laskav"],
	"thanks": ["dik", "dekuj", "diky", "dikes", "zaplat panbu"],
	"weather": ["pocasi", "prsi", "prset", "zima ", "zimu", "horko", "teplo", "snih", "snezi", "slunce", "slunic",
		"mlha", "bourk", "vitr", "fouka", "mrzne", "mraz", "dest"],
	"items": ["houb", "hrib", "dukat", "zalud", "poklad", "jablk", "sbir"],
	"horse": ["kun ", "kone", "konik", "jezdit na"],
	"goodbye": ["nashle", "na shledanou", "sbohem", "mej se", "mejte se", "dobrou noc", "uvidime se", "tak zatim",
		"pa pa", "cau cau", "musim jit", "jdu dal"],
	"greeting": ["ahoj", "cau", "cus", "nazdar", "zdravim", "dobry den", "dobre rano", "dobry vecer", "dobre odpoledne",
		"zdar", "servus", "cest praci", "zdarec", "nazdarek", "hola", "hej", "haloo", "halo"],
	"yes": ["ano", "jo ", "jasne", "urcite", "presne", "souhlas", "dobre ", "ok ", "oki"],
	"no": ["ne ", "nee", "nikdy", "vubec", "nechci"],
}
const INTENT_ORDER := ["threat", "insult", "sorry", "lost", "name", "introduce", "howareyou", "age", "job", "time",
	"hours", "where", "sleep", "police", "news", "quest", "invite", "drunk_admit", "drink", "food", "money", "joke",
	"flirt", "reputation", "weather", "compliment", "thanks", "items", "horse", "topic", "goodbye", "greeting",
	"yes", "no"]

const PLACE_WORDS := {
	"hospoda": ["hospod", "pivnic", "hospu", "knajp", "putyk", "u hriste", "hostinsk"],
	"obchod": ["obchod", "potravin", "samoobsluh", "koloni", "nakoup", "kram", "prodavack"],
	"palenice": ["palenic", "palirn", "palic", "u kotla"],
	"sklep": ["sklep", "vinar", "degust", "jílk"],
	"chata": ["chat", "myslivec", "myslivn"],
	"urad": ["urad", "starost", "obecni"],
	"domov": ["domu ", "domov", "muj dum", "doma ", "bydlim", "muj byt", "do bytu", "bytovk"],
	"deda": ["ded", "vomack"],
}

## Témata z profilu postavy (Characters.PROFILES[*].topics) → klíčová slova a nadšené odpovědi.
const TOPICS := {
	"pole": [["pole", "obil", "psenic", "kukuric", "sklizen", "zne"], ["Letos to na poli vypadá slušně, jen kdyby víc zapršelo.", "Pole, to je moje. Každá hrouda má svou historii."]],
	"traktor": [["traktor", "kombajn"], ["Starý traktor je starý traktor. Ty nové traktory mají víc elektroniky než rozumu.", "Traktor ti jednou řekne víc než člověk."]],
	"zahrada": [["zahrad", "kvetin", "zelenin", "rajcat", "jirin", "zalev", "zahon"], ["Na zahradě mám rajčata jak pěsti!", "Zahrada je lék na všechno. Hlavně na manžela."]],
	"kostel": [["kostel", "kaplick", "mse", "farar", "bozi"], ["V neděli v deset je mše, přijď.", "Kaplička u cesty pamatuje ještě moji babičku."]],
	"fotbal": [["fotbal", "zapas", "hrist", "gol", "mic "], ["V neděli je zápas, přijď fandit na hřiště!", "Náš útok je slabý, ale srdce máme velký."]],
	"les": [["les", "lesy", "strom", "drev"], ["Les je teď samá kůrovcová paseka, škoda ho.", "V lese je klid. Jen pozor na divočáky."]],
	"zver": [["srn", "divocak", "zajic", "zver", "lov", "myslivost"], ["Srnky chodí za soumraku k lesu, divočáci v noci do polí.", "Divočáci mi rozryli louku. Holota."]],
	"vcely": [["vcel", "med", "ul "], ["Včely letos dají pěkný med, když nebude mrznout.", "K úlům moc nechoď, bodají."]],
	"deti": [["det", "skolk", "mimin", "kluk", "holk"], ["Děti jsou poklad, i když někdy řvou jak tur.", "Ve školce je teď dvacet dětí, to je na vesnici hodně!"]],
	"skola": [["skol", "studi", "zkousk", "univerz", "ucen"], ["Studium je fuška, ale jednou se to vyplatí.", "Škola? Radši mi to nepřipomínej."]],
	"auta": [["aut", "kar", "motor ", "oktavk", "fabick", "ridicak"], ["Oktávka je nejlepší auto, co kdy vzniklo, a basta.", "Auto musí mít duši, ne jen displej."]],
	"motorka": [["motork", "javor", "jawa", "kyvack"], ["Kývačka je legenda! Takovou má u vás děda, ne?", "Na motorce je svoboda. A mouchy v zubech."]],
	"mobil": [["mobil", "telefon", "internet", "signal", "wifi", "pocitac", "hry"], ["Signál tu je jen u kapličky, fakt.", "Internet tu vypadává každou bouřku."]],
	"vino": [["vin", "sklep", "hrozn", "ryzlink", "frankovk"], ["Letošní ročník bude jak z pohádky!", "Víno se nepije, víno se vychutnává."]],
	"pivo": [["pivo", "pivk", "desitk", "dvanactk", "orosen"], ["Láďa v hospodě točí nejlepší dvanáctku v okolí.", "Pivo je tekutý chleba, to ví každý."]],
	"stavba": [["stavb", "zed", "cihl", "beton", "stavet"], ["Stavím teď garáž sousedovi, za měsíc hotovo. Snad.", "Cihla na cihlu, tak se staví domy i život."]],
	"drby": [["drb", "soused", "novink"], ["Hromádková prý zase viděla lišku u kurníku. A Ploužek byl v hospodě do tří!", "Nic neříkám, ale na úřadě se prý bude něco dít…"]],
	"urad": [["urad", "starost", "obec", "zastupitel", "papir"], ["Na úřadě je otevřeno od sedmi do pěti. Starosta tam bývá dopoledne.", "Úředničina, to je věda."]],
	"poradek": [["poradek", "zakon", "pravid", "slusnost"], ["Pořádek musí být. Kdo se chová slušně, nemá se čeho bát.", "Zákony jsou od toho, aby se dodržovaly."]],
	"policie": [["polic", "kontrol"], ["Policajti tu teď jezdí častěji. A dobře dělají.", "Radši ať kontrolují, než aby se něco stalo."]],
	"hasici": [["hasic", "stricka", "pozar", "soutez"], ["Hasičská soutěž je v červnu, to je sláva!", "Čtyřicet let u hasičů, to se nezapomíná."]],
	"zdravi": [["zdravi", "nemoc", "doktor", "lekar", "nemocnic"], ["Hlavně pij vodu a spi. A nekuř.", "V nemocnici vidím, co dělá alkohol za volantem."]],
	"jidlo": [["jidl", "kolac", "pec", "dort", "buchty"], ["V sobotu peču koláče – tvarohové, povidlové, makové.", "Dobré jídlo spraví náladu."]],
	"ryby": [["ryb", "kapr", "udic", "rybnik"], ["Kapři teď moc neberou. Zkus na kukuřici.", "U vody je klid."]],
	"kun": [["kun", "kone", "konik", "povoz"], ["Koně, to byla jiná doprava. Nesmrděli benzínem.", "Kůň je chytřejší, než si lidi myslí."]],
	"jablka": [["jablk", "sad", "tresn", "hrusk"], ["Jablka letos pěkně rodí, pod stromy v zahradách jich je spousta.", "V sadu je práce až nad hlavu."]],
	"zvirata": [["slepic", "kurnik", "lisk", "kocka", "pes ", "psi"], ["Zase mi liška vybrala kurník!", "Slepice jsou hloupé, ale vajíčka dělají dobrá."]],
	"prace": [["prac", "prace", "sichta", "vyplat"], ["Práce je dost, jen peníze nejsou.", "Dělám, co se dá."]],
	"pocasi": [["pocasi"], ["Počasí? To se dneska nedá odhadnout, pořád se mění.", "Za mých mladých let byly zimy pořádné."]],
	"obchod": [["obchod", "nakup", "potravin"], ["V Potravinách mají čerstvé rohlíky od šesti.", "Ceny zase stouply, to je hrůza."]],
}

const JOKES := [
	"Víš, proč má traktor velká zadní kola? Aby se mu dobře couvalo z hospody!",
	"Potká farmář souseda: „Mé slepice přestaly snášet.“ „A zkoušel jsi jim pustit rádio?“ „Jo, ale jen si stěžují na cenu vajec.“",
	"Jak poznáš, že je vesničan na dovolené? Má vypnutou sekačku.",
	"Přijde houbař do lesa a hřib na něj: „Dneska ne, mám volno.“",
	"Starosta slíbil novou silnici. Díry už máme, teď čekáme na asfalt.",
]


# ====================================================================== pomocné

## Malá písmena, bez diakritiky a interpunkce, mezery kolem (hledá se " klíč").
static func norm(t: String) -> String:
	var s := t.to_lower()
	var out := ""
	for ch in s:
		out += _DIA.get(ch, ch)
	var re := RegEx.new()
	re.compile("[^a-z0-9 ]")
	out = re.sub(out, " ", true)
	return " " + " ".join(out.split(" ", false)) + " "


static func _has(n: String, keys: Array) -> bool:
	for k in keys:
		if n.contains(" " + k):
			return true
	return false


static func _pick(a: Array) -> String:
	return a[randi() % a.size()]


static func _g(ctx: Dictionary, male: String, female: String) -> String:
	return female if _female(_prof(ctx)) else male


## Žena? Příznak je u vesničanů ve vzhledu (`look.female`), u ostatních přímo v profilu.
static func _female(pr: Dictionary) -> bool:
	return bool(pr.get("female", pr.get("look", {}).get("female", false)))


static func _prof(ctx: Dictionary) -> Dictionary:
	var p: Persona = ctx.get("persona")
	return p.profile if p else {}


static func _trait(ctx: Dictionary) -> String:
	return String(_prof(ctx).get("trait", "pratelsky"))


## Oslovení hráče podle povahy.
static func _voc(ctx: Dictionary) -> String:
	match _trait(ctx):
		"moudry": return "synku"
		"mlady": return "kámo"
		"bruclavy": return "mladej"
		"drbna": return "zlatíčko"
		"veselak", "pratelsky": return "sousede"
	return ""


static func _fill(t: String, ctx: Dictionary) -> String:
	var pr := _prof(ctx)
	var v := _voc(ctx)
	if t.contains("{"):
		t = _fill_ext(t, ctx)
	t = t.replace("{voc}", v).replace(", !", "!").replace(", .", ".").replace(" ,", ",")
	t = t.replace("{name}", String(pr.get("name", ""))).replace("{first}", String(pr.get("name", "")).split(" ")[0])
	var hobby := String(pr.get("hobby", ""))
	if ItemsDB.adult_on and pr.has("hobby_adult"):           # M4.8: jedna věta jen při zapnuté volbě pro dospělé
		hobby += " " + String(pr["hobby_adult"])
	t = t.replace("{job}", String(pr.get("job", ""))).replace("{hobby}", hobby)
	# prázdné oslovení: „Ahoj, !“ → „Ahoj!“
	t = t.replace(", !", "!").replace(", ?", "?").replace(", .", ".").replace(",  ", ", ")
	return t.strip_edges()


## Zástupné znaky rozšířeného rozhovoru: {g:mužský|ženský} tvar mluvčí, {pub} hospoda (podle předložky),
## {shop} obchod, {temp} teplota, {season} období, {other} / {other_job} jiná postava ze vsi,
## M1.7: {home} domov hráče („byt 5 v č. p. 48“), {deda_home} dům dědy („č. p. 17“), {lot} usedlost se zahradou a výběhem.
static func _fill_ext(t: String, ctx: Dictionary) -> String:
	if _re_g == null:
		_re_g = RegEx.new()
		_re_g.compile("\\{g:([^|}]*)\\|([^}]*)\\}")
	t = _re_g.sub(t, "$2" if _female(_prof(ctx)) else "$1", true)
	var pub := String(ctx.get("places", {}).get("hospoda", {}).get("name", "Hospoda U Hřiště"))
	var tail := pub.substr(8) if pub.begins_with("Hospoda ") else pub
	t = t.replace("do {pub}", "do hospody " + tail).replace("v {pub}", "v hospodě " + tail).replace("V {pub}", "V hospodě " + tail)
	t = t.replace("{pub}", "Hospoda " + tail if pub.begins_with("Hospoda ") else pub)
	t = t.replace("{shop}", String(ctx.get("places", {}).get("obchod", {}).get("name", "Potraviny")))
	t = t.replace("{temp}", "%d °C" % roundi(float(ctx.get("temp", 12.0)))).replace("{season}", String(ctx.get("season", "")))
	t = t.replace("{home}", String(ctx.get("home_label", "domov"))).replace("{deda_home}", String(ctx.get("deda_label", "vedle")))
	t = t.replace("{lot}", String(ctx.get("lot_label", "")))
	if t.contains("{other"):
		var o := _random_other(_prof(ctx))
		t = t.replace("{other_job}", String(o.get("job", ""))).replace("{other}", String(o.get("name", "")).split(" ")[0])
	return t


## Opilý hráč „šišlá“ – co řekne, vidí ostatní trochu zkomolené.
static func slur(t: String, promile: float) -> String:
	if promile < 1.3:
		return t
	var k := clampf((promile - 1.3) / 1.5, 0.0, 1.0)
	var out := ""
	for ch in t:
		if ch == "s" and randf() < 0.6 * k:
			out += "sh"
		elif ch == "c" and randf() < 0.4 * k:
			out += "š"
		elif ch in ["a", "e", "o"] and randf() < 0.12 * k:
			out += ch + ch
		else:
			out += ch
	if randf() < 0.5 * k:
		out += " …hik"
	return out


static func _place_in(n: String) -> String:
	for k in PLACE_WORDS:
		if _has(n, PLACE_WORDS[k]):
			return k
	return ""


static func _dist_text(d: float) -> String:
	if d < 60.0:
		return "kousek odsud"
	if d < 1000.0:
		return "asi %d metrů" % (roundi(d / 50.0) * 50)
	return ("asi %.1f km" % (d / 1000.0)).replace(".", ",")


## Přístup k hráči (−100..100): pověst (u netolerantních postav horší) + nálada postavy.
static func attitude(rep: float, mood: float, trait_: String) -> float:
	var tol := Characters.tolerance(trait_)
	var r := rep / tol if rep < 0.0 else rep
	return clampf(r + mood * 45.0, -100.0, 100.0)


# ====================================================================== pozdrav a drby

## Pozdrav, když hráč přijde blízko (bez psaní).
static func greet(ctx: Dictionary) -> String:
	var a: float = ctx.get("attitude", 0.0)
	var t := _trait(ctx)
	var p: float = ctx.get("promile", 0.0)
	if p > 1.2 and randf() < 0.6:
		return _fill(_pick({
			"prisny": ["Zase opilý? Styď se.", "Běž se vyspat, takhle se po vsi nechodí."],
			"bruclavy": ["Ty seš ale nametenej!", "Zase z hospody, co?"],
			"veselak": ["Ty už máš náskok, co? Počkej na mě!", "Hehe, to byla asi dobrá dvanáctka!"],
			"moudry": ["Jdi se vyspat, {voc}.", "Dej si rohlík, ať to trochu nasákne."],
			"mlady": ["Kámo, ty se motáš!", "Hlavně neřiď, jo?"],
		}.get(t, ["Ty se nějak motáš…", "Hlavně neřiď!", "Tak opatrně, ať neskončíš v příkopě!"])), ctx)
	var ot: Array = ctx.get("outfit_tags", [])
	if ot.has("plavky") and a > -55.0 and randf() < 0.7:     # M2.3: plavky ve vsi
		return _fill(_pick({
			"prisny": ["V plavkách po vsi? To snad ne.", "Dobrý den. Koupaliště je jinde."],
			"bruclavy": ["Ty ses spletl, tady není moře.", "Plavky? Uprostřed vsi?"],
			"veselak": ["Hehe, kam jdeš, k rybníku? Zapomněl jsi ručník!", "Nazdar, plavče!"],
			"mlady": ["Čau, plavčíku!", "Kámo, v plavkách? Fakt?"],
		}.get(t, ["Ty jdeš plavat? Tady? Uprostřed vsi?", "Plavky ve vsi… no, každý jak chce."])), ctx)
	if ot.has("slavnostni") and a > 0.0 and randf() < 0.35:   # M2.3: slavnostní oblečení
		return _fill(_pick({
			"prisny": ["Vidím, že dnes dbáte na vzhled. To se cení.", "Konečně někdo, kdo se umí obléknout."],
			"veselak": ["Ty ses ale vyfešákoval! Něco slavíš?", "Jé, sako! Jdeš na svatbu?"],
			"mlady": ["Čus, ty máš ale outfit!", "Hustý, sako!"],
		}.get(t, ["Ty ses ale vyparádil, {voc}!", "Slušívá ti to, {voc}."])), ctx)
	if a <= -55.0:
		return _fill(_pick({
			"prisny": ["Jdi ode mě, nebo zavolám policii!", "S takovým člověkem nemluvím."],
			"bruclavy": ["Táhni, výtečníku!", "Ty máš ještě odvahu se tu ukazovat?"],
			"plachy": ["…", "(uhne pohledem)"],
		}.get(t, ["Radši se ti vyhnu.", "O tobě se ve vsi povídají hrozné věci.", "Hm."])), ctx)
	if a <= -20.0:
		return _fill(_pick(["Hm… zase ty.", "No nazdar.", "Doufám, že dneska nic nevyvedeš.", "Slyšel%s jsem, co se stalo. Dávej si pozor." % _g(ctx, "", "a")]), ctx)
	var h: float = ctx.get("hour", 12.0)
	var dayp := "Dobré ráno" if h >= 4.0 and h < 9.0 else ("Dobrý večer" if h >= 18.0 or h < 4.0 else "Dobrý den")
	# přátelé a komunita, která si hráče váží (M0.6): vřelejší pozdrav
	var fr: float = ctx.get("friendship", 0.0)
	if fr >= Persona.FRIEND_HIGH:
		return _fill(_pick(["%s, kamaráde! Rád%s tě vidím, pojď dál s řečí." % [dayp, _g(ctx, "", "a")],
			"Ahoj, kamaráde! Už jsem myslel%s, že se nezastavíš." % _g(ctx, "", "a"),
			"%s, příteli! Tebe je vždycky radost vidět." % dayp]), ctx)
	if float(ctx.get("respect", 0.0)) >= 40.0 and a > 0.0:
		return _fill(_pick(["%s, {voc}! U nás si tě považujeme." % dayp, "Á, %s! O tobě se mezi našimi mluví dobře." % dayp.to_lower(),
			"%s! Dobře, že jdeš, {voc}." % dayp]), ctx)
	if a >= 50.0:
		return _fill(_pick(["%s, {voc}! Rád%s tě vidím." % [dayp, _g(ctx, "", "a")], "Á, náš vzorný soused! %s!" % dayp,
			"%s! Díky, že tak pomáháš ve vsi." % dayp]), ctx)
	if not ctx.get("met", false) and randf() < 0.5:
		return _fill("%s! Já jsem {first}, %s" % [dayp, String(_prof(ctx).get("job", ""))] + ".", ctx)
	return _fill(_pick({
		"pratelsky": ["%s, {voc}!" % dayp, "Zdravím! Pěkně dneska, co?", "Ahoj! Jak se vede?"],
		"drbna": ["%s! Víš už, co se stalo u Hromádků?" % dayp, "Á, ahoj! Počkej, musím ti něco říct…"],
		"bruclavy": ["Hm, %s." % dayp.to_lower(), "Zdar.", "Zase ten vítr…"],
		"prisny": ["%s." % dayp, "Dobrý den. Nešlapte mi na trávník."],
		"veselak": ["Nazdar, {voc}! Na jedno?", "Čau! Dneska je den jak stvořenej na pivo!"],
		"plachy": ["Dobrý den.", "(kývne na pozdrav)"],
		"moudry": ["%s, {voc}. Kam tak spěcháš?" % dayp, "Pozdrav pánbůh."],
		"mlady": ["Čau!", "Nazdar!", "Čus!"],
	}.get(t, ["Dobrý den!"])), ctx)


## Drb z vesnice (E u vesničana). Obsahuje-li „policajti“, hráč se dozví o silniční kontrole.
static func rumor(ctx: Dictionary) -> String:
	var out := ["U kapličky prý někdo ztratil dukáty…", "V lesích kolem prý svítí zlaté žaludy!",
		"Hostinský Láďa točí nejlepší dvanáctku v okolí.", "V Pálenici U Kotla mají slivovici jak křen.",
		"Vinař Zdeněk dělá degustace, ale kdo se motá, toho vyhodí.",
		"Kdo se nemůže dostat domů, vyspí se na seníku za hospodou. Smrdí to, ale je tam sucho."]
	if ctx.get("police_cp", false):
		out.append("Na hlavní %s prý stojí policajti a nechávají foukat." % String(ctx.get("police_dir", "")))
	else:
		out.append("Policajti jezdí od města, dávej bacha na rychlost.")
	var off: String = ctx.get("last_offense", "")
	if off != "":
		out.append("Víš, co se o tobě povídá? Že prý %s. Stydět by ses měl." % off)
	var qo: Array = ctx.get("quest_offers", [])
	if not qo.is_empty():
		out.append("%s prý něco potřebuje." % qo[randi() % qo.size()])
	return _pick(out)


# ====================================================================== odpověď na volný text

static func respond(text: String, ctx: Dictionary) -> Dictionary:
	var n := norm(text)
	var r := {"text": "", "intent": "", "mood": 0.0, "rep": 0.0, "rep_text": "", "police_hint": false, "fine": 0,
		"call_police": false}
	var t := _trait(ctx)
	var role: String = ctx.get("role", "villager")
	var mood: float = ctx.get("mood", 0.0)
	var a: float = ctx.get("attitude", 0.0)
	var p: float = ctx.get("promile", 0.0)
	var pr := _prof(ctx)
	var found := []
	var wds := _words()
	for k in _order():
		if k == "topic":
			if _topic(n, pr) != "":
				found.append(k)
		elif k == "about_person":
			if not _person_in(n, pr).is_empty():
				found.append(k)
		elif _has(n, wds.get(k, [])):
			found.append(k)
	var intent: String = found[0] if not found.is_empty() else "unknown"
	# samotné „ahoj“ na konci věty nemá přebít otázku: pozdrav + otázka → odpověď na otázku s pozdravem
	var greet_prefix := found.size() > 1 and found.has("greeting") and intent != "greeting"
	r["intent"] = intent

	# --- postava se zlobí – mluví jen s tím, kdo se omluví
	if mood < -0.6 and intent != "sorry":
		r["text"] = _fill(_pick({"prisny": ["S vámi nemluvím.", "Nejdřív se omluvte."],
			"bruclavy": ["Táhni.", "Po tom, cos mi řekl? Ani náhodou."],
			"plachy": ["…"]}.get(t, ["Nechci s tebou mluvit.", "Po tom všem? Ne."])), ctx)
		return r

	var mem := _mem(ctx)
	var conds := _conds(ctx)
	var ans := ""
	var short := n.strip_edges().split(" ", false).size() <= DialogData.FOLLOW_MAX_WORDS
	var fresh := float(ctx.get("now_min", 0.0)) - float(mem.get("t", -1.0e9)) < DialogData.MEMORY_FRESH_MIN
	var q_key := String(mem.get("ask", ""))
	mem["ask"] = ""
	if short and fresh and q_key != "" and found.all(func(k): return k in ["yes", "no", "thanks", "greeting"]):
		r["intent"] = "answer"
		return _finish(r, _askback_reply(q_key, found, ctx, conds, mem, r), ctx, mem, conds, String(mem.get("theme", "")))
	if short and fresh:
		var f := _follow(n, found, ctx, conds, mem)
		if f != "":
			r["intent"] = "followup"
			return _finish(r, f, ctx, mem, conds, String(mem.get("theme", "")))
	mem["howto"] = ""

	match intent:
		"threat":
			r["mood"] = -0.8
			r["rep"] = -6.0
			r["rep_text"] = "vyhrožoval jsi: %s" % String(pr.get("name", ""))
			if role == "cop":
				r["fine"] = 2000
				ans = "Tak to stačí. Vyhrožování úřední osobě – pokuta 2 000 Kč. A buďte rád, že jen to."
			elif t in ["prisny", "bruclavy", "moudry"]:
				r["call_police"] = true
				ans = _pick(["Tak to volám policii!", "Vyhrožuješ mi? To si vyřídíš s policajtama!"])
			else:
				ans = _pick(["Pomoc! Ten člověk mi vyhrožuje!", "Nech mě bejt! Já zavolám policii!"])
				r["call_police"] = t != "plachy"
		"insult":
			r["mood"] = -0.45
			r["rep"] = -2.0
			r["rep_text"] = "sprostě jsi urazil: %s" % String(pr.get("name", ""))
			if role == "cop":
				r["fine"] = 1000
				r["rep"] = -8.0
				r["rep_text"] = "urážka policisty"
				ans = "Urážka veřejného činitele. Pokuta 1 000 Kč na místě. Chcete pokračovat?"
			else:
				ans = _pick({
					"prisny": ["Tak takhle ne! To si budu pamatovat.", "Jak se to chováte? Styďte se!"],
					"bruclavy": ["Sám seš! Táhni!", "Ještě jednou a dostaneš přes hubu."],
					"veselak": ["Hele, klid, nebo ti ten jazyk přistřihnu.", "Tak to nebylo vtipný, kamaráde."],
					"plachy": ["…", "(zbledne a odvrátí se)"],
					"moudry": ["Takhle mluvit se starším člověkem? To tě doma nenaučili?", "Za mých časů by ti otec nařezal."],
					"drbna": ["No to je hrůza! To řeknu celé vsi!", "Tak tohle se dozví každý!"],
					"mlady": ["Cože? Seš normální?", "Kámo, uklidni se."],
				}.get(t, ["To se neříká!"]))
		"sorry":
			if mood < -0.1:
				r["mood"] = 0.35
				ans = _pick(["No dobře. Odpouštím, ale ať se to neopakuje.", "Omluva se přijímá.", "Tak jo, zapomeneme na to."])
			else:
				ans = _pick(["Za co? To je v pořádku.", "Nic se nestalo.", "Klid, v pohodě."])
		"lost":
			var home: Dictionary = ctx.get("places", {}).get("domov", {})
			if home.is_empty():
				ans = "Tady jsi v Dukelčicích, {voc}."
			else:
				ans = "Tady jsi v Dukelčicích, {voc}. Domů, %s, je to odsud %s, %s." % [String(ctx.get("home_where", "")),
					home["dir"], _dist_text(home["dist"])]
			if p > 1.5:
				ans += " A v tomhle stavu radši pomalu."
		"name":
			if ctx.get("met", false):
				ans = _pick(["Vždyť už jsem ti to říkal%s – {first}." % _g(ctx, "", "a"), "Pořád {name}, {voc}."])
			else:
				ans = "Jsem {name}, %s. A ty jsi ten z čísla %d, že?" % [String(pr.get("job", "")), int(ctx.get("home_no", 0))]
			r["mood"] = 0.05
		"introduce":
			r["mood"] = 0.1
			ans = _pick(["Těší mě! Já jsem {first}.", "Rád%s tě poznávám. Říkej mi {first}." % _g(ctx, "", "a"),
				"Aha, tak to jsi ty! Já jsem {name}."])
		"howareyou":
			if a < -20.0:
				ans = "Dokud tě nevidím, tak dobře."
			else:
				ans = _pick({
					"pratelsky": ["Dobře, díky! A ty?", "Moc dobře, děkuju za optání!"],
					"drbna": ["Dobře, ale ta Hromádková, to ti povím…", "Ale jo, jen těch novinek je tolik!"],
					"bruclavy": ["Ale, jak by se mělo. Záda bolí, důchod malej…", "Blbě. Jako vždycky."],
					"prisny": ["Děkuji, dobře.", "Nestěžuji si."],
					"veselak": ["Bezva, jen žízeň mám!", "Líp než včera, hůř než zítra!"],
					"plachy": ["Dobře.", "Ujde to."],
					"moudry": ["Na můj věk dobře, {voc}. Hlavně že nohy slouží.", "Pánbůh zaplať, dobře."],
					"mlady": ["V pohodě.", "Dobrý, jen se nudím."],
				}.get(t, ["Dobře."]))
		"age":
			var age := int(pr.get("age", 40))
			if age >= 65:
				ans = "%d let, {voc}, a pořád čil%s!" % [age, _g(ctx, "ý", "á")]
			elif age < 25:
				ans = "Je mi %d. Proč?" % age
			else:
				ans = _pick(["Na to se %s neptá!" % _g(ctx, "chlapa", "ženské"), "Je mi %d, ale cítím se na míň." % age])
		"job":
			ans = "Jsem %s. {hobby}" % String(pr.get("job", "tady z vesnice"))
			if role == "keeper":
				ans = "Starám se tady o podnik. Když něco chceš, zmáčkni E u dveří."
			elif role == "cop":
				ans = "Hlídáme pořádek na silnicích. Řidiči foukají, pěší můžou jít."
		"time":
			ans = "Je %s." % String(ctx.get("time_text", ""))
			var h: float = ctx.get("hour", 12.0)
			if h >= 23.0 or h < 4.0:
				ans += " Takhle pozdě bys měl být v posteli."
			elif h < 7.0:
				ans += " Ranní ptáče dál doskáče."
		"hours", "where":
			var k := _place_in(n)
			var pls: Dictionary = ctx.get("places", {})
			if k == "" or not pls.has(k):
				ans = "Kam přesně? Hospoda, Potraviny, pálenice, sklep, chata nebo úřad?"
			else:
				var pl: Dictionary = pls[k]
				if k == "domov":
					ans = "Domů, %s? To je odsud %s, %s." % [String(ctx.get("home_where", "")), pl["dir"], _dist_text(pl["dist"])]
				elif k == "deda":
					ans = "Děda Vomáčka sedí na lavičce u svého domu ({deda_home}), to je odsud %s." % pl["dir"]
				else:
					ans = "%s je odsud %s, %s." % [pl["name"], pl["dir"], _dist_text(pl["dist"])]
					if intent == "hours" or randf() < 0.6:
						ans += " Otevřeno mají %s%s." % [pl["hours"], "" if pl["open"] else ", teď je zavřeno"]
		"sleep":
			ans = "Doma se vyspíš nejlíp. Jinak je seník za hospodou a palanda u Myslivecké chaty. A v Potravinách mají spacáky."
			if p > 1.5:
				ans = "Vyspat se? To bys měl, a hned! " + ans
		"police":
			r["police_hint"] = ctx.get("police_cp", false)
			if role == "cop":
				ans = "Jsem tady kvůli silniční kontrole. Když neřídíte, nemusíte se bát."
			elif ctx.get("police_cp", false):
				ans = _pick(["Na hlavní %s stojí policajti, dávej bacha!" % String(ctx.get("police_dir", "")),
					"Policajti? Stojí na hlavní %s a nechávají foukat." % String(ctx.get("police_dir", ""))])
			else:
				ans = _pick(["Policajti jezdí od města, občas měří rychlost.", "Hlídka tu jezdí dost často, hlavně večer."])
			if p >= 0.3:
				ans += " A ty bys za volant rozhodně neměl!"
		"news":
			ans = rumor(ctx)
			r["police_hint"] = ans.contains("policajti") and ctx.get("police_cp", false)
		"quest":
			var qa: String = ctx.get("quest_active", "")
			var qo: Array = ctx.get("quest_offers", [])
			if qa != "":
				ans = "Nejdřív dodělej, co máš rozdělané: %s." % qa
			elif role in ["keeper", "deda", "regular"] and not qo.is_empty():
				ans = "Něco by se našlo. Zmáčkni E, domluvíme se."
			elif not qo.is_empty():
				ans = "Já nic nepotřebuju, ale %s prý shání pomoc." % qo[randi() % qo.size()]
			else:
				ans = "Teď nic, díky. Ale je hezké, že se ptáš."
			r["mood"] = 0.05
		"invite":
			if t in ["veselak", "mlady"] or role == "regular":
				r["mood"] = 0.2
				ans = _pick(["Ty zveš? Tak to jdu!", "Na pivo vždycky! Hospoda U Hřiště, jdem!", "Jen jedno. Tak dvě."])
			elif t == "prisny":
				ans = "Děkuji, nepiju."
			else:
				ans = _pick(["Dneska ne, díky.", "Možná jindy.", "Já už nepiju, doktor zakázal."])
		"drunk_admit":
			if role == "cop":
				ans = "Tak hlavně neřiďte. Pěšky domů a vyspat se."
			else:
				ans = _pick({"prisny": ["To je vidět. A pěkné to není."], "veselak": ["To je vidět! Hlavně neřiď, jo?"],
					"moudry": ["Tak se jdi vyspat, {voc}. Ráno moudřejší večera."]}.get(t, ["Tak hlavně neřiď!", "To je poznat."]))
		"drink":
			var hosp: Dictionary = ctx.get("places", {}).get("hospoda", {})
			if role == "keeper" and ctx.get("place", "") in ["hospoda", "sklep", "palenice", "obchod"]:
				ans = "U mě dostaneš, co hrdlo ráčí – zmáčkni E u dveří."
				if p > 2.5:
					ans = "Ty už máš dost. Dneska ti nenaliju."
			elif p > 1.0:
				ans = _pick(["Ty už máš dost, ne?", "Pití? Tobě by bodla spíš voda."])
			elif t == "prisny":
				ans = "Pití ti moc nesvědčí. A za volant potom ani omylem."
			elif hosp.is_empty():
				ans = "Na pivo do hospody, kam jinam."
			else:
				ans = "Hospoda U Hřiště je odsud %s. %s" % [hosp["dir"], "Teď mají otevřeno." if hosp["open"] else "Teď mají zavřeno, otevírají v deset."]
				if t == "veselak":
					ans = "Pivo? To je řeč! " + ans
		"food":
			ans = _pick(["V Potravinách mají rohlíky a tlačenku. V hospodě uvaří guláš.", "Hlad? V hospodě mají smažák jak podrážku, ale dobrej."])
			if p > 1.0:
				ans += " A něco sníst ti fakt pomůže."
		"money":
			if t in ["bruclavy", "prisny"]:
				ans = _pick(["Peníze? Ty si vydělej!", "Nepůjčuju. Zásadně."])
				r["mood"] = -0.05
			else:
				ans = _pick(["Nemám nazbyt. Ale na silnicích se prý válejí dukáty!", "Zkus pomoct lidem ve vsi, někdo ti za to i zaplatí."])
		"joke":
			if t in ["prisny", "plachy"]:
				ans = "Vtipy moc neumím."
			else:
				ans = _pick(JOKES)
				r["mood"] = 0.1
		"flirt":
			if t == "plachy":
				ans = "(zčervená) No… já… musím jít."
			elif t == "prisny":
				ans = "Tak to ne. Mějte trochu úrovně."
				r["mood"] = -0.1
			elif int(pr.get("age", 40)) >= 65:
				ans = "Ale jdi ty, {voc}! Na tohle jsem už stará bačkora." if _female(pr) else "Hehe, to bys musel dřív vstávat."
			else:
				ans = _pick(["Ty jsi ale lichotník!", "Hele, zkus to radši v hospodě na tancovačce.", "No… to bych musel%s ještě promyslet." % _g(ctx, "", "a")])
		"reputation":
			var rep_t: String = ctx.get("tier_name", "")
			if a >= 50.0:
				ans = "Lidi o tobě mluví jen hezky. Jsi %s." % rep_t
			elif a >= 15.0:
				ans = "Jsi slušný soused, nemůžu si stěžovat."
			elif a > -20.0:
				ans = "Moc tě neznám, ale zatím dobrý."
			else:
				var off: String = ctx.get("last_offense", "")
				ans = "Upřímně? Nic moc. %s" % (("Povídá se, že prý %s." % off) if off != "" else "Chovej se slušně a lidi zapomenou.")
		"compliment":
			r["mood"] = 0.15
			r["rep"] = 0.5
			r["rep_text"] = "byl jsi milý na: %s" % String(pr.get("name", ""))
			ans = _pick({"prisny": ["Děkuji.", "To je od vás hezké."], "bruclavy": ["No… díky.", "Hm. To jsem nečekal."],
				"plachy": ["(usměje se) Děkuju.", "Díky."], "drbna": ["Ty jsi ale zlatíčko!", "To řeknu všem, jak jsi milý!"]
			}.get(t, ["Děkuju, to potěší!", "Ty jsi ale milý!", "To je hezké, díky!"]))
		"thanks":
			r["mood"] = 0.05
			ans = _pick(["Není zač!", "Rádo se stalo.", "Nemáš zač, {voc}."])
		"weather":
			ans = "Teď je %s." % String(ctx.get("weather", "")).to_lower()
			var temp: float = ctx.get("temp", 12.0)
			if ctx.get("snowing", false):
				ans += " Sněží – obleč se a na silnici opatrně."
			elif ctx.get("raining", false):
				ans += " Prší, tak na houby bude ráno jak stvořené."
			elif temp > 27.0:
				ans += " Horko jak v peci."
			elif temp < 3.0:
				ans += " Pořádná kosa."
			if t == "moudry":
				ans += " Za mých mladých let byly zimy pořádné."
		"items":
			if _has(n, ["houb", "hrib"]):
				ans = "Hřiby rostou v lesích kolem obce, hlavně po dešti."
			elif _has(n, ["dukat", "poklad"]):
				ans = "U kapličky a na silnicích v obci prý někdo ztratil dukáty…"
			elif _has(n, ["jablk"]):
				ans = "Pod stromy v zahradách je jablek spousta, nikdo je nesbírá."
			else:
				ans = "V lesích daleko za vsí prý svítí zlaté žaludy. Poznáš je zdálky."
		"horse":
			ans = "Tvůj kůň se pase ve výběhu u usedlosti {lot}, ne? Vyleze na něj každý, kdo umí F." if role != "deda" \
				else "Koně jsme měli, když jsem byl kluk. Tvůj se pase kousek odsud."
		"topic":
			var tp := _topic(n, pr)
			ans = _pick(TOPICS[tp][1])
			r["mood"] = 0.1
		"howto":
			ans = _howto(n, ctx, conds, mem, fresh)
			r["mood"] = 0.03
		"about_person":
			ans = _about_person(n, ctx, mem)
			r["mood"] = 0.03
		"goodbye":
			ans = _pick({"prisny": ["Na shledanou."], "bruclavy": ["Zdar.", "Tak jo."], "mlady": ["Čau!", "Měj se!"],
				"moudry": ["S pánembohem, {voc}.", "Opatruj se."], "veselak": ["Čau, a na zdraví!"]
			}.get(t, ["Na shledanou!", "Měj se!", "Ahoj, zas někdy!"]))
		"greeting":
			ans = greet(ctx)
			r["mood"] = 0.03
		"yes":
			ans = _pick(["No vidíš.", "Tak jo.", "Aha."])
		"no":
			ans = _pick(["Tak nic.", "No, jak myslíš.", "Hm."])
		_:
			if DialogThemes.THEMES.has(intent):
				ans = _theme_answer(intent, ctx, conds, mem, r)
			elif p > 1.5:
				ans = _pick(["Mluvíš nějak z cesty. Nemáš trochu v hlavě?", "Cože? Nerozumím ti ani slovo.", "Jdi se vyspat, pak si promluvíme."])
			else:
				ans = _pick({
					"pratelsky": ["Hm, tomu úplně nerozumím, ale ráda si popovídám." if _female(pr) else "Hm, tomu úplně nerozumím, ale rád si popovídám.", "Zajímavé! A co jinak?"],
					"drbna": ["Aha… a víš, co se povídá o Ploužkovi?", "To je zajímavé, to musím říct sousedce!"],
					"bruclavy": ["Co? Nerozumím.", "Hm. Nemám čas na kecy."],
					"prisny": ["Prosím? Vyjadřujte se jasně.", "Nerozumím, co tím myslíte."],
					"veselak": ["Hehe, to je dobrý!", "No jo, no jo. Dáme na to pivo?"],
					"plachy": ["Aha.", "Hm."],
					"moudry": ["Každý den se člověk něco naučí.", "Hm, to je zajímavé. {hobby}"],
					"mlady": ["Cože? Nechápu.", "Jako… jo?"],
				}.get(t, ["Hm?"]))
	ans = _enrich(intent, ans, ctx, conds, mem, r)
	if greet_prefix and intent not in ["insult", "threat"]:
		var h: float = ctx.get("hour", 12.0)
		ans = ("Dobrý den! " if t in ["prisny", "moudry"] else ("Ahoj! " if h >= 4.0 and h < 22.0 else "Dobrý večer! ")) + ans
		r["mood"] = float(r["mood"]) + 0.03

	# --- přídavky: křik, řidič pod vlivem, opilost
	if ctx.get("shout", false) and intent not in ["threat"]:
		if t in ["prisny", "bruclavy", "moudry"]:
			ans = "Neřvi tak! " + ans
			r["mood"] = float(r["mood"]) - 0.1
	if ctx.get("in_car", false) and p >= 0.25 and role != "cop" and intent not in ["threat", "insult"]:
		if t in ["prisny", "moudry", "pratelsky"]:
			ans += " Počkej… ty řídíš a táhne z tebe alkohol? To nahlásím!"
			r["call_police"] = true
		else:
			ans += " A s tím pitím za volantem skonči, jo?"
	elif p > 1.2 and randf() < 0.3 and intent not in ["drunk_admit", "insult", "threat", "unknown", "drink"]:
		ans += _pick([" (Ty jsi ale nametenej.)", " A běž se vyspat.", " Nějak se motáš."])
	if intent not in ["threat", "insult", "goodbye"] and not r["call_police"] and int(r["fine"]) == 0:
		ans = _extras(ans, intent, ctx, conds, mem)
	var mt := intent
	if intent == "howto" and String(mem.get("howto", "")) != "":
		mt = String(mem["howto"])
	return _finish(r, ans, ctx, mem, conds, mt)


## Postava, která slyšela, jak hráč někoho urazil nebo mu vyhrožoval.
static func witness(ctx: Dictionary, intent: String) -> String:
	var t := _trait(ctx)
	if intent == "threat":
		return _fill(_pick(["Slyšel%s jsem to! Ještě jednou a volám policii." % _g(ctx, "", "a"), "Nech ho bejt, ty grázle!",
			"Tak tohle si celá ves bude pamatovat."]), ctx)
	return _fill(_pick({"prisny": ["To se neříká! Styďte se.", "Takové chování sem nepatří."],
		"drbna": ["No to je hrůza! To musím říct sousedce.", "Slyšela jsem to! Celá ves se to dozví!"],
		"veselak": ["Hele, klídek, kamaráde.", "Ale no tak, nejsme v hospodě po půlnoci."],
		"moudry": ["Za mých časů by ti otec nařezal.", "Slušnost nic nestojí, {voc}."],
		"plachy": ["(nesouhlasně zavrtí hlavou)"]}.get(t, ["To se neříká!", "No tohle!"])), ctx)


## Téma z profilu postavy, o kterém hráč mluví (nebo "" – o témata mimo profil postava nemá zájem).
static func _topic(n: String, pr: Dictionary) -> String:
	for tp in pr.get("topics", []):
		if TOPICS.has(tp) and _has(n, TOPICS[tp][0]):
			return tp
	return ""


# ====================================================================== rozšířený rozhovor (DialogData, DialogThemes)

static var _w_cache := {}
static var _o_cache := []
static var _re_g: RegEx
static var _re_go: RegEx


## Klíčová slova všech záměrů: `WORDS` + hovorové tvary z `DialogData.EXTRA_WORDS`, rady (`howto`) a slova témat.
static func _words() -> Dictionary:
	if _w_cache.is_empty():
		for k in WORDS:
			_w_cache[k] = (WORDS[k] as Array) + (DialogData.EXTRA_WORDS.get(k, []) as Array)
		for k in DialogData.WORDS:
			if not String(k).begins_with("f_") and not (DialogData.WORDS[k] as Array).is_empty():
				_w_cache[k] = DialogData.WORDS[k]
		for k in DialogThemes.THEMES:
			if DialogThemes.THEMES[k].has("words") and not WORDS.has(k):
				_w_cache[k] = DialogThemes.THEMES[k]["words"]
	return _w_cache


## Priorita záměrů: `INTENT_ORDER` + rady před cestou, lidé před drby, témata (konkrétní fráze) před pitím.
static func _order() -> Array:
	if _o_cache.is_empty():
		for k in INTENT_ORDER:
			if k == "where":
				_o_cache.append("howto")
			elif k == "news":
				_o_cache.append("about_person")
			elif k == "drink":
				for th in DialogThemes.THEMES:
					if DialogThemes.THEMES[th].has("words") and not WORDS.has(th):
						_o_cache.append(th)
			_o_cache.append(k)
	return _o_cache


## Krátká paměť rozhovoru postavy s hráčem (Persona.talk): téma, čas, co už řekla, otázka zpět, poznámky.
## Po `DialogData.MEMORY_FORGET_DAYS` herních dnech se zapomene.
static func _mem(ctx: Dictionary) -> Dictionary:
	var fresh := {"day": int(ctx.get("day", 0)), "said": [], "theme": "", "t": -1.0e9, "ask": "", "asked": [],
		"remarked": [], "remark_t": -1.0e9, "howto": ""}
	var per: Persona = ctx.get("persona")
	if per == null:
		return fresh
	var id := int(ctx.get("pid", 0))
	var m: Dictionary = per.talk.get(id, {})
	if m.is_empty() or int(ctx.get("day", 0)) - int(m.get("day", 0)) >= DialogData.MEMORY_FORGET_DAYS:
		m = fresh
		per.talk[id] = m
	return m


## Uloží téma a čas rozhovoru a vyplní zástupné znaky.
static func _finish(r: Dictionary, ans: String, ctx: Dictionary, mem: Dictionary, _c: Dictionary, theme: String) -> Dictionary:
	mem["theme"] = theme
	mem["t"] = float(ctx.get("now_min", 0.0))
	r["text"] = _fill(ans, ctx)
	return r


## Podmínky pro výběr odpovědí (klíče `cond` v `DialogThemes`, `DialogData.REMARKS`, `GENERIC_TIPS`).
static func _conds(ctx: Dictionary) -> Dictionary:
	var c := {}
	var h: float = ctx.get("hour", 12.0)
	var temp: float = ctx.get("temp", 12.0)
	var rain: bool = ctx.get("raining", false)
	var snow: bool = ctx.get("snowing", false)
	if rain:
		c["raining"] = true
	if snow:
		c["snowing"] = true
	if temp > 27.0:
		c["hot"] = true
	elif temp < 3.0:
		c["cold"] = true
	if float(ctx.get("fog", 0.0)) > 0.35:
		c["fog"] = true
	if float(ctx.get("wind", 0.0)) > 8.0:
		c["windy"] = true
	if float(ctx.get("snow_cover", 0.0)) > 0.15:
		c["snowcover"] = true
	if not rain and not snow and float(ctx.get("cloud", 1.0)) < 0.35 and float(ctx.get("daylight", 0.0)) > 0.3:
		c["sunny"] = true
	if h >= 21.0 or h < 5.0:
		c["night"] = true
	elif h < 10.0:
		c["morning"] = true
	elif h >= 17.0:
		c["evening"] = true
	var season := String(ctx.get("season", ""))
	if season != "":
		c[season] = true
		c[{"jaro": "spring", "léto": "summer", "podzim": "autumn", "zima": "winter"}.get(season, "")] = true
	if ctx.has("weekday"):
		c["weekend" if int(ctx["weekday"]) >= 5 else "weekday"] = true
	if String(ctx.get("holiday", "")) != "":
		c["holiday"] = true
	if float(ctx.get("promile", 0.0)) > 0.8:
		c["drunk"] = true
	if ctx.has("money"):
		if int(ctx["money"]) < 300:
			c["poor"] = true
		elif int(ctx["money"]) > 30000:
			c["rich"] = true
	var a: float = ctx.get("attitude", 0.0)
	if float(ctx.get("friendship", 0.0)) >= Persona.FRIEND_HIGH:
		c["friend"] = true
	if not ctx.get("met", false):
		c["stranger"] = true
	if a <= -20.0:
		c["disliked"] = true
	if a >= 50.0 or float(ctx.get("respect", 0.0)) >= 40.0:
		c["respected"] = true
	if ctx.get("in_car", false):
		c["in_car"] = true
	if (ctx.get("outfit_tags", []) as Array).has("slavnostni"):
		c["outfit_slavnostni"] = true
	for k in ctx.get("carry", []):
		c[k] = true
	for k in ctx.get("events", []):
		c[k] = true
	var now: float = ctx.get("now_min", 0.0)
	var rec: Dictionary = ctx.get("recent", {})
	for kind in rec:
		var m: Array = DialogData.RECENT_MAP.get(kind, [])
		if not m.is_empty() and now - float(rec[kind]) < float(m[1]) * 60.0:
			c[m[0]] = true
	if String(ctx.get("last_offense", "")) != "":
		c["recent_offense"] = true
	return c


## Vybere větu, kterou postava tomuto hráči ještě neřekla (a zapamatuje si ji). `allow_repeat` = když už
## řekla všechno, smí opakovat (jinak vrátí "").
static func _pick_new(pool: Array, mem: Dictionary, allow_repeat := true) -> String:
	if pool.is_empty():
		return ""
	var said: Array = mem.get("said", [])
	var fresh := pool.filter(func(x): return not said.has(hash(x)))
	if fresh.is_empty():
		if not allow_repeat:
			return ""
		fresh = pool
	var s := String(fresh[randi() % fresh.size()])
	if not said.has(hash(s)):
		said.append(hash(s))
		while said.size() > DialogData.MEMORY_SAID_MAX:
			said.pop_front()
	return s


## Všechny možné odpovědi tématu s vahami (opakováním): obecné ×1, povaha ×2, roční období ×3, platná podmínka ×4.
static func _theme_pool(th: String, ctx: Dictionary, conds: Dictionary) -> Array:
	var T: Dictionary = DialogThemes.THEMES.get(th, {})
	var pool: Array = []
	pool.append_array(T.get("lines", []))
	var tl: Array = T.get("trait", {}).get(_trait(ctx), [])
	var sl: Array = T.get("season", {}).get(String(ctx.get("season", "")), [])
	for i in 2:
		pool.append_array(tl)
	for i in 3:
		pool.append_array(sl)
	var cd: Dictionary = T.get("cond", {})
	for k in cd:
		if conds.has(k):
			for i in 4:
				pool.append_array(cd[k])
	return pool


## Odpověď na téma z `DialogThemes`: nová věta (paměť), nadšení odborníka, nebo odkaz na toho, kdo to zná.
static func _theme_answer(th: String, ctx: Dictionary, conds: Dictionary, mem: Dictionary, r: Dictionary) -> String:
	var T: Dictionary = DialogThemes.THEMES[th]
	var t := _trait(ctx)
	var s := _pick_new(_theme_pool(th, ctx, conds), mem, bool(T.get("social", false)))
	if s == "":
		return _pick(DialogThemes.EXHAUSTED.get(t, DialogThemes.EXHAUSTED["_"]))
	r["mood"] = float(T.get("mood", 0.05))
	var tp := String(DialogData.THEME_TOPIC.get(th, ""))
	if tp != "":
		var pr := _prof(ctx)
		if (pr.get("topics", []) as Array).has(tp):
			if randf() < 0.6:
				s = _pick(DialogThemes.EXPERT_PREFIX.get(t, DialogThemes.EXPERT_PREFIX["_"])) + s
			r["mood"] = float(r["mood"]) + 0.05
		elif randf() < 0.25:
			var ex := _expert(tp, pr)
			if not ex.is_empty():
				s += " " + _pick(DialogThemes.REFERRALS).replace("{expert}", String(ex["name"])).replace("{expert_job}", String(ex["job"]))
	return s


## Jiná postava, která má téma `tp` mezi oblíbenými (odborník), nebo {}.
static func _expert(tp: String, pr: Dictionary) -> Dictionary:
	var c := []
	for o in Characters.PROFILES:
		if o["name"] != pr.get("name", "") and (o.get("topics", []) as Array).has(tp):
			c.append(o)
	return c[randi() % c.size()] if not c.is_empty() else {}


## Staré záměry s vlastním tématem v `DialogThemes` dostanou pestřejší odpověď; vtipy a drby z `DialogData`.
static func _enrich(intent: String, ans: String, ctx: Dictionary, conds: Dictionary, mem: Dictionary, r: Dictionary) -> String:
	var t := _trait(ctx)
	match intent:
		"weather":
			var s := _pick_new(_theme_pool("weather", ctx, conds), mem, true)
			if s != "":
				ans += " " + s
		"goodbye", "thanks", "compliment", "food", "money":
			var s := _pick_new(_theme_pool(intent, ctx, conds), mem, true)
			if s != "":
				ans = s
		"howareyou":
			if float(ctx.get("attitude", 0.0)) >= -20.0:
				var s := _pick_new(_theme_pool(intent, ctx, conds), mem, true)
				if s != "":
					ans = s
		"joke":
			if t not in ["prisny", "plachy"]:
				ans = _joke_line(ctx, mem)
		"news":
			if not r.get("police_hint", false):
				ans = _news_line(ctx, mem)
	return ans


static func _joke_line(ctx: Dictionary, mem: Dictionary) -> String:
	var pool: Array = JOKES + DialogData.JOKES + (DialogData.JOKES_TRAIT.get(_trait(ctx), []) as Array)
	return _pick_new(pool, mem, true)


## Novinka: drb o jiném obyvateli (drbna častěji; kdo o lidech nemluví, jen přátelům), jinak drb ze vsi.
static func _news_line(ctx: Dictionary, mem: Dictionary) -> String:
	var t := _trait(ctx)
	var can := not DialogData.NO_GOSSIP.has(t) or float(ctx.get("friendship", 0.0)) >= Persona.FRIEND_HIGH
	if can and randf() < (0.6 if t == "drbna" else 0.35):
		var o := _random_other(_prof(ctx))
		if not o.is_empty():
			var g := _gossip(o, mem)
			if g != "":
				return _fill_other(g, o)
	return rumor(ctx)


static func _random_other(pr: Dictionary) -> Dictionary:
	var c := []
	for o in Characters.PROFILES:
		if o["name"] != pr.get("name", ""):
			c.append(o)
	return c[randi() % c.size()] if not c.is_empty() else {}


## Drb o postavě `o` podle její povahy a oblíbených témat (ještě neřečený).
static func _gossip(o: Dictionary, mem: Dictionary) -> String:
	var pool: Array = (DialogData.GOSSIP_TRAIT.get(String(o.get("trait", "")), []) as Array).duplicate()
	for tp in o.get("topics", []):
		for g in DialogData.GOSSIP_TOPIC.get(tp, []):
			pool.append("{o} " + String(g) + ".")
	return _pick_new(pool, mem, false)


## Zástupné znaky o jiné postavě: {o} křestní jméno, {oj} povolání, {go:mužský|ženský} tvar.
static func _fill_other(s: String, o: Dictionary) -> String:
	if _re_go == null:
		_re_go = RegEx.new()
		_re_go.compile("\\{go:([^|}]*)\\|([^}]*)\\}")
	s = _re_go.sub(s, "$2" if _female(o) else "$1", true)
	return s.replace("{o}", String(o.get("name", "")).split(" ")[0]).replace("{oj}", String(o.get("job", "")))


## Vztah dvou postav (stálý, odvozený ze jmen): friend / rival / neutral.
static func _relation(a: Dictionary, b: Dictionary) -> String:
	var k := [String(a.get("name", "")), String(b.get("name", ""))]
	k.sort()
	var h := absi(hash(k[0] + "|" + k[1])) % 10
	if h < 3:
		return "friend"
	if h < 5 or (h < 6 and "bruclavy" in [a.get("trait", ""), b.get("trait", "")]):
		return "rival"
	return "neutral"


## Kmen jména pro hledání ve větě (bez diakritiky, bez koncovky: Pazderka → pazderk, Křemínek → kremin).
static func _stem(w: String) -> String:
	w = norm(w).strip_edges()
	if w.ends_with("ek") and w.length() > 5:
		return w.substr(0, w.length() - 2)
	if w.length() > 4 and w.right(1) in ["a", "e", "i", "o", "u", "y"]:
		return w.substr(0, w.length() - 1)
	return w


## O kom hráč mluví: {"folk": záznam DialogData.FOLK} / {"prof": profil z Characters.PROFILES} / {}.
## Postava, se kterou hráč mluví (oslovení jménem), se nepočítá – kromě obsluhy (FOLK), ta odpoví „to jsem já“.
static func _person_in(n: String, pr: Dictionary) -> Dictionary:
	for f in DialogData.FOLK:
		if _has(n, f["words"]):
			return {"folk": f}
	for o in Characters.PROFILES:
		if o["name"] == pr.get("name", ""):
			continue
		var keys := []
		for part in String(o["name"]).split(" "):
			var st := _stem(part)
			if st.length() >= 4:
				keys.append(st)
		if _has(n, keys):
			return {"prof": o}
	return {}


static func _about_person(n: String, ctx: Dictionary, mem: Dictionary) -> String:
	var pr := _prof(ctx)
	var t := _trait(ctx)
	var who := _person_in(n, pr)
	if who.has("folk"):
		var f: Dictionary = who["folk"]
		if _has(norm(String(pr.get("name", ""))), f["words"]):
			return "To jsem přece já, {voc}! " + String(pr.get("hobby", ""))
		var s := _pick_new(f["lines"], mem, false)
		return s if s != "" else _pick(DialogData.NOTHING_MORE)
	var o: Dictionary = who.get("prof", {})
	if o.is_empty():
		return "Koho myslíš?"
	if DialogData.NO_GOSSIP.has(t) and float(ctx.get("friendship", 0.0)) < Persona.FRIEND_HIGH:
		return _pick(DialogData.NO_GOSSIP[t])
	var s := _pick(DialogData.OPINION[_relation(pr, o)])
	if t in ["drbna", "veselak", "pratelsky", "mlady"] or randf() < 0.4:
		var g := _gossip(o, mem)
		if g != "":
			s += " " + g
	return _fill_other(s, o)


## Rada „jak na to / kde koupit“: podle předmětu ve větě, nebo navazuje na téma, o kterém se právě mluvilo.
static func _howto(n: String, ctx: Dictionary, conds: Dictionary, mem: Dictionary, fresh: bool) -> String:
	var subj := ""
	for k in DialogData.HOWTO:
		if _has(n, DialogData.HOWTO[k]["words"]):
			subj = k
			break
	if subj == "" and fresh and DialogData.HOWTO.has(String(mem.get("theme", ""))):
		subj = String(mem["theme"])
	if subj == "":
		return _generic_tip(conds, mem)
	mem["howto"] = subj
	var s := _pick_new(DialogData.HOWTO[subj]["lines"], mem, false)
	if s == "":
		return _pick(DialogData.NOTHING_MORE)
	return String({"bruclavy": "No jo, tak poslouchej. ", "prisny": "Postup je jasný. ", "moudry": "Poradím ti, {voc}. ",
		"mlady": "Jasně, kámo. ", "drbna": "To ti povím, zlatíčko. "}.get(_trait(ctx), "")) + s


static func _generic_tip(conds: Dictionary, mem: Dictionary) -> String:
	var pool: Array = (DialogData.GENERIC_TIPS["_"] as Array).duplicate()
	for c in conds:
		if DialogData.GENERIC_TIPS.has(c):
			for i in 2:
				pool.append_array(DialogData.GENERIC_TIPS[c])
	return _pick_new(pool, mem, true)


## Navazující krátká otázka („a proč?“, „a dál?“, „jak na to?“, „kde?“, „a ty?“) k tématu, o kterém se právě mluvilo.
## Vrací "" když nejde o navazující otázku.
static func _follow(n: String, found: Array, ctx: Dictionary, conds: Dictionary, mem: Dictionary) -> String:
	var key := ""
	for k in ["f_andyou", "f_why", "f_how", "f_more", "f_where"]:
		if _has(n, DialogData.WORDS[k]):
			key = String(k).substr(2)
			break
	if key == "":
		return ""
	# jiný rozpoznaný záměr má přednost („jak to jde?“ je otázka na zdraví, ne „a proč?“)
	for k in found:
		if k in ["yes", "no"] or (k == "where" and _place_in(n) == "") or (k == "howto" and key == "how") \
				or (k in ["howareyou", "greeting"] and key == "andyou"):
			continue
		return ""
	var th := String(mem.get("theme", ""))
	var T: Dictionary = DialogThemes.THEMES.get(th, {})
	var s := ""
	match key:
		"why":
			if T.has("why"):
				s = _pick_new(T["why"], mem, true)
		"more":
			var ht := String(mem.get("howto", ""))
			if ht != "" and DialogData.HOWTO.has(ht):
				s = _pick_new(DialogData.HOWTO[ht]["lines"], mem, false)
			elif th == "news":
				s = _news_line(ctx, mem)
			elif th == "joke":
				s = _joke_line(ctx, mem)
			elif not T.is_empty():
				s = _pick_new(_theme_pool(th, ctx, conds), mem, false)
			if s == "" and (ht != "" or not T.is_empty()):
				s = _pick(DialogData.NOTHING_MORE)
		"how":
			for k in DialogData.HOWTO:
				if _has(n, DialogData.HOWTO[k]["words"]):
					return ""          # konkrétní předmět → běžná rada (howto)
			if DialogData.HOWTO.has(th):
				s = _pick_new(DialogData.HOWTO[th]["lines"], mem, false)
				mem["howto"] = th
	if s == "":
		var fb: Dictionary = DialogThemes.FOLLOW_FALLBACK[key]
		s = _pick(fb.get(_trait(ctx), fb["_"]))
	return s


## Odpověď postavy na hráčovu odpověď k její otázce zpět (`DialogData.ASKBACK`): ano / ne / cokoli jiného.
static func _askback_reply(q_key: String, found: Array, ctx: Dictionary, conds: Dictionary, mem: Dictionary, r: Dictionary) -> String:
	var q: Dictionary = DialogData.ASKBACK.get(q_key, {})
	if q.is_empty():
		return _pick(["Aha.", "Hm."])
	var kind := "no" if found.has("no") else ("yes" if found.has("yes") else "other")
	var pool: Array = q.get(kind, [])
	var s := _pick(pool) if not pool.is_empty() else "Aha."
	if kind == "yes":
		r["mood"] = float(q.get("yes_mood", 0.03))
		match String(q.get("yes_do", "")):
			"news":
				s += " " + _news_line(ctx, mem)
			"joke":
				s += " " + _joke_line(ctx, mem)
			"howto":
				s += " " + _generic_tip(conds, mem)
	elif kind == "other":
		r["mood"] = 0.02
	return s


## Přídavky za odpověď: poznámka k nedávné události hráče (úlovek, nehoda, svátek…) a otázka zpět podle povahy.
static func _extras(ans: String, intent: String, ctx: Dictionary, conds: Dictionary, mem: Dictionary) -> String:
	var a: float = ctx.get("attitude", 0.0)
	if a <= -55.0:
		return ans
	var t := _trait(ctx)
	var now: float = ctx.get("now_min", 0.0)
	var remarked := false
	if randf() < DialogData.REMARK_CHANCE and now - float(mem.get("remark_t", -1.0e9)) > DialogData.REMARK_COOLDOWN_H * 60.0:
		var done: Array = mem.get("remarked", [])
		var cands := []
		for c in conds:
			if DialogData.REMARKS.has(c) and not done.has(c):
				cands.append(c)
		if not cands.is_empty():
			var rc: String = cands[randi() % cands.size()]
			ans += " " + _pick(DialogData.REMARKS[rc])
			done.append(rc)
			mem["remark_t"] = now
			remarked = true
	if a > -20.0 and not ans.strip_edges().ends_with("?") and intent not in ["yes", "no", "lost", "time", "hours", "where",
			"police", "quest", "reputation", "drunk_admit", "sorry", "flirt"]:
		var ch := float(DialogData.ASK_CHANCE.get(t, 0.2)) * (0.5 if remarked else 1.0)
		if randf() < ch:
			var asked: Array = mem.get("asked", [])
			var opts: Array = []
			if DialogThemes.THEMES.has(intent):
				opts.append_array(DialogThemes.THEMES[intent].get("ask", []))
			if opts.is_empty() or randf() < 0.3:
				opts.append_array(DialogData.ASK_OFFER.get(t, []))
			opts = opts.filter(func(q): return DialogData.ASKBACK.has(q) and String(DialogData.ASKBACK[q].get("text", "")) != "" and not asked.has(q))
			if not opts.is_empty():
				var q: String = opts[randi() % opts.size()]
				ans += " " + String(DialogData.ASKBACK[q]["text"])
				mem["ask"] = q
				asked.append(q)
	return ans
