# Prompty – roadmapa „Život na vsi“ (etapa 1 singleplayer + verze 2 multiplayer)

Každý soubor je **samostatné zadání pro novou session** (jedno kontextové okno, dimenzováno pro Sonnet).
Vize a zdůvodnění: [`../../docs/VIZE_A_ROADMAPA.md`](../../docs/VIZE_A_ROADMAPA.md), původní poznámky:
[`../../docs/požadavky.md`](../../docs/požadavky.md).

## Jak zadávat
Do nové session napiš např.:

> *Přečti a proveď `prompts/roadmapa/M0_zaklady/01_assety_a_licence.md`.*

- Každý prompt nejdřív pošle agenta do [`00_SPOLECNE.md`](00_SPOLECNE.md) (pravidla, mapa kódu, konvence, registr kláves)
  a pak jen do souborů, které krok potřebuje – aby se práce vešla do jednoho okna.
- Agent hru ani testy **nespouští**; na konci zapíše `PROJECT_LOG.md`, deník efektivity AI, commitne a vypíše
  **checklist ručních testů (max. 10 bodů)**. Ty testy projdeš a pošleš výsledky („1 OK, 3 chyba: …“), agent opraví.
- Když krok nedoběhne celý: zadej ho znovu s poznámkou *„pokračuj podle otevřených bodů v PROJECT_LOG.md“*.
  Každý větší prompt má oddíl **Minimum** – co musí být hotové vždy.
- Kroky jdou **postupně podle čísla** (uvnitř milníku lze některé přehodit – viz sloupec „Předpoklady“).
  Předpoklad: série `prompts/priroda/01–04` je hotová (04 se právě dokončuje).
- Po dokončení kroku agent odškrtne `[ ]` → `[x]` tady i ve VIZE.

## Etapa 1 – singleplayer

### M0 – Základy (společné systémy, na které se vše ostatní napojuje)
| | Krok | Soubor | Předpoklady |
|---|---|---|---|
| [x] | M0.1 Pipeline a registr legálních assetů | [`M0_zaklady/01_assety_a_licence.md`](M0_zaklady/01_assety_a_licence.md) | – |
| [x] | M0.2 Jednotný katalog předmětů a inventář | [`M0_zaklady/02_katalog_predmetu_a_inventar.md`](M0_zaklady/02_katalog_predmetu_a_inventar.md) | – |
| [x] | M0.3 Dovednosti a XP (RuneScape styl) | [`M0_zaklady/03_dovednosti_a_xp.md`](M0_zaklady/03_dovednosti_a_xp.md) | M0.2 |
| [x] | M0.4 Kontextové akce, nástroje, náklad (základ) | [`M0_zaklady/04_kontextove_akce_a_nastroje.md`](M0_zaklady/04_kontextove_akce_a_nastroje.md) | M0.2, M0.3 |
| [x] | M0.5 Zákon jako data, bodový systém | [`M0_zaklady/05_katalog_prestupku.md`](M0_zaklady/05_katalog_prestupku.md) | M0.2 |
| [x] | M0.6 Respekt, karma, přátelství | [`M0_zaklady/06_respekt_a_karma.md`](M0_zaklady/06_respekt_a_karma.md) | M0.5 |

