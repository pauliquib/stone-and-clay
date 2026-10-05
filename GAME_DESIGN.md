# Dukelčice – herní dokument (Game Design Document)

> Verze 0.1 · 2026-09-29 · stav: základní definice hry a multiplayeru
> Technické podrobnosti (formáty dat, ovládání, ladicí parametry) viz `README.md`.

---

## 1. Vize

**Dukelčice** je open-world simulátor života na české vesnici, postavený na věrné 3D mapě
skutečného katastru obce Dukelčic (terén DMR 5G, budovy z DMP 1G, silnice z OSM, ortofoto ČÚZK).
Hráč se volně pohybuje pěšky i autem, plní drobné vesnické úkoly (cigarety pro dědu, páteční
pivo, slivovice pro starostu, mejdan na chatě…) a nese si jejich následky – alkohol v krvi,
plný žaludek, policejní kontroly, poškozené auto.

**Tón:** laskavý humor a nadsázka s realistickými systémy pod povrchem. Hra nic nemoralizuje,
ale důsledky jsou skutečné: kdo řídí opilý, riskuje nehodu a policii; kdo to přežene,
zvrací nebo usne v příkopu.

**Pilíře**

1. **Skutečné místo** – každý dům, cesta a les odpovídá realitě; orientace „jako doma“.
2. **Uvěřitelná simulace** – fyzika pohybu a aut, fyziologie (Widmark, trávení, nikotin),
   denní doba, doprava a policie fungují nezávisle na hráči.
3. **Příběhy z následků** – nejzajímavější zážitky vznikají kombinací systémů, ne skriptem.
4. **Spolu je to lepší** – hra je navržená tak, aby se dala hrát s kamarády (kap. 6).

## 2. Základní parametry

| | |
|---|---|
| Žánr | open-world sandbox / life-sim s úkoly, humor |
| Engine | Godot 4.3 (Forward+, Vulkan), GDScript |
| Pohled | 1. i 3. osoba (přepínání V) |
| Svět | katastr Dukelčic + katastry 5 okolních obcí, ~11,3 × 7,5 km detailu, bez načítacích obrazovek |
| Hráči | singleplayer + kooperativní multiplayer 2–8 hráčů |
| Platforma | PC (Linux, Windows), klávesnice+myš i ovladač |
| Délka sezení | 30–120 min („jeden večer ve vsi“) |
| Cílový výkon | 60 FPS na GTX 1050-třídě při 1080p |

## 3. Herní smyčka

```
 vyber úkol (hospoda / obchod / úřad / děda …)
        │
        ▼
 obstarej věci  ──►  cestuj (pěšky / autem / s kamarádem)  ──►  splň cíl
        ▲                     │ jídlo, pití, kouření, nehody, policie     │
        │                     ▼                                          ▼
   peníze, reputace   ◄──  důsledky (‰, zdraví, škody, pokuty)  ◄──  odměna
```

- **Mikro (sekundy):** pohyb, řízení, interakce (F), jídlo a pití.
- **Střední (minuty):** úkol s podmínkami (nic nepoškodit, nezranit se, nenechat se chytit,
  dojít pěšky, nezvracet, stihnout čas).
- **Makro (herní den):** denní cyklus 1 h = 2 min reálně; peníze, reputace ve vsi,
  zdraví a hmotnost postavy se přenáší mezi dny.

## 4. Herní systémy (stav)

