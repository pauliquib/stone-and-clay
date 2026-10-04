# M4.1 – Řidičská oprávnění a autoškola

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 1/6
> Předpoklady: M0.5 (zákon), M1.6 (`skupina_rp` u vozidel), M3.4 (eTesty) · Navazují: M3.3 (rozvoz), M4.2 (přezkoušení po 12 bodech)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.4 „Řidičská oprávnění“
3. `scripts/law.gd` + `data/zakon.json` (M0.5) – body, zákaz řízení
4. `scripts/police.gd` – `license_ok`, kontrola dokladů (grep `license|doklad|kontrol`)
5. `scripts/car_model.gd` / katalog vozidel (M1.6 – `skupina_rp`), `scripts/world.gd` – `enter_car`
6. `scripts/computer_ui.gd` – eTesty (`TestUI`, `data/testy/`)
7. `scripts/quests.gd` – vzor úkolu s trasou a podmínkami (pro jízdy s instruktorem)

## 1. Proč
Simulace reálného života v ČR: řídit se smí jen s příslušným řidičským oprávněním. Hráč ho na začátku má
jen pro **B** (auto) a **AM** (moped) – motorka Javor (250 ccm) a traktor vyžadují další skupiny, které si
může udělat v autoškole. Bez oprávnění = přestupek nebo trestný čin.

## 2. Návrh
### 2.1 Doklady
- Nový obecný systém dokladů `scripts/permits.gd` (`class_name Permits`, per hráč `World.permits[id]`):
  `has(kind: String, sub := "") -> bool`, `grant(kind, sub, valid_until := -1)`, `revoke(kind, sub, reason)`,
  `list()` → deník. Druhy: `ridicsky` (sub = skupina), později `zbrojni`, `lovecky_listek`, `rybarsky_listek`,
  `povolenka_lov`, `povolenka_rybolov`, `dron_a1a3`, `pilot_ul`, `povoleni_kaceni`.
  **Nahraď** háček `World.has_permit(id, kind, …)` z dřívějších kroků → volá `Permits`.
- Klávesa **P** = přehled dokladů (panel s kartičkami: řidičák – skupiny, platnost, body z `Law`).
- Výchozí stav nové hry: `ridicsky` B + AM. **Starý save**: dej B + AM + A (aby se nerozbila hra s motorkou) – napiš do logu.

### 2.2 Skupiny (zjednodušeně podle 361/2000 Sb. – v `data/zakon.json` sekce `ridicska_opravneni` s poznámkou „ověřit“)
| Skupina | Vozidla ve hře | Min. věk (info) |
|---|---|---|
| AM | moped, skútr do 45 km/h | 15 |
| A1 | motocykl do 125 ccm | 16 |
| A2 | motocykl do 35 kW (Javor 250) | 18 |
| A | motocykl bez omezení | 24 (nebo 2 roky A2) |
| B | osobní auto, dodávka do 3,5 t, pickup | 18 |
| T | traktor | 17 |
`enter_car` → pokud hráč nemá skupinu vozidla: hláška „Na tohle nemáš řidičák (skupina A2)“ a **jde to** (hra nic nezakazuje),
ale jízda = přestupek / trestný čin `rizeni_bez_opravneni` (361/2000 Sb. § 125c odst. 1 písm. e) – přestupek; opakovaně
do 2 let trestný čin § 337 – „ověřit“) → zjistí se při policejní kontrole (napoj do `police.gd` kontroly dokladů).

### 2.3 Autoškola
- Místo: kancelář v obci (nový `Place` nebo nabídka na úřadě „Autoškola Volant (smyšlená)“), instruktor NPC.
- Kurz skupiny (cena: A2 9 900 Kč, A 7 900 Kč, T 6 900 Kč, AM – má): 1) **teorie** – eTest na PC (M3.4, `data/testy/autoskola.json`,
  25 vlastních otázek, 20 náhodných, projde při ≥ 85 %), 2) **jízdy s instruktorem** – 3 jízdy (úkol: trasa po obci
  a okolí s kontrolními body, instruktor sedí vedle / jede za tebou na motorce), podmínky: max rychlost v obci 50 km/h,
  zastavit na STOP (pokud jsou značky – `prop_models` má dopravní značky; jinak na křižovatkách), nenabourat,
  střízlivost, 3) **zkouška** (stejná jako jízda + komisař, 2 hrubé chyby = neprospěl, opakování za poplatek).
- Úspěch → `Permits.grant("ridicsky", skupina)`, XP `rizeni` 100, pověst +1.

### 2.4 Kontrola a důsledky
- Policie při kontrole (`police.gd`) chce řidičák: bez dokladu pro skupinu → `commit_offense("rizeni_bez_opravneni")`,
  zákaz další jízdy (auto odtaženo domů – najdi `move_player_car_to`), pokuta.
- 12 bodů (M0.5) → `revoke("ridicsky", "*")` na 1 rok a pro vrácení: **přezkoušení** v autoškole (teorie + jízda) – M4.2
  řeší žádost na úřadě; tady jen stav „odebráno – nutné přezkoušení“.

## 3. Hotovo, když
- P ukazuje doklady; vozidla vyžadují skupinu; jízda bez ní je přestupek při kontrole; autoškola (teorie na PC, jízdy, zkouška)
  udělí skupinu; vše se ukládá.

## 4. Návrh checklistu ručních testů
1. Nová hra → P: řidičák B, AM.
2. Motorka Javor → „Na tohle nemáš řidičák (A2)“; jeď → policejní kontrola → přestupek.
3. Autoškola → kurz A2 → PC eTest (neprojdi a pak projdi).
4. Jízdy s instruktorem: 60 km/h v obci → chyba.
5. Zkouška → P: A2; kontrola policie → v pořádku.
6. Starý save → B, AM, A – motorka bez přestupku.
7. F5/F9 → doklady zůstanou.

## 5. Závěr
README (Systémy → Doklady, Ovládání → P), `data/zakon.json`, `data/testy/autoskola.json`, VIZE odškrtnout, roadmapa README,
PROJECT_LOG, deník AI, commit „M4.1 Řidičská oprávnění a autoškola: …“, checklist a čekat.
