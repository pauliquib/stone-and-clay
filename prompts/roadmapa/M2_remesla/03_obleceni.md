# M2.3 – Oblečení: sloty, teplo, nepromokavost, vzhled, šatník

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 3/10
> Předpoklady: M0.2, M1.4 (šatník doma) · Navazují: M2.1 (ochrana k pile), M3 (pracovní oděv), M5.3 (zásahový oblek), M5.2 (plavky)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Oblečení“
3. `scripts/humanoid.gd` – hlavička, proměnné vzhledu (grep `var .*color|hat|beard|outfit|uniform`), `_build_torso`, `_build_leg`, `_build_head` (klobouky) – **jak se dnes barví a tvaruje oblečení**
4. `scripts/persona.gd` / `characters.gd` – jak se nastavuje vzhled postav (grep `appearance|look|hat`)
5. `scripts/body_state.gd` – `COLD_COMFORT`, `CHILL_RATE`, `WET_RAIN`, výpočet `wetness` / `cold` (grep)
6. `scripts/player.gd` – `beekeeper_suit` (jak funguje dnešní „kukla“ – vzor), `_update_body`
7. `scripts/items_db.gd` (typ `clothing`), `scripts/interior.gd` (šatník v domově)

## 1. Proč
Uživatel chce měnit oblečení. Navíc to propojí počasí (zima, déšť) a práci (pracovní oděv, ochrana k pile,
hasičský oblek) – oblečení bude mít **vlastnosti**, ne jen barvu.

## 2. Návrh
- Sloty: `hlava`, `trup` (triko/košile), `bunda`, `nohy`, `boty`, `ruce`. `Player.outfit := {slot: item_id}`
  (ukládá se). Oblečení = předměty typu `clothing` v `ItemsDB` s klíči:
  `slot`, `insul` (tepelná izolace 0..1), `waterproof` (0..1), `color`, `style` (klíč pro `Humanoid` – „triko“,
  „kosile“, „mikina“, „bunda“, „prsiplast“, „montérky“, „dzíny“, „kratasy“, „holinky“, „pracovni_boty“,
  „tenisky“, „cepice“, „klobouk“, „kukla“, „helma_pila“, „reflexni_vesta“, „plavky“…), `tags`
  (`ochrana_pila`, `reflexni`, `pracovni`, `slavnostni`, `hasic`, `plavky`).
- Výchozí oblečení hráče = to, co má dnes (převeď na předměty, aby se vzhled nezměnil).
- **Vzhled:** `Humanoid.apply_outfit(outfit: Dictionary)` – přestaví díly (trup, nohy, boty, hlava) podle `style`
  a `color`. Využij stávající stavbu dílů (loft/lathe) – např. bunda = širší trup + delší rukávy + límec,
  kraťasy = kratší nohavice (barva kůže na lýtku), holinky = vyšší boty. Přestavba jen při změně (ne každý snímek).
- **Fyziologie:** `BodyState` dostane `insulation` (součet `insul`, max ~1,5) a `waterproof` (vážený průměr trup+bunda+hlava):
  `COLD_COMFORT` se posune dolů o `insulation × 12 °C`, promáčení × (1 − waterproof). Příliš teplé oblečení
  v létě (> 25 °C a insul > 0,8) → víc žízně / pocení (jen menší výdrž – laditelné, volitelné).
- **Šatník:** v domově (M1.4) E → nabídka „Převléknout“: pro každý slot vybrat z vlastněného oblečení.
  Mimo domov: klávesa **I** = přehled, co máš na sobě (bez převlékání); převléct jde i z inventáře (Tab → „Obléct“)
  – trvá 5 s (akce `kneel`), ne v autě.
- **Obchod s oblečením:** do Potravin sekce „Textil“ (triko, mikina, pláštěnka, holinky, čepice, rukavice)
  a „Pracovní“ (montérky, pracovní boty, reflexní vesta, rukavice); ochranné kalhoty a helma k pile
  (tag `ochrana_pila`) – ceny realistické.
- **Reakce postav:** `dialog_context` dostane `outfit_tags` – slavnostní oblečení na úřadě / zábavě = +1 nálada,
  plavky ve vsi = poznámka postavy (humor). Jen pár hlášek.
- Kukla včelaře: převeď `beekeeper_suit` na kus oblečení (`kukla`, tag `vcelar`) – chování zachovat.

## 3. Hotovo, když
- Hráč se převlékne doma i z inventáře; vzhled se změní; zimní oblečení chrání před chladem, pláštěnka před deštěm.
- Uložení / načtení zachová oblečení; starý save = výchozí oblečení.

## 4. Návrh checklistu ručních testů
1. `./run.sh` → vzhled hráče stejný jako dřív; I → seznam oblečení.
2. Potraviny → kup pláštěnku, holinky, čepici; Tab → Obléct → vzhled se změní (3. osoba, V).
3. F2 → leden −10 °C: v tričku prochladneš rychle, v bundě + čepici pomalu (sleduj HUD / deník).
4. Déšť: s pláštěnkou promokneš pomalu.
5. Doma šatník → převlékni všechny sloty.
6. Kukla u včel → nebodají (jako dřív).
7. F5/F9 → oblečení zůstane.

## 5. Závěr
README (Systémy → Oblečení, Ovládání → I), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M2.3 Oblečení: …“, checklist a čekat.
