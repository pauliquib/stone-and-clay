# Dukelčice – nová podoba hry a roadmapa

> Zdroj: poznámky uživatele v [`požadavky.md`](požadavky.md) (22 bodů + „multiplayer až ve fázi 2“)
> a upřesnění z 29. 9. 2026 (RuneScape = činnosti ve světě, rybaření, lov, lovecké zbraně, přeprava
> úlovku, ruční vozík; místo Radia Skyrock jiné české rockové rádio).
> Tento dokument je rozpracovává do jedné vize, společných pravidel a postupných kroků.
> Každý krok roadmapy je dimenzovaný zhruba na jednu pracovní relaci agenta a má vlastní „Hotovo, když…“.
> Stav kroků se odškrtává přímo zde (`[ ]` → `[x]`), podrobnosti implementace pak patří do README / návodů.
> **Prompty pro jednotlivé kroky** (jeden soubor = jedna session): [`../prompts/roadmapa/README.md`](../prompts/roadmapa/README.md).

---

## 1. Vize – čím má hra být

**Stone & Clay je simulátor života na české vesnici.** Hráč žije v obci postavené na skutečném terénu
katastru (ČÚZK + OSM), ale ve smyšleném světě se smyšlenými lidmi. Nehraje se na „misi“, ale na **život**:
pracuje, učí se řemesla, stará se o zahradu a zvířata, jezdí, létá, sportuje, chodí na zábavy – a nese
důsledky svých činů podle **českých zákonů** (pokuty, body, řidičák, soud, vězení) i podle toho,
**co si o něm myslí lidé** (pověst, respekt, karma).

Progres je postavený na mechanice ve stylu **RuneScape** – tím se myslí **činnosti ve světě**
(sekání dřeva, rozdělávání ohně, rybaření, lov zvěře, zahrada, chov…), ne ovládání klikáním. Vše, co hráč
dělá, trénuje **dovednosti** (kácení, oheň, rybaření, myslivost, střelba, zahradničení, chov, řízení,
létání, hasičina…). Úroveň dovednosti odemyká nástroje,
recepty, zaměstnání, vozidla a úkoly. Neexistuje jedna „hlavní cesta“ – hráč si sám vybírá, čím bude.

### Herní pilíře

| Pilíř | Co to znamená ve hře | Body z poznámek |
|---|---|---|
| **Živý svět** | Budovy s okny, dveřmi a komíny, interiéry, kouř podle teploty, terén bez satelitního snímku, víc vozidel a zvířat | 6, 8, 9, 20, 22 |
| **Řemesla a dovednosti (RS)** | Kácení, oheň, rybaření, lov, zahrada/pole, sázení stromů, chov, oblečení; XP a úrovně | 3, 4, 5, 10, 20, 21, U1–U3 |
| **Práce a ekonomika** | Zaměstnání s pracovní dobou a výplatou, obchody (i stavebniny), počítač jako brána k úřadům a e-shopu | 11, 13, 15 |
| **Zákon a společnost** | Česká legislativa (přestupky, body, řidičská oprávnění, zbraně, lov a rybolov, soud, vězení), hajný a stráže, pověst + respekt + karma | 12, 14, U2 |
| **Obec a volný čas** | Koupaliště, hasiči a hasičský sport, fotbal, zábava s kapelou, rock/metal rádia, skateboard a U-rampa | 2, 15, 16, 17, 18, 19 |
| **Pohyb a stroje** | Nové auta a motorky, skateboard, létající prostředky (dron, motorový paraglide, motorové rogalo…) | 1, 2, 9 |
| **Multiplayer** | Až v **etapě 2** – teď jen neporušovat architekturu, která je na něj připravená | 26 |

---

## 2. Společná pravidla (platí pro všechny kroky)

### 2.1 Právní zásady obsahu
Platí beze změny [`../PRAVNI_DOPORUCENI.md`](../PRAVNI_DOPORUCENI.md)
a shrnutí v [`../README.md`](../README.md) → „Právní zásady obsahu“. Důsledky pro nové body:

- **Domov hráče** (od M1.7) = nemovitost z registru `Estate`, kterou hráč vlastní / má pronajatou (nová hra: nájemní byt
  v bytovém domě **vylosovaném náhodně z celé mapy**). Všechna čísla popisná jsou smyšlená (číslování od návsi ze seedu);
  původní dům hráče z podkladů („domov hráče“ v poznámkách, dříve smyšlené „č. 221“) je ve hře usedlost s novým
  smyšleným číslem – u ní hospodářství; zahrada a výběh koně jsou pronajaté u domova (stěhují se s `apply_home`).
  Skutečné číslo se nikde nezobrazí.
- **Interiéry jsou vymyšlené** – nikdy podle skutečných domů. Okna nesmí umožnit průhled do reálných
  soukromých prostor (neprůhledná / generická skla, interiéry jen u vstupných budov).
- **Stavebniny, koupaliště, hasiči (SDH), fotbalový klub, kapela** – vše pod smyšlenými nebo parodickými
  názvy, bez log a obecních symbolů. Sousední obce se v herních textech nejmenují (v tomto dokumentu jen
  jako orientace pro umístění).
- **Modely vozidel z internetu** musí být **odbrandované** (bez log, maskotů, typových nápisů) a pojmenované
  parodicky (Oktávka, Fábička, Javor…). I free model skutečného auta nese ochrannou známku / design výrobce.
- **Reálná rádia** (bod 19) – jen jako odkaz na veřejný stream v `data/radia.json`, žádná loga ani jingly
  v datech hry; před veřejným vydáním souhlas provozovatele nebo vyprázdnit seznam (stejně jako u ČRo).
- **Zákony ČR** jsou ve hře zjednodušené – u každého čísla (pokuty, body, lhůty) ve zdrojových datech uvádět
  paragraf a datum ověření; do nápovědy doložku „zjednodušená herní simulace, nejde o právní radu“.

### 2.2 Legální assety z internetu (bod 7)
Každý cizí model, textura, zvuk nebo hudba musí jít **legálně použít v publikované (i placené) hře**.

| Povoleno | Podmíněně (jen konkrétní licence) | Zakázáno |
|---|---|---|
| CC0 / public domain (Poly Haven, ambientCG, Kenney, Quaternius, CC0 na Freesound / OpenGameArt) | CC BY 3.0/4.0 (nutné uvést autora – Sketchfab, Poly Pizza, Freesound, OpenGameArt), royalty-free balíky s licencí pro hry (např. GDC balíky Sonniss) | CC BY-**NC** (nekomerční), CC BY-**ND** (bez úprav), „free for personal use“, bez uvedené licence, ripy z jiných her, Google / Bing 3D |

