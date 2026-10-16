## Divoké čtyřnohé zvíře (srnec, divočák, sele, zajíc) – fyzika pohybu a chování podle AnimalSpecs.
##
## Fyzika: rychlost se mění jen s omezeným zrychlením / brzděním (hmotnost), zatáčí se s omezenou
## úhlovou rychlostí a dostředivým zrychlením (rychlé zvíře zatáčí širokým obloukem), do kopce zpomalí,
## na příliš prudký svah nevyleze, překážky (kmeny, zdi) obchází podle paprsků, přes nízké přeskočí
## (balistický skok podle výšky ve specifikaci), padá gravitací, auto ho může srazit (knock).
##
## Chování (stavový automat): pastva / rytí → přesun v okrsku podle stanoviště (les, okraj, pole) →
## odpočinek mimo dobu aktivity (leží) → pozornost (hlava nahoru, dívá se na člověka) → útěk (od hrozby
## a k lesu; srnec štěkne, zajíc kličkuje) → uklidnění. Zajíc v pelechu strne a vyrazí až zblízka,
## bachyně se selaty může zaútočit. Vnímání: zrak (tma, les a přikrčení ho zkracují), sluch (běh,
## auto), čich (po větru cítí dál). Jezdce na koni se zvěř bojí méně.
##
## Klid: zvěř je plachá, ale ne hysterická – útěk je klusem / cvalem podle blízkosti hrozby (flee_speed),
## nehybného člověka dál než flight si časem přivykne (calm) a po chvíli se vrátí k pastvě.
##
## Úroveň detailu: do 110 m od hráče plná fyzika, do 260 m bez kolizí (výška z terénu), dál neviditelné
## a „přemýšlí“ jen jednou za 1,5 s. Vzdálenost se bere od NEJBLIŽŠÍHO hráče (`World.nearest_player_dist`
## prochází celé `world.players`), takže s více hráči je zvíře FULL, kdykoli je do 110 m od kteréhokoli z nich
## (na serveru v MP tedy fyziku a AI dostane každé zvíře poblíž kohokoli; daleko od všech jen zjednodušeně).
##
## Multiplayer (příprava): zvíře má `net_id` a `authority`. Autorita (výchozí true = singleplayer / server)
## simuluje AI a fyziku jako vždy. Klientské „loutka“ (`authority = false`, vyrábí ji `Fauna._spawn_puppet`)
## nemá AI ani fyziku: `puppet_push` mu předá snímek ze serveru, `_puppet_process` z posledních snímků
## interpoluje polohu a yaw (zpoždění PUPPET_DELAY) a rig animuje ze rychlosti; LOD podle nejbližšího lokálního hráče.
class_name Animal
extends CharacterBody3D

enum Lod { FULL, NEAR, FAR }
## M8.D2d: konstanty chování jsou `static var` – ladí je menu pro vývojáře (F3 → Zvěř/…, `scripts/dev/tune_zver.gd`).
static var FULL_R := 110.0
static var NEAR_R := 260.0
static var GRAVITY := 20.0
## Stavy pro síť (index ve snímku = pozice v poli); nové stavy jen na konec.
const STATES := ["graze", "move", "rest", "alert", "flee", "freeze", "charge", "dead"]
const FLAG_DEAD := 1
const FLAG_MALE := 2
const FLAG_YOUNG := 4
const FLAG_WINTER := 8
static var PUPPET_DELAY := 0.15      # loutka se zobrazuje o tolik s pozadu (interpolace mezi snímky)
static var PUPPET_EXTRAP := 0.25     # nejvýš tolik s se dopředu odhaduje pohyb, když snímek nepřišel
const PUPPET_BUF := 4                # kolik posledních snímků se drží
# ---- M2.9 postřelení (`shot`): energie (J) potřebná k okamžitému usmrcení srnce (24 kg); pro těžší zvíře × (hmotnost / 24)^0,6.
static var KILL_HEAD_J := 40.0       # zásah do hlavy
static var KILL_HEART_J := 75.0      # komora (srdce a plíce)
static var KILL_REF_KG := 24.0       # hmotnost, pro kterou platí energie výše
static var KILL_MASS_EXP := 0.6      # … těžší zvíře potřebuje × (hmotnost / KILL_REF_KG)^tohle
static var WOUND_RUN_HEART_M := [20.0, 60.0]   # srdce: tolik m ještě uběhne a padne
static var WOUND_RUN_BELLY_M := [200.0, 600.0] # břicho: uteče daleko a zalehne
static var WOUND_LIE_MIN := [60.0, 180.0]      # zalehlé zvíře zhyne za 1–3 herní hodiny
static var WOUND_RISE_M := 15.0      # při přiblížení na tolik m se zalehlé zvíře může zvednout a utéct dál
static var WOUND_RISE_RUN_M := [100.0, 250.0]
static var WOUND_RISE_P := 0.5
static var WOUND_RISES_MAX := 2
static var WOUND_FLEE_K := 1.3       # postřelené do břicha běží únikovou rychlostí × tohle
static var SHOT_PANIC_S := 40.0      # po zásahu zvíře a stádo prchá tolik s
static var LIMP_S := 900.0           # postřelená noha: tolik s kulhá (zpomalené, stopa)
static var LIMP_SPEED_K := 0.55
static var LIMP_BLOOD_S := 120.0     # postřelená noha: krvavá stopa jen prvních tolik s
static var BLOOD_STEP_M := 2.5       # krvavá kapka každých tolik m běhu
static var STAND_HEIGHT_M := 3.0     # hráč výš než tolik m nad terénem (posed) je zvěři hůř vidět a cítit
static var STAND_SIGHT_K := 0.6
## M8.10: kde je „vysoká tráva“ (srnec v ní skáče odrazovými skoky): třída plochy `Fields.class_at`
## (1 orná půda, 2 louka) → měsíce, kdy porost stojí (obilí do žní, louka do první seče). Hrubé, než M8.12 dá
## skutečnou výšku plodin.
const TALL_VEG_MONTHS := {1: [5, 6, 7], 2: [5, 6]}
static var TALL_VEG_CHECK_S := 0.5

