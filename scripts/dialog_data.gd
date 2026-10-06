## Data rozhovoru (T) – rozšíření klíčových slov, rady a návody, drby, otázky zpět a vtipy (jen tabulky, logika je v `Dialog`).
## Témata s odpověďmi jsou v `DialogThemes`. Klíčová slova jsou bez diakritiky, hledají se na začátku slova (viz `Dialog._has`).
## Jména jsou smyšlená (viz README → Právní zásady obsahu).
class_name DialogData
extends RefCounted

## Doplňková slova k záměrům z `Dialog.WORDS` (hovorové tvary, překlepy, synonyma).
const EXTRA_WORDS := {
	"greeting": ["ahojky", "ahooj", "cauky", "caute", "zdravicko", "dobryden", "dobrejden", "dobrej den", "dobre dopoledne", "cuau", "cauec",
		"dobrej vecer", "hello", "hellou", "zdravim vas", "ahojte", "dobry rano", "dobrou chut", "cus cus", "salut"],
	"goodbye": ["papa", "nashledanou", "nashle", "mejte se hezky", "hezky den", "hezky zbytek", "uz musim", "pujdu", "odchazim", "tak ja jdu",
		"tak ja pujdu", "jdu domu", "tak se mej", "zatim pa", "vidime se", "dobre noci", "dobrou", "opatruj se", "drz se", "budu muset jit", "mam naspech"],
	"thanks": ["dekuju", "dekuji", "dekujeme", "diky moc", "dikes", "dikec", "thx", "dekan", "velke diky", "moc dekuju", "vdecny", "vdecna", "bohudik", "diky ti", "dekuju ti"],
	"compliment": ["jsi skvel", "jsi super", "jsi dobr", "jsi hodn", "jsi fajn", "jsi nejlepsi", "pekny dum", "pekna zahrada", "pekna ves", "moc hezky",
		"moc pekne", "obdivuju", "obdivuji", "gratuluju", "gratuluji", "bravo", "dobra prace", "jsi borec", "jsi kral", "zlata", "zlaty", "parada", "chapu te", "mas hezky"],
	"howareyou": ["jak se ti vede", "jak se vam vede", "jak to vypada", "jak jsi na tom", "jak ses mel", "co noveho u tebe", "jak jde zivot",
		"jak se ti dari", "jak se dnes mas", "jaka je nalada", "co rodina", "jak jsi se vyspal", "jak ses vyspala", "jak ti je"],
	"weather": ["pocasicko", "jaky bude den", "bude prset", "bude snih", "bude hezky", "jak je venku", "je venku zima", "je venku horko", "predpoved",
		"pranostik", "zatazeno", "oblacno", "jasno", "blesk", "parno", "dusno", "vedro", "pliskanic", "snezeni", "naledi", "studene", "bude zitra", "pocasi zitra"],
	"news": ["nejaky drb", "nejake drby", "povez mi neco", "neco zajimaveho", "co se stalo", "co se ve vsi", "jake novinky", "neco novyho",
		"co se tu deje", "co nove", "co tu nove", "stalo se neco", "co jsi slysel", "co jsi slysela", "zpravy ze vsi", "neco noveho", "co je noveho",
		"co se tu povida", "co tu slychat", "co slychat"],
	"joke": ["vtipek", "vtipku", "vtipy", "zazertuj", "zerty", "zert", "neco k smichu", "neco vtipneho", "anekdot", "sranda", "nasmej me",
		"rozesmej me", "rekni vtip", "povez vtip", "dalsi vtip", "jeste jeden vtip"],
	"money": ["pujcis mi", "pujcite mi", "dluzim", "sezen mi", "ani korunu", "par korun", "stovku", "tisicovku", "pujcka", "pujcit si", "na dluh",
		"jsem bez penez", "mam prazdnou kapsu", "nemam na", "dej mi par", "podpor"],
	"food": ["jsem hladov", "co k jidlu", "co na obed", "co na veceri", "co ke snidani", "kde se najim", "kde se da najist", "kde dostanu jist",
		"zobnout", "svacin", "na obed", "na veceri", "mam chut na"],
	"sleep": ["jsem unaven", "chce se mi spat", "spat se mi chce", "kde prespim", "kde prespat", "kam si lehnout", "kde si lehnu", "zdrimnout",
		"odpocinout", "unava", "jsem grogy", "jsem hotov", "jdu spat", "usnout", "nemuzu spat", "nespim", "nespavost", "vyspat se"],
	"time": ["kolik je", "kolik hodin", "kolik bije", "jake je datum", "kolikaty je", "kolikateho je", "jaky je dnes den", "jaky je dneska den",
		"co je dnes za den", "jaky datum", "dnes je", "jaky je den"],
	"hours": ["kdy otevira", "kdy zavira", "otevreno", "je otevreno", "je zavreno", "do kdy maji", "od kdy maji", "do kdy je", "kdy se otevira"],
	"where": ["kudy se jde", "kde to je", "kde tu je", "kde mate", "kam se jde", "pujdu ke", "jak dojit", "kde seznam"],
	"police": ["policajt", "policajty", "policajti", "cmukal", "pokut", "silnicni kontrola", "dechovk", "nafoukat", "zakaz rizeni", "odecet bodu", "ridicak sebrali", "auto policie", "hlidka"],
	"quest": ["neco na praci", "nejaka prace", "nejaka brig", "hledas pomoc", "potrebujes pomoct", "potrebujete pomoct", "mam ti pomoct", "mam vam pomoct", "mate praci", "mas praci", "zakazk"],
	"invite": ["jdem na pivo", "jdeme na pivo", "pojdme na pivo", "zajdem na pivo", "zajdeme na pivo", "skocime na pivo", "dame jedno", "dame kafe", "zvu vas na", "pojd do hospody",
		"pojdme do hospody", "posedime", "zajdem do hospody", "dame pivko", "tak na pivo"],
	"sorry": ["omluvte me", "omlouvam se", "prominte", "odpust", "odpustte", "to mi je lito", "lituju", "lituji", "mrzi me to", "moje chyba", "bylo to blbe", "to jsem nemel",
		"nemyslel jsem to", "nechtel jsem ti ublizit"],
	"insult": ["hlupak", "pitomec", "zmetek", "blbej", "pako", "ksindl", "bastard", "hnusak", "dobytek", "grazl", "sracko", "blbka", "hnus "],
	"threat": ["rozmlatim", "vyrizu", "podriznu", "zapalim ti", "zastrelim", "zastrelit te", "utlucu", "hrozim ti", "uvidis co te ceka"],
	"yes": ["jojo", "klidne", "samozrejme", "pochopitelne", "presne tak", "asi ano", "asi jo", "to jo", "jj ", "jop", "jep", "rozhodne", "to bych rad", "s radosti", "tak jo"],
	"no": ["nene", "to ne", "asi ne", "nemam", "nemuzu", "nemohu", "ani ne", "v zadnem pripade", "ani nahodou", "radsi ne", "ne dik", "ne diky", "nepotrebuju"],
	"where_am_i": [],
}