Postup (zavádí krok **M0.1**):
1. Asset se stáhne do `assets/<druh>/<název>/` spolu s kopií licence / odkazem.
2. Zapíše se řádek do registru `assets/LICENSES.md` (název, autor, zdroj URL, licence, datum, úpravy).
3. Assety s CC BY se automaticky propíšou do titulků (`Hud.CREDITS`, F1).
4. Úpravy: odstranit loga, sjednotit měřítko (1 j = 1 m), osy (Godot −Z dopředu), LOD, kolize.

### 2.3 Technické zásady
- **Singleplayer teď, multiplayer potom:** nový stav patří do `World` (per-hráč přes `id`), vstup přes
  `InputState`, zprávy přes `World.notify` / `emit_game_event` – viz README → „Architektura“.
- **Data místo kódu:** katalogy (předměty, recepty, dovednosti, zaměstnání, přestupky, oblečení, zvířata,
  události) jako slovníky / JSON na jednom místě, aby šly ladit bez zásahu do logiky.
- **Ukládání:** každý nový systém rozšiřuje `save_game.gd`; formát má verzi a staré pozice se musí načíst.
- **Výkon:** celý katastr bez načítání – nové objekty s LOD, daleko od hráče bez fyziky / jen data.
- **Testování dělá výhradně uživatel.** Každý krok končí checklistem ručních testů (max. 10 bodů).

---

### 2.4 Mapování poznámek → kroky roadmapy

| # | Poznámka (zkráceně) | Kapitola | Kroky |
|---|---|---|---|
| 1 | Létající prostředky (dron, motorový paraglide, rogalo…) | 4.6 | M6.1–M6.5 |
| 2 | Skateboard s animacemi + U-rampa za domem | 4.5 | M5.7, M5.8 |
| 3 | Rozdělání ohně | 4.2 | M2.2 |
| 4 | Kácení stromů | 4.2 | M2.1 |
| 5 | Změna oblečení | 4.2 | M2.3 |
| 6 | Interiéry domů | 4.1 | M1.4, M1.5 |
| 7 | Free modely, zvuky a materiály (legálně) | 2.2 | M0.1 (a průběžně) |
| 8 | Okna, dveře, komíny, kouř podle teploty | 4.1 | M1.2, M1.3 |
| 9 | Další auta a motorky (free modely) | 4.1 | M1.6 |
| 10 | Mechanika jako RuneScape (činnosti ve světě) | 3.x, 4.2 | M0.2–M0.4, M2 |
| 11 | Různá zaměstnání | 4.3 | M3.1–M3.3 |
| 12 | Vše dle legislativy ČR (pokuty, vězení, řidičák…) | 4.4 | M0.5, M4.1–M4.4 |
| 13 | Počítače | 4.3 | M3.4 |
| 14 | Víc způsobů jak zlepšit pověst, karmu, respekt | 4.4 | M0.6, M4.5 |
| 15 | Koupaliště na bývalé hasičské nádrži + stavebniny | 4.5 | M5.1, M5.2 |
| 16 | Hasiči a hasičský sport | 4.5 | M5.3, M5.4 |
| 17 | Občasná zábava s kapelou | 4.5 | M5.5 |
| 18 | Lepší fotbalové hřiště + hraní fotbalu | 4.5 | M5.6 |
| 19 | Reálná česká rocková rádia (bez Radia Skyrock) | 4.5 | M5.9 |
| 20 | Slepice, prasata, krávy, kozy, ovce na oplocených loukách | 4.2 | M2.6 |
| 21 | Obdělávání pole / zahrady, sázení stromů | 4.2 | M2.4, M2.5 |
| 22 | Terén bez satelitního snímku | 4.1 | M1.1 |
| U1 | Rybaření | 4.2 | M2.7 |
| U2 | Lov zvěře, lovecké zbraně (luk, kuše, puška), oprávnění, policie a hajný | 4.2, 4.4 | M2.8, M2.9, M4.6 |
| U3 | Nošení úlovku (rameno, auto, nosič motorky, ruční vozík) + ruční vozík | 4.2 | M2.10 |
| 26 | Multiplayer až ve fázi 2 | 6 | Etapa 2 |
| D1 | Konec závislosti na domě hráče, popisná čísla všech domů, start v bytě v bytovém domě | 4.1 | M1.7 |
| D2 | Koupě a prodej domů, bytů, polí, pozemků a lesů | 4.4 | M4.7 |
| D3 | Interiéry všech používaných budov, vstup dveřmi, stavba jen zblízka / uvnitř | 4.1 | M1.8 |
| D4 | Hlavní cíl: popularita a cesta na starostu (poctivě i úplatky / podvody), unikátní příběh, hodně sidequestů | 4.7 | M7.1–M7.4 |
| D5 | Co nejbohatší rozhovor s obyvateli přes T | 3.5 | hotovo mimo milník (doplněk 30. 9. 2026) |
| D6 | Oprava 3D: končetiny „naruby“, divné držení předmětů | – | hotovo mimo milník (doplněk 30. 9. 2026) |
| E1 | Pálení větví jen suchých, obecní vyhláška o zákazu pálení, legální táborák na špekáčky / gril | 4.4 | M4.4 |
| E2 | Úkol: spálit velkou hromadu větví a maskovat to jako opékání špekáčků | 4.7 | M7.3 (mechanika M4.4) |
| E3 | Sucho → vyhláška: zákaz zalévání a napouštění bazénů z vodovodu (kdo má studnu, nemusí) | 4.4 | M4.4 |
| E4 | Sekání trávy a otravný hluk na vsi, nedělní klid | 4.4 | M4.4 |
| E5 | Pouliční osvětlení a světelný smog (viditelnost hvězd) | 4.1 | M5.12 |
| E6 | Rádio v autě, rozsvěcování vnitřního světla v autě | 4.5 | M5.9 |
| E7 | Řidiči v NPC autech, nástup a výstup obyvatel | 4.1 | M5.11 (navazuje M4.5 „odvezeš mě“) |
| E8 | Pěstování, sušení, zpracování a kouření tabáku a konopí, lysohlávky (stavy po užití) – obsah pro dospělé | 4.4 | M4.8 |
| E9 | Nedělní mše v kapličce a v kostele ve Velkém Oříškově (farář, interiér) | 4.5 | M5.5 |
| E10 | Studánka, skautský tábor v lese, MTB bikepark | 4.5 | M5.10 |
| E11 | Editor map, postav, objektů a úkolů | – | milník N (po M7) |
| E12 | Poznámky ze hry 30. 9. (propad u obchodu, zoom mapy, cigarety, víkendy obchodu, vozík a sprint, doprava) | – | hotovo ve vlně 0 (`docs/audit_vlna0.md`) |

---

## 3. Jádro nových mechanik (návrh)

### 3.1 Dovednosti a zkušenosti (RuneScape styl)
- Každá činnost dává **XP** do jedné či více dovedností. Úroveň **1–50** (méně než RS 99, aby šlo
  maxima dosáhnout v rozumné době); křivka exponenciální, parametry v jedné tabulce.