## --- M8.D2d: čísla dřív zapsaná přímo ve vzorcích (stejné hodnoty)
# úroveň detailu a takt rozhodování
static var LOD_CHECK_S := 0.5        # jak často se přepočítá LOD podle hráčů (s)
static var FAR_THINK_S := 1.5        # daleko (LOD FAR) přemýšlí jednou za tolik s
static var THINK_FULL_S := 0.25      # rozhodování blízko hráče (s)
static var THINK_NEAR_S := 0.6       # … v LOD NEAR
static var NEAR_ANIM_S := 0.1        # LOD NEAR se animuje jen jednou za tolik s
# rozhodování: hrozba a útěk
static var BAD_RAIN := 0.5           # nečas: déšť nad tolik …
static var BAD_WIND := 12.0          # … nebo vítr nad tolik m/s → zvěř zalehne do úkrytu
static var APPROACH_V := 0.35        # m/s – hrozba se „přibližuje“, když se vzdálenost zkracuje rychleji
static var FREEZE_AWARE := 0.4       # zajíc strne od této pozornosti (hrozba dál než úniková vzdálenost)
static var FLEE_AWARE := 0.45        # útěk při pozornosti nad tolik …
static var FLEE_PANIC_K := 0.5       # … nebo vždy, když je hrozba blíž než úniková vzdálenost × tohle
static var HERD_ALARM_S := 6.0       # útěk člena vyplaší stádo na tolik s
static var ALERT_AWARE := 0.5        # pozor (hlava nahoru) od této pozornosti
static var ALERT_R_APPROACH := 2.2   # … když je hrozba blíž než úniková vzdálenost × tohle a přibližuje se
static var ALERT_R_STILL := 1.6      # … × tohle, když se nepřibližuje
static var FLEE_MIN_S := 3.0         # útěk trvá aspoň tolik s
static var FLEE_SPRINT_K := 0.6      # plný trysk, když je hrozba blíž než úniková vzdálenost × tohle (plynule)
static var CAR_PANIC_V := 8.0        # m/s – auto rychlejší než tohle → zvíře utíká tryskem
static var ZIG_R := 30.0             # m – zajíc kličkuje, když je hrozba blíž
static var ZIG_EVERY := [0.5, 1.1]   # s – klička jednou za (od–do)
static var ZIG_ANGLE := [0.5, 0.9]   # rad – úhel kličky (od–do)
static var ZIG_HOLD := 0.45          # s – jak dlouho klička drží
# útok bachyně
static var CHARGE_R := 11.0          # m – bachyně se selaty zaútočí na přibližujícího se člověka blíž než tohle
static var CHARGE_MAX_S := 7.0       # s – útok nejdéle
static var CHARGE_GIVEUP_R := 25.0   # m – dál útok vzdá
static var CHARGE_SPEED_K := 1.3     # rychlost útoku = cval × tohle
static var CHARGE_HIT_R := 1.4       # m – zásah
static var ATTACK_PUSH := 5.0        # m/s – odhození člověka
static var ATTACK_LIFT := 3.0        # m/s – nadhození
static var ATTACK_KNOCK_S := 4.5     # s – člověk leží
static var ATTACK_DMG := 12.0        # zranění kly
# pozornost, klid, odpočinek
static var FREEZE_CALM_AWARE := 0.15 # strnulý zajíc se uklidní pod touto pozorností …
static var FREEZE_MAX_S := 40.0      # … nebo nejpozději po tolika s
static var ALERT_CALM_S := 8.0       # s – hrozba se nepřibližuje (a je dál než úniková vzdálenost) → uklidní se
static var CALM_AWARE := 0.3         # pozornost po uklidnění nejvýš
static var ALERT_COOLDOWN_S := 30.0  # s – pak si nepřibližující se hrozby tolik nevšímá
static var ALERT_HOLD := [5.0, 12.0] # s – pozor trvá (od–do), pak zpět k pastvě
static var ALERT_END_AWARE := 0.5    # … když pozornost klesne pod tohle
static var REST_MIN_S := 20.0        # s – odpočívá aspoň tolik
# pastva a přesuny
static var FOLLOW_REST_R := 5.0      # m – člen u odpočívajícího vůdce si lehne
static var FOLLOW_GAP := 3.0         # m – člen dál od svého místa ve skupině jde za vůdcem
static var FOLLOW_K := 0.35          # rychlost dohánění = vzdálenost × tohle (1/s)
static var FOLLOW_MIN_K := 0.6       # … nejméně krok × tohle
static var FOLLOW_MAX_K := 0.8       # … nejvíc klus × tohle
static var SHELTER_AFTER_S := 8.0    # s mimo dobu aktivity → jde do úkrytu
static var SHELTER_BAD_S := 15.0     # s v nečase → do úkrytu
static var SHELTER_SCORE := 0.4      # úkryt = stanoviště se skóre nad tolik
static var SHELTER_R := 150.0        # m – úkryt hledá v tomto okruhu
static var GRAZE_HOLD := [20.0, 60.0] # s – pase se na místě (od–do)
static var MOVE_CHANCE := 0.35       # pak se s touto šancí přesune jinam v okrsku (jinak jen pár kroků)
static var HOME_RETURN_K := 0.8      # dál od domova než okrsek × tohle → vrací se
static var HOME_WANDER_K := 0.5      # nový cíl v okruhu okrsek × tohle
static var STEP_ANGLE := 1.2         # rad – pár kroků při pastvě: odchylka směru
static var STEP_DIST := [1.5, 5.0]   # m – pár kroků při pastvě (od–do)
static var ARRIVE_R := 1.2           # m – cíl dosažen
static var LONG_MOVE_D := 60.0       # m – delší přesun …
static var LONG_MOVE_K := 1.5        # … rychlejším krokem (× tohle)
# vnímání (zrak, sluch, čich)
static var AWARE_DECAY_NONE := 0.2   # 1/s – pokles pozornosti bez hráče
static var AWARE_DECAY := 0.08       # 1/s – pokles pozornosti, když hrozbu nevnímá
static var NIGHT_SIGHT := 0.3        # v noci zrak × tohle (ve dne 1)
static var FOG_SIGHT := 0.35         # v husté mlze zrak × tohle
static var COVER_SIGHT := 0.55       # člověk v lese: zrak × tohle
static var CROUCH_SIGHT := 0.5       # přikrčený člověk: zrak × tohle
static var CAR_SIGHT := 0.8          # auto: zrak × tohle
static var CAR_HEAR_BASE := 1.2      # auto: sluch × (tohle + min(v / CAR_HEAR_V, CAR_HEAR_MAX))
static var CAR_HEAR_V := 10.0        # m/s
static var CAR_HEAR_MAX := 1.2
static var HORSE_SIGHT := 0.6        # jezdec na koni: zrak × tohle (koně se zvěř tolik nebojí)
static var HORSE_HEAR_V := 6.0       # kůň: sluch × clamp(v / tohle, HORSE_HEAR_MIN, HORSE_HEAR_MAX)
static var HORSE_HEAR_MIN := 0.2
static var HORSE_HEAR_MAX := 1.2
static var STEP_HEAR_FROM := 2.0     # m/s – kroky člověka slyší od této rychlosti …
static var STEP_HEAR_RANGE := 5.0    # m/s – … naplno o tolik rychleji
static var STEP_HEAR_MAX := 1.2      # nejvýš sluch × tohle
static var SMELL_WIND_MIN := 0.5     # m/s – čich jen při větru nad tolik
static var SMELL_CONE := 0.6         # vítr musí vanout od člověka ke zvířeti (kosinus odchylky nad tohle)
static var SMELL_K := 1.3            # po větru cítí na zrak × tohle
static var AWARE_BASE := 0.3         # nárůst pozornosti za s: tohle + AWARE_NEAR × (1 − d / dosah)
static var AWARE_NEAR := 1.2
static var STILL_V := 0.8            # m/s – člověk pomalejší je „nehybný“ (zvěř si zvyká)
static var CALM_K := 0.7             # návyk: nárůst pozornosti × (1 − klid druhu × tohle)
static var HABIT_CAP := 0.7          # návyk: pozornost nejvýš
static var CAR_FLIGHT_V := 12.0      # auto: úniková vzdálenost × clamp(v / tohle, min, max)
static var CAR_FLIGHT_MIN := 0.4
static var CAR_FLIGHT_MAX := 1.3
static var HORSE_FLIGHT := 0.45      # jezdec na koni: úniková vzdálenost × tohle
static var LISTEN_AWARE := 0.15      # uši ke zdroji zvuku od této pozornosti
# směr útěku
static var FLEE_FAN := 0.35          # rad – rozestup 7 zkoušených směrů útěku
static var FLEE_PROBE := 35.0        # m – jak daleko se směr útěku posuzuje
static var FLEE_AWAY_W := 1.2        # váha „pryč od hrozby“
static var FLEE_FOREST_W := 0.8      # váha „do lesa“
static var FLEE_EDGE_PEN := 3.0      # postih za směr mimo mapu
static var FLEE_SLOPE_PEN := 1.5     # postih za příliš prudký svah
# pohyb a překážky
static var AVOID_DECAY := 2.0        # rad/s – návrat po obcházení
static var LOOK_BACK_R := 2.0        # při pastvě se ohlíží po člověku blíž než úniková vzdálenost × tohle
static var LOOK_RATE := 1.5          # rad/s – otáčení hlavy k člověku
static var TURN_SLOW_MIN := 0.25     # při ostrém úhlu rychlost × cos(úhel), nejméně tohle
static var SLOPE_SLOW_FROM := 0.6    # do kopce zpomalí od podílu největšího svahu …
static var SLOPE_AVOID_S := 1.0      # s – na příliš prudkém svahu uhne bokem na tolik
static var PROBE_S := 0.15           # s – paprsky na překážky jednou za
static var PROBE_MIN_V := 0.4        # m/s – … jen v pohybu rychleji
static var PROBE_H := 0.6            # paprsek ve výšce kohoutku × tohle
static var PROBE_REACH_K := 0.7      # dosah paprsku = rychlost × tohle (s) …
static var PROBE_REACH_MIN := 1.2    # m
static var PROBE_REACH_MAX := 8.0    # m
static var PROBE_SIDE_A := 0.6       # rad – zkouší obejít o tento úhel …
static var PROBE_WIDE_A := 1.2       # rad – … nebo o tento
static var PROBE_AVOID_S := 0.7      # s – obcházení drží
static var JUMP_MIN_V := 2.5         # m/s – přeskakuje překážky od této rychlosti
static var JUMP_CLEAR := 0.25        # m – nad překážkou musí být volno o tolik výš
static var JUMP_H_K := 0.85          # výška skoku = výška druhu × tohle + JUMP_H_ADD
static var JUMP_H_ADD := 0.15        # m
static var PRONK_V := 0.7            # odrazové skoky od rychlosti cval × tohle
static var PRONK_TALL_V := 0.4       # … ve vysoké trávě od cval × tohle
static var PRONK_H_K := 0.6          # výška odrazového skoku = pronk × tohle + PRONK_H_ADD
static var PRONK_H_ADD := 0.1        # m
static var PRONK_EVERY := [0.8, 1.6] # s mezi odrazovými skoky (od–do)
static var PRONK_TALL_EVERY := [0.45, 0.8]   # … ve vysoké trávě
static var STUCK_V := 1.0            # m/s – zaseknutí se hlídá od této rychlosti
static var STUCK_FRAC := 0.25        # posunulo se méně než tento podíl rychlosti → zaseknuté
static var STUCK_S := 0.8            # s – po tolika s zaseknutí zkusí jiný směr
static var STUCK_TURN := [0.9, 1.8]  # rad – úhel úhybu (od–do)
static var STUCK_HOLD := 1.2         # s
static var STUCK_SLOW := 0.3         # rychlost × tohle
# vzhled
static var ANIM_BLEND := 3.0         # 1/s – prolínání pastvy, pozornosti, lehání
static var LIE_BLEND_K := 0.6        # lehání × tohle (pomalejší)
static var ALERT_FLEE_V := 2.0       # m/s – v útěku pomaleji = hlava nahoru (rozhlíží se)
static var AIR_V := 4.0              # m/s svislé rychlosti = plně ve skoku (nohy složené)
# srážka s autem a uhynutí
static var KNOCK_KILL_V := 6.0       # m/s – srážka rychlejší než tohle zvíře usmrtí …
static var KNOCK_SMALL_KG := 10.0    # … malé zvíře (pod tolik kg) …
static var KNOCK_SMALL_V := 3.0      # … už od této rychlosti
static var KNOCK_MASS_REF := 60.0    # odhození × clamp(tohle / hmotnost, KNOCK_MIN, KNOCK_MAX)
static var KNOCK_MIN := 0.3
static var KNOCK_MAX := 1.5
static var KNOCK_ALARM_S := 12.0     # s – sražené zvíře vyplaší stádo
static var KNOCK_SCARE_S := 10.0     # s – odhozené (živé) zvíře vyplaší stádo
static var DEAD_FRICTION := 8.0      # m/s² – tělo dojede po zemi
static var DEAD_BLEND := 3.0         # 1/s – pád na bok
static var CORPSE_S := 600.0         # s – mrtvé zvíře (bez myslivce) zmizí, až ho nikdo nevidí

