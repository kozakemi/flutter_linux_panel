# WebSocket 屏幕亮度控制 API（前后端分离：前端 Flutter，后端 C）

版本：1.0.0  ·  传输：WebSocket(JSON)

后端监听：`ws://<host>:<port>/brightness`（端口示例：`8080`）。

## 设计原则

* 统一消息结构：所有请求/响应/事件均以相同的 JSON 外层结构进行封装。

* 类型约定：`type` 为蛇形命名，区分 `*_request`、`*_response`、`*_event`。

* 关联标识：所有请求与响应必须携带字符串 `request_id`；事件不携带。

* 简化数据：只传输亮度百分比（0-100）和必要的标志位。

## 通用消息结构

请求（Request）：

```json
{
  "type": "<operation>_request",
  "request_id": "<string>",
  "data": { /* operation payload */ }
}
```

响应（Response）：

```json
{
  "type": "<operation>_response",
  "request_id": "<same-string-request-id>",
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

* `success` 为布尔；成功时 `error` 应为 `0`；失败时为非零（见错误码枚举）。

* `message` 可选，用于人类可读错误或状态描述。

* `request_id` 必须在请求与响应中传递且类型为字符串，不接受数字；响应必须原样回显与请求一致的 `request_id`（包括失败场景）。事件不携带 `request_id`。

## 操作列表与数据结构

除特别说明，所有响应均包含：`success`、`error`、`message`、`data`。

### 1) 获取亮度状态

* 请求：`brightness_status_request`

```json
{ "type": "brightness_status_request", "request_id": "req-1", "data": {} }
```

* 响应：`brightness_status_response`

```json
{
  "type": "brightness_status_response",
  "request_id": "req-1",
  "success": true,
  "error": 0,
  "data": {
    "brightness": 75,           // 当前亮度百分比 0-100
    "auto_brightness": false    // 是否启用自动亮度（可选）
  }
}
```

### 2) 设置亮度

* 请求：`brightness_set_request`

```json
{
  "type": "brightness_set_request",
  "request_id": "req-2",
  "data": {
    "brightness": 80            // 目标亮度百分比 0-100
  }
}
```

* 响应（成功）：`brightness_set_response`

```json
{
  "type": "brightness_set_response",
  "request_id": "req-2",
  "success": true,
  "error": 0,
  "data": {
    "brightness": 80（可选）
  }
}
```

* 响应（失败）：

```json
{
  "type": "brightness_set_response",
  "request_id": "req-2",
  "success": false,
  "error": 2,
  "data": {
    "brightness": 80 （可选）
  }
}
```

### 3) 自动亮度控制（可选）

* 请求：`brightness_auto_request`

```json
{
  "type": "brightness_auto_request",
  "request_id": "req-3",
  "data": {
    "enable": true              // 启用/禁用自动亮度
  }
}
```

* 响应：`brightness_auto_response`

```json
{
  "type": "brightness_auto_response",
  "request_id": "req-3",
  "success": true,
  "error": 0,
  "data": {
    "auto_brightness": true     // 当前自动亮度状态
  }
}
```

## 事件推送（可选）

后端可在亮度变化时主动推送事件，前端订阅处理即可。

* 亮度变化事件：`brightness_event`

```json
{
  "type": "brightness_event",
  "data": {
    "brightness": 85,           // 新的亮度百分比
    "auto_brightness": false    // 自动亮度状态（可选）
  }
}
```

## 错误码枚举

为简化解析，错误码使用整型；`0` 表示成功，不同场景的失败为非零。

```c
typedef enum {
  BRIGHTNESS_ERR_OK = 0,
  BRIGHTNESS_ERR_UNKNOWN = -1,
  BRIGHTNESS_ERR_BAD_REQUEST = 1,        // 数据缺失/类型不符
  BRIGHTNESS_ERR_INVALID_VALUE = 2,      // 亮度值无效（超出0-100范围）
  BRIGHTNESS_ERR_NOT_SUPPORTED = 3,      // 设备不支持亮度调节
  BRIGHTNESS_ERR_PERMISSION = 4,         // 权限不足
  BRIGHTNESS_ERR_DEVICE_ERROR = 5,       // 硬件设备错误
  BRIGHTNESS_ERR_INTERNAL = 6            // 后端内部错误
} brightness_error_t;
```

## 示例：设置亮度请求/响应

请求：

```json
{
  "type": "brightness_set_request",
  "request_id": "req-brightness-1",
  "data": {
    "brightness": 60
  }
}
```

响应（成功）：

```json
{
  "type": "brightness_set_response",
  "request_id": "req-brightness-1",
  "success": true,
  "error": 0,
  "data": {
    "brightness": 60
  }
}
```

响应（失败）：

```json
{
  "type": "brightness_set_response",
  "request_id": "req-brightness-1",
  "success": false,
  "error": 2,
  "data": {
    "brightness": 60
  }
}
```

## 前端建议（Flutter）

* 封装一个 `BrightnessWebSocketClient`，统一发送 `type/request_id/data`，并用 `request_id` 路由响应

* 将每个操作封装为方法：`getBrightness()`, `setBrightness(int value)`, `setAutoBrightness(bool enable)`

* 对事件使用 `Stream` 广播到 UI，实现实时亮度显示

* 实现亮度滑块组件，支持 0-100% 的亮度调节

## 后端建议（C）

* 解析 JSON（如 cJSON、yyjson），校验 `type` 和 `data`

* 通过 `/sys/class/backlight/` 目录操作硬件亮度：

  * 读取 `brightness` 文件获取当前值

  * 读取 `max_brightness` 文件获取最大值

  * 写入 `brightness` 文件设置亮度

* 实现亮度值转换：百分比 ↔ 硬件原始值

* 权限检查：确保有写入 `/sys/class/backlight/` 的权限

* 错误处理：设备不存在、权限不足、I/O 错误等

## 系统集成

* **Linux**: 通过 `/sys/class/backlight/` 接口控制

* **权限要求**: 需要 root 权限或加入 `video` 组

* **设备检测**: 自动扫描 `/sys/class/backlight/` 下的可用设备

