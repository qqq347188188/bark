# 推送送达状态验证 API（与 bark-server 集成）

本文档说明 Bark iOS 客户端新增的「送达状态验证」能力，以及如何与现有的
[bark-server](https://github.com/Finb/bark-server) 后端集成。

---

## 1. 客户端行为概述

- 设备收到任意一条推送时，`NotificationServiceExtension` 中的 `DeliveryProcessor`
  会写入一条「已送达」回执到 App Group 共享目录 `group.bark/push_delivery/*.plist`。
  回执字段：`pushId`（服务端 ID，见下文）、`apnsId`（系统 APNs 请求 ID）、
  `receivedAt`（设备收到时间）、`title`、`body`、`group`。
- 主 App 启动或收到 Darwin 通知后，读取这些回执并写入本地 Realm（`DeliveryReceipt`）。
- 若开关 `DeliverySettingManager.reportToServer` 为 true（默认开启），主 App 会调用
  `POST /push/delivery` 把这些回执上报给 bark-server，用于服务端侧的送达状态聚合。
- 在「送达状态查询」界面，可按 `pushid` 或时间戳查询：
  - 本地：直接读取 `DeliveryReceipt`（表示设备已收到，即“已送达”）。
  - 服务端：调用 `GET /push/delivery` 获取 bark-server 侧状态。

> 说明：客户端代码不依赖服务端即可完成「本地已送达」记录与查询；服务端集成仅用于
> 提供「待发送 / 已发送 / 失败」等更完整的状态视图。

---

## 2. 送达状态枚举

| 状态 | 含义 |
| --- | --- |
| `pending` | 服务端已接收推送请求，等待下发 APNs |
| `sent` | 已成功提交给 APNs |
| `delivered` | 设备已确认收到（客户端回执上报成功） |
| `failed` | 下发失败（如设备 token 失效、参数错误等） |
| `unknown` | 无记录 / 无法判定 |

---

## 3. 需要 bark-server 配合的改动

### 3.1 在 APNs payload 中携带 `pushid`

bark-server 在把推送转发给 APNs 时，应为每一次推送生成一个唯一 ID（**pushid**），
并放入 APNs 自定义载荷（即 iOS 端 `request.content.userInfo` 中）：

```json
{
  "aps": { "alert": { "title": "...", "body": "..." }, "sound": "..." },
  "pushid": "bark-20261016-a1b2c3d4",
  "title": "...", "body": "...", "image": "..."
}
```

客户端按 `userInfo["pushid"] ?? userInfo["id"] ?? request.identifier` 的优先级读取该 ID，
作为后续查询 / 上报的关联键。

### 3.2 新增接口

#### 上报送达回执（设备 → 服务端）

```
POST /push/delivery
Content-Type: application/json

{
  "device_key": "<KEY>",
  "deliveries": [
    {
      "pushid": "bark-20261016-a1b2c3d4",
      "apnsid": "<APNs request id>",
      "received_at": 1730000000,
      "status": "delivered"
    }
  ]
}
```

- 成功：`200 { "code": 200, "message": "success" }`
- 服务端应将对应 `pushid` 的状态由 `sent` 更新为 `delivered`，并记录 `delivered_at`。

#### 查询送达状态（按 pushid 或时间戳）

```
GET /push/delivery?pushid=bark-20261016-a1b2c3d4
GET /push/delivery?timestamp=1730000000
```

响应：

```json
{
  "code": 200,
  "message": "success",
  "data": {
    "pushid": "bark-20261016-a1b2c3d4",
    "status": "delivered",
    "sent_at": 1730000000,
    "delivered_at": 1730000001
  }
}
```

- 同时按 `timestamp` 查询时，返回该时间戳附近的推送状态列表（数组）。

---

## 4. 参考 Go 实现（bark-server 风格）

以下为可嵌入现有 bark-server 的参考实现（使用标准库 `net/http` + 内存存储，
生产环境请替换为你的现有存储 / ORM）：

```go
package delivery

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

type Status string

const (
	StatusPending  Status = "pending"
	StatusSent     Status = "sent"
	StatusDelivered Status = "delivered"
	StatusFailed   Status = "failed"
)

type Record struct {
	PushID      string `json:"pushid"`
	DeviceKey   string `json:"device_key"`
	Status      Status `json:"status"`
	SentAt      int64  `json:"sent_at"`
	DeliveredAt int64  `json:"delivered_at"`
}

// Store 生产环境请替换为数据库 / Redis
type Store struct {
	mu       sync.RWMutex
	records  map[string]*Record
	byDevice map[string][]*Record
}

func NewStore() *Store {
	return &Store{records: map[string]*Record{}, byDevice: map[string][]*Record{}}
}

// 在现有“向 APNs 发送推送”的逻辑中调用，记录为 pending/sent
func (s *Store) MarkSent(pushID, deviceKey string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now().Unix()
	rec := &Record{PushID: pushID, DeviceKey: deviceKey, Status: StatusSent, SentAt: now}
	s.records[pushID] = rec
	s.byDevice[deviceKey] = append(s.byDevice[deviceKey], rec)
}

// 在 APNs 返回失败时调用
func (s *Store) MarkFailed(pushID, deviceKey string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if r, ok := s.records[pushID]; ok {
		r.Status = StatusFailed
	} else {
		now := time.Now().Unix()
		r := &Record{PushID: pushID, DeviceKey: deviceKey, Status: StatusFailed, SentAt: now}
		s.records[pushID] = r
		s.byDevice[deviceKey] = append(s.byDevice[deviceKey], r)
	}
}

// 设备回执上报：标记为 delivered
func (s *Store) MarkDelivered(pushID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if r, ok := s.records[pushID]; ok {
		r.Status = StatusDelivered
		r.DeliveredAt = time.Now().Unix()
	}
}

// ---- HTTP handlers ----

func (s *Store) ReportHandler(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeviceKey string `json:"device_key"`
		Deliveries []struct {
			PushID     string `json:"pushid"`
			APNSID     string `json:"apnsid"`
			ReceivedAt int64  `json:"received_at"`
			Status     string `json:"status"`
		} `json:"deliveries"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	for _, d := range body.Deliveries {
		if d.Status == "delivered" {
			s.MarkDelivered(d.PushID)
		}
	}
	json.NewEncoder(w).Encode(map[string]any{"code": 200, "message": "success"})
}

