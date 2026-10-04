# M2.8 – Lovecké zbraně a střelba (luk, kuše, puška) + střelnice

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 8/10
> Předpoklady: M0.2–M0.5 · Navazují: M2.9 (lov), M4.6 (zbrojní oprávnění, lovecký lístek, stráže)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3; tón hry: satira, ale zbraně = vážné důsledky)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Lovecké zbraně (U2)“ a „Kdo tě může chytit“
3. `scripts/player.gd` – `scope_on`, `scope`, `SCOPE_FOV` (dalekohled X – **vzor pro míření s optikou**), `_apply_look`
4. `scripts/local_client.gd` – obsluha dalekohledu (grep `scope`), `_unhandled_input`
5. `scripts/tool_models.gd` (luk, kuše, puška z M0.4), `scripts/actions.gd` (nástroj v ruce), `scripts/humanoid.gd` (akce `aim`)
6. `scripts/police.gd` – jak policie reaguje na přestupek v dohledu (grep `wanted|chase|witness`)
7. `scripts/law.gd` + `data/zakon.json`

## 1. Proč
Uživatel chce lovecké zbraně: **luk, kuši, pušku**. Puška jen se **zbrojním oprávněním**, jinak řeší
policie. Luk a kuši lze koupit volně, ale **lov jimi je v ČR zakázán** – je to záměrně možná, ale zakázaná
cesta (pytláctví). Tento krok dodá zbraně a střelbu; lov zvěře je M2.9, doklady a stráže M4.6.

## 2. Návrh
### 2.1 Zbraně (v `ItemsDB`, typ `weapon`, + tabulka `WEAPONS` v novém `scripts/weapons.gd`, `class_name Weapons`)
| Zbraň | Střelivo | Nabití | Úsťová rychlost | Účinný dostřel | Hluk (slyšet do) | Nákup |
|---|---|---|---|---|---|---|
| Luk (sportovní reflexní) | `sipy` | 1,2 s (natažení drží LMB) | ~60 m/s | 30 m | 25 m | volně – Potraviny / stavebniny „Sport“ 2 900 Kč |
| Kuše | `sipky_kuse` | 4 s | ~100 m/s | 45 m | 30 m | volně 5 900 Kč |
| Puška kulovnice (opakovačka, 3 náboje) | `naboje` | 1,5 s mezi ranami, přebití 4 s | ~800 m/s | 200 m | **1 500 m** | **jen se zbrojním oprávněním** (`World.has_permit(id, "zbrojni")` – zatím false → obchod odmítne) |
Volitelně brokovnice (drobná zvěř) – otevřený bod.

### 2.2 Míření a střelba
- Zbraň v ruce (Q). **Pravé tlačítko** = mířit: kamera přiblíží (luk/kuše FOV 45°, puška s optikou jako dalekohled
  FOV 8–12°, použij logiku `scope`), animace `aim`, zpomalení chůze. **Levé tlačítko** = výstřel (u luku držet =
  natahovat, síla podle doby, pustit = výstřel).
- **Kolísání mušky:** podle výdrže (po sprintu víc), opilosti (`BodyState.drunk_level` – hodně), chladu (`cold`),
  dovednosti `strelba` (méně) a dechu (Shift při míření = zadržet dech 3 s – menší kolísání, pak horší).
- **Balistika:** projektil jako `RayCast` po krocích (ne `RigidBody` – výkon): gravitace, šíp pomalý (vidět letět –
  malý mesh), kulka rychlá (trasovač neviditelný, jen dopad). Vítr (`Weather.wind_vector`) ovlivní šíp.
  Zásah: terén (prach), strom (šíp se zapíchne a zůstane 2 min, jde sebrat zpět – akce `sebrat`), zvíře (M2.9 –
  zatím jen `emit_game_event("shot_hit", {target, part, energy})`), osoba / auto / budova → viz 2.4.
- Zásahové zóny zvířete připrav obecně: `hit_zone(local_point) -> "hlava" | "srdce_plice" | "bricho" | "noha"`
  (odhad podle pozice v rámci modelu – M2.9 zapojí).
