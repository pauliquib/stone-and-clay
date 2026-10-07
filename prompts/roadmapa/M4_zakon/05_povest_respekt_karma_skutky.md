# M4.5 – Nové cesty k pověsti, respektu a karmě (dobré skutky)

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 5/8
> Předpoklady: M0.6 (respekt, karma, přátelství), M2.4 (zahrada), M3.2 (odklízení sněhu) · doporučeno po M4.4
> (`witness_check` – výhoda „přítel nenahlásí“)
> Navazují: M5.11 (NPC nastupují do aut – prosba „odvezeš mě“ naplno), M5 (spolky), M7.1 (popularita), V2
> Stav kódu ověřen po vlně 0 (commit `357f7eb`). Když grep ukáže něco jiného, věř kódu a rozdíl zapiš do logu.
> **Lze dělat souběžně s M4.1–M4.3** (jiné soubory) – viz README roadmapy.

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 3.5 (seznam „Nové zdroje zlepšení“)
3. `scripts/reputation.gd` (`EVENT_EFFECTS`, `change_respect`, `change_karma`, `on_event`), `scripts/persona.gd` (celý, ~130 ř.)
4. `scripts/world.gd` – výřezy: `give_to_npc` (~ř. 2786), `dialog_context` (~2571), `talk` (~2490), `_spawn_bots` (~816)
5. `scripts/dialog.gd` – `TOPICS`, `WORDS`; `scripts/dialog_themes.gd` (vzor tématu s `ask`)
6. `scripts/quests.gd` – vzor úkolu, `place_options`; `scripts/jobs.gd` – zakázky zahradníka (`set_contract_maker`,
   `Estate.pick_customer_house`) – **vzor dočasné zóny u cizího domu**
7. `scripts/villager.gd` – `BT_VILLAGERS`, `_home_pos` (~ř. 195, dům z `Estate.pick_customer_house(_seed)`), `_garden_pos`

## 1. Proč
Uživatel: „přidat mnohem více možností, jak si zlepšit pověst, karmu a respekt – pomocí práce na zahradě, plněním úkolů,
slušným chováním, kamarádským přístupem k lidem“. Hráč, který se choval špatně, musí mít cestu zpět, a hodný hráč musí
vidět, že se mu to vyplácí.

## 2. Co už v kódu je
- `Persona`: `profile` (name, trait, job, hobby, topics, age, female, role, place), `friendship[id]` 0..100,
  `get_friendship`, `add_friendship(id, d, now, day, gift)`, `FRIEND_GIFT`, `FRIEND_HIGH` 60. **`Persona.likes` neexistuje.**
- `World.give_to_npc(id, npc, item_id)` – dárek: přátelství podle ceny, karma +0,5, událost `gift_given`. Chybí UI výběru.
- **`Favors` neexistuje** (nový soubor). `class_name Favors` ověř grepem, že nekoliduje.
- **BT rutiny (LimboAI) má jen prvních `BT_VILLAGERS` = 5 vesničanů** (víc kvůli výkonu nezvyšovat – audit A4-04).
  Ostatních 23 z 28 chodí po starém. Domov každého vesničana jde spočítat stejně jako `_home_pos`
  (`Estate.pick_customer_house(seed, 700)`) – prosby proto **nesmí** záviset na BT (cíl = dům / místo, ne rutina).
- Auta nemají místo spolujezdce (spolujezdec je jen u triku – `Trike._pax_vis`).

## 3. Co udělat
### 3.1 Prosby vesničanů (malé generované úkoly) – `scripts/favors.gd` (`class_name Favors`, jedna instance `World.favors`)
- Každý herní den 2–4 vesničané (ze všech 28, nejen BT) mají **prosbu** (ikona „!“ nad hlavou zblízka nebo zmínka v
  rozhovoru). Šablony v tabulce `FAVORS` (laditelné):
  - „Pomůžeš mi na zahradě?“ – u jeho domu dočasná zóna záhonů (vzor zakázek zahradníka M3.3), zrýt / pořezat / zalít,
  - „Odhrneš mi sníh?“ (zima – zóna před domem, mechanika z M3.2),
  - „Donesl bys mi nákup?“ – koupit 2–3 věci v Potravinách a donést (dát přes `give_to_npc` / E u dveří),
  - „Odvezeš mě k lékaři / do hospody?“ – zjednodušeně: vesničan „nastoupí“ (zmizí u auta, objeví se v cíli, když tam
    hráč dojede autem do X minut); skutečné sezení v autě přinese **M5.11** – zapiš háček,
  - „Pohlídáš mi psa / slepice?“ – nakrmit zvířata souseda 2 dny,
  - „Najdi mi ztracenou věc“ (klíče, peněženka – předmět v okolí, kompas s nepřesností),
  - „Opravíš mi kolo / plot?“ (kutilství).