## Záměry, které mají svá slova tady (nejsou ve `Dialog.WORDS` ani v `DialogThemes`).
const WORDS := {
	"howto": ["jak na to", "jak se to dela", "jak to mam", "jak mam", "jak se hraje", "poradte", "poradis", "poradite", "navod", "tip ", "tipy", "radu ", "kde koupit", "kde koupim",
		"kde sezenu", "kde se da koupit", "kde se prodava", "kde dostanu", "kde vezmu", "jak zacit", "jak zacnu", "s cim zacit", "co mam koupit", "co potrebuju na",
		"co je potreba na", "jak se naucim", "jak se to", "jak se to pouziva", "co s tim", "co s tim mam delat", "kde se to"],
	"f_why": ["proc", "z jakeho duvodu", "jak to", "cim to", "jak to ze", "a proc", "kvuli cemu", "na co to"],
	"f_more": ["a co dal", "a dal", "pokracuj", "vic ", "neco dalsiho", "a co jeste", "a jinak", "rekni vic", "povez vic", "povidej", "dalsi", "jeste neco", "a co jeste", "dal "],
	"f_how": ["jak na to", "jak se to dela", "jak mam", "jak to mam", "poradis", "poradite", "navod", "jak to udelat", "jak na to zacit", "jak postupovat"],
	"f_where": ["kde", "kdepak", "kam", "odkud"],
	"f_andyou": ["a ty", "a vy", "a co ty", "a co vy", "a tobe", "a vam", "a ty jak", "ty taky", "vy taky", "ty take"],
	"about_person": [],
}

## Jak dlouho (herní minuty) je krátká paměť rozhovoru „čerstvá“ (navazující otázky a otázka zpět).
const MEMORY_FRESH_MIN := 90.0
## Kolik odpovědí si postava pamatuje (aby se neopakovala) a po jak dlouhé době (herní dny) zapomene.
const MEMORY_SAID_MAX := 60
const MEMORY_FORGET_DAYS := 1
## Jak dlouho (herní hodiny) se neopakuje poznámka k nedávné události.
const REMARK_COOLDOWN_H := 6.0
## Nejdelší zpráva hráče (počet slov), která se ještě bere jako navazující otázka / krátká odpověď.
const FOLLOW_MAX_WORDS := 5

## Šance (0..1), že postava po odpovědi položí otázku zpět, podle povahy (`Characters.TRAITS`).
const ASK_CHANCE := {"pratelsky": 0.4, "drbna": 0.45, "bruclavy": 0.12, "prisny": 0.1, "veselak": 0.4, "plachy": 0.06, "moudry": 0.3, "mlady": 0.3}
## Šance na poznámku k nedávné události (úlovek, pokácený strom…).
const REMARK_CHANCE := 0.35

## Nedávné události hráče (`Reputation.recent`) → podmínka (`Dialog._conds`) a platnost v herních hodinách.
const RECENT_MAP := {
	"fish_caught": ["recent_fish", 30.0], "tree_felled": ["recent_tree", 30.0], "hunt_kill": ["recent_hunt", 48.0], "poaching": ["recent_poach", 72.0],
	"offense": ["recent_offense", 72.0], "busted": ["recent_offense", 72.0], "fire_lit": ["recent_fire", 12.0], "fire_report": ["recent_fire", 12.0],
	"quest_done": ["recent_quest", 36.0], "harvest": ["recent_harvest", 30.0], "car_crash": ["recent_crash", 24.0], "passed_out": ["recent_drunk", 36.0],
	"cooked": ["recent_cooked", 12.0], "tree_planted": ["recent_planted", 48.0], "gift_given": ["recent_gift", 48.0], "slept": ["recent_slept", 10.0],
	"knocked_out": ["recent_drunk", 24.0], "venison_processed": ["recent_hunt", 48.0],
}

## Téma (`DialogThemes.THEMES`) → oblíbené téma postavy (`Characters.PROFILES[*].topics`). Postava s tímto tématem je „odborník“.
const THEME_TOPIC := {
	"garden": "zahrada", "seasonwork": "pole", "animals": "zvirata", "fishing": "ryby", "hunting": "zver", "wood": "les", "fire": "hasici", "cars": "auta",
	"pub": "pivo", "beer": "pivo", "football": "fotbal", "firefighters": "hasici", "politics": "urad", "neighbors": "drby", "family": "deti",
	"recipes": "jidlo", "mushrooms": "les", "health": "zdravi", "tech": "mobil", "event": "kostel", "bus": "silnice", "earn": "prace",
	"village": "drby", "weather": "pocasi", "music": "kostel",
}

## Poznámky k nedávné události přidané za odpověď (podmínka → věty). {g:…|…} = tvar postavy.
const REMARKS := {
	"recent_fish": ["Mimochodem, slyšel{g:|a} jsem, že se ti povedlo něco chytit.", "Prý ses chlubil rybou. Příště ji ukaž!"],
	"recent_tree": ["A slyšel{g:|a} jsem, že jsi porazil strom. Doufám, že jsi to měl povolené.", "Kdosi tu mluvil o pokáceném stromu. Že bys to byl ty?"],
	"recent_hunt": ["A prý jsi byl na lovu. Hlavně ať po právu.", "Jen ať se ta zvěřina nezkazí, slyšel{g:|a} jsem, že něco ležíš."],
	"recent_poach": ["A povídá se o tobě, že jsi lovil bez papírů. Nedělej to.", "Pytláci ve vsi nejsou oblíbení. Jen abys věděl."],
	"recent_offense": ["Povídá se, že ses někde provinil. Polepši se, {voc}.", "Slyšel{g:|a} jsem o tom přestupku. Příště dej pozor."],
	"recent_fire": ["Ten kouř u lesa nebyl tvůj? Nezapomeň oheň uhasit.", "Kdo rozdělává oheň, nesmí zapomenout na vodu."],
	"recent_quest": ["A díky, že ses ve vsi činil. Lidi o tom mluví dobře.", "Slyšel{g:|a} jsem, že jsi komusi pomohl. Dobrý skutek."],
	"recent_harvest": ["Prý se ti daří na zahradě. To je dobře.", "Čerstvá úroda, to je radost, co?"],
	"recent_crash": ["Doufám, že jsi v pořádku po té nehodě.", "Slyšel{g:|a} jsem o nehodě. Dej si pozor, {voc}."],
	"recent_drunk": ["A že tě našli ležet? Už si dávej pozor na pití.", "Slyšel{g:|a} jsem, že tě včera sbalilo. Není to hezké."],
	"recent_cooked": ["Ucítil{g:|a} jsem, že ses dobře najedl. Dobrou chuť."],
	"recent_planted": ["Prý sázíš stromy. To je hezké, ves bude zelenější."],
	"recent_gift": ["A děkuju ještě jednou za ten dárek."],
	"recent_slept": ["Vypadáš odpočatě, to je dobře."],
	"event_vanoce": ["Vánoce jsou tady, nezapomeň na cukroví."], "event_masopust": ["Dnes je masopust, to je veselo!"], "event_carodejnice": ["Dnes se pálí čarodějnice, pozor na oheň."],
	"event_hody": ["Hody jsou tady, přijď na zábavu!"], "event_silvestr": ["Šťastný nový rok se blíží!"],
}

# ====================================================================== rady a návody (jak na to, kde koupit)

