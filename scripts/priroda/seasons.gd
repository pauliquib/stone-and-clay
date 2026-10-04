## Roční období – vegetace a klima podle dne v roce (pro střední Moravu, ~250–400 m n. m.).
## Všechny křivky jsou tabulky [den v roce, hodnota] s lineární interpolací – upravují se přímo tady.
## Používá je Weather (teploty, pravděpodobnost počasí), klient (barvy stromů a trávy přes globální
## parametry shaderů) a Fauna (aktivita zvířat, tažní ptáci).
class_name Seasons
extends RefCounted

## Olistění listnáčů 0..1: rašení v dubnu, plné olistění od poloviny května, opad od poloviny října.
const FOLIAGE := [[1, 0.0], [100, 0.0], [115, 0.35], [135, 1.0], [285, 1.0], [300, 0.6], [318, 0.12], [330, 0.0], [366, 0.0]]
## Podzimní zbarvení listí 0..1 (0 zelené, 1 žluté / oranžové / červené).
const AUTUMN := [[1, 0.0], [250, 0.0], [268, 0.15], [285, 0.7], [298, 1.0], [366, 1.0]]
## Svěžest trávy a polí 0..1 (1 jarní zeleň, 0 zimní hnědá / sláma).
const GREEN := [[1, 0.2], [65, 0.25], [95, 0.7], [125, 1.0], [180, 0.95], [220, 0.7], [250, 0.65], [300, 0.5], [335, 0.25], [366, 0.2]]
## Kvetení (louky, sady) 0..1 – pro včely.
const BLOOM := [[1, 0.0], [75, 0.0], [95, 0.4], [115, 1.0], [170, 0.9], [230, 0.5], [270, 0.15], [290, 0.0], [366, 0.0]]

## Průměrná denní teplota podle měsíce (°C, normál 1991–2020) a denní rozkmit (max − min).
const TEMP_MEAN := [-1.2, 0.3, 4.2, 9.6, 14.4, 17.8, 19.6, 19.2, 14.6, 9.4, 4.4, 0.2]
const TEMP_RANGE := [5.5, 7.0, 9.0, 11.0, 11.5, 11.5, 12.0, 12.0, 11.0, 9.5, 6.5, 5.0]
## Počet dní se srážkami ≥ 1 mm za měsíc a podíl bouřek na srážkových dnech.
const WET_DAYS := [7, 7, 7, 7, 9, 9, 9, 8, 7, 6, 7, 8]
const STORM_SHARE := [0.0, 0.0, 0.0, 0.03, 0.12, 0.25, 0.3, 0.25, 0.1, 0.01, 0.0, 0.0]


static func curve(table: Array, doy: float) -> float:
	if doy <= table[0][0]:
		return table[0][1]
	for i in range(1, table.size()):
		if doy <= table[i][0]:
			var a: Array = table[i - 1]
			var b: Array = table[i]
			return lerpf(a[1], b[1], (doy - a[0]) / float(b[0] - a[0]))
	return table[table.size() - 1][1]


static func foliage(doy: float) -> float:
	return curve(FOLIAGE, doy)


static func autumn(doy: float) -> float:
	return curve(AUTUMN, doy)


static func green(doy: float) -> float:
	return curve(GREEN, doy)


static func bloom(doy: float) -> float:
	return curve(BLOOM, doy)


## Hodnota měsíční tabulky interpolovaná k danému dni v roce (středy měsíců ~ den 15, 46, …).
static func monthly(table: Array, doy: float) -> float:
	var m := fposmod((doy - 15.0) / 30.44, 12.0)
	var i := int(m)
	return lerpf(table[i], table[(i + 1) % 12], m - i)


## Tažní ptáci (vlaštovky) jsou u nás zhruba od 5. dubna do 20. září.
static func swallows_present(doy: float) -> bool:
	return doy > 95.0 and doy < 263.0
