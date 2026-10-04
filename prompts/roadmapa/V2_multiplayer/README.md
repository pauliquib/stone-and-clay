# V2 – Multiplayer (verze 2, až po celé etapě 1)

> Multiplayer se dělá **až po dokončení M0–M6** (rozhodnutí uživatele: „multiplayer až ve fázi 2“).
> Architektura na něj je připravená od úkolu 02 (World / LocalClient / InputState, `id` hráče, `notify`,
> `emit_game_event`) – každý krok etapy 1 ji musí dodržet (viz `../00_SPOLECNE.md`, kap. 4).

## Pořadí

| # | Soubor | Obsah |
|---|---|---|
| V2.00 | `00_revize_mp_promptu.md` | **nejdřív**: revize starých MP promptů `prompts/03–10` a `priroda/05` podle toho, co přibylo v etapě 1 (plánovací krok, jen dokumenty) |
| MP-03 … MP-10 | `../../03_sitovy_zaklad.md` … `../../10_server_zatez_vydani.md` | původní řada: síťový základ, lobby, auta, NPC/doprava/policie, předměty/ekonomika/fyziologie, úkoly/party/chat, ukládání/reputace, server a vydání – **po revizi V2.00** |
| MP-P5 | `../../priroda/05_priroda_v_multiplayeru.md` | kalendář, počasí, zvěř a koně přes síť (po MP-06) |
| V2.01 | `01_dovednosti_inventar_akce_mp.md` | dovednosti, jednotný inventář, nástroje, kontextové akce, náklad a vozík přes síť |
| V2.02 | `02_menitelny_svet_mp.md` | pokácené / zasazené stromy, zahrady, zvířata, ohně, stavby, interiéry – sdílený stav světa |
| V2.03 | `03_prace_zakon_doklady_mp.md` | práce, zákon, doklady, stráže, soud a vězení per hráč; svědci vidí všechny hráče |
| V2.04 | `04_spolecne_aktivity_mp.md` | nesení ve dvou, fotbal, požární útok, zábava, vyhlídkové lety, obchodování mezi hráči |
| V2.05 | `05_letani_skate_vykon_mp.md` | dron, paramotor, trike, skateboard přes síť + zátěžový test s novými systémy |

Doporučený průchod: **V2.00 → MP-03 → MP-04 → MP-05 → MP-06 → MP-07 → V2.01 → MP-08 → MP-09 → MP-P5 → V2.02 → V2.03 → V2.04 → V2.05 → MP-10**.
(MP-xx = původní soubory `prompts/03–10`; `10_server_zatez_vydani.md` až úplně na konec – zátěžový test musí zahrnout nové systémy.)

## Společné zásady pro V2
- Autorita podle `GAME_DESIGN.md` kap. 6.3: pohyb vlastní postavy a řízení vozidla u klienta, vše s hodnotou
  (peníze, inventář, XP, přestupky, stav světa) na serveru.
- Klient **žádá** (`rpc_id(1, "request_…")`), server **ověří** (vzdálenost, nástroj, úroveň, vlastnictví) a **rozhodne**,
  výsledek rozešle (`World.notify` → RPC, `emit_game_event` → RPC vlastníkovi).
- Oblast zájmu 400 m: měnitelný svět (stromy, záhony, zvířata, ohně) posílat jen v okolí + při připojení snapshot.
- Ukládání světa (host) odděleně od ukládání hráčů (profil) – navazuje na `09_ukladani_reputace.md`.
- Testy dělá uživatel (dva klienti na jednom PC + LAN) – každý prompt končí checklistem.