## Subjekt rady → slova (subjekt se hledá ve větě) + rady (odkazují na skutečné herní systémy; zjednodušená herní simulace).
const HOWTO := {
	"fishing": {"words": ["ryb", "udic", "navnad", "rybar", "rybnik", "kapr"], "lines": [
		"Udici a návnadu koupíš v Potravinách (sekce Rybaření). Pak vezmi udici do ruky (Q) a hoď na rybníku nebo v potoce levým tlačítkem.",
		"Žížaly se dají vykopat lopatou nebo motykou, nebo koupit. Když ryba zabere, rychle zasekni a pak navíjej.",
		"Malé ryby a hájené druhy radši pouštěj zpátky, lidé si toho váží. A na rybaření se hodí rybářský lístek, bez něj je to pytláctví.",
		"Podběrák se hodí na větší kousky. Kapři jdou nejlíp brzo ráno nebo po soumraku."]},
	"garden": {"words": ["zahrad", "zahon", "sadit", "sazet", "semen", "zalev", "pestov", "brambor", "rajcat", "plet", "sklizet"], "lines": [
		"Zahradu máš u usedlosti {lot}, kousek od lavičky dědy Vomáčky. Potřebuješ lopatu, semena a konev – všechno v Potravinách. Nejdřív zrýt záhon, pak zasít, zalévat a plít.",
		"Semena kup podle ročního období, jaro je na brambory, salát a mrkev. Když záhon nezaléváš, uschne.",
		"Sklizenou zeleninu můžeš sníst, uvařit, nebo prodat v Potravinách, kde ji vykupují.",
		"Větší pole si můžeš pronajmout na úřadě na rok. Stojí to 1 500 korun."]},
	"hunting": {"words": ["lov", "zver", "puska", "luk ", "kuse", "zbran", "strel", "myslivost", "pytlak"], "lines": [
		"Na lov potřebuješ pušku, zbrojní oprávnění, lovecký lístek a povolenku. Bez nich je to pytláctví, to ti hrozí pokuta i hanba.",
		"Střílí se jen v době lovu, ne v noci, ne v obci a ne z auta. Luk a kuše se na lov nepoužívají.",
		"Po výstřelu zvíře najdi, vyvrhni nožem a nech si doklad o původu, jinak zvěřinu neprodáš.",
		"Nejdřív si zkus střelbu na střelnici u myslivecké chaty. Kolísání mušky závisí na výdrži a dechu, přidrž dech Shiftem."]},
	"wood": {"words": ["drev", "sekera", "sekeru", "kacet", "pila", "pilu", "polen", "klest", "vetve"], "lines": [
		"Sekeru (staré i nové) a motorovou pilu koupíš ve stavebninách za vsí, prkna a dříví na pile vedle nich. Kácej jen na vlastní zahradě, jinak je to krádež a přestupek.",
		"Pokácený strom odvětvi a rozřež na polena. Polena se hodí na topení, nebo se prodávají v Pálenici.",
		"Při práci s pilou nos helmu a ochranné kalhoty, jinak hrozí úraz.",
		"Dřevo musí uschnout, mokré hůř hoří. Suché větve jsou nejlepší roznětka."]},
	"fire": {"words": ["ohen", "ohni", "zapal", "sirk", "grilov", "burt", "topit", "vatr", "upect"], "lines": [
		"Oheň rozděláš ze suchých větví a polen, potřebuješ sirky nebo zapalovač (Potraviny). Nejlépe v kamenném kruhu.",
		"V lese nebo do 50 metrů od lesa oheň nerozděláš, je to přestupek. V létě za sucha a větru je to hlavně nebezpečné.",
		"U ohně (E) si můžeš opéct buřt, brambory nebo ryby. A kdo se zahřeje, ten usušil mokré šaty.",
		"Nikdy neodcházej od hořícího ohně. Když se vzdálíš, hrozí požár trávy."]},
	"cars": {"words": ["auto", "ridic", "jezdit", "jizd", "kolo ", "kola ", "motork", "benzin", "vuz", "kara"], "lines": [
		"Na řízení musíš být střízlivý a mít platné oprávnění. Policie na silnicích občas měří rychlost a dělá dechovou zkoušku.",
		"Kolo a motorku má u domu děda. Na kole se nejlíp vozí lehčí náklad.",
		"V zimě a za deště jezdi pomalu, silnice kloužou. Kolem lesa dej pozor na zvěř.",
		"Když do něčeho narazíš, auto se opraví v servisu. Raději jezdi opatrně a nepij."]},
	"sleep": {"words": ["spat", "spani", "nocleh", "vyspat", "spacak", "postel", "prespat"], "lines": [
		"Nejlíp se vyspíš doma v posteli ({home}). Nouzově na seníku za hospodou, na palandě u Myslivecké chaty, nebo ve spacáku z Potravin.",
		"Když jsi unavený, klesá ti výdrž. Spánek ji vrátí a srovná i hlavu po pití.",
		"Spací pytel koupíš v Potravinách a můžeš ho rozložit, kde se ti zachce. Jen ne na cizím pozemku."]},
	"earn": {"words": ["vydel", "penize", "penez", "brigad", "praci", "prace", "zbohatn", "prodat", "prodej"], "lines": [
		"Vydělat se dá úkoly: zmáčkni E u dědy, hostinského, na úřadě nebo u myslivce, někdo vždycky něco potřebuje.",
		"Prodávat můžeš v Potravinách: zeleninu, vejce, mléko, maso, vlnu. Polena vykupuje Pálenice. Zvěřinu jen s dokladem o původu.",
		"Čím lepší pověst, tím líp se ti bude ve vsi dařit. Slušnost se vyplatí.",
		"Pronajmi si pole na úřadě a pěstuj, nebo chovej zvířata. Pomalu, ale jistě to vynáší."]},
	"quests": {"words": ["ukol", "ukoly", "pomahat", "zadani"], "lines": [
		"Úkoly se berou na místech: dveře hospody, úřadu, chaty nebo lavička dědy u jeho domu ({deda_home}). Zmáčkni E a nabídne se ti práce.",
		"Když máš rozdělaný úkol, najdeš ho v deníku (J). Splněný úkol ti přidá pověst a respekt.",
		"Kdo úkol vzdá, nic neztratí. Kdo ho nesplní nebo zradí, o pověst přijde."]},
	"horse": {"words": ["kun ", "kone", "konik", "jezdec"], "lines": [
		"Tvůj kůň stojí ve výběhu u usedlosti {lot}. Nasedni na něj klávesou F, zahvízdat na něj můžeš klávesou G.",
		"Na koni se jezdí rychle, ale ve stoje krmit musíš. V trysku tě může shodit, buď opatrný.",
		"V zimě dej koni seno a vodu, ať se neschoulí do stájky."]},
	"field": {"words": ["pole ", "poli ", "pronajem", "traktor", "pestovani"], "lines": [
		"Pole si pronajmeš na úřadě za 1 500 korun na rok. Pak je můžeš obdělávat jako zahradu, jen větší.",
		"Pole se sklízí podle kalendáře. Když je zásah, zkus radu od zemědělců, třeba od pana Stonožky.",
		"Plodiny si nech prodat v Potravinách nebo si je přivez domů."]},
	"trees": {"words": ["strom", "sazenice", "sazeni", "ovocn", "jablon", "hrusen", "tresen"], "lines": [
		"Sazenice stromů jsou v Potravinách (jabloň, švestka, hrušeň, třešeň, dub, buk, smrk, borovice). Zasaď je lopatou a nezapomeň zalévat.",
		"Ovocné stromy dávají plody za pár let, lesní rostou pomalu. Ochranný obal je ochrání před zvěří.",
		"Sázet se má jaro a podzim, v létě vysychá."]},
	"clothes": {"words": ["obleceni", "obleknout", "boty", "bunda", "saty", "oblek", "kalhoty", "plavky", "sako", "sat", "trik"], "lines": [
		"Oblečení koupíš v Potravinách: Textil, Pracovní a Slavnostní. Oblékat se dá doma ve skříni (I).",
		"Na práci s pilou bereš helmu a ochranné kalhoty. Na úřad a do společnosti sako a slavnostní košili.",
		"V zimě bunda, čepice a rukavice, jinak nastydneš. V plavkách po vsi jen k vodě."]},
	"laws": {"words": ["zakon", "pokuta", "doklad", "papiry", "opravneni", "povolenk", "listek", "policie"], "lines": [
		"Doklady a oprávnění si vyřiď dřív, než vyrazíš. Bez zbrojního, loveckého lístku nebo povolenky se nesmí lovit ani střílet.",
		"Zákony jsou zjednodušené, ale platí: nejezdit opilý, nekácet v lese bez povolení, nerozdělávat oheň u lesa.",
		"Policie dělá kontroly na hlavní. Když jsi v právu, nemáš se čeho bát."]},
	"cargo": {"words": ["vozik", "naklad", "nest ", "prepravit", "odvezt", "odvez"], "lines": [
		"Na nesení (G) se hodí rameno – zvěř, špalek, pytel. Větší kusy dáš do kufru nebo na pickup.",
		"Ruční vozík koupíš v Potravinách za 2 490 korun. Táhni ho za ojí, do kopce to je fuška.",
		"Plachta schová náklad před zvědavci. Koupíš ji v Potravinách."]},
	"shoot": {"words": ["strelnice", "mirit", "miris", "strilet", "strelba"], "lines": [
		"Střelnice je u Myslivecké chaty. Pravým tlačítkem miř, levým střílej, Shift zadrží dech.",
		"Luk a kuši koupíš v Potravinách. Pušku jen se zbrojním oprávněním.",
		"Mířit se musí klidně. Unavený nebo opilý střelec se třese."]},
	"orientation": {"words": ["mapa", "orientov", "navigace", "kde jsem", "ztracen", "denik", "trefit", "najit"], "lines": [
		"Mapu otevřeš klávesou M, deník klávesou J. V deníku jsou úkoly, pověst a předpověď.",
		"Když nevíš, kde jsi, zeptej se někoho: postavy znají směr a vzdálenost k hospodě, Potravinám, úřadu i domů.",
		"Domů to máš – {home}. Když se ztratíš, ptej se na cestu domů."]},
	"animals": {"words": ["slepic", "kury", "kralic", "chov", "zvirata", "krmit", "seno", "zrni"], "lines": [
		"Zvířata koupíš u výběhu přes ceduli. Krmivo (zrní, seno, granule) je v Potravinách.",
		"Výkup vajec, mléka, vlny a masa je v Potravinách. Zvířata potřebují vodu a čisto.",
		"V zimě krm víc. Liška ráda navštíví kurník, zavři na noc."]},
	"cooking": {"words": ["vareni", "jak uvarit", "jak upect", "pecen", "opecen", "recept"], "lines": [
		"Jídlo vaříš na ohni: rozděl ho, dej suroviny a využij E u ohně. Buřty, brambory a ryby se dají opéct.",
		"Dej pozor, ať jídlo nespálíš. Pak už je k ničemu.",
		"Polévku a guláš máš v hospodě. Kdo chce vařit, potřebuje suroviny z Potravin."]},
	"buy": {"words": ["koupit", "nakupovat", "obchod", "co koupit", "sehnat"], "lines": [
		"V Potravinách je skoro všechno: jídlo, pití, semena, udice, oblečení, vozík. Sekeru a nářadí mají stavebniny, prkna pila. Pálenice prodává slivovici, sklep víno, hospoda pivo a jídlo.",
		"Když si nejsi jistý, co potřebuješ, zeptej se, na co: lov, rybaření, zahrada, dřevo…",
		"Potraviny mají v sobotu jen dopoledne a v neděli zavřeno. Plánuj nákup."]},
}

