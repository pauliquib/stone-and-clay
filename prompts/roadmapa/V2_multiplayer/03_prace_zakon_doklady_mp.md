# V2.03 – Práce, zákon, doklady, stráže, soud a vězení v multiplayeru

> Verze 2 · **Multiplayer** · krok 3
> Předpoklady: V2.01, `prompts/06` (policie na serveru), `prompts/08` (úkoly per hráč), `prompts/09` (reputace) · Navazují: V2.04

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`, `V2_multiplayer/README.md`, `GAME_DESIGN.md` kap. 6
2. `scripts/law.gd`, `scripts/permits.gd`, `scripts/jobs.gd`, `scripts/favors.gd`, `scripts/reputation.gd` (respekt, karma, přátelství),
   `scripts/gamekeeper.gd` (hajný, rybářská stráž), `witness_check` ve `world.gd`, soud a vězení (M4.3 – grep `prison|soud`)
3. `scripts/police.gd` po úkolu 06 (jak policie vybírá hráče)

## 1. Cíl
Zákon, práce a společenské vztahy jsou **per hráč** a fungují, když je ve světě víc hráčů – včetně toho, že
hráči jsou si navzájem **svědky**, a vězení jednoho hráče nezastaví svět ostatním.

## 2. Co udělat
1. **Per hráč na serveru:** `Law`, `Permits`, `Jobs`, respekt, karma, přátelství postav (Persona si pamatuje každého hráče
   zvlášť – ověř, že to tak je od úkolu 02), prosby (každý hráč vidí svoje + „společné“ prosby, které si může vzít kdokoli).
2. **Svědci:** `witness_check` zahrne **ostatní hráče** jako svědky – hráč-svědek dostane nabídku „Nahlásit / Mlčet“ (UI),
   rozhodnutí ovlivní jeho karmu a vztah s pachatelem (malý systém „reputace mezi hráči“ – volitelné, jen do GDD).
3. **Stráže a policie:** vybírají cíl mezi hráči (nejbližší podezřelý), kontrola dokladů konkrétního hráče.
4. **Soud a vězení:** čas světa **nelze přeskočit** kvůli jednomu hráči → vězení v MP = hráč je přesunut do „cely“
   (interiér) na **reálný** čas (zkrácený – např. 1 herní den = 2 min reálně; konstanta), může se odpojit a trest mu běží dál
   (odpočet v profilu); následky (práce, zvířata) se vyhodnotí stejně, ale zvířata mohou krmit ostatní hráči (karma +).
   Soudní jednání: jen obžalovaný (a jako „svědci“ volitelně další hráči – humor).
5. **Práce:** víc hráčů může mít stejnou práci (směna s kolegou – úkoly se dělí); výplata per hráč.
6. **Spánek a skok času** (úkol 07/09 to možná řeší hlasováním) – ověř, že spánek jednoho hráče neposouvá čas ostatním
   (a jak se tedy počítají lhůty pokut, růst plodin – server čas běží normálně).

## 3. Hotovo, když
- Každý hráč má vlastní rejstřík, doklady, práci a vztahy; hráči jsou svědci; stráže a policie řeší správného hráče;
  vězení funguje bez zastavení světa.

## 4. Návrh checklistu (2 klienti)
1. A kácí v lese, B stojí vedle → B dostane „Nahlásit / Mlčet“.
2. A pytlačí, hajný kontroluje A, ne B.
3. A je ve vězení → B hraje dál, A je v cele, odpočet běží.
4. A i B mají práci na farmě → směna spolu, výplata každému.
5. A je u postavy přítel, B ne → postava je k A vřelejší.
6. B uloží profil a připojí se k jinému hostovi → doklady a rejstřík s sebou (profil), svět ne.

## 5. Závěr
GDD kap. 6, README, PROJECT_LOG, commit „V2.03 Práce a zákon v MP: …“, checklist a čekat.
