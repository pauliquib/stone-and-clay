# M7.4 – Starostou: rozpočet, rozhodnutí a konce příběhu

> Roadmapa „Život na vsi“ · **M7 Cesta na starostu** · krok 4/4
> Předpoklady: M7.2 (hráč může vyhrát volby) · doporučeno M4.2 (úřad), M4.7 (majetek obce), M5 (akce obce)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` + README → „Právní zásady obsahu“ (smyšlená obec v satiře,
   **žádný skutečný rozpočet, znak ani vlajka obce**)
2. Záznamy M7.1–M7.3 v `PROJECT_LOG.md`, `data/volby.json`, klam a sliby v `Reputation`
3. Interiér úřadu (`public_interiors.gd`), úkoly (`data/ukoly/`), `village_events.gd`

## 1. Proč
Po zvolení nesmí hra skončit. Starosta rozhoduje o penězích obce, plní (nebo neplní) sliby z kampaně
a čelí následkům – včetně odhalení podvodů, pokud šel nečestnou cestou.

## 2. Co udělat
- **Kancelář starosty** na úřadě (stůl, počítač): **rozpočet obce** (příjmy – daně, dotace, pronájmy obecních
  pozemků z M4.7; výdaje – údržba, akce, projekty), měsíční přehled.
- **Projekty:** oprava silnice (méně děr → méně nehod), nové lavičky, veřejné osvětlení (víc světel v noci),
  koupaliště (M5.2), hasičárna (M5.3), hřiště (M5.6), autobusová zastávka… Každý projekt: cena, doba, dopad na
  popularitu komunit a viditelná změna ve světě (aspoň jednoduchá: nové lampy, lavičky, cedule).
- **Rozhodnutí na zastupitelstvu** (jednou za měsíc): 2–3 generované body (prodat obecní pozemek sousedovi,
  povolit tancovačku do rána, zakázat parkování na návsi…), hlasování zastupitelů podle vztahu k hráči.
- **Sliby a klam:** nesplněné sliby z kampaně snižují popularitu; nahromaděný klam může spustit **odvolání,
  kontrolu, trestní oznámení** (M4.3) – konec „padlý starosta“. Úplatky od podnikatelů (nabídka → přijmout /
  odmítnout / udat) s rizikem.
- **Konce příběhu (deník + krátká závěrečná scéna, hra pokračuje):** oblíbený starosta (znovuzvolení),
  „šedá eminence“ (vládne přes úplatky, nikdo se nedozví), padlý starosta (odhalení, soud), starosta proti své
  vůli (poctivý, ale bez peněz). Konec určuje popularita, karma a klam.
- **Uložení** rozpočtu, projektů, rozhodnutí a stavu mandátu.

## 3. Minimum
Rozpočet, 5 projektů s viditelnou změnou, měsíční zastupitelstvo, sliby a klam s koncem „padlý starosta“,
aspoň 2 konce.

## 4. Hotovo, když
- Zvolený hráč má co dělat aspoň do dalších voleb a jeho rozhodnutí mění obec, popularitu a konec příběhu.

## 5. Návrh checklistu ručních testů
1. Vyhrát volby (F2 cheat) → kancelář starosty na úřadě přístupná.
2. Rozpočet → spustit projekt „lavičky“ → po dokončení stojí na návsi lavičky.
3. Zastupitelstvo → hlasování o bodech → výsledek podle vztahů.
4. Nesplnit slib z kampaně → popularita klesá, drby.
5. Přijmout úplatek → při odhalení kontrola a soud → konec „padlý starosta“.
6. Další volby → znovuzvolení při vysoké popularitě.
7. Uložit / načíst → rozpočet a projekty zůstanou.

## 6. Závěr
README, VIZE a roadmapa README odškrtnout, PROJECT_LOG, commit „M7.4 Starostování: …“,
checklist a čekat.