## Rady, když není jasné téma (podle podmínky nebo ročního období; "_" = vždy).
const GENERIC_TIPS := {
	"_": ["Zajdi na úřad nebo do hospody, tam vždycky něco najdeš.", "Zmáčkni E u dveří míst, nabídnou ti práci, jídlo nebo zboží.", "Zkus se někoho zeptat na nové drby nebo na cestu, postavy toho ví hodně.",
		"Pověst se vyplatí: slušnost, pomoc ve vsi a dodržování zákonů."],
	"raining": ["Za deště běž do lesa, brzy budou houby.", "V dešti zůstaň doma u ohně a uvař něco teplého."],
	"night": ["V noci se nejlíp spí. Zajdi domů a odpočiň si.", "V noci je venku tma, dej pozor na silnici."],
	"winter": ["V zimě nasekej dříví a topíš v kamnech. Sníh prozradí každou stopu.", "V zimě si vem čepici a rukavice, ať nenastydneš."],
	"spring": ["Na jaře se seje. Kup semena a zkus záhon."], "summer": ["V létě dej pozor na požár trávy a pij hodně vody."], "autumn": ["Na podzim sbírej houby, jablka a šípky."],
	"poor": ["Když nemáš peníze, vezmi úkol ve vsi. Jsou důležité."], "drunk": ["Radši se vyspi. Ráno moudřejší večera."],
	"carry_fish": ["Z ryby uděláš oběd na ohni."], "carry_game": ["Zvěřinu nezapomeň vyvrhnout."], "carry_rod": ["S udicí jdi k vodě."],
}

# ====================================================================== drby o jiných postavách