var spec: Dictionary
var species := ""
var fauna: Fauna
var herd: Herd
var slot_i := 0
var rig: QuadrupedRig
var rng := RandomNumberGenerator.new()
var home := Vector3.ZERO
var male := false
var young := false
var dead := false
var net_id := 0                      # stabilní síťové číslo (Fauna ho přiděluje; 0 = nepřiděleno)
var authority := true                # true = simuluje se tady; false = loutka podle snímků serveru
var keep_corpse := false             # srážka s autem: tělo zůstane ležet, dokud si ho nevyzvedne myslivec (Hunter)
# M2.9 postřelení: "" zdravé, "srdce" (uběhne a padne), "bricho" (uteče daleko, zalehne, zhyne), "noha" (kulhá)
var wound := ""
var wound_left := 0.0                # kolik m ještě uběhne
var wound_lie := false               # zalehlé (ještě žije)
var wound_die_min := 0.0             # herní minuta (Clock.minutes), kdy zalehlé zvíře zhyne
var wound_src := Vector3.ZERO        # odkud přišla rána (od toho uteče)
var shot_by := {}                    # {id, weapon, legal, reasons, zone} – kdo a čím zvíře postřelil (čte `Hunting`)
var limp_t := 0.0                    # do konce kulhání (s)
var _wound_last := Vector3.INF       # poloha při minulém kroku (krvavá stopa, uběhnutá vzdálenost)
var _blood_acc := 0.0
var _wound_rises := 0
var _rise_rolled := false

var state := "graze"                 # graze, move, rest, alert, flee, freeze, charge, dead
var state_t := 0.0                   # jak dlouho trvá stav (s)
var target := Vector3.INF
var yaw := 0.0
var speed := 0.0                     # rychlost vpřed (m/s)
var want_speed := 0.0
var want_dir := Vector3.FORWARD
var aware := 0.0                     # 0..1 jak moc si všiml hrozby
var threat: Node3D = null
var threat_d := INF

var _lod := Lod.FAR
var _lod_t := 0.0
var _think_t := 0.0
var _far_dt := 0.0
var _avoid := 0.0                    # úhlový posun kvůli překážce (rad)
var _avoid_t := 0.0
var _probe_t := 0.0
var _zig_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _prev_threat_d := INF
var _approaching := false            # hrozba se přibližuje (z posledního _think)
var _calm_t := 0.0                   # jak dlouho v pozoru hrozba nepřibližuje se (s)
var _alert_cd := 0.0                 # do té doby (s) se nepřibližující hrozba znovu nevšímá
var _yaw_rate := 0.0
var _slope := 0.0
var _graze := 0.0
var _alert := 0.0
var _lie := 0.0
var _crouch := 0.0
var _sit := 0.0                     # zajíc „panáček" (sedí na zadních a rozhlíží se)
var _pronk_t := 0.0                 # odstup času do příštího odrazového skoku při útěku
var _anim_dt := 0.0                 # akumulace času pro animaci ve vzdáleném LOD
var _tall := false                   # M8.10: stojí ve vysoké trávě / obilí (zjišťuje se 2× za s)
var _tall_t := 0.0
var _charged := false
var _noise_pos := Vector3.ZERO         # odkud zazněl výstřel / hluk (M2.8), odtud zvíře prchá
var _noise_t := 0.0                    # do kdy (s) zvíře prchá před hlukem
var _snd: AudioStreamPlayer3D
var _snd_t := 5.0
var _dead_t := 0.0
var _foot: CollisionShape3D
var _torso: CollisionShape3D
var _soil: GPUParticles3D           # odhrnutá hlína při rytí (divočák)
var _pbuf: Array = []                # loutka: poslední snímky [čas příjmu, poloha, yaw, rychlost]
var _p_hop := 0.0                    # loutka: výška nad terénem v minulém kroku (odhad svislé rychlosti skoku)


func setup(f: Fauna, id: String, pos: Vector3, h: Herd, variant: Dictionary, seed_: int) -> void:
	fauna = f
	species = id
	spec = AnimalSpecs.get_spec(id)
	herd = h
	rng.seed = seed_
	male = variant.get("male", false)
	young = spec.has("base")
	home = pos
	position = pos + Vector3(0, 0.05, 0)
	yaw = rng.randf() * TAU
	want_dir = Vector3(sin(yaw), 0, cos(yaw))
	rig = QuadrupedModel.build(spec, variant)
	rig.name = "Model"


func _ready() -> void:
	collision_layer = 4                # jako psi a vesničané → auta před zvířetem brzdí, srazí ho
	collision_mask = 1 | 2 | 8 | 16
	if not authority:
		collision_layer = 0            # loutka je jen vizuální (kolize a zásahy řeší server)
		collision_mask = 0
	floor_max_angle = deg_to_rad(float(spec["max_slope"]) + 5.0)
	floor_snap_length = 0.5
	safe_margin = 0.02
	var g := QuadrupedModel.geometry(spec)
	# dolní kapsle pod trupem nese zvíře (kontakt se zemí), kvádr trupu naráží do překážek
	var sh := CapsuleShape3D.new()
	sh.radius = clampf(float(spec["chest"][0]) * 0.8, 0.05, 0.3)
	sh.height = maxf(g["shoulder_h"], sh.radius * 2.0 + 0.02)
	_foot = CollisionShape3D.new()
	_foot.shape = sh
	_foot.position.y = sh.height * 0.5
	add_child(_foot)
	var bx := BoxShape3D.new()
	var ch: Array = spec["chest"]
	bx.size = Vector3(ch[0] * 2.0, ch[1] * 1.6, float(spec["length"]) + ch[1] * 0.6)
	_torso = CollisionShape3D.new()
	_torso.shape = bx
	_torso.position = Vector3(0, float(g["y_mid"]) + ch[1] * 0.1, 0)
	add_child(_torso)
	add_child(rig)
	rig.rotation.y = yaw
	rig.footfall.connect(_on_footfall)
	rig.ground_fn = fauna.terrain.height_at
	rig.foot_ik = false                # zapne se až v LOD FULL (štedří výkon)
	rig.visible = false
	if spec["behaviour"] == "rooter":
		_soil = _soil_particles()
		_soil.position = Vector3(0, -float(spec["head"][1]) * 0.5, float(spec["head"][0]) * 0.85)
		rig.head.add_child(_soil)
	_last_pos = global_position
	_think_t = rng.randf() * 1.0
	_lod_t = rng.randf() * 0.5


