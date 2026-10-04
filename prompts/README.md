# Prompty pro vývoj – Dukelčice (singleplayer → multiplayer)

> **Nová hlavní řada: [`roadmapa/`](roadmapa/README.md) – „Život na vsi“ (etapa 1, singleplayer, milníky M0–M6).**
> Multiplayer (úkoly 03–10 níže a `priroda/05`) patří až do **verze 2** – viz
> [`roadmapa/V2_multiplayer/README.md`](roadmapa/V2_multiplayer/README.md), kde je i pořadí a revize těchto promptů.

Každý soubor je samostatné zadání pro **novou session** Claude Code (celé kontextové okno).
Zadávej je **postupně podle čísla** – každý navazuje na předchozí. Stačí do nové session napsat
např.: *„Přečti a proveď `prompts/03_sitovy_zaklad.md`.“*

Každý prompt začíná společným kontextem (co přečíst, obecná pravidla) a končí záznamem
do `PROJECT_LOG.md` + commitem, takže další session naváže z logu.

**Průběh každého úkolu (platí automaticky, je v pravidlech každého promptu):**
1. Agent programuje; hru ani testy nespouští (jen na výslovný pokyn uživatele).
2. Zapíše log, commitne a vypíše **checklist ručních testů (max. 10)**, pak čeká.
3. Uživatel testy projde a pošle výsledky (stačí „1 OK, 2 chyba: …“).
4. Agent nahlášené chyby opraví, doplní log a commitne.

| # | Soubor | Obsah | Verze GDD |
|---|---|---|---|
| 01 | `01_dokonceni_singleplayeru.md` | ověření úkolů, AI doprava, noc, výkon, README | 0.2 |
| 02 | `02_refaktor_architektury.md` | rozdělení `main.gd` na svět/klient, více hráčů, InputState | 0.3 příprava |
| 03 | `03_sitovy_zaklad.md` | `net.gd`, host/join, handshake, pohyb hráčů, čas | 0.3 |
| 04 | `04_menu_lobby.md` | hlavní menu, lobby, LAN, profil, odpojení | 0.3 |
| 05 | `05_auta_v_mp.md` | autorita řidiče, spolujezdci, poškození | 0.4 |
| 06 | `06_npc_doprava_policie_mp.md` | NPC/doprava/policie na serveru, oblast zájmu 400 m | 0.4 |
| 07 | `07_predmety_ekonomika_fyziologie_mp.md` | předměty, inventář, nákupy, BodyState na serveru | 0.4 |
| 08 | `08_ukoly_party_chat.md` | úkoly per hráč, party, co-op úkoly, chat, emoty | 0.5 |
| 09 | `09_ukladani_reputace.md` | ukládání světa a hráčů, reputace | 0.5–0.6 |
| 10 | `10_server_zatez_vydani.md` | dedikovaný server, zátěžový test, export, lokalizace | 1.0 |

Když některý úkol nedoběhne celý, nezačínej další – zadej ho znovu s poznámkou
„pokračuj podle otevřených bodů v PROJECT_LOG.md“.

**Příroda** (zvěř, ptáci, hmyz, kůň, počasí, roční období) má vlastní navazující prompty ve složce
[`priroda/`](priroda/README.md) – lze je zadávat nezávisle na číslované řadě (kromě `05`, ten až po úkolu 06).