## Drb podle povahy postavy, o které se mluví ({o} = křestní jméno, {go:…|…} = mužský|ženský tvar o ní).
const GOSSIP_TRAIT := {
	"pratelsky": ["{o} prý zase rozdával{go:|a} sousedům přebytky ze zahrady.", "{o} hlídal{go:|a} sousedovi psa a ani o to nestál{go:|a}.", "{o} pomáhal{go:|a} sousedce nosit nákup, to je dobrá duše."],
	"drbna": ["{o} ví všechno o všech, a to i včera, co se stalo ve čtvrtek.", "{o} prý zase někomu vyprávěl{go:|a} o tom, co slyšel{go:|a} před pěti minutami.", "Když chceš něco rychle roznést, stačí, aby to slyšel{go:|a} {o}."],
	"bruclavy": ["{o} se prý zase hádal{go:|a} se sousedem kvůli plotu.", "{o} si zase na všechno stěžoval{go:|a}, i na počasí, které ještě ani nenastalo.", "{o} dnes ráno nadával{go:|a} na cesty. A to ještě nevstal{go:|a} z postele."],
	"prisny": ["{o} prý dělal{go:|a} sousedovi poznámky, že má trávu moc vysoko.", "{o} dodržuje předpisy tak přísně, že i hodiny mu chodí přesně.", "{o} prý chodí kontrolovat, kdo jak zametl před domem."],
	"veselak": ["{o} byl{go:|a} v hospodě do zavíračky a ještě prý zpíval{go:|a}.", "{o} si včera nechal{go:|a} narazit třetí pivo a pak už nepočítal{go:|a}.", "{o} dělá každému dobrou náladu, hlavně když je kolem pivo."],
	"plachy": ["{o} prý v neděli mluvil{go:|a} s někým déle než deset minut a bylo z toho překvapení.", "{o} je {go:tichý|tichá}, ale ví víc, než říká.", "{o} se na cestě vyhýbá lidem, ale vždycky pozdraví."],
	"moudry": ["{o} vyprávěl{go:|a} dětem pověst o kapličce a zase to bylo dlouhé.", "{o} si pamatuje věci, o kterých už nikdo neví.", "{o} dal{go:|a} sousedovi dobrou radu a ten ji neposlechl."],
	"mlady": ["{o} sedí pořád u mobilu, prý hledá signál.", "{o} prý zase uháněl{go:|a} vsí, že nebylo slyšet nic jiného než tlumič.", "{o} prý plánuje něco velkého, ale zatím spí."],
}
## Drb podle oblíbeného tématu postavy (`topics`).
const GOSSIP_TOPIC := {
	"pole": ["prý zase orá jako o život", "má letos slušnou úrodu, tak se nedá poznat"], "traktor": ["opravuje traktor už třetí týden", "prý zase bouchl traktorem do plotu"],
	"zahrada": ["má nejhezčí zahrádku ve vsi, tak alespoň tvrdí", "zalévá i v dešti, prý kvůli jistotě"], "kostel": ["chodí každou neděli do kostela a zpívá nahlas", "zdobí kapličku a nenechá nikoho pomoct"],
	"fotbal": ["přijde na každý zápas a u toho komentuje každý míč", "prý sestavuje nový tým, ale nemá hráče"], "les": ["chodí do lesa i v noci, pro jistotu", "znáte ho, pořád je v lese"],
	"zver": ["sleduje divočáky a prý je počítá", "si stěžuje na divočáky, že mu rozryli louku"], "vcely": ["má včely a bojí se jich víc než sousedů", "prodává med za cenu, že by se musel stydět"],
	"deti": ["se stará o děti a občas dělá kočku s nimi na bále", "prý ví, kdo z dětí co provedl"], "skola": ["pořád studuje a říká, že se to vyplatí", "prý píše práci o vsi"],
	"auta": ["opravuje auto na dvoře už od jara", "prý zase nechal auto na cestě, že není kam"], "motorka": ["prý zase jezdí na motorce moc rychle", "čistí motorku víc než sebe"],
	"mobil": ["se dívá do telefonu při chůzi a spadl do příkopu", "prý chytil signál u kapličky a nechce ho pustit"], "vino": ["má ve sklepě něco, co nikomu neukáže", "chystá letošní víno a už ho ochutnává"],
	"pivo": ["dává pivo do ledničky i v zimě", "prý zase objevil novou dvanáctku"], "stavba": ["staví a nikdy to není hotové", "prý dělá sousedovi garáž už třetí měsíc"],
	"drby": ["ví všechno, co se ve vsi stalo, i to, co se ještě nestalo", "říká, že nic neříká, ale řekne to všem"], "urad": ["chodí na úřad častěji než do obchodu", "stěžuje si na úřad a jde tam zase"],
	"poradek": ["hlídá pořádek i u sousedů", "zamete i cizí chodník, protože mu to vadí"], "policie": ["prý se kamarádí s policajty, aby věděl, kde stojí", "říká, že policie dělá málo a hodně zároveň"],
	"hasici": ["se hasičům nikdy nevzdá, ani v důchodu", "prý pořád vodí soutěžní stříkačku na návštěvu"], "zdravi": ["radí každému, co má dělat s kašlem", "říká, že pivo je lék, ale jen když není moc"],
	"jidlo": ["peče koláče pro celou ves", "dává sousedům na ochutnání a pak chce recenzi"], "ryby": ["sedí u rybníka, i když nic nechytí", "prý chytil kapra větší než ostatní, nebo aspoň tak tvrdí"],
	"kun": ["by nejradši jezdil na koni, ale nemá ho", "stále mluví o koních a dávných časech"], "jablka": ["trhá jablka a prodává je i sousedům", "prý už má plný sklep jablek"],
	"zvirata": ["má ve dvoře víc zvířat než lidí ve vsi", "prý zase něco ztratil, asi kozu"], "prace": ["makaj od rána do večera a nestěžuje si", "říká, že práce je dost, ale peníze nejsou"],
	"pocasi": ["si stěžuje na počasí, ať je jaké chce", "předpovídá počasí podle kloubů"], "obchod": ["chodí do obchodu každý den, i když nic nepotřebuje", "zná cenu všeho a stěžuje si na všechno"],
	"silnice": ["nadává na díry v silnici a občas do nich i padne", "prý poslal na úřad dopis o díře před domem"],
}
## Jak mluví o jiné postavě podle vztahu (`Dialog.relation`) a povahy mluvčí – {o} = křestní jméno, {oj} = povolání.
const OPINION := {
	"friend": ["{o}? To je dobrá duše, {oj}. Rozumíme si.", "{o} je můj dobrý známý. Je to {oj}, ale srdce na pravém místě.", "{o} je fajn. Občas se potkáme na lavičce a pokecáme."],
	"rival": ["{o}? No… {oj}. Moc si nerozumíme, já bych to dělal{g:|a} jinak.", "{o}? {go:Ten|Ta} mi občas leze na nervy.", "{o} a já, to není zrovna přátelství. Ale jinak slušný člověk."],
	"neutral": ["{o}? Je to {oj}. Znám {go:ho|ji} od vidění.", "{o} je {oj}, co víc k tomu říct?", "{o}? Nic špatného nevím. Je to {oj}."],
}
## Mluvčí, který o lidech nemluví (povaha) – odpověď bez drbu, pokud není přítel.
const NO_GOSSIP := {
	"prisny": ["Do cizích záležitostí se nepletu.", "Lidé nejsou můj obor. Dodržujte řád a bude dobře."],
	"plachy": ["Raději nic neříkám.", "Nerad{g:|a} mluvím o druhých."],
	"bruclavy": ["Co je mi po cizích? Mám dost svého.", "Každému je dost svých starostí."],
}

