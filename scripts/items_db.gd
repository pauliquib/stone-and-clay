## Jednotný katalog předmětů (M0.2): jídlo, pití, cigarety, vybavení, sběratelské předměty i předměty pro
## další kroky roadmapy (nástroje, materiál, semena, zbraně, střelivo…). Jen statická data a pomocné funkce.
##
## Povinné klíče: name, type (viz TYPES). Volitelné: short (krátký název), price (Kč), kg (hmotnost 1 ks),
## stack (max. v jednom slotu; 1 = nestackuje), durability (použití do zničení; nástroje),
## perishable_h (zkazí se za herní hodiny), skill_req ({"drevorubectvi": 5}), points (skóre sběru),
## cook_to / burnt_to (M2.2: výsledek opékání na ohni / spálené), color (barva ikony / modelu), hold (false = nástroj se nedává do ruky, např. špalek), world_object (předmět ve světě, ne v kapse) a klíče z původních Consumables
## (ml, sip, abv, kcal, count, bottle, caffeine…).
## Oblečení (M2.3, type `clothing`): slot (hlava, trup, bunda, nohy, boty, ruce), insul (tepelná izolace 0..1), waterproof (0..1),
## color, style (klíč pro `Humanoid.apply_outfit`), tags (ochrana_pila, reflexni, pracovni, slavnostni, hasic, plavky, vcelar).
## `Consumables.ITEMS` a `Item.INFO` jsou aliasy na `ITEMS`.
class_name ItemsDB
extends RefCounted

const TYPES := ["drink", "food", "smoke", "gear", "tool", "weapon", "ammo", "material", "seed",
	"clothing", "animal_product", "meat", "fish", "document", "collectible", "misc"]

## Nadpisy skupin v inventáři (Tab): pořadí a text podle typu.
const TYPE_LABELS := {
	"drink": "Jídlo a pití", "food": "Jídlo a pití", "meat": "Jídlo a pití", "fish": "Jídlo a pití",
	"animal_product": "Jídlo a pití", "smoke": "Tabák", "gear": "Vybavení", "tool": "Nástroje",
	"weapon": "Zbraně", "ammo": "Střelivo", "material": "Materiál", "seed": "Semena a sazenice",
	"clothing": "Oblečení", "document": "Doklady", "collectible": "Sběratelské předměty", "misc": "Ostatní",
}
const GROUP_ORDER := ["Jídlo a pití", "Tabák", "Vybavení", "Nástroje", "Zbraně", "Střelivo", "Materiál",
	"Semena a sazenice", "Oblečení", "Doklady", "Sběratelské předměty", "Ostatní"]

