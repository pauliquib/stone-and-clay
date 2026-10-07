# M7.2 – Kampaň a volby: poctivě, nebo s úplatky a podvody

> Roadmapa „Život na vsi“ · **M7 Cesta na starostu** · krok 2/4
> Předpoklady: M7.1 · doporučeno M4.3 (soud), M4.4 (svědci), M4.7 (majetek), M3.4 (počítač)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` + README → „Právní zásady obsahu“ (satira; smyšlené postavy,
   **žádné skutečné strany, hesla, loga ani osoby**; nečestné cesty jsou herní satira s následky, ne návod)
2. Záznam M7.1 v `PROJECT_LOG.md`, `data/volby.json`, popularita v `Reputation`
3. `scripts/law.gd` + `data/zakon.json` (přestupky / trestné činy, svědci) a M4.3 (soud)
4. `scripts/quests.gd`, `scripts/dialog.gd` (otázky zpět, drby), `scripts/priroda/village_events.gd`

## 1. Proč
Uživatel chce cestu na starostu **poctivou i nečestnou** (podplácení, podvody, „aby ti věřili“) a klidně
další nápady. Každý hráč má mít vlastní příběh, kritéria zůstávají daná (M7.1).

## 2. Co udělat
- **Poctivé nástroje kampaně:** mítink v sále hospody (M1.5 / M5.5) – krátký rozhovor s volbou témat podle
  přání obce, letáky (tisk v počítači / na úřadě, roznos do schránek = procházka po číslech popisných z M1.7),
  plnění přání obce (oprava lavičky, úklid, akce pro děti – napojit na M4.5 / M5), podpora spolků (sponzorský
  dar hasičům / fotbalu → respekt komunity), debata s protikandidátem (výběr argumentů, Výřečnost).
- **Nečestné nástroje (s rizikem):** úplatek voliči (peníze / pivo / dárek → hlas, ale postava to může říct dál –
  šance podle povahy: drbna a přísný skoro jistě), falešné sliby (popularita hned, po zvolení „dluh slibů“),
  pomluva / fáma o protikandidátovi (šíří se drby v `Dialog`; odhalení = velký pád), zfalšované podpisy petice,
  kupování hlasů přes štamgasty, **kompromat** (vyfotit protikandidáta při přestupku – dron / telefon, M6.1 / M3.4).
  Vše zvyšuje skrytý **klam**; svědci a náhoda (karma) rozhodují o odhalení → novinový „skandál“, policie
  (M4.4: podplácení / volební podvod jako trestný čin), soud (M4.3), zákaz kandidatury.
- **Volební den:** místnost na úřadě, hlasování postav (každá postava hlasuje podle svého výpočtu, s šumem),
  sčítání s napětím (postupné výsledky), vyhlášení na návsi. Prohra → další volby za 120 dní (nebo doplňovací).
  Výhra → M7.4. Remíza → los.
- **Unikátnost:** seed hry mění protikandidáty, přání obce, skandály a náhodné události kampaně (vichřice –
  kdo pomůže, vyhoří stodola, přijede televize…). Zapsat do deníku jako „Příběh kampaně“ (krátké záznamy).
- **Rozhovory:** nová témata a otázky zpět v `DialogThemes` / `DialogData` (volby, sliby, úplatek – nabídnout
  větou „dám ti stovku, když mě budeš volit“ → nový záměr `bribe`).

## 3. Minimum
Mítink + letáky + plnění přání (poctivě), úplatek a pomluva s rizikem odhalení (nečestně), volební den
s hlasováním postav a výsledkem.

## 4. Hotovo, když
- Volby lze vyhrát oběma cestami; nečestná cesta je rychlejší, ale může skončit skandálem a soudem.

## 5. Návrh checklistu ručních testů
1. Mítink v hospodě → vybrat témata podle přání obce → popularita +.
2. Letáky → roznést do 10 schránek → malý nárůst popularity v ulici.
3. T: „dám ti stovku, když mě budeš volit“ → postava přijme / odmítne; drbna to roznese (drb o hráči).
4. Pomluva o protikandidátovi → jeho popularita klesne; při odhalení pád hráče.
5. F2 → přeskočit na volby → hlasování, postupné výsledky, vyhlášení.
6. Prohra → nový termín; výhra → hráč je starosta (oznámení).
7. Úplatek před policistou / přísnou postavou → přestupek / trestný čin a následky.

## 6. Závěr
README, VIZE a roadmapa README odškrtnout, PROJECT_LOG, commit „M7.2 Kampaň a volby: …“,
checklist a čekat.
