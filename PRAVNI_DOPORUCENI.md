# Právní a vývojová doporučení pro 3D hru (reálná obec, satira)

Tento dokument shrnuje právní pravidla, rizika a doporučené postupy při tvorbě 3D hry, která využívá reálné rozložení terénu a budov obce (konkrétně modelováno na příkladu obce Dukelčic), se satirickým námětem (přežití, konzumace alkoholu, vyhýbání se policii).

---

## 1. Zdroje geodat a licenční podmínky

Samotná topografie zemského povrchu není autorskoprávním dílem, avšak digitální datové sady a snímky ano.

* **Bezpečné zdroje (Open Data):**
  * **ČÚZK (Český úřad zeměměřický a katastrální):** Poskytuje výškopisná data (DMR 4G/5G) a ortofotomapy v režimu otevřených dat, která lze legálně využít jako podklad pro výškovou mapu a tvar terénu.
  * **OpenStreetMap (OSM):** Vhodné pro silniční síť a půdorysy parcel/budov. Pozor na licenci **ODbL**, která vyžaduje uvedení autorství a specifický přístup k odvozeným databázím.
* **Rizikové zdroje:**
  * **Google Earth / Google Maps / Street View:** Přísné licenční podmínky striktně zakazují ripování, reverzní inženýrství, extrakci 3D meshů a použití fototextur v herních enginech (Unity, Unreal Engine apod.).

---

## 2. Architektura a Svoboda panoramatu

* **Svoboda panoramatu (§ 33 Autorského zákona č. 121/2000 Sb.):**
  * Umožňuje zaznamenat nebo vyobrazit dílo trvale umístěné na veřejném prostranství (zvenčí z ulice).
* **Běžná vesnická zástavba:**
  * Klasické rodinné domy, hospodářská stavení a starší domy nepředstavují unikátní architektonická autorská díla moderních autorů.
  * Tvorba 3D modelů inspirovaných touto zástavbou je autorskoprávně bezpečná.
* **Památky a dominanty:**
  * Kaple, kostely, pomníky nebo budova obecního úřadu jsou součástí veřejného prostoru a jejich vnější zobrazení je v souladu se zákonem.

---

## 3. Ochrana osobnosti a soukromí (Občanský zákoník § 81 a násl.)

Jelikož hra obsahuje prvky nelegálního jednání, alkoholu a střetů s policií, je klíčové zamezit spojení konkrétních reálných osob s herním obsahem:

* **Zákaz identifikátorů:**
  * Na texturách ani modelech nesmí být **reálná čísla popisná / orientační**.
  * Nesmí se objevit **jména rodin na schránkách a zvoncích**.
  * Pokud používáte reálné fototextury, musíte odstranit **SPZ vozidel** a **obličeje osob**.
  * Nesmí být zobrazeny průhledy do soukromí (přes ploty do dvorů, detaily oken).
* **Fikce zástavby:**
  * Zachování reálných pozic domů na parcelách v kombinaci s **odlišnými fasádami, vymyšlenými interiéry a modifikovanými zahradami** vytváří zřejmou fikci a spolehlivě eliminuje žaloby na zásah do dobré pověsti majitelů nemovitostí.
* **NPC postavy:**
  * Herní postavy (hospodský, policista, sousedé) nesmí nést reálná jména ani karikaturní podobizny žijících obyvatel obce.

---

## 4. Ochranné známky a obecní symbolika

* **Firemní značky:**
  * Cedule hospod (značky piva), loga obchodů či billboardy je nutné nahradit parodickými nebo fiktivními názvy (ochrana ochranných známek).
* **Obecní symboly:**
  * Nepoužívejte oficiální **znak a prapor obce** – jejich užití může podléhat schválení zastupitelstvem podle zákona o obcích.

---

## 5. Prevence sporů se samosprávou (Doporučený postup)

Pokud chcete předejít zbytečným konfliktům s obecním zastupitelstvem kvůli tématu hry:

1. **Jemná změna názvu obce (tzv. přístup GTA / My Summer Car):**
   * Ponechte reálnou silniční síť a kopce, ale obec ve hře mírně přejmenujte (např. *Dukelčice*, *Jílka* či místním slangovým označením).
2. **Právní doložka (Disclaimer):**
   * Do úvodu hry a popisu projektu vložte standardní text:
     > *„Tato hra je satirickým uměleckým dílem. Všechny postavy, události a vyobrazené soukromé objekty jsou smyšlené. Jakákoliv podobnost se skutečnými osobami či konkrétními obydlími je čistě náhodná.“*