- Úroveň odemyká: nástroje (stará sekera → ocelová → motorová pila), recepty, zaměstnání, úkoly,
  vozidla/stroje a zlepšuje výsledek (rychlost, výnos, menší šance na nehodu).
- Návrh dovedností (lze přidávat):

| Dovednost | Trénuje se | Odemyká (příklady) |
|---|---|---|
| Dřevorubectví | kácení, štípání dřeva | lepší sekery, motorová pila, práce v lese |
| Topení a oheň | rozdělání ohně, topení v kamnech | oheň za deště, grilování, pálení klestí |
| Vaření | opékání, vaření doma | výživnější jídla, recepty |
| Zahradničení / zemědělství | rytí, setí, sklizeň, sázení stromů | nové plodiny, stroje, prodej úrody |
| Chovatelství | krmení, dojení, sběr vajec, stříhání | další druhy zvířat, zisk z produktů |
| Rybaření | lov ryb na udici v potocích a nádržích | lepší prut a návnady, větší ryby, noční rybolov |
| Myslivost | stopování, čekaná, vyvrhnutí a zpracování zvěře | lov větší zvěře, práce v honitbě, lepší zpracování |
| Střelba | střelnice, lov (luk, kuše, puška) | přesnost, rychlejší nabíjení, lepší zbraně |
| Kutilství | oprava auta (už existuje), stavby z materiálu ze stavebnin | U-rampa, ploty, kurníky |
| Řízení | jízda autem, motorkou (per druh vozidla) | lepší ovladatelnost, profesní řidič |
| Jezdectví | jízda na koni (už existuje) | trysk bez pádu, skoky |
| Skateboarding | triky na rampě i na ulici | složitější triky |
| Letectví | dron, paraglide, rogalo | delší lety, náročnější stroje |
| Hasičina | výjezdy, tréninky, požární útok | pozice v družstvu, soutěže |
| Fotbal / kondice | hra, trénink, běh | lepší výdrž, místo v týmu |
| Výřečnost | slušné rozhovory, vyjednávání | slevy, lepší reakce postav |

### 3.2 Předměty, inventář a řemeslo
- Dnes existují dva katalogy: sběratelské `Item.INFO` (body) a `Consumables.ITEMS` (jídlo, pití, vybavení)
  a `Player.inventory` (id → počet). Sjednotit do **jednoho katalogu předmětů** s typy: `food`, `drink`,
  `gear`, `tool`, `material`, `seed`, `clothing`, `animal_product`, `document` (řidičák, licence…).
- Vlastnosti: hmotnost (nosnost podle kondice), cena, trvanlivost / opotřebení nástroje.
- **Recepty** (řemeslo): vstupy → výstup + dovednost/úroveň + nástroj + místo (ohniště, dílna, kuchyň).

### 3.3 Kontextové akce
Jednotný systém „akce na cíl“: hráč míří na strom / záhon / ohniště / zvíře, E nabídne akce podle
nástroje v ruce, akce má **trvání** (průběh na HUD), stojí výdrž, dá XP, může selhat a může být
**přestupkem** (kácení v cizím lese). Na tom stojí kácení, oheň, zahrada, chov, stavby i práce.

### 3.4 Zákon jako data
Katalog `přestupků / trestných činů`: druh → zákon a § (např. 361/2000 Sb. silniční provoz,
251/2016 Sb. přestupky, 40/2009 Sb. trestní zákoník, 114/1992 Sb. ochrana přírody, 289/1995 Sb. lesy,
133/1985 Sb. požární ochrana, 449/2001 Sb. myslivost, 99/2004 Sb. rybářství, zákon o zbraních
a střelivu – od 2026 nový zákon č. 90/2024 Sb., letecké předpisy ÚVL), rozpětí pokuty, body v bodovém systému, zákaz
činnosti, zda jde o trestný čin (→ soud). Konkrétní částky a body se doplní z **aktuálního znění** při
implementaci (bodový systém byl novelizován v roce 2024).

### 3.5 Pověst, respekt, karma
Dnes: **Pověst** −100…100 (`reputation.gd`) + nálada jednotlivých postav (`persona.gd`). Nově tři osy:

| Osa | Rozsah a viditelnost | Co ji mění | Co ovlivňuje |
|---|---|---|---|
| **Pověst** (už je) | celá obec, viditelná | přestupky, veřejné chování, úkoly | ceny, obsluha, policie, drby |
| **Respekt** (nový) | zvlášť v každé komunitě: sousedé, štamgasti, hasiči, fotbalisté, zemědělci, mládež | výkony a pomoc v dané komunitě (soutěž, gól, pomoc na poli, trik na rampě) | přístup do spolků, role v týmu, pozvánky, práce |
| **Karma** (nová) | skrytá, dlouhodobá (v deníku jen slovní popis) | dobré / zlé skutky i bez svědků (vrácená peněženka, týrání zvířete, pomoc cizímu) | náhodné události (štěstí / smůla), vztah zvířat, konce příběhů |

Nové zdroje zlepšení (bod 14): pomoc sousedům na zahradě, odklízení sněhu, dobrovolnictví u hasičů,
úklid po zábavě, doprovod opilého kamaráda domů, vrácení nalezené věci, slušnost a kamarádský přístup
(opakovaný kontakt s postavou → přátelství), pravidelná práce bez absencí, vítězství pro obec (fotbal,
hasičská soutěž).

---

## 4. Obsahové moduly (co přesně chceme)

### 4.1 Živý svět a vzhled
- **Terén bez satelitu (22):** místo ortofota procedurální materiály podle tříd povrchu – pole, louka,
  sad, zahrada (`data/landuse.bin`), les (z `trees.bin`), asfalt/štěrk (`asphalt.bin`, `gravel.bin`),
  voda, dvory; sklon → hlína/kámen; šum proti opakování; roční období a sníh zůstávají. Bonus: z mapy zmizí
  reálné detaily soukromých dvorů.
- **Budovy (8):** generovaná okna, dveře, parapety a komíny na procedurálních domech podle půdorysu
  a výšky (styl vesnické zástavby, žádná kopie skutečných fasád). V noci některá okna svítí.
- **Kouř z komínů podle teploty (8):** pravděpodobnost, že dům topí, roste s mrazem (orientačně
  > 15 °C nikdo, 10 °C ~30 %, 0 °C ~80 %, pod −5 °C všichni; ráno a večer víc), sílu kouře ovlivňuje
  teplota, směr vítr, v mlze / inverzi se kouř drží při zemi. Částice s LOD jen v okolí hráče.
- **Interiéry (6):** vstupné budovy – domov hráče, hospoda, Potraviny, úřad, pálenice, sklep, chata,
  později hasičárna, stavebniny, šatny koupaliště. Ostatní domy zamčené (nebo jen předsíň u úkolů).
  Interiér se načte při vstupu (bez načítací obrazovky), nábytek z free modelů.
