# 🌍 国外全免费服务器 - 永久免费方案

**问题**: 想要找到全免费的国外服务器  
**解决**: 提供 5 个永久免费的云平台对比  
**成本**: ¥0 (永久免费，无信用卡也可用)  

---

## 📋 目录

1. [快速对比](#快速对比)
2. [推荐方案](#推荐方案)
3. [Oracle Cloud (推荐)](#oracle-cloud-推荐)
4. [AWS 免费层](#aws-免费层)
5. [Google Cloud](#google-cloud)
6. [Heroku](#heroku)
7. [常见问题](#常见问题)

---

## 📊 快速对比表

| 平台 | 免费配置 | 免费时长 | 优点 | 缺点 | 推荐度 |
|------|----------|---------|------|------|--------|
| **Oracle Cloud** | 2 核 1GB 内存 50GB 存储 | ✅ 永久免费 | 完全免费，性能稳定 | 需要信用卡验证 | ⭐⭐⭐⭐⭐ |
| **AWS** | 1 核 1GB 内存 | ⏱️ 12 个月 | 全球最大，功能最多 | 12 个月后付费 | ⭐⭐⭐⭐ |
| **Google Cloud** | 1 核 0.6GB 内存 | ✅ 永久免费 | 谷歌品质，速度快 | 配置较低 | ⭐⭐⭐⭐ |
| **Azure** | 1 核 1GB 内存 | ⏱️ 12 个月 | 功能全面，集成好 | 12 个月后付费 | ⭐⭐⭐ |
| **Heroku** | 512MB 内存 | ⏱️ 24/7 免费（已停用） | ~~简单易用~~ | ❌ 已不提供免费 | ❌ 不推荐 |

---

## 🎯 推荐方案

### 方案 1: **Oracle Cloud 单独部署** (最推荐!)

```
✅ 完全免费，永久有效
✅ 2 核 CPU + 1GB 内存 (足够!)
✅ 50GB 存储空间
✅ 月 10GB 出网流量

不足:
⚠️ 需要信用卡认证 (不会扣费)
⚠️ 国外服务器，延迟较高 (但可接受)
⚠️ 注册流程稍复杂

预计时间: 30 分钟

👍 推荐指数: ⭐⭐⭐⭐⭐
```

### 方案 2: **AWS 免费层** (次推荐)

```
✅ 全球最知名的云平台
✅ 1 核 CPU + 1GB 内存
✅ 12 个月完全免费

不足:
⚠️ 12 个月后需要付费
⚠️ 流量有限制
⚠️ 注册较严格

预计时间: 20 分钟

👍 推荐指数: ⭐⭐⭐⭐
```

### 方案 3: **Google Cloud 永久免费**

```
✅ 永久免费
✅ 谷歌基础设施
✅ 可靠性高

不足:
⚠️ 配置较低 (0.6GB 内存)
⚠️ 1 个 f1-micro 实例

预计时间: 25 分钟

👍 推荐指数: ⭐⭐⭐⭐
```

---

## 🚀 Oracle Cloud (推荐!)

### 为什么推荐 Oracle?

```
1. 完全永久免费
2. 配置最高 (2 核 1GB)
3. 官方承诺不收费
4. 中国访问速度可以
5. 部署脚本完全兼容
```

### 注册链接

```
https://www.oracle.com/cloud/free/
```

### 快速注册步骤

#### Step 1: 访问官网

打开: https://www.oracle.com/cloud/free/

点击: "Start for free" 或 "立即开始"

#### Step 2: 选择地区

建议选择:
```
新加坡 (Singapore) - 离中国最近
或
韩国 (Korea) - 也不错
或
日本 (Tokyo) - 也可以
```

**不要选**:
```
❌ 美国西部 (延迟太高)
❌ 欧洲 (距离远)
```

#### Step 3: 创建账户

```
1. 输入邮箱
2. 设置密码
3. 输入手机号 (用于 OTP)
4. 选择国家 (选中国)
5. 点击创建账户
```

#### Step 4: 验证信息

```
1. 验证邮箱 (点击链接)
2. 验证手机号 (输入验证码)
3. 填写个人信息
4. 选择国家和公司名称
```

#### Step 5: 添加支付信息

```
⚠️ 重要: 虽然是免费的，但需要添加信用卡

但不用担心，Oracle 保证:
✅ 不会自动收费
✅ 免费配额用完也不会扣钱
✅ 只是用于身份验证

信用卡需要:
- Visa
- MasterCard
- American Express

注意: 如果您不舒服添加卡，可以用 AWS 或 Google Cloud
```

#### Step 6: 选择免费资源

```
系统会默认选择:
✅ 1x Compute VM (2 OCPU, 1 GB RAM)
✅ 1x MySQL Database
✅ 1x Block Storage (50GB)
✅ 100 GB 出网流量/月

保持默认即可！
```

#### Step 7: 创建 Compute Instance

```
1. 登录 Oracle Cloud 控制台
2. 进入 Compute → Instances
3. 点击 Create Instance
4. 配置:
   - Name: mahjong-game
   - Image: Ubuntu 22.04
   - Shape: Always Free Eligible (很重要!)
   - vCPU: 2
   - RAM: 1GB
   - Storage: 50GB
5. 点击 Create
```

#### Step 8: 获取公网 IP

```
实例创建后 (2-3 分钟):
1. 找到您的实例
2. 记下 Public IP Address
3. 记下 Default Username (opc 或 ubuntu)
```

---

## 🔐 AWS 免费层

### 注册链接

```
https://aws.amazon.com/cn/free/
或
https://aws.amazon.com/free/
```

### 快速注册步骤

#### Step 1: 访问官网

打开: https://aws.amazon.com/free/

点击: "创建免费账户"

#### Step 2: 创建账户

```
1. 输入邮箱地址
2. 输入账户名
3. 设置强密码
4. 点击继续
```

#### Step 3: 联系方式

```
1. 输入邮箱地址
2. 电话号码 (用于验证)
3. 地址 (选择中国)
```

#### Step 4: 支付方式

```
需要信用卡 (Visa/MasterCard)

AWS 免费层保证:
✅ 12 个月内不收费
✅ 超过免费额度会提示
✅ 在您同意前不会扣费
```

#### Step 5: 启动 EC2 实例

```
1. 登录 AWS 控制台
2. 进入 EC2
3. 点击 Launch Instance
4. 选择 Ubuntu 20.04 LTS (Free Tier Eligible)
5. 选择 t2.micro (1 核 1GB)
6. 配置安全组 (允许 SSH 和 HTTP/HTTPS)
7. 启动
```

---

## 🔵 Google Cloud 永久免费

### 注册链接

```
https://cloud.google.com/free
```

### 快速注册步骤

#### Step 1: 访问官网

打开: https://cloud.google.com/free

点击: "开始使用"

#### Step 2: 创建账户

```
用 Google 账户登录
或创建新的 Google 账户
```

#### Step 3: 创建项目

```
1. 项目名称: mahjong-game
2. 计费账户: Free Tier
3. 点击创建
```

#### Step 4: 启动 Compute Engine

```
1. 进入 Compute Engine
2. 点击 Create Instance
3. 配置:
   - Name: mahjong-game
   - Region: asia-east1 (台湾) 或 asia-northeast1 (日本)
   - Machine type: e2-micro (0.25-1 vCPU, 0.6GB)
   - Boot disk: Ubuntu 20.04 LTS
4. 启动
```

---

## 📝 部署步骤 (所有平台通用)

### Step 1: SSH 连接

**Oracle Cloud:**
```bash
ssh ubuntu@公网IP
或
ssh opc@公网IP
```

**AWS:**
```bash
ssh -i 密钥文件.pem ubuntu@公网IP
```

**Google Cloud:**
```bash
gcloud compute ssh 实例名
或
ssh 用户名@公网IP
```

### Step 2: 下载部署脚本

```bash
wget https://raw.githubusercontent.com/yourusername/mahjong-game/v1.0.0/CLOUD_DEPLOYMENT_AUTO.sh

或

curl -O https://raw.githubusercontent.com/yourusername/mahjong-game/v1.0.0/CLOUD_DEPLOYMENT_AUTO.sh
```

### Step 3: 运行脚本

```bash
chmod +x CLOUD_DEPLOYMENT_AUTO.sh
./CLOUD_DEPLOYMENT_AUTO.sh
```

### Step 4: 验证部署

```bash
curl http://localhost:8080/api/health
```

### Step 5: 从浏览器访问

```
http://公网IP:8080/api/health
```

---

## 🛡️ 配置防火墙规则

### Oracle Cloud

```
1. 进入 Networking → Virtual Cloud Networks
2. 选择您的 VCN
3. 找到 Security List
4. 添加入站规则:
   - Port: 8080 (TCP)
   - Source: 0.0.0.0/0
5. 保存
```

### AWS

```
1. 进入 EC2 → Security Groups
2. 编辑入站规则
3. 添加规则:
   - Type: Custom TCP
   - Port: 8080
   - Source: 0.0.0.0/0
4. 保存
```

### Google Cloud

```
1. 进入 VPC network → Firewall
2. 创建防火墙规则
3. 配置:
   - Name: allow-mahjong
   - Direction: Ingress
   - Targets: 所有实例
   - Source IP: 0.0.0.0/0
   - Protocol: TCP
   - Ports: 8080
4. 创建
```

---

## ❓ 常见问题

### Q1: 哪个平台最好?

**答:**

对于麻将游戏:

```
第 1 选: Oracle Cloud
  ✅ 永久免费
  ✅ 配置最好 (2核1GB)
  ✅ 性能稳定
  ⚠️ 需要信用卡

第 2 选: AWS
  ✅ 知名度最高
  ✅ 功能最全
  ⚠️ 12 个月后付费

第 3 选: Google Cloud
  ✅ 永久免费
  ⚠️ 配置较低 (0.6GB)
```

推荐: **Oracle Cloud**
```

### Q2: 需要信用卡吗?

**答:**

```
Oracle Cloud: ✅ 需要 (但不会扣费)
AWS: ✅ 需要 (但 12 个月内免费)
Google Cloud: ✅ 需要 (但永久免费)

所有平台都需要信用卡用于身份验证
但官方承诺不会未经同意收费
```

### Q3: 可以用预付卡或虚拟卡吗?

**答:**

```
Oracle Cloud: ✅ 可以 (大部分虚拟卡支持)
AWS: ✅ 可以
Google Cloud: ✅ 可以

建议用:
- Stripe 虚拟卡
- Wise 卡
- 2Checkout 虚拟卡
```

### Q4: 延迟会不会很高?

**答:**

```
从中国访问:

Oracle Singapore: 50-80ms (可以)
AWS 新加坡: 40-70ms (很好)
Google Cloud 台湾: 30-50ms (最好!)

对于游戏来说都可以接受
```

### Q5: 数据安全吗?

**答:**

```
非常安全！

所有平台都提供:
✅ SSL/TLS 加密
✅ DDoS 防护
✅ 防火墙
✅ 定期备份

完全可以放心
```

### Q6: 如果配置不够可以升级吗?

**答:**

```
Oracle Cloud: 不行，免费配额固定
AWS: 可以升级，但会产生费用
Google Cloud: 不行，免费配额固定

如果不够用，可以:
1. 优化麻将游戏代码
2. 升级为付费套餐
3. 转到其他平台
```

---

## 📋 快速选择指南

### 如果您...

**想要永久免费:**
→ **Oracle Cloud** 或 **Google Cloud**

**想要最知名的平台:**
→ **AWS**

**想要最快的国内速度:**
→ **Google Cloud (台湾)**

**想要最高的配置:**
→ **Oracle Cloud (2核1GB)**

**完全新手:**
→ **AWS** (教程最多)

---

## 🎯 我的建议

### 最佳方案

```
第 1 步: 选择 Oracle Cloud
  原因: 永久免费 + 最高配置

第 2 步: 如果配置不够
  转到: AWS (付费升级)

第 3 步: 国内小程序需要
  配置: 购买国内域名 + HTTPS
  成本: ~¥50/年 (域名) + 可选 CDN
```

---

## 🚀 立即开始

### 最快的方式 (15 分钟):

```
1. 选择一个平台 (推荐 Oracle Cloud)
2. 打开官网链接
3. 注册账户
4. 创建实例 (选择 Ubuntu 20.04)
5. 获取公网 IP
6. SSH 连接
7. 运行部署脚本
8. 完成！
```

### 三个选项的注册链接

```
【选项 1】Oracle Cloud (推荐!)
https://www.oracle.com/cloud/free/

【选项 2】AWS
https://aws.amazon.com/free/

【选项 3】Google Cloud
https://cloud.google.com/free
```

---

## 📞 选择后的下一步

一旦您选择了平台并创建了实例，告诉我：

```
"我选择了 [Oracle/AWS/Google Cloud]，
实例的公网 IP 是: xxx.xxx.xxx.xxx"
```

然后我会给您：
1. 具体的 SSH 连接命令
2. 适配的部署脚本
3. 完整的配置步骤
4. 验证部署的方法

---

## ✨ 总结

```
✅ Oracle Cloud: 永久免费 + 高配置
✅ AWS: 12 个月免费 + 最知名
✅ Google Cloud: 永久免费 + 良好性能

都完全免费，选择您喜欢的即可！

预计总时间: 30 分钟内完成部署
```

---

**现在就选择一个平台，开始注册吧！🚀**

**推荐**: Oracle Cloud

**链接**: https://www.oracle.com/cloud/free/
