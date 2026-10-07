# M8.6 – Pohyb člověka: biomechanika chůze, rovnováha a držení těla

> Roadmapa **M8 Realistický svět** · krok 6/19 · vlna 2
> Předpoklady: M8.1 · Navazují: M8.16 (únava, chlad → postoj), M8.17 (vesničané při práci)
> Zavádí API: `Gait` (nový `scripts/gait.gd`, používá `Humanoid`)

## 0. Než začneš – přečti
1. `00_SPOLECNE.md`, `M8_realismus/00_PRINCIPY.md` (kap. 8 – člověk, pohyb)
2. `scripts/humanoid.gd` – hlavička, `_process_impl` (`grep -n "func _process_impl" -A220` – dnešní animace podle rychlosti), `_leg_ik`, `_arm_ik`
3. `scripts/player.gd` – jak předává rychlost / stav postavě (`grep -n "humanoid\.\|\.speed\b\|crouch\|sprint" scripts/player.gd | head -40`)
4. `scripts/villager.gd` – chůze NPC (`grep -n "humanoid\|velocity" scripts/villager.gd | head`)
5. `scripts/fauna/quadruped_rig.gd` – vzor: fázový cyklus, stojná fáze bez klouzání, IK na terén (tam už to funguje – převezmi myšlenky)
6. `scripts/cargo.gd` (náklad na rameni – postoj), `scripts/body_state.gd` (`cold`, `wetness`, únava/výdrž)

## 1. Proč
Člověk je na obrazovce pořád – a dnes chodí jako panák: chodidla kloužou, na svahu prochází nohou terénem, krok nezávisí na rychlosti,
nese-li pytel, drží se stejně rovně. Lidské oko pozná špatnou chůzi okamžitě. Cílem není motion capture, ale **fyzikálně věrohodná
procedurální chůze**, která sedí k terénu, rychlosti, nákladu a stavu těla.

## 2. Co udělat
- **`scripts/gait.gd`** (`class_name Gait`, RefCounted, jedna instance na `Humanoid`): fázový cyklus chůze/běhu:
  - frekvence a délka kroku z rychlosti a výšky postavy (délka ≈ 0,4–0,45 × výška při chůzi, kadence 1,6–2,0 kroku/s; běh: letová fáze),
    **stojná fáze ~60 % při chůzi, ~35 % při běhu** (duty factor), přechod chůze ↔ běh kolem ~2 m/s (Froudovo číslo ~0,5),
  - **chodidlo ve stojné fázi pevně na zemi** (zamčený bod ve světě, žádné klouzání), ve švihové fázi oblouk nad terénem
    (výška zdvihu podle rychlosti a nerovnosti), dopad paty → odval → odraz špičkou (rotace chodidla),
  - **IK na terén:** paprsek / `height_fn(x,z)` pod oběma chodidly, pánev se sníží podle nižší nohy, chodidlo se natočí podle normály (svah),
    schody (interiéry) – krok nahoru o výšku stupně,
  - **těžiště a rovnováha:** pánev se kymácí do strany nad stojnou nohou (lateral shift ~3–5 cm), vertikální pohup (dvakrát za cyklus),
    rotace pánve a protirotace hrudníku, **protipohyb paží** (amplituda ∝ rychlost),
  - **náklon** do zatáčky (dostředivé zrychlení) a do kopce / z kopce (trup dopředu do kopce, z kopce kratší krok a zaklonění),
  - rozjezd / zastavení: krok navíc při prudkém zastavení, při otočce na místě přešlapování (ne rotace „na kolíku“).
- **Stav těla → postoj** (čte `BodyState` a `Cargo`, nic nemění): náklad na rameni (hmotnost) → úklon a kratší krok; únava (nízká výdrž)
  → shrbení, pomalejší kadence; chlad (`cold`) → ruce u těla, ramena nahoru, občasný třes; déšť → hlava skloněná; opilost — dnešní potácení
  ponech, jen ho postav na `Gait` (posun těžiště mimo opěrnou bázi = vrávorání a nápravný krok); obezita → širší báze.
- **Hlava a oči:** look-at na nejbližší zajímavý bod (mluvící postava, hráč, zvíře, auto) s omezením úhlů; stabilizace hlavy při chůzi
  (hlava se pohupuje méně než trup).
- **Dýchání:** jemný pohyb hrudníku, rychlejší po sprintu (z výdrže).
- **Napojení:** `Humanoid._process_impl` volá `Gait` pro nohy, pánev a paže **za přepínačem `gait`**; starý kód zůstane jako fallback.
  Hráč (3. osoba) i vesničané. Vesničané daleko (> 40 m) jen zjednodušeně (bez IK paprsků, LOD konstantou).
- **Výkon:** IK paprsky jen do 25 m od kamery; jinak výška z `Terrain.height_at`. ≤ 0,05 ms na postavu v plném detailu.
- Měřicí scéna: `ves_poledne` (víc vesničanů) – zapsat ms procesu.

## 3. Minimum
`Gait` s fázovým cyklem, stojnou fází bez klouzání, IK chodidel na svahu, kymácením pánve a protipohybem paží; přechod chůze/běh; náklad a únava mění postoj.

## 4. Hotovo, když
- Ve 3. osobě na svahu chodidla leží na terénu a při chůzi nekloužou; běh má letovou fázi; s pytlem na rameni postava viditelně nese váhu.

## 5. Návrh checklistu ručních testů
1. 3. osoba (V), pomalá chůze po rovině → chodidla stojí, neujíždějí.
2. Chůze napříč svahem → jedna noha níž, pánev nakloněná, chodidla rovnoběžně se svahem.
3. Rozběh → plynulý přechod do běhu, chvíle bez kontaktu se zemí.
4. Prudké zastavení a otočka na místě → přešlap, ne otočení na kolíku.
5. Srnec na rameni (M2.10) → úklon, kratší krok.
6. Vyčerpaná výdrž → shrbení; zima bez bundy → ruce u těla.
7. Opilý (‰ > 1) → vrávorání s nápravnými kroky.
8. Vesničan na návsi → chůze vypadá stejně věrohodně, hlava se otočí za hráčem.
9. Schody v bytovém domě → krok po stupních.
10. Přepínač Pohyb člověka vypnout → stará animace.

## 6. Závěr
`docs/SYSTEMS.md` (Pohyb postav), PROJECT_LOG, `docs/testy_M8.md`, commit „M8.6 Pohyb člověka: …“.
