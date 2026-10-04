# M4.2 – Správní řízení na úřadě: pokuty, splatnost, exekuce, žádosti

> Roadmapa „Život na vsi“ · **M4 Zákon a společnost** · krok 2/6
> Předpoklady: M0.5, M4.1 (`Permits`), M3.4 (banka, pošta), M1.5 (interiér úřadu) · Navazují: M4.3 (soud), M4.4 (povolení ke kácení)

## 0. Než začneš – přečti
1. `prompts/roadmapa/00_SPOLECNE.md`
2. `docs/VIZE_A_ROADMAPA.md` – kap. 4.4
3. `scripts/law.gd` + `data/zakon.json` – `misto` (`na_miste` | `spravni_rizeni` | `soud`), `records`, `unpaid_fines`
4. `scripts/permits.gd` (M4.1), `scripts/computer_ui.gd` (pošta `send_mail`, banka)
5. `scripts/place.gd` – úřad (`urad`, otevírací doba, úřednice), `scripts/local_client.gd` – `open_place_menu`
6. `scripts/world.gd` – `skip_time`, peníze hráče

## 1. Proč
Dnes se pokuta prostě strhne. Realita: část přestupků se řeší **na místě** (bloková pokuta), závažnější
**ve správním řízení** (příkaz poštou, lhůta, odvolání, nezaplacení → exekuce). Úřad je navíc místo
pro žádosti (povolení ke kácení, pronájem pole, vrácení řidičáku).

## 2. Návrh
### 2.1 Tok přestupku (v `Law.commit`)
- `na_miste`: policista nabídne blokovou pokutu (nabídka: „Zaplatit hned“ / „Nesouhlasím – správní řízení“).
  Zaplatit hned = strhnout z hotovosti (když nemá hotovost → „Bloková pokuta na místě nezaplacená“ – složenka, splatnost 15 dní).
- `spravni_rizeni`: za 1–3 herní dny přijde **příkaz** poštou (M3.4 `send_mail`, a papírový dopis do schránky u domu –
  objekt schránka, E = vybrat poštu) s pokutou (z rozmezí podle závažnosti a opakování) + zákazem činnosti.
  Lhůta **15 dní** (herních) na zaplacení; do 8 dní lze podat **odpor** (na úřadě / PC) → **ústní jednání** na úřadě
  v daný den a hodinu (hráč musí přijít; minihra: vybrat argumenty – „přiznat a omluvit se“ sníží pokutu o 20 %,
  „zapírat“ bez důkazů 30 % šance na zastavení, jinak +20 %; nepřijde → rozhodnutí v nepřítomnosti).
- **Nezaplacení** po lhůtě: upomínka (+ náklady řízení 1 000 Kč), po dalších 30 dnech **exekuce**: strhne se z účtu
  (M3.4) nebo z výplaty (M3.1) + exekutorské náklady (min. 3 000 Kč, orientačně), pověst −5; když nic není,
  exekutor „sepíše“ věc z domu (vozidlo nejvyšší hodnoty v bazarové ceně).
- Deník J → Úřední záznamy: stav každé věci (na místě / příkaz / odpor / jednání / splatné do / zaplaceno / exekuce).

### 2.2 Úřad – nabídka (E u úřednice)
- „Zaplatit pokutu“ (seznam nezaplacených), „Podat odpor“, „Nahlédnout do spisu“ (text záznamu),
  „Žádost o vrácení řidičského oprávnění“ (po uplynutí zákazu + přezkoušení v autoškole M4.1 → vydání),
  „Pronájem pole“ (M2.4 – pokud už tam je, ponech), „Žádost o povolení ke kácení“ (připrav rámec: formulář
  = vyber strom na mapě / buď u něj a řekni „tenhle“ – M4.4 to dokončí), „Ohlášení chovu“ (M2.6 háček).
- Úřad má otevřeno jen v úředních hodinách (`Place.HOURS` – po a st déle – úřední dny).
- Poplatky za úkony (správní poplatky – orientačně: vydání ŘP 50 Kč / přezkoušení 700 Kč, „ověřit“).

### 2.3 Ukládání
Všechny věci v řízení, lhůty, schránka (dopisy).

## 3. Hotovo, když
- Přestupky se dělí na blokové a správní řízení; příkaz přijde poštou, platí se na úřadě nebo přes banku;
  odpor vede k jednání; nezaplacení k upomínce a exekuci; úřad vyřizuje vrácení řidičáku.

## 4. Návrh checklistu ručních testů
1. Rychlost v obci → policista: bloková pokuta → zaplatit hned.
2. Řízení pod vlivem (do 1 ‰) → za 2 dny dopis ve schránce + e-mail: příkaz, lhůta.
3. Podej odpor na úřadě → termín jednání → přijď → vyber argument → výsledek.
4. Nech pokutu nezaplacenou 15 dní (F2 → posun data) → upomínka; +30 dní → exekuce z účtu.
5. Úřad mimo úřední hodiny → zavřeno.
6. Po zákazu řízení: přezkoušení v autoškole → úřad → vrácení řidičáku.
7. F5/F9 → řízení a lhůty zůstanou.

## 5. Závěr
README (Systémy → Úřad), VIZE odškrtnout, roadmapa README, PROJECT_LOG, deník AI, commit „M4.2 Správní řízení: …“, checklist a čekat.
