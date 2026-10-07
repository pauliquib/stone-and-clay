# Checklist ručních testů – vlna 0 (stabilizace před M4)

> `./run.sh` (obnoví seznam tříd). Výsledky pošli ve tvaru „F1.2 OK, F4.3 chyba: …“.
> Podrobnosti oprav: `docs/audit_vlna0.md` a `PROJECT_LOG.md` (sekce Vlna 0b, 0d F1–F5).

## 0b – Dohled mapy
1. F2 → Teleport → Okolní obce (> 2 km od domu): budovy, silnice a cesty jsou vidět a pevné.
2. Otoč kamerou: domy do ~1–1,5 km vidět, dál plynule mizí, nic nebliká.
3. Esc → Nastavení → Dohlednost „Krátká“ / „Velmi daleká“: dosah se mění všude, ne jen u spawnu.
4. Dlouhý potok daleko od středu mapy: hladina je vidět. V zimě se sněhem: stopy za hráčem.

## F1 – Létání M6
1. F2 → Teleport → Letiště, F2 → Vozidla → Testovací letoun: kola na trávě, pilot kouká dopředu. Drž W: odlepení ~40 km/h, za 10 s výš než 20 m. Bez plynu klesání ~1:9.
2. Motorové rogalo (trike): rogalo s trubkami a prohnutím (vidět i zespodu). Shift plyn, odlepení ~70 km/h. Ve vzduchu W nahoru, A doleva; Esc → Nastavení „Realistické řízení rogala“ obrátí.
3. Paramotor: křídlo leží naplocho za pilotem, pilot stojí na zemi; Shift na začátku jen varuje. Proti větru W: křídlo se zvedne, pilot běží; Shift → odlepení ~32 km/h, pilot sedí.
4. Přistání se staženým plynem bez poskakování; F → pilot stojí vedle stroje rovně (bez pózy z auta).
5. Spolujezdec (kamarád, přátelství ≥ 60, E u triku): je vidět na zadním sedadle, po přistání vystoupí.
6. Let za okraj mapy: žádná neviditelná zeď, AGL sedí nad krajinou, u hranice (2 km) protivítr.

## F2 – Doprava
1. `--pos=259,241` (pravoúhlá zatáčka), `--pos=19,-28`, `--pos=172,508`: AI auta zpomalí, neseříznou zatáčku přes zahradu, nekrouží ani necouvají.
2. `--pos=3319,-851` a `--pos=4033,-3181`: dům, který zasahoval do silnice, zmizel; auta projíždějí.
3. `--pos=345,44` a náves `--pos=116,195`: AI auta nekončí ani nestojí na konci vjezdu do dvora.
4. Postav auto napříč silnicí před AI autem: do ~40 s troubí a pak objede / přeplánuje, nestojí navždy.
5. Honička s policií po vesnici: policejní auto nekličkuje a neotáčí se k bodům za sebou.

## F3 – Hráč a řemesla
1. Esc → Nastavení: přepínač „Třes obrazu“; vypnuto = žádný třes ani v zimě; po restartu drží.
2. Cigarety jen v Potravinách (hospoda je nenabízí); děda (úkol) vezme i načatou krabičku (≥ 15 ks).
3. Pár cigaret, pak spánek: ráno chuť není 100 %; přes den roste pomalu.
4. F2 → Hráč: silná abstinence a zima → jemný třes v krátkých záchvatech, při míření žádný; F5/F9 závislost zůstane.
5. Ruční vozík: táhni, pusť, sprint funguje na plnou rychlost. Zkus i vozík během úkolu Krmivo a zvěř na rameni.

## F4 – Svět, mapa, místa
1. Mapa M: zoom kolečkem ke kurzoru, tažení, plynulé (bez propadu FPS); silnice obcí se nekreslí dvakrát. V menu / chatu kolečko nezoomuje kameru.
2. Sobota po 11:00 (F2 → Datum/Čas): Potraviny u dveří jen „Zavřeno, otevřeno …“, obsluha není venku. Úřad v sobotu zavřený, v pondělí 7–17.
3. Vejdi do Potravin a vyjdi (víckrát): nepropadneš se. Kdyby ano, pošli z konzole řádky `exit_interior[...]` a varování „propadl“.
4. Ulož uvnitř budovy (F5), načti (F9): bez pádu.
5. Víkend ve dne: v ulicích „Výletník / Výletnice“, žádní dvojníci pojmenovaných postav.

## F5 – NPC, zákon, obsah
1. Konzole bez chyby `ai/villager_routine.tres`; v pracovní den jdou vesničané na pracoviště, zemědělec na statek (ne do hospody).
2. Déšť nebo zima ráno 6–8 h: nikdo nekope na zahradě; jasné jarní ráno ano.
3. So/Ne ~10 h: vesničané jdou nakoupit do otevřeného obchodu.
4. Pá/So večer u hospody: po pivu sedí u stolu, nechodí sem a tam.
5. Zaměstnej se, začni směnu, změň datum (F2): směna se zruší bez napomenutí. Spáchej přestupek → drb na PC zní přirozeně.
6. PC → eTesty: pořadí odpovědí se mění. Texty: místo „ÚCL“ je „ÚVL“, nikde „Zetor“.

## Otevřené body k ověření (varování při startu 6. 10.)
- „Obecní údržba: zóna naves / naves_listi se nevešla“ a „Lesní dělník: v okolí chaty se nenašel les pro paseku“ –
  skripty se neměnily, příčina je nejspíš v nových mapových datech (union mapa / přegenerované stromy a budovy).
  Ověř: práce Obecní údržba a Lesní dělník – mají pracoviště?
