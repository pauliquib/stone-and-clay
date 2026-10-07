# Start M7 – zadání pro novou session (orchestrátor, model Sonnet 5)

Zkopíruj do nové session. Model nastav **před spuštěním**, aby ho zdědili i subagenti:

```bash
# v kořeni repozitáře; proměnná pojistí, že subagenti poběží na Sonnet 5 (ne na aliasu „sonnet“ = nejnovější)
CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-5 claude --model claude-sonnet-5
```

(Když session už běží: `/model claude-sonnet-5`; subagenti pak model zdědí, pokud ho orchestrátor nezadá.)

---

Pokračujeme na hře Stone & Clay. M0–M6 jsou hotové (M5 uzavřena závěrečnou kontrolou `23e98bf`, ruční testy M5 čekají
na uživatele). **Multiplayer (V2) se teď vůbec neřeší.** Zbývá milník **M7 Cesta na starostu** – hlavní cíl hry.
Pracuješ jako **orchestrátor**: práci rozplánuješ, necháš si plán schválit a pak ji zadáváš subagentům ve vlnách tak,
aby si nepřekáželi a aby sis **nezahltil kontextové okno**.

## Pravidla orchestrátora (šetři kontext)
- **Sám kód nepiš a velké soubory nečti.** Čteš jen: tento soubor, `00_SPOLECNE.md`, oddíl M7 v `prompts/roadmapa/README.md`,
  poslední 3 záznamy `PROJECT_LOG.md` a **shrnutí, která ti vrátí subagenti**. Prompty kroků (`M7_starosta/0X_*.md`)
  nečti celé – subagent je čte sám; ty potřebuješ jen hlavičku (předpoklady) a oddíl „Minimum“ (`sed -n` / `Read` s limitem).
- Každý krok = **jeden subagent** (`Agent`, `isolation: "worktree"`). **Parametr `model` nezadávej** – zdědí Sonnet 5
  (alias `sonnet` by mohl vést na jiný model).
- Subagent ti vrací **jen krátké shrnutí (max. 25 řádků)**: co je hotové, změněné soubory, nová API, otevřené body,
  výsledek kontroly překladu, hash commitu. Checklist ručních testů zapíše do `docs/testy_M7.md`, ne do odpovědi.
- Když subagent nedoběhne („Minimum“ nesplněno), zadej **nového** subagenta s poznámkou *„pokračuj podle otevřených bodů
  v PROJECT_LOG.md (záznam M7.X)“* – nesnaž se to dodělat sám.
- Mezi vlnami nic nevymýšlej navíc; drž se kroků. Otevřené body zapisuj do logu.

## Nejdřív přečti (nic jiného)
1. `prompts/roadmapa/00_SPOLECNE.md` – pravidla, mapa kódu, registr kláves, **povinná kontrola překladu (kap. 6)**.
2. `prompts/roadmapa/README.md` – oddíl M7 (a „Rozhodnutí, která budou potřeba od uživatele“).
3. Poslední 3 záznamy `PROJECT_LOG.md` (uzavření a závěrečná kontrola M5, kříže a kaplička).

## Rozhodnutí uživatele (platí)
- Klávesa **P = doklady**, panel úkolu na **Z**. Cigarety jen v Potravinách.
- Satira se **smyšlenými** postavami: žádný skutečný starosta, strana, obec, znak, rozpočet ani firma (00_SPOLECNE kap. 3).
- Hra k trestné činnosti nenabádá – nečestné cesty (úplatky, podvody) jsou možné, ale **s rizikem a důsledky** (M4).
- Testuje **uživatel až po celé M7**, nikdy po dílčí vlně (na začátku se jednou zeptej, jestli chce testovat dřív – krok 0).
- Hru ani testy nespouštěj (výjimka: kontrola překladu podle kap. 6).

## Krok 0 – ověř, kde je potřeba uživatel, a vyžádej si to HNED na začátku (povinné, před první vlnou)
Uživatel chce zadat M7 a pak ji nechat běžet bez přerušování. Proto **všechno, co potřebuje jeho odpověď, zjisti a vyžádej si
v první minutě session** – ne až uprostřed vlny, kdy může být pryč.