- **Vozidla (9):** víc aut a motorek z legálních modelů (odbrandovat), zapojit do AI dopravy i do
  bazaru / koupě; postup viz [`../VLASTNI_VOZIDLA.md`](../VLASTNI_VOZIDLA.md).

### 4.2 Řemesla a venkovský život
- **Kácení (4):** strom z MultiMeshe se změní na fyzikální kmen, padá podle směru zářezu, zbyde
  pařez; kmen → špalky → polena (štípání). Odstraněné stromy se ukládají. Zákon: na vlastní zahradě
  volně, jinde podle zákona o ochraně přírody (povolení z úřadu – obvod kmene, ptáci v hnízdní době),
  v cizím lese = krádež dřeva. Motorová pila: ochranné pomůcky (oblečení!), riziko úrazu.
- **Oheň (3):** zapalovač/sirky + podpal + dřevo, déšť a vítr zhoršují zapálení, oheň hoří podle paliva,
  hřeje (`body_state.cold`), suší (`wetness`), svítí, opékání buřtů. Zákaz rozdělávat oheň v lese
  a do 50 m od lesa, nehlídaný oheň v suchu se šíří → požár → hasiči, přestupek. Doma kamna / krb –
  topení vlastním dřevem (i vlastní komín kouří).
- **Oblečení (5):** sloty hlava / trup / bunda / nohy / boty / rukavice; vlastnosti izolace
  a nepromokavost (napojit na chlad a promáčení), vzhled na postavě (`humanoid.gd`), šatník doma,
  obchod. Pracovní oděv jako podmínka (pila, hasičský zásah, reflexní vesta na silnici), dopad na
  reakce postav (upravený na úřad / zábavu).
- **Pole a zahrada (21):** záhon doma i pronajaté pole: rytí/orba, setí/sázení, zálivka, pletí,
  sklizeň, prodej nebo vaření; plodiny podle kalendáře a počasí (sucho, mráz). Napojit na existující
  `priroda/fields.gd` a sezóny.
- **Sázení stromů (21):** sazenice (ovocné i lesní), růst v herních letech, vlastní vrstva stromů nad
  datovými `trees.bin`, ukládání. Karma / pověst za výsadbu.
- **Hospodářská zvířata (20):** slepice (vejce), prasata, krávy (mléko), kozy, ovce (vlna) na
  **oplocených** loukách a ve výbězích; krmení, voda, péče, produkty, zvířata se mohou zatoulat při
  rozbitém plotu. Stavba na `fauna/animal.gd`, `herd.gd`, `animal_specs.gd`. Týrání/zanedbání = karma
  a přestupek.
  **Porážka vlastních zvířat** je **legální a doporučená cesta k masu** (hra k ní hráče vede místo
  pytláctví): slepice, králík, prase (zabijačka jako malá událost, pomoc sousedů, respekt), koza, ovce;
  maso → jídlo, uzení, prodej sousedům. Pravidla: jen vlastní zvíře, bez zbytečného trápení (jinak
  karma a přestupek týrání), maso pro vlastní potřebu; prodej ve velkém jen přes výkup / jatka.
  Veterinární podmínky (např. vyšetření prasete na trichinely) ověřit v aktuálních předpisech při
  implementaci. Vlastní chov je pomalejší a dražší než pytláctví, ale bez rizika.
- **Rybaření (U1):** prut, vlasec, návnady (žížaly z vlastní zahrady, těsto), místa v potocích a na
  nádržích (`water.gd`); záběr jako krátká minihra (napětí vlasce), ryby podle místa, denní doby, sezóny
  a počasí, hájení a lovné míry. Úlovek sníst (oheň z M2.2), prodat nebo pustit. Legálně jen
  s **rybářským lístkem + povolenkou** k revíru; bez nich = pytláctví → **rybářská stráž**.
- **Lov zvěře (U2):** srnci, divočáci, zajíci z `fauna/` (už mají vnímání zrakem, sluchem a čichem po
  větru – stopování, přikrčení, vítr v zádech, čekaná na posedu za soumraku). Zásah podle místa
  a zbraně, postřelené zvíře utíká a nechává krvavou stopu, dohledávka. Po úlovku vyvrhnutí
  a přeprava; zvěřina se zpracuje doma, sní nebo prodá (legálně jen s dokladem o původu).
- **Lovecké zbraně (U2):** **luk**, **kuše**, **puška** (kulovnice, případně brokovnice na drobnou
  zvěř). Nákup, střelivo / šípy, opotřebení, střelnice pro trénink. Pravidla:
  - **puška** – koupit a nosit jen se **zbrojním oprávněním**; lovit jen navíc s **loveckým lístkem**
    a **povolenkou k lovu** od honitby (myslivecký spolek). Bez oprávnění = policie (zabavení,
    trestný čin nedovoleného ozbrojování).
  - **luk a kuše** – jde koupit bez oprávnění (střelnice, terče), ale **lov jimi je v ČR zakázán** →
    každý úlovek lukem / kuší je **pytláctví**. Legální použití jen sportovní.
  - **Pytláctví je záměrně možná, ale zakázaná cesta:** hráč lovit může (luk, kuše i puška bez povolenky),
    je to rychlý a **výnosnější** zdroj masa a peněz (zvěřina „bokem“ – překupník, hospoda, sousedé, kteří
    se nebudou ptát), ale s vysokým rizikem: hajný, svědci, policie, soud, zabavení zbraní, ztráta
    zbrojního oprávnění, pověsti a karmy. Hra nic nezakazuje, jen nese důsledky.
  - Zbraň v obci, opilý se zbraní, střelba u silnice nebo u domů = přestupky až trestné činy.
- **Kdo tě může chytit (U2):** **hajný / myslivecká stráž** hlídkuje v lesích (hlavně za šera, slyší
  výstřely, vidí krev a stopy), **rybářská stráž** u vody, **policie** (kontrola na silnici, zbraň při
  kontrole) a **svědci** – vesničan, který uvidí nést zvěř nebo pušku, to může nahlásit (podle povahy
  a vztahu k hráči). Kontrola: předložit doklady (zbrojní oprávnění, lovecký / rybářský lístek,
  povolenka, doklad o původu zvěřiny). Pytláctví = pokuta, zabavení zbraně i úlovku, trestný čin,
  velká ztráta pověsti a karmy.