| Systém | Popis | Stav |
|---|---|---|
| Pohyb hráče | zrychlení, sprint s výdrží, proměnný skok, coyote time, skluz, přikrčení | hotovo |
| Auta | VehicleBody3D, momentová křivka, automat, spojka, ruční brzda, povrchy, deformace | hotovo |
| Fyziologie | Widmark + vstřebávání, jídlo, kalorie → BMI, nikotin, nevolnost, otrava | hotovo |
| Opilost | efekty kamery a ovládání podle ‰ (`drunk_fx.gd`) | hotovo |
| Čas | den/noc, slunce, měsíc, světla (`clock.gd`) | hotovo |
| NPC | 28 vesničanů, 7 psů, hostinský, děda, starosta, myslivec | hotovo |
| Doprava + policie | AI auta (překážky v pruhu, objíždění, přednost), hlídka, pronásledování, silniční kontrola – policista dojde k okénku a dá dýchnout | hotovo |
| Místa | hospoda, Potraviny, pálenice, vinný sklep, Myslivecká chata, úřad, domov | hotovo |
| Úkoly | 6 úkolů s kroky a podmínkami (`quests.gd`), test `--questtest` | hotovo |
| Kontextové akce a nástroje | nástroj v ruce (Q, 1–5), výběr cíle, akce s průběhem, výdrží, XP a selháním (`actions.gd`); zatím jen testovací akce | základ |
| Ekonomika | peníze, ceny, pokuty, výplata za úkoly | základ |
| Zaměstnání | katalog prací `data/prace.json`, pohovor, směny s docházkou, pracovní úkoly (akce M0.4 / dojít), napomenutí → výpověď, týdenní výplata (čistá mzda zjednodušeně), deník J → Práce (`jobs.gd`, M3.1); zatím testovací „Pomocník v hospodě“ | **základ (M3.1)** |
| Reputace | vztah vsi k hráči (ovlivňuje ceny, úkoly, ochotu NPC) | **plánováno** |
| Respekt komunit, karma, přátelství | šest komunit (−100…100), skrytá karma jako „štěstí“, přátelství s postavami (M0.6) | **hotovo (M0.6)** |
| Uložení hry | stav hráče, času, aut a úkolů | **plánováno** |
| Multiplayer | viz kap. 6 | **plánováno** |

## 5. Základní pravidla

### 5.1 Hráčská postava
- Atributy: **zdraví** (0–100), **výdrž**, **hmotnost** (→ BMI, rychlost), **‰ alkoholu**,
  **nikotin/chuť**, **nevolnost**, **peníze**.
- Smrt/otrava ani bezvědomí hru nekončí: hráč se probudí doma (č. 221) nebo v nemocnici,
  přijde o část peněz a aktivní úkol selže.

### 5.2 Alkohol a řízení
- Stupně (`body_state.gd`): střízlivý < 0,05 ‰ < mírně ovlivněný < 0,5 ‰ < podnapilý < 1,0 ‰
  < opilý < 1,5 ‰ < silně opilý < 2,5 ‰ < těžká opilost < 3,5 ‰ < otrava.
- Policie při kontrole měří dechem; nad 0,0 ‰ pokuta, nad 1 ‰ zabavení auta a selhání úkolu.
- Opilost zhoršuje ovládání (zpoždění, kmitání řízení, rozmazání), ne jen obraz.

### 5.3 Úkoly
- Vždy jeden aktivní úkol na hráče; zadávají je místa a postavy.
- Každý úkol má **kroky**, **cíl na kompasu/mapě** a **podmínky**; porušení = selhání,
  úkol lze zkusit znovu.
- Odměna: peníze + reputace; některé úkoly odemykají další (řetězy).

### 5.4 Ekonomika
- Příjmy: úkoly, drobné nálezy (dukáty, hřiby, jablka k prodeji), **práce** (M3.1: hodinová mzda za přítomnost
  na pracovišti a plnění úkolů, výplata týdně v pátek u zaměstnavatele, čistá zjednodušeně −15 %, prémie 0–20 %
  podle hodnocení). Pozdní příchod, opilost, pití v práci, odchod a absence = napomenutí, 3 napomenutí nebo
  zadržení policií = výpověď. Hlavní cesta, jak utáhnout nájem bytu (M1.7).
- Výdaje: pití, jídlo, cigarety, benzín, opravy auta, pokuty.
- Ceny jsou pevné, reputace je upravuje ±20 %.

### 5.5 Svět
- Den trvá 48 min reálně (TIME_SCALE 30). Otevírací doby (`place.gd`): hospoda 10–2,
  obchod 6–21, pálenice 8–22, sklep 12–24, úřad 7–17, chata a domov nonstop.
- Předměty ve světě se obnovují každý herní den.
- Škody na autech/majetku se pamatují do konce dne.
- Kalendář je skutečný (výchozí dnešní datum), slunce a měsíc astronomicky; počasí a roční období
  (vegetace, sníh, teploty) podle klimatu střední Moravy. Herní menu F2 umožní datum, čas a počasí změnit.
- Zvěř (srnci, divočáci, zajíci), ptáci a hmyz žijí hlavně v lesích a na jejich okrajích; kůň hráče je
  dopravní prostředek bez řidičáku (v MP zvěř a počasí simuluje server – viz prompty `prompts/priroda/`).