# ------------------------------------------------------------------ smyčka

func _physics_process(delta: float) -> void:
	var __t0 := Tests.prof_t0()
	_physics_impl(delta)
	Tests.prof_add("animal", __t0)


func _physics_impl(delta) -> void:
	if fauna == null:
		return
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = LOD_CHECK_S
		_update_lod()
	if not authority:
		_puppet_process(delta)
		return
	if dead:
		_dead_update(delta)
		return
	if _lod == Lod.FAR:
		_far_dt += delta
		if _far_dt < FAR_THINK_S:
			return
		delta = _far_dt
		_far_dt = 0.0
		state_t += delta
		_think(delta)
		_steer(delta)
		_kinematic_move(delta)
		return
	state_t += delta
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = THINK_FULL_S if _lod == Lod.FULL else THINK_NEAR_S
		_think(THINK_FULL_S if _lod == Lod.FULL else THINK_NEAR_S)
	_steer(delta)
	if _lod == Lod.FULL:
		_physics_move(delta)
	else:
		_kinematic_move(delta)
	# vzdálená zvířata (LOD NEAR) se animují jen ~10× za sekundu – na dálku to není poznat
	_anim_dt += delta
	if _lod == Lod.FULL or _anim_dt >= NEAR_ANIM_S:
		_animate(_anim_dt)
		_anim_dt = 0.0
	_sounds(delta)


func _update_lod() -> void:
	var d: float = fauna.world.nearest_player_dist(global_position)
	var want := Lod.FAR
	if d < FULL_R:
		want = Lod.FULL
	elif d < NEAR_R:
		want = Lod.NEAR
	if want == _lod:
		return
	_lod = want
	rig.visible = _lod != Lod.FAR
	rig.foot_ik = _lod == Lod.FULL
	var on := _lod == Lod.FULL
	_foot.disabled = not on
	_torso.disabled = not on
	if on and authority:
		# zpátky na terén (daleko se pohybovalo bez kolizí)
		global_position.y = fauna.terrain.height_at(global_position.x, global_position.z) + 0.05
		velocity = Vector3.ZERO


# ------------------------------------------------------------------ síť: loutka a snímek

## Kompaktní záznam pro klienty: [net_id, index druhu (Fauna.SPECIES_IDS), x, y, z (dm), yaw (1/1024 otáčky),
## rychlost (dm/s), index stavu (STATES), příznaky]. Všechno celá čísla (var_to_bytes je pak malé).
func net_record() -> Array:
	var flags := 0
	if dead:
		flags |= FLAG_DEAD
	if male:
		flags |= FLAG_MALE
	if young:
		flags |= FLAG_YOUNG
	if fauna.clock.month() >= 11 or fauna.clock.month() <= 3:
		flags |= FLAG_WINTER
	var p := global_position
	return [net_id, Fauna.SPECIES_IDS.find(species), roundi(p.x * 10.0), roundi(p.y * 10.0), roundi(p.z * 10.0),
		roundi(fposmod(yaw, TAU) / TAU * 1024.0), roundi(speed * 10.0), maxi(STATES.find(state), 0), flags]


## Loutka dostala snímek ze serveru (čas příjmu `t` v s, poloha, yaw, rychlost, index stavu, příznaky).
func puppet_push(t: float, pos: Vector3, yaw_: float, spd: float, state_i: int, flags: int) -> void:
	var st: String = STATES[clampi(state_i, 0, STATES.size() - 1)]
	var known := not _pbuf.is_empty()
	_pbuf.append([t, pos, yaw_, spd])
	while _pbuf.size() > PUPPET_BUF:
		_pbuf.pop_front()
	dead = (flags & FLAG_DEAD) != 0
	if dead:
		st = "dead"
	if st != state:
		state = st
		state_t = 0.0
		if known:                       # zvuk podle změny stavu (nový záznam nebouchá)
			if st == "flee":
				_play("alarm")
			elif st == "charge":
				_play("attack")


## Vzorek z vyrovnávací paměti snímků v čase `rt`: [poloha, yaw, rychlost]. Mezi dvěma snímky lineárně,
## za posledním krátce dopředu podle rychlosti (PUPPET_EXTRAP), pak drží. Sdílí ho Horse.
static func puppet_sample(buf: Array, rt: float) -> Array:
	var first: Array = buf[0]
	if buf.size() == 1 or rt <= float(first[0]):
		return [first[1], first[2], first[3]]
	for i in range(1, buf.size()):
		var b: Array = buf[i]
		if rt <= float(b[0]):
			var a: Array = buf[i - 1]
			var span := float(b[0]) - float(a[0])
			var k := clampf((rt - float(a[0])) / maxf(span, 0.0001), 0.0, 1.0)
			var pa: Vector3 = a[1]
			var pb: Vector3 = b[1]
			return [pa.lerp(pb, k), lerp_angle(float(a[2]), float(b[2]), k), lerpf(float(a[3]), float(b[3]), k)]
	var last: Array = buf[buf.size() - 1]
	var over := minf(rt - float(last[0]), PUPPET_EXTRAP)
	var lp: Vector3 = last[1]
	var ly: float = last[2]
	var ls: float = last[3]
	return [lp + Vector3(sin(ly), 0.0, cos(ly)) * ls * over, ly, ls]


## Krok loutky (jen `authority == false`): žádná AI ani fyzika, jen interpolace a animace.
func _puppet_process(delta: float) -> void:
	if _pbuf.is_empty():
		return
	var s := Animal.puppet_sample(_pbuf, Time.get_ticks_msec() / 1000.0 - PUPPET_DELAY)
	var np: Vector3 = s[0]
	var ny: float = s[1]
	speed = s[2]
	_yaw_rate = lerpf(_yaw_rate, wrapf(ny - yaw, -PI, PI) / maxf(delta, 0.001), 0.3)
	yaw = ny
	global_position = np
	if _lod == Lod.FAR:
		return
	if dead:
		rig.dead = move_toward(rig.dead, 1.0, delta * DEAD_BLEND)
		rig.speed = 0.0
		rig.animate(delta)
		return
	# sklon těla a případný skok (výška nad terénem) – jen pro viditelná zvířata
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var L: float = spec["length"]
	var h0: float = fauna.terrain.height_at(np.x, np.z)
	var h1: float = fauna.terrain.height_at(np.x + fwd.x * L, np.z + fwd.z * L)
	_slope = atan2(h1 - h0, L)
	var hop := np.y - h0 - 0.05
	velocity = Vector3(0.0, (hop - _p_hop) / maxf(delta, 0.001), 0.0)
	_p_hop = hop
	_anim_dt += delta
	if _lod == Lod.FULL or _anim_dt >= NEAR_ANIM_S:
		_animate(_anim_dt)
		_anim_dt = 0.0
	_sounds(delta)


# ------------------------------------------------------------------ vnímání a rozhodování

func _think(dt: float) -> void:
	if wound != "" and _wound_think(dt):
		return
	_perceive(dt)
	var h: float = fauna.clock.hour()
	var active := AnimalSpecs.is_active(spec, h)
	var weather: Weather = fauna.weather
	var bad_weather := weather != null and (weather.rain > BAD_RAIN or weather.wind > BAD_WIND)
	var beh: String = spec["behaviour"]
	# --- hrozba
	if herd and herd.alarmed() and state != "flee" and state != "charge":
		_enter("flee")
	if _noise_t > 0.0:
		_noise_t -= dt
		if state != "flee" and state != "charge":
			_enter("flee")
	if threat:
		var flight := _flight_distance()
		var approaching := _prev_threat_d - threat_d > APPROACH_V * dt
		_approaching = approaching
		if beh == "hare" and state in ["rest", "graze", "freeze", "move"] and threat_d > flight and aware > FREEZE_AWARE:
			if state != "freeze":
				_enter("freeze")
		elif threat_d < flight and (aware > FLEE_AWARE or threat_d < flight * FLEE_PANIC_K):
			if beh == "rooter" and herd and herd.has_young and not young and not male and threat_d < CHARGE_R \
					and approaching and not _charged and threat is Player:
				_enter("charge")
			elif state != "flee" and state != "charge":
				_enter("flee")
				if herd:
					herd.alarm(threat.global_position, HERD_ALARM_S)
		elif aware > ALERT_AWARE and threat_d < flight * (ALERT_R_APPROACH if approaching else ALERT_R_STILL) and state in ["graze", "move", "rest"] \
				and (_alert_cd <= 0.0 or approaching):
			_enter("alert")
	else:
		_approaching = false
	_prev_threat_d = threat_d
	_alert_cd = maxf(_alert_cd - dt, 0.0)
	# --- stavy
	match state:
		"flee":
			var src := herd.alarm_pos if herd and herd.alarmed() else Vector3.INF
			if threat:
				src = threat.global_position
			if src == Vector3.INF and _noise_t > 0.0:
				src = _noise_pos
			if src == Vector3.INF:
				_enter("move")
				return
			var safe: float = spec["safe"]
			var d := global_position.distance_to(src)
			if d > safe and (herd == null or not herd.alarmed()) and state_t > FLEE_MIN_S:
				_enter("alert")
				return
			var away := global_position - src
			away.y = 0.0
			want_dir = _flee_dir(away.normalized())
			var top: float = spec["gaits"]["gallop"]
			var fl: float = spec["flight"]
			want_speed = lerpf(float(spec["flee_speed"]), top, clampf(1.0 - d / maxf(fl * FLEE_SPRINT_K, 1.0), 0.0, 1.0))
			if threat is Car and (threat as Car).linear_velocity.length() > CAR_PANIC_V:
				want_speed = top
			if limp_t > 0.0:
				want_speed *= LIMP_SPEED_K
			if beh == "hare":
				_zig_t -= dt
				if _zig_t <= 0.0 and d < ZIG_R:
					_zig_t = rng.randf_range(ZIG_EVERY[0], ZIG_EVERY[1])
					_avoid = rng.randf_range(ZIG_ANGLE[0], ZIG_ANGLE[1]) * (1.0 if rng.randf() < 0.5 else -1.0)
					_avoid_t = ZIG_HOLD
		"charge":
			if threat == null or state_t > CHARGE_MAX_S or threat_d > CHARGE_GIVEUP_R:
				_charged = true
				_enter("flee")
				return
			var to := threat.global_position - global_position
			to.y = 0.0
			want_dir = to.normalized()
			want_speed = float(spec["gaits"]["canter"]) * CHARGE_SPEED_K
			if threat_d < CHARGE_HIT_R:
				_attack()
		"freeze":
			want_speed = 0.0
			if threat == null or aware < FREEZE_CALM_AWARE or state_t > FREEZE_MAX_S:
				_enter("graze")
		"alert":
			want_speed = 0.0
			# hrozba se 8 s nepřibližuje a je za únikovou vzdáleností → zvíře se uklidní
			if threat != null and not _approaching and threat_d > _flight_distance():
				_calm_t += dt
			else:
				_calm_t = 0.0
			if _calm_t > ALERT_CALM_S:
				aware = minf(aware, CALM_AWARE)
				_alert_cd = ALERT_COOLDOWN_S
				_enter("graze" if active else "rest")
				return
			if state_t > rng.randf_range(ALERT_HOLD[0], ALERT_HOLD[1]) and (threat == null or aware < ALERT_END_AWARE):
				_enter("graze" if active else "rest")
		"rest":
			want_speed = 0.0
			if active and not bad_weather and state_t > REST_MIN_S:
				_enter("graze")
		"graze":
			_follow_or_idle(dt, active, bad_weather)
		"move":
			_follow_or_idle(dt, active, bad_weather)


## Pastva a přesuny: člen skupiny drží místo u vůdce, vůdce (nebo samotář) vybírá cíle v okrsku.
func _follow_or_idle(_dt: float, active: bool, bad_weather: bool) -> void:
	var leader: Node = herd.get_leader() if herd else null
	if leader != null and leader != self:
		var lp: Vector3 = leader.global_position + Basis(Vector3.UP, leader.yaw) * herd.slot(slot_i)
		var d := Vector3(lp.x - global_position.x, 0, lp.z - global_position.z)
		if leader.state == "rest" and d.length() < FOLLOW_REST_R:
			_enter("rest")
			return
		if d.length() > FOLLOW_GAP:
			want_dir = d.normalized()
			want_speed = clampf(d.length() * FOLLOW_K, float(spec["gaits"]["walk"]) * FOLLOW_MIN_K, float(spec["gaits"]["trot"]) * FOLLOW_MAX_K)
			state = "move"
			return
		want_speed = 0.0
		state = "graze"
		return
	# vůdce / samotář: mimo dobu aktivity (nebo v nečase) si jde lehnout do úkrytu
	if (not active and state_t > SHELTER_AFTER_S) or (bad_weather and state_t > SHELTER_BAD_S):
		var shelter := "forest" if bad_weather or spec["habitat"] != "field" else "field"
		if fauna.score(shelter, global_position.x, global_position.z) > SHELTER_SCORE:
			_enter("rest")
			return
		if target == Vector3.INF:
			target = fauna.random_point(global_position, SHELTER_R, shelter, rng)
			state = "move"
	if state == "move" and target == Vector3.INF:
		_enter("graze")
	if state == "graze" and state_t > rng.randf_range(GRAZE_HOLD[0], GRAZE_HOLD[1]):
		if rng.randf() < MOVE_CHANCE:
			var hab: String = spec["habitat"]
			# srnci se ve dne drží v lese a za soumraku vycházejí na okraje a louky
			if hab == "edge" and not active:
				hab = "forest"
			var c := home if global_position.distance_to(home) > float(spec["home_range"]) * HOME_RETURN_K else global_position
			target = fauna.random_point(c, float(spec["home_range"]) * HOME_WANDER_K, hab, rng)
			state = "move"
			state_t = 0.0
		else:
			# pár kroků při pastvě
			var a := yaw + rng.randf_range(-STEP_ANGLE, STEP_ANGLE)
			target = global_position + Vector3(sin(a), 0, cos(a)) * rng.randf_range(STEP_DIST[0], STEP_DIST[1])
			state = "move"
			state_t = 0.0
	if target != Vector3.INF:
		var d := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
		if d.length() < ARRIVE_R:
			target = Vector3.INF
			_enter("graze")
			want_speed = 0.0
			return
		want_dir = d.normalized()
		# přesun krokem, na delší vzdálenost o něco rychleji (ne klusem)
		want_speed = float(spec["gaits"]["walk"]) if d.length() < LONG_MOVE_D else float(spec["gaits"]["walk"]) * LONG_MOVE_K


## Kdo je hrozba a jak moc si jí zvíře všimlo (zrak, sluch, čich po větru).
func _perceive(dt: float) -> void:
	var p: Node3D = fauna.world.nearest_player(global_position)
	threat = null
	threat_d = INF
	if p == null:
		aware = move_toward(aware, 0.0, dt * AWARE_DECAY_NONE)
		return
	var tpos := p.global_position
	var d := tpos.distance_to(global_position)
	var day: float = fauna.clock.daylight()
	var w: Weather = fauna.weather
	var sight: float = spec["sight"] * lerpf(NIGHT_SIGHT, 1.0, day)
	if w:
		sight *= lerpf(1.0, FOG_SIGHT, w.fog)      # v husté mlze zvěř vidí zhruba na třetinu
	var cover: float = fauna.forest_at(tpos.x, tpos.z)
	sight *= lerpf(1.0, COVER_SIGHT, cover)
	# M2.9: hráč na posedu (výš než STAND_HEIGHT_M nad terénem) je zvěři hůř vidět a cítit
	var on_stand: bool = tpos.y - fauna.terrain.height_at(tpos.x, tpos.z) > STAND_HEIGHT_M
	if on_stand:
		sight *= STAND_SIGHT_K
	var hear := 0.0
	var car: Node3D = p.get("car")
	var horse: Node3D = p.get("horse")
	var mover: Node3D = car if car else (horse if horse else p)
	var v := 0.0
	if mover is RigidBody3D:
		v = (mover as RigidBody3D).linear_velocity.length()
	elif mover is CharacterBody3D:
		v = Vector3((mover as CharacterBody3D).velocity.x, 0, (mover as CharacterBody3D).velocity.z).length()
	if car:
		hear = float(spec["hearing"]) * (CAR_HEAR_BASE + minf(v / CAR_HEAR_V, CAR_HEAR_MAX))
		sight *= CAR_SIGHT
	elif horse:
		hear = float(spec["hearing"]) * clampf(v / HORSE_HEAR_V, HORSE_HEAR_MIN, HORSE_HEAR_MAX)
		sight *= HORSE_SIGHT                  # koně se zvěř tolik nebojí
	else:
		var vis: Humanoid = p.get("visual")
		if vis and vis.crouching:
			sight *= CROUCH_SIGHT
		hear = float(spec["hearing"]) * clampf((v - STEP_HEAR_FROM) / STEP_HEAR_RANGE, 0.0, STEP_HEAR_MAX)
	# čich: vítr vane od člověka ke zvířeti → cítí ho dál
	var smell := 0.0
	if w and w.wind > SMELL_WIND_MIN:
		var wv := w.wind_vector().normalized()
		if fauna.world != null and fauna.world.wind_field != null:
			var wl := fauna.world.wind_field.wind_at(global_position, 1.5)   # M8.4: vítr u zvířete (údolí, les)
			wv = Vector3(wl.x, 0.0, wl.z).normalized()
		var to_me := (global_position - tpos)
		to_me.y = 0.0
		if to_me.length() > 0.1 and wv.dot(to_me.normalized()) > SMELL_CONE:
			smell = float(spec["sight"]) * SMELL_K * (STAND_SIGHT_K if on_stand else 1.0)
	var detect := maxf(maxf(sight, hear), smell)
	if d < detect:
		var inc := dt * (AWARE_BASE + AWARE_NEAR * (1.0 - d / detect))
		var cap := 1.0
		# návyk: nehybný člověk dál než flight zvíře tolik nevzrušuje
		if v < STILL_V and d > float(spec["flight"]):
			inc *= 1.0 - float(spec["calm"]) * CALM_K
			cap = HABIT_CAP
		if aware < cap:
			aware = minf(aware + inc, cap)
	else:
		aware = move_toward(aware, 0.0, dt * AWARE_DECAY)
	threat = mover
	threat_d = d


func _flight_distance() -> float:
	var f: float = spec["flight"]
	if threat is Car:
		# auto na silnici: zvěř je zvyklá, uteče až zblízka nebo když jede rychle
		return f * clampf((threat as Car).linear_velocity.length() / CAR_FLIGHT_V, CAR_FLIGHT_MIN, CAR_FLIGHT_MAX)
	if threat and threat.has_method("is_horse"):
		return f * HORSE_FLIGHT
	return f


## Směr útěku: pryč od hrozby, ale radši do lesa a ne do vesnice ani na prudký svah.
func _flee_dir(away: Vector3) -> Vector3:
	var best := away
	var bs := -INF
	for k in 7:
		var a := (k - 3) * FLEE_FAN
		var dir := Basis(Vector3.UP, a) * away
		var p := global_position + dir * FLEE_PROBE
		var s := dir.dot(away) * FLEE_AWAY_W + fauna.score("forest", p.x, p.z) * FLEE_FOREST_W
		if not fauna.terrain.contains(p.x, p.z, 60.0):
			s -= FLEE_EDGE_PEN
		var dh: float = fauna.terrain.height_at(p.x, p.z) - global_position.y
		if absf(dh) / FLEE_PROBE > tan(deg_to_rad(float(spec["max_slope"]))):
			s -= FLEE_SLOPE_PEN
		if s > bs:
			bs = s
			best = dir
	return best.normalized()


func _enter(s: String) -> void:
	if s == state:
		return
	state = s
	state_t = 0.0
	_calm_t = 0.0
	match s:
		"flee":
			target = Vector3.INF
			_play("alarm")
		"charge":
			_play("attack")
		"graze", "rest":
			target = Vector3.INF
			want_speed = 0.0


## Bachyně narazila do člověka: odhodí ho a zraní (kly), pak uteče.
func _attack() -> void:
	var p: Player = fauna.world.nearest_player(global_position)
	if p and p.car == null:
		var dir: Vector3 = p.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized()
		p.knock(dir * ATTACK_PUSH + Vector3.UP * ATTACK_LIFT, ATTACK_KNOCK_S)
		p.body.hurt(ATTACK_DMG, "útok divočáka")
		fauna.world.emit_game_event(p.id, "animal_attack", {"species": species})
	_charged = true
	_enter("flee")


# ------------------------------------------------------------------ pohyb

## Natočení a rychlost s fyzikálními omezeními (zrychlení, dostředivé zrychlení, svah, překážky).
func _steer(delta: float) -> void:
	if state in ["graze", "rest", "alert", "freeze"] and want_speed <= 0.0:
		want_dir = Vector3(sin(yaw), 0, cos(yaw))
	_avoid_t -= delta
	if _avoid_t <= 0.0:
		_avoid = move_toward(_avoid, 0.0, delta * AVOID_DECAY)
	var dir := Basis(Vector3.UP, _avoid) * want_dir
	var want_yaw := atan2(dir.x, dir.z)
	var diff := wrapf(want_yaw - yaw, -PI, PI)
	var turn_max := minf(float(spec["turn"]), float(spec["lat_acc"]) / maxf(absf(speed), 0.3))
	if state == "alert" and threat:
		var to := threat.global_position - global_position
		diff = 0.0
		rig.look_yaw = wrapf(atan2(to.x, to.z) - yaw, -PI, PI)
	elif state == "graze" and threat and aware > 0.3 and threat_d < float(spec["flight"]) * LOOK_BACK_R:
		# při pastvě se občas ohlédne k člověku
		var to2 := threat.global_position - global_position
		rig.look_yaw = move_toward(rig.look_yaw, wrapf(atan2(to2.x, to2.z) - yaw, -PI, PI), delta * LOOK_RATE)
	else:
		rig.look_yaw = move_toward(rig.look_yaw, 0.0, delta)
	var dyaw := clampf(diff, -turn_max * delta, turn_max * delta)
	yaw = wrapf(yaw + dyaw, -PI, PI)
	_yaw_rate = dyaw / maxf(delta, 0.001)
	# rychlost: při ostrém úhlu zpomalit, do kopce taky
	var ws := want_speed * clampf(cos(diff), TURN_SLOW_MIN, 1.0)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var L: float = spec["length"]
	var h0: float = fauna.terrain.height_at(global_position.x, global_position.z)
	var h1: float = fauna.terrain.height_at(global_position.x + fwd.x * L, global_position.z + fwd.z * L)
	_slope = atan2(h1 - h0, L)
	var max_s := deg_to_rad(float(spec["max_slope"]))
	if _slope > max_s * SLOPE_SLOW_FROM:
		ws *= clampf(1.0 - (_slope - max_s * SLOPE_SLOW_FROM) / (max_s * (1.0 - SLOPE_SLOW_FROM)), 0.0, 1.0)
		if _slope > max_s and ws <= 0.0 and want_speed > 0.0:
			_avoid = PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
			_avoid_t = SLOPE_AVOID_S
	var acc: float = spec["accel"] if ws > speed else spec["brake"]
	speed = move_toward(speed, ws, acc * delta)


