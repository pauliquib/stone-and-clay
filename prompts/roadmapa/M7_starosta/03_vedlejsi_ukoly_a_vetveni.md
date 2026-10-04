# M7.3 – Vedlejší úkoly (sidequesty) s větvením podle pověsti a karmy

> Roadmapa „Život na vsi“ · **M7 Cesta na starostu** · krok 3/4
> Předpoklady: M7.1 · lze dělat souběžně s M7.2 · využívá vše z M2–M5

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` + README → „Právní zásady obsahu“
2. `scripts/quests.gd` (celý – struktura úkolu, kroky, `on_event`, nabídky u míst) a deník v `hud.gd`
3. Seznam herních událostí: `grep -rhoE 'emit_game_event\([^,]+, "[a-z_]+"' scripts | sort | uniq -c`
4. `scripts/reputation.gd` (karma, respekt komunit), `scripts/characters.gd` (postavy a jejich témata)

## 1. Proč
Uživatel: *„Ve hře bude plno sidequestů.“* Dnes je úkolů pár a jsou lineární. Vedlejší úkoly mají dávat
body popularity (M7.1), budovat vztahy a nabízet **morální volby**, které mění příběh.

## 2. Co udělat
- **Úkoly jako data** (`data/ukoly/*.json`): kroky = podmínky na herní události (`fish_caught`, `tree_felled`,
  `harvest`, `gift_given`, `cargo_load`, `chat` se záměrem…), větve = volba hráče (dialog / čin), odměny
  (peníze, předměty, respekt komunity, přátelství, karma, popularita), požadavky (pověst, dovednost, majetek, čas).
  Převést stávající úkoly z `quests.gd` do dat, pokud to nerozbije ukládání (jinak jen nové).
- **Aspoň 15 nových úkolů** napříč řemesly a komunitami, každý s **2–3 zakončeními**, např.:
  sousedův ztracený pes (vrátit / nechat si / „najít“ za odměnu), pytlák v lese (udat / krýt / přidat se),
  hasiči shánějí stříkačku (sehnat poctivě / „vypůjčit“ z vedlejší obce), stará paní potřebuje dřevo (zadarmo /
  za peníze / předražit), hádka o mez mezi sousedy (rozsoudit / podplatit jednoho / nechat eskalovat),
  fotbalisté bez brankáře, zatoulaná kráva na silnici, sbírka na kapličku (přispět / zpronevěřit), vinařův
  ukradený sud, kluci s pyrotechnikou, výlov rybníka, požár trávy (M5.3), pomoc s porodem telete, nedělní
  oběd u babičky, stará motorka ve stodole (opravit a vrátit / prodat).
- **Větvení podle pověsti / karmy:** kdo je „postrach vsi“, tomu lidé nabídnou jiné (horší) úkoly; vysoká
  karma odemyká úkoly „od srdce“ (bez odměny, s velkým respektem). Úkoly se nabízejí rozhovorem (téma „help_me“,
  otázka zpět) a u míst (E).
- **Řetězy postav:** 3 postavy z `Characters` dostanou řetěz 3 úkolů (příběh), jehož konec ovlivní jejich hlas
  a hlas jejich komunity ve volbách.
- **Deník:** aktivní / splněné / nezdařené, u každého zvolená větev jednou větou.

## 3. Minimum
Úkoly jako data s větvemi, 10 nových úkolů se 2 konci, nabídka rozhovorem, dopad na popularitu a karmu.

## 4. Hotovo, když
- Hráč najde během prvních dní hry aspoň 5 úkolů, rozhodnutí v nich mají viditelné následky (drby, hlasy, karma).

## 5. Návrh checklistu ručních testů
1. T u vesničana: „potřebuješ s něčím pomoct?“ → nabídne úkol (nebo odkáže na jiného).
2. Ztracený pes → najít → vrátit → přátelství + respekt sousedů.
3. Stejný úkol znovu (nová hra) → nechat si psa → drby o hráči, karma −.
4. Pytlák → udat myslivci / krýt → rozdílné reakce myslivce a štamgastů.
5. Sbírka na kapličku → zpronevěřit → při odhalení pád pověsti.
6. Deník (J) → splněné úkoly se zvolenou větví.
7. Uložit / načíst uprostřed úkolu → pokračuje správný krok.

## 6. Závěr
README, VIZE a roadmapa README odškrtnout, PROJECT_LOG, deník AI, commit „M7.3 Vedlejší úkoly: …“,
checklist a čekat.