## 6. Multiplayer

### 6.1 Cíle
- **Kooperace** 2–8 hráčů v jednom světě (celý katastr), drop-in / drop-out kdykoli.
- Hraje se s kamarády, ne proti cizím → priorita je **jednoduchost a plynulost**, ne
  neprůstřelná ochrana proti cheatování.
- Singleplayer je jen „server s jedním hráčem“ – jedna kódová cesta.

### 6.2 Architektura

- **Model: autoritativní hostitel (listen server)**, volitelně dedikovaný headless server
  (`godot --headless -- --server --port=7777`).
- Transport: Godot **ENetMultiplayerPeer** (UDP), výchozí port **7777**; připojení přes
  IP / LAN. Později Steam Networking (NAT průchod, pozvánky).
- Replikace: `MultiplayerSpawner` (vznik/zánik hráčů, aut, předmětů) +
  `MultiplayerSynchronizer` (stav) + RPC pro jednorázové události.
- **Mapa se nepřenáší**: všichni mají stejná data v `data/`; při připojení klient pošle
  hash `map.json` + verzi hry, při neshodě je odmítnut.

```
          ┌───────────── HOST / SERVER (autorita) ─────────────┐
          │ čas, počasí · NPC, doprava, policie · předměty       │
          │ úkoly · ekonomika · fyziologie hráčů · validace      │
          └──────▲──────────────────────┬──────────────────────┘
      vstupy,    │                      │ snapshoty 20 Hz (jen v okolí),
      pozice auta│                      │ RPC události
          ┌──────┴──────┐  ┌──────────┐ ┌──────────┐
          │  klient A   │  │ klient B │ │ klient C │  … až 8
          └─────────────┘  └──────────┘ └──────────┘
```

### 6.3 Kdo má nad čím autoritu

| Objekt | Autorita | Synchronizace |
|---|---|---|
| Vlastní postava (pohyb) | **klient** (predikce, okamžitá odezva) | pozice/rotace/animace 20 Hz, server kontroluje rychlost a teleporty |
| Auto s řidičem | **klient řidiče** (fyzika běží u něj) | transform + rychlost + stav kol 20 Hz; ostatní interpolují |
| Prázdné auto, bedny, míč | server | 10 Hz, při klidu nic |
| Fyziologie (‰, zdraví, nikotin…) | server | hodnoty 2 Hz jen vlastníkovi, stupeň opilosti všem (animace) |
| NPC, psi, doprava, policie | server | 10 Hz, jen v okruhu zájmu |
| Předměty ve světě | server | spawn/despawn; sebrání = žádost → potvrzení |
| Úkoly, peníze, inventář | server | RPC při změně |
| Čas dne | server | synchronizace 1×/10 s, klienti extrapolují |
| Poškození aut | server (z hlášení řidiče) | RPC při kolizi |

Důvod „klientské“ autority pro pohyb a řízení: VehicleBody3D a CharacterBody3D nejsou
deterministické, plná serverová predikce + rollback by byla pro kooperativní hru zbytečně
složitá. Server jen kontroluje hrubé nesmysly (rychlost > limitu, teleport > 20 m).

### 6.4 Síťový provoz

- **Tick** serveru 60 Hz fyzika, síťové snapshoty **20 Hz**; klienti interpolují
  s bufferem **100 ms**, auta navíc extrapolují podle rychlosti.
- **Oblast zájmu:** katastr je velký → každý klient dostává stav NPC, aut a předmětů jen
  v okruhu **400 m** (filtr viditelnosti `MultiplayerSynchronizer`). Ostatní hráči jsou
  viditelní vždy (pozice 2 Hz mimo okruh, pro mapu a kompas).
- **Simulace NPC mimo hráče:** v okolí libovolného hráče plná, jinde zjednodušená (jako dnes
  „boti bez fyziky daleko od hráče“).
- Odhad: 8 hráčů × ~40 objektů v okolí × 20 Hz ≈ 30–60 kB/s na klienta.

### 6.5 Pravidla kooperace

- **Úkoly jsou osobní**, ale ostatní se mohou **přidat do party** (pozvánka) – pak mají
  společný postup, podmínky platí pro všechny a odměnu dostane každý.
