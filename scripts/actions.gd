## Registr kontextových akcí (M0.4): „hráč drží nástroj, míří na cíl, spustí akci, ta chvíli trvá,
## stojí výdrž, dá XP, může selhat.“ Jen statická data a čisté funkce; průběh řeší `ActionRunner`.
##
## Klíče definice:
##   name      název pro HUD („Natrhat trávu“)
##   target    druh cíle: "ground" (země pod zaměřovačem), "water", "any" nebo druh registrovaného cíle
##             (`World.register_target`: "tree", "fire_spot", "animal", …)
##   needs     volitelně omezení povrchu pro "ground": "grass" (ne silnice / zástavba)
##   tool      potřebný předmět: "" = holé ruce (jde i s čímkoli v ruce), jinak id oddělená „|“
##   time_s    trvání v reálných s při úrovni 1 (s úrovní se zkracuje až na polovinu – `Skills.bonus`)
##   stamina   kolik výdrže (0..1) akce spotřebuje; při startu musí být aspoň tolik
##   skill, xp, level   dovednost, zisk XP a minimální úroveň
##   anim      pózu pro `Humanoid.start_action` (chop, dig, kneel, pour, cast, aim)
##   fail_chance   šance neúspěchu při úrovni 1 (klesá s úrovní); neúspěch = půl XP, žádný výnos
##   gives     {předmět: počet} do inventáře při úspěchu
##   wear      opotřebení nástroje za jedno použití (výchozí 1, jen pokud tool != "")
##   tool_level  volitelně {id nástroje: minimální úroveň} – přebíjí `level` (kácení: stará sekera 1, sekera 5, pila 20)
## Speciální výsledky (kácení stromu…) registrují další kroky: `Actions.set_handler(id, Callable)`;
## handler dostane (player_id: int, def: Dictionary, aim: Dictionary, ok: bool).
class_name Actions
extends RefCounted

