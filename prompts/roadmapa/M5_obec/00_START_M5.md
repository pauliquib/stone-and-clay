# Start M5 – zadání pro novou session (model Sonnet 5)

Zkopíruj do nové session (nejdřív `/model` → Sonnet 5):

---

Pokračujeme na hře Stone & Clay. M4 Zákon a společnost je uzavřená (`d528df2`). Teď (1) dokonči nedokončené části M4
a (2) pusť se do milníku **M5 Obec a volný čas**. Pracuješ jako **orchestrátor**: práci rozplánuješ, necháš si plán
schválit a pak ji zadáváš subagentům ve vlnách tak, aby si nepřekáželi.

**Nejdřív přečti (nic jiného zatím):**
1. `prompts/roadmapa/00_SPOLECNE.md` – pravidla, mapa kódu, registr kláves, **povinná kontrola překladu (kap. 6)**.
2. `prompts/roadmapa/README.md` – oddíly M4 (včetně „Pořadí a souběh“) a M5.
3. Konec `PROJECT_LOG.md` – záznamy M4.9 a závěrečná kontrola M4 (otevřené body).
4. Prompty kroků čti až ve chvíli, kdy krok zadáváš (`prompts/roadmapa/M4_zakon/*.md`, `prompts/roadmapa/M5_obec/*.md`).

**Stav:** M0–M3, M4 (všechny kroky, některé částečně) a M6 hotové. Ruční testy M4 provádí uživatel podle `docs/testy_M4.md`
– výsledky se čekají, nezakládej na nich nic nového, dokud je uživatel nepošle.

**Rozhodnutí uživatele (platí):**
- Klávesa **P = doklady**, panel úkolu na **Z**. Cigarety jen v Potravinách.
- M4.8 návykové látky jen za volbou „Obsah pro dospělé“ (výchozí vypnuto); hra k trestné činnosti nenabádá; žádná glorifikace.
- Nemovitosti jen v domácím katastru; žádné reálné názvy obcí, značek, osob.
- Testuje **uživatel až po celém milníku** (M5 celá), nikdy po dílčí vlně.
- Zahrádkář Ladislav Hrubý (M4.9c) je neutrální postava; žádné stereotypy podle národnosti nebo etnika.

**Krok 1 – dokončení M4 (vlna 0 před M5):**
Zadej subagentům tyto otevřené body, každý ve vlastním worktree (`isolation: "worktree"`), jako první krok `git merge --ff-only main`:
- **M4.4 B zbytek:** zalévání z vodovodu (vodovodní kohoutek u domu jen pokud je malý), hromada klestí jako objekt ve světě.
- **M4.6 zbytek:** hajný zabavuje luk a kuši, pověst −20 a respekt zemědělcům; rybářská stráž podél úseků vody.
- **M4.8 zbytek:** ubalení (akce z papírků z Potravin), jedlá varianta konopí, sběr lysohlávek v lese (sezónní, riziko záměny),
  samostatný přepínač „Efekty obrazu“ ve Nastavení, následky nahlášení u zahrádkáře (pokuta / zabavení).
- **M4 závěrečné:** zákonná čísla v `data/zakon.json` označená NEOVĚŘENO – nech je, jen zkontroluj, že jsou označená.
Pokud některý bod je příliš velký, zapiš ho do PROJECT_LOG jako otevřený a pokračuj dál. Nezavírej M4 na úkor M5.

**Krok 2 – M5 (plán vln, navrhni uživateli, uprav jen s odůvodněním):**
Doporučené pořadí z README: **5.9 → 5.1 → 5.2 → 5.5 → 5.6 → 5.3 → 5.4 → 5.7 → 5.8 → 5.10 → 5.11 → 5.12**.

| Vlna | Kroky souběžně | Pozn. |
|---|---|---|
| 1 | M5.9 Rocková rádia ∥ M5.7 Skateboard | M5.9 má hluk až po M4.4 (hotovo); M5.7 jen M0.3 |
| 2 | M5.1 Stavebniny ∥ M5.12 Osvětlení | M5.1 potřebuje **souřadnice od uživatele** – zeptej se předem |
| 3 | M5.2 Koupaliště ∥ M5.5 Kalendář | M5.2 potřebuje **souřadnice nádrže**; M5.5 mění `clock`/`village_events`, pozor na kolizi |
| 4 | M5.6 Fotbal ∥ M5.3 Hasiči | M5.3 používá požáry (M2.2, M2.3) |
| 5 | M5.4 Hasičský sport | po M5.3 |
| 6 | M5.8 U-rampa | **rozhodnutí uživatele: hotová / stavět** – zeptej se předem |
| 7 | M5.10 Místa v lese ∥ M5.11 Doprava 2 | M5.10 mění `forestry`/`pois`; M5.11 `car.gd`/`traffic.gd`, jiné soubory |

Před vlnou 2, 3 a 6 se zeptej uživatele na chybějící souřadnice / rozhodnutí. Ostatní vlny jdou bez dotazu.

**Jak pracovat se subagenty (stejně jako v M4):**
- Každý subagent v **izolovaném worktree**, první krok `git merge --ff-only main`. Zadání = „Přečti `prompts/roadmapa/00_SPOLECNE.md`
  a proveď `prompts/roadmapa/M5_obec/0X_….md`“ + seznam sdílených souborů, které nesmí měnit, + že checklist vrátí v odpovědi
  a zapíše do `docs/testy_M5.md` (vlastní oddíl).
- **Model subagentů nezadávej** – zdědí Sonnet 5.
- Po každé vlně: slouč větev do `main` (konflikty v `PROJECT_LOG.md` / `README.md` / `docs/testy_*.md` = ponech obě části),
  spusť kontrolu překladu nad celým `main` (kap. 6 v 00_SPOLECNE, `godot --import` + `--check-only` na každý .gd zvlášť), oprav chyby, commitni.
- **Hru ani testy nespouštěj** (kromě kontroly překladu). Neptej se zbytečně – ptej se jen tam, kde krok říká „zeptat se uživatele“.
- Uživatel testuje **až po celé M5** podle `docs/testy_M5.md` (na začátku se zeptej, jestli chce testovat dřív).

**Na konci M5 (povinné):**
1. Odškrtni kroky v `prompts/roadmapa/README.md` a `docs/VIZE_A_ROADMAPA.md`, záznam do `PROJECT_LOG.md`.
2. **Vyzvi uživatele, ať přepne model na Opus 5.5** (`/model`) a zadá: *„Proveď závěrečnou kontrolu M5 podle
   `prompts/roadmapa/M5_obec/00_START_M5.md`, oddíl Závěrečná kontrola.“*

---

## Závěrečná kontrola M5 (pro Opus 5.5)
1. Kontrola překladu všech skriptů (`find scripts -name '*.gd'`, postup kap. 6 v 00_SPOLECNE) – výstup prázdný.
2. Code review změn M5: `git diff <commit před M5>..HEAD -- scripts data` – chyby logiky, nekonzistence mezi kroky,
   neexistující volání, kolize s nativními členy Node, Variant do `:=`.
3. Ukládání: každý nový stav se ukládá i načítá s výchozí hodnotou; starý save se načte (`save_game.gd`).
4. `data/zakon.json` a `data/*.json`: všechny klíče na místě, každé `commit_offense` míří na existující id.
5. Právní zásady obsahu (00_SPOLECNE kap. 3) – žádná reálná jména, značky, obce.
6. Oprav nalezené chyby, doplň `docs/testy_M5.md`, commit, a předej uživateli finální checklist ručních testů.
