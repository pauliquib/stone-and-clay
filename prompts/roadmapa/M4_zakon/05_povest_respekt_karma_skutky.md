# M4.5 – Nové cesty k pověsti, respektu a karmě (dobré skutky)

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 5/6
> Předpoklady: M0.6 (respekt, karma, přátelství), M2.4 (zahrada), M3.2 (odklízení sněhu) · Navazují: M5 (spolky), V2

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 3.5 (seznam „Nové zdroje zlepšení“)
3. `scripts/reputation.gd` (s rozšířením z M0.6 – `EVENT_EFFECTS`, `change_respect`, `change_karma`), `scripts/persona.gd` (`friendship`)
4. `scripts/world.gd` – `give_to_npc` (háček z M0.6), `dialog_context`, `talk`
5. `scripts/dialog.gd` – `TOPICS`, `WORDS` (přidáš témata prosby / pomoci)
6. `scripts/quests.gd` – vzor úkolu (pro malé „prosby“)
7. `scripts/villager.gd` – denní rutina vesničana (kde bydlí / chodí – grep `home|route`)

## 1. Proč
Uživatel: „přidat mnohem více možností, jak si zlepšit pověst, karmu a respekt – pomocí práce na zahradě,
plněním úkolů, slušným chováním, kamarádským přístupem k lidem“. Hráč, který se choval špatně, musí mít
cestu zpět, a hodný hráč musí vidět, že se mu to vyplácí.

## 2. Co udělat
### 2.1 Prosby vesničanů (malé generované úkoly)
- Nový `scripts/favors.gd` (`class_name Favors`): každý herní den 2–4 vesničané mají **prosbu** (ikona „!“ nad hlavou nebo
  zmínka v rozhovoru). Šablony (tabulka `FAVORS`, laditelné):
  - „Pomůžeš mi na zahradě?“ – přijít k jeho domu, zrýt / pořezat / zalít 4 záhony (dočasná zóna z M2.4),
  - „Odhrneš mi sníh?“ (zima – zóna před domem, M3.2 mechanika),
  - „Donesl bys mi nákup?“ – koupit 2–3 věci v Potravinách a donést,
  - „Odvezeš mě k lékaři / do hospody?“ – svézt vesničana autem (sedne si jako spolujezdec – pokud to auto neumí,
    stačí „jede za tebou“ – zapiš do logu),
  - „Pohlídáš mi psa / slepice?“ – nakrmit zvířata souseda 2 dny,
  - „Najdi mi ztracenou věc“ (klíče, peněženka – objekt v okolí, kompas s nepřesností),
  - „Opravíš mi kolo / plot?“ (kutilství).
- Odměna: přátelství +10–20, respekt komunity +2–5, pověst +1–3, karma +1, někdy dárek (jídlo, slivovice, sazenice)
  místo peněz; odmítnutí nic nebere, slib a nesplnění → přátelství −10.
- Prosby jde přijmout v rozhovoru (T: „potřebujete s něčím pomoct?“ – přidej téma do `dialog.gd`) nebo E u vesničana.

### 2.2 Spontánní dobré skutky (bez úkolu)
Detekce ve světě → `EVENT_EFFECTS`:
- **Vrácení nalezené věci:** občas na zemi leží peněženka / klíče (předmět s majitelem-vesničanem) → vrátit (dát) = karma +3,
  přátelství +15; nechat si peníze → karma −3 (a když to zjistí, pověst −5).
- **Doprovod opilého kamaráda domů** (po zábavě / hospodě: vesničan opilý, hráč ho doprovodí – následování jako pomocník z M2.10).
- **Úklid** odpadků i mimo práci (sebrat a hodit do popelnice – popelnice Prop je cíl akce) → karma +0,5 za kus (limit za den).
- **Dárek** (T / E „dát“ – UI pro `give_to_npc`: vyber předmět z inventáře): postava reaguje podle oblíbených věcí
  (`Persona.likes` – přidej: pivo, slivovice, koláč, zelenina, maso…) – přátelství +5–15.
- **Pomoc při nehodě:** zastavit u havarovaného auta AI (pokud se stane) / sraženého chodce → karma +3, pověst +2.
- **Zdravení:** první pozdrav postavě za den (T „dobrý den“) – už je slušnost, drž limit.

### 2.3 Přátelství – zřetelné výhody
- ≥ 40: postava pomůže nést (M2.10), půjčí nářadí, upozorní „policie stojí u kapličky“.
- ≥ 60: nenahlásí drobný přestupek (M4.4), pozve na zabijačku / narozeniny (malá událost doma u postavy – stůl, jídlo).
- ≥ 80: dá klíč od kůlny (úložiště), svěří zvířata, doporučí do práce (M3.1 – snazší přijetí).
Deník J → Vztahy: přátelé s ikonou výhody.

## 3. Hotovo, když
- Každý den jsou dostupné prosby, jdou splnit a odměňují; spontánní skutky fungují; výhody přátelství jsou vidět.

## 4. Návrh checklistu ručních testů
1. Ráno projdi obec → 2–4 vesničané mají prosbu; T „potřebujete pomoct?“ → přijmout.
2. Splň „zahrada“ a „nákup“ → přátelství, respekt, dárek.
3. Nesplň slíbené → přátelství dolů.
4. Najdi peněženku → vrať → karma nahoru; nech si ji jindy → karma dolů.
5. Dárek (slivovice) oblíbené postavě → velké plus.
6. Přátelství 60 → postava tě varuje před policií; nenahlásí drobnost.
7. F5/F9 → prosby a přátelství zůstanou.

## 5. Závěr
README, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M4.5 Dobré skutky a přátelství: …“, checklist a čekat.