## Osoby z obsluhy míst a děda (smyšlené, viz `Place.KEEPERS`): klíč, slova (celá slova), jméno, věty.
const FOLK := [
	{"id": "ladi", "words": ["ladi", "ladu", "ladovi", "lada", "hostinsky", "hostinskeho", "hostinskem"], "name": "Láďa", "job": "hostinský v {pub}",
		"lines": ["Láďa točí v {pub} pivo s čepicí jako sníh. Nikdy nespěchá, to je jeho kouzlo.", "Hostinský Láďa ví všechno o všech, ale nikomu nic neřekne. To je řemeslo.", "Láďa prý dvacet let nezměnil jedinou píseň z hudebního automatu."]},
	{"id": "jarka", "words": ["jarka", "jarky", "jarce", "jarku", "prodavacka", "prodavacky", "prodavacku"], "name": "Jarka", "job": "prodavačka v Potravinách",
		"lines": ["Jarka v Potravinách ví, kdo co nakupuje. A nikomu nic neřekne. Skoro.", "Prodavačka Jarka vozí rohlíky od šesti. Kdo přijde dřív, ten je má.", "Jarka mívá vždycky dobrou náladu, dokud ne v neděli."]},
	{"id": "vojta", "words": ["vojta", "vojty", "vojtovi", "vojtu", "palic", "palice", "palicovi"], "name": "Vojta", "job": "palič v Pálenici U Kotla",
		"lines": ["Vojta v Pálenici pálí slivovici, že by ji nechali i v muzeu. Jen nesmíš přijít opilý.", "Palič Vojta prý přesně ví, kolik kdo vypil. A nikomu to nepřipomíná.", "Vojta je bručoun, ale slivovici dělá poctivě."]},
	{"id": "zdenek", "words": ["zdenek", "zdenka", "zdenkovi", "zdenku", "vinar", "vinare", "vinarovi"], "name": "Zdeněk", "job": "vinař",
		"lines": ["Vinař Zdeněk dělá degustace. Kdo se motá, toho vyhodí.", "Zdeněk říká, že víno je poezie v lahvi. A dělá z něj dobrou poezii.", "Ve sklepě mají u Zdeňka chladno a veselo."]},
	{"id": "franta", "words": ["franta", "franty", "frantovi", "frantu", "myslivec", "myslivce", "myslivci"], "name": "Franta", "job": "myslivec u chaty",
		"lines": ["Myslivec Franta chodí po lese tak tiše, že ho nikdo neslyší. Jen jeho klobouk.", "Franta hlídá zvěř i pytláky. Ti druzí ho nemají rádi.", "Franta v chatě vypráví o lese tak, že by poslouchal celý den."]},
	{"id": "starosta", "words": ["novak", "novaka", "novakovi", "novaku", "starosta", "starosty", "starostovi", "starostu"], "name": "starosta Novák", "job": "starosta obce",
		"lines": ["Starosta Novák má pořád co dělat: díry na silnici, rozpočet a lidi.", "Novák je přísný, ale spravedlivý. Nebo aspoň tvrdí.", "Starosta bývá na úřadě dopoledne. Odpoledne je v terénu."]},
	{"id": "deda", "words": ["deda", "dedu", "dedovi", "vomacek", "vomacka", "vomackovi", "vomacku"], "name": "děda Vomáčka", "job": "děda z {deda_home}",
		"lines": ["Děda Vomáčka sedí na lavičce u svého domu ({deda_home}) a dává dobré rady, i když se ho nikdo neptá.", "Děda ví, jak bývalo, a rád to povídá. Stačí si sednout.", "Děda má kolo a motorku. Jezdí podle nálady."]},
	{"id": "stamgasti", "words": ["standa", "standy", "standovi", "vasek", "vaska", "vaskovi", "honza", "honzy", "honzovi"], "name": "páteční štamgasti", "job": "štamgasti v {pub}",
		"lines": ["V pátek sedí v {pub} u druhého stolu Standa, Vašek a Honza. Mluví hlavně o fotbale a politice.", "Páteční parta u druhého stolu nikdy nevyřeší nic, ale hádají se srdečně."]},
]

# ====================================================================== otázky zpět