1. **Najdi body vyžadující uživatele** (jen grep, nečti celé soubory):
   ```bash
   grep -n -iE "zeptej|zeptat|rozhodnutí uživatele|rozhodne uživatel|potřebuje .*uživatel|souřadnic|potvrd|dodá uživatel|ověřit na mapě" \
     prompts/roadmapa/M7_starosta/0[1-4]_*.md
   grep -n -A30 "^## Rozhodnutí, která budou potřeba od uživatele" prompts/roadmapa/README.md
   grep -n -A20 "^## 7. Otevřené otázky pro uživatele" docs/VIZE_A_ROADMAPA.md
   ```
   a v posledních záznamech `PROJECT_LOG.md` oddíly „Otevřené body“, které se týkají M7 (volby, starosta, úřad, kaplička, úkoly,
   popularita, rozpočet obce).
2. **Roztřiď je:** (a) **blokující** – bez odpovědi nejde krok udělat správně (termín voleb, místo, které musí ukázat uživatel na mapě,
   rozsah obsahu); (b) **s rozumným výchozím návrhem** – zeptej se taky, ale nabídni návrh jako první volbu „(doporučeno)“; (c) **technické
   volby**, které umíš rozhodnout sám podle 00_SPOLECNE a kódu – na ty se **neptej**, jen je zapiš do plánu.
3. **Polož všechny otázky (a) a (b) najednou** – jedním `AskUserQuestion` (max. 4 otázky v jednom volání; je-li jich víc, druhé volání hned
   po prvním, nic mezi tím). Vždy obsahuj aspoň tyto, pokud je uživatel už dřív nezodpověděl (ověř v logu / README):
   - **Termín prvních voleb** (M7.1): *první volby po 60 herních dnech, další po 120* (doporučeno) / jiné.
   - **Testování:** až po celé M7 (doporučeno – tak to chce uživatel u milníků) / po každé vlně.
   - **Kaplička (otevřený bod M5.5):** nechat `Krize.chapel_pos()` 225 m od úřadu (doporučeno) / posunout na náves (uživatel dodá souřadnice).
   - **Míra nečestných cest (M7.2):** úplatky, pomluvy a podvody s rizikem odhalení podle promptu (doporučeno) / zmírnit.
4. **Zapiš odpovědi** do plánu i do `PROJECT_LOG.md` (záznam „Start M7 – rozhodnutí uživatele“) a **předávej je subagentům v zadání**
   (oddíl „Rozhodnutí uživatele“ v šabloně), aby se nikdo z nich znovu neptal.
5. Teprve pak předlož plán vln ke schválení (může jít v tomtéž dotazu jako poslední otázka „Plán vln OK?“) a začni.

**Během běhu se už neptej**, s jedinou výjimkou: subagent narazí na skutečný blok, který z odpovědí nejde vyřešit (chybějící data,
rozpor v zadání). Pak nejdřív dokonči vše, co na odpovědi nezávisí, a zeptej se jednou souhrnně. Subagenti se uživatele **neptají nikdy** –
blok vrátí v shrnutí jako otevřený bod a orchestrátor rozhodne.

## Plán vln (navrhni uživateli, uprav jen s odůvodněním)

| Vlna | Kroky | Proč takto | Sdílené soubory – pozor |
|---|---|---|---|
| 1 | **M7.1** Popularita a kritéria | základ: `Reputation.popularity`, `data/volby.json`, záložka „Obec“ – na tom stojí vše ostatní | `reputation.gd`, `hud.gd` (deník), `dialog*.gd`, `save_game.gd` |
| 2 | **M7.2** Kampaň a volby ∥ **M7.3** Vedlejší úkoly s větvením | M7.3 smí souběžně s M7.2 (prompt to říká); M7.2 = kampaň, úplatky, volební den; M7.3 = úkoly jako data `data/ukoly/*.json` | **obě** mění `quests.gd` a `dialog*.gd` → M7.2 do `quests.gd` jen **nové funkce na konec souboru**, M7.3 přestavuje strukturu úkolů; slučuj **M7.3 první**, pak M7.2 (konflikty řeš ve prospěch datové struktury M7.3) |
| 3 | **M7.4** Starostování a konce příběhu | po M7.2 (zvolení) a M7.3 (řetězy postav ovlivňují konec) | `world.gd`, `hud.gd`, `village_events.gd`, `computer.gd` (web obce) |

Pokud M7.3 nestihne převést stávající úkoly do dat, je to v pořádku (prompt to dovoluje) – hlavně ať nerozbije ukládání.

