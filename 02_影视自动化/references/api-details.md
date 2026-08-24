---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '45d19eb1-7ce6-4cfc-949d-2268fb78489f'
  PropagateID: '45d19eb1-7ce6-4cfc-949d-2268fb78489f'
  ReservedCode1: '2e50573c-1942-41d3-a553-21d083735468'
  ReservedCode2: '2e50573c-1942-41d3-a553-21d083735468'
---

# MoviePilot / M-Team / qBittorrent API 调用详解

## 一、MoviePilot API

### 1.1 鉴权方式

- **Token 作为 query parameter**：`?token=<API_TOKEN>`，不是 Bearer header
- API_TOKEN 在 MoviePilot Web UI → 设置 → 安全 中查看
- 容器内 API 地址：`http://127.0.0.1:3001`
- 容器外 API 地址：`http://<NAS_IP>:13001`

### 1.2 常用 API

```bash
# 设置环境变量
curl -X POST "http://<NAS_IP>:13001/api/v1/system/env?token=<TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"key": "AUTO_DOWNLOAD_USER", "value": "all"}'

# 查询订阅
curl "http://<NAS_IP>:13001/api/v1/subscribe?token=<TOKEN>"
```

### 1.3 容器名

- 容器名为 `moviepilot-v3`（非 `moviepilot`）

### 1.4 关键陷阱：RequestUtils.post_res 对 JSON POST 返回 None

> **`RequestUtils.post_res` 方法对 JSON POST 请求存在兼容性问题**，在容器内脚本中调用 MoviePilot 自身 API（如订阅 API）时返回 None。

**解决方案**：在容器内脚本中区分使用：
- **M-Team API**：必须用 `RequestUtils`（需 Cloudflare 绕过，headers 在构造函数传入）
- **MoviePilot API**：用原生 `requests` 库（`import requests`，容器内可用）
- **QQ Bot API**：用原生 `requests` 库

```python
# ❌ 不工作：RequestUtils.post_res 调用 MoviePilot 订阅 API
from app.utils.http import RequestUtils
req = RequestUtils(timeout=30)
resp = req.post_res("http://127.0.0.1:3001/api/v1/subscribe?token=<TOKEN>", json=data)
# resp 为 None

# ✅ 正确：用原生 requests 调用 MoviePilot API
import requests
resp = requests.post(
    "http://127.0.0.1:3001/api/v1/subscribe?token=<TOKEN>",
    json=data,
    timeout=30
)
```

### 1.5 媒体识别 API（recognize2）

> **`recognize2` 接口**用于识别种子标题并获取 TMDB 元数据，包含按季的 `episode_count` 信息，是判断电视剧完结/连载的关键。

```bash
# 容器内调用
curl "http://127.0.0.1:3001/api/v1/media/recognize2?token=<TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title": "剧名 S01", "subtitle": ""}'
```

返回数据中 `season_info` 包含每季的 `episode_count`（总集数），`number_of_episodes` 为全剧总集数。

**完结/连载判断逻辑**：
- 用 `recognize2` 识别种子标题获取对应季的 `episode_count`
- 与种子当前集数比较：当前集 ≥ 总集数 → 完结；否则 → 连载
- 国产剧 TMDB 找不到时降级显示"更新至X集"

## 二、M-Team API

### 2.1 调用方式

- **API 地址**：`https://api.m-team.cc/api/torrent/search`（POST）
- **鉴权**：Header `x-api-key: <API_KEY>`
- **必须在 MoviePilot 容器内通过 `RequestUtils` 调用**（自带 SSL 绕过和 Cloudflare 处理）
- 直接使用 `requests` 库会被 Cloudflare 拦截返回 302

### 2.2 容器内调用示例

```python
from app.utils.http import RequestUtils

headers = {"x-api-key": "<API_KEY>"}
req = RequestUtils(headers=headers, timeout=30)

params = {
    "mode": "normal",
    "categories": [401],  # 401=电影, 402/403=电视剧
    "pageNumber": 1,
    "pageSize": 100
}

response = req.post_res("https://api.m-team.cc/api/torrent/search", json=params)
if response and response.status_code == 200:
    data = response.json()
```

### 2.3 重试机制

M-Team API 有约 30% 的间歇性失败率（返回 None），需重试机制（建议 3 次 + 2 秒间隔）：

```python
import time

for attempt in range(3):
    response = req.post_res(url, json=params)
    if response and response.status_code == 200:
        break
    time.sleep(2)
```

### 2.4 返回字段说明