## Otázka, kterou postava sama položí: text, odpovědi na ano / ne / cokoliv jiného, změna nálady při „ano“, `yes_do` = záměr, který se při „ano“ spustí.
const ASKBACK := {
	"q_weather_walk": {"text": "Jdeš někam na procházku, nebo jen tak hledíš do nebe?", "yes": ["To je dobře, pohyb je zdraví.", "Tak si ji užij."], "no": ["Taky dobrý, doma je taky hezky.", "Jen tak koukat je taky umění."], "other": ["Aha, tak to je zajímavé.", "No vidíš."], "yes_mood": 0.05},
	"q_garden": {"text": "Máš taky nějakou zahrádku, nebo jen koukáš, jak roste u sousedů?", "yes": ["Výborně! Zahrada je radost. Jen nezapomeň zalévat.", "Tak to se máš! Zeleninu z vlastní hlíny nic nepřekoná."], "no": ["Tak si ji obdělej. U usedlosti {lot} máš kus zahrady.", "To je škoda. Semínka se dají koupit v Potravinách."], "other": ["Aha, tak to zkusíme jindy.", "Hm, zajímavé."], "yes_mood": 0.08},
	"q_wood": {"text": "Máš dost dřeva na zimu, nebo zase zjistíš, že je ho málo, až bude mráz?", "yes": ["Chytrý člověk! Dřevo se musí nachystat včas.", "To je dobře. Kdo má dřevo, má klid."], "no": ["Tak se do toho dej. Sekeru mají ve stavebninách.", "Nasekej si, dokud je čas. V zimě je pozdě."], "other": ["No jo, to se musí vyřešit.", "Jak myslíš."], "yes_mood": 0.06},
	"q_pet": {"text": "Máš nějaké zvíře? Psa, kočku, slepice?", "yes": ["To je fajn! Zvířata dělají dům domovem.", "Tak to je dobře. Nezapomeň jim dát vodu."], "no": ["Tak třeba někdy. Kočka je nenáročná.", "Zvíře člověka změní k lepšímu."], "other": ["Aha. Každý má svůj svět.", "Hm."], "yes_mood": 0.07},
	"q_fish": {"text": "Rybaříš taky, nebo jen občas zajdeš k vodě?", "yes": ["To se mi líbí! Dáš někdy ukázat úlovek.", "Tak to máme společné. U vody je klid."], "no": ["Zkus to. Udici koupíš v Potravinách.", "Škoda, rybaření je skvělé na nervy."], "other": ["Aha, nevadí.", "Hm, no dobře."], "yes_mood": 0.08},
	"q_hunt": {"text": "Střílíš, nebo jen koukáš, jak to dělají jiní?", "yes": ["Hlavně ať máš papíry a dodržuješ pravidla.", "Tak opatrně. Zbraň je vážná věc."], "no": ["Je to tak lepší. Kdo nestřílí, nemůže minout.", "Sledování zvěře je taky hezké."], "other": ["No jo, každý má svůj názor.", "Hm."], "yes_mood": 0.03},
	"q_hunt_dummy": {"text": "", "yes": [], "no": [], "other": []},
	"q_car": {"text": "Řídíš, nebo chodíš pěšky jako já?", "yes": ["Tak hlavně opatrně. Silnice jsou plné děr a srn.", "Řidič je dneska zodpovědná profese. Drž se toho."], "no": ["Pěšky se toho vidí víc. A jsi zdravější.", "Dobrá volba, benzín je drahý."], "other": ["No jo, každý jezdí jinak.", "Hm, rozumím."], "yes_mood": 0.04},
	"q_beer": {"text": "Dáme si spolu pivo, nebo radši ne?", "yes": ["Tak to jdu hned! Pojď do hospody.", "Dobrá zpráva! {pub} nás čeká."], "no": ["Dobře, taky se dá pít vodu.", "Škoda. Příště?"], "other": ["No jo, dobrý nápad neodmítnu.", "Hm, rozmyslíme se."], "yes_mood": 0.12, "yes_do": "invite"},
	"q_fotbal": {"text": "Přijdeš se někdy podívat na zápas? Fandění nikdy není dost.", "yes": ["To je dobrá zpráva! Kluci budou mít radost.", "Přijď, přijď. Budeme hlučet dvojnásobně."], "no": ["Škoda, ale pochopím. Fotbal není pro všechny.", "Třeba příště."], "other": ["Aha, rozmysli si to.", "Hm."], "yes_mood": 0.08},
	"q_fire": {"text": "Jak to máš s ohněm, hlídáš ho dobře?", "yes": ["To je dobře. Jedna jiskra a je průšvih.", "Tak to je odpovědné. Uhasit, než odejdeš."], "no": ["Tak to si dej pozor. Oheň nemá rád nepozornost.", "Buď opatrný a miň ho nech samotný."], "other": ["No jo, rozumím.", "Hm."], "yes_mood": 0.04},
	"q_politics": {"text": "Zajímáš se o to, co se děje na úřadě?", "yes": ["To je dobře, občan musí vědět, co se děje.", "Tak to sleduj, nebo nás to vyjde draho."], "no": ["Taky rozumné. Politika je nervy.", "Dobře děláš. Radši zahrádka."], "other": ["No jo, každý má svůj názor.", "Hm."], "yes_mood": 0.03},
	"q_gossip": {"text": "Chceš slyšet, co se povídá ve vsi?", "yes": ["Tak poslouchej…", "No, přisedni si."], "no": ["Tak nic. Drby jsou jen pro zvědavé.", "Dobře, nebudu ti ubírat klid."], "other": ["Aha, tak dobře.", "Hm."], "yes_mood": 0.06, "yes_do": "news"},
	"q_family": {"text": "A máš ty nějakou rodinu, nebo jsi tu sám?", "yes": ["To je krásné. Rodina je to nejdůležitější.", "Tak to se máš dobře. Pozdravuj je."], "no": ["To je škoda. Ale ves je velká rodina, ne?", "Nevadí, sousedé jsou skoro rodina."], "other": ["Aha. Každý má svůj příběh.", "Hm."], "yes_mood": 0.06},
	"q_childhood": {"text": "A jaké bylo tvoje dětství? Na vsi, nebo jinde?", "yes": ["To musí být krásné vzpomínky.", "Děti dneska mají jiný svět, že?"], "no": ["Každý si to pamatuje jinak.", "To je taky příběh."], "other": ["Aha, zajímavé.", "Hm, dobře."], "yes_mood": 0.06},
	"q_food": {"text": "Máš rád dobré jídlo? Co si nejradši dáš?", "yes": ["To se mi líbí. Dobré jídlo spojuje lidi.", "Dobrou chuť příště! Zkus guláš v hospodě."], "no": ["Tak tys nikdy nechutnal koláče, že?", "To se ti pak těžko žije."], "other": ["No vidíš, tak se někdy dáme na jídlo.", "Hm, chuť bývá různá."], "yes_mood": 0.06},
	"q_visit": {"text": "Zastavíš se někdy na kafe? Občas mám čas.", "yes": ["To mě těší. Přijď, až budeš moct.", "Tak jo, těším se."], "no": ["Nevadí, třeba jindy.", "Dobře, chápu."], "other": ["Aha, uvidíme.", "Hm."], "yes_mood": 0.08},
	"q_help": {"text": "Potřebuješ s něčím poradit? Ve vsi se dá sehnat pomoc.", "yes": ["Tak povídej, třeba ti poradím.", "Jasně, zkusíme to spolu."], "no": ["Tak dobře. Kdyby něco, víš, kde mě najdeš.", "Dobře, ale kdyby něco…"], "other": ["Aha, tak to zkus.", "Hm."], "yes_mood": 0.05, "yes_do": "howto"},
	"q_walk": {"text": "Zkusil jsi už procházku po okolí? Je tu co vidět.", "yes": ["Tak to víš, že je tu klid.", "Dobře děláš. Pohyb je zdraví."], "no": ["Tak to udělej. Jdi třeba k lesu, tam jsou houby.", "Zkus to, ves má hezká zákoutí."], "other": ["Aha, uvidíme.", "Hm."], "yes_mood": 0.04},
	"q_village": {"text": "Jak se ti u nás líbí? Zvykáš si?", "yes": ["To je dobře, pak tu budeš spokojený.", "Dukelčice si tě najdou."], "no": ["To se spraví. Chce to čas.", "Dej tomu čas, ves si každého získá."], "other": ["Aha, zajímavé.", "Hm."], "yes_mood": 0.07},
	"q_mushroom": {"text": "Sbíráš houby? Nebo se jich bojíš?", "yes": ["Dobře, jen je dobře poznej. Jedovatých je dost.", "To je skvělé! Nasbírej na smaženici."], "no": ["Tak to zkus. Je to zábava a dobré jídlo.", "Jen pozor, ať si něco nespleteš."], "other": ["No vidíš.", "Hm."], "yes_mood": 0.06},
	"q_tech": {"text": "Máš v telefonu signál? U mě jen na půl čárky.", "yes": ["To máš štěstí. Já jen u kapličky.", "Dobrý! Tak mi jednou pošli ten jeho kód."], "no": ["Taky nic. Jděte k kapličce, tam to chytne.", "To znám, ves je na signál chudá."], "other": ["Aha, tak to je fuška.", "Hm."], "yes_mood": 0.04},
	"q_music": {"text": "Posloucháš rád hudbu? Jakou nejradši?", "yes": ["To je fajn. Hudba je dobrá na všechno.", "Tak to máme společné. Tancuješ taky?"], "no": ["Tak to je škoda. Hudba zlepšuje náladu.", "No, ticho je taky dobré."], "other": ["Aha, každý má svůj vkus.", "Hm."], "yes_mood": 0.05},
	"q_event": {"text": "Budeš slavit s námi, nebo půjdeš jinam?", "yes": ["To se mi líbí! Ve společnosti je to lepší.", "Tak přijď. Bude veselo."], "no": ["Škoda, ale pochopím.", "Nevadí, třeba příště."], "other": ["Aha, rozmyslíš si to.", "Hm."], "yes_mood": 0.06},
	"q_ghost": {"text": "Nebojíš se chodit v noci venku?", "yes": ["Tak jsi odvážný. Já bych tam {g:nešel|nešla}.", "No, statečnost je dobrá, ale baterka lepší."], "no": ["Rozumný. Noc je noc.", "Tak nechoď. Doma je tepleji."], "other": ["No jo.", "Hm."], "yes_mood": 0.03},
	"q_philo": {"text": "A co tebe nejvíc těší v životě?", "yes": ["To je krásné, nezapomeň na to.", "Tak to je dobré. Těšit se je základ."], "no": ["To se spraví. Hlavně nevěšet hlavu.", "Uvidíš, že přijde něco dobrého."], "other": ["No vidíš.", "Hm, zajímavé."], "yes_mood": 0.05},
	"q_offer_news": {"text": "Mimochodem, nechceš slyšet čerstvou novinku?", "yes": ["Tak poslouchej…", "Tak dobře, ale nikomu to neříkej…"], "no": ["Dobře, tak třeba příště.", "Tak nic, nechám si to."], "other": ["No, jak myslíš.", "Hm."], "yes_mood": 0.05, "yes_do": "news"},
	"q_offer_joke": {"text": "Znáš ten o farmářovi a traktoru? Nechceš slyšet?", "yes": ["Tak poslouchej…", "Dobře, tady je…"], "no": ["Tak ne, škoda.", "No, tak příště."], "other": ["No, tak příště.", "Hm."], "yes_mood": 0.05, "yes_do": "joke"},
	"q_offer_pub": {"text": "Nezajdeme večer do {pub}? Jedno pivo s tebou by se hodilo.", "yes": ["Tak to je řeč! Uvidíme se tam.", "Domluveno. Těším se."], "no": ["Škoda, ale chápu.", "Tak příště."], "other": ["No, rozmysli si to.", "Hm."], "yes_mood": 0.12, "yes_do": "invite"},
	"q_where_from": {"text": "A ty odkud vlastně jsi? Nejsi odsud, že?", "yes": ["Tak vítej. Doufám, že se ti tu bude líbit.", "No vidíš, každý odněkud."], "no": ["Tak jsi odsud a já tě neznám? To není možné.", "Aha, tak to je překvapení."], "other": ["Zajímavé, ve vsi se to rozkřikne.", "Aha, tak to bys mohl vyprávět."], "yes_mood": 0.05},
}
## Kterou otázku nabídnout zpět, když téma nemá `ask`, nebo jaké nabídky dát (povaha → klíče `ASKBACK` s prefixem q_offer_ / q_where_from).
const ASK_OFFER := {
	"drbna": ["q_offer_news", "q_gossip"], "veselak": ["q_offer_joke", "q_offer_pub"], "pratelsky": ["q_visit", "q_offer_news", "q_where_from"], "moudry": ["q_childhood", "q_village", "q_philo"],
	"mlady": ["q_music", "q_tech", "q_offer_pub"], "bruclavy": ["q_politics"], "prisny": ["q_politics"], "plachy": ["q_walk"],
}

