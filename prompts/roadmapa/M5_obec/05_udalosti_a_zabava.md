# M5.5 – Kalendář událostí a zábava s kapelou

> Roadmapa „Život na vsi“ · **M5 Obec a volný čas** · krok 5/9
> Předpoklady: M1.5 (sál v hospodě), M3.4 (web obce, pošta), M0.6 (respekt) · Navazují: M5.4 (soutěž), M5.6 (zápas), M2.6 (zabijačka) – všechny se zapíšou do kalendáře

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md` (kap. 3 – kapela se smyšleným názvem, hudba vlastní / CC0)
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.5 „Zábava s kapelou (17)“
3. `scripts/priroda/village_events.gd` (celý, 801 ř. – čti po částech: `EVENTS`, `_active_at`, `_place_day`, `event_hours`, `_build`, `_destroy`, `_build_hody`) – **tohle rozšiřuješ**
4. `scripts/radio_music.gd` (213 ř.) – generovaná hudba (Rádio Kovadlina / Pohoda) – **znovu použij pro kapelu**
5. `scripts/place.gd` – hospoda, obsluha, `FRIDAY_EXTRA` (přidání hostů), `scripts/villager.gd` – jak poslat vesničana na místo
6. `scripts/computer_ui.gd` (web obce – kalendář akcí), `scripts/humanoid.gd` (animace – tanec přidáš)
7. `scripts/dialog.gd` – témata (pozvání na zábavu)

## 1. Proč
Uživatel: „občasný event – zábava s kapelou“. Obecně potřebujeme **kalendář akcí**, do kterého se zapojí
zábavy, hody, zápasy, hasičská soutěž, zabijačky… a který uvidí hráč na plakátech a webu obce.

## 2. Co udělat
### 2.1 Kalendář událostí (rozšíření `VillageEvents`)
- Tabulka `EVENTS` rozšiř o **plánované opakované akce**: `"zabava": {"nazev": "Taneční zábava", "misto": "hospoda_sal",
  "kdy": {"weekday": 6, "nth": [1, 3], "months": [1,2,3,4,5,9,10,11]}, "od": 20.0, "do": 3.0, "vstupne": 150, ...}`
  a jednorázové / generované (hasičský bál v únoru, letní zábava pod širým nebem na hřišti v červenci, fotbalový zápas
  každou 2. neděli (M5.6), hasičská soutěž (M5.4), posvícení / hody (už je)).
- API: `upcoming(days: int) -> Array` (pro plakáty a web), `is_active(id)`, `register(id, def)` (další kroky přidají své akce).
- **Plakáty:** na nástěnce u úřadu, u Potravin a v hospodě (Label3D / quad s textem – „TANEČNÍ ZÁBAVA · hraje skupina
  Traktor Blues · sobota 20:00 · sál hostince“ – **smyšlené kapely**: „Traktor Blues“, „Zlatá Kovadlina“, „Vesnický
  Expres“, „Kulatá Šestka“), E u plakátu = detail. Web obce a pošta (M3.4) ukazují totéž.

### 2.2 Zábava v sále hospody (nebo pod širým nebem na hřišti v létě)
- **Scéna** (staví se při aktivaci jako ostatní události): pódium s kapelou (4 NPC Humanoidi s nástroji – kytara, basa,
  bicí, klávesy – MeshKit modely, animace hraní), světla (barevné `OmniLight3D`, blikání do rytmu), bar (výčep – obsluha
  hospody + pomocník), stoly, **parket**.
- **Hudba:** `RadioMusic` generátor → styl „dechovka / country / rock“ podle kapely, přehrávat 3D ze stage (AudioStreamPlayer3D),
  hlasitě; pauzy mezi sety (20 min hudba / 10 min pauza).
- **Návštěvníci:** 15–30 vesničanů (večer přicházejí 20–22 h, odchází 1–3 h, opilejší); dav z `villager` – posílat na
  parket / k barům / ke stolům. Tanec: jednoduchá animace (pohupování, otáčení v páru – 2 NPC proti sobě).
- **Hráč:** vstupné u dveří (pokladna), tančit (klávesa – akce „tanec“ poblíž parketu → animace, `kondice` XP, přátelství +2
  s partnerem – vyzvat postavu k tanci T „zatančíme si?“), pít, mluvit.
- **Rvačka:** opilí vesničané (> 1,5 ‰ – NPC nemají BodyState, použij náhodu podle času a počtu piv) se občas pohádají;
  hráč může urovnat (T „klid, pánové“ – `vyrecnost` → šance) → respekt +3, nebo se přidat (urážka / strkání) →
  `vytrznictvi` (M4.4), policie. Hráč opilý + vyprovokovaný → stejné.
- **Po zábavě:** ráno nepořádek (odpadky, lahve) – úklid = dobrý skutek (M4.5) nebo práce (M3.2 obecní údržba).
  Opilý kamarád → doprovod domů (M4.5).
- Respekt: návštěva `mladez` +1, `stamgasti` +1; tancování `mladez` +1.

### 2.3 Hasičský bál (varianta)
Únor, pořádá SDH (M5.3): vstupné, **tombola** (hráč si koupí lístky, o půlnoci losování – ceny: sele (M2.6!), dort,
slivovice, poukaz do stavebnin), předtančení hasičů. Respekt `hasici`.

## 3. Minimum
Kalendář + plakáty + taneční zábava v sále s kapelou, hudbou, návštěvníky a tancem. Rvačky a bál do otevřených bodů.

## 4. Hotovo, když
- Na plakátech a webu obce jsou nadcházející akce; zábava se v daný den postaví, kapela hraje, lidé přicházejí,
  tančí, pijí; hráč může tančit a vyzvat postavu; akce se po skončení uklidí.

## 5. Návrh checklistu ručních testů
1. Nástěnka u úřadu → plakát na nejbližší zábavu; web obce → kalendář.
2. F2 → Datum na den zábavy 21:00 → sál: kapela, světla, hudba, 15+ lidí.
3. Vstupné; tanec (klávesa) na parketu; T „zatančíme si?“ → postava tančí s tebou.
4. Pauza mezi sety → hudba ztichne, kapela u baru.
5. 02:00 → opilejší hosté, odcházejí; rvačka → urovnej.
6. Ráno odpadky → uklid → karma.
7. Hasičský bál v únoru (pokud hotovo) → tombola o půlnoci.

## 6. Závěr
README (Systémy → Události), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M5.5 Kalendář událostí a zábava: …“, checklist a čekat.
