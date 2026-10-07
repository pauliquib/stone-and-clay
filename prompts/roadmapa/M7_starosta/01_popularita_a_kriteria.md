# M7.1 – Popularita a kritéria cesty na starostu (hlavní cíl hry)

> Roadmapa „Život na vsi“ · **M7 Cesta na starostu** · krok 1/4 (doplněk od uživatele)
> Předpoklady: M0.6 (respekt, karma), M4.5 (dobré skutky), M5.5 (kalendář událostí) · doporučeno M1.7, M4.7
> Navazují: M7.2 (kampaň a volby), M7.3 (vedlejší úkoly), M7.4 (starostování)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` + README → „Právní zásady obsahu“ (satira, smyšlená jména;
   **žádný skutečný starosta, strana ani symbol obce**)
2. `scripts/reputation.gd` (pověst, respekt komunit, karma, `on_event`) a `scripts/skills.gd` (Výřečnost)
3. `scripts/quests.gd` (struktura úkolů, `giver`, stavy) a `scripts/hud.gd` → deník (J)
4. `scripts/dialog.gd` + `dialog_data.gd` / `dialog_themes.gd` (téma „politics“ – napojit)
5. `scripts/priroda/village_events.gd` (události v obci)

## 1. Proč
Uživatel: *„Hlavním cílem ve hře bude získat kladnou popularitu a stát se starostou – poctivě, nebo
podplácením a podvody. Cesta má být pro každého hráče jiná, kritéria ale zhruba daná.“* Dnes hra cíl nemá.

## 2. Co udělat
- **Popularita** (nová osa v `Reputation`, 0–100 %): podíl voličů, kteří by hráče volili. Počítá se z
  **pověsti** (veřejné), **respektu komunit** (sousedé, štamgasti, hasiči, fotbalisté, zemědělci, mládež – každá
  komunita = blok voličů s váhou podle počtu členů), **přátelství** s konkrétními postavami (každá postava =
  hlas + vliv na rodinu / komunitu) a **klamu** (skrytá hodnota z nečestných cest, M7.2). Karma popularitu přímo
  nemění, ale řídí štěstí a konec příběhu.
- **Kritéria kandidatury** (data `data/volby.json`): trvalý pobyt v obci (M1.7 – byt stačí), bez odsouzení za
  úmyslný trestný čin v posledních letech (M4.3; jinak jen přes podvod), podpisy 7 % voličů na petici
  (sbírají se rozhovorem – postava podepíše podle přístupu `attitude`), kauce / poplatek, termín voleb
  (komunální volby každé 4 herní roky; pro hratelnost **první volby po 60 herních dnech**, dál po 120 – nastavitelné).
- **Protikandidát:** smyšlený úřadující starosta (dnes „Starosta Novák“ u úřadu) s vlastní popularitou, která se
  mění podle událostí (díry v silnici, akce obce, skandály). Další 1–2 kandidáti podle seedu hry → každá hra jiná.
- **Deník (J) → záložka „Obec“:** popularita (slovně + %, přesně až s dovedností Výřečnost / průzkumem),
  bloky voličů, splněná kritéria, datum voleb, co lidé chtějí (3 aktuální „přání obce“ – generovaná: oprava
  hřiště, lavičky, rozhlas, koupaliště, méně aut na návsi…).
- **Rozhovor:** vesničané reagují na kandidaturu (téma „politics“, nové věty v `DialogThemes` / `DialogData`),
  ptají se na názor k přání obce (otázka zpět → ano / ne ovlivní jejich hlas).
- **Uložení** popularity, kritérií, podpisů, kandidátů a termínu.

## 3. Minimum
Popularita z pověsti / respektu / přátelství, kritéria a termín voleb v `data/volby.json`, záložka „Obec“ v deníku,
podpisy petice rozhovorem, protikandidát.

## 4. Hotovo, když
- Hráč vidí v deníku, jak si stojí a co mu chybí; akce ve světě (úkoly, přestupky, dárky) popularitu viditelně mění.

## 5. Návrh checklistu ručních testů
1. Nová hra → J → „Obec“: popularita nízká, kritéria, datum voleb, 3 přání obce.
2. Splnit úkol pro hasiče → roste respekt hasičů i popularita.
3. Urazit postavu → popularita klesne (a víc u její komunity).
4. Rozhovor (T): „podepíšeš mi petici?“ → přítel podepíše, nepřítel ne; počet podpisů v deníku.
5. Rozhovor: „co si myslíš o starostovi?“ → názor podle povahy.
6. F2 → přeskočit čas k volbám → oznámení o blížících se volbách.
7. Uložit / načíst → hodnoty zůstanou.

## 6. Závěr
README, VIZE a roadmapa README odškrtnout, PROJECT_LOG, commit „M7.1 Popularita a kritéria: …“,
checklist a čekat.
