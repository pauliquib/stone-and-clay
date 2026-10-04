# M5.4 – Hasičský sport: požární útok (minihra) a soutěž

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 4/9
> Předpoklady: M5.3 (spolek, technika), M5.6 nebo aspoň hřiště (poloha) · Navazují: M5.5 (soutěž jako událost v kalendáři)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.5 „Hasičský sport (16)“
3. Záznam M5.3 v `PROJECT_LOG.md` a `scripts/` hasičů (grep `class_name` v nových souborech M5.3)
4. `scripts/priroda/village_events.gd` – `BONFIRE_POS` (poloha hřiště), `_build_carodejnice` (jak se staví dočasná scéna a dav)
5. `scripts/humanoid.gd` – běh, `hold`, akce paží; `scripts/villager.gd` (NPC pohyb k cíli)
6. `scripts/hud.gd` – `popup`, `open_menu` (výsledková tabule)

## 1. Proč
Hasičský sport je na vsích fenomén. **Požární útok** – družstvo co nejrychleji nasaje vodu z kádě
přenosnou stříkačkou, rozvine hadice a dvěma proudy nastříká terče. Hraje se na čas.

## 2. Pravidla (zjednodušeně, laditelné v `data/hasicsky_sport.json`)
- Základna (podložka 2 × 2 m) s mašinou (PS 12), káď s vodou (1 000 l), 2 savice, sací koš, 2 hadice B, rozdělovač,
  4 hadice C, 2 proudnice; 2 **nástřikové terče** ve vzdálenosti ~ 90 m od základny (světla nad terči se rozsvítí
  při naplnění).
- Družstvo 7 členů: **strojník** (nastartuje, dá plyn), **koš** (našroubuje sací koš), **savice 1 a 2** (spojí savice),
  **béčko** (rozvine B k rozdělovači), **rozdělovač** (připojí C a otevře ventily), **proudař levý / pravý** (rozvine C
  a míří na terč).
- Start na signál (výstřel startovní pistole), čas se měří do naplnění **obou** terčů. Běžné časy: 18–30 s vesnická
  liga, přes 30 s pomalé, neplatný pokus (rozpojená hadice, chybné pořadí) = N.P.

## 3. Minihra
- Hráč si vybere **roli** (na tréninku / soutěži u velitele), ostatní role hrají NPC s časy podle „formy“ družstva
  (průměrné časy + rozptyl; respekt / tréninky zlepšují formu).
- **Vstupy podle role** (krátké časované sekvence – QTE):
  - strojník: po spojení savic E (nastartovat, 3 pokusy – studený motor), pak držet plyn LMB v zelené zóně otáček (moc =
    rozpojení / „vyražení“ hadice),
  - koš / savice: běh k místu + stisknout E ve správný okamžik (pruh), chyba = zdržení 1–2 s,
  - béčko: běh s hadicí (hadice se rozvíjí za hráčem – čára / řetěz segmentů), dobíhá k rozdělovači,
  - proudař: běh 70 m s rozvíjenou hadicí C, pak míření proudnicí (vodní proud – oblouk částic, míření myší) na terč –
    terč se plní jen, když proud zasahuje otvor.
- **Fyzika vody:** jednoduchá – po otevření rozdělovače teče voda do proudů se zpožděním (plnění hadic 3–4 s), tlak podle
  otáček strojníka (dostřel proudu).
- Výsledek: čas, pořadí, hláška („Nový rekord sboru!“), XP `hasicina` + `kondice`, respekt `hasici`.

## 4. Trénink a soutěž
- **Trénink** každou středu 18:00 na hřišti (M5.3) – dráha se postaví (dočasně jako scéna čarodějnic) – libovolně pokusů.
- **Soutěž** (událost – přidej do `VillageEvents.EVENTS` nebo do kalendáře M5.5): 1× za sezónu (sobota v červnu),
  4–6 družstev (smyšlené přídomky), diváci, stánek s pivem a klobásou, výsledková tabule, pohár (do klubovny).
  Vítězství → respekt `hasici` +10, pověst +5.
- Kategorie ženy / muži / veteráni – jen text v tabulce.

## 5. Hotovo, když
- Na tréninku jde hrát požární útok v kterékoli roli; NPC hrají ostatní role; čas a chyby se počítají; soutěž v červnu
  má více družstev, diváky a výsledky.

## 6. Návrh checklistu ručních testů
1. Středa 18:00, člen SDH → hřiště → trénink, vyber roli strojník → start, plyn v zelené → čas.
2. Role proudař: běh, míření na terč → terč se plní, světlo.
3. Přehnaný plyn → rozpojená hadice → N.P.
4. Opakuj 5 pokusů → čas se zlepšuje (forma).
5. F2 → Datum soutěžní sobota v červnu → soutěž, 5 družstev, diváci, tabule, pohár.
6. Vítězství → respekt Hasiči v deníku.

## 7. Závěr
README (Systémy → Hasičský sport), `data/hasicsky_sport.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI,
commit „M5.4 Hasičský sport: …“, checklist a čekat.