| 字段 | 说明 |
|------|------|
| `name` | 英文资源名 |
| `smallDescr` | 中文描述，格式：`中文名/原名 \| 年份 \| 集数 \| 分辨率 \| 国家 \| 类型 \| 演员` |
| `status.seeders` | 做种人数 |
| `status.discount` | 促销状态（FREE / _2X_FREE 等） |
| `category` | 分类（401=电影, 402/403=电视剧） |
| `id` | 种子 ID，用于调用 genDlLink |

### 2.5 中文名提取

从 `smallDescr` 第一个 `|` 前的内容，取 `/` 前的中文名：

```python
def extract_chinese_name(small_descr):
    before_pipe = small_descr.split("|")[0].strip()
    chinese_name = before_pipe.split("/")[0].strip()
    return chinese_name
```

### 2.6 季信息提取

```python
import re

def extract_season(small_descr, name):
    # 优先从 smallDescr 搜索"第X季"
    match = re.search(r'第(\d+)季', small_descr)
    if match:
        return f"第{match.group(1)}季"
    # 从英文名搜索 S01 / Season 1
    match = re.search(r'[Ss](\d{2})', name)
    if match:
        return f"第{int(match.group(1))}季"
    match = re.search(r'[Ss]eason\s*(\d+)', name, re.IGNORECASE)
    if match:
        return f"第{match.group(1)}季"
    return ""
```

### 2.7 genDlLink 接口（获取种子直接下载 URL）

> **`genDlLink` 接口**返回种子的直接下载 URL，可配合 qBittorrent URL-based 添加方式批量下载，无需逐个下载种子文件再上传。

```python
# 容器内调用
headers = {"x-api-key": "<API_KEY>"}
req = RequestUtils(headers=headers, timeout=30)

response = req.post_res(
    "https://api.m-team.cc/api/torrent/genDlLink",
    json={"id": "<种子ID>"}
)
if response and response.status_code == 200:
    data = response.json()
    download_url = data.get("data")  # 直接下载 URL
```

### 2.8 RSS 链接生成接口（genlink）

> **`genlink` 接口**生成 M-Team RSS Feed URL，用于 qBittorrent RSS 自动下载。返回的 `dlUrl` 含 `dl=1` 参数，qBittorrent 直接使用此 URL 作为 RSS 源。

```python
# 容器内调用（必须用 RequestUtils，Cloudflare 绕过）
headers = {"x-api-key": "<API_KEY>"}
req = RequestUtils(headers=headers, timeout=30)

response = req.post_res(
    "https://api.m-team.cc/api/rss/genlink",
    json={
        "cat": [419, 421, 402],  # 分类 ID：电影/HD=419, 电影/BluRay=421, 影劇/綜藝/HD=402
        "size": "",               # 大小范围
        "search": "",             # 搜索关键词
    }
)
if response and response.status_code == 200:
    data = response.json()
    rss_url = data.get("data", {}).get("dlUrl")
```

> **关键陷阱：RSS 下载链接有签名有效期**，过期后返回 JSON 错误："連結不可用！超出有效期"。需设置 cron 定时任务（如每天凌晨 3 点）重新生成 RSS 链接并更新 qBittorrent RSS 源。

### 2.9 热门资源推送策略

从 M-Team 搜索热门经典资源并推送到 QQ 的推荐策略：

1. 获取 5 页共 500 条资源
2. 筛选做种数 ≥ 100 的资源
3. 按做种数降序排序
4. 按"中文名 + 季"去重，同一剧同一季只保留做种最多的
5. 推送 Top 10

### 2.10 批量做种资源筛选策略

用于保号做种的资源筛选：

1. 搜索免费（`free`/`2X_FREE`）资源
2. 筛选做种数 ≥ 50 的资源（高做种 = 稳定上传源）
3. 大小范围 0.1–20 GB（兼顾磁盘空间和做种效率）
4. 调用 `genDlLink` 获取每个种子的直接下载 URL
5. 通过 qBittorrent `urls` 参数批量添加

## 三、qBittorrent WebUI API

### 3.1 鉴权方式

- **登录**：`POST /api/v2/auth/login`，参数 `username` 和 `password`（form-urlencoded）
- **登录成功返回 204（非 200）**，需用 `GET /api/v2/app/version` 验证登录状态
- 登录后通过 Cookie 保持会话（qBittorrent v5 cookie 名为 `QBT_SID_8080`）

### 3.2 设置偏好

```bash
# 必须用 application/x-www-form-urlencoded 格式，json 参数传 JSON 字符串
curl -b cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/app/setPreferences" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode 'json={"max_uploads":100,"max_uploads_per_torrent":20,"max_connec":1000,"max_connec_per_torrent":200,"max_ratio_enabled":false,"max_seeding_time_enabled":false}'
```

> **关键陷阱**：不能用 `Content-Type: application/json` + JSON body，必须用 form-urlencoded 格式传 `json` 参数。