- **Přeprava úlovku a ruční vozík (U3):** zvěř se **nemůže nosit v inventáři**. Možnosti:
  - **na rameni** – jen drobná zvěř (zajíc) a srnec; pomalá chůze, nelze sprint ani skok, rychleji ubývá
    výdrž, úlovek je dobře vidět (svědci, hajný);
  - **v autě** – v kufru (nevidí ho nikdo, ale policie při kontrole může kufr prohlédnout);
  - **na nosiči motorky** (vzadu na Javoru) – jen menší kus, zhorší ovladatelnost, je vidět;
  - **na ručním vozíku** – **nový předmět**: vozík se tlačí / táhne (fyzika jako u beden a sudů), uveze
    i divočáka, dřevo z kácení, úrodu, materiál ze stavebnin, pytle; lze ho přikrýt plachtou
    (hůř vidět), do kopce se tlačí pomalu, na svahu může ujet.
  - **divočák** jde **jen ve dvou** (hráč + pomocník – kamarád z vesnice s dobrým vztahem, v etapě 2
    druhý hráč; oba jdou pomalu), **v autě** nebo **na ručním vozíku**. Sám na rameni ani na motorce ne.
  Stejný systém „nákladu“ (náklad na těle / ve vozidle / na vozíku) použijí i polena, úroda a materiál.

### 4.3 Práce, ekonomika, počítače
- **Zaměstnání (11):** každé má požadavky (dovednost, řidičské oprávnění, oblečení, čistý rejstřík,
  pověst), pracovní dobu, náplň (série kontextových akcí / minihra), výplatu a hodnocení. Pozdní
  příchod, opilost v práci nebo absence → napomenutí → výpověď. Návrhy: pomocník na farmě, lesní dělník,
  prodavač (Potraviny, stavebniny), výčepní, rozvoz / pošta, obecní údržba (sekání, úklid sněhu),
  zahradník u sousedů, plavčík na koupališti, pomocník v pálenici, opravář aut / počítačů. Hasič
  dobrovolník je spolek, ne práce (respekt místo mzdy).
- **Počítače (13):** PC doma (později notebook / úřad): e-shop s doručením balíku, bazar vozidel,
  portál práce, internetové bankovnictví, e-testy (teorie autoškoly, zkouška pro drony), obecní
  web s akcemi a drby, pozvánky na události, jednoduché hry. Herní UI ve stylu starého OS.

### 4.4 Zákon a společnost
- **Řidičská oprávnění:** skupiny AM / A1 / A2 / A / B / T (traktor) – řízení bez oprávnění = přestupek
  či trestný čin; získání přes autoškolu (teorie na PC, jízdy s instruktorem, zkouška).
- **Bodový systém a pokuty:** body za přestupky, po dosažení limitu zákaz řízení a přezkoušení;
  pokuty na místě (blokově) / příkazem / ve správním řízení na úřadě.
- **Trestné činy:** jízda pod vlivem nad 1 ‰ (už je záchytka), maření výkonu úředního rozhodnutí
  (řízení přes zákaz), ublížení na zdraví, krádež (dřevo, úroda) → **soud** (podmínka, obecně prospěšné
  práce, vězení). Vězení = časový skok s následky (ztráta práce, zvířata bez péče, pověst).
- **Letectví, požáry, příroda:** registrace provozovatele dronu, létání nad lidmi a soukromím,
  pálení v suchu, kácení bez povolení – vše ze stejného katalogu přestupků.
- **Zbraně, lov a rybolov:** doklady jako předměty typu `document` – **zbrojní oprávnění** (zkouška
  teorie na PC + praktická na střelnici, lékařský posudek, čistý rejstřík), **lovecký lístek** (myslivecký
  kurz a zkouška), **rybářský lístek** (kurz a zkouška), **povolenky** (koupě u spolku / na PC). Odebrání
  při trestné činnosti nebo alkoholu se zbraní. Stráže (hajný, rybářská stráž) jsou postavy s povahou,
  mohou legitimovat, zabavit a předat policii.

### 4.5 Obec a volný čas
- **Stavebniny (15):** nová budova v dolině za obcí u cesty k sousední obci (smyšlený název), obchod
  s materiálem, nářadím, semeny, plotovkami; napojení na kutilství (U-rampa, ploty, kurníky).
- **Koupaliště (15):** bývalá hasičská nádrž u potoka hned za stavebninami → koupaliště (mola, šatny,
  občerstvení, plavčík). Nové **plavání** hráče (zatím je jen brodění), teplota vody podle počasí
  a sezóny, chlad po vylezení, zakázané skoky do mělké vody, v zimě bruslení na ledu.
- **Hasiči (16):** zbrojnice, spolek SDH (smyšlený), členství, tréninky, výjezdy k požárům z bodu 3
  (tráva, komín, auto), cisterna / stříkačka jako vozidlo.
- **Hasičský sport (16):** **požární útok** jako minihra (sání, mašina, rozdělovač, proudy na terče,
  měření času), soutěž více družstev jako událost, respekt u hasičů.
- **Zábava s kapelou (17):** systém **událostí** v kalendáři (zábava, hody, fotbalový zápas, hasičská
  soutěž, posvícení) – plakáty / web na PC, NPC přijdou, kapela hraje (generovaná nebo CC0 hudba),
  tanec, bar, rvačky → policie, po zábavě úklid (respekt).
- **Fotbal (18):** hřiště s brankami a sítí, čarami, lavičkami, osvětlením, kabinami; kopaná s NPC,
  penalty, víkendový zápas s diváky jako událost, dovednost Fotbal.
- **Skateboard (2):** nové jednostopé vozidlo (odraz nohou, jízda, brzda, ollie, grind, jednoduché
  triky) s animacemi postavy přes IK v `humanoid.gd`; pád při chybě; dovednost Skateboarding.
- **U-rampa (2):** na zahradě domu hráče hned za domem; volitelně jako stavba z materiálu ze stavebnin.
- **Rocková rádia (19):** přidat do `data/radia.json` veřejné streamy českých rockových stanic
  **Rock Radio** a **Radio Beat** (klasický rock), případně **Rock Zone** – ověřit adresy streamů
  a podmínky. Radio Skyrock se nepřidává. Smyšlené *Rádio Kovadlina* (metal) zůstává.

### 4.6 Létání (1)
- **Dron:** pohled z kamery, baterie, dosah, vítr; pravidla ÚVL (registrace provozovatele, online test
  A1/A3, max. 120 m, ne nad lidmi a cizími pozemky) → přestupky, dron může spadnout a něco poškodit.
- **Motorový paraglide (paramotor):** rozběh, trim, plyn, vítr a termika, přistání; pilotní průkaz
  (sportovní létání – LAA ČR).
- **Motorové rogalo (trike)** a další (UL letadlo, vírník – volitelně): rozjezd po louce / letišti.
- **Technicky:** mapa končí na hranici katastru – z výšky bude potřeba **pozadí za okrajem**
  (nízkorozlišený terén okolí z DMR ČÚZK, mlha na horizontu) a neviditelná hranice letu.