const ITEMS := {
	# ------------------------------------------------------------ alkohol
	"pivo": {"name": "Pivo 12° (lahev 0,5 l)", "short": "Pivo", "type": "drink", "kg": 0.8, "ml": 500, "sip": 500,
		"abv": 5.0, "kcal": 215, "price": 32, "bottle": "beer", "color": Color(0.36, 0.2, 0.06)},
	"pivo_cepovane": {"name": "Točené pivo 12° (0,5 l)", "short": "Točené", "type": "drink", "kg": 0.7, "ml": 500, "sip": 500,
		"abv": 5.0, "kcal": 215, "price": 49, "bottle": "mug", "color": Color(0.9, 0.62, 0.12)},
	"pivo10": {"name": "Výčepní pivo 10° (0,5 l)", "short": "Desítka", "type": "drink", "kg": 0.7, "ml": 500, "sip": 500,
		"abv": 4.0, "kcal": 180, "price": 39, "bottle": "mug", "color": Color(0.95, 0.72, 0.2)},
	"nealko": {"name": "Nealkoholické pivo (0,5 l)", "short": "Nealko", "type": "drink", "kg": 0.8, "ml": 500, "sip": 500,
		"abv": 0.0, "kcal": 110, "price": 35, "bottle": "beer", "color": Color(0.2, 0.45, 0.12)},
	"vino_bile": {"name": "Víno bílé – Ryzlink (0,75 l)", "short": "Bílé víno", "type": "drink", "kg": 1.2, "ml": 750, "sip": 200,
		"abv": 12.0, "kcal": 620, "price": 160, "bottle": "wine", "color": Color(0.25, 0.4, 0.15)},
	"vino_cervene": {"name": "Víno červené – Frankovka (0,75 l)", "short": "Červené víno", "type": "drink", "kg": 1.2, "ml": 750,
		"sip": 200, "abv": 13.0, "kcal": 640, "price": 175, "bottle": "wine", "color": Color(0.18, 0.08, 0.1)},
	"vino_sklenka": {"name": "Sklenka vína (0,2 l)", "short": "Sklenka vína", "type": "drink", "kg": 0.3, "ml": 200, "sip": 200,
		"abv": 12.0, "kcal": 165, "price": 45, "bottle": "glass", "color": Color(0.95, 0.88, 0.5)},
	"degustace": {"name": "Degustační vzorek vína (0,1 l)", "short": "Vzorek vína", "type": "drink", "kg": 0.15, "ml": 100, "sip": 100,
		"abv": 13.0, "kcal": 85, "price": 0, "bottle": "glass", "color": Color(0.6, 0.1, 0.15)},
	"slivovice": {"name": "Slivovice 50 % (0,7 l)", "short": "Slivovice", "type": "drink", "kg": 1.1, "ml": 700, "sip": 50,
		"abv": 50.0, "kcal": 1700, "price": 450, "bottle": "sliv", "color": Color(0.92, 0.95, 0.97)},
	"panak_slivovice": {"name": "Panák slivovice (0,05 l)", "short": "Panák slivovice", "type": "drink", "kg": 0.1, "ml": 50, "sip": 50,
		"abv": 50.0, "kcal": 120, "price": 55, "bottle": "shot", "color": Color(0.95, 0.97, 1.0)},
	"vodka": {"name": "Vodka 40 % (0,5 l)", "short": "Vodka", "type": "drink", "kg": 0.9, "ml": 500, "sip": 50,
		"abv": 40.0, "kcal": 1100, "price": 229, "bottle": "vodka", "color": Color(0.9, 0.93, 0.98)},
	"panak_vodky": {"name": "Panák vodky (0,05 l)", "short": "Panák vodky", "type": "drink", "kg": 0.1, "ml": 50, "sip": 50,
		"abv": 40.0, "kcal": 110, "price": 45, "bottle": "shot", "color": Color(0.95, 0.97, 1.0)},
	"rum": {"name": "Tuzemský rum 37,5 % (0,5 l)", "short": "Rum", "type": "drink", "kg": 0.9, "ml": 500, "sip": 50,
		"abv": 37.5, "kcal": 1050, "price": 189, "bottle": "rum", "color": Color(0.45, 0.2, 0.05)},
	"becherovka": {"name": "Bylinkovka 38 % (0,5 l)", "short": "Bylinkovka", "type": "drink", "kg": 0.9, "ml": 500, "sip": 50,
		"abv": 38.0, "kcal": 1350, "price": 259, "bottle": "becher", "color": Color(0.2, 0.4, 0.2)},
	"fernet": {"name": "Panák Hořké (0,05 l)", "short": "Hořká", "type": "drink", "kg": 0.1, "ml": 50, "sip": 50,
		"abv": 38.0, "kcal": 130, "price": 50, "bottle": "shot", "color": Color(0.15, 0.1, 0.06)},
	# ------------------------------------------------------------ nealko
	"kava": {"name": "Káva (turek)", "short": "Káva", "type": "drink", "kg": 0.25, "ml": 150, "sip": 150,
		"abv": 0.0, "kcal": 5, "price": 35, "bottle": "cup", "color": Color(0.2, 0.12, 0.06), "caffeine": 1.0},
	"voda": {"name": "Minerálka (0,5 l)", "short": "Voda", "type": "drink", "kg": 0.6, "ml": 500, "sip": 500,
		"abv": 0.0, "kcal": 0, "price": 19, "bottle": "water", "color": Color(0.6, 0.8, 0.95)},
	# ------------------------------------------------------------ jídlo
	"rohlik": {"name": "Rohlíky (2 ks)", "short": "Rohlíky", "type": "food", "kg": 0.1, "kcal": 280, "price": 8,
		"color": Color(0.85, 0.62, 0.3)},
	"parek": {"name": "Párek v rohlíku", "short": "Párek v rohlíku", "type": "food", "kg": 0.15, "kcal": 380, "price": 39,
		"color": Color(0.8, 0.45, 0.3), "cook_to": "parek_opeceny"},
	"chleba_sadlo": {"name": "Chleba se sádlem a cibulí", "short": "Chleba se sádlem", "type": "food", "kg": 0.25, "kcal": 420,
		"price": 45, "color": Color(0.9, 0.85, 0.7), "cook_to": "topinka"},
	# ---- M2.2 opékání na ohni: klíč `cook_to` (výsledek), volitelně `burnt_to` (spálené; výchozí `spalene_jidlo`)
	"burt": {"name": "Buřt (syrový)", "short": "Buřt", "type": "food", "kg": 0.15, "kcal": 260, "price": 25,
		"color": Color(0.75, 0.32, 0.25), "cook_to": "burt_opeceny"},
	"burt_opeceny": {"name": "Opečený buřt", "short": "Opečený buřt", "type": "food", "kg": 0.14, "kcal": 340, "price": 0,
		"color": Color(0.55, 0.28, 0.15)},
	"parek_opeceny": {"name": "Opečený párek v rohlíku", "short": "Opečený párek", "type": "food", "kg": 0.14, "kcal": 400,
		"price": 0, "color": Color(0.65, 0.35, 0.2)},
	"topinka": {"name": "Opečená topinka se sádlem", "short": "Topinka", "type": "food", "kg": 0.22, "kcal": 480, "price": 0,
		"color": Color(0.7, 0.5, 0.25)},
	"spalene_jidlo": {"name": "Spálené jídlo", "short": "Spálené jídlo", "type": "food", "kg": 0.1, "kcal": 60, "price": 0,
		"color": Color(0.1, 0.08, 0.06)},
	"utopenec": {"name": "Utopenec", "short": "Utopenec", "type": "food", "kg": 0.2, "kcal": 320, "price": 59,
		"color": Color(0.7, 0.4, 0.35)},
	"tlacenka": {"name": "Tlačenka s cibulí", "short": "Tlačenka", "type": "food", "kg": 0.25, "kcal": 450, "price": 65,
		"color": Color(0.75, 0.5, 0.45)},
	"gulas": {"name": "Guláš, 6 knedlíků", "short": "Guláš", "type": "food", "kg": 0.5, "kcal": 980, "price": 169,
		"color": Color(0.5, 0.2, 0.1)},
	"smazak": {"name": "Smažený sýr, hranolky, tatarka", "short": "Smažák", "type": "food", "kg": 0.5, "kcal": 1250,
		"price": 189, "color": Color(0.95, 0.75, 0.3)},
	"chipsy": {"name": "Brambůrky (150 g)", "short": "Brambůrky", "type": "food", "kg": 0.15, "kcal": 800, "price": 45,
		"color": Color(0.95, 0.8, 0.2)},
	"jablko": {"points": 5, "name": "Jablko", "short": "Jablko", "type": "food", "kg": 0.15, "kcal": 80, "price": 6,
		"color": Color(0.8, 0.12, 0.08)},
	"sipek": {"points": 5, "name": "Šípky (sušené)", "short": "Šípky", "type": "food", "kg": 0.05, "kcal": 40, "price": 0,
		"color": Color(0.8, 0.12, 0.1)},
	"med": {"name": "Sklenice lipového medu", "short": "Med", "type": "food", "kg": 0.5, "kcal": 320, "price": 0,
		"color": Color(0.85, 0.55, 0.1)},
	"hrib": {"points": 10, "name": "Hřib (syrový)", "short": "Hřib", "type": "food", "kg": 0.1, "kcal": 30, "price": 0,
		"color": Color(0.5, 0.3, 0.12)},
	# ------------------------------------------------------------ tabák
	"cigarety": {"name": "Cigarety (krabička 20 ks)", "short": "Cigarety", "type": "smoke", "kg": 0.03, "count": 20, "price": 165,
		"color": Color(0.9, 0.9, 0.88)},
	# ---- M4.8 obsah pro dospělé (`adult: true`): vidí se jen při zapnuté volbě (`ItemsDB.adult_on`), jinak nejsou ve hře.
	# Oficiální text: zjednodušená herní simulace, nejde o návod. Úroveň THC / psilocybinu v `BodyState`.
	"tabak_semena": {"name": "Semena tabáku (sáček)", "short": "Semena tabáku", "type": "seed", "kg": 0.01, "stack": 99,
		"price": 45, "adult": true, "color": Color(0.7, 0.75, 0.5)},
	"tabak_susene": {"name": "Ruční cigareta z papírku (tabák)", "short": "Cigareta", "type": "smoke", "kg": 0.05,
		"count": 1, "stack": 99, "price": 0, "adult": true, "color": Color(0.5, 0.36, 0.18)},
	"papirky": {"name": "Papírky na cigarety (balení 60 ks)", "short": "Papírky", "type": "material", "kg": 0.02,
		"stack": 99, "price": 25, "adult": true, "color": Color(0.95, 0.93, 0.85)},
	"konopi_semena": {"name": "Semena konopí (průmyslová odrůda, nízké THC)", "short": "Semena konopí", "type": "seed",
		"kg": 0.01, "stack": 99, "price": 60, "adult": true, "color": Color(0.55, 0.6, 0.35)},
	"konopi_kvety": {"name": "Joint z konopí (1 dávka)", "short": "Joint", "type": "smoke", "kg": 0.05, "count": 1,
		"stack": 99, "price": 0, "adult": true, "thc": 1.0, "color": Color(0.42, 0.52, 0.22)},
	# M4.8 sušák: čerstvá sklizeň schne ~2 týdny (Garden → Vyhlasky.add_batch), pak je z ní suchý materiál (na ubalení / pečení)
	"tabak_list": {"name": "Sušený tabák (na ubalení)", "short": "Sušený tabák", "type": "material", "kg": 0.05,
		"stack": 99, "price": 0, "adult": true, "color": Color(0.5, 0.36, 0.18)},
	"konopi_susene": {"name": "Sušené květy konopí (na ubalení a pečení)", "short": "Suché konopí", "type": "material", "kg": 0.05,
		"stack": 99, "price": 0, "adult": true, "color": Color(0.42, 0.52, 0.22)},
	"tabak_cerstvy": {"name": "Čerstvé listy tabáku (sušák)", "short": "Čerstvý tabák", "type": "material", "kg": 0.1,
		"stack": 99, "price": 0, "adult": true, "color": Color(0.4, 0.55, 0.25)},
	"konopi_cerstve": {"name": "Čerstvé květy konopí (sušák)", "short": "Čerstvé konopí", "type": "material", "kg": 0.1,
		"stack": 99, "price": 0, "adult": true, "color": Color(0.35, 0.5, 0.2)},
	"lysohlavky": {"points": 8, "name": "Lysohlávky (čerstvé)", "short": "Lysohlávky", "type": "food",
		"kg": 0.05, "kcal": 20, "price": 0, "adult": true, "psilo": 1.0, "color": Color(0.8, 0.75, 0.6)},
	# záměna při sběru (`World._houba_druh`): muchomůrka = otrava (`toxic`, `BodyState.eat`)
	"muchomurka": {"name": "Muchomůrka (záměna za lysohlávku)", "short": "Muchomůrka", "type": "food",
		"kg": 0.05, "kcal": 20, "price": 0, "adult": true, "toxic": 1.0, "color": Color(0.8, 0.15, 0.1)},
	# jedlá varianta: rohlík + sušené konopí; THC nastoupí se zpožděním (`thc_eat`, `BodyState.eat`)
	"konopne_pecivo": {"name": "Konopné pečivo (rohlík s THC)", "short": "Konopné pečivo", "type": "food",
		"kg": 0.1, "kcal": 300, "price": 0, "adult": true, "thc_eat": 0.8, "color": Color(0.7, 0.55, 0.3)},
	# ------------------------------------------------------------ vybavení
	"spacak": {"name": "Spacák a karimatka (vyspíš se kdekoli venku)", "short": "Spacák", "type": "gear", "kg": 1.5, "price": 890,
		"color": Color(0.8, 0.3, 0.1)},
	# ---- M6.1 drony (stavy baterie a poškození drží `World.drone_states`, modely `DroneModel.MODELS`;
	# start z inventáře → `World.drone_launch`; opravy a nabíjení na počítači doma, stránka Letectví – ÚVL)
	"dron": {"name": "Dron Ptáček Mini (249 g, kamera, ~12 min letu)", "short": "Dron Mini", "type": "gear", "kg": 0.45,
		"price": 7990, "color": Color(0.82, 0.83, 0.88)},
	"dron_velky": {"name": "Dron Ptáček Pro XL (2,5 kg, 4K kamera, ~15 min letu, vyžaduje A1/A3)", "short": "Dron XL",
		"type": "gear", "kg": 2.9, "price": 32900, "color": Color(0.2, 0.22, 0.27)},
	"dron_baterie": {"name": "Náhradní baterie dronu (při startu se sama vymění za vybitou)", "short": "Baterie dronu",
		"type": "gear", "kg": 0.3, "price": 1490, "color": Color(0.35, 0.55, 0.75)},
	# ---- M6.4 paramotor (sbalený stroj v batohu, 25 kg = hranice nosnosti; start přes detail →
	# „Připravit k letu" → `World.pg_prepare`; registrace / škola / pojištění na PC → Letectví – ÚVL)
	"paramotor": {"name": "Paramotor Vlaštovka 24 (nový: křídlo 24 m² + motor s vrtulí)", "short": "Paramotor",
		"type": "gear", "kg": 25.0, "price": 180000, "color": Color(0.85, 0.3, 0.2)},
	"paramotor_ojety": {"name": "Paramotor Sokolík (ojetý, po prohlídce)", "short": "Paramotor (ojetý)",
		"type": "gear", "kg": 25.0, "price": 90000, "color": Color(0.5, 0.5, 0.55)},
	# ------------------------------------------------------------ sběratelské předměty (jen skóre sběru)
	"dukat": {"name": "Dukát", "short": "Dukát", "type": "collectible", "kg": 0.0, "price": 0, "points": 20, "color": Color(1.0, 0.78, 0.2)},
	"zalud": {"name": "Zlatý žalud", "short": "Zlatý žalud", "type": "collectible", "kg": 0.0, "price": 0, "points": 100, "color": Color(1.0, 0.8, 0.25)},
	# ------------------------------------------------------------ nové položky pro další kroky (zatím jen data, bez logiky)
	"sekera_stara": {"name": "Stará sekera", "short": "Stará sekera", "type": "tool", "kg": 1.8, "price": 390, "durability": 60, "color": Color(0.5, 0.45, 0.4)},
	"sekera": {"name": "Sekera", "short": "Sekera", "type": "tool", "kg": 1.6, "price": 1290, "durability": 200, "color": Color(0.55, 0.5, 0.45)},
	"motorova_pila": {"name": "Motorová pila", "short": "Motorovka", "type": "tool", "kg": 5.5, "price": 6900, "durability": 500, "color": Color(0.9, 0.5, 0.1)},
	"sirky": {"name": "Krabička sirek", "short": "Sirky", "type": "tool", "kg": 0.03, "price": 12, "durability": 40, "color": Color(0.8, 0.7, 0.4)},
	"zapalovac": {"name": "Zapalovač", "short": "Zapalovač", "type": "tool", "kg": 0.05, "price": 39, "durability": 300, "color": Color(0.3, 0.5, 0.8)},
	"trava": {"name": "Tráva (svazek)", "short": "Tráva", "type": "material", "kg": 0.1, "price": 0, "stack": 50, "color": Color(0.35, 0.6, 0.2)},
	"polena": {"name": "Polena", "short": "Polena", "type": "material", "kg": 1.5, "price": 30, "stack": 50, "color": Color(0.55, 0.38, 0.2)},
	"vetve": {"name": "Větve (klestí)", "short": "Větve", "type": "material", "kg": 0.8, "price": 0, "stack": 50, "color": Color(0.4, 0.3, 0.18)},
	"vetve_cerstve": {"name": "Čerstvé větve (klestí)", "short": "Čerstvé větve", "type": "material", "kg": 0.8, "price": 0, "stack": 50, "color": Color(0.45, 0.4, 0.22)},
	"klesti": {"name": "Kleště", "short": "Kleště", "type": "tool", "kg": 0.5, "price": 180, "durability": 300, "color": Color(0.5, 0.5, 0.55)},
	"spalek": {"name": "Špalek na štípání", "short": "Špalek", "type": "tool", "hold": false, "kg": 12.0, "price": 0, "color": Color(0.5, 0.35, 0.2)},
	"lopata": {"name": "Lopata", "short": "Lopata", "type": "tool", "kg": 2.0, "price": 320, "durability": 250, "color": Color(0.5, 0.5, 0.5)},
	"motyka": {"name": "Motyka", "short": "Motyka", "type": "tool", "kg": 1.5, "price": 280, "durability": 250, "color": Color(0.5, 0.45, 0.4)},
	"konev": {"name": "Konev", "short": "Konev", "type": "tool", "kg": 0.8, "price": 150, "durability": 400, "color": Color(0.3, 0.55, 0.7)},
	"konev_plna": {"name": "Konev (plná vody)", "short": "Konev (plná)", "type": "tool", "kg": 4.0, "price": 0, "durability": 400, "color": Color(0.3, 0.55, 0.7)},
	# ---- Fáze 8 Zahrádky (`Garden`, §11): hnůj z kompostu u zahrady – nosí se v kbelíku, akce `hnojit` na záhonu
	"hnuj": {"name": "Hnůj (kbelík)", "short": "Hnůj", "type": "tool", "kg": 2.0, "price": 15, "stack": 10, "color": Color(0.28, 0.18, 0.1)},
	# ---- M3.2 nářadí prací (zapůjčí ho zaměstnavatel na směnu – `Jobs` `zapujcit`; v obchodě zatím není, DOPLNIT: stavebniny M5.1)
	"vidle": {"name": "Vidle", "short": "Vidle", "type": "tool", "kg": 1.6, "price": 290, "durability": 300, "color": Color(0.55, 0.55, 0.58)},
	"kosa": {"name": "Kosa", "short": "Kosa", "type": "tool", "kg": 1.8, "price": 590, "durability": 300, "color": Color(0.6, 0.62, 0.66)},
	"hrabe": {"name": "Hrábě", "short": "Hrábě", "type": "tool", "kg": 1.0, "price": 190, "durability": 300, "color": Color(0.55, 0.4, 0.22)},
	"kladivo": {"name": "Kladivo a hřebíky", "short": "Kladivo", "type": "tool", "kg": 0.8, "price": 250, "durability": 300, "color": Color(0.4, 0.4, 0.42)},
	"pisek": {"name": "Posypový písek (kbelík)", "short": "Písek", "type": "material", "kg": 3.0, "price": 10, "stack": 20, "color": Color(0.78, 0.68, 0.48)},
	# ---- M3.3 zahradník u sousedů (zapůjčí je zákazník / děda na zakázku; DOPLNIT: prodej ve stavebninách M5.1)
	"nuzky_zahradni": {"name": "Zahradní nůžky na živý plot", "short": "Zahradní nůžky", "type": "tool", "kg": 1.2, "price": 390, "durability": 300, "color": Color(0.35, 0.55, 0.3)},
	"sazenice_kvetin": {"name": "Sazenice květin (plato)", "short": "Květiny (sazenice)", "type": "seed", "kg": 0.4, "price": 35, "stack": 20, "color": Color(0.9, 0.4, 0.6)},
	"semena_brambory": {"name": "Sadbové brambory", "short": "Brambory (sadba)", "type": "seed", "kg": 0.5, "price": 45, "stack": 20, "color": Color(0.7, 0.6, 0.4)},
	"semena_mrkev": {"name": "Semena mrkve", "short": "Mrkev (semena)", "type": "seed", "kg": 0.02, "price": 25, "stack": 20, "color": Color(0.9, 0.5, 0.1)},
	"semena_cibule": {"name": "Sadbová cibule", "short": "Cibule (sadba)", "type": "seed", "kg": 0.3, "price": 35, "stack": 20, "color": Color(0.8, 0.6, 0.3)},
	"semena_salat": {"name": "Semena salátu", "short": "Salát (semena)", "type": "seed", "kg": 0.02, "price": 25, "stack": 20, "color": Color(0.3, 0.7, 0.2)},
	"semena_rajcata": {"name": "Sazenice rajčat", "short": "Rajčata (sazenice)", "type": "seed", "kg": 0.1, "price": 60, "stack": 20, "color": Color(0.8, 0.2, 0.1)},
	"semena_dyne": {"name": "Semena dýně", "short": "Dýně (semena)", "type": "seed", "kg": 0.02, "price": 30, "stack": 20, "color": Color(0.9, 0.6, 0.15)},
	"semena_cesnek": {"name": "Sadbový česnek (stroužky)", "short": "Česnek (sadba)", "type": "seed", "kg": 0.1, "price": 40, "stack": 20, "color": Color(0.92, 0.9, 0.85)},
	# ---- M2.4 úroda ze zahrady (typ food; `feed` = hodnota jako krmivo pro zvířata, M2.6)
	"brambory": {"name": "Brambory", "short": "Brambory", "type": "food", "kg": 0.3, "kcal": 90, "price": 8, "stack": 50, "feed": 1.0,
		"color": Color(0.72, 0.6, 0.38), "cook_to": "brambora_pecena"},
	"mrkev": {"name": "Mrkev", "short": "Mrkev", "type": "food", "kg": 0.15, "kcal": 40, "price": 8, "stack": 50, "feed": 1.0, "color": Color(0.92, 0.5, 0.1)},
	"cibule": {"name": "Cibule", "short": "Cibule", "type": "food", "kg": 0.15, "kcal": 30, "price": 8, "stack": 50, "color": Color(0.85, 0.65, 0.35)},
	"salat": {"name": "Hlávkový salát", "short": "Salát", "type": "food", "kg": 0.3, "kcal": 25, "price": 25, "stack": 20, "feed": 0.6,
		"perishable_h": 72, "color": Color(0.45, 0.75, 0.3)},
	"rajce": {"name": "Rajče", "short": "Rajče", "type": "food", "kg": 0.15, "kcal": 30, "price": 15, "stack": 50, "color": Color(0.85, 0.15, 0.1)},
	"dyne": {"name": "Dýně", "short": "Dýně", "type": "food", "kg": 2.0, "kcal": 180, "price": 60, "stack": 10, "feed": 1.5, "color": Color(0.92, 0.5, 0.1)},
	"cesnek": {"name": "Česnek", "short": "Česnek", "type": "food", "kg": 0.05, "kcal": 15, "price": 12, "stack": 50, "color": Color(0.94, 0.92, 0.86)},
	"brambora_pecena": {"name": "Pečená brambora", "short": "Pečená brambora", "type": "food", "kg": 0.25, "kcal": 190, "price": 0,
		"color": Color(0.6, 0.42, 0.22)},
	"polevka": {"name": "Bramborová polévka (talíř)", "short": "Polévka", "type": "food", "kg": 0.4, "kcal": 320, "price": 0,
		"color": Color(0.85, 0.75, 0.45)},
	"pronajem_pole": {"name": "Pronájem pole (1 rok)", "short": "Pronájem pole", "type": "misc", "kg": 0.0, "price": 1500, "color": Color(0.62, 0.5, 0.34)},
	"sazenice_jablon": {"name": "Sazenice jabloně", "short": "Sazenice jabloně", "type": "seed", "kg": 3.0, "price": 290, "stack": 1, "color": Color(0.4, 0.6, 0.2)},
	# M2.5 Sázení stromů (ceny 150–450 Kč; druhy a růst v `PlantedTrees.SPECIES`)
	"sazenice_slivon": {"name": "Sazenice slivoně", "short": "Sazenice slivoně", "type": "seed", "kg": 3.0, "price": 260, "stack": 1, "color": Color(0.45, 0.35, 0.55)},
	"sazenice_hrusen": {"name": "Sazenice hrušně", "short": "Sazenice hrušně", "type": "seed", "kg": 3.0, "price": 320, "stack": 1, "color": Color(0.55, 0.65, 0.25)},
	"sazenice_tresen": {"name": "Sazenice třešně", "short": "Sazenice třešně", "type": "seed", "kg": 3.0, "price": 350, "stack": 1, "color": Color(0.6, 0.2, 0.2)},
	"sazenice_dub": {"name": "Sazenice dubu", "short": "Sazenice dubu", "type": "seed", "kg": 2.5, "price": 180, "stack": 1, "color": Color(0.35, 0.5, 0.2)},
	"sazenice_buk": {"name": "Sazenice buku", "short": "Sazenice buku", "type": "seed", "kg": 2.5, "price": 180, "stack": 1, "color": Color(0.4, 0.55, 0.25)},
	"sazenice_smrk": {"name": "Sazenice smrku", "short": "Sazenice smrku", "type": "seed", "kg": 2.0, "price": 150, "stack": 1, "color": Color(0.15, 0.4, 0.2)},
	"sazenice_borovice": {"name": "Sazenice borovice", "short": "Sazenice borovice", "type": "seed", "kg": 2.0, "price": 150, "stack": 1, "color": Color(0.2, 0.45, 0.2)},
	"ochranny_obal": {"name": "Ochranný obal na sazenici", "short": "Ochranný obal", "type": "material", "kg": 0.2, "price": 45, "stack": 20, "color": Color(0.7, 0.85, 0.7)},
	"svestka": {"name": "Švestka", "short": "Švestka", "type": "food", "kg": 0.05, "kcal": 30, "price": 4, "stack": 30, "color": Color(0.32, 0.12, 0.42)},
	"hruska": {"name": "Hruška", "short": "Hruška", "type": "food", "kg": 0.18, "kcal": 90, "price": 7, "stack": 30, "color": Color(0.7, 0.75, 0.25)},
	"tresne": {"name": "Třešně", "short": "Třešně", "type": "food", "kg": 0.05, "kcal": 35, "price": 5, "stack": 30, "color": Color(0.6, 0.05, 0.1)},
	# ---- M2.6 Hospodářská zvířata: krmivo, nářadí a produkty (`FarmSpecs`, `Farm`); zelenina z M2.4 s klíčem `feed`
	# jde krmit taky (brambory, mrkev, salát, dýně). Ceny odhad (DOPLNIT).
	"zrni": {"name": "Slepičí zrní", "short": "Zrní", "type": "material", "kg": 0.05, "price": 15, "stack": 50, "color": Color(0.85, 0.7, 0.3)},
	"seno": {"name": "Otep sena", "short": "Seno", "type": "material", "kg": 3.0, "price": 25, "stack": 30, "color": Color(0.78, 0.66, 0.3)},
	"granule": {"name": "Krmné granule", "short": "Granule", "type": "material", "kg": 1.0, "price": 20, "stack": 50, "color": Color(0.55, 0.45, 0.3)},
	"kbelik": {"name": "Kbelík na dojení", "short": "Kbelík", "type": "tool", "kg": 1.0, "price": 150, "durability": 2000, "color": Color(0.75, 0.75, 0.78)},
	"nuzky": {"name": "Nůžky na stříhání ovcí", "short": "Nůžky", "type": "tool", "kg": 0.4, "price": 250, "durability": 100, "color": Color(0.6, 0.6, 0.65)},
	"nuz": {"name": "Řeznický nůž", "short": "Nůž", "type": "tool", "kg": 0.3, "price": 350, "durability": 200, "color": Color(0.7, 0.7, 0.72)},
	"vejce": {"name": "Vejce", "short": "Vejce", "type": "animal_product", "kg": 0.06, "kcal": 70, "price": 5, "stack": 30,
		"perishable_h": 480, "color": Color(0.92, 0.85, 0.65)},
	"mleko": {"name": "Mléko (1 l)", "short": "Mléko", "type": "animal_product", "kg": 1.0, "kcal": 65, "price": 18, "stack": 20,
		"perishable_h": 48, "color": Color(0.95, 0.94, 0.88)},
	"vlna": {"name": "Ovčí vlna (rouno)", "short": "Vlna", "type": "material", "kg": 2.5, "price": 150, "stack": 10, "color": Color(0.88, 0.85, 0.78)},
	"maso_drubez": {"name": "Drůbeží maso (syrové)", "short": "Drůbeží maso", "type": "meat", "kg": 1.0, "kcal": 150, "price": 130,
		"stack": 20, "perishable_h": 48, "cook_to": "pecene_maso", "color": Color(0.85, 0.68, 0.55)},
	"maso_kralici": {"name": "Králičí maso (syrové)", "short": "Králičí maso", "type": "meat", "kg": 1.0, "kcal": 130, "price": 150,
		"stack": 20, "perishable_h": 48, "cook_to": "pecene_maso", "color": Color(0.82, 0.62, 0.58)},
	"maso_veprove": {"name": "Vepřové maso (syrové)", "short": "Vepřové maso", "type": "meat", "kg": 1.0, "kcal": 250, "price": 140,
		"stack": 30, "perishable_h": 48, "cook_to": "pecene_maso", "color": Color(0.78, 0.42, 0.4)},
	"sadlo": {"name": "Vepřové sádlo", "short": "Sádlo", "type": "meat", "kg": 1.0, "kcal": 890, "price": 60,
		"stack": 20, "perishable_h": 720, "color": Color(0.95, 0.92, 0.82)},
	"maso_kozi": {"name": "Kozí maso (syrové)", "short": "Kozí maso", "type": "meat", "kg": 1.0, "kcal": 180, "price": 160,
		"stack": 20, "perishable_h": 48, "cook_to": "pecene_maso", "color": Color(0.72, 0.4, 0.32)},
	"maso_skopove": {"name": "Skopové maso (syrové)", "short": "Skopové maso", "type": "meat", "kg": 1.0, "kcal": 200, "price": 160,
		"stack": 20, "perishable_h": 48, "cook_to": "pecene_maso", "color": Color(0.68, 0.36, 0.3)},
	"maso_hovezi": {"name": "Hovězí maso (syrové)", "short": "Hovězí maso", "type": "meat", "kg": 1.0, "kcal": 220, "price": 180,
		"stack": 30, "perishable_h": 48, "cook_to": "pecene_maso", "color": Color(0.62, 0.22, 0.2)},
	# DOPLNIT: zjednodušené společné „Pečené maso" pro všechny druhy (skutečná hra by chtěla recept na druh) – opékání na ohni / kamnech
	"pecene_maso": {"name": "Pečené maso", "short": "Pečené maso", "type": "food", "kg": 0.9, "kcal": 620, "price": 0, "color": Color(0.55, 0.3, 0.2)},
	"jitrnice": {"name": "Jitrnice", "short": "Jitrnice", "type": "food", "kg": 0.2, "kcal": 380, "price": 55, "color": Color(0.7, 0.42, 0.28)},
	"udice": {"name": "Udice", "short": "Udice", "type": "tool", "kg": 0.6, "price": 220, "durability": 150, "color": Color(0.4, 0.3, 0.2)},
	"navnada_zizaly": {"name": "Žížaly na návnadu", "short": "Žížaly", "type": "material", "kg": 0.1, "price": 20, "stack": 20, "perishable_h": 48, "color": Color(0.6, 0.3, 0.3)},
	# ---- M2.7 Rybaření (`Fishing`, `data/ryby.json`): vybavení, návnady, úlovky (syrová ryba se zkazí za 12 h, na ohni se opeče
	# – `cook_to`; velikost úlovku se hlásí při lovu, v inventáři je jen druh, `kg` je průměr). Ceny odhad (DOPLNIT).
	"udice_lepsi": {"name": "Lepší udice (carbon)", "short": "Lepší udice", "type": "tool", "kg": 0.5, "price": 890, "durability": 300,
		"skill_req": {"rybareni": 10}, "color": Color(0.2, 0.2, 0.25)},
	"podberak": {"name": "Podběrák", "short": "Podběrák", "type": "gear", "kg": 0.8, "price": 240, "stack": 1, "hold": false, "color": Color(0.35, 0.4, 0.3)},
	"navnada_testo": {"name": "Těstíčko na ryby", "short": "Těstíčko", "type": "material", "kg": 0.1, "price": 15, "stack": 20, "perishable_h": 72, "color": Color(0.9, 0.85, 0.7)},
	"navnada_kukurice": {"name": "Sladká kukuřice na ryby", "short": "Kukuřice na ryby", "type": "material", "kg": 0.1, "price": 18, "stack": 20, "color": Color(0.95, 0.8, 0.15)},
	"ryba_pecena": {"name": "Pečená ryba", "short": "Pečená ryba", "type": "food", "kg": 0.4, "kcal": 380, "price": 0, "color": Color(0.7, 0.45, 0.25)},
	"ryba_kapr": {"name": "Kapr obecný", "short": "Kapr", "type": "fish", "kg": 2.0, "kcal": 120, "price": 120, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.55, 0.45, 0.25)},
	"ryba_lin": {"name": "Lín obecný", "short": "Lín", "type": "fish", "kg": 0.8, "kcal": 120, "price": 110, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.3, 0.4, 0.2)},
	"ryba_plotice": {"name": "Plotice obecná", "short": "Plotice", "type": "fish", "kg": 0.2, "kcal": 120, "price": 25, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.7, 0.72, 0.75)},
	"ryba_perlin": {"name": "Perlín ostrobřichý", "short": "Perlín", "type": "fish", "kg": 0.5, "kcal": 120, "price": 60, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.75, 0.65, 0.4)},
	"ryba_cejn": {"name": "Cejn velký", "short": "Cejn", "type": "fish", "kg": 1.0, "kcal": 120, "price": 45, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.6, 0.58, 0.5)},
	"ryba_okoun": {"name": "Okoun říční", "short": "Okoun", "type": "fish", "kg": 0.4, "kcal": 120, "price": 55, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.4, 0.5, 0.25)},
	"ryba_stika": {"name": "Štika obecná", "short": "Štika", "type": "fish", "kg": 2.0, "kcal": 120, "price": 200, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.35, 0.45, 0.25)},
	"ryba_candat": {"name": "Candát obecný", "short": "Candát", "type": "fish", "kg": 1.8, "kcal": 120, "price": 220, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.5, 0.5, 0.4)},
	"ryba_pstruh": {"name": "Pstruh obecný", "short": "Pstruh", "type": "fish", "kg": 0.3, "kcal": 120, "price": 90, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.55, 0.5, 0.35)},
	"ryba_jelec": {"name": "Jelec tloušť", "short": "Jelec", "type": "fish", "kg": 0.3, "kcal": 120, "price": 25, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.6, 0.6, 0.5)},
	"ryba_klen": {"name": "Klen obecný", "short": "Klen", "type": "fish", "kg": 0.8, "kcal": 120, "price": 40, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.55, 0.5, 0.4)},
	"ryba_uhor": {"name": "Úhoř říční", "short": "Úhoř", "type": "fish", "kg": 1.0, "kcal": 120, "price": 250, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.2, 0.22, 0.15)},
	"ryba_sumec": {"name": "Sumec velký", "short": "Sumec", "type": "fish", "kg": 5.0, "kcal": 120, "price": 400, "stack": 10, "perishable_h": 12, "cook_to": "ryba_pecena", "color": Color(0.25, 0.25, 0.2)},
	"luk": {"name": "Luk (sportovní reflexní)", "short": "Luk", "type": "weapon", "kg": 0.9, "price": 2900, "color": Color(0.5, 0.35, 0.2)},
	"kuse": {"name": "Kuše", "short": "Kuše", "type": "weapon", "kg": 3.0, "price": 5900, "color": Color(0.3, 0.3, 0.3)},
	"puska": {"name": "Lovecká puška (opakovačka, optika)", "short": "Puška", "type": "weapon", "kg": 3.5, "price": 18000, "color": Color(0.25, 0.2, 0.15)},
	"sipy": {"name": "Šípy do luku", "short": "Šípy", "type": "ammo", "kg": 0.05, "price": 25, "stack": 30, "color": Color(0.6, 0.5, 0.3)},
	"sipky_kuse": {"name": "Šipky do kuše", "short": "Šipky do kuše", "type": "ammo", "kg": 0.04, "price": 30, "stack": 30, "color": Color(0.5, 0.5, 0.5)},
	"naboje": {"name": "Náboje do pušky", "short": "Náboje", "type": "ammo", "kg": 0.03, "price": 40, "stack": 50, "color": Color(0.8, 0.6, 0.2)},
	# ---- M2.9 Lov zvěře (`Hunting`, `data/lov.json`): zvěřina po zpracování (kg = ks; čerstvá se zkazí za 3 dny, na ohni se upeče – cook_to),
	# trofej a doklad o původu (vzniká automaticky při legálním úlovku). Ceny odhad (DOPLNIT).
	"zverina_srnci": {"name": "Srnčí maso (syrové)", "short": "Srnčí maso", "type": "meat", "kg": 1.0, "kcal": 120, "price": 220, "stack": 30,
		"perishable_h": 72, "cook_to": "pecene_maso", "color": Color(0.6, 0.22, 0.2)},
	"zverina_divocak": {"name": "Divočí maso (syrové)", "short": "Divočí maso", "type": "meat", "kg": 1.0, "kcal": 160, "price": 150, "stack": 40,
		"perishable_h": 72, "cook_to": "pecene_maso", "color": Color(0.5, 0.2, 0.2)},
	"zverina_zajic": {"name": "Zaječí maso (syrové)", "short": "Zaječí maso", "type": "meat", "kg": 1.0, "kcal": 110, "price": 180, "stack": 20,
		"perishable_h": 72, "cook_to": "pecene_maso", "color": Color(0.62, 0.3, 0.26)},
	"trofej_parozky": {"name": "Srnčí paroží (trofej)", "short": "Paroží", "type": "collectible", "kg": 0.4, "price": 120, "stack": 10,
		"color": Color(0.8, 0.72, 0.55)},
	"doklad_puvod": {"name": "Doklad o původu zvěřiny", "short": "Doklad o původu", "type": "document", "kg": 0.0, "price": 0, "stack": 20,
		"color": Color(0.95, 0.95, 0.85)},
	"plachta": {"name": "Plachta", "short": "Plachta", "type": "gear", "kg": 1.2, "price": 180, "color": Color(0.2, 0.4, 0.6)},
	"rucni_vozik": {"name": "Ruční vozík", "short": "Ruční vozík", "type": "gear", "kg": 15.0, "price": 2490, "stack": 1, "world_object": true, "color": Color(0.6, 0.2, 0.1)},
	# ---- M2.3 Oblečení (trup, bunda, nohy, boty, ruce, hlava)
	"triko_cervene": {"name": "Triko červené", "short": "Červené triko", "type": "clothing", "slot": "trup", "insul": 0.1, "waterproof": 0.0, "style": "triko", "kg": 0.2, "price": 199, "stack": 1,
		"color": Color(0.85, 0.25, 0.18)},
	"triko_modre": {"name": "Triko modré", "short": "Modré triko", "type": "clothing", "slot": "trup", "insul": 0.1, "waterproof": 0.0, "style": "triko", "kg": 0.2, "price": 199, "stack": 1,
		"color": Color(0.2, 0.45, 0.8)},
	"triko_zelene": {"name": "Triko zelené", "short": "Zelené triko", "type": "clothing", "slot": "trup", "insul": 0.1, "waterproof": 0.0, "style": "triko", "kg": 0.2, "price": 199, "stack": 1,
		"color": Color(0.25, 0.5, 0.28)},
	"kosile_kostkovana": {"name": "Košile kostkovaná", "short": "Kostkovaná košile", "type": "clothing", "slot": "trup", "insul": 0.15, "waterproof": 0.0, "style": "kosile", "kg": 0.3, "price": 449, "stack": 1,
		"color": Color(0.55, 0.3, 0.22)},
	"kosile_slavnostni": {"name": "Košile bílá (slavnostní)", "short": "Bílá košile", "type": "clothing", "slot": "trup", "insul": 0.15, "waterproof": 0.0, "style": "kosile", "kg": 0.3, "price": 690, "stack": 1,
		"color": Color(0.93, 0.93, 0.9), "tags": ["slavnostni"]},
	"mikina_seda": {"name": "Mikina šedá", "short": "Šedá mikina", "type": "clothing", "slot": "trup", "insul": 0.3, "waterproof": 0.05, "style": "mikina", "kg": 0.6, "price": 690, "stack": 1,
		"color": Color(0.5, 0.5, 0.52)},
	"bunda_zimni": {"name": "Zimní bunda", "short": "Zimní bunda", "type": "clothing", "slot": "bunda", "insul": 0.55, "waterproof": 0.5, "style": "bunda", "kg": 1.4, "price": 2490, "stack": 1,
		"color": Color(0.15, 0.2, 0.35)},
	"vetrovka": {"name": "Větrovka", "short": "Větrovka", "type": "clothing", "slot": "bunda", "insul": 0.2, "waterproof": 0.35, "style": "vetrovka", "kg": 0.5, "price": 890, "stack": 1,
		"color": Color(0.3, 0.45, 0.3)},
	"platenka": {"name": "Pláštěnka do deště", "short": "Pláštěnka", "type": "clothing", "slot": "bunda", "insul": 0.05, "waterproof": 0.95, "style": "platenka", "kg": 0.3, "price": 249, "stack": 1,
		"color": Color(0.95, 0.8, 0.1)},
	"prsiplast": {"name": "Voskovaný plášť", "short": "Plášť", "type": "clothing", "slot": "bunda", "insul": 0.4, "waterproof": 0.6, "style": "prsiplast", "kg": 1.2, "price": 1990, "stack": 1,
		"color": Color(0.35, 0.3, 0.22)},
	"sako": {"name": "Sako (slavnostní)", "short": "Sako", "type": "clothing", "slot": "bunda", "insul": 0.2, "waterproof": 0.05, "style": "sako", "kg": 0.8, "price": 2290, "stack": 1,
		"color": Color(0.14, 0.15, 0.2), "tags": ["slavnostni"]},
	"reflexni_vesta": {"name": "Reflexní vesta", "short": "Reflexní vesta", "type": "clothing", "slot": "bunda", "insul": 0.05, "waterproof": 0.0, "style": "reflexni_vesta", "kg": 0.15, "price": 129, "stack": 1,
		"color": Color(0.95, 0.85, 0.1), "tags": ["reflexni", "pracovni"]},
	"dziny_modre": {"name": "Džíny modré", "short": "Modré džíny", "type": "clothing", "slot": "nohy", "insul": 0.2, "waterproof": 0.0, "style": "dziny", "kg": 0.7, "price": 799, "stack": 1,
		"color": Color(0.16, 0.22, 0.36)},
	"monterky": {"name": "Montérky", "short": "Montérky", "type": "clothing", "slot": "nohy", "insul": 0.25, "waterproof": 0.05, "style": "monterky", "kg": 0.8, "price": 699, "stack": 1,
		"color": Color(0.15, 0.3, 0.55), "tags": ["pracovni"]},
	"kratasy": {"name": "Kraťasy", "short": "Kraťasy", "type": "clothing", "slot": "nohy", "insul": 0.05, "waterproof": 0.0, "style": "kratasy", "kg": 0.3, "price": 349, "stack": 1,
		"color": Color(0.55, 0.5, 0.35)},
	"teplaky_zimni": {"name": "Zateplené kalhoty", "short": "Zimní kalhoty", "type": "clothing", "slot": "nohy", "insul": 0.35, "waterproof": 0.15, "style": "dziny", "kg": 0.9, "price": 890, "stack": 1,
		"color": Color(0.25, 0.25, 0.28)},
	"oblekove_kalhoty": {"name": "Oblekové kalhoty (slavnostní)", "short": "Oblekové kalhoty", "type": "clothing", "slot": "nohy", "insul": 0.2, "waterproof": 0.0, "style": "dziny", "kg": 0.5, "price": 990, "stack": 1,
		"color": Color(0.12, 0.13, 0.17), "tags": ["slavnostni"]},
	"ochranne_kalhoty": {"name": "Ochranné kalhoty k pile", "short": "Ochranné kalhoty", "type": "clothing", "slot": "nohy", "insul": 0.3, "waterproof": 0.1, "style": "monterky", "kg": 1.3, "price": 2990, "stack": 1,
		"color": Color(0.9, 0.45, 0.08), "tags": ["ochrana_pila", "pracovni"]},
	"plavky": {"name": "Plavky", "short": "Plavky", "type": "clothing", "slot": "nohy", "insul": 0.0, "waterproof": 0.0, "style": "plavky", "kg": 0.1, "price": 299, "stack": 1,
		"color": Color(0.15, 0.4, 0.7), "tags": ["plavky"]},
	"polobotky": {"name": "Kožené polobotky", "short": "Polobotky", "type": "clothing", "slot": "boty", "insul": 0.1, "waterproof": 0.0, "style": "", "kg": 0.9, "price": 1290, "stack": 1,
		"color": Color(0.13, 0.09, 0.07)},
	"tenisky": {"name": "Tenisky", "short": "Tenisky", "type": "clothing", "slot": "boty", "insul": 0.1, "waterproof": 0.0, "style": "tenisky", "kg": 0.6, "price": 990, "stack": 1,
		"color": Color(0.75, 0.75, 0.78)},
	"holinky": {"name": "Holínky", "short": "Holínky", "type": "clothing", "slot": "boty", "insul": 0.15, "waterproof": 0.9, "style": "holinky", "kg": 1.1, "price": 549, "stack": 1,
		"color": Color(0.1, 0.32, 0.15)},
	"pracovni_boty": {"name": "Pracovní boty", "short": "Pracovní boty", "type": "clothing", "slot": "boty", "insul": 0.2, "waterproof": 0.3, "style": "pracovni_boty", "kg": 1.3, "price": 1290, "stack": 1,
		"color": Color(0.4, 0.28, 0.14), "tags": ["pracovni"]},
	"zimni_boty": {"name": "Zimní boty", "short": "Zimní boty", "type": "clothing", "slot": "boty", "insul": 0.3, "waterproof": 0.6, "style": "pracovni_boty", "kg": 1.4, "price": 1890, "stack": 1,
		"color": Color(0.2, 0.15, 0.1)},
	"rukavice_zimni": {"name": "Zimní rukavice", "short": "Zimní rukavice", "type": "clothing", "slot": "ruce", "insul": 0.1, "waterproof": 0.05, "style": "rukavice", "kg": 0.15, "price": 349, "stack": 1,
		"color": Color(0.15, 0.15, 0.2)},
	"rukavice_pracovni": {"name": "Pracovní rukavice", "short": "Pracovní rukavice", "type": "clothing", "slot": "ruce", "insul": 0.03, "waterproof": 0.05, "style": "rukavice", "kg": 0.15, "price": 149, "stack": 1,
		"color": Color(0.75, 0.6, 0.3), "tags": ["pracovni"]},
	"cepice": {"name": "Kšiltovka", "short": "Kšiltovka", "type": "clothing", "slot": "hlava", "insul": 0.02, "waterproof": 0.05, "style": "cepice", "kg": 0.1, "price": 199, "stack": 1,
		"color": Color(0.2, 0.3, 0.5)},
	"cepice_zimni": {"name": "Zimní čepice", "short": "Zimní čepice", "type": "clothing", "slot": "hlava", "insul": 0.15, "waterproof": 0.05, "style": "kulich", "kg": 0.1, "price": 249, "stack": 1,
		"color": Color(0.55, 0.12, 0.12)},
	"klobouk": {"name": "Klobouk", "short": "Klobouk", "type": "clothing", "slot": "hlava", "insul": 0.03, "waterproof": 0.1, "style": "klobouk", "kg": 0.2, "price": 599, "stack": 1,
		"color": Color(0.35, 0.25, 0.12)},
	"helma_pila": {"name": "Přilba s ochranou sluchu a štítem", "short": "Pilařská přilba", "type": "clothing", "slot": "hlava", "insul": 0.05, "waterproof": 0.0, "style": "helma_pila", "kg": 0.9, "price": 1490, "stack": 1,
		"color": Color(0.92, 0.5, 0.08), "tags": ["ochrana_pila", "pracovni"]},
	"kukla": {"name": "Včelařská kukla", "short": "Včelařská kukla", "type": "clothing", "slot": "hlava", "insul": 0.02, "waterproof": 0.0, "style": "kukla", "kg": 0.3, "price": 0, "stack": 1,
		"color": Color(0.92, 0.92, 0.88), "tags": ["vcelar", "pracovni"]},
}