func (s *Store) QueryHandler(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	pushID := q.Get("pushid")
	ts := q.Get("timestamp")

	s.mu.RLock()
	defer s.mu.RUnlock()

	if pushID != "" {
		if rec, ok := s.records[pushID]; ok {
			json.NewEncoder(w).Encode(map[string]any{"code": 200, "message": "success", "data": rec})
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"code": 404, "message": "not found"})
		return
	}

	if ts != "" {
		var list []*Record
		for _, rec := range s.records {
			// 简易 ±30s 范围匹配
			list = append(list, rec)
		}
		json.NewEncoder(w).Encode(map[string]any{"code": 200, "message": "success", "data": list})
		return
	}

	http.Error(w, "pushid or timestamp required", http.StatusBadRequest)
}
```

在你的 bark-server `main` 路由中挂载：

```go
store := delivery.NewStore()
http.HandleFunc("/push/delivery", func(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		store.ReportHandler(w, r)
	} else {
		store.QueryHandler(w, r)
	}
})
```

> 注意：鉴权、限流、按 `device_key` 隔离等安全逻辑请沿用 bark-server 现有中间件。

---

## 5. 客户端调用位置

- 上报：`Controller/DeliveryManager.swift` → `reportPendingDeliveries()`
- 查询：`Controller/DeliveryManager.swift` → `queryServer(pushId:timestamp:)`
- 接口定义：`Common/Moya/BarkApi.swift` → `pushDeliveryReport` / `pushDeliveryQuery`