- **Zvuk:** výstřel pušky přes `World.sound(pos, "gunshot", …, max_dist 1500)` – všichni NPC / zvěř / hajný v dosahu
  ho „slyší“ (zvěř v okruhu 400 m prchne – najdi v `animal.gd _perceive`, jak reaguje na hluk, a přidej).
- XP `strelba`: zásah terče podle vzdálenosti a přesnosti.

### 2.3 Střelnice (legální trénink)
- Místo: u myslivecké chaty (bezpečný val / svah za terči) – `pois` má `chata`; postav 3 terče (kruhové, 10–50 m a
  100 m pro pušku), stůl. Terč ukazuje zásahy (malé tečky – decaly), E u stolu → skóre posledních 5 ran.
- Střelba na střelnici je legální (s puškou jen s oprávněním – kontroluje myslivec, pokud je přítomen).

### 2.4 Zákon a bezpečnost (napoj na `commit_offense`, svědky a policii)
Přidej do `data/zakon.json` (paragrafy s „ověřit“; od 1. 1. 2026 platí nový zákon o zbraních č. 90/2024 Sb.):
- `nedovolene_ozbrojovani` – držení pušky bez oprávnění (trestný čin, 40/2009 Sb. § 279),
- `strelba_v_obci` – výstřel (jakýkoli) v zástavbě (`Fauna.settle_at > 0.5`) nebo do 100 m od silnice / domu,
- `zbran_pod_vlivem` – zbraň v ruce s promile > 0 (a výstřel),
- `ublizeni_na_zdravi` – zásah člověka (NPC hráče – zranění, pád, NPC uteče, přivolá policii) – trestný čin,
- `poskozeni_veci` – zásah auta / okna / zvířete v ohradě.
- Viditelnost zbraně: puška v ruce v obci → vesničané se leknou (hláška), mohou volat policii (šance podle povahy);
  přes rameno (Q na prázdné ruce – zbraň „na zádech“, vizuál na zádech) nevadí, pokud má hráč oprávnění.
- Policie při kontrole (`police.gd`) zkontroluje, jestli má hráč pušku a oprávnění → bez oprávnění zadržení,
  zabavení zbraně (`remove_item`), záznam.

### 2.5 Ukládání
Zbraně a střelivo jsou v inventáři (M0.2) – nic navíc; zapíchnuté šípy neukládat.

## 3. Hotovo, když
- Luk a kuše jdou koupit a střílet (natahování, míření, balistika, vítr, sebrání šípů); puška bez oprávnění koupit nejde.
- Střelnice u chaty funguje se skóre; výstřel v obci / opilý / na lidi je přestupek nebo trestný čin se svědky.

## 4. Návrh checklistu ručních testů
1. Kup luk a 10 šípů; střelnice u chaty: pravé tl. míření, LMB natáhnout a pustit → šíp letí obloukem, zásah v terči.
2. Při silném větru šíp uhýbá; po sprintu muška víc kolísá; Shift = zadržet dech.
3. Šíp ve stromě → sebrat zpět.
4. Pokus koupit pušku → „Bez zbrojního oprávnění vám ji neprodám.“
5. F2 cheat „zbrojní oprávnění“ (přidej do `World.cheat` pro test) → koupit pušku, střílet na 100 m terč s optikou.
6. Výstřel z pušky u lesa → zvěř v okolí prchá.
7. Výstřel šípem v obci u vesničana → přestupek, vesničan utíká.
8. Po 3 pivech s puškou v ruce ve vsi → přestupek / policie.
9. Policejní kontrola s puškou bez oprávnění (cheat vypnout) → zadržení a zabavení.

## 5. Závěr
README (Systémy → Zbraně, Ovládání → pravé/levé tl., Shift), `data/zakon.json`, VIZE odškrtnout, roadmapa README,
PROJECT_LOG, deník AI, commit „M2.8 Zbraně a střelba: …“, checklist a čekat.
