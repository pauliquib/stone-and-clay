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
