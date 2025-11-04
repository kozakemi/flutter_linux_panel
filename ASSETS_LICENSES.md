# 资源许可与合规说明

本文件用于说明本仓库中字体与图标等视觉资源的许可与使用边界。代码许可为 `Apache License 2.0`，详见仓库根目录 `LICENSE`。

## HarmonyOS Sans 字体

- 位置与来源：`source/fonts/HarmonyOS_Sans/`（含 `LICENSE_Fonts`）
- 许可证：HarmonyOS Sans Fonts License Agreement（随字体提供的许可文件 来自https://gitee.com/openharmony/global_system_resources/blob/master/LICENSE_Fonts）
- 允许范围：
  - 复制、合并（含产品打包）、嵌入、捆绑、再分发和/或销售未修改的字体副本。
  - 在应用、系统或发行包中以嵌入形式使用字体（不直接修改字体文件）。
- 使用要求：
  - 在任何副本中保留版权声明与本许可协议（参考许可条款：`YOU shall retain the copyright notice and this Agreement in any copies of HarmonyOS Sans Fonts.`）。
  - 分发或发布包需包含 `source/fonts/HarmonyOS_Sans/LICENSE_Fonts`，或在 `NOTICE`/`README` 明确标注字体来源与许可。
- 限制与禁止：
  - 不得修改字体文件（包含但不限于字形、命名、内部表等）。
  - 不得将字体作为独立资源再分发或销售（不得单独提供字体下载或售卖）。
- 终止与免责声明：
  - 违反许可条款授权将自动终止；字体按“现状”提供，无任何明示或暗示担保，详见原协议全文。
- 本项目使用说明：
  - 以嵌入和打包形式使用字体，不对字体本体进行改造或拆分；遵守原协议全文与声明保留要求。

## Iconfont 图标素材

- 位置与来源：
  - `source/ico/` 与 `source/app_ico/` 下的 `*.svg`、以及同目录的 `iconfont.pdf` 等文件。
  - 来自 Iconfont 平台；具体素材的授权以素材页面与平台“用户服务协议”为准（链接由用户提供）。
- 使用边界（根据平台声明与用户提供的条款要点）：
  - 该素材仅供广大用户交流学习使用，未经 Iconfont 或其关联公司书面授权许可，不得用于任何商业用途。
  - 若希望使用该素材，请提前联系作者，取得授权后再进行使用，避免造成侵犯作者知识产权。
  - 遵守平台服务协议及各素材的版权与署名要求，不将素材以独立形式再分发。
- 合规措施：
  - 在开源或分发包中保留素材来源与授权信息；在 `NOTICE` 或本文件记录素材清单、来源链接、作者信息与授权状态。
  - 商业发布前需替换为自有版权或已获商业授权的图标；或移除相关未获授权素材。
  - 一旦取得作者授权，应在本文件补充授权详情（作者、授权编号/凭据、有效期、素材链接等）。
  - 授权状态：当前仅学习使用；商业使用尚未取得授权。

## 资源清单与路径

- 字体资源：
  - `source/fonts/HarmonyOS_Sans/` 中的全部文件（含 `LICENSE_Fonts`）。
- 图标资源：
  - `source/ico/*.svg`
  - `source/app_ico/*.svg`
- 其他图片：
  - `source/background/*` 等其他图片文件请分别确认来源与许可后再分发或发布。

## 分发与声明要求

- 在任何发布或二次分发中：
  - 保留 `LICENSE`（Apache-2.0）、本文件 `ASSETS_LICENSES.md`、以及 `source/fonts/HarmonyOS_Sans/LICENSE_Fonts`。
  - 在 `README` 或 `NOTICE` 中标注第三方资源来源和许可，并保留必要的版权声明。
  - 不将任何图标或字体以独立资源形式再分发或销售。

## 变更记录

- 2025-11-04：初始版本，整理 HarmonyOS Sans 字体许可与 Iconfont 平台素材使用边界及合规措施。