### 4.7 Hlavní cíl: cesta na starostu (D4)
- **Popularita** (podíl voličů) z pověsti, respektu komunit a přátelství s postavami; kritéria kandidatury
  a termín voleb jsou daná (`data/volby.json`), cesta k nim je na hráči.
- **Poctivě:** mítinky, letáky, plnění „přání obce“, podpora spolků, debata. **Nečestně:** úplatky, falešné sliby,
  pomluvy, zfalšované podpisy, kompromaty – rychlejší, ale se skrytým „klamem“ a rizikem skandálu, soudu a pádu.
- **Unikátnost:** seed hry mění protikandidáty, přání obce, skandály a události kampaně; vedlejší úkoly se
  2–3 konci a řetězy postav rozhodují hlasy komunit. Po zvolení rozpočet, projekty, zastupitelstvo a konce příběhu.
- Satira se smyšlenými postavami – žádný skutečný starosta, strana, znak ani rozpočet obce.

---

## 5. Roadmapa (etapa 1 – singleplayer)

Pořadí je zvolené tak, aby se **nejdřív postavily společné základy** (assety, předměty, dovednosti,
akce, zákon, společenské osy), na které se pak jednotlivé funkce jen „zapojují“. Uvnitř milníku lze
kroky přehazovat, mezi milníky platí závislosti.

### M0 – Základy
- [x] **M0.1 Pipeline a registr legálních assetů** – složka `assets/`, `assets/LICENSES.md`,
  automatické titulky z CC BY, návod k importu `.glb` / zvuků (měřítko, osy, LOD, kolize, odbrandování).
  *Hotovo, když:* jeden testovací CC0 model a zvuk je ve hře a v registru, titulky ho uvádějí.
- [x] **M0.2 Jednotný katalog předmětů a inventář** – sloučit `Item.INFO` a `Consumables.ITEMS`,
  typy, hmotnost, opotřebení; převést ukládání. *Hotovo, když:* stávající nákupy, sběr, spacák
  a staré uložené pozice fungují beze změny chování.
- [x] **M0.3 Dovednosti a XP** – tabulka dovedností, křivka, zisk XP z událostí (`emit_game_event`),
  HUD oznámení „+XP / nová úroveň“, záložka v deníku J, ukládání. Napojit na existující činnosti
  (řízení, jízda na koni, oprava auta, rozhovory). *Hotovo, když:* jízdou a jízdou na koni rostou úrovně.
- [x] **M0.4 Kontextové akce a nástroje** – nástroj v ruce, výběr cíle, trvání s průběhem, výdrž,
  XP, recepty (řemeslo). *Hotovo, když:* testovací akce (např. natrhat trávu) projde celým řetězcem.
- [x] **M0.5 Katalog přestupků (zákon jako data)** – převést dnešní pravidla (alkohol, rychlost,
  zákaz řízení, rušení klidu, urážky) do katalogu s § a body; bodový systém řidiče. *Hotovo, když:*
  současné pokuty jdou z katalogu a deník ukazuje body.
- [x] **M0.6 Respekt a karma** – rozšířit `reputation.gd` o komunity a skrytou karmu, deník J.
  *Hotovo, když:* aspoň 3 existující akce mění respekt / karmu a vše se ukládá.

### M1 – Živý svět
- [x] **M1.1 Terén bez satelitu** – procedurální materiály podle tříd povrchu; přepínač ortofoto ↔
  nové, po schválení ortofoto z buildu odstranit (a aktualizovat licence).
- [x] **M1.2 Okna, dveře, komíny** – generátor fasád podle půdorysu (`data/buildings.json` z `tools/buildings.py`),
  svícení oken v noci, LOD (`BuildingDetails`; API `chimneys_near`, `door_of`).
- [x] **M1.3 Kouř z komínů podle teploty** – pravidlo z 4.1 napojené na `priroda/weather.gd`, vítr, mlha.
- [x] **M1.4 Systém interiérů** – vstup do budovy bez načítání, sdílený kolizní a světelný model,
  první interiér: **domov hráče** (kuchyň, lednička, postel, rádio, kamna, šatník, PC – zatím místa).
- [x] **M1.5 Interiéry veřejných budov** – hospoda, Potraviny, úřad, pálenice, sklep, chata.
- [x] **M1.6 Nová vozidla** – 2–4 auta a 1–2 motorky z legálních modelů (odbrandované), AI doprava,
  koupě v bazaru (zatím u úřadu / dialogem, později přes PC).
- [x] **M1.7 Popisná čísla a start v bytě** (D1) – registr nemovitostí `Estate` se smyšlenými čísly popisnými
  a cedulkami, domov = vlastnictví / nájem, nová hra v bytě v bytovém domě, žádné „221“ v kódu (migrace
  starých uložení). *Hotovo, když:* nová hra začíná v bytě a staré uložení funguje.
- [x] **M1.8 Interiéry všech budov se streamováním** (D3) – generované interiéry z půdorysu (rodinný dům,
  bytový dům, hospodářská budova), stavba jen do ~8 m od dveří / uvnitř, max. 3 najednou, cizí domy zamčené
  s klepáním. *Hotovo, když:* do každé budovy se jde dveřmi a chůze obcí je bez záseků.

### M2 – Řemesla a venkov (RS jádro)
- [x] **M2.1 Kácení a zpracování dřeva** – kácení, pád, pařez, špalky, polena, ukládání odstraněných
  stromů, přestupky podle místa.
- [x] **M2.2 Oheň a topení** – ohniště, kamna doma (+ vlastní komín), opékání, šíření v suchu, zákazy.
- [x] **M2.3 Oblečení** – sloty, izolace / nepromokavost, vzhled, šatník, obchod s oděvy.
- [x] **M2.4 Zahrada a pole** – záhon u domu hráče, plodiny podle kalendáře, sklizeň, prodej / vaření.
- [x] **M2.5 Sázení stromů** – dynamická vrstva stromů, růst, ukládání.
- [x] **M2.6 Hospodářská zvířata** – ploty a výběhy, slepice → prasata, krávy, kozy, ovce; péče, produkty
  a porážka vlastních zvířat (zabijačka jako událost), maso a jeho zpracování. *Hotovo, když:* jde
  vychovat slepici / prase, porazit a sníst maso bez přestupku.
- [x] **M2.7 Rybaření** – prut a návnady, místa v potocích a nádržích, minihra záběru, druhy ryb podle
  místa / sezóny / počasí, hájení a míry, vaření na ohni. *Hotovo, když:* jde chytit, upéct a prodat rybu.
- [x] **M2.8 Zbraně a střelba** – luk, kuše, puška, střelivo / šípy, míření a balistika, střelnice
  s terči, dovednost Střelba, zbraň v ruce viditelná pro okolí. *Hotovo, když:* na střelnici jde trénovat
  všemi třemi zbraněmi a puška bez oprávnění nejde koupit.