- Úkol **„Mejdan na chatě“** je skupinový: odměna roste s počtem účastníků.
- **Auta:** až 5 hráčů v jednom autě (řidič + spolujezdci). Spolujezdec ovládá rádio
  a okno, může střídat řidiče jen když auto stojí.
- **Policie** řeší řidiče; spolujezdci mohou být „svědky“ (vliv na reputaci).
- **Sdílený svět:** předmět sebere ten, kdo je první; otevírací doby a čas jsou společné.
- **Čas nelze zrychlit ani pauzovat** v multiplayeru (spánek doma = jen pro singleplayer
  nebo když spí všichni).
- **Hlasovou komunikaci** hra neřeší (Discord); je **textový chat** a **emote** (mávnutí,
  přípitek, ukázat směr) – přípitek dvou hráčů je interakce.
- **Přátelská srážka:** hráči do sebe mohou strkat a porazit se autem; zranění ano,
  smrt jiného hráče jen s pravidlem serveru `pvp_damage = true` (výchozí vypnuto).

### 6.6 Připojení a lobby

1. Hostitel: *Hrát → Hostovat* (jméno, heslo, max. hráčů, pravidla).
2. Klient: *Připojit → IP:port* (nebo seznam LAN serverů přes UDP broadcast).
3. Handshake: verze hry, hash mapy, jméno, vzhled postavy → server přidělí spawn
   (dům č. 221 nebo u hostitele).
4. Odpojení: postava zmizí, její auto zůstane zaparkované; aktivní úkol se pozastaví.
   Odchod hostitele = uložení a konec relace (migrace hosta neřešíme).

### 6.7 Uložení

- Svět (čas, auta, škody, stav předmětů) ukládá **server** do `user://saves/<svet>.json`.
- Hráč (peníze, inventář, úkoly, hmotnost, reputace) se ukládá **na serveru podle
  jména/ID hráče** – kamarád se vrací ke svému postupu v daném světě.

### 6.8 Dopad na současný kód

| Soubor | Změna |
|---|---|
| `main.gd` | ✔ rozděleno na `world.gd` (`World`, server) a `local_client.gd` (`LocalClient`: HUD, kamera, efekty, vstup) – úkol 02; zbývá spawn hráčů přes `MultiplayerSpawner` |
| `player.gd` | ✔ vstup přes `InputState`, kamera jen u lokálního hráče (úkol 02); vstup jen pro `is_multiplayer_authority()`; vzdálení hráči = „puppet“ s interpolací |
| `car.gd` | autorita = řidič, `set_multiplayer_authority()` při nástupu |
| `body_state.gd` | běží na serveru pro každého hráče; klient jen zobrazuje |
| `quests.gd` | ✔ úkoly per hráč, `emit_game_event(player_id, …)` (úkol 02); party; `emit_game_event` → RPC na server |
| `npc.gd`, `traffic.gd`, `police.gd` | simulace jen na serveru, klienti jen interpolují |
| `clock.gd` | serverový čas + synchronizace |
| nový `net.gd` | autoload: host/join, handshake, lobby, chat |

## 7. Plán vývoje

| Fáze | Obsah |
|---|---|
| **0.2 – dokončení SP** | ověření úkolů, noc a světla, výkon (draw calls), README |
| **0.3 – síťový základ** | `net.gd`, host/join, 2 hráči chodí po mapě, synchronizace času |
| **0.4 – svět v MP** | NPC, doprava, policie, předměty a auta přes síť, oblast zájmu |
| **0.5 – kooperace** | party, sdílené úkoly, spolujezdci, chat a emoty, ukládání |
| **0.6 – obsah** | reputace, nové úkoly (hasiči, pouť, sklizeň), víc NPC s rozvrhem dne |
| **1.0** | dedikovaný server, Steam, lokalizace (CZ/EN), vyladění |

## 8. Otevřené otázky

- Kolik zjednodušit fyziologii pro kooperaci (sdílené rundy v hospodě)?
- Chceme volitelný režim „policista“ pro jednoho z hráčů (asymetrický multiplayer)?
- Steam vs. vlastní relay pro hraní přes internet bez přesměrování portů.
- Vliv počasí na přilnavost aut, promoknutí a prochladnutí hráče – připraveno v `prompts/priroda/`.
