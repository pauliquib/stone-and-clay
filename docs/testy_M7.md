# Ruční testy M7 – Cesta na starostu

> Testuje uživatel až po celém M7 (M7.1–M7.4), ne po jednotlivých krocích. Tento soubor sbírá
> checklisty podle kroků; každý krok má vlastní oddíl.

## M7.1 Popularita a kritéria kandidatury

1. Nová hra → J (deník) → oddíl „Obec“: popularita nízká / „o tvé kandidatuře zatím neví vůbec
   nikdo“, kritéria (trvalý pobyt splněno, bez odsouzení splněno, podpisy 0/15), datum voleb
   a odpočet dní, 3 přání obce.
2. Splnit úkol pro hasiče (zadavatel `giver` = hasiči) → v deníku roste respekt hasičů i popularita
   (malý, ale viditelný posun).
3. Urazit postavu (T: „jsi debil“) → pověst i popularita klesnou (víc u komunity té postavy).
4. Rozhovor (T): „podepíšeš mi petici?“ nebo „kandiduji na starostu“ → kamarádská / neutrální
   postava podepíše (počet podpisů v deníku +1), postava s nízkou vřelostí odmítne; stejná postava
   podruhé už jen „podpis už jsi dostal“.
5. Rozhovor: „co si myslíš o starostovi?“ / zmínka „starosta“, „volby“, „zastupitelstvo“ → odpověď
   podle povahy postavy (téma „politics“).
6. F2 → přeskočit čas na pár dní před volby (60/30/14/7/1 dní) → každé z těchto dní popup
   „Do komunálních voleb zbývá N dní.“
7. F2 → přeskočit čas za datum voleb → v deníku se termín posune o další funkční období
   (1 461 dní), popularita protikandidáta se mezitím pomalu měnila.
8. Uložit (F5) / načíst (F9) → popularita, podpisy petice a termín voleb zůstanou stejné.
9. Starý save bez `politics` (ze staršího milníku) se dá načíst beze pádu – nová kandidatura se
   založí s výchozím termínem a 0 podpisy.
10. `godot --headless --check-only` na změněné skripty bez chyby (ověřeno orchestrátorem/agentem
    před commitem – informační bod, ne akce pro uživatele).

## M7.3 Vedlejší úkoly s větvením

> Nová datová struktura úkolů: `data/ukoly/*.json` + engine `scripts/quest_data.gd` (`QuestData`,
> `DataQuest extends Quests.Quest`). Formát souboru (klíče, typy kroků `near`/`item`/`event`/`talk`,
> větve `branches` s `reward`/`risk`) je podrobně popsaný v komentáři nahoře v `scripts/quest_data.gd`
> a stručně i v `scripts/quests.gd`. `Quests.setup()` je načte automaticky do `list` vedle starých
> (ručně psaných) úkolů – obojí má stejné rozhraní `Quest` i ukládání (`save_game.gd`, klíč `id`/`state`,
> beze změny). Nový úkol = nový `.json` v `data/ukoly/`, žádný jiný soubor se nemusí měnit.
> 10 nových úkolů (2 konce každý): `pes_ztraceny`, `pytlak_v_lese`, `strikacka`, `drevo_babicka`,
> `mez_sousede`, `kaplicka_sbirka`, `sud_vinar`, `klesti_hromada`, `motorka_stodola`, `krava_na_silnici`.

1. Nová hra, 0.–2. herní den → dojdi postupně k dědovi, myslivecké chatě, Potravinám, pile, úřadu,
   vinnému sklepu – u každého se v nabídce (E) objeví aspoň jeden nový úkol (★ Úkol: …), u některých
   i přes rozhovor (T → „potřebuješ pomoct?“ → zmíní, že někdo shání pomoc).
2. „Ztracený pes“ (děda) → dojdi na vyznačené místo u chaty → u dědy zvol „Vrátit Punťu“ → deník:
   splněno, text větve, přátelství s dědou a respekt sousedů stoupl (J → Obec/popularita se mírně
   zvedla), karma (slovně v nápovědi/testu) kladná.
3. Stejný úkol znovu (nová hra) → zvol „Nechat si Punťu sám“ → karma klesne; při smůle (cca 50 %)
   navíc popup o drbech a pád respektu sousedů – over více pokusů (nová hra pro reset) ověř, že
   nastane aspoň jednou.
4. „Pytlák v lese“ (myslivecká chata) → „Řekni Frantovi vše“ vs. „Mlč“ → rozdílný text, u udání
   stoupne respekt zemědělců/myslivců, u krytí může přijít dodatečný postih.
5. „Sbírka na kapličku“ (úřad) → zvol „Nechat si část peněz“ → peníze hráče stouply o 800 Kč, karma
   klesla; při odhalení (risk) navíc pád respektu a pověsti s textem o podezření.
6. „Dříví pro paní Hronovou“ (pila) se nabídne až po získání aspoň trochu kladné karmy (dřív jiným
   úkolem) – ověř, že na úplném začátku hry (karma 0) v nabídce pily ještě není, po pár poctivých
   úkolech se objeví.
7. „Motorka ve stodole“ (Stavebniny) se naopak nenabídne, pokud má hráč už vysokou karmu (over 30) –
   ověř opačně, že se brzy po začátku (karma ~0) nabízí.
8. Deník (J) → oddíl úkolů: u dokončených/nezdařených je vidět název a jedna věta s výsledkem/větví.
9. Uložit (F5) uprostřed rozdělaného datového úkolu / načíst (F9) → úkol se vrátí do nabídky
   (stejné chování jako staré úkoly – rozdělaný se při načtení resetuje na „available“, bez pádu).
10. `godot --headless --check-only` na `scripts/quests.gd` a `scripts/quest_data.gd` bez chyby
    (ověřeno před commitem – informační bod).
