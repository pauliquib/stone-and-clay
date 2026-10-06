# Start M4 – zadání pro novou session (model Sonnet 5)

Zkopíruj do nové session (nejdřív `/model` → Sonnet 5):

---

Pokračujeme na hře Stone & Clay milníkem **M4 Zákon a společnost**. Pracuješ jako **orchestrátor**: práci rozplánuješ,
necháš si plán schválit a pak ji zadáváš subagentům ve vlnách tak, aby si nepřekáželi.

**Nejdřív přečti (nic jiného zatím):**
1. `prompts/roadmapa/00_SPOLECNE.md` – pravidla, mapa kódu, registr kláves, **povinná kontrola překladu (kap. 6)**.
2. `prompts/roadmapa/README.md` – oddíl M4 včetně „Pořadí a souběh M4“.
3. Konec `PROJECT_LOG.md` (vlna 0 – stabilizace, vše otestováno uživatelem 6. 10. 2026).
4. Prompty kroků čti až ve chvíli, kdy krok zadáváš: `prompts/roadmapa/M4_zakon/01–08*.md`.

**Stav:** M0–M3 a M6 hotové, vlna 0 (oprava mapy, létání, dopravy, hráče, NPC) hotová a otestovaná.
Prompty M4 jsou sladěné se skutečným kódem (commit 33aea43). Rozhodnutí uživatele: klávesa **P = doklady**
(panel úkolu je na Z), cigarety jen v Potravinách, M4.8 návykové látky jen za volbou „Obsah pro dospělé“
(výchozí vypnuto, hra k trestné činnosti nenabádá), nemovitosti (M4.7) jen v domácím katastru, nikdy reálné
názvy obcí / značek.

**Plán vln (navrhni uživateli, uprav jen s odůvodněním):**
| Vlna | Kroky souběžně | Pozn. |
|---|---|---|
| 1 | M4.1 Řidičák a autoškola ∥ M4.5 Dobré skutky | M4.5 má vlastní `favors.gd` |
| 2 | M4.2 Správní řízení (zavádí `Debts`) | sám – přepisuje `Law.commit` a save klíč `law` |
| 3 | M4.3 Soud a vězení ∥ M4.4 část A (svědci, `witness_check`) | pozor na `world.gd`, `zakon.json` – slučuj ručně |
| 4 | M4.4 část B (vyhlášky: pálení, sucho, hluk) | |
| 5 | M4.6 Zbraně, lov, rybolov ∥ M4.7 Katastr | M4.7 po M4.4 kvůli `forestry.zone_at` |
| 6 | M4.8 Návykové látky | až po commitu M4.6 (sdílí `zakon.json`, `police.gd`) |

**Jak pracovat se subagenty:**
- Každý subagent v **izolovaném worktree** (`isolation: "worktree"`); jako první krok `git merge --ff-only main`
  (worktree může vzniknout ze starého commitu). Zadání = „Přečti `prompts/roadmapa/00_SPOLECNE.md` a proveď
  `prompts/roadmapa/M4_zakon/0X_….md`“ + co nesmí měnit (soubory souběžného agenta) + že checklist testů vrátí
  v odpovědi a zapíše do `docs/testy_M4.md` (vlastní oddíl).
- **Model subagentů nezadávej** – zdědí model této session (Sonnet 5). Parametr `model: "sonnet"` by mohl vybrat
  dražší verzi.
- Po dokončení: slouč větev do `main` (konflikty v `PROJECT_LOG.md` / `README.md` = ponech obě části),
  spusť kontrolu překladu (kap. 6 v 00_SPOLECNE) nad sloučeným `main`, oprav případné chyby, commitni.
- Hru ani testy nespouštěj (jen kontrola překladu). Neptej se zbytečně – ptej se jen na rozhodnutí, která
  prompt označuje jako „zeptat se uživatele“.
- Uživatel testuje **až po celé M4** podle `docs/testy_M4.md` (na začátku se ho zeptej, jestli nechce
  testovat dřív, např. po vlně 2).

**Na konci M4 (povinné):**
1. Odškrtni kroky v `prompts/roadmapa/README.md` a `docs/VIZE_A_ROADMAPA.md`, záznam do `PROJECT_LOG.md`.
2. **Vyzvi uživatele, ať přepne model na Opus 5.5** (`/model`) a zadá: *„Proveď závěrečnou kontrolu M4 podle
   `prompts/roadmapa/M4_zakon/00_START_M4.md`, oddíl Závěrečná kontrola.“*

---

## Závěrečná kontrola (pro Opus 5.5)
1. Kontrola překladu všech skriptů (`find scripts -name '*.gd'`, postup kap. 6 v 00_SPOLECNE) – výstup prázdný.
2. Code review změn M4: `git diff <commit před M4>..HEAD -- scripts data` (commit před M4 = `23deab2` nebo novější
   commit „Start M4“) – chyby logiky, nekonzistence mezi kroky (Permits, Law, Debts, witness_check, zakon.json),
   neexistující volání, kolize s nativními členy Node, Variant do `:=`.
3. Ukládání: každý nový stav se ukládá i načítá s výchozí hodnotou; starý save (před M4) se načte – projdi `save_game.gd`.
4. `data/zakon.json`: každý řádek má `nazev, zakon, par, pokuta, misto, trestny_cin, poznamka, drb, karma`;
   každé `commit_offense("…")` míří na existující id.
5. Právní zásady obsahu (00_SPOLECNE kap. 3) – žádná reálná jména, značky, obce; M4.8 jen za volbou pro dospělé.
6. Oprav nalezené chyby, doplň `docs/testy_M4.md`, commit, a předej uživateli finální checklist ručních testů.
