# M2.6 – Hospodářská zvířata: výběhy, péče, produkty, porážka

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 6/10
> Předpoklady: M0.2–M0.4, M2.4 (krmivo), M2.2 (vaření masa) · Navazují: M3.2 (práce na farmě), M4.4 (týrání – přestupek), M5.5 (zabijačka jako událost)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Hospodářská zvířata“ (včetně odstavce **Porážka vlastních zvířat**)
3. `ZVIRATA.md` – jak jsou zvířata postavená a laděná
4. `scripts/fauna/animal_specs.gd` (celý, 226 ř.) – tabulka druhů (rozměry, rychlosti, chody, zvuky)
5. `scripts/fauna/quadruped_model.gd` a `quadruped_rig.gd` – hlavičky a jak se staví model z parametrů
6. `scripts/fauna/animal.gd` – `setup`, `_think`, `_steer`, `_kinematic_move`, `_update_lod` (vzor chování a LOD)
7. `scripts/fauna/horse.gd` – hlavička; **stáj a výběh koně** z přírody 04 (grep `ohrad|vybeh|stable|paddock`) – vzor ohrady s kolizí
8. `scripts/fauna/bird.gd` – hlavička (model ptáka – pro slepice)

## 1. Proč
Uživatel: slepice, prasata, krávy, kozy a ovce na **oplocených** loukách. A zásadní rozhodnutí:
**legální cesta k masu je chov a porážka vlastních zvířat** (pytláctví je riskantní alternativa – M2.9).

## 2. Návrh
### 2.1 Druhy (nové řádky v `AnimalSpecs` nebo nová tabulka `FarmSpecs` – drž jeden styl)
| Druh | Model | Produkt | Péče | Cena mláděte / dospělého |
|---|---|---|---|---|
| Slepice (+ kohout) | pták (nový jednoduchý model – tělo, hřebínek, zobáček), klove zrní | vejce 0–1 / den (méně v zimě) | zrní, voda, kurník na noc | 120 / 250 Kč |
| Králík | malý čtyřnožec (zajíc – upravené proporce) | maso | seno, mrkev, kotec | 150 / 300 Kč |
| Prase | čtyřnožec (divočák bez srsti, růžové) | maso, sádlo | krmení 2× denně (brambory, zbytky), chlívek | 1 500 / 6 000 Kč |
| Koza | čtyřnožec | mléko 1–2 l / den, maso | tráva (pastva), voda | 1 800 / 3 500 Kč |
| Ovce | čtyřnožec (vlna – objemné tělo) | vlna (1× ročně stříhání V–VI), maso | pastva | 2 000 / 4 000 Kč |
| Kráva | velký čtyřnožec | mléko 10–15 l / den, maso | pastva + seno v zimě, dojení 2× denně | 15 000 / 30 000 Kč |

### 2.2 Výběhy a ohrady
- Nový `scripts/farm/pen.gd` (`class_name Pen`): ohrada = polygon (sloupky + 2–3 břevna/pletivo, MeshKit,
  kolize – vzor ohrada koně), branka (E = otevřít/zavřít; otevřená → zvířata mohou utéct). Přístřešek
  (kurník / chlívek / přístřešek pro ovce) jako jednoduchá stavba s kolizí.
- **Umístění:** za domem hráče na louce (výběh ~20 × 15 m, kurník, chlívek) – ověř volné místo (zahrada M2.4,
  kůň, rampa M5.8). Další výběhy si hráč může **postavit** později (M5.1 stavebniny) – připrav `Pen.create(polygon)`.
- Zvířata se drží uvnitř polygonu (steering jako `Animal`, ale „stanoviště“ = polygon výběhu), v noci jdou
  do přístřešku, za deště pod přístřešek. Rozbitý / otevřený plot → zvíře se zatoulá (vrátit: vést ho – akce
  `vest` zvíře následuje hráče jako kůň na povel – nebo nalákat krmením).

### 2.3 Péče a stavy (per zvíře: `hlad`, `zizen`, `zdravi`, `spokojenost`, `vek_dni`, `pohlavi`, `jmeno`)
- Akce: `nakrmit` (krmivo z inventáře: `zrni`, `seno`, zelenina z M2.4, `granule`), `napojit` (voda – konev / koryto
  jako objekt, který se plní), `podojit` (koza, kráva – kýbl → `mleko` l), `sebrat vejce` (v kurníku), `ostrihat`
  (ovce, nůžky), `pohladit` (spokojenost, XP malé). XP `chovatelstvi`.
- Hlad / žízeň rostou; hladové zvíře → méně produktů → hubne → nemocné → uhyne. **Zanedbání** (hlad > 2 dny)
  → karma −2 za den a (při zjištění sousedem / veterinou – háček M4.4) přestupek týrání `tyrani_zvirat`
  (246/1992 Sb. na ochranu zvířat proti týrání – `par` s „ověřit“).
- **Rozmnožování:** jen slepice (kvočna, kuřata) – zjednodušeně: kohout + ≥ 3 slepice → na jaře šance na 3–6 kuřat. Ostatní kupovat.
- Nákup: zvířata u farmáře (NPC – nový vesničan „chovatel“ v obci, nebo nabídka na úřadě / v Potravinách „inzerát“) –
  koupené zvíře se objeví ve výběhu. Prodej zpět výkupem.

### 2.4 Porážka vlastních zvířat (legální maso)
- Akce `porazit` jen na **vlastním** zvířeti, dospělém, ve výběhu / u domu, nástroj `nuz` (+ u prasete „zabijačka“
  – potřeba pomocníka: přátelství ≥ 40 s vesničanem z M0.6, nebo zaplatit řezníkovi 800 Kč). Porážka je rychlá
  a **nezobrazuje se naturalisticky** (ztmavení obrazovky 2 s + text), výsledek: maso (`maso_drubez`, `maso_kraliči`,
  `maso_veprove`, `sadlo`, `maso_kozi`, `maso_skopove`, `maso_hovezi`) podle hmotnosti.
- Maso se kazí (`perishable_h` z M0.2): lednička doma prodlouží (M1.4 – lednička jako úložiště: nová nabídka
  „Uložit do ledničky“), uzení (M2.2 udírna – otevřený bod), vaření na ohni / sporáku.
- **Zabijačka** (prase): malá událost na dvoře – přijdou 2–3 sousedé, výsledek i jitrnice / tlačenka (`tlacenka` už existuje),
  respekt `sousede` +5, pověst +2. Veterinární podmínky: poznámka v datech („domácí porážka pro vlastní spotřebu,
  prase – vyšetření na trichinely – ověřit“) – ve hře stačí volitelný krok „odnést vzorek na veterinu“ (háček).
- Prodej masa sousedům v malém OK, prodej „ve velkém“ (> 10 kg za týden) bez jatek → přestupek (háček M4.4).
- Týrání (zranění bez porážky, porážka bez nástroje / opakovaně neúspěšná) → karma −10, přestupek.

### 2.5 Ukládání
Ohrady (polygon, branka), zvířata (druh, stavy, pozice, jméno), produkty v přístřešku (vejce).

## 3. Minimum
Slepice + prase: výběh, kurník / chlívek, krmení, voda, vejce, porážka prasete s pomocníkem nebo řezníkem, maso do ledničky.

## 4. Hotovo, když
- Za domem je výběh s přístřeškem, koupená zvířata v něm žijí, jdou krmit / napájet / dojit / stříhat,
  dávají produkty; hlad škodí; otevřená branka = útěk; porážka dává maso; vše se ukládá.

## 5. Návrh checklistu ručních testů
1. Kup 3 slepice a kohouta → jsou ve výběhu za domem, v noci v kurníku.
2. Nakrm, napoj → druhý den vejce v kurníku, seber.
3. Nech je 3 dny bez krmení → hláška, méně vajec, karma v deníku horší.
4. Otevři branku → zvíře vyjde; vrať ho (vést / krmení).
5. Kup prase, krm týden; porážka → výzva k pomocníkovi / řezníkovi → maso, sádlo, tlačenka; sousedé přijdou.
6. Maso do ledničky; mimo ledničku se za pár dní zkazí.
7. Koza / kráva (pokud hotovo): dojení → mléko.
8. F5/F9 → zvířata a jejich stav zůstanou.

## 6. Závěr
README, `ZVIRATA.md` (hospodářská zvířata), `data/zakon.json`, VIZE odškrtnout, roadmapa README, PROJECT_LOG,
deník AI, commit „M2.6 Hospodářská zvířata: …“, checklist a čekat.
