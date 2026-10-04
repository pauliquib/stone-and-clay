# M3.3 – Další práce: les, prodavač, rozvoz, zahradník, pálenice, opravář

> Roadmapa „Život na vsi“ · **M3 Práce a počítače** · krok 3/4
> Předpoklady: M3.1, M3.2, M2.1 (kácení), M2.5 (sázení), M1.6 (dodávka), M1.7 (`Estate` – čísla popisná) · Navazují: M5.2 (plavčík), M4.1 (řidičák – rozvoz)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `scripts/jobs.gd`, `data/prace.json` a záznamy M3.1–M3.2 v `PROJECT_LOG.md` (vzor definice úkolů)
3. `scripts/tree_manager.gd`, `scripts/actions.gd` (kácení / sázení), `scripts/cargo.gd` (náklad)
4. `scripts/place.gd` – Potraviny, pálenice (`OFFERS`, obsluha)
5. `scripts/traffic.gd` / `road_graph.gd` – hlavičky (trasy po obci pro rozvoz), `scripts/world.gd` – `move_player_car_to`, `place_park`
6. `scripts/car.gd` – `repair`, poškození (grep `damage`)

## 1. Proč
Pestrost prací pro různé styly hry a dovednosti. Každá práce využívá už hotové systémy.

## 2. Práce (každá = záznam v `data/prace.json` + pracovní úkoly; přidávej po jedné, commit po každé dvou)
| Práce | Zaměstnavatel (smyšlený) | Požadavky | Směna | Náplň | Mzda |
|---|---|---|---|---|---|
| **Lesní dělník** | Lesní správa (vedoucí u myslivecké chaty) | `drevorubectvi ≥ 8`, pracovní oděv + ochrana k pile (M2.3) pro pilu | po–pá 6–14 | vyznačené stromy (barevný pruh na kmeni) pokácet, odvětvit, rozřezat, složit polena na hromadu; na jaře **výsadba** sazenic v pasece (M2.5) | 190 Kč/h, respekt `zemedelci` |
| **Prodavač/ka v Potravinách** | Potraviny | `vyrecnost ≥ 2`, pověst ≥ 0 | po–so ranní 6–12 / odpolední 12–21 | pokladna (zákazník přinese zboží – součet, vrátit správně: jednoduchá minihra s mincemi), doplnit regály (nosit bedny ze skladu – náklad), ráno převzít pečivo | 150 Kč/h |
| **Rozvoz / pošta** | „Vesnická pošta“ | řidičák B (M4.1 – do té doby `license_ok`), dodávka zapůjčená (M1.6) | út, čt 8–13 | rozvézt 6–10 balíků na adresy (náhodné domy z registru `Estate` – u dveří E „Doručit“, adresa = **smyšlené číslo popisné z M1.7** + značka na mapě; u bytového domu schránky u vchodu), čas | 165 Kč/h + prémie za včasnost |
| **Zahradník u sousedů** | brigáda na zavolání (sousedé) | `zahradnictvi ≥ 5` | nepravidelně (nabídka u dědy / vesničanů) | sekání trávy, stříhání keřů, rytí záhonů na cizí zahradě (dočasná zóna u domu zákazníka z `Estate`), výsadba | úkolová: 400–900 Kč za zakázku, respekt `sousede` |
| **Pomocník v pálenici** | Pálenice U Kotla | věk – dospělý (vždy), střízlivost | sezóna IX–XII, st–so 8–16 | nosit kvas (sudy – náklad), přikládat pod kotel (polena z M2.1), hlídat teplotu (minihra – ručička v zeleném pásmu), plnit lahve | 150 Kč/h + lahev slivovice týdně (pozor na pokušení!) |
| **Opravář aut** | kutil ve dvoře (smyšlený) | `kutilstvi ≥ 10` | na zavolání | opravit poškozená auta vesničanů (akce oprava z `Car.repair` rozšířit o díly: `dily_auto` ze stavebnin/Potravin) | úkolová 500–1500 Kč |

- **Plavčík na koupališti** – přidá M5.2 (jen si připrav zápis v tabulce, práce se aktivuje, až koupaliště existuje).
- Každá práce: aspoň 2 typy úkolů, odměna XP do příslušných dovedností.

## 3. Minimum
Lesní dělník, prodavač a zahradník. Ostatní do otevřených bodů.

## 4. Hotovo, když
- Nové práce jdou získat podle požadavků, směny fungují, úkoly jsou hratelné, výplaty chodí.

## 5. Návrh checklistu ručních testů
1. Lesní dělník (cheat úroveň 8) → vyznačené stromy, pokácet, složit polena; bez ochrany k pile → nepustí tě s pilou.
2. Potraviny – pokladna: 3 zákazníci, správně vrátit; doplnit regál.
3. Rozvoz: dodávka u pošty, 6 balíků, doručit do času.
4. Děda → zakázka zahradník → posekat → výplata a respekt sousedů.
5. Pálenice v říjnu: přikládání, hlídání teploty.
6. Opravář: opravit auto vesničana.

## 6. Závěr
README, `data/prace.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M3.3 Další práce: …“, checklist a čekat.
