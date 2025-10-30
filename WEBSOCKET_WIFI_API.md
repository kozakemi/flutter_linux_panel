# WebSocket Wi‑Fi 控制 API（前后端分离：前端 Flutter，后端 C）

版本：1.0.0  ·  传输：WebSocket(JSON)

后端建议监听：`ws://<host>:<port>/wifi`（端口示例：`9901`）。

## 设计原则

- 统一消息结构：所有请求/响应/事件均以相同的 JSON 外层结构进行封装。
- 类型约定：`type` 为蛇形命名，区分 `*_request`、`*_response`、`*_event`。
- 关联标识：使用 `request_id` 关联请求与响应（可选但推荐）。
- 可扩展：`data` 字段仅承载业务数据；新增字段不破坏旧客户端。

## 通用消息结构

请求（Request）：

```json
{
  "type": "<operation>_request",
  "request_id": "<string-or-int-optional>",
  "data": { /* operation payload */ }
}
```

响应（Response）：

```json
{
  "type": "<operation>_response",
  "request_id": "<echo-request-id>",
  "success": true,
  "error": 0,
  "message": "optional human-readable message",
  "data": { /* result payload */ }
}
```

事件（Event，后端主动推送）：

```json
{
  "type": "<domain>_event",
  "data": { /* event payload */ }
}
```

说明：
- `success` 为布尔；成功时 `error` 应为 `0`；失败时为非零（见错误码枚举）。
- `message` 可选，用于人类可读错误或状态描述。
- `request_id` 推荐在请求与响应中传递，便于前端路由。

## 操作列表与数据结构

除特别说明，所有响应均包含：`success`、`error`、`message`、`data`。

### 1) Ping（健康检查）
- 请求：`ping_request`
```json
{ "type": "ping_request", "data": {} }
```
- 响应：`ping_response`
```json
{
  "type": "ping_response",
  "success": true,
  "error": 0,
  "data": { "uptime_ms": 1234567 }
}
```

### 2) 开关 Wi‑Fi
- 请求：`wifi_enable_request`
```json
{ "type": "wifi_enable_request", "data": { "enable": true } }
```
- 响应：`wifi_enable_response`
```json
{
  "type": "wifi_enable_response",
  "success": true,
  "error": 0,
  "data": { "enabled": true }
}
```

### 3) 获取状态
- 请求：`wifi_status_request`
```json
{ "type": "wifi_status_request", "data": {} }
```
- 响应：`wifi_status_response`
```json
{
  "type": "wifi_status_response",
  "success": true,
  "error": 0,
  "data": {
    "enabled": true,
    "connected": true,
    "ssid": "MyHomeNetwork",
    "bssid": "aa:bb:cc:dd:ee:ff",
    "interface": "wlan0",
    "ip": "192.168.1.23",
    "signal": 78,          // 0-100
    "security": "WPA2",
    "channel": 6,
    "frequency_mhz": 2437
  }
}
```

### 4) 扫描网络
- 请求：`wifi_scan_request`
```json
{ "type": "wifi_scan_request", "data": { "rescan": true } }
```
- 响应：`wifi_scan_response`
```json
{
  "type": "wifi_scan_response",
  "success": true,
  "error": 0,
  "data": {
    "networks": [
      {
        "ssid": "MyHomeNetwork",
        "bssid": "aa:bb:cc:dd:ee:ff",
        "signal": 78,
        "security": "WPA2",
        "channel": 6,
        "frequency_mhz": 2437
      },
      {
        "ssid": "CafeWiFi",
        "bssid": "11:22:33:44:55:66",
        "signal": 55,
        "security": "Open",
        "channel": 1,
        "frequency_mhz": 2412
      }
    ]
  }
}
```

### 5) 连接网络
- 请求：`wifi_connect_request`
```json
{
  "type": "wifi_connect_request",
  "data": {
    "ssid": "MyHomeNetwork",
    "password": "mysecretpassword",
    "bssid": "optional",
    "security": "WPA2",
    "timeout_ms": 20000
  }
}
```
- 响应（示例：成功）：`wifi_connect_response`
```json
{
  "type": "wifi_connect_response",
  "success": true,
  "error": 0,
  "data": {
    "connected": true,
    "ssid": "MyHomeNetwork",
    "interface": "wlan0",
    "ip": "192.168.1.23"
  }
}
```
- 响应（示例：失败）：
```json
{
  "type": "wifi_connect_response",
  "success": false,
  "error": -1,
  "message": "unknown error",
  "data": { "connected": false }
}
```

### 6) 断开连接
- 请求：`wifi_disconnect_request`
```json
{ "type": "wifi_disconnect_request", "data": { "ssid": "MyHomeNetwork" } }
```
- 响应：`wifi_disconnect_response`
```json
{
  "type": "wifi_disconnect_response",
  "success": true,
  "error": 0,
  "data": { "disconnected": true }
}
```

### 7) 配置档（可选）
- 列出配置：`wifi_profiles_request` → `wifi_profiles_response`
```json
{
  "type": "wifi_profiles_response",
  "success": true,
  "error": 0,
  "data": {
    "profiles": [
      { "ssid": "MyHomeNetwork", "security": "WPA2", "autoconnect": true },
      { "ssid": "Office", "security": "WPA2", "autoconnect": false }
    ]
  }
}
```
- 保存配置：`wifi_profile_save_request` → `wifi_profile_save_response`
```json
{ "type": "wifi_profile_save_request", "data": { "ssid": "MyHomeNetwork", "password": "mysecretpassword", "autoconnect": true } }
```
- 删除配置：`wifi_profile_delete_request` → `wifi_profile_delete_response`
```json
{ "type": "wifi_profile_delete_request", "data": { "ssid": "MyHomeNetwork" } }
```

## 事件推送（可选）
后端可在状态变化时主动推送事件，前端订阅处理即可。

- 连接状态事件：`wifi_connect_event`
```json
{ "type": "wifi_connect_event", "data": { "connected": true, "ssid": "MyHomeNetwork" } }
```
- 断开事件：`wifi_disconnect_event`
```json
{ "type": "wifi_disconnect_event", "data": { "connected": false, "ssid": "MyHomeNetwork" } }
```
- 扫描完成事件：`wifi_scan_event`
```json
{ "type": "wifi_scan_event", "data": { "networks": [ /* 同上 */ ] } }
```

## 错误码枚举

为简化解析，错误码使用整型；`0` 表示成功，不同场景的失败为非零。保留 `-1` 表示未知错误以兼容你的示例。

```c
typedef enum {
  WIFI_ERR_OK = 0,
  WIFI_ERR_UNKNOWN = -1,

  WIFI_ERR_BAD_REQUEST = 1,        // 数据缺失/类型不符
  WIFI_ERR_NOT_SUPPORTED = 2,      // 操作不支持
  WIFI_ERR_WIFI_DISABLED = 3,      // Wi‑Fi 已关闭
  WIFI_ERR_ALREADY_CONNECTED = 4,  // 已连接同一 SSID
  WIFI_ERR_NETWORK_NOT_FOUND = 5,  // 扫描无该 SSID
  WIFI_ERR_AUTH_FAILED = 6,        // 认证失败/密码错误
  WIFI_ERR_TIMEOUT = 7,            // 连接/操作超时
  WIFI_ERR_INTERNAL = 8,           // 后端内部错误
  WIFI_ERR_PERMISSION = 9,         // 权限不足
  WIFI_ERR_BUSY = 10,              // 设备繁忙/正在进行其他操作
  WIFI_ERR_INVALID_SSID = 11,
  WIFI_ERR_INVALID_PASSWORD = 12,
  WIFI_ERR_INTERFACE_DOWN = 13,    // 网卡未启动/无效
  WIFI_ERR_TOOL_ERROR = 14,        // 底层工具错误（nmcli/wpa_cli）
  WIFI_ERR_CONFIG_ERROR = 15,      // 配置存储/读取失败
  WIFI_ERR_IO_ERROR = 16,          // I/O 异常
  WIFI_ERR_NOT_CONNECTED = 17      // 未连接
} wifi_error_t;
```

## 示例：Wi‑Fi 连接请求/响应

请求：
```json
{
  "type": "wifi_connect_request",
  "data": {
    "ssid": "MyHomeNetwork",
    "password": "mysecretpassword"
  }
}
```

响应（成功）：
```json
{
  "type": "wifi_connect_response",
  "data": {
    "success": true,
    "error": 0
  }
}
```

响应（失败）：
```json
{
  "type": "wifi_connect_response",
  "data": {
    "success": false,
    "error": -1
  }
}
```

> 说明：为兼容你的示例，此处在响应中也展示了把 `success` 和 `error` 放到 `data` 内的变体。推荐做法仍是把 `success/error/message` 放在响应的顶层，见上文统一结构。

## 前端建议（Flutter）
- 封装一个 `WebSocketClient`，统一发送 `type/request_id/data`，并用 `request_id` 路由响应。
- 将每个操作封装为方法：`enableWifi(bool)`, `scan()`, `connect(ssid, password)`, `status()`, `disconnect([ssid])`。
- 对事件使用 `Stream` 广播到 UI。

## 后端建议（C）
- 解析 JSON（如 cJSON、yyjson），校验 `type` 和 `data`。
- 调用底层工具：`nmcli` / `wpa_cli` / 直接 D‑Bus（libnm），并按结果映射错误码。
- 响应始终保持统一结构；超时可用线程/定时器实现。

## 兼容与演进
- 可逐步引入认证（如在握手阶段），消息结构不变。
- 新增操作时沿用相同外层结构，前后端零改动即可路由与解析。