## M4.8: „Obsah pro dospělé“ (Esc → Nastavení). Nastavuje `GameSettings` / `PauseMenu`; výchozí vypnuto.
static var adult_on := false


## M4.8: ruční úpravy v inventáři (ubalení, pečení). `need` = kromě předmětu, na který se akce volá (ten se spotřebuje
## vždy), se spotřebuje ještě tohle; `out` vznikne. Jen při zapnuté volbě (položky jsou `adult`).
const RECIPES := {
	"tabak_list": [{"name": "Ubalit cigaretu", "need": {"papirky": 1}, "out": "tabak_susene"}],
	"konopi_susene": [
		{"name": "Ubalit joint", "need": {"papirky": 1}, "out": "konopi_kvety"},
		{"name": "Upéct konopné pečivo (s rohlíkem)", "need": {"rohlik": 1}, "out": "konopne_pecivo"}],
}


## Předmět s klíčem `adult` je ve hře jen při zapnuté volbě (vypnuto = neexistuje, ani v nabídkách).
static func hidden(id: String) -> bool:
	return ITEMS.has(id) and bool(ITEMS[id].get("adult", false)) and not adult_on


static func exists(id: String) -> bool:
	return ITEMS.has(id) and not hidden(id)


static func info(id: String) -> Dictionary:
	return ITEMS[id]