### M1 – Živý svět
| | Krok | Soubor | Předpoklady |
|---|---|---|---|
| [x] | M1.1 Terén bez satelitu | [`M1_svet/01_teren_bez_satelitu.md`](M1_svet/01_teren_bez_satelitu.md) | M0.1 |
| [x] | M1.2 Okna, dveře, komíny | [`M1_svet/02_okna_dvere_komin.md`](M1_svet/02_okna_dvere_komin.md) | – |
| [x] | M1.3 Kouř z komínů podle teploty | [`M1_svet/03_kour_z_kominu.md`](M1_svet/03_kour_z_kominu.md) | M1.2 |
| [x] | M1.4 Systém interiérů + domov | [`M1_svet/04_system_interieru_domov.md`](M1_svet/04_system_interieru_domov.md) | M0.4 |
| [x] | M1.5 Interiéry veřejných budov | [`M1_svet/05_interiery_verejnych_budov.md`](M1_svet/05_interiery_verejnych_budov.md) | M1.4 |
| [x] | M1.6 Nová vozidla a bazar | [`M1_svet/06_nova_vozidla.md`](M1_svet/06_nova_vozidla.md) | M0.1 |
| [x] | M1.7 Popisná čísla všech domů, start v bytě (konec domu hráče) | [`M1_svet/07_popisna_cisla_a_start_v_byte.md`](M1_svet/07_popisna_cisla_a_start_v_byte.md) | M1.4, M1.5 · **doporučeno před M3** · **rozhodnutí: který bytový dům** |
| [x] | M1.8 Interiéry všech budov se streamováním | [`M1_svet/08_interiery_vsech_budov_streaming.md`](M1_svet/08_interiery_vsech_budov_streaming.md) | M1.7 |

### M2 – Řemesla a venkov (jádro RuneScape činností)
| | Krok | Soubor | Předpoklady |
|---|---|---|---|
| [x] | M2.1 Kácení a dřevo | [`M2_remesla/01_kaceni_a_drevo.md`](M2_remesla/01_kaceni_a_drevo.md) | M0.2–M0.5 |
| [x] | M2.2 Oheň a topení | [`M2_remesla/02_ohen_a_topeni.md`](M2_remesla/02_ohen_a_topeni.md) | M2.1, M1.4 |
| [x] | M2.3 Oblečení | [`M2_remesla/03_obleceni.md`](M2_remesla/03_obleceni.md) | M0.2, M1.4 |
| [x] | M2.4 Zahrada a pole | [`M2_remesla/04_zahrada_a_pole.md`](M2_remesla/04_zahrada_a_pole.md) | M0.4 |
| [x] | M2.5 Sázení stromů | [`M2_remesla/05_sazeni_stromu.md`](M2_remesla/05_sazeni_stromu.md) | M2.1, M2.4 |
| [x] | M2.6 Hospodářská zvířata a porážka | [`M2_remesla/06_hospodarska_zvirata.md`](M2_remesla/06_hospodarska_zvirata.md) | M2.4, M2.2 |
| [x] | M2.7 Rybaření | [`M2_remesla/07_rybareni.md`](M2_remesla/07_rybareni.md) | M2.2 |
| [x] | M2.8 Zbraně a střelba | [`M2_remesla/08_zbrane_a_strelba.md`](M2_remesla/08_zbrane_a_strelba.md) | M0.5 |
| [x] | M2.9 Lov zvěře | [`M2_remesla/09_lov_zvere.md`](M2_remesla/09_lov_zvere.md) | M2.8 |
| [x] | M2.10 Náklad a ruční vozík | [`M2_remesla/10_naklad_a_rucni_vozik.md`](M2_remesla/10_naklad_a_rucni_vozik.md) | M2.9, M1.6 |

### M3 – Práce a počítač
| | Krok | Soubor | Předpoklady |
|---|---|---|---|
| [x] | M3.1 Systém zaměstnání | [`M3_prace/01_system_zamestnani.md`](M3_prace/01_system_zamestnani.md) | M0.3–M0.6 |
| [x] | M3.2 Farma, obecní údržba, výčep | [`M3_prace/02_prvni_tri_prace.md`](M3_prace/02_prvni_tri_prace.md) | M3.1, M2.4, M2.6 |
| [x] | M3.3 Další práce | [`M3_prace/03_dalsi_prace.md`](M3_prace/03_dalsi_prace.md) | M3.2 |
| [x] | M3.4 Počítač doma | [`M3_prace/04_pocitac.md`](M3_prace/04_pocitac.md) | M1.4, M3.1 |