- Odměna: přátelství +10–20, respekt komunity +2–5, pověst +1–3, karma +1, někdy dárek (jídlo, slivovice, sazenice) místo
  peněz; odmítnutí nic nebere, slib a nesplnění → přátelství −10. Ukládání (klíč `favors`).
- Přijetí: rozhovor (T: „potřebujete s něčím pomoct?“ – nové téma v `dialog_themes.gd` / `dialog.gd`) nebo E u vesničana.
  Deník J → Prosby.

### 3.2 Spontánní dobré skutky (bez úkolu) → `Reputation.EVENT_EFFECTS`
- **Vrácení nalezené věci:** občas na zemi leží peněženka / klíče (předmět s majitelem-vesničanem) → vrátit = karma +3,
  přátelství +15; nechat si peníze → karma −3 (a když to vyjde najevo, pověst −5).
- **Doprovod opilého kamaráda domů** (po hospodě / zábavě – následování jako pomocník z M2.10).
- **Úklid** odpadků i mimo práci (sebrat a hodit do popelnice – `Prop` popelnice jako cíl akce) → karma +0,5 za kus (limit za den).
- **Dárek s UI:** T / E „dát“ → výběr předmětu z inventáře → `give_to_npc`. Přidej **`Persona.likes`** (seznam id předmětů
  odvozený deterministicky z `trait` / `hobby` / `job` – pivo, slivovice, koláč, zelenina, maso…, ukládat netřeba)
  a `dislikes`; oblíbené ×2 přátelství, neoblíbené mírné mínus.
- **Pomoc při nehodě:** zastavit u havarovaného auta AI / sraženého chodce → karma +3, pověst +2.
- **Zdravení:** první pozdrav za den – už je (slušnost), drž limit.

### 3.3 Přátelství – zřetelné výhody
- ≥ 40: postava pomůže nést (M2.10), půjčí nářadí, upozorní „policie stojí u kapličky“ (když stojí kontrola – `Police.set_checkpoint`).
- ≥ 60: **nenahlásí drobný přestupek** (`witness_check` z M4.4 – pokud M4.4 ještě není, napoj na `Forestry.witness_near`
  a zapiš háček), pozve na zabijačku / narozeniny (malá událost doma u postavy).
- ≥ 80: dá klíč od kůlny (úložiště), svěří zvířata, doporučí do práce (M3.1 – snazší přijetí, `Jobs.can_apply` bonus).
Deník J → Vztahy: přátelé s ikonou výhody.

## 4. Minimum
`Favors` se 4 šablonami (zahrada, nákup, sníh, ztracená věc) pro všech 28 vesničanů, přijetí rozhovorem, odměny, ukládání;
dárek s UI a `likes`; výhody přátelství ≥ 40 / ≥ 60.

## 5. Hotovo, když
- Každý den jsou dostupné prosby (i od vesničanů bez BT), jdou splnit a odměňují; spontánní skutky fungují; výhody
  přátelství jsou vidět.

## 6. Návrh checklistu ručních testů
1. Ráno projdi obec → 2–4 vesničané mají prosbu (aspoň jeden mimo prvních 5); T „potřebujete pomoct?“ → přijmout.
2. Splň „zahrada“ a „nákup“ → přátelství, respekt, dárek.
3. Nesplň slíbené → přátelství dolů.
4. Najdi peněženku → vrať → karma nahoru; nech si ji jindy → karma dolů.
5. Dárek oblíbené věci → velké plus; neoblíbené → malé mínus.
6. Přátelství 60 → postava tě varuje před policií; nenahlásí drobnost.
7. F5/F9 → prosby a přátelství zůstanou.

## 7. Závěr
README, VIZE odškrtnout, roadmapa README, PROJECT_LOG, commit „M4.5 Dobré skutky a přátelství: …“, checklist a čekat.