const DEFS := {
	# M2.5 (cíl `ground`, stejně jako „Natrhat trávu“ níž): musí být před ní v pořadí – `natrhat_travu` má prázdný
	# `tool` (jde vždy) a bez toho by v HUD nápovědě „Zasadit strom“ navždy zastínila (`ActionRunner.hint`:
	# první proveditelná akce v pořadí `DEFS` vyhraje).
	"zasadit": {"name": "Zasadit strom", "target": "ground", "needs": "grass", "tool": "lopata", "time_s": 60.0,
		"stamina": 0.3, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "dig", "fail_chance": 0.0},
	# M2.7: žížaly na návnadu – před `natrhat_travu` (ta jde vždy, jinak by ji nikdy nepřebila); mimo vlastní pozemek
	# akce hlásí důvod (`Fishing._check_dig_worms`) a v nápovědě zůstane „Natrhat trávu“
	"kopat_zizaly": {"name": "Vykopat žížaly", "target": "ground", "needs": "grass", "tool": "lopata|motyka", "time_s": 20.0,
		"stamina": 0.12, "skill": "rybareni", "xp": 2, "level": 1, "anim": "dig", "fail_chance": 0.0},
	"natrhat_travu": {"name": "Natrhat trávu", "target": "ground", "needs": "grass", "tool": "", "time_s": 2.0,
		"stamina": 0.05, "skill": "zahradnictvi", "xp": 2, "level": 1, "anim": "kneel", "fail_chance": 0.0,
		"gives": {"trava": 1}},
	# ---- M2.1 Kácení a dřevo (výnosy a XP řeší handlery ve `Forestry`; čas se škáluje podle cíle přes `set_time_mod`)
	"pokacet": {"name": "Pokácet strom", "target": "tree", "tool": "sekera_stara|sekera|motorova_pila", "time_s": 9.0,
		"stamina": 0.35, "skill": "drevorubectvi", "xp": 0, "level": 1, "anim": "chop", "fail_chance": 0.0,
		"tool_level": {"sekera_stara": 1, "sekera": 5, "motorova_pila": 20}},
	"odvetvit": {"name": "Odvětvit kmen", "target": "log", "tool": "sekera_stara|sekera|motorova_pila", "time_s": 5.0,
		"stamina": 0.2, "skill": "drevorubectvi", "xp": 5, "level": 1, "anim": "chop", "fail_chance": 0.0},
	"rozrezat": {"name": "Rozřezat kmen na špalky", "target": "log", "tool": "sekera_stara|sekera|motorova_pila", "time_s": 8.0,
		"stamina": 0.3, "skill": "drevorubectvi", "xp": 8, "level": 1, "anim": "chop", "fail_chance": 0.0},
	"stipat": {"name": "Rozštípat špalek", "target": "block", "tool": "sekera_stara|sekera", "time_s": 3.0,
		"stamina": 0.12, "skill": "drevorubectvi", "xp": 3, "level": 1, "anim": "chop", "fail_chance": 0.0},
	# ---- M2.2 Oheň a topení (šanci zapálení, spotřebu dříví a XP řeší handlery ve `FireManager`; pořadí = přednost v HUD nápovědě)
	"rozdelat_ohen": {"name": "Rozdělat oheň", "target": "ground", "needs": "grass", "tool": "sirky|zapalovac", "time_s": 6.0,
		"stamina": 0.08, "skill": "ohen", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	"zapalit_ohniste": {"name": "Zapálit ohniště", "target": "fire", "tool": "sirky|zapalovac", "time_s": 6.0,
		"stamina": 0.08, "skill": "ohen", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	# opékání: šance spálení = fail_chance (klesá s dovedností Vaření); co se opeče, vybírá nabídka (E) nebo první opékatelný předmět
	"opekat": {"name": "Opékat na ohni", "target": "fire", "tool": "", "time_s": 60.0,
		"stamina": 0.04, "skill": "vareni", "xp": 12, "level": 1, "anim": "kneel", "fail_chance": 0.3},
	"uhasit": {"name": "Uhasit oheň", "target": "fire", "tool": "", "time_s": 10.0,
		"stamina": 0.12, "skill": "ohen", "xp": 3, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	"hasit": {"name": "Hasit hořící trávu", "target": "grassfire", "tool": "", "time_s": 12.0,
		"stamina": 0.3, "skill": "hasicina", "xp": 15, "level": 1, "anim": "chop", "fail_chance": 0.1},
	# ---- M2.4 Zahrada a pole (cíl `zahon` = záhon 1 × 1 m z `Garden.aim_cell`; výsledky a XP řeší handlery v `Garden`;
	# pořadí = přednost v HUD nápovědě: první proveditelná akce vyhraje, `zahon_info` je poslední záloha)
	"ryt": {"name": "Ryt záhon", "target": "zahon", "tool": "lopata|motyka", "time_s": 20.0,
		"stamina": 0.15, "skill": "zahradnictvi", "xp": 2, "level": 1, "anim": "dig", "fail_chance": 0.0},
	# Fáze 8: hnojení z kompostu – před `sit`, aby držení kbelíku hnoje dalo přednost hnojení
	"hnojit": {"name": "Pohnojit záhon", "target": "zahon", "tool": "hnuj", "time_s": 4.0,
		"stamina": 0.05, "skill": "zahradnictvi", "xp": 2, "level": 1, "anim": "pour", "fail_chance": 0.0, "wear": 0},
	"sit": {"name": "Zasít", "target": "zahon", "tool": "", "time_s": 4.0,
		"stamina": 0.03, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	"zalevat": {"name": "Zalít záhon", "target": "zahon", "tool": "konev_plna", "time_s": 3.0,
		"stamina": 0.03, "skill": "zahradnictvi", "xp": 1, "level": 1, "anim": "pour", "fail_chance": 0.0},
	"sklidit": {"name": "Sklidit úrodu", "target": "zahon", "tool": "", "time_s": 4.0,
		"stamina": 0.06, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	"plet": {"name": "Plít záhon", "target": "zahon", "tool": "", "time_s": 5.0,
		"stamina": 0.06, "skill": "zahradnictvi", "xp": 2, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	"naplnit": {"name": "Naplnit konev", "target": "water", "tool": "konev", "time_s": 4.0,
		"stamina": 0.02, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "wear": 0},
	"naplnit_kohoutek": {"name": "Naplnit konev (sud u zahrady)", "target": "kohoutek", "tool": "konev", "time_s": 4.0,
		"stamina": 0.02, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "wear": 0},
	"naplnit_studna": {"name": "Nabrat vodu ze studny", "target": "studna", "tool": "konev", "time_s": 4.0,
		"stamina": 0.02, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "wear": 0},
	"zahon_info": {"name": "Prohlédnout záhon", "target": "zahon", "tool": "", "time_s": 0.6,
		"stamina": 0.0, "skill": "", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	# ---- M2.5 Sázení stromů (`zasadit` je nahoře kvůli pořadí; zasazený strom nese v `aim` klíč `tree` ≥ `TreeManager.DYN_BASE`;
	# výsledky a XP řeší handlery v `PlantedTrees`; `strom_info` je poslední záloha v HUD nápovědě)
	"zalevat_strom": {"name": "Zalít strom", "target": "tree", "tool": "konev_plna", "time_s": 6.0,
		"stamina": 0.04, "skill": "zahradnictvi", "xp": 1, "level": 1, "anim": "pour", "fail_chance": 0.0},
	"obalit": {"name": "Obalit sazenici ochranným obalem", "target": "tree", "tool": "", "time_s": 8.0,
		"stamina": 0.05, "skill": "zahradnictvi", "xp": 2, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	"natrhat_ovoce": {"name": "Natrhat ovoce", "target": "tree", "tool": "", "time_s": 8.0,
		"stamina": 0.08, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	"strom_info": {"name": "Prohlédnout strom", "target": "tree", "tool": "", "time_s": 0.6,
		"stamina": 0.0, "skill": "", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	# ---- M2.7 Rybaření (cíl `water` s dosahem 8 m při udici v ruce; průběh lovu, záběr a zdolávání řeší `Fishing`,
	# tahle akce je jen nahození; stav lovu se v nápovědě ukazuje přes `Fishing._check_cast`)
	"nahodit": {"name": "Nahodit udici", "target": "water", "tool": "udice|udice_lepsi", "time_s": 1.6,
		"stamina": 0.03, "skill": "rybareni", "xp": 0, "level": 1, "anim": "cast", "fail_chance": 0.0, "wear": 0,
		"tool_level": {"udice": 1, "udice_lepsi": 10}},
	# ---- M3.1 Pracovní úkoly (cíle registruje `Jobs` jen během směny a jen pro hráče, který úkol plní – viz
	# `Actions.set_target_check` v `Jobs._register_builtin`; XP a mzdu dává `Jobs` podle `data/prace.json`, proto tu `xp` 0)
	"uklidit_stul": {"name": "Uklidit stůl", "target": "job_table", "tool": "", "time_s": 5.0,
		"stamina": 0.04, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	# ---- M3.2 První tři práce (`job: true` = cíl s `data.pid` patří jen hráči na směně – `Jobs.own_target`; XP dává `Jobs`
	# za hotový úkol, proto `xp` 0; `skill` jen zkracuje dobu akce s úrovní). Statek (`Statek`): seno z hromady → koryto,
	# napojit, podojit, vejce, hnůj vidlemi, záhony motykou.
	"nabrat_seno": {"name": "Nabrat seno z hromady", "target": "seno_hromada", "tool": "", "time_s": 3.0,
		"stamina": 0.06, "skill": "chovatelstvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	"nakrmit_koryto": {"name": "Nasypat seno do koryta", "target": "job_koryto", "tool": "", "time_s": 3.0,
		"stamina": 0.05, "skill": "chovatelstvi", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	"napojit": {"name": "Napojit zvířata (kbelík vody)", "target": "job_napajecka", "tool": "kbelik", "time_s": 4.0,
		"stamina": 0.06, "skill": "chovatelstvi", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "wear": 0, "job": true},
	"podojit": {"name": "Podojit krávu", "target": "job_krava", "tool": "kbelik", "time_s": 9.0,
		"stamina": 0.08, "skill": "chovatelstvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "wear": 0, "job": true},
	"sebrat_vejce": {"name": "Sebrat vejce z hnízda", "target": "job_hnizdo", "tool": "", "time_s": 2.5,
		"stamina": 0.02, "skill": "chovatelstvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	"vykydat": {"name": "Vykydat hnůj", "target": "job_hnuj", "tool": "vidle", "time_s": 8.0,
		"stamina": 0.22, "skill": "chovatelstvi", "xp": 0, "level": 1, "anim": "dig", "fail_chance": 0.0, "job": true},
	"okopat": {"name": "Okopat záhon", "target": "job_zahon", "tool": "motyka", "time_s": 8.0,
		"stamina": 0.15, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "dig", "fail_chance": 0.0, "job": true},
	# obecní údržba (`ObecniUdrzba`): tráva kosou, odpadky, lavička, listí hráběmi, sníh lopatou (i dobrovolně bez práce), posyp
	"posekat": {"name": "Posekat trávu", "target": "job_trava", "tool": "kosa", "time_s": 6.0,
		"stamina": 0.16, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "chop", "fail_chance": 0.0, "job": true},
	"sebrat_odpadek": {"name": "Sebrat odpadek", "target": "job_odpadek", "tool": "", "time_s": 1.2,
		"stamina": 0.02, "skill": "", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	"opravit_lavicku": {"name": "Opravit lavičku", "target": "job_lavicka", "tool": "kladivo", "time_s": 12.0,
		"stamina": 0.1, "skill": "kutilstvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	"shrabat_listi": {"name": "Shrabat listí", "target": "job_listi", "tool": "hrabe", "time_s": 6.0,
		"stamina": 0.12, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "dig", "fail_chance": 0.0, "job": true},
	"odklidit_snih": {"name": "Odklidit sníh", "target": "snih", "tool": "lopata", "time_s": 6.0,
		"stamina": 0.2, "skill": "kondice", "xp": 0, "level": 1, "anim": "dig", "fail_chance": 0.0, "job": true},
	"posypat": {"name": "Posypat chodník pískem", "target": "job_posyp", "tool": "", "time_s": 2.5,
		"stamina": 0.03, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	# výčep (`Vycep`): čepování je minihra (LMB držet / pustit) – `cepovat` je tu jen kvůli nápovědě [LMB] u pípy,
	# klik si vezme `Vycep.on_click` dřív, než se akce spustí; donést pivo hostovi = krátká akce
	"cepovat": {"name": "Čepovat pivo (drž LMB, pusť v zelené)", "target": "job_pipa", "tool": "", "time_s": 0.5,
		"stamina": 0.0, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	"donest_pivo": {"name": "Postavit pivo na stůl", "target": "job_host", "tool": "", "time_s": 1.2,
		"stamina": 0.0, "skill": "vyrecnost", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	# ---- M3.3 Další práce. Lesní dělník (`LesniPrace`): kácí, odvětvuje a řeže běžnými akcemi M2.1 (`pokacet`…), sází `zasadit`
	# (M2.5); dřevo na hromadu u paseky (špalek na rameni nebo 4 polena z kapsy)
	"slozit_drevo": {"name": "Složit dřevo na hromadu", "target": "job_hromada", "tool": "", "time_s": 3.0,
		"stamina": 0.08, "skill": "drevorubectvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	# M4.4 část B: hromada klestí u domu (`Klesti`) – čerstvé větve z kapsy na hromadu (schnou), suché z hromady do kapsy
	"slozit_vetve": {"name": "Složit větve na hromadu klestí", "target": "klesti_hromada", "tool": "", "time_s": 3.0,
		"stamina": 0.05, "skill": "", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	"vzit_vetve": {"name": "Vzít suché větve z hromady", "target": "klesti_hromada", "tool": "", "time_s": 2.0,
		"stamina": 0.04, "skill": "", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0},
	# prodavač/ka v Potravinách (`ProdavacPrace`): pokladna (minihra s mincemi v nabídce), bedny ze skladu do regálu, pečivo
	"markovat": {"name": "Namarkovat nákup", "target": "job_pokladna", "tool": "", "time_s": 1.5,
		"stamina": 0.0, "skill": "vyrecnost", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	"vzit_bednu": {"name": "Vzít bednu se zbožím na rameno", "target": "job_sklad", "tool": "", "time_s": 1.5,
		"stamina": 0.04, "skill": "kondice", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	"doplnit_regal": {"name": "Doplnit regál", "target": "job_regal", "tool": "", "time_s": 5.0,
		"stamina": 0.04, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	"prevzit_pecivo": {"name": "Převzít pečivo od řidiče", "target": "job_pecivo", "tool": "", "time_s": 3.0,
		"stamina": 0.02, "skill": "vyrecnost", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	# zahradník u sousedů (`ZahradnikPrace`): dočasná zóna na zahradě zákazníka (tráva, keře, záhony, výsadba)
	"posekat_zahradu": {"name": "Posekat trávník", "target": "job_zahrada_trava", "tool": "kosa", "time_s": 6.0,
		"stamina": 0.16, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "chop", "fail_chance": 0.0, "job": true},
	"strihat_ker": {"name": "Zastřihnout keř", "target": "job_ker", "tool": "nuzky_zahradni", "time_s": 7.0,
		"stamina": 0.08, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	"ryt_cizi": {"name": "Zrýt záhon", "target": "job_cizi_zahon", "tool": "lopata|motyka", "time_s": 10.0,
		"stamina": 0.18, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "dig", "fail_chance": 0.0, "job": true},
	"vysadit_kvetiny": {"name": "Vysadit květiny", "target": "job_vysadba", "tool": "", "time_s": 4.0,
		"stamina": 0.05, "skill": "zahradnictvi", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	# pomocník v pálenici (`PalenicePrace`): soudek kvasu na rameno → do kotle; topení je minihra (LMB u topeniště = přiložit
	# poleno, klik si vezme `PalenicePrace.on_click` dřív, než se akce spustí – `topit` je tu kvůli nápovědě); plnění lahví
	"vzit_sud": {"name": "Vzít soudek s kvasem na rameno", "target": "job_sudy", "tool": "", "time_s": 2.0,
		"stamina": 0.08, "skill": "kondice", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	"nalit_kvas": {"name": "Vylít kvas do kotle", "target": "job_kotel", "tool": "", "time_s": 4.0,
		"stamina": 0.08, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
	"topit": {"name": "Přiložit pod kotel (LMB = poleno)", "target": "job_topeniste", "tool": "", "time_s": 0.5,
		"stamina": 0.0, "skill": "ohen", "xp": 0, "level": 1, "anim": "kneel", "fail_chance": 0.0, "job": true},
	"plnit_lahve": {"name": "Naplnit lahve pálenkou", "target": "job_lahve", "tool": "", "time_s": 5.0,
		"stamina": 0.02, "skill": "", "xp": 0, "level": 1, "anim": "pour", "fail_chance": 0.0, "job": true},
}

## Nejmenší koeficient zkrácení času při maximální úrovni (× time_s).
const MIN_TIME_K := 0.5

static var _handlers := {}
static var _time_mods := {}          # id akce → Callable(aim, tool_id) -> float (násobek doby trvání)
static var _target_checks := {}      # id akce → Callable(aim, player_id) -> String (důvod, proč cíl nejde; "" = jde)


static func exists(action_id: String) -> bool:
	return DEFS.has(action_id)


static func set_handler(action_id: String, handler: Callable) -> void:
	_handlers[action_id] = handler


static func handler(action_id: String) -> Callable:
	return _handlers.get(action_id, Callable())


## Násobič doby trvání podle cíle a nástroje (velký strom trvá déle, pila je rychlejší). Bez registrace 1.
static func set_time_mod(action_id: String, f: Callable) -> void:
	_time_mods[action_id] = f


static func time_mod(action_id: String, aim: Dictionary, tool_id: String) -> float:
	var f: Callable = _time_mods.get(action_id, Callable())
	return float(f.call(aim, tool_id)) if f.is_valid() else 1.0


## Kontrola cíle akce (např. „nejdřív odvětvi kmen“). Vrací důvod, proč to nejde, nebo "".
static func set_target_check(action_id: String, f: Callable) -> void:
	_target_checks[action_id] = f


## M3.3: přidá další kontrolu cíle k té, co už akce má (lesní dělník: pila jen s ochrannými pomůckami); první důvod vyhraje.
static func chain_target_check(action_id: String, f: Callable) -> void:
	var prev: Callable = _target_checks.get(action_id, Callable())
	if not prev.is_valid():
		_target_checks[action_id] = f
		return
	_target_checks[action_id] = func(aim: Dictionary, player_id: int) -> String:
		var why := String(prev.call(aim, player_id))
		return why if why != "" else String(f.call(aim, player_id))


static func target_reason(action_id: String, aim: Dictionary, player_id: int) -> String:
	var f: Callable = _target_checks.get(action_id, Callable())
	return String(f.call(aim, player_id)) if f.is_valid() else ""


## Minimální úroveň dovednosti pro akci s daným nástrojem (`tool_level` přebíjí `level`).
static func required_level(def: Dictionary, equipped: String) -> int:
	var tl: Dictionary = def.get("tool_level", {})
	if tl.has(equipped):
		return int(tl[equipped])
	return int(def.get("level", 1))


## Vyhovuje nástroj v ruce definici? (`equipped` = id předmětu nebo "").
static func tool_ok(def: Dictionary, equipped: String) -> bool:
	var need := String(def.get("tool", ""))
	if need == "":
		return true
	return equipped in need.split("|")


## Čitelný název potřebného nástroje („Sekera / Motorová pila“).
static func tool_names(def: Dictionary) -> String:
	var out := []
	for t in String(def.get("tool", "")).split("|"):
		if t != "":
			out.append(ItemsDB.name_of(t) if ItemsDB.exists(t) else t)
	return " / ".join(out)


## Trvání akce v s pro hráče s danými dovednostmi (`sk` může být null → úroveň 1).
static func duration(def: Dictionary, sk: Skills) -> float:
	var b := sk.bonus(String(def.get("skill", ""))) if sk else 0.0
	return float(def.get("time_s", 1.0)) * lerpf(1.0, MIN_TIME_K, b)


## Šance selhání po započtení dovednosti.
## `luck` = Reputation.luck() (−0,2..+0,2 z karmy): dobrá karma šanci snižuje, špatná zvyšuje (až ±40 %).
static func fail_chance(def: Dictionary, sk: Skills, luck := 0.0) -> float:
	var b := sk.bonus(String(def.get("skill", ""))) if sk else 0.0
	return clampf(float(def.get("fail_chance", 0.0)) * (1.0 - b) * (1.0 - 2.0 * luck), 0.0, 1.0)


## Důvod, proč hráč akci nemůže spustit (prázdný řetězec = jde). Cíl se zde neřeší.
static func reason(def: Dictionary, p: Player, sk: Skills) -> String:
	if p.car != null or p.horse != null:
		return "V autě ani na koni to nejde."
	if p.fallen > 0.0 or p.busy or p.controls_locked:
		return "Teď ne."
	if not tool_ok(def, p.equipped):
		return "Chybí nástroj: %s." % tool_names(def)
	var skill := String(def.get("skill", ""))
	var lvl := required_level(def, p.equipped)
	if sk and skill != "" and not sk.has_level(skill, lvl):
		return "Chce to %s %d (máš %d)." % [Skills.skill_name(skill), lvl, sk.level(skill)]
	if p.stamina < float(def.get("stamina", 0.0)) or p.is_stamina_locked():
		return "Nemáš dost výdrže."
	return ""