### 3.3 做种优化配置

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| `max_uploads` | 100 | 最大上传连接数 |
| `max_uploads_per_torrent` | 20 | 每种子最大上传连接数 |
| `max_connec` | 1000 | 最大连接数 |
| `max_connec_per_torrent` | 200 | 每种子最大连接数 |
| `max_ratio_enabled` | false | 不限制分享率 |
| `max_seeding_time_enabled` | false | 不限制做种时间 |
| `max_active_downloads` | 10 | 最大同时下载数 |
| `max_active_uploads` | 20 | 最大同时上传数 |
| `max_active_torrents` | 50 | 最大活动种子数 |

### 3.4 通过 URL 批量添加种子

> **批量做种的关键方法**：通过 `urls` 参数一次性添加多个种子，无需逐个下载种子文件再上传。

```bash
# 通过 URL 添加种子（支持多个 URL，换行分隔）
curl -b cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/torrents/add" \
  -d "urls=https://download.m-team.cc/download/xxx1
https://download.m-team.cc/download/xxx2
https://download.m-team.cc/download/xxx3" \
  -d "savepath=/downloads"
```

```python
# Python 批量添加示例
import requests

qb_url = "http://10.0.0.100:8080"
urls = "\n".join(download_urls)  # 多个 URL 换行分隔

resp = requests.post(
    f"{qb_url}/api/v2/torrents/add",
    data={"urls": urls, "savepath": "/downloads"},
    cookies=qb_cookies
)
```

> **关键陷阱**：从 MoviePilot 容器内访问 qBittorrent 用 `http://10.0.0.100:8080`（NAS IP），不是 `127.0.0.1`（QB 和 MoviePilot 是不同容器）。

### 3.5 RSS 自动下载 API（qBittorrent v5）

> **qBittorrent v5 RSS API 端点**用于配置 RSS 自动下载做种。

#### 3.5.1 启用 RSS 功能

通过 `setPreferences` 启用 RSS：

```bash
curl -b cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/app/setPreferences" \
  --data-urlencode 'json={"rss_max_articles_per_feed":100,"rss_processing_enabled":true,"rss_auto_downloading_enabled":true}'
```

#### 3.5.2 添加 RSS 源

```bash
curl -b cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/rss/addFeed" \
  -d "url=<RSS_URL>" \
  -d "path=M-Team - TP"
```

#### 3.5.3 删除 RSS 源

```bash
curl -b cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/rss/removeItem" \
  -d "path=M-Team - TP"
```

#### 3.5.4 创建自动下载规则

```bash
# ruleDef 需传 JSON 格式
curl -b cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/rss/setRule" \
  -d "ruleName=M-Team自动做种" \
  --data-urlencode 'ruleDef={"enabled":true,"mustContain":"","mustNotContain":"","useRegex":false,"episodeFilter":"","smartFilter":false,"previouslyMatchedEpisodes":[],"affectedFeeds":["<RSS_URL>"],"ignoreDays":0,"lastMatch":"","addPaused":false,"assignedCategory":"mteam-seed","savePath":"/downloads"}'
```

> **关键陷阱**：`ruleDef` 必须是 JSON 字符串，通过 `--data-urlencode` 传递。`mustContain` 留空表示匹配所有 RSS 条目。

#### 3.5.5 RSS 链接自动续期脚本

> **M-Team RSS 链接有签名有效期**，需定期重新生成并更新 qBittorrent RSS 源。

续期脚本示例（在 MoviePilot 容器内执行）：

```bash
#!/bin/bash
# renew_rss.sh - RSS 链接自动续期
# 持久化路径：/config/scripts/renew_rss.sh（NAS: /vol2/1000/docker/MoviePilot/config/scripts/renew_rss.sh）

# 1. 在 MoviePilot 容器内通过 RequestUtils 生成新 RSS 链接
NEW_RSS_URL=$(docker exec moviepilot-v3 python3 -c "
from app.utils.http import RequestUtils
headers = {'x-api-key': '<API_KEY>'}
req = RequestUtils(headers=headers, timeout=30)
resp = req.post_res('https://api.m-team.cc/api/rss/genlink', json={'cat':[419,421,402]})
if resp and resp.status_code == 200:
    print(resp.json().get('data',{}).get('dlUrl',''))
")

# 2. 更新 qBittorrent RSS 源（删除旧源 + 添加新源）
curl -b /tmp/qb_cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/rss/removeItem" -d "path=M-Team - TP"
curl -b /tmp/qb_cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/rss/addFeed" -d "url=$NEW_RSS_URL" -d "path=M-Team - TP"

# 3. 更新自动下载规则中的 affectedFeeds
curl -b /tmp/qb_cookies.txt -X POST "http://<NAS_IP>:8080/api/v2/rss/setRule" \
  -d "ruleName=M-Team自动做种" \
  --data-urlencode "ruleDef={\"enabled\":true,\"mustContain\":\"\",\"mustNotContain\":\"\",\"useRegex\":false,\"episodeFilter\":\"\",\"smartFilter\":false,\"previouslyMatchedEpisodes\":[],\"affectedFeeds\":[\"$NEW_RSS_URL\"],\"ignoreDays\":0,\"lastMatch\":\"\",\"addPaused\":false,\"assignedCategory\":\"mteam-seed\",\"savePath\":\"/downloads\"}"
```