func _physics_move(delta: float) -> void:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	# překážky: paprsky dopředu ve výšce hrudi
	_probe_t -= delta
	if _probe_t <= 0.0 and speed > PROBE_MIN_V:
		_probe_t = PROBE_S
		_probe(fwd)
	var vy := velocity.y
	if is_on_floor():
		vy = -0.5
	else:
		vy -= GRAVITY * delta
	# odrazové skoky při útěku (srnec vyskakuje i bez překážky)
	_pronk_t -= delta
	var pronk := float(spec.get("pronk", 0.0))
	# M8.10: ve vysoké trávě / obilí skáče srnec výš, častěji a už od klusu (bounding přes porost)
	var tall := pronk > 0.0 and state == "flee" and QuadrupedRig.v2 and _tall_veg(delta)
	var min_v := float(spec["gaits"]["canter"]) * (PRONK_TALL_V if tall else PRONK_V)
	if pronk > 0.0 and state == "flee" and speed > min_v and is_on_floor() and _pronk_t <= 0.0:
		var ph := pronk * PRONK_H_K + PRONK_H_ADD
		if tall:
			ph *= float(spec.get("pronk_tall", 1.3))
		vy = sqrt(2.0 * GRAVITY * ph)
		_pronk_t = rng.randf_range(PRONK_TALL_EVERY[0], PRONK_TALL_EVERY[1]) if tall else rng.randf_range(PRONK_EVERY[0], PRONK_EVERY[1])
	velocity = fwd * speed + Vector3(0, vy, 0)
	move_and_slide()
	var ground: float = fauna.terrain.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 1.5:
		global_position.y = ground + 0.1
		velocity.y = 0.0
	# zaseknutí (narazil a nehne se) → jiný směr
	var moved := Vector3(global_position.x - _last_pos.x, 0, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	if speed > STUCK_V and moved < speed * delta * STUCK_FRAC:
		_stuck_t += delta
		if _stuck_t > STUCK_S:
			_stuck_t = 0.0
			_avoid = rng.randf_range(STUCK_TURN[0], STUCK_TURN[1]) * (1.0 if rng.randf() < 0.5 else -1.0)
			_avoid_t = STUCK_HOLD
			speed *= STUCK_SLOW
			if state == "move":
				target = Vector3.INF
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)


func _probe(fwd: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var g_y: float = float(spec["withers"]) * PROBE_H
	var from := global_position + Vector3(0, g_y, 0) + fwd * float(spec["length"]) * 0.5
	var reach := clampf(speed * PROBE_REACH_K, PROBE_REACH_MIN, PROBE_REACH_MAX)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * reach, 1 | 8 | 16)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	# přeskočit? (nízká překážka, dost rychlosti, na zemi)
	var jump: float = spec["jump"]
	if jump > 0.0 and speed > JUMP_MIN_V and is_on_floor():
		var top := global_position + Vector3(0, jump + JUMP_CLEAR, 0)
		var q2 := PhysicsRayQueryParameters3D.create(top, top + fwd * (reach + 1.0), 1 | 8 | 16)
		q2.exclude = [get_rid()]
		if space.intersect_ray(q2).is_empty():
			velocity.y = sqrt(2.0 * GRAVITY * (jump * JUMP_H_K + JUMP_H_ADD))
			return
	# obejít: stranu, kde je volněji
	var best := 0.0
	var bd := -1.0
	for a in [PROBE_SIDE_A, -PROBE_SIDE_A, PROBE_WIDE_A, -PROBE_WIDE_A]:
		var d := Basis(Vector3.UP, a) * fwd
		var q3 := PhysicsRayQueryParameters3D.create(from, from + d * reach, 1 | 8 | 16)
		q3.exclude = [get_rid()]
		var h := space.intersect_ray(q3)
		var free := reach if h.is_empty() else from.distance_to(h["position"])
		if free > bd + 0.2:
			bd = free
			best = a
	_avoid = best
	_avoid_t = PROBE_AVOID_S


func _kinematic_move(delta: float) -> void:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var p := global_position + fwd * speed * delta
	if not fauna.terrain.contains(p.x, p.z, 50.0):
		yaw = wrapf(yaw + PI, -PI, PI)
		speed = 0.0
		return
	p.y = fauna.terrain.height_at(p.x, p.z)
	global_position = p
	velocity = fwd * speed
	_last_pos = p


# ------------------------------------------------------------------ vzhled a zvuk

func _animate(delta: float) -> void:
	var k := 1.0 - exp(-delta * ANIM_BLEND)
	var beh: String = spec["behaviour"]
	_graze = lerpf(_graze, 1.0 if state == "graze" and speed < 0.3 else 0.0, k)
	_alert = lerpf(_alert, 1.0 if state in ["alert", "freeze"] or (state == "flee" and speed < ALERT_FLEE_V) else 0.0, k * 2.0)
	_lie = lerpf(_lie, 1.0 if state == "rest" and beh != "hare" else 0.0, k * LIE_BLEND_K)
	_crouch = lerpf(_crouch, 1.0 if (state == "freeze" or state == "rest" and beh == "hare") else 0.0, k * 2.0)
	# zajíc v pozornosti se postaví na zadní („panáček"), jinak sedí 0
	_sit = lerpf(_sit, 1.0 if beh == "hare" and state == "alert" and speed < 0.5 else 0.0, k * 2.5)
	rig.rotation.y = yaw
	rig.speed = speed
	rig.turn_rate = _yaw_rate
	rig.slope = _slope
	rig.graze = _graze
	rig.alert = _alert
	rig.lie = _lie
	rig.crouch = _crouch
	rig.sit = _sit
	rig.rooting = beh == "rooter"
	if _soil:
		_soil.emitting = _lod == Lod.FULL and rig.rooting and _graze > 0.5
	rig.airborne = clampf(absf(velocity.y) / AIR_V, 0.0, 1.0) if _lod == Lod.FULL and not is_on_floor() else 0.0
	# M8.10: uši ke zdroji zvuku (hrozba z vnímání, nebo výstřel / hluk), útěk (ocas, zrcátko), dráha skoku
	rig.flee = 1.0 if state == "flee" else 0.0
	rig.vy = velocity.y if _lod == Lod.FULL else 0.0
	var src := Vector3.INF
	if threat and aware > LISTEN_AWARE:
		src = threat.global_position
	elif _noise_t > 0.0:
		src = _noise_pos
	if src != Vector3.INF:
		rig.listen = 1.0
		rig.listen_yaw = wrapf(atan2(src.x - global_position.x, src.z - global_position.z) - yaw, -PI, PI)
	else:
		rig.listen = 0.0
	rig.animate(delta)


## M8.10: stojí zvíře ve vysoké trávě / obilí? (`TALL_VEG_MONTHS`, dotaz do `World.fields` jen 2× za s)
func _tall_veg(delta: float) -> bool:
	_tall_t -= delta
	if _tall_t > 0.0:
		return _tall
	_tall_t = TALL_VEG_CHECK_S
	_tall = false
	var f: Fields = fauna.world.fields if fauna.world else null
	if f == null:
		return false
	var months: Array = TALL_VEG_MONTHS.get(f.class_at(global_position.x, global_position.z), [])
	_tall = fauna.clock.month() in months
	return _tall


## Hrudebníček hlíny u rypáku divočáka při rytí (drobné částice letí dozadu).
func _soil_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.5
	p.local_coords = false
	p.explosiveness = 0.0
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1.0, -0.5)
	pm.spread = 42.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -8.0, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.018
	m.height = 0.036
	m.radial_segments = 5
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.1, 0.06)
	mat.roughness = 1.0
	m.material = mat
	p.draw_pass_1 = m
	p.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _sounds(delta: float) -> void:
	if _lod != Lod.FULL:
		return
	_snd_t -= delta
	if _snd_t <= 0.0:
		_snd_t = rng.randf_range(6.0, 18.0)
		if state in ["graze", "move"] and spec["sounds"].has("idle") and rng.randf() < 0.5:
			_play("idle")


func _play(kind: String) -> void:
	if _lod != Lod.FULL or not spec["sounds"].has(kind):
		return
	if _snd == null:
		_snd = NatureSfx.player3d(self, 90.0, 2.0)
	_snd.stream = NatureSfx.get_stream(spec["sounds"][kind])
	_snd.pitch_scale = rng.randf_range(0.9, 1.1) * (1.4 if young else 1.0)
	_snd.play()


# ------------------------------------------------------------------ srážka a úhyn

## Výstřel / hlasitý zvuk v `pos` (M2.8, `Weapons`): zvíře i celé stádo se splaší a běží pryč od zdroje hluku.
func hear_shot(pos: Vector3, panic_s := 20.0) -> void:
	if dead:
		return
	_noise_pos = pos
	_noise_t = maxf(_noise_t, panic_s)
	aware = 1.0
	if herd:
		herd.alarm(pos, panic_s)


# ------------------------------------------------------------------ postřelení (M2.9)