- [x] **M2.9 Lov zvěře** – zásahy, postřelení a dohledávka, krvavá stopa, posed a čekaná, vyvrhnutí,
  zvěřina. Využije vnímání zvěře z `fauna/`. *Hotovo, když:* jde ulovit srnce, vyvrhnout a zpracovat doma.
- [x] **M2.10 Náklad a ruční vozík** – systém nákladu (rameno / kufr auta / nosič motorky / vozík),
  omezení pohybu, viditelnost nákladu; ruční vozík jako tlačený fyzikální předmět (i pro dřevo, úrodu,
  materiál); nesení ve dvou s pomocníkem (NPC kamarád). *Hotovo, když:* srnec jde dopravit domů všemi
  čtyřmi způsoby a divočák jen ve dvou, autem nebo na vozíku. *(Hotovo Minimum: rameno, kufr / ložná plocha, nosič, vozík;
  nesení ve dvou s pomocníkem zůstává otevřený bod.)*

### M3 – Práce a počítače
- [x] **M3.1 Systém zaměstnání** – katalog prací, docházka, výplata, hodnocení, výpověď.
- [x] **M3.2 První tři práce** – farma, obecní údržba, výčep (využijí M2 a M0.4).
- [x] **M3.3 Další práce** – les, prodavač, rozvoz, zahradník u sousedů (plavčík po M5.2). *Hotovo: lesní dělník, prodavač/ka, zahradník, pálenice; rozvoz a opravář – otevřené body (PROJECT_LOG).*
- [x] **M3.4 Počítač** – PC doma s UI: e-shop + doručení, bazar, portál práce, bankovnictví, web obce. *Hotovo i pošta, bankomat, eTesty (rámec + cvičný test), Miny; otevřené body v PROJECT_LOG.*

### M4 – Zákon a společnost
- [x] **M4.1 Řidičská oprávnění a autoškola** – rozšíření `Permits` (skupiny, odebrání, přezkoušení), panel dokladů P,
  e-test na PC, jízdy, zkouška, jízda bez oprávnění.
- [x] **M4.2 Správní řízení na úřadě** – blokové pokuty, příkazy poštou, splatnost, odpor, společný systém dluhů a exekucí
  (`Debts` – použije ho i M4.3 a hypotéka M4.7), schránka, vrácení řidičáku.
- [ ] **M4.4 Další přestupky a svědci** – **část A hotová** (jednotný `witness_check`, nenahlášené činy, oživené řádky
  katalogu; zbývá povolení ke kácení). **Část B částečně:** hotovo – vyhlášky na úřední desce (zákaz pálení, sucho,
  nedělní klid), čerstvé vs. suché větve (sušení ~30 dní, kouř u ohně, přestupky), `Weather.drought`. **Zbývá:** hromada
  klestí jako objekt, zákaz zalévání z vodovodu (vodovodní zdroj neexistuje), hluk a sekačka / nedělní klid (`World.noise`),
  vyhlášky poštou a v drbech.
- [x] **M4.3 Soud a vězení** – trestné činy z katalogu, rejstřík jako pohled na záznamy, tresty, souhrnný časový skok a jeho následky.
- [x] **M4.5 Nové cesty k pověsti / respektu / karmě** – pomoc sousedům, úklid, vrácení věcí, přátelství
  s postavami, drobné dobré skutky (seznam v 3.5).
- [ ] **M4.6 Zbraně, lov a rybolov podle zákona** – zbrojní oprávnění, lovecký a rybářský lístek,
  povolenky (kurzy a zkoušky přes PC / střelnici), hajný a rybářská stráž v terénu, svědci hlásí
  pytláctví, kontroly dokladů a kufru policií, zabavení, trestné činy. *Hotovo, když:* pytlák s úlovkem
  na rameni je dopaden hajným a legální lovec s doklady a úlovkem v kufru projde kontrolou policie.
- [x] **M4.7 Katastr: koupě a prodej nemovitostí** (D2) – smyšlené parcely z `landuse`, katastr na úřadě / PC,
  vklad se lhůtou, hypotéka, pronájem, vlastnictví řídí kácení / sklizeň / chov. *Hotovo, když:* hráč koupí dům
  a les, přestěhuje se a v lese smí kácet. Nemovitosti jen v domácím katastru (rozhodnutí 6. 10. 2026).
- [ ] **M4.8 Návykové látky** (E8) – tabák, konopí, lysohlávky za volbou „Obsah pro dospělé“ (výchozí vypnuto),
  pěstování, sušení, zpracování, stavy v `BodyState`, zákony a důsledky bez glorifikace. *Hotovo, když:* s vypnutou volbou
  obsah ve hře není; se zapnutou má každý krok právní i tělesné důsledky.

### M5 – Obec a volný čas
- [ ] **M5.1 Stavebniny** – budova, obchod, materiál pro kutilství.
- [ ] **M5.2 Koupaliště a plavání** – úprava nádrže u potoka za stavebninami, plavání, sezóna, šatny.
- [ ] **M5.3 Hasiči** – zbrojnice, spolek, výjezdy k požárům, hasičské vozidlo.
- [ ] **M5.4 Hasičský sport** – minihra požární útok, soutěž jako událost.
- [ ] **M5.5 Systém událostí + zábava s kapelou** – kalendář akcí, plakáty, NPC účast, hudba, bar; nedělní mše (E9).
- [ ] **M5.6 Fotbal** – úprava hřiště, míč, kopaná s NPC, zápas jako událost.
- [ ] **M5.7 Skateboard** – vozidlo, animace, triky, dovednost.
- [ ] **M5.8 U-rampa za domem hráče** – rampa (hotová, nebo stavba ze stavebnin), triky na rampě.
- [ ] **M5.9 Rocková rádia** – Rock Radio a Radio Beat (případně Rock Zone) jako ověřené streamy
  v `data/radia.json`, právní poznámka v README; autorádio a vnitřní světlo v autě (E6).
- [ ] **M5.10 Místa v lese** (E10) – studánka, skautský tábor (letní událost), MTB bikepark s horským kolem a dovedností cyklistika.
- [ ] **M5.11 Doprava 2** (E7) – řidiči v AI autech, vesničané nastupují a vystupují, spolujezdec v autě hráče.
- [ ] **M5.12 Pouliční osvětlení a světelný smog** (E5) – lampy v obci, méně hvězd nad obcí, víc v lese.

