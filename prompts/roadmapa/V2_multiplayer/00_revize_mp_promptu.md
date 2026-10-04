# V2.00 – Revize starých multiplayerových promptů podle etapy 1

> Verze 2 · **Multiplayer** · krok 0 (plánovací – mění jen dokumenty, ne kód)
> Předpoklady: dokončené M0–M6 (nebo aspoň M0–M4) · Navazují: `prompts/03–10`, `priroda/05`, V2.01–V2.05

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` a `prompts/roadmapa/V2_multiplayer/README.md`
2. `GAME_DESIGN.md` – kap. 6 (Multiplayer: architektura, autorita, provoz)
3. `prompts/README.md` a **všechny** `prompts/03_…10_*.md` (každý ~50 ř.) + `prompts/priroda/05_*.md`
4. `docs/VIZE_A_ROADMAPA.md` – stav odškrtnutí M0–M6
5. `PROJECT_LOG.md` – záznamy M0.1 až M6.5 (jen nadpisy a „Otevřené body“ – `grep -n "^## " PROJECT_LOG.md`, pak čti vybrané)
6. `README.md` → „Architektura (příprava na multiplayer)“

## 1. Proč
MP prompty 03–10 vznikly **před** etapou 1. Od té doby přibyly systémy, které musí být v síti (dovednosti,
jednotný inventář, akce, zákon, doklady, práce, měnitelný svět, zvířata, stavby, interiéry, vozidla, létání…),
a změnily se detaily (domov hráče je nemovitost z registru `Estate` se smyšleným č. p., ne pevný dům). Než se začne programovat síť, je potřeba prompty
zaktualizovat, aby agent v novém okně nepracoval podle zastaralého zadání.

## 2. Co udělat (jen dokumenty)
1. V každém z `prompts/03–10` a `priroda/05`:
   - oprav zmínky o pevném domu hráče → domov přes `Estate` (smyšlené č. p., `Estate.home_label(id)`),
   - doplň odstavec „**Nové od etapy 1**“: které nové systémy spadají do rozsahu toho promptu (např. `07` předměty →
     jednotný `ItemsDB`, nosnost, opotřebení nástrojů, oblečení; `08` úkoly → prosby vesničanů, práce; `09` ukládání →
     `Skills`, `Law`, `Permits`, `Jobs`, respekt, karma, přátelství, stavby, stromy, zahrady, zvířata),
   - odkaz na `prompts/roadmapa/00_SPOLECNE.md` jako zdroj pravidel (ať se neduplikují),
   - zkontroluj, že pravidla testování odpovídají `CLAUDE.md` (agent nic nespouští).
2. Přečísluj / označ je v `prompts/README.md` jako **verze 2** (tabulka s odkazem na `roadmapa/V2_multiplayer/README.md`)
   – soubory **nepřejmenovávej** (odkazy v logu), jen uprav texty a tabulku.
3. V `GAME_DESIGN.md` kap. 6.3 doplň řádky tabulky autority pro nové objekty (stromy, záhony, zvířata ve výbězích, ohně,
   stavby, náklad a vozík, zbraně a projektily, drony a letadla, doklady a rejstřík, práce).
4. V `roadmapa/V2_multiplayer/README.md` uprav doporučené pořadí, pokud při revizi zjistíš jiné závislosti.
5. Seznam **rizik** (do logu): co z etapy 1 porušuje MP architekturu (přímé volání HUD ze světa, globální singletony bez `id`,
   logika v `LocalClient`, která patří do `World`) – s odkazem na soubor a řádek (grep). To opraví V2.01–V2.05.

## 3. Hotovo, když
- Staré MP prompty odpovídají stavu hry po etapě 1, tabulka autority v GDD je úplná, rizika jsou sepsaná.

## 4. Checklist pro uživatele (kontrola dokumentů – nic se nespouští)
1. `prompts/README.md` → řada 03–10 označená jako verze 2 s odkazem na V2.
2. Otevři `prompts/07_…` → odstavec „Nové od etapy 1“ dává smysl.
3. `GAME_DESIGN.md` kap. 6.3 → nové řádky.
4. `PROJECT_LOG.md` → seznam rizik s odkazy na soubory.

## 5. Závěr
PROJECT_LOG, deník AI, commit „V2.00 Revize MP promptů po etapě 1“, checklist a čekat.
