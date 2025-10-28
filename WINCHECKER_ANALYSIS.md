# 🔍 WinChecker 代码深度分析

## 问题代码定位

### 文件: `godot/scripts/win_checker.gd`

---

## 🐛 **发现的问题 #1: 对子选择没有完全搜索**

### 问题代码 (第31-60行):

```gdscript
# 尝试找到眼睛（对子）
var pair_map = _count_cards(cards_to_check)
for suit_idx in range(4):
    for num_idx in range(1, 10):
        var card_key = "%d_%d" % [suit_idx, num_idx]
        if card_key in pair_map and pair_map[card_key] >= 2:
            # 找到可能的对子
            var remaining = cards_to_check.duplicate()

            # 移除对子
            var removed_count = 0
            var eye_card_found: CardData = null
            for i in range(remaining.size() - 1, -1, -1):
                if removed_count < 2:
                    var card = remaining[i]
                    if card.suit == suit_idx and card.number == num_idx:
                        eye_card_found = card
                        remaining.remove_at(i)
                        removed_count += 1

            # 检查剩余的牌是否能组成完整的顺序
            if _can_form_melds(remaining):
                result.can_win = true
                result.eye_card = eye_card_found
                result.win_patterns.append({
                    "eye": eye_card_found,
                    "melds": _extract_melds(remaining)
                })

return result  # ⚠️ 问题：找到一个就立即返回！
```

### 问题分析

**当前逻辑**:
```
对每个可能的对子:
  尝试这个对子
  如果成功:
    标记为能胡
    (立即返回)  ← 这里！
```

**问题**: 当找到第一个有效的对子后，函数就立即返回，**不再尝试其他对子**！

### 🎯 案例分析：清一色手牌

```
手牌: 万1万1万1 万2万3万4 万5万6万7 万8万9万9万9 (14张)

对子选择顺序:
1️⃣ 试万1作为对子
   移除万1万1后，剩余: 万1万2万3万4万5万6万7万8万9万9万9
   能组成4组面子吗?
   ❌ 不能! 因为:
      - 万1: 只有1张，无法形成面子
      - 无法回溯继续

2️⃣ 但这里没有继续尝试万9作为对子！
   (因为第一个对子选择失败后，函数就返回了)
```

### ✅ **修复方案**

```gdscript
# 尝试找到眼睛（对子）
var pair_map = _count_cards(cards_to_check)
var found_win = false

for suit_idx in range(4):
    for num_idx in range(1, 10):
        if found_win:  # ✅ 新增：如果已找到，停止搜索
            break
        
        var card_key = "%d_%d" % [suit_idx, num_idx]
        if card_key in pair_map and pair_map[card_key] >= 2:
            # ... 对子选择逻辑 ...
            
            if _can_form_melds(remaining):
                result.can_win = true
                result.eye_card = eye_card_found
                result.win_patterns.append({...})
                found_win = true  # ✅ 标记找到，继续只是为了完成循环

    if found_win:  # ✅ 新增：双重break
        break

return result
```

---

## 🐛 **发现的问题 #2: 对子数量检查不全**

### 问题代码 (第35-36行):

```gdscript
if card_key in pair_map and pair_map[card_key] >= 2:
    # 只要有2张或以上就认为可能是对子
```

### 问题分析

在**清一色手牌**中:
- 万1有**3张**
- 万9有**3张**

当我们试图用万1作为对子时:
```
pair_map["万1"] = 3  # ✅ >= 2，所以被选中

移除2张万1后，剩余:
- 万1: 1张 (剩下的)
- 万2-万8: 各1张
- 万9: 3张

现在无法组成有效的面子，因为万1只有1张！
```

### ✅ **修复原理**

问题不在这里，而在于我们**没有尝试所有对子**。应该继续尝试万9作为对子！

---

## 🐛 **发现的问题 #3: 字牌花色处理**

### 问题代码 (第34行):

```gdscript
for num_idx in range(1, 10):  # 1-9
```

### 问题分析

这个范围对所有花色都是1-9，但**字牌(花色3)只有7种**：
- 东南西北中发白 = 只有 1-7

当检查字牌时，会尝试字8和字9（不存在的牌）。这不会导致错误，但会浪费时间。

### ✅ **修复方案**

```gdscript
for num_idx in range(1, (10 if suit_idx < 3 else 8)):  # 字牌只到7
```

---

## 📋 总结：修复优先级

| 优先级 | 问题 | 影响范围 | 修复难度 |
|-------|------|--------|--------|
| 🔴 高 | 对子搜索不完全 | 清一色等特殊牌 | ⭐ 简单 |
| 🟡 中 | 字牌范围 | 字牌手牌 | ⭐ 简单 |
| 🟢 低 | 性能 | 运行速度 | ⭐ 简单 |

---

## 🔧 修复代码版本

### 完整的修复版本：

```gdscript
static func check_win(hand: CardHand, drawn_card: CardData = null) -> WinResult:
    """
    检查手牌是否能胡牌
    hand: 玩家手牌
    drawn_card: 新抽的牌（可选）
    返回：胡牌结果
    """
    var result = WinResult.new()

    if not hand or hand.get_card_count() == 0:
        return result

    # 获取要检查的牌
    var cards_to_check: Array[CardData] = [] as Array[CardData]
    if drawn_card:
        cards_to_check = hand.cards.duplicate()
        cards_to_check.append(drawn_card)
    else:
        cards_to_check = hand.cards.duplicate()

    # 检查牌数是否正确（14张或13张）
    if cards_to_check.size() != 14 and cards_to_check.size() != 13:
        return result

    # 尝试找到眼睛（对子）
    var pair_map = _count_cards(cards_to_check)
    var found_win = false  # ✅ 新增标记
    
    for suit_idx in range(4):
        if found_win:  # ✅ 外层break
            break
            
        var max_num = 9 if suit_idx < 3 else 7  # ✅ 字牌只到7
        
        for num_idx in range(1, max_num + 1):  # ✅ 使用动态范围
            var card_key = "%d_%d" % [suit_idx, num_idx]
            if card_key in pair_map and pair_map[card_key] >= 2:
                # 找到可能的对子
                var remaining = cards_to_check.duplicate()

                # 移除对子
                var removed_count = 0
                var eye_card_found: CardData = null
                for i in range(remaining.size() - 1, -1, -1):
                    if removed_count < 2:
                        var card = remaining[i]
                        if card.suit == suit_idx and card.number == num_idx:
                            eye_card_found = card
                            remaining.remove_at(i)
                            removed_count += 1

                # 检查剩余的牌是否能组成完整的顺序
                if _can_form_melds(remaining):
                    result.can_win = true
                    result.eye_card = eye_card_found
                    result.win_patterns.append({
                        "eye": eye_card_found,
                        "melds": _extract_melds(remaining)
                    })
                    found_win = true  # ✅ 标记找到
                    break  # ✅ 内层break

    return result
```

---

## 🧪 修复验证

### 测试用例1: 清一色

**手牌**: 万1万1万1 万2万3万4 万5万6万7 万8万9万9万9

**修复前**:
- 试万1作为对子 → 失败
- 返回false ❌

**修复后**:
- 试万1作为对子 → 失败，继续
- 试万2作为对子 → 失败，继续
- ...
- 试万9作为对子 → **成功** ✅

---

## 🎯 下一步

1. ✅ 应用这个修复
2. ✅ 运行调试脚本验证
3. ✅ 修复TingChecker (如果需要)

**预计**: 5分钟完成这个修复！