### M6 – Létání
- [x] **M6.1 Dron** – ovládání, kamera, baterie, pravidla ÚVL a přestupky. *Hotovo: `Drone` (RigidBody3D se servo letovým modelem, vítr, režimy vzlet/let/RTH/přistání/pád/strom), `DroneModel` (2 modely, procedurální vizuál), `Permits` (registrace ÚVL + osvědčení A1/A3 přes eTest), 7 přestupků v `zakon.json`, prodej v Potravinách / eŠuplíku, stránka Letectví – ÚVL na PC (registrace, flotila, nabíjení, oprava), fotka do `user://fotky_dron/`, OSD telemetrie, save/load; otevřené body v PROJECT_LOG.*
- [x] **M6.2 Pozadí za okrajem mapy** – nízkorozlišený terén okolí, horizont, hranice letu. *Hotovo: `Surroundings` (LOD dlaždice okolí + díra pod katastrem, MultiMesh kužely lesa, fallback prstenec bez dat), `tools/surroundings.py` (DMR 5G ČÚZK + maska OSM → `surround_height/surface.bin`), `World.flight_bounds` (strop 1 500 m AGL, hranice 2 km za katastrem – rozhodnutí uživatele), mlha z řídne z výšky, F2 → Teleport → volná kamera; otevřené body v PROJECT_LOG.*
- [x] **M6.3 Letový model** – společný základ (vztlak, odpor, vítr, termika) pro paraglide a rogalo.
- [x] **M6.4 Motorový paraglide** – rozběh, řízení, přistání, pilotní průkaz.
- [x] **M6.5 Motorové rogalo** (a volitelně další stroje). *Hotovo: `Trike` (weight-shift hrazda – realisticky obrácená, přepínač v Nastavení), `Airfield` (polní dráha ~260 m, práh A x −440 / z 240, směr 30°, sklon ~1,4 %; rukáv + hangár + inzerát na ojetý trike 350 000 Kč), `pilot_ul`/`ul_registrace`/`ul_pojisteni` + škola 75 000 (eTest `ul` + 10 letů), přestupky `ul_*` v `zakon.json`, spolujezdec-vesničan (přátelství ≥ 60), F2 → Letiště; otevřené body (další stroje) v PROJECT_LOG.*

### M7 – Cesta na starostu (hlavní cíl hry, doplněk D4)
- [ ] **M7.1 Popularita a kritéria** – popularita z pověsti / respektu / přátelství, kritéria kandidatury, petice,
  protikandidát, záložka „Obec“ v deníku.
- [ ] **M7.2 Kampaň a volby** – poctivé nástroje i úplatky, pomluvy a podvody s rizikem odhalení, volební den.
- [ ] **M7.3 Vedlejší úkoly s větvením** – úkoly jako data, 15+ úkolů se 2–3 konci, řetězy postav, dopad na hlasy.
- [ ] **M7.4 Starostování** – rozpočet, projekty s viditelnou změnou, zastupitelstvo, sliby a klam, konce příběhu.

### Doporučené pořadí v kostce

```
M0 základy ──► M1 svět ──► M2 řemesla ──► M3 práce/PC ──► M4 zákon ──► M5 obec ──► M6 létání
   │                          ▲               ▲   │                       ▲
   └── M0.1 assety se používají všude          │   └── M3.4 PC: e-testy pro M4.1, M4.6, M6.1
                              M2 dává náplň prací v M3        M5.3 hasiči potřebují oheň z M2.2
   M2.8–2.10 zbraně, lov, náklad ──► M4.6 oprávnění, hajný a stráže
```

Doplňky od uživatele (30. 9. 2026): **M1.7** co nejdřív (před M3 – ať nové systémy už nestaví na domě hráče),
**M1.8** po M1.7, **M4.7** po M4.2, **M7** po M4 a M5.5 (M7.3 lze začít souběžně s M7.2; M6 létání je
volitelné a může jít až po M7).

Rychlé „radostné“ kroky, které lze vložit kdykoli po M0 bez rozbití pořadí: **M5.9 rádia**, **M5.7–5.8
skateboard a rampa**, **M5.6 fotbal**, **M5.12 osvětlení**.

Pořadí uvnitř M4 (6. 10. 2026): **M4.1 → M4.2 → M4.3** řetězem; **M4.5** souběžně s nimi; **M4.4** po M4.2; **M4.6** a **M4.8**
po M4.4 (navzájem souběžně); **M4.7** kdykoli po M4.2. Podrobně `prompts/roadmapa/README.md`.

### N – Nástroje (po M7)
Editor map, postav, objektů a úkolů (E11). První krok: úkoly jako JSON data (navazuje na M7.3) a editor nad nimi.
Prompty se napíšou až po M7.

---

## 6. Etapa 2 – Multiplayer (až po etapě 1)
Prompty: [`../prompts/roadmapa/V2_multiplayer/README.md`](../prompts/roadmapa/V2_multiplayer/README.md) – nejdřív revize
starých MP promptů (`prompts/03–10`, `priroda/05`), pak síť a doplňkové kroky V2.01–V2.05.
- Nahradit `World.notify` / `emit_game_event` / `sound` síťovými RPC (připravený úkol 03 z README).
- Synchronizace nových stavů: pokácené a zasazené stromy, pole, zvířata, ohně, události, interiéry.
- Sdílená ekonomika a zaměstnání, spolky (hasiči, fotbal) jako skupiny hráčů, společné zábavy.
- Zákon per hráč (už je navrženo per `id`), vězení vs. ostatní hráči (časový skok nelze → jiná mechanika).

---

## 7. Otevřené otázky pro uživatele
*Vyřešeno 29. 9. 2026:* RuneScape = činnosti ve světě (dřevo, oheň, rybaření, lov…), ovládání zůstává;
Radio Skyrock vypuštěno, místo něj Radio Beat (případně Rock Zone). Pytláctví (i lukem a kuší) je
záměrně možná, ale zakázaná cesta s vyšším ziskem a rizikem; legální cesta k masu je chov a porážka
domácích zvířat. Divočák se přepravuje jen ve dvou, autem nebo na ručním vozíku.

1. **Úroveň realismu zákona** – stačí zjednodušené pokuty a body, nebo i placení daní, pojištění
   (povinné ručení), STK?
2. ~~**Interiéry ostatních domů** – zamčené, nebo generované?~~ → *generované, stavěné jen zblízka (M1.8, doplněk D3) – hotovo: `InteriorGen` + `InteriorStreamer`, cizí domy zamčené s klepáním.*
6. **Bytový dům pro start (M1.7)** – který dům v obci (návrh: největší obytná budova s více podlažími)?
7. **Termín prvních voleb (M7.1)** – návrh po 60 herních dnech, další po 120; ok?
3. **U-rampa** – hotová od začátku, nebo si ji hráč postaví z materiálu ze stavebnin?
4. ~~**Létání** – jak vysoko a jak daleko za hranici katastru se smí letět?~~ → *rozhodnuto (M6.2): strop 1 500 m nad terénem, hranice 2 km za katastrem s měkkým odpuzením (`World.FLY_*`).*
5. **Úrovně dovedností** – souhlas s rozsahem 1–50?

---

## 8. Původní poznámky
Beze změny v [`požadavky.md`](požadavky.md).
