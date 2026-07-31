class_name YakuId

# State-driven
const RIICHI = 0
const IPPATSU = 1
const DOUBLE_RIICHI = 2
const MENZEN_TSUMO = 3
const HAITEI = 4
const HOUTEI = 5
const RINSHAN = 6
const CHANKAN = 7

# Yakuhai
const YAKUHAI_HAKU = 8
const YAKUHAI_HATSU = 9
const YAKUHAI_CHUN = 10
const YAKUHAI_BAKAZE = 11
const YAKUHAI_JIKAZE = 12

# 1 han pattern
const PINFU = 13
const IIPEIKOU = 14
const TANYAO = 15

# 2 han pattern
const SANSHOKU_DOUJUN = 16
const ITTSU = 17
const HONCHANTA = 18
const CHIITOITSU = 19
const TOITOI = 20
const SANANKOU = 21
const SANSHOKU_DOUKOU = 22
const SANKANTSU = 23
const SHOUSANGEN = 24

# 3 han pattern
const RYANPEIKOU = 25
const JUNCHAN = 26
const HONITSU = 27

# 6 han
const CHINITSU = 28

# Yakuman
const KOKUSHI = 29
const KOKUSHI_13 = 30           # double yakuman variant
const DAISANGEN = 31
const SUUANKOU = 32
const SUUANKOU_TANKI = 33       # double yakuman variant
const TSUUIISOU = 34
const RYUUIISOU = 35
const CHINROUTOU = 36
const SUUKANTSU = 37
const SHOUSUUSHI = 38
const DAISUUSHI = 39            # double yakuman variant
const CHUUREN = 40
const JUNSEI_CHUUREN = 41       # double yakuman variant
const TENHOU = 42
const CHIIHOU = 43

# 40 个'基础'役（state 10 + yakuhai 5 + 1han 3 + 2han 9 + 3han 3 + 6han 1 + yakuman 9）
const ALL: Array[int] = [
	RIICHI, IPPATSU, DOUBLE_RIICHI, MENZEN_TSUMO, HAITEI, HOUTEI, RINSHAN, CHANKAN, TENHOU, CHIIHOU,
	YAKUHAI_HAKU, YAKUHAI_HATSU, YAKUHAI_CHUN, YAKUHAI_BAKAZE, YAKUHAI_JIKAZE,
	PINFU, IIPEIKOU, TANYAO,
	SANSHOKU_DOUJUN, ITTSU, HONCHANTA, CHIITOITSU, TOITOI, SANANKOU, SANSHOKU_DOUKOU, SANKANTSU, SHOUSANGEN,
	RYANPEIKOU, JUNCHAN, HONITSU,
	CHINITSU,
	KOKUSHI, DAISANGEN, SUUANKOU, TSUUIISOU, RYUUIISOU, CHINROUTOU, SUUKANTSU, SHOUSUUSHI, CHUUREN,
]

const ALL_VARIANTS: Array[int] = [
	KOKUSHI_13, SUUANKOU_TANKI, DAISUUSHI, JUNSEI_CHUUREN,
]

