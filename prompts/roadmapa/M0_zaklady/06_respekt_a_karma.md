# M0.6 – Respekt v komunitách a skrytá karma

> Roadmapa „Život na vsi“ · **M0 Základy** · krok 6/6
> Předpoklady: M0.5 · Navazují: M4.5 (nové cesty ke zlepšení), M5 (spolky), M3 (práce – požadavky)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. **3.5 Pověst, respekt, karma**
3. `scripts/reputation.gd` (celý) – rozšiřuješ ho
4. `scripts/persona.gd` (celý, 79 ř.) a `scripts/characters.gd` (prvních ~60 ř. + grep `job`, `topics`) – povahy a povolání postav
5. `scripts/world.gd` – `dialog_context`, `_apply_reply` (jak pověst ovlivňuje rozhovor)
6. `scripts/hud.gd` – `reputation_changed`, `_journal_bbcode`

## 1. Proč
Pověst v obci (−100…100) už existuje. Uživatel chce **víc způsobů, jak si zlepšit pověst, respekt
a karmu** (práce na zahradě, plnění úkolů, slušnost, kamarádský přístup). Zavedeme dvě nové osy,
aby dobré a špatné skutky měly různý dopad podle toho, **kdo** je vidí a **co** znamenají.

## 2. Návrh (rozšíření `Reputation`, žádná nová třída není nutná)
```gdscript
## Komunity: id → [název, kdo do ní patří (povolání / témata postav), barva]
const COMMUNITIES := {
	"sousede": ["Sousedé", ...], "stamgasti": ["Štamgasti", ...], "hasici": ["Hasiči", ...],
	"fotbal": ["Fotbalisté", ...], "zemedelci": ["Zemědělci a myslivci", ...], "mladez": ["Mládež", ...],
}
var respect := {}      # komunita → −100..100
var karma := 0.0       # −100..100, skrytá
func change_respect(comm: String, delta: float, text: String) -> void
func change_karma(delta: float, why: String) -> void      # bez hlášky na HUD (skrytá), jen do historie
func respect_of(comm: String) -> float
func karma_word() -> String   # „čisté svědomí“, „nic zvláštního“, „něco tě tíží“, „prokletý“ … (5 stupňů)
func community_of(persona: Persona) -> String   # podle povolání / témat postavy
```

### 2.1 Pravidla (laditelná tabulka `EVENT_EFFECTS`: kind → {rep, respect: {comm: delta}, karma})
- Přesunout současné dopady z `on_event` do tabulky tam, kde to jde (chování se nesmí změnit).
- Nově:
  - každý **přestupek** (`offense` z M0.5): karma −1 až −5 podle závažnosti, i bez svědků;
  - **úkol splněný**: respekt komunity zadavatele (hospoda → štamgasti, děda → sousedé, chata → zemědělci a myslivci);
  - **slušnost v rozhovoru**: respekt komunity postavy +1 (limit jako dnes u pověsti – max +2 za den od jedné postavy);
  - **urážka**: respekt komunity −3, karma −1;
  - **sražení zvířete a ujetí**: karma −3; **nahlášení srážky se zvěří** (už existuje z přírody 04 – grep) karma +2.
- Karma ovlivní (jen háčky, využijí další kroky): `func luck() -> float` (−0,2..+0,2) – šance na nález,
  úspěch akce (`M0.4 fail_chance`), náhodné události. Zapoj ji hned do `fail_chance` v akcích.
- Respekt ovlivní: pozdrav a tón postavy dané komunity (v `dialog_context` přidej `respect`), dostupnost
  práce a spolků (háček `respect_of`).

### 2.2 Přátelství (kamarádský přístup)
`Persona` už si pamatuje známost a náladu. Přidej `friendship` (0..100): roste opakovaným slušným
kontaktem (max. 1× za herní den), dárkem (dát předmět postavě – zatím jen háček `World.give_to_npc(id, npc, item)`
bez UI, UI dodá M4.5), klesá urážkou. Ukládá se s náladami postav. Při ≥ 60 postava pozdraví jménem hráče
a v M2.10 může pomoct nést divočáka.

### 2.3 HUD a deník
- Deník J: oddíl „Vztahy“ – pověst (jako dnes), respekt po komunitách (název + slovně: „váží si tě“, „nevšímají si tě“, „nemají tě rádi“), karma jen slovně, top 5 přátel.
- Změna respektu: krátká zpráva jako u pověsti („Hasiči: +3 – pomohl při soutěži“). Karma bez hlášky.

## 3. Hotovo, když
- Pověst funguje beze změny; respekt a karma se mění podle tabulky, ukládají se, deník je ukazuje.
- Postavy s vysokým respektem / přátelstvím odpovídají vřeleji (viditelné v rozhovoru).

## 4. Návrh checklistu ručních testů
1. J → Vztahy: pověst, 6 komunit „nevšímají si tě“, karma „nic zvláštního“.
2. Splň úkol v hospodě → pověst + respekt štamgastů.
3. Slušně mluv s trenérem fotbalu (T „dobrý den, jak se máte“) → respekt Fotbalisté +1; opakuj → limit za den.
4. Uraz vesničana → respekt jeho komunity dolů, v deníku karma se zhorší po více urážkách.
5. Řízení opilý (bez svědků) → karma klesne (v deníku slovně), pověst jako dřív.
6. F5/F9 → vše zůstane; starý save → výchozí hodnoty.

## 5. Závěr
README (Systémy → Pověst, respekt, karma), GAME_DESIGN, VIZE odškrtnout, roadmapa README, PROJECT_LOG,
deník AI, commit „M0.6 Respekt a karma: …“, checklist a čekat.
