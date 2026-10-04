# M1.5 – Interiéry veřejných budov

> Roadmapa „Život na vsi“ · **M1 Živý svět** · krok 5/6
> Předpoklady: M1.4 · Navazují: M3 (práce ve výčepu, v obchodě), M4.2 (úřad), M5.5 (zábava v sále)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `scripts/interior.gd` a domov z M1.4 (jak se staví a registrují objekty) + záznam M1.4 v `PROJECT_LOG.md`
3. `scripts/place.gd` (celý, 298 ř.) – obsluha (`keeper`), štamgasti (`regulars`), páteční hosté, nabídky, otevírací doby, `_beer_garden`
4. `scripts/npc.gd` (110 ř.) – jak stojí / sedí obsluha
5. `scripts/local_client.gd` – `open_place_menu`
6. `scripts/priroda/village_events.gd` – `event_hours` (hody: hospoda déle)

## 1. Proč
Hospoda, obchod, úřad, pálenice, sklep a myslivecká chata jsou dnes jen dveře s nabídkou. Chceme
dovnitř: obsluha za pultem, štamgasti u stolu, zboží v regálech – a místo pro budoucí práce (výčep,
prodavač), úřad (pokuty, doklady) a zábavy.

## 2. Co udělat (každý interiér vymyšlený, procedurální přes MeshKit, reálné rozměry)
| Místo | Obsah | Kdo je uvnitř |
|---|---|---|
| **Hospoda U Hřiště** | výčep s pípou, bar, 5–6 stolů, lavice, věšák, šipky, TV na zdi, **sál** vzadu (pódium pro kapelu – M5.5), WC dveře (dekor) | hostinský za výčepem, štamgasti u stolu (přesunout dovnitř z venkovní zahrádky – zahrádka zůstane v létě venku), páteční hosté |
| **Potraviny** | pokladna, 4 regály (pečivo, nápoje, konzervy, drogerie), chladicí vitrína, košíky | prodavačka u pokladny |
| **Obecní úřad** | chodba, podatelna s přepážkou, kancelář starosty (stůl, vlajka **bez znaku obce** – obecná trikolóra nebo nic), nástěnka | úřednice u přepážky |
| **Pálenice U Kotla** | kotel, destilační kolona (měď), sudy s kvasem, stůl s lahvemi | pálenice |
| **Vinný sklep** | klenba, sudy, degustační stůl, police s lahvemi | sklepník |
| **Myslivecká chata** | krb, trofeje (parůžky – bez skutečných osob), stůl, palandy (propojit s existující palandou pod přístřeškem – nech venku) | myslivec (pokud je v chatě podle přírody 04) |

- Obsluha (`Place.keeper`) stojí **uvnitř** za pultem, když je hráč uvnitř; venku zmizí / zůstane u dveří,
  když je zavřeno. Nejjednodušší: `Place` má `keeper_inside_pos` a keeper se přesune podle toho, zda je
  hráč uvnitř (hráč je v jednu chvíli jen na jednom místě). Nabídka (E u obsluhy uvnitř) = stávající `open_place_menu(key)`.
- **Zavřeno:** dveře zamčené → E ukáže otevírací dobu (jako dnes).
- **Vyhození:** pověst „postrach vsi“ (`Reputation.refused_at`) → obsluha odmítne a pošle hráče ven.
- **Zvuk:** uvnitř hospody šum hostů (pokud `sfx.gd` nemá, stačí nízký procedurální šum – nebo nic a otevřený bod).
- Venkovní interakce u dveří: „Vejít dovnitř“ + (kvůli rychlosti) ponech i přímou nabídku, pokud uživatel
  zvykl nakupovat rovnou ze dveří – napiš v logu, jak jsi to vyřešil.

## 3. Minimum
Hospoda a Potraviny úplně, ostatní jako jednoduchá místnost s pultem a obsluhou.

## 4. Hotovo, když
- Do všech 6 míst jde vejít (když je otevřeno), obsluha je uvnitř, nákupy a úkoly fungují jako dřív.
- Štamgasti sedí v hospodě; v pátek přibudou hosté.

## 5. Návrh checklistu ručních testů
1. Hospoda 18:00 → dovnitř → hostinský za výčepem, štamgasti u stolu; E u hostinského → nabídka, kup pivo.
2. Pátek 20:00 → víc hostů u druhého stolu.
3. Potraviny → prodavačka, regály; nákup funguje.
4. Úřad v 18:00 → zavřeno, E ukáže otevírací dobu.
5. Pálenice, sklep, chata → vejít, nabídka.
6. Pověst „postrach vsi“ (F2 → Hráč, pokud jde nastavit; jinak přeskoč) → v hospodě odmítnou.
7. Úkol „Páteční pivo“ → funguje i s interiérem.

## 6. Závěr
README, VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M1.5 Interiéry veřejných budov: …“, checklist a čekat.
