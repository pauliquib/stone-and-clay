# M2.9 – Lov zvěře: zásah, dohledávka, vyvrhnutí, zvěřina, pytláctví

> Roadmapa „Život na vsi“ · **M2 Řemesla a venkov** · krok 9/10
> Předpoklady: M2.8 (zbraně), M0.5 · Navazují: M2.10 (přeprava úlovku), M4.6 (lovecký lístek, povolenka, hajný)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.2 „Lov zvěře (U2)“, „Lovecké zbraně“ (odstavec **Pytláctví je záměrně možná, ale zakázaná cesta**), „Kdo tě může chytit“
3. `ZVIRATA.md` – zvěř, vnímání, laditelné tabulky
4. `scripts/fauna/animal.gd` – `_perceive` (zrak, sluch, čich po větru), `_enter` (stavy), `_flight_distance`, `knock`, `_dead_update` (co se děje se sraženým zvířetem)
5. `scripts/fauna/animal_specs.gd` – druhy (srnec, srna, divočák, bachyně, sele, zajíc), hmotnosti
6. `scripts/fauna/herd.gd`, `scripts/fauna/fauna.gd` – `ENCOUNTER_*` (jak se zvěř objevuje kolem hráče), `TRANSIENT_GONE`
7. Myslivec, krmelec, posed z přírody 04 (grep `myslivec|krmel|posed` v `scripts/`)
8. `scripts/weapons.gd` (M2.8) – `shot_hit` událost, `hit_zone`
9. `scripts/local_client.gd` – stopy ve sněhu (`_snow_footprint`, `_tracks` – vzor pro krvavou stopu)

## 1. Proč
Lov je RuneScape činnost (Hunter) s vysokým ziskem a vysokým rizikem. **Legální** jen s puškou,
zbrojním oprávněním, loveckým lístkem a povolenkou (M4.6). Lukem / kuší nebo bez dokladů = **pytláctví**:
hra to umožní, ale nese důsledky (hajný, svědci, policie, soud, ztráta pověsti a karmy). Hra hráče
nenápadně vede k chovu (M2.6) jako bezpečné cestě k masu.

## 2. Návrh
### 2.1 Zásah a smrt zvířete
- `shot_hit` na zvíře → `Animal.shot(zone, energy, from)`: `hlava` / `srdce_plice` s dostatečnou energií →
  zvíře padne do pár metrů (srdce: uběhne 20–60 m, pak padne); `bricho` → uteče daleko (200–600 m), zalehne
  po 1–3 herních hodinách; `noha` → uteče, zpomalené. Energie šípu je menší → častěji postřelení.
  **Nenaturalisticky:** žádné detaily zranění, jen pád a ležící zvíře.
- **Postřelené zvíře** zanechává **krvavou stopu** (tmavé kapky na zemi – decaly jako stopy ve sněhu, po trase
  útěku, mizí za 2 herní h; v dešti rychleji). Po zalehnutí leží, při přiblížení na 15 m se může zvednout a utéct dál.
- **Postřelení** bez dohledání → karma −5 („postřelené zvíře trpí“), hajný to může najít (háček).
- Mrtvé zvíře = objekt `Carcass` (druh, hmotnost, čas úmrtí, `legalni: bool`, `vyvrzeno: bool`), ne v inventáři.

### 2.2 Lovecké techniky (využij existující vnímání zvěře)
- **Stopování:** zvěř nechává stopy (ve sněhu už jsou – přírodu 04 rozšiř na otisky v blátě po dešti – volitelné),
  **čekaná**: na posedu (z přírody 04 – když existuje, sedni si E; hráč na posedu = vyšší pozice, zvěř ho hůř vidí
  a cítí – v `_perceive` sniž dosah zraku a čichu, když je hráč > 3 m nad terénem), za soumraku srnci vycházejí na okraje.
- **Vítr:** HUD ikona směru větru při míření (šipka – `wind_vector`); hráč po větru = zvěř cítí dřív (už je v `_perceive`).
- **Vábnička** (volitelně): na srnce v říji (VII–VIII) – zvuk, srnec přijde blíž.

### 2.3 Vyvrhnutí a zpracování
- Akce `vyvrhnout` na `Carcass` (nástroj `nuz`, 30–90 s, `myslivost` XP 20–60): sníží hmotnost (~20 %), bez
  vyvrhnutí se maso po 3 herních h znehodnotí (v létě dřív). Obrazovka se krátce ztmaví – **bez naturalismu**.