### M4 – Zákon a společnost
| | Krok | Soubor | Předpoklady |
|---|---|---|---|
| [ ] | M4.1 Řidičská oprávnění a autoškola | [`M4_zakon/01_ridicska_opravneni_autoskola.md`](M4_zakon/01_ridicska_opravneni_autoskola.md) | M3.4, M1.6 |
| [ ] | M4.2 Správní řízení na úřadě | [`M4_zakon/02_spravni_rizeni_urad.md`](M4_zakon/02_spravni_rizeni_urad.md) | M4.1 |
| [ ] | M4.3 Soud a vězení | [`M4_zakon/03_soud_a_vezeni.md`](M4_zakon/03_soud_a_vezeni.md) | M4.2 |
| [ ] | M4.4 Další přestupky a svědci | [`M4_zakon/04_dalsi_prestupky.md`](M4_zakon/04_dalsi_prestupky.md) | M4.2 |
| [ ] | M4.5 Dobré skutky a přátelství | [`M4_zakon/05_povest_respekt_karma_skutky.md`](M4_zakon/05_povest_respekt_karma_skutky.md) | M0.6 |
| [ ] | M4.6 Zbraně, lov a rybolov podle zákona | [`M4_zakon/06_zbrane_lov_rybolov_zakon.md`](M4_zakon/06_zbrane_lov_rybolov_zakon.md) | M4.4, M2.7–M2.10 |
| [ ] | M4.7 Katastr: koupě a prodej domů, bytů, polí, pozemků, lesů | [`M4_zakon/07_katastr_koupe_prodej_nemovitosti.md`](M4_zakon/07_katastr_koupe_prodej_nemovitosti.md) | M1.7, M4.2, M3.1 |

### M5 – Obec a volný čas
Doporučené pořadí: **5.9 → 5.1 → 5.2 → 5.5 → 5.6 → 5.3 → 5.4 → 5.7 → 5.8** (5.9 rádia a 5.7–5.8 skate lze vložit kdykoli po M0).
| | Krok | Soubor | Předpoklady |
|---|---|---|---|
| [ ] | M5.1 Stavebniny + kutilské stavby | [`M5_obec/01_stavebniny.md`](M5_obec/01_stavebniny.md) | M0.4 · **potřebuje souřadnice od uživatele** |
| [ ] | M5.2 Koupaliště a plavání | [`M5_obec/02_koupaliste_a_plavani.md`](M5_obec/02_koupaliste_a_plavani.md) | M5.1 · **souřadnice nádrže** |
| [ ] | M5.3 Hasiči | [`M5_obec/03_hasici.md`](M5_obec/03_hasici.md) | M2.2, M2.3 |
| [ ] | M5.4 Hasičský sport | [`M5_obec/04_hasicsky_sport.md`](M5_obec/04_hasicsky_sport.md) | M5.3, (M5.6) |
| [ ] | M5.5 Kalendář událostí a zábava | [`M5_obec/05_udalosti_a_zabava.md`](M5_obec/05_udalosti_a_zabava.md) | M1.5, M3.4 |
| [ ] | M5.6 Fotbal | [`M5_obec/06_fotbal.md`](M5_obec/06_fotbal.md) | (M5.5) |
| [ ] | M5.7 Skateboard | [`M5_obec/07_skateboard.md`](M5_obec/07_skateboard.md) | M0.3 |
| [ ] | M5.8 U-rampa za domem | [`M5_obec/08_u_rampa.md`](M5_obec/08_u_rampa.md) | M5.7 · **rozhodnutí: hotová / stavět** |
| [ ] | M5.9 Rocková rádia | [`M5_obec/09_rockova_radia.md`](M5_obec/09_rockova_radia.md) | – |

