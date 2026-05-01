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
