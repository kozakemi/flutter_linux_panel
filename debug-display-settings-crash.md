# Debug Session: display-settings-crash
- **Status**: [OPEN]
- **Issue**: 开发板点击设置后，进入显示设置界面出现闪退，但当前没有有效日志可用于定位崩溃点。
- **Debug Server**: http://198.18.0.1:7778/event
- **Log File**: .dbg/trae-debug-log-display-settings-crash.ndjson

## Reproduction Steps
1. 在开发板启动应用。
2. 点击“设置”入口。
3. 进入“显示设置”界面。
4. 观察到应用闪退，当前缺少有效日志。

## Hypotheses & Verification
| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | 显示设置页初始化时触发平台通道/原生服务调用，抛出未捕获异常或导致宿主进程退出。 | High | Low | Pending |
| B | 设置页跳转到显示设置页时，页面构建依赖的状态为空或类型不符，导致 Flutter 层构建期异常。 | High | Low | Pending |
| C | 页面进入后的监听器、定时器或异步回调在首帧前后触发异常。 | Medium | Medium | Pending |
| D | 问题不在 Dart 层，而是底层插件/FFI/平台实现触发 native crash，因此 Flutter 控制台几乎无日志。 | Medium | Medium | Pending |

## Log Evidence
Pending

## Verification Conclusion
Pending

## Instrumentation Points
1. `lib/settings_page.dart`: 点击“显示设置”前记录路由跳转事件，用于确认是否真正进入目标页面链路。
2. `lib/setting/display_page.dart`: 记录 `initState`、亮度模块初始化入口、状态返回与异常分支，用于区分页面构建问题和亮度初始化问题。
3. `lib/services/native_brightness_service.dart`: 记录 `initialize`、后端探测、`getStatus` 进入/返回与错误处理，用于确认是否在亮度服务边界附近闪退。