- Doma (dvůr / kůlna): akce `zpracovat` → `zverina_srnci`, `zverina_divocak`, `zverina_zajic` (kg podle hmotnosti)
  + trofej (`parozky` – ozdoba do domova, volitelné).
- Přeprava domů – **M2.10** (rameno, auto, motorka, vozík; divočák jen ve dvou / autem / vozíkem). Tady jen:
  `Carcass` jde „zvednout“ G (když M2.10 ještě není, připrav jednoduché nesení na rameni jen pro zajíce a srnce).

### 2.4 Legalita a prodej
- `World.is_legal_hunt(id, weapon, species, pos) -> Dictionary {ok: bool, reasons: []}`:
  zbraň puška (luk/kuše → nikdy legální), `has_permit(id, "zbrojni")`, `has_permit(id, "lovecky_listek")`,
  `has_permit(id, "povolenka_lov")` (M4.6), doba lovu druhu (tabulka `HUNT_SEASONS` – orientačně: srnec
  16. 5. – 30. 9., srna a srnče 1. 9. – 31. 12., divočák celoročně, zajíc 1. 11. – 31. 12. a jen při společném honu –
  zjednodušeně jen listopad–prosinec; do `data/lov.json` s poznámkou „vyhl. 245/2002 Sb. – ověřit“),
  lovit se nesmí v noci s výjimkou divočáka, ne v obci, ne z auta.
- Nelegální úlovek → `Carcass.legalni = false`. Samotný výstřel na zvěř bez práva → **pytláctví** (`pytlactvi`,
  40/2009 Sb. § 304 – trestný čin), ale zjistí se jen: svědkem (vesničan / myslivec v dohledu nebo doslechu výstřelu
  a pak uvidí zvíře / hráče s úlovkem), hajným (M4.6), policií při kontrole (M4.6 – kufr, rameno). Teď: svědci + háčky.
- **Prodej:** legální zvěřina s „dokladem o původu“ (předmět `doklad_puvod` vzniká automaticky u legálního úlovku)
  → hospoda / Potraviny za tržní cenu. **Nelegální** zvěřina → „překupník“ (nový NPC, večer za hospodou nebo u
  pálenice – dá o 30 % víc než tržní cena, ale šance 10 % na „prásknutí“ → přestupek) nebo sousedé, kteří se
  neptají (menší množství, respekt `stamgasti` +1, karma −1).
- Karma: legální lov 0, pytláctví −3 za kus, postřelení a nedohledání −5; srážka zvěře autem – vzít si ji = pytláctví
  (přivlastnění – z přírody 04 myslivec pro ni přijede).

### 2.5 Ukládání
`Carcass` (pozice, druh, stav) – mrtvá zvířata mimo domov po 2 herních dnech zmizí; zpracované maso je v inventáři / ledničce.

## 3. Minimum
Zásah → pád / útěk s krvavou stopou, vyvrhnutí, zvěřina, legalita (luk = vždy pytláctví), svědci.

## 4. Hotovo, když
- Zvěř jde ulovit puškou i lukem; zásahové zóny mají smysl; postřelené zvíře jde dohledat po stopě.
- Vyvrhnutí a zpracování dají maso; nelegální lov je pytláctví se svědky a karmou; prodej legální i „bokem“.

## 5. Návrh checklistu ručních testů
1. F2 → cheat zbrojní oprávnění + kup pušku; F2 → Teleport → k zvěři (srnci), večer, vítr do tváře.
2. Plížení (Ctrl) → zvěř tě vidí později; po větru tě ucítí dřív.
3. Míření (pravé tl.) na srnce 80 m, zásah na komoru → uběhne kus a padne.
4. Zásah do břicha → uteče, krvavá stopa na zemi, dohledej zalehlé zvíře.
5. E / akce Vyvrhnout (nůž) → ztmavení, hláška, hmotnost menší.
6. Luk: zastřel zajíce → vždy pytláctví; blízko vesničana → přestupek, karma dolů.
7. Myslivec v doslechu výstřelu mimo dobu lovu → přijde a řeší to.
8. Prodej legální zvěřiny v hospodě s dokladem; nelegální u překupníka – víc peněz, občas průšvih.

## 6. Závěr
README (Systémy → Lov), `ZVIRATA.md`, `data/lov.json`, `data/zakon.json`, VIZE odškrtnout, roadmapa README,
PROJECT_LOG, deník AI, commit „M2.9 Lov zvěře: …“, checklist a čekat.
