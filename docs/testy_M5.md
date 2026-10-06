# Ruční testy – M5 (Obec a volný čas)

Každý krok má vlastní oddíl. Testuje uživatel po dokončení vlny; agent hru nespouští.

## M5.7 Skateboard

1. F2 → Hráč → přidat „skateboard“ do inventáře (případně e-shop / stavebniny až po napojení).
2. Stiskni F na volném místě → hláška „Stoupl jsi na skateboard…“. Hráč stojí na desce, deska je vidět pod nohama.
3. W = odraz (rychlost roste po krocích), S = brzda patou, A/D = zatáčení; zastaví se bez vstupu.
4. Jedeš z kopce u silnice → rychlost roste; nad ~12 m/s deska kmitá, nad ~15 m/s pád.
5. Najeď do zdi nebo obrubníku rychleji než ~3 m/s → pád, hráč leží.
6. Na trávě nebo mokru (déšť) při rychlosti přes ~2,5 m/s → přepadneš dopředu.
7. Mezerník na rovině (rychlost pod 2 m/s nebo i za jízdy) → ollie; dopad rovně přidá +10 bodů (zatím jen v logu / signálu, HUD ještě ne).
8. F při rychlosti pod 2 m/s → seskok; při vyšší rychlosti hláška „Nejdřív zpomal“.
9. Ulož (F5), ukonči hru, načti (F9) → rekord zůstane, skateboard zůstane v inventáři, hráč jde pěšky.
10. Starý save (před M5.7) se musí načíst bez chyby a rekord bude 0.