# ====================================================================== vtipy

## Vtipy (obecný repertoár – laskavé, bez nenávistného obsahu, bez reálných jmen a firem).
const JOKES := [
	"Víš, proč má traktor velká zadní kola? Aby se mu dobře couvalo z hospody!",
	"Potká farmář souseda: „Mé slepice přestaly snášet.“ „A zkoušel jsi jim pustit rádio?“ „Jo, ale jen si stěžují na cenu vajec.“",
	"Jak poznáš, že je vesničan na dovolené? Má vypnutou sekačku.",
	"Přijde houbař do lesa a hřib na něj: „Dneska ne, mám volno.“",
	"Starosta slíbil novou silnici. Díry už máme, teď čekáme na asfalt.",
	"Proč si hasič nevzal dovolenou? Protože mu pořád hořelo.",
	"Sedí dva rybáři u rybníka. Jeden povídá: „Dneska neberou.“ Druhý: „Neberou ani včera.“ „A proč tu sedíme?“ „Je tu klid.“",
	"Říká babička vnukovi: „Ve tvém věku jsem chodila pět kilometrů do školy.“ „A co jsi tam dělala?“ „Sedávala na lavičce, než zazvonilo.“",
	"Jaký je rozdíl mezi zahrádkářem a optimistou? Optimista ještě nezjistil, že mu slimáci sežrali salát.",
	"Přijde chlap do hospody: „Pivo, prosím.“ „Dvanáctku?“ „Ne, dvanáctka mi včera řekla, že už nechce.“",
	"Potkají se dvě sousedky: „Slyšela jsi, co se stalo u Nováků?“ „Ne!“ „No, já taky ne, ale můžeme si to vymyslet.“",
	"Na vsi se poznáš podle toho, že když řekneš ‚kousek odsud‘, je to tři kilometry a dva kopce.",
	"Kolik myslivců je potřeba na výměnu žárovky? Jen jeden, ale ta žárovka musí stát v posedu.",
	"Říká dědek: „Za mých mladých let byla tráva zelenější.“ „Dědo, to je tím, že jsi byl mladý.“ „Ne, tím, že jsme neměli sekačky.“",
	"Hostinský se ptá hosta: „Jak vám chutná guláš?“ „Výborně, hlavně že je to pořád ta samá kráva.“",
	"Proč slepice přešla silnici? Protože pes na druhé straně nevěděl, jak se otevírá branka.",
	"Jede pan Novák autem a volá: „Pane policisto, já jsem nepil!“ „A proč se tedy vyhýbáte čáře?“ „Protože ji viděl dvakrát.“",
	"Učitelka: „Kdo z vás ví, kolik je dvakrát dvě?“ Pepíček: „Čtyři.“ „A trojnásobek?“ „Nevím, to je zrovna v mobilu.“",
	"Jede traktorista kolem pole a vidí strašáka. „Co tady děláš?“ „Hlídám.“ „A co tě to baví?“ „No, sousedi aspoň pozdraví.“",
	"Sedí dva důchodci na lavičce. „Vidíš, jak jde čas.“ „Jo, právě jde rychleji než my.“",
	"Zeptal se klučina kamaráda: „Jak poznám, že je kohout unavený?“ „Když zapomene zakokrhat.“",
	"Proč si včelař nestěžuje? Protože ho už nic nemůže bodnout.",
	"Potká ježek ježka: „Jak se máš?“ „Jde to, jen mě trochu bodá svědomí.“",
	"Žena říká: „Ty ani nevíš, kdy mám narozeniny!“ „Vím, jen nevím, kolikátý rok to je.“",
]

## Vtipy podle povahy postavy (navíc k obecným, jen pokud postava vtipy vypráví).
const JOKES_TRAIT := {
	"veselak": ["Víš, proč je pivo lepší než manželka? Pivo se dá vypít, ale manželka se nedá přežvýkat. No, vlastně to je na jiný vtip…", "Přijde Kája do hospody a hlásí: „Všichni dneska platí, já jsem zapomněl peněženku u sousedky!“"],
	"moudry": ["Nejlepší rada je ta, kterou nikdo neposlechne. To jsem zažil{g:|a} už padesátkrát.", "Víš, co říkal můj děd? ‚Kdo se směje naposled, tomu to došlo.‘"],
	"mlady": ["Kámo, víš, proč je telefon smutný? Protože má pořád slabou baterku a silný signál do slz.", "Jak poznáš hackera na vsi? Jako jediný má vždycky nabíječku."],
	"pratelsky": ["Proč je sousedka tak milá? Protože jí to nikdo nezakázal.", "Víš, jak se poznají dobří sousedé? Půjčí si sekačku a vrátí ji s plnou nádrží."],
	"drbna": ["Víš, proč je ve vsi tak málo tajemství? Protože sousedka ráda pomáhá s jejich šířením.", "Vtip? Nevím, ale slyšela jsem jednu věc, co je lepší než vtip…"],
}

## Kdo jaké věty říká, když hráč prosí o „víc“ a témata došla (žádná další věta ani rada).
const NOTHING_MORE := ["K tomu jsem vyčerpal{g:|a} všechno.", "Víc už k tomu nevím, {voc}. Zeptej se na něco jiného.", "To je tak všechno, co umím říct."]