## Zásah střelou (volá `Hunting.animal_shot`): zóna z `Weapons.zone_of`, energie z balistiky (J), `from` = odkud se střílelo,
## `info` = {id, weapon, legal, …} pro `Hunting`. Vrací "dead" (padlo na místě), "wounded" (postřelené, uteče) nebo "limp".
## Hlava a komora s dost energie zvíře usmrtí (srdce: ještě uběhne 20–60 m), se slabou střelou (šíp) se to jen někdy
## povede, jinak je postřelené do břicha: uteče 200–600 m, zalehne a po 1–3 herních hodinách zhyne. Noha: kulhá, žije.
## Nenaturalisticky: jen pád a ležící zvíře, žádné detaily zranění.
func shot(zone: String, energy: float, from: Vector3, info := {}) -> String:
	if dead:
		return "dead"
	shot_by = info
	shot_by["zone"] = zone
	wound_src = from
	hear_shot(from, SHOT_PANIC_S)
	var need := 0.0
	var k := pow(float(spec["mass"]) / KILL_REF_KG, KILL_MASS_EXP)
	match zone:
		"hlava":
			need = KILL_HEAD_J * k
		"srdce_plice":
			need = KILL_HEART_J * k
	if zone == "noha":
		wound = "noha"
		limp_t = LIMP_S
		wound_left = 0.0
		_wound_last = global_position
		_enter("flee")
		return "limp"
	if need > 0.0 and (energy >= need or rng.randf() < energy / need):
		if zone == "hlava":
			die_shot()
			return "dead"
		wound = "srdce"
		wound_left = rng.randf_range(WOUND_RUN_HEART_M[0], WOUND_RUN_HEART_M[1])
	else:
		wound = "bricho"
		wound_left = rng.randf_range(WOUND_RUN_BELLY_M[0], WOUND_RUN_BELLY_M[1])
	wound_lie = false
	_wound_last = global_position
	_enter("flee")
	return "wounded"


## Zvíře padlo po zásahu: zůstane ležet (nezmizí samo) a `Hunting` z něj udělá `Carcass`.
func die_shot(natural := false) -> void:
	if dead:
		return
	shot_by["natural"] = natural       # true = zhynulo samo na následky postřelení (břicho), ne přímým zásahem
	dead = true
	wound = ""
	wound_lie = false
	state = "dead"
	velocity = Vector3.ZERO
	collision_layer = 0
	keep_corpse = true
	_dead_t = 0.0
	if fauna and fauna.world.hunting:
		fauna.world.hunting.on_animal_died(self)


## Mrtvé tělo obnovené z uložené hry (`Hunting.restore`): bez AI, jen ležící model.
func make_corpse() -> void:
	dead = true
	wound = ""
	state = "dead"
	collision_layer = 0
	keep_corpse = true
	_dead_t = 0.0


## Chování postřeleného zvířete (z `_think`). Vrací true, když převzalo řízení (srdce, břicho); noha jen zpomalí běh.
func _wound_think(dt: float) -> bool:
	var pos := global_position
	if _wound_last == Vector3.INF:
		_wound_last = pos
	var moved := pos.distance_to(_wound_last)
	if moved > 0.05 and not wound_lie and (wound != "noha" or limp_t > LIMP_S - LIMP_BLOOD_S):
		_blood_trail(_wound_last, pos)
	_wound_last = pos
	if wound == "noha":
		limp_t -= dt
		if limp_t <= 0.0:
			wound = ""
			if fauna.world.hunting:
				fauna.world.hunting.on_wound_healed(self)
			return false
		return false
	if wound_lie:
		return _wound_lying(dt)
	wound_left -= moved
	if wound_left <= 0.0:
		if wound == "srdce":
			die_shot()
			return true
		wound_lie = true
		_rise_rolled = false
		wound_die_min = fauna.clock.minutes + rng.randf_range(WOUND_LIE_MIN[0], WOUND_LIE_MIN[1])
		_enter("rest")
		want_speed = 0.0
		return true
	var away := pos - wound_src
	away.y = 0.0
	if away.length() < 0.5:
		away = Vector3(sin(yaw), 0, cos(yaw))
	if state != "flee":
		_enter("flee")
	want_dir = _flee_dir(away.normalized())
	want_speed = float(spec["gaits"]["canter"]) if wound == "srdce" else float(spec["flee_speed"]) * WOUND_FLEE_K
	return true


## Zalehlé postřelené zvíře: čeká na smrt, při přiblížení hráče se může zvednout a utéct.
func _wound_lying(_dt: float) -> bool:
	want_speed = 0.0
	if state != "rest":
		_enter("rest")
	if fauna.clock.minutes >= wound_die_min:
		die_shot(true)
		return true
	var p: Player = fauna.world.nearest_player(global_position)
	if p != null:
		var d := fauna.world.player_world_pos(p).distance_to(global_position)
		if d < WOUND_RISE_M and not _rise_rolled:
			_rise_rolled = true
			if _wound_rises < WOUND_RISES_MAX and rng.randf() < WOUND_RISE_P:
				_wound_rises += 1
				wound_lie = false
				wound_left = rng.randf_range(WOUND_RISE_RUN_M[0], WOUND_RISE_RUN_M[1])
				wound_src = fauna.world.player_world_pos(p)
				_enter("flee")
		elif d > WOUND_RISE_M * 2.0:
			_rise_rolled = false
	return true


## Krvavé kapky po trase útěku (mezi dvěma kroky, i když se zvíře ve vzdáleném LOD posunulo o desítky metrů).
func _blood_trail(a: Vector3, b: Vector3) -> void:
	var hunting: Hunting = fauna.world.hunting
	if hunting == null:
		return
	var seg := b - a
	var len_ := seg.length()
	if len_ < 0.01:
		return
	_blood_acc += len_
	while _blood_acc >= BLOOD_STEP_M:
		_blood_acc -= BLOOD_STEP_M
		var t := 1.0 - _blood_acc / len_
		hunting.add_blood(a + seg * clampf(t, 0.0, 1.0))


## Srážka s autem (volá Car): rychlá srážka zvíře usmrtí, pomalá ho odhodí a vyplaší.
func knock(vel: Vector3, spd: float) -> void:
	if dead:
		return
	if spd > KNOCK_KILL_V or float(spec["mass"]) < KNOCK_SMALL_KG and spd > KNOCK_SMALL_V:
		dead = true
		state = "dead"
		velocity = vel * clampf(KNOCK_MASS_REF / float(spec["mass"]), KNOCK_MIN, KNOCK_MAX)
		collision_layer = 0
		_dead_t = 0.0
		if herd:
			herd.alarm(global_position, KNOCK_ALARM_S)
	else:
		velocity = vel
		_enter("flee")
		if herd:
			herd.alarm(global_position - vel.normalized() * 5.0, KNOCK_SCARE_S)


func _dead_update(delta: float) -> void:
	_dead_t += delta
	if _lod == Lod.FULL:
		velocity.x = move_toward(velocity.x, 0.0, DEAD_FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, DEAD_FRICTION * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
	rig.dead = move_toward(rig.dead, 1.0, delta * DEAD_BLEND)
	rig.speed = 0.0
	rig.animate(delta)
	# mrtvé zvíře po čase zmizí (sebere ho myslivec) – až když ho nikdo nevidí
	if _dead_t > CORPSE_S and _lod == Lod.FAR and not keep_corpse:
		queue_free()


## Dopad nohy → stopa ve sněhu (jen zvěř v plném detailu; správce stop `World.tracks`).
func _on_footfall(leg: int) -> void:
	if _lod != Lod.FULL or dead:
		return
	var tr: Tracks = fauna.world.tracks
	if tr == null or fauna.weather == null or fauna.weather.snow_cover < Tracks.SNOW_MIN:
		return
	var kind := "deer"
	if species == "divocak" or species == "sele":
		kind = "boar"
	elif species == "zajic":
		if leg != 3:
			return                     # zajíc: jedno „Y“ na skok
		kind = "hare"
	var half := float(spec["length"]) * 0.42
	var side := float(spec["chest"][0]) * 0.6
	var lp := Vector3(side if leg % 2 == 0 else -side, 0.0, half if leg < 2 else -half)
	if kind == "hare":
		lp = Vector3.ZERO
	tr.add(kind, global_position + Basis(Vector3.UP, yaw) * lp, yaw)
