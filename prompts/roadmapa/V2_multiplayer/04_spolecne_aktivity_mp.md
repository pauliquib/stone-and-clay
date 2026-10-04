# V2.04 – Společné aktivity: nesení ve dvou, fotbal, požární útok, zábava, lety, obchod mezi hráči

> Verze 2 · **Multiplayer** · krok 4
> Předpoklady: V2.01–V2.03, `prompts/08` (party, chat, emoty) · Navazují: V2.05

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`, `V2_multiplayer/README.md`, `GAME_DESIGN.md` kap. 6
2. `scripts/cargo.gd` (nesení ve dvou – NPC partner), fotbal (M5.6 – míč, zápas), hasičský sport (M5.4 – role), události a zábava
   (M5.5 – tanec, tombola), trike (M6.5 – spolujezdec), party a chat z úkolu 08

## 1. Cíl
To, co v singleplayeru dělá NPC „jako partner“, může v MP dělat **druhý hráč**. Hra je navržená pro kamarády
(„Spolu je to lepší“ – pilíř GDD).

## 2. Co udělat
1. **Nesení ve dvou** (divočák): druhý hráč místo NPC – request „pomoz nést“ → oba drží, pohyb určuje ten vpředu,
   druhý jen následuje (nebo se vzájemně „táhnou“ – jednoduše: rychlost = min obou, směr = průměr vstupů). Pusť = náklad spadne.
2. **Fotbal:** míč autorita server (nebo hráč nejblíž míči – „vlastnictví míče“ s předáváním – vyber a zdůvodni v GDD),
   hráči v týmech proti sobě i s NPC doplněním; skóre, rozhodčí.
3. **Požární útok:** hráči obsadí role (lobby u velitele), NPC doplní zbytek; časování na serveru; soutěž družstev hráčů proti sobě.
4. **Zábava:** tanec v páru s hráčem (vyzvat – přijmout), tombola (losy per hráč), rvačky mezi hráči? – jen „strkání“ bez zranění
   + policie (vytržnictví) – rozhodni a zapiš.
5. **Lety ve dvou:** trike (M6.5) a UL – druhý hráč jako spolujezdec (nastoupí zezadu), pohled pasažéra; paramotor ne (jednomístný).
   Tandem paraglide – volitelně.
6. **Obchod mezi hráči:** nabídka „prodat hráči“ (předmět + cena → druhý potvrdí) – navazuje na předávání z úkolu 07; zvířata,
   vozidla (přepis vlastnictví), zvěřina (s dokladem / bez – pytláctví se přenáší na kupujícího, pokud ví).
7. **Společné prosby a práce:** prosba vesničana pro 2 hráče (větší zahrada, stěhování), bonus za spolupráci.

## 3. Hotovo, když
- Divočáka jde nést ve dvou hráčích, fotbal a požární útok jdou hrát hráči proti sobě / spolu, na zábavě jde tančit s hráčem,
  trike uveze druhého hráče, hráči si mohou prodávat věci.

## 4. Návrh checklistu (2 klienti)
1. A a B nesou divočáka → pomalý společný pohyb; B pustí → spadne.
2. Fotbal A vs. B + NPC → skóre shodné u obou.
3. Požární útok: A strojník, B proudař → čas.
4. Zábava: A vyzve B k tanci → oba tančí.
5. Trike: A pilot, B spolujezdec → let, přistání.
6. A prodá B sekeru za 500 Kč → peníze a sekera se přesunou.

## 5. Závěr
GDD kap. 6, README, PROJECT_LOG, deník AI, commit „V2.04 Společné aktivity v MP: …“, checklist a čekat.
