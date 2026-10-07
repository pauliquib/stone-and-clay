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

## M7.2 Kampaň a volby: poctivě i nečestně

1. Jít ke dveřím hospody v otevírací době → E → „Mítink kampaně (v sále)“ → vybrat „Poctivě
   slíbit“ u jednoho přání obce → zpráva o potlesku, v deníku „Obec“ nový záznam v „Příběh
   kampaně“ a respekt sousedů stoupl (druhé vyvolání mítinku už toto přání nenabídne).
2. Tamtéž vybrat u jiného přání „Slíbit bez krytí“ → stejný mítink, ale v deníku „Dluh slibů
   bez krytí: 1“ a skrytý klam stoupl (bez viditelné změny respektu).
3. Projít podél cest k 10 různým poštovním schránkám (E u každé) → počítadlo „(n/10 dnes)“
   roste, po 10. zápis do „Příběh kampaně“; druhý den se počítadlo vynuluje.
4. T: „dám ti stovku, když mě budeš volit“ u postavy (mít u sebe aspoň 150 Kč) → postava
   úplatek přijme nebo odmítne podle povahy/nálady; při přijetí −150 Kč a záznam v deníku.
5. T: „novák bere úplatky“ / „nevol nováka“ u postavy → podle důvěryhodnosti klesne vidina
   popularita protikandidáta (deník „Obec“ – stav „vede/zaostává“) a přibude záznam kampaně.
6. Opakovat úplatek/pomluvu víckrát (ideálně u „drbny“ nebo „přísné“ postavy, nebo s nízkou
   karmou) → časem skandál: popup „Skandál!“, pokles pověsti, přestupek v P (doklady) /
   deníku práva, u trestného činu předvolání k soudu (M4.3); po odsouzení zmizí „bez
   odsouzení“ z kritérií kandidatury.
7. Na úřadě v otevírací době → E → „Přimalovat podpis na petici (podvod)“ → počet podpisů
   +1 bez rozhovoru s postavou; opakovat týž den už nejde („už jsi přimaloval“).
8. F2 → přeskočit čas na den voleb (`election_jd` z deníku „Obec“) → otevře se okno
   „Vyhlášení výsledků voleb“ s hlasy hráče a soupeřů a výsledkem (výhra/prohra).
9. Při výhře: v deníku „Obec“ nápis „Jsi starostou/starostkou obce“; při prohře: nový
   termín voleb za 120 dní a nová přání/soupeři v deníku.
10. Uložit (F5) / načíst (F9) → mítinky, dluh slibů, úplatky a „Příběh kampaně“ zůstanou
    stejné; starý save bez klíče `campaign` se načte beze pádu (prázdná kampaň).