### M6 – Létání
| | Krok | Soubor | Předpoklady |
|---|---|---|---|
| [x] | M6.1 Dron | [`M6_letani/01_dron.md`](M6_letani/01_dron.md) | M3.4, M4.1 |
| [x] | M6.2 Krajina za okrajem mapy | [`M6_letani/02_pozadi_za_okrajem_mapy.md`](M6_letani/02_pozadi_za_okrajem_mapy.md) | M1.1 · **rozhodnuto: strop 1 500 m AGL, 2 km za katastr** |
| [x] | M6.3 Letový model | [`M6_letani/03_letovy_model.md`](M6_letani/03_letovy_model.md) | M6.2 |
| [x] | M6.4 Motorový paraglide | [`M6_letani/04_motorovy_paraglide.md`](M6_letani/04_motorovy_paraglide.md) | M6.3 |
| [x] | M6.5 Motorové rogalo (trike) | [`M6_letani/05_motorove_rogalo.md`](M6_letani/05_motorove_rogalo.md) | M6.4 · ~~souřadnice polní dráhy~~ → dráha JZ od návsi: práh (−440, 240), směr 30°, 260 m |

### M7 – Cesta na starostu (hlavní cíl hry)
Doplněk od uživatele (30. 9. 2026). Doporučeno po M4 a M5.5; M6 létání je volitelné a může jít až po M7.
| | Krok | Soubor | Předpoklady |
|---|---|---|---|
| [ ] | M7.1 Popularita a kritéria kandidatury | [`M7_starosta/01_popularita_a_kriteria.md`](M7_starosta/01_popularita_a_kriteria.md) | M0.6, M4.5, M5.5 |
| [ ] | M7.2 Kampaň a volby (poctivě i nečestně) | [`M7_starosta/02_kampan_a_volby.md`](M7_starosta/02_kampan_a_volby.md) | M7.1, (M4.3, M4.4) |
| [ ] | M7.3 Vedlejší úkoly s větvením | [`M7_starosta/03_vedlejsi_ukoly_a_vetveni.md`](M7_starosta/03_vedlejsi_ukoly_a_vetveni.md) | M7.1 |
| [ ] | M7.4 Starostování a konce příběhu | [`M7_starosta/04_starostovani.md`](M7_starosta/04_starostovani.md) | M7.2 |

### Doplňky hotové mimo milníky (30. 9. 2026)
- [x] Oprava 3D: končetiny „naruby“ a úchop předmětů v ruce (commit 66213e0)
- [x] Rozšířený rozhovor přes T: témata, rady, drby o sousedech, paměť rozhovoru, navazující otázky, otázky zpět
  (`scripts/dialog_data.gd`, `scripts/dialog_themes.gd`, commit 45b6901)

## Verze 2 – multiplayer (až po etapě 1)
Viz [`V2_multiplayer/README.md`](V2_multiplayer/README.md): revize starých MP promptů (`prompts/03–10`, `priroda/05`),
pak síťový základ a nové kroky V2.01–V2.05 (dovednosti a akce, měnitelný svět, zákon a práce, společné aktivity, létání a výkon).

## Rozhodnutí, která budou potřeba od uživatele
| Kdy | Otázka |
|---|---|
| M0.3 | rozsah úrovní dovedností 1–50 (návrh) – ok? |
| M0.5 / M4 | úroveň realismu zákona (daně, povinné ručení, STK – ano/ne) |
| M1.5 | ~~interiéry ostatních domů – zamčené, nebo generované?~~ → generované se streamováním (M1.8) – **hotovo** (M1.8: cizí domy zamčené, zaklepat) |
| M1.7 | který dům bude bytový (start hráče) – návrh: největší obytná budova s více podlažími |
| M7.1 | termín prvních voleb (návrh 60 herních dní, další po 120) |
| M5.1, M5.2 | souřadnice stavebnin a bývalé hasičské nádrže (mapa M ve hře ukazuje souřadnice hráče) |
| M5.8 | U-rampa hotová od začátku (návrh), nebo stavba ze stavebnin? |
| M6.2 | ~~strop a dosah letu~~ → rozhodnuto: strop 1 500 m nad terénem, hranice 2 km za katastrem (`World.FLY_*`) |
| M6.5 | místo polní dráhy pro trike |