static func name_of(id: String) -> String:
	return String(ITEMS[id]["name"]) if ITEMS.has(id) else id


static func type_of(id: String) -> String:
	return String(ITEMS[id]["type"]) if ITEMS.has(id) else "misc"


## Hmotnost 1 ks v kg (chybí-li klíč `kg`, 0).
static func weight(id: String) -> float:
	return float(ITEMS[id].get("kg", 0.0)) if ITEMS.has(id) else 0.0


static func is_stackable(id: String) -> bool:
	return ITEMS.has(id) and int(ITEMS[id].get("stack", 99)) > 1


## Co se z předmětu stane na ohni (M2.2; klíč `cook_to`, M2.7 ryby a M2.9 zvěřina jen doplní klíč u svých předmětů). "" = nejde opékat.
static func cook_to(id: String) -> String:
	return String(ITEMS[id].get("cook_to", "")) if ITEMS.has(id) else ""


## Výsledek při spálení (`burnt_to`, výchozí `spalene_jidlo`).
static func burnt_to(id: String) -> String:
	return String(ITEMS[id].get("burnt_to", "spalene_jidlo")) if ITEMS.has(id) else "spalene_jidlo"


static func by_type(t: String) -> Array[String]:
	var out: Array[String] = []
	for id in ITEMS:
		if ITEMS[id]["type"] == t and not hidden(id):
			out.append(id)
	return out


## Nadpis skupiny v inventáři pro daný předmět.
static func group_of(id: String) -> String:
	return String(TYPE_LABELS.get(type_of(id), "Ostatní"))