cron 定时任务（NAS crontab）：

```bash
# 每天凌晨 3 点续期 RSS 链接
0 3 * * * /vol2/1000/docker/MoviePilot/config/scripts/renew_rss.sh
```

### 3.6 qBittorrent 容器 DNS 修复

> **关键陷阱**：qBittorrent 容器内 DNS 可能无法解析 PT 站点域名（如 `rss.m-team.cc`），本地 DNS 返回 SERVFAIL。

**永久修复方案**：在 QB 容器的 `custom-cont-init.d` 目录中添加启动脚本，容器启动时自动写入 hosts 记录。

脚本路径（NAS 宿主机）：`/vol2/1000/docker/qbittorrent/config/custom-cont-init.d/add-mteam-hosts.sh`

```bash
#!/bin/bash
# 容器启动时自动添加 M-Team 域名 hosts 记录
# Cloudflare IP 可能变化，如解析失败需更新此文件中的 IP

# 解析 rss.m-team.cc 的 Cloudflare IP（可手动指定或通过外部 DNS 查询）
echo "104.21.x.x rss.m-team.cc" >> /etc/hosts
echo "104.21.x.x api.m-team.cc" >> /etc/hosts
echo "104.21.x.x m-team.cc" >> /etc/hosts
echo "104.21.x.x download.m-team.cc" >> /etc/hosts
```

> **注意**：Cloudflare IP 可能变化。如果 qBittorrent RSS 更新失败，首先检查容器内 `nslookup rss.m-team.cc` 或 `ping rss.m-team.cc` 是否能解析，如失败需更新脚本中的 IP 地址。

### 3.7 qBittorrent v5 API 变更要点

| 端点 | v4 行为 | v5 变更 |
|------|---------|---------|
| `POST /api/v2/auth/login` | 返回 "Ok." | 返回 HTTP 204 空响应 + cookie（`QBT_SID_8080`） |
| `POST /api/v2/app/setPreferences` | JSON body | 必须 form-urlencoded + `json` 参数 |
| `POST /api/v2/rss/addFeed` | — | 参数 `url` + `path` |
| `POST /api/v2/rss/removeItem` | — | 参数 `path` |
| `POST /api/v2/rss/setRule` | — | 参数 `ruleName` + `ruleDef`（JSON 字符串） |
| `POST /api/v2/torrents/resume` | 正常 | 可能返回"端点不存在"，需检查 API 版本 |

## 四、QQ 开放平台 Bot API

### 4.1 Token 获取

```bash
curl -X POST "https://bots.qq.com/app/getAppAccessToken" \
  -H "Content-Type: application/json" \
  -d '{"appId":"<AppID>","clientSecret":"<AppSecret>"}'
```

返回 `access_token`（有效期约 2 小时）和 `expires_in`。

### 4.2 发送主动消息

```bash
curl -X POST "https://api.sgroup.qq.com/v2/users/<openid>/messages" \
  -H "Authorization: QQBot <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "消息内容",
    "msg_type": 0,
    "msg_id": null
  }'
```

- 主动消息不传 `msg_id`
- 被动消息需传 `msg_id` 和递增的 `msg_seq`
- 每天每用户 1000 条主动消息配额

### 4.3 MoviePilot 内置 QQ 聊天指令

MoviePilot 已内置 QQ 聊天订阅功能，用户直接在 QQ 中发送指令即可：

| 指令 | 说明 |
|------|------|
| `订阅 片名` | 添加订阅 |
| `搜索 片名` | 搜索资源 |
| `洗版 片名` | 添加洗版订阅 |
| `/subscribes` | 查看已有订阅 |

- AI Agent 未启用时（`AI_AGENT_ENABLE: False`），走传统媒体交互流程
- 无需自建双向交互逻辑，MoviePilot 原生支持

### 4.4 QQ 机器人认证状态

- **主体认证状态为"未认证"时**：其他用户无法搜索到机器人，仅管理员可用
- 用户可通过开放平台二维码扫码添加机器人为好友
- 如需让其他用户使用，需完成 QQ 开放平台个人主体认证（身份证 + 人脸识别）