## Zadání pro subagenta (šablona – doplň X a seznam souborů)

> Pracuješ na hře Stone & Clay v izolovaném worktree. **První krok:** `git merge --ff-only main`.
> Přečti `prompts/roadmapa/00_SPOLECNE.md` a proveď `prompts/roadmapa/M7_starosta/0X_….md`.
> Šetři kontext: velké soubory (`world.gd`, `hud.gd`, `quests.gd`, `jobs.gd`) nečti celé – `grep -n` a výřezy.
> **Nesmíš měnit strukturu** těchto sdílených souborů: … (jen přidávat nové funkce / klíče na konec, ne přejmenovávat).
> **Rozhodnutí uživatele (platí, neptej se znovu):** … (vlož odpovědi z kroku 0). Uživatele se **neptej** – když narazíš na blok,
> dokonči, co jde, a blok vrať v odpovědi jako otevřený bod.
> Hru ani testy nespouštěj; povinná je kontrola překladu (00_SPOLECNE kap. 6) – výstup musí být prázdný.
> Na konci: záznam do `PROJECT_LOG.md`, checklist ručních testů (max. 10 bodů) do **vlastního oddílu** `docs/testy_M7.md`,
> README / VIZE / roadmapa README odškrtnout jen při splnění „Hotovo, když“, **commit** ve worktree (česky, styl historie,
> zakončit řádkem `Co-Authored-By` podle systémové připomínky).
> **Odpověď mně (orchestrátorovi): max. 25 řádků** – hotovo / změněné soubory / nová API / otevřené body / výsledek
> kontroly překladu / hash commitu. Nic dalšího.

## Po každé vlně (dělá orchestrátor)
1. Slouč větve do `main` (konflikty v `PROJECT_LOG.md` / `README.md` / `docs/testy_M7.md` = ponech obě části v pořadí kroků).
2. Kontrola překladu nad celým `main` (kap. 6: `godot --import` + `--check-only` na **každý** změněný `.gd` zvlášť). Chyby po sloučení
   oprav malým subagentem („oprav chyby překladu: <výpis>“), ne sám, pokud jde o víc než pár řádků.
3. Commit sloučení. Krátká zpráva uživateli (3–5 řádků): co je ve `main`, co zůstalo otevřené.

## Na konci M7 (povinné)
1. Odškrtni kroky v `prompts/roadmapa/README.md` a `docs/VIZE_A_ROADMAPA.md` (jen splněné), záznam „Uzavření M7“ do `PROJECT_LOG.md`.
2. Dopiš do `docs/testy_M7.md` úvod (pořadí testů, jak se dostat k volbám přes F2 → přeskočit čas).
3. **Vyzvi uživatele, ať přepne model na Opus 5.5** (`/model`) a zadá: *„Proveď závěrečnou kontrolu M7 podle
   `prompts/roadmapa/M7_starosta/00_START_M7.md`, oddíl Závěrečná kontrola.“*
4. Upozorni, že další na řadě je **M8 Realistický svět** (`prompts/roadmapa/M8_realismus/00_START_M8.md`).

---

## Závěrečná kontrola M7 (pro Opus 5.5)
1. Kontrola překladu všech skriptů (`find scripts -name '*.gd'`, postup kap. 6 v 00_SPOLECNE) – výstup prázdný.
2. Code review změn M7: `git diff <commit před M7>..HEAD -- scripts data` – chyby logiky, nekonzistence mezi kroky
   (popularita počítaná na dvou místech, volby bez kandidátů, úkol odkazující na neexistující událost), neexistující volání,
   kolize s nativními členy Node, Variant do `:=`.
3. Každý `data/ukoly/*.json`: kroky míří na existující `emit_game_event` druhy (`grep -rhoE 'emit_game_event\([^,]+, "[a-z_]+"' scripts`),
   odměny na existující komunity / předměty, každá větev má konec.
4. Ukládání: popularita, kandidatura, podpisy, kampaň, volby, úřad starosty a stav úkolů se ukládají i načítají s výchozí hodnotou;
   save z M5 se načte.
5. Právní zásady obsahu (00_SPOLECNE kap. 3) – žádná reálná jména, strany, obce; satira jen na smyšlené postavy.
6. Oprav nalezené chyby, doplň `docs/testy_M7.md`, commit, předej uživateli finální checklist ručních testů.