# 元数据
static func metadata(yid: int) -> Dictionary:
	match yid:
		RIICHI: return {"name_zh": "立直", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		IPPATSU: return {"name_zh": "一発", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		DOUBLE_RIICHI: return {"name_zh": "W立直", "base_han_closed": 2, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		MENZEN_TSUMO: return {"name_zh": "门前清自摸和", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		HAITEI: return {"name_zh": "海底捞月", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		HOUTEI: return {"name_zh": "河底捞鱼", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		RINSHAN: return {"name_zh": "岭上开花", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		CHANKAN: return {"name_zh": "抢杠", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_HAKU: return {"name_zh": "役牌·白", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_HATSU: return {"name_zh": "役牌·发", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_CHUN: return {"name_zh": "役牌·中", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_BAKAZE: return {"name_zh": "场风牌", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		YAKUHAI_JIKAZE: return {"name_zh": "自风牌", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		PINFU: return {"name_zh": "平和", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		IIPEIKOU: return {"name_zh": "一杯口", "base_han_closed": 1, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		TANYAO: return {"name_zh": "断幺九", "base_han_closed": 1, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		SANSHOKU_DOUJUN: return {"name_zh": "三色同顺", "base_han_closed": 2, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		ITTSU: return {"name_zh": "一気通貫", "base_han_closed": 2, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		HONCHANTA: return {"name_zh": "混全带幺九", "base_han_closed": 2, "base_han_open": 1, "is_yakuman": false, "yakuman_multiplier": 0}
		CHIITOITSU: return {"name_zh": "七対子", "base_han_closed": 2, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		TOITOI: return {"name_zh": "対々和", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		SANANKOU: return {"name_zh": "三暗刻", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		SANSHOKU_DOUKOU: return {"name_zh": "三色同刻", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		SANKANTSU: return {"name_zh": "三杠子", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		SHOUSANGEN: return {"name_zh": "小三元", "base_han_closed": 2, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		RYANPEIKOU: return {"name_zh": "二杯口", "base_han_closed": 3, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}
		JUNCHAN: return {"name_zh": "纯全带幺九", "base_han_closed": 3, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		HONITSU: return {"name_zh": "混一色", "base_han_closed": 3, "base_han_open": 2, "is_yakuman": false, "yakuman_multiplier": 0}
		CHINITSU: return {"name_zh": "清一色", "base_han_closed": 6, "base_han_open": 5, "is_yakuman": false, "yakuman_multiplier": 0}
		KOKUSHI: return {"name_zh": "国士無双", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		KOKUSHI_13: return {"name_zh": "国士無双13面", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 2}
		DAISANGEN: return {"name_zh": "大三元", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		SUUANKOU: return {"name_zh": "四暗刻", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		SUUANKOU_TANKI: return {"name_zh": "四暗刻単騎", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 2}
		TSUUIISOU: return {"name_zh": "字一色", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		RYUUIISOU: return {"name_zh": "绿一色", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		CHINROUTOU: return {"name_zh": "清老头", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		SUUKANTSU: return {"name_zh": "四杠子", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		SHOUSUUSHI: return {"name_zh": "小四喜", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		DAISUUSHI: return {"name_zh": "大四喜", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 2}
		CHUUREN: return {"name_zh": "九蓮宝燈", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		JUNSEI_CHUUREN: return {"name_zh": "纯正九蓮宝燈", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 2}
		TENHOU: return {"name_zh": "天和", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
		CHIIHOU: return {"name_zh": "地和", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": true, "yakuman_multiplier": 1}
	return {"name_zh": "?", "base_han_closed": 0, "base_han_open": 0, "is_yakuman": false, "yakuman_multiplier": 0}


# 面向役种图鉴的教学元数据。检测与番数仍只消费 metadata()，这里不参与规则判定。
static func catalog_metadata(yid: int) -> Dictionary:
	var base := metadata(yid).duplicate()
	var teaching := _teaching_copy(yid)
	base["category"] = teaching[0]
	base["description"] = teaching[1]
	base["condition"] = teaching[2]
	base["example"] = teaching[3]
	return base


static func _teaching_copy(yid: int) -> Array[String]:
	match yid:
		RIICHI:
			return ["一番役", "门清听牌后宣告并支付立直棒。", "必须门清；宣告后只能摸切，直到和牌。", "示例：门清听牌时宣告立直。"]
		IPPATSU:
			return ["场况役", "立直后的一巡内和牌。", "期间不能发生吃、碰或杠导致巡目中断。", "示例：立直后的下一次摸牌自摸。"]
		DOUBLE_RIICHI:
			return ["二番役", "第一巡尚未鸣牌时宣告立直。", "必须门清，且在自己的第一次弃牌时宣告。", "示例：起手听牌，首巡双立直。"]
		MENZEN_TSUMO:
			return ["一番役", "门清状态下自摸和牌。", "明吃、明碰或明杠后不成立；暗杠不破坏门清。", "示例：门清两面听后自摸和牌。"]
		HAITEI:
			return ["场况役", "以牌山最后一张牌自摸。", "必须由最后一次正常摸牌直接和牌。", "示例：海底牌自摸。"]
		HOUTEI:
			return ["场况役", "荣和本局最后一张弃牌。", "必须是牌山耗尽前最后一次弃牌。", "示例：河底牌荣和。"]
		RINSHAN:
			return ["场况役", "开杠后用岭上牌自摸。", "杠成立并摸岭上牌，随后立即和牌。", "示例：暗杠后岭上开花。"]
		CHANKAN:
			return ["场况役", "在他家加杠时荣和该张牌。", "通常针对加杠；国士无双可按规则抢暗杠。", "示例：对手加杠时抢杠和。"]
		YAKUHAI_HAKU, YAKUHAI_HATSU, YAKUHAI_CHUN:
			return ["一番役", "由三元牌组成刻子或杠子。", "白、发、中每一种分别计算一番。", "示例：三张白组成刻子。"]
		YAKUHAI_BAKAZE:
			return ["一番役", "场风牌组成刻子或杠子。", "牌组必须与当前场风相同。", "示例：东场组成东风刻子。"]
		YAKUHAI_JIKAZE:
			return ["一番役", "自风牌组成刻子或杠子。", "牌组必须与玩家当前座风相同。", "示例：南家组成南风刻子。"]
		PINFU:
			return ["一番役", "全部由顺子构成、无符点的门清役。", "非役牌雀头，且必须两面听。", "示例：234m 345m 456p 678s 55p，两面听。"]
		IIPEIKOU:
			return ["一番役", "同一花色有两组完全相同的顺子。", "必须门清。", "示例：两组 234m。"]
		TANYAO:
			return ["一番役", "所有牌都是二至八的中张牌。", "手牌中不能出现一、九或字牌。", "示例：234m 456p 678s 等中张组合。"]
		SANSHOKU_DOUJUN:
			return ["二番役", "万、筒、索各有一组相同数字顺子。", "副露后由二番降为一番。", "示例：123m 123p 123s。"]
		ITTSU:
			return ["二番役", "同一花色集齐 123、456、789 三组顺子。", "副露后由二番降为一番。", "示例：123m 456m 789m。"]
		HONCHANTA:
			return ["二番役", "每组面子及雀头都含幺九牌或字牌，并至少有顺子。", "副露后由二番降为一番。", "示例：123m 789p 东东东 999s 白白。"]
		CHIITOITSU:
			return ["二番役", "由七组不同对子组成的特殊牌型。", "必须门清；固定计 25 符。", "示例：11m 22m 33p 44p 55s 66s 东东。"]
		TOITOI:
			return ["二番役", "四组面子全部为刻子或杠子。", "可以副露。", "示例：111m 222p 777s 东东东 白白。"]
		SANANKOU:
			return ["二番役", "拥有三组未通过荣和完成的暗刻或暗杠。", "手牌整体可以有副露。", "示例：三组自摸形成的暗刻。"]
		SANSHOKU_DOUKOU:
			return ["二番役", "万、筒、索各有一组相同数字刻子。", "可以副露。", "示例：777m 777p 777s。"]
		SANKANTSU:
			return ["二番役", "一手牌中完成三个杠子。", "明杠、暗杠和加杠均可计入。", "示例：三组已经成立的杠子。"]
		SHOUSANGEN:
			return ["二番役", "三元牌中两组刻子或杠子，另一种作雀头。", "三元牌刻子还分别计算役牌。", "示例：白白白 发发发 中中。"]
		RYANPEIKOU:
			return ["三番役", "同一手中有两组一杯口。", "必须门清；成立时不再重复计算一杯口。", "示例：两组 234m 与两组 678p。"]
		JUNCHAN:
			return ["三番役", "每组面子及雀头都含一或九，且没有字牌。", "副露后由三番降为二番。", "示例：123m 789m 111p 789s 99p。"]
		HONITSU:
			return ["三番役", "只使用一种数牌花色和字牌。", "副露后由三番降为二番。", "示例：全部万子与东南白等字牌。"]
		CHINITSU:
			return ["六番役", "整手牌只使用一种数牌花色。", "副露后由六番降为五番。", "示例：整手全部由万子组成。"]
		KOKUSHI, KOKUSHI_13:
			return ["役满", "集齐十三种幺九字牌并有其中一组对子。", "必须门清；十三面听变体按双倍役满。", "示例：十三种幺九字牌各一张，再配任意一张。"]
		DAISANGEN:
			return ["役满", "白、发、中全部组成刻子或杠子。", "可以副露，可能触发包牌。", "示例：白白白 发发发 中中中。"]
		SUUANKOU, SUUANKOU_TANKI:
			return ["役满", "拥有四组暗刻或暗杠。", "普通形必须自摸；单骑听变体按双倍役满。", "示例：四组暗刻加一组雀头。"]
		TSUUIISOU:
			return ["役满", "整手牌全部由字牌组成。", "可以由刻子牌型或七对子牌型成立。", "示例：东南西北白发中组成的牌型。"]
		RYUUIISOU:
			return ["役满", "整手只使用绿色牌。", "可用 2、3、4、6、8 索及发。", "示例：234s 666s 888s 发发发 22s。"]
		CHINROUTOU:
			return ["役满", "整手牌全部由数牌的一和九组成。", "只能由刻子、杠子和雀头构成。", "示例：111m 999m 111p 999s 11s。"]
		SUUKANTSU:
			return ["役满", "一手牌中完成四个杠子。", "和牌前四杠必须全部成立。", "示例：四组杠子加一组雀头。"]
		SHOUSUUSHI:
			return ["役满", "三种风牌成刻子或杠子，第四种作雀头。", "可以副露。", "示例：东东东 南南南 西西西 北北。"]
		DAISUUSHI:
			return ["役满", "东南西北四种风牌全部成刻子或杠子。", "本规则按双倍役满，可能触发包牌。", "示例：四组风牌刻子。"]
		CHUUREN, JUNSEI_CHUUREN:
			return ["役满", "同一花色构成 1112345678999 加任意一张同花色牌。", "必须门清；纯正九面听按双倍役满。", "示例：1112345678999m 的九面听。"]
		TENHOU:
			return ["役满", "庄家配牌完成后立即自摸和牌。", "第一巡且期间不能发生鸣牌。", "示例：庄家起手即和。"]
		CHIIHOU:
			return ["役满", "闲家在第一巡摸牌时自摸和牌。", "此前不能发生鸣牌。", "示例：闲家第一次摸牌即和。"]
	return ["其他", "日麻役种。", "满足该役在当前规则中的检测条件。", "示例：查看成立条件。"]
