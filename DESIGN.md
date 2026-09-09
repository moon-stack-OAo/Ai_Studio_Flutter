# AI Studio — DESIGN.md

产品设计规格（四端目标）。用于重构选型、原型对照与实现验收；实现细节见 [`docs/architecture.md`](./docs/architecture.md)。

| 项     | 值                                                                              |
|-------|--------------------------------------------------------------------------------|
| 产品    | AI Studio                                                                      |
| 定位    | 本地多模态 AI 客户端（密钥与会话仅存本机，无自建后端托管）                                                |
| 目标平台  | **Windows · macOS · Android · iOS**                                            |
| UI 策略 | **两套独立设计系统**：桌面 **Fluent** · 移动 **Material 3**（Android / iOS 共用 Material）      |
| 色彩气质  | **亮色仿 Claude**（暖奶油纸感）· **暗色仿 Cursor**（冷灰 IDE 感）                                |
| 文档状态  | Draft · 关键已决（Q1–Q3/Q5）；**P0–P2 已落地**；**P3 抛光已落地**（含 a11y 全路径自证清单；非第三方 WCAG 认证） |
| 实现栈   | **Flutter 新仓库**：`D:\Moon\tools\Ai_Studio_Flutter`                              |
| 分发更新  | **不上架应用商店**；延续现网直链自动更新（桌面清单 + Android 侧载清单）                                    |
| 关联    | 现网 Vue/Tauri 仅作能力规格与更新协议参考                                                     |

---

## 1. 产品目标

### 1.1 要解决什么

在桌面与手机上完成同一套**能力**（非同一套 UI）：

1. **对话**：多轮、SSE 流式、可停止 / 撤回、Markdown
2. **生图**：文生图 / 图生图、参数、时间线、下载 / 另存 / 相册
3. **生视频**：文生 / 图生、任务进度、恢复、播放与下载
4. **设置**：多提供商、密钥本机存储、外观、更新

跨端统一的是「提供商 → 模型 → 生成」心智与能力边界；**页面结构、导航、组件与动效按设计系统独立演进**。

### 1.2 非目标（本期不做）

- 自建账号体系 / 云同步会话
- 服务端代理密钥或计费
- 插件市场、Agent 工作流编排（超出「对话 + 媒体生成」）
- Linux 桌面（可预留，不进入首期验收）
- 强制 Flutter Web 作为主交付面
- **第三套 Cupertino 设计系统**（iOS 首期跟 Material；架构可预留，不纳入验收）
- 用一套线框强行套四端（禁止「换皮即交付」）

### 1.3 设计原则

| 原则             | 说明                                                   |
|----------------|------------------------------------------------------|
| 本地优先           | 配置、密钥、会话、媒体缓存均在本机；安全模型见 `SECURITY.md`                |
| **能力对等、UI 独立** | 四端功能清单对齐；Fluent / Material 各自完整，不要求布局或组件一一对应         |
| 提供商可扩展         | OpenAI / xAI / OpenAI 兼容；新兼容源优先「自定义」                 |
| 生成可中断          | 对话 / 生图 / 生视频均有进行中态与停止 / 取消                          |
| 平台礼貌           | Fluent 侧遵循桌面窗口 / 托盘 / 键盘；Material 侧遵循返回栈、安全区、相册与系统分享 |

---

## 2. 设计系统架构（核心约定）

### 2.1 分层：只共享业务，不共享 UI

```
┌─────────────────────────────────────────────────┐
│  design_fluent +    │  design_material +         │
│  desktop_fluent     │  mobile_material           │
│  Windows · macOS    │  Android · iOS             │
│  独立页面 · 组件 · 动效 · 导航 · 空态             │
├─────────────────────────────────────────────────┤
│  packages/core                                    │
│  （纯业务：会话、生成任务、提供商、安全 URL…）      │
└─────────────────────────────────────────────────┘
```

| 可共享                                 | 不可共享（禁止「抽一层通用 Widget 冒充两套系统」）        |
|-------------------------------------|--------------------------------------|
| Provider / adapter / SSE / 生图生视频状态机 | 导航壳、页面布局、列表/画廊结构                     |
| 设置数据模型、密钥存储接口                       | 按钮、对话框、AppBar/CommandBar、主题 token 实现 |
| 错误码与用户可读错误文案（可按系统改语气）               | 空态插画与排版、手势与右键菜单                      |
| 能力开关（某模型是否支持图生等）                    | 「逻辑组件同构、仅换皮肤」的伪独立                    |

验收标准：**能力清单**（能配 Key、能流式对话、能生图/视频…），**不是**同一套线框截图对齐。

### 2.2 两套系统定义

#### A. Fluent Design System（桌面）

| 项  | 约定                                                                                           |
|----|----------------------------------------------------------------------------------------------|
| 适用 | Windows · macOS                                                                              |
| 参照 | WinUI / Fluent 2 信息密度与控件语义（NavigationView、CommandBar、ContentDialog、TeachingTip、MenuFlyout 等） |
| 导航 | 左侧 NavigationView（或等价）；**常驻 compact ~56px 图标窄栏**（`toggleable: false`，不可展开/折叠）；设置可为 Nav 项或独立页 |
| 交互 | 悬停显隐、右键菜单、键盘快捷键、多栏分割                                                                         |
| 窗口 | 标题栏 / 无边框可选；关闭 → 退出 / 托盘 / 询问；系统托盘菜单                                                         |
| 密度 | 默认偏松（舒适）；支持紧凑                                                                                |
| 主题 | **亮 / 暗**（不提供跟随系统）；可用亚克力/云母等材质（非必须，按实现栈能力）                                                   |

#### B. Material 3 Design System（移动）

| 项  | 约定                                                                                         |
|----|--------------------------------------------------------------------------------------------|
| 适用 | **Android · iOS**（移动统一 Material，不做独立 Cupertino 系统）                                         |
| 参照 | Material 3（NavigationBar、TopAppBar、FAB/扩展钮、Modal BottomSheet、Snackbar、NavigationDrawer 按需） |
| 导航 | 底部 NavigationBar 四入口；二级用全屏页或 sheet                                                         |
| 交互 | 大触控目标、长按、滑动返回（iOS 边缘 / Android 预测返回与分层）；**禁止依赖悬停**                                         |
| 系统 | 安全区、软键盘避让（可收起底栏）、相册保存、分享表                                                                  |
| 密度 | 默认偏紧；触控不少于约 48dp                                                                           |
| 主题 | **亮 / 暗**（不提供跟随系统）；可用 M3 dynamic color（Android 可选，iOS 用固定种子色）                              |

### 2.2.1 色彩气质（跨 Fluent / Material 共用语义）

控件形态仍分 Fluent / Material；**亮/暗两套色板语义全局统一**，禁止亮色走冷灰 SaaS、暗色走暖棕网页风。

| 模式        | 参照            | 气质一句话                       | 禁止                           |
|-----------|---------------|-----------------------------|------------------------------|
| **Light** | **Claude.ai** | 暖奶油纸面 + 墨色字 + 克制珊瑚/陶土强调     | 纯冷白 `#fff` 铺底、科技蓝主按钮刷屏、高饱和渐变 |
| **Dark**  | **Cursor**    | 近黑冷灰 IDE 表面 + 清晰层级 + 单一冷色强调 | 暖棕暗底、霓虹多色强调、强发光边框            |

**仿的是气质与层级，不是商标/插画/专有字体的复制。** 字体用**各设计系统默认系统栈**（见 §2.2.2），勿嵌入 Anthropic / Cursor 专有字库与 Logo；禁止第三套跨端商业正文字体。

#### Light — Claude 向 Token（推荐起点）

| Token             | 建议值                               | 角色                      |
|-------------------|-----------------------------------|-------------------------|
| `canvas`          | `#faf9f5` / `#f8f8f6`             | 页面底（暖骨色，非纯白）            |
| `surface`         | `#ffffff` / `#efe9de`             | 卡片 / 升高面                |
| `surface-muted`   | `#efeeeb` / `#f5f0e8`             | 嵌套区、次级带                 |
| `ink`             | `#141413` / `#121212`             | 主文字（暖近黑）                |
| `ink-secondary`   | `#3d3d3a` / `#5c4f42`             | 次级文字                    |
| `ink-muted`       | `#6c6a64` / `#8a7b6b`             | 辅助说明                    |
| `border`          | `#e7e6e1` / `#e2d5c3`             | 发丝分割                    |
| `primary`         | `#cc785c` / `#c45c26` / `#d97757` | CTA / 关键强调（暖珊瑚·陶土，克制使用） |
| `primary-pressed` | `#a9583e` / `#a34b1f`             | 按下                      |
| `on-primary`      | `#ffffff`                         | 主按钮字色                   |

亮色排版气质：偏编辑感、留白略多；标题可用衬线**仅作营销/空态点缀**，产品主 UI 仍以无衬线为主（Fluent/M3 控件可读性优先）。

#### Dark — Cursor 向 Token（推荐起点）

| Token              | 建议值                   | 角色                |
|--------------------|-----------------------|-------------------|
| `canvas`           | `#0a0a0a` / `#09090b` | 编辑器级近黑底           |
| `surface`          | `#141414` / `#18181b` | 侧栏 / 面板           |
| `surface-elevated` | `#1c1c1c` / `#27272a` | 浮层、弹出、输入底         |
| `ink`              | `#fafafa` / `#eceff4` | 主文字               |
| `ink-secondary`    | `#a1a1aa` / `#c8c8c8` | 次级                |
| `ink-muted`        | `#71717a` / `#8b8b8b` | 辅助                |
| `border`           | `#27272a` / `#2e2e2e` | 低对比分割（避免刺眼亮线）     |
| `primary`          | `#3b82f6` / `#60a5fa` | 单一冷蓝强调（链接、主按钮、焦点） |
| `primary-pressed`  | `#2563eb` / `#4f8fe8` | 按下                |
| `on-primary`       | `#ffffff`             | 主按钮字色             |
| `focus-ring`       | primary @ 较低透明度       | 键盘焦点，清晰但不炫光       |

暗色排版气质：密度略高于亮色、信息优先；圆角略收；阴影极弱或改用边框分层（IDE 感）。

#### 映射规则（两套设计系统都要遵守）

| 规则                | 说明                                                                                         |
|-------------------|--------------------------------------------------------------------------------------------|
| 一模式一主色            | Light 只用暖珊瑚系作 primary；Dark 只用冷蓝系作 primary；**不要**亮暗共用同一 hue                                 |
| 表面分层靠明度           | Light：canvas < muted < card；Dark：canvas < surface < elevated                               |
| 语义色独立             | success / warning / error 另定，且不得抢 primary                                                  |
| Fluent / Material | 各自组件吃同一套 token；**禁止**再维护第三套「现网橙蓝」并行色板                                                      |
| 与现网关系             | 现网亮 `#f4efe6`+#c45c26、暗 `#0b1020`+#60a5fa 可作为过渡近似；**新设计以本节为准**，重构时允许漂移到 Claude/Cursor 更近的值 |

### 2.2.2 默认字体栈（按设计系统拆分 · 系统字体）

**原则**：不内嵌 Claude / Cursor / 其它商业正文字库；Fluent 与 Material **各自**指定默认栈；中文靠系统 CJK 回退。

| 设计系统         | 适用              | UI 正文（`--font` / `fontFamily`）                                                                                                              | 等宽（代码块 / 日志）                                               |
|--------------|-----------------|---------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------|
| **Fluent**   | Windows · macOS | `system-ui`, **`Segoe UI Variable`**, **`Segoe UI`**, `-apple-system`, `BlinkMacSystemFont`, `PingFang SC`, `Microsoft YaHei`, `sans-serif` | `Cascadia Code` / `Cascadia Mono` / `SF Mono` / `Consolas` |
| **Material** | Android · iOS   | **`Roboto`**, **`Noto Sans SC`**, `system-ui`, `-apple-system`, `PingFang SC`, `Microsoft YaHei`, `sans-serif`                              | `Roboto Mono` / `Noto Sans Mono` / `SF Mono` / `Consolas`  |

| 端上实际命中（实现时）      | 说明                                                                                  |
|------------------|-------------------------------------------------------------------------------------|
| Windows Fluent   | 优先 Segoe UI Variable → Segoe UI；中文 Microsoft YaHei                                  |
| macOS Fluent     | `-apple-system`（SF）优先；中文 PingFang SC                                                |
| Android Material | Roboto + Noto Sans SC（系统或 Google 预装）                                                |
| iOS Material     | 可用 Roboto（若随 Material 主题指定）或继续系统 UI + PingFang；**仍属 Material 包配置，不另开 Cupertino 字栈** |

Flutter 落点：`packages/design_fluent` 与 `packages/design_material` 的 `ThemeData` / `TextTheme` 分别设置；**不要**在 `packages/core` 写死统一 `fontFamily`。

### 2.3 端矩阵

| 端       | 设计系统       | 形态   | 系统能力（产品层）                              |
|---------|------------|------|----------------------------------------|
| Windows | Fluent     | 桌面窗口 | 托盘、关闭偏好、另存为、桌面更新                       |
| macOS   | Fluent     | 桌面窗口 | Dock / 关闭惯例、另存为、签名分发 / 更新              |
| Android | Material 3 | 全屏   | 返回分层、安全区、相册、**侧载清单自动更新**（不上架）          |
| iOS     | Material 3 | 全屏   | 手势返回、安全区、相册、**非 Store 分发 / 内测更新**（不上架） |

### 2.4 能力级信息架构（非页面线框）

跨端必须具备的**能力入口**（呈现方式由各设计系统自定）：

| 能力  | 语义                                        | Fluent 常见呈现          | Material 常见呈现          |
|-----|-------------------------------------------|----------------------|------------------------|
| 对话  | 多会话消息                                     | Nav 项 + 会话列表窗格 + 消息区 | Tab + 会话列表页/层 + 聊天页    |
| 生图  | 参数 + 时间线                                  | Nav 项 + 参数窗格 + 画廊    | Tab + 参数 sheet/区 + 时间线 |
| 生视频 | 任务 + 播放                                   | Nav 项 + 参数 + 进度/播放器  | Tab + 参数 + 进度/播放器      |
| 设置  | 提供商 / 对话默认 / 外观 / **日志** / 关于与更新（桌面含关闭行为） | Nav 项 + 五分类侧栏        | 底栏「设置」+ **五 Tab**      |

设置须在各系统内 **两步内可达**。默认移动端设置为 NavigationBar 第四项（可与现网 Android 一致）。

---

## 3. 关键用户流程（能力流，UI 分叉）

流程描述的是**业务步骤**；控件与页面跳转由 Fluent / Material 各自设计。

### 3.1 首次使用

**冷启动视觉序**（与功能引导无关）：原生纯色启动底（`flutter_native_splash` 仅 canvas `#faf9f5` / `#0a0a0a`，无 logo；Material 端避免与品牌首屏尺寸跳变）→ Flutter 短品牌首屏（`SHELL-BRAND-INTRO`，可跳过，≠ onboarding）→ `AppShell`。Material：仅预加载外观后即播品牌首屏，其余仓库并行后台加载，就绪后再挂壳。每次冷启动都播；与下方「首次配置提供商」划清。

1. 进入默认能力（建议：对话空态）
2. CTA：**添加提供商 / 填写 API Key**
3. 测试连接 → 拉取模型 → 可发送首条消息

空态需区分：「未配置提供商」与「已配置但无会话」。两套系统可有不同插画与排版，文案语义一致即可。

### 3.2 对话

```
选择或新建会话 → 选模型 / 可选会话级参数
  → 发送 → 流式输出（可停止）
  → 助手消息展示所用模型与响应耗时（如 `grok-4.5 · 52秒`）
  → 复制；用户末条可撤回（助手仅复制）；上下文受双上限约束
```

耗时展示（`CHAT-MSG-META`）：按量级自适应——`<1秒` 用毫秒（如 `850毫秒`）；`<60秒` 用整秒（如 `52秒`）；`≥60秒` 用 `x分x秒`（如 `1分23秒`）。格式为 `模型 · 耗时`。

**状态**：空闲 · 流式中 · 停止中 · 错误（可行动提示）。

|      | Fluent          | Material       |
|------|-----------------|----------------|
| 会话列表 | 常驻窗格或可钉         | 独立页或 modal/全屏层 |
| 消息操作 | 右键 / CommandBar | 长按 / 顶栏更多      |
| 返回   | 无「物理返回」语义       | 先关层再离页         |

### 3.3 生图

```
选模型与能力 → 参数 → 提示词（可辅助）· 可选参考图
  → 生成（可停止）→ 预览 / 灯箱 → 下载或相册 → 可作参考图
```

参数面板：Fluent 可用侧翼窗格；Material 可用折叠区或 BottomSheet——**不要求同构**。

### 3.4 生视频

```
选模型与能力 → 参数 + 提示词 + 可选参考图
  → 创建任务 → 进度（可取消）→ 播放 / 下载；支持恢复未完成任务
```

进度与失败态须在两套 UI 中都可读；交互控件可不同（桌面主按钮 + 详情；移动线性进度 + Snackbar）。

### 3.5 设置与更新

能力块（两套系统都要有对应界面，信息架构可不同）：

- **提供商**：CRUD、预设、自定义兼容、测试连接、拉取模型；**按能力分设模型**（对话 / 生图 / 生视频）。模型来自拉取列表，控件为**可搜索下拉**（输入用于过滤，对齐现网 `filterable` + `tag`）；视频可「不使用」留空
- **对话默认**：温度、系统提示、Max Tokens、超时、上下文裁剪
- **外观**：主题（**仅浅色 / 深色**，不提供跟随系统）、**字号五档**、密度（密度含义可按系统解释）
- **日志**（必有）：本机运行日志查看 / 筛选 / 搜索 / 复制 / 清空；时间格式 `YYYY-MM-DD HH:mm:ss`；不得含密钥明文
- **关于与更新**：版本、检查更新、开源说明、导入导出 / 清数据；桌面安装更新；Android 侧载清单；iOS 非 Store 说明
- **仅 Fluent · 关闭行为**：退出 / 托盘 / 询问 —— **归入「关于与更新」页内**，不单独占设置分类

#### 设置信息架构（已决 · 对齐现网 + 原型）

| 端        | 呈现                            | 分类顺序                                        |
|----------|-------------------------------|---------------------------------------------|
| Fluent   | 左分类栏 + 右内容（与会话栏同宽约 260px 第二栏） | 提供商 → 对话默认 → 外观 → **日志** → **关于与更新**（含关闭行为） |
| Material | 顶栏五 Tab（可横滑）                  | 提供商 → 对话 → 外观 → **日志** → 关于                 |

---

## 4. 界面结构（分系统示意，非强制像素稿）

### 4.1 Fluent（Win / Mac）示意

```
┌─────────────────────────────────────────────┐
│ TitleBar / 窗口控点                           │
├──────────┬──────────────────────────────────┤
│ NavView  │  CommandBar / 工具条               │
│ 对话     ├──────────────────────────────────┤
│ 生图     │  多栏工作区（列表 · 内容 · 属性）    │
│ 生视频   │                                  │
│ 设置     ├──────────────────────────────────┤
│          │  Composer / 状态条                 │
└──────────┴──────────────────────────────────┘
```

破坏性操作使用 ContentDialog（或等价）确认。

### 4.2 Material（Android / iOS）示意

```
┌─────────────────────┐
│ TopAppBar           │
├─────────────────────┤
│ 主内容（单栏为主）    │
├─────────────────────┤
│ Composer / 主操作    │
├─────────────────────┤
│ NavigationBar ×4    │  ← IME 可见时可隐藏
└─────────────────────┘
```

列表、灯箱、重参数以 **全屏子页或 Modal sheet** 呈现；系统返回先关闭最上层。

---

## 5. 组件策略与双系统规格表

### 5.1 禁止与允许

- **禁止**：维护一份「跨端通用 UI 组件库」再主题切换，充当 Fluent + Material。
- **允许**：极薄的无 UI 绑定层（如 `ChatSessionFacade`、`ImageSessionFacade`、`VideoJobFacade`、`SettingsRepository`），供两套 UI 调用。
- **Markdown**：可共享解析与纯渲染内核；工具条、代码主题、复制入口分系统包装。
- **ID 约定**：下表 `F-*` = Fluent 规格，`M-*` = Material 规格；同一行 = **同一能力面**，实现必须分属两套包，不得互相 import UI。

### 5.2 规格表读法

| 列        | 含义                    |
|----------|-----------------------|
| 能力 ID    | 稳定标识，原型标注与验收用例引用      |
| 职责       | 必须满足的产品行为             |
| Fluent   | Win/Mac 组件取向与关键交互     |
| Material | Android/iOS 组件取向与关键交互 |
| 关键状态     | 两端都要覆盖的状态机（呈现控件可不同）   |

密度：Fluent 默认舒适；Material 默认紧凑触控（主操作 ≥ ~48dp）。

---

### 5.3 壳层与导航

| 能力 ID               | 职责         | Fluent（F）                                                         | Material（M）                                           | 关键状态                            |
|---------------------|------------|-------------------------------------------------------------------|-------------------------------------------------------|---------------------------------|
| `NAV-ROOT`          | 四能力入口切换    | `F-NavView`：左侧 NavigationView，**常驻 compact ~56px**（不可展开/折叠）；当前项高亮 | `M-NavBar`：底部 NavigationBar 四项；IME 可见时可隐藏             | 对话 / 生图 / 生视频 / 设置              |
| `NAV-TITLE`         | 当前区标题与全局动作 | `F-TitleBar` + 可选窗口控点；内容区 `F-CommandBar`                          | `M-TopAppBar`：标题 + 溢出 `More`；可叠搜索                     | 普通 / 选择模式（若有）                   |
| `NAV-BACK`          | 关闭层、返回上一级  | 无系统返回；Esc 关 Dialog/Flyout；窗格关闭按钮                                  | `M-BackHost`：系统返回 / 边缘滑动先 pop 层；根页「再按一次退出」进最近任务（不清数据） | 无层 / 有层栈 / 待确认退出                |
| `SHELL-SAFE`        | 避让系统 UI    | 窗口边距即可                                                            | `M-SafeArea`：顶底 inset；不遮挡 NavBar/Composer             | 竖屏 / 横屏 / 刘海                    |
| `SHELL-TRAY`        | 托盘与关闭（仅桌面） | `F-TrayMenu` + `F-CloseConfirm`（退出 / 托盘 / 询问）                     | —（不适用）                                                | Ask / Quit / Tray               |
| `SHELL-THEME`       | 亮暗切换入口     | `F-ThemeToggle`（设置内 + 可选 CommandBar）                              | `M-ThemePref`（设置内）                                    | **light / dark only**（无 system） |
| `SHELL-BRAND-INTRO` | 冷启动品牌首屏    | `F-BrandIntro`（可跳过短覆层）                                            | `M-BrandIntro`（可跳过短覆层）                                | 原生纯色底→短品牌→壳                     |

---

### 5.4 对话

| 能力 ID               | 职责             | Fluent（F）                                                         | Material（M）                                  | 关键状态                          |
|---------------------|----------------|-------------------------------------------------------------------|----------------------------------------------|-------------------------------|
| `CHAT-SESSION-LIST` | 会话 CRUD、选中、空态  | `F-SessionList`：左窗格 ListView；新建在窗格顶；右键删/重命名                       | `M-SessionList`：全屏或 modal 列表；FAB/顶栏「新建」；长按操作 | 空 / 加载 / 有数据 / 编辑中            |
| `CHAT-SESSION-OPEN` | 打开列表           | 常驻窗格或可钉                                                           | `M-SessionHistoryBtn` → 打开列表层/页              | 开 / 关                         |
| `CHAT-MODEL`        | 选模型、刷新列表       | `F-ModelCombo`：可搜索 ComboBox / 飞出列表 + 刷新                           | `M-ModelPicker`：顶栏入口 → 菜单或全屏单选页 + 刷新         | 加载中 / 失败 / 空列表                |
| `CHAT-OVERRIDE`     | 本会话参数覆盖        | `F-SessionOverrides`：Modal/ContentDialog 内表单（建议宽 ≈480）            | `M-SessionOverrides`：子页或 BottomSheet 表单      | 默认 / 已覆盖（可视指示）                |
| `CHAT-STREAM`       | 消息流展示          | `F-MessageList`：气泡 + 角色区分；流式尾气泡                                   | `M-MessageList`：单栏气泡；流式尾气泡                   | 空闲 / 流式中                      |
| `CHAT-MSG-META`     | 助手消息元信息        | 角色旁 `模型 · 耗时`；耗时自适应：`<1s`→毫秒、`<60s`→秒、`≥60s`→`x分x秒`；流式中可暂隐耗时或仅显模型 | 同语义；字号触控友好                                   | 流式中 / 完成（有模型、有耗时）             |
| `CHAT-MD`           | Markdown / 代码块 | `F-MarkdownHost`：块级复制在代码框角                                        | `M-MarkdownHost`：同内核；复制入口触控友好                | 渲染中 / 完成                      |
| `CHAT-MSG-ACTIONS`  | 复制；撤回仅用户末条     | 悬停显按钮 + **右键 MenuFlyout**（用户末条：复制+撤回；助手：仅复制）                      | 长按 BottomSheet（用户末条：复制+撤回；助手：仅复制）            | 用户末条可撤回 / 助手仅复制               |
| `CHAT-COMPOSER`     | 输入与发送/停止       | `F-Composer`：多行 TextBox；主按钮发送；流式中变停止；Enter 发送（可配）                 | `M-Composer`：TextField + 发送/停止；IME 不挡输入      | 空闲 / 可发送 / 流式中 / 禁用           |
| `CHAT-EMPTY`        | 未配置 / 无会话空态    | `F-ChatEmpty`：短文案 + 主按钮（去设置 / 新建）                                 | `M-ChatEmpty`：同语义，竖向 CTA                     | 未配置 Key / 无会话                 |
| `CHAT-ERROR`        | 发送失败可行动提示      | CommandBar 下 InfoBar 或气泡内错误                                       | Snackbar + 气泡内错误文案                           | 超时 / 取消 / 4xx / 5xx / 不安全 URL |

---

### 5.5 生图

| 能力 ID          | 职责                 | Fluent（F）                               | Material（M）                                | 关键状态           |
|----------------|--------------------|-----------------------------------------|--------------------------------------------|----------------|
| `IMG-PARAMS`   | 数量、尺寸/比例、质量等       | `F-ImageParams`：侧翼窗格或分割视图属性栏            | `M-ImageParams`：折叠区或 Modal BottomSheet     | 按模型能力显隐字段      |
| `IMG-PROMPT`   | 提示词 + 辅助           | `F-PromptBox` + `F-PromptAssist`（面板/折叠） | `M-PromptBox` + `M-PromptAssist`（sheet/折叠） | 编辑中 / 辅助加载     |
| `IMG-REF`      | 参考图增删              | `F-RefImage`：拖放 + 缩略图 + 清除              | `M-RefImage`：点选相册/文件 + 预览 + 清除             | 无 / 有参考图       |
| `IMG-GENERATE` | 生成 / 停止            | `F-GenPrimary`：窗格底主按钮；忙时停止              | `M-GenPrimary`：底栏上方主按钮；忙时停止                | 空闲 / 忙 / 停止中   |
| `IMG-TIMELINE` | 结果时间线（**按回合时间分隔**） | `F-ImageTimeline`：自适应网格；每回合含用户提示 + 结果块  | `M-ImageTimeline`：竖向卡片流；回合分隔可读             | 空 / 生成中占位 / 有图 |
| `IMG-LIGHTBOX` | 大图浏览               | `F-Lightbox`：遮罩 + 左右键切换                 | `M-Lightbox`：全屏 + 滑动切换                     | 开 / 关          |
| `IMG-ACTIONS`  | 下载、另存、作参考          | 悬停工具条 + 右键                              | 长按 / 顶栏 / 预览内动作；**存相册**                    | 权限拒绝时提示        |
| `IMG-SESSION`  | 生图会话列表（若保留多会话）     | 对齐 `CHAT-SESSION-LIST` 的 Fluent 窗格模式    | 对齐 Material 列表层模式                          | 同对话会话态         |

---

### 5.6 生视频

| 能力 ID            | 职责                   | Fluent（F）                                                     | Material（M）                                              | 关键状态                                                                                                                                                |
|------------------|----------------------|---------------------------------------------------------------|----------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| `VID-PARAMS`     | 时长、比例等               | `F-VideoParams`：属性窗格                                          | `M-VideoParams`：sheet / 折叠                               | 按能力显隐                                                                                                                                               |
| `VID-PROMPT-REF` | 提示词 + 参考图            | 复用 Prompt/Ref 的 Fluent 变体                                     | 复用 Material 变体                                           | 同生图                                                                                                                                                 |
| `VID-GENERATE`   | 创建任务 / 取消            | `F-VideoPrimary`                                              | `M-VideoPrimary`                                         | 空闲 / 提交中                                                                                                                                            |
| `VID-QUEUE`      | 任务队列与进度（**按回合时间分隔**） | `F-VideoQueue`：状态筛选 Chip + 每回合提示词 + 任务卡 + ProgressBar + 放弃/重试 | `M-VideoQueue`：状态筛选 Chip + 卡片列表 + LinearProgress + 放弃/重试 | 筛选：全部 / 生成中 / 待恢复 / 已完成 / 失败 / 已放弃；条目态 loading / pending_resume / success / error / abandoned（规格文案 queued·running·succeeded·failed·abandoned 为对外表述） |
| `VID-PLAYER`     | 播放完成片                | `F-VideoPlayer`：内嵌播放器 + 下载                                    | `M-VideoPlayer`：全屏友好播放 + 下载/相册                           | 本地 / 远端 URL；缓冲                                                                                                                                      |
| `VID-RESUME`     | 启动时恢复未完成             | 静默续跑 + InfoBar 提示                                             | 静默续跑 + Snackbar                                          | 无可恢复 / 恢复中                                                                                                                                          |

---

### 5.7 设置

| 能力 ID                | 职责                                 | Fluent（F）                                                                                    | Material（M）                                     | 关键状态                                    |
|----------------------|------------------------------------|----------------------------------------------------------------------------------------------|-------------------------------------------------|-----------------------------------------|
| `SET-SHELL`          | 设置信息架构                             | `F-Settings`：**五分类**侧栏 + 右页（提供商 / 对话默认 / 外观 / 日志 / 关于）                                       | `M-Settings`：**五 Tab**（提供商 / 对话 / 外观 / 日志 / 关于） | —                                       |
| `SET-PROVIDERS`      | 提供商列表 CRUD                         | `F-ProvidersList`：列表点选 + 右侧表单                                                                | `M-ProvidersList`：列表点选切换；「编辑所选」打开 BottomSheet   | 空 / 有项                                  |
| `SET-PROVIDER-EDIT`  | Base URL、Key、类型、测试连接、拉模型、**分能力模型** | `F-ProviderForm`：分区表单；**对话 / 生图 / 视频** 各一 **可搜索下拉**（选项=拉取结果；输入=过滤，对齐现网 `filterable` + `tag`） | `M-ProviderForm`：BottomSheet；分区表单；**底栏固定**保存/取消 | 未拉取 / 拉取中 / 成功 / 失败；Key 掩码；视频可「不使用」留空   |
| `SET-CHAT-DEFAULTS`  | 温度、系统提示、Max Tokens、超时、上下文裁剪        | `F-ChatDefaults`                                                                             | `M-ChatDefaults`                                | 校验错误                                    |
| `SET-APPEARANCE`     | 主题、字号、密度                           | `F-Appearance`：主题仅浅/深并联动对侧稿；字号五档；密度=Fluent 疏密                                                | `M-Appearance`：同上；密度=触控疏密                       | **light / dark**（无跟随系统）                 |
| `SET-LOGS`           | **运行日志**（必有）                       | `F-Logs`：筛选级别/来源、搜索、复制可见、清空；控制台列表最新在上                                                        | `M-Logs`：同能力，触控工具栏更紧凑                           | 空 / 有数据 / 过滤后空；时间 `YYYY-MM-DD HH:mm:ss` |
| `SET-ABOUT`          | 版本、检查更新、开源说明、数据清理                  | `F-About`：自动检查开关、状态 pill、changelog、更新按钮；**内嵌关闭行为**                                           | `M-About`：同上（无关闭行为）                             | 检查中 / 有更新 / 已最新 / 失败；可跳过版本              |
| `SET-DATA`           | 导入导出、清数据                           | Dialog 确认                                                                                    | Dialog / 确认 sheet                               | 危险操作二次确认                                |
| `SET-CLOSE-BEHAVIOR` | 关闭行为                               | **仅 Fluent** `F-CloseBehavior`，**嵌在关于页**（非独立分类）                                              | —                                               | Ask / Quit / Tray                       |

**字号五档（`SET-APPEARANCE`，已决）**：更小 · 较小 · **标准（默认）** · 较大 · 更大。

---

### 5.8 反馈、覆层与系统力

| 能力 ID           | 职责       | Fluent（F）                                                       | Material（M）                                           | 关键状态                                            |
|-----------------|----------|-----------------------------------------------------------------|-------------------------------------------------------|-------------------------------------------------|
| `FB-CONFIRM`    | 破坏性确认    | `F-ContentDialog`                                               | `M-ConfirmDialog` / 确认 sheet                          | 开 / 关                                           |
| `FB-TOAST`      | 短反馈      | InfoBar / TeachingTip                                           | Snackbar                                              | 成功 / 失败                                         |
| `FB-PROGRESS`   | 不确定或确定进度 | ProgressRing / ProgressBar                                      | Circular / LinearProgress                             | —                                               |
| `FB-UPDATE`     | 更新提示     | 冷启动/托盘 **ContentDialog**（跳过 / 稍后 / 下载并安装）；设置侧栏 **NEW** 角标；关于页内联 | 冷启动 **AlertDialog**（同上）；底栏设置 **Badge**；关于页 / Snackbar | 见 `SET-ABOUT`；`UpdatePrefs`（自动检查 / 跳过版本 / 可用版本） |
| `SYS-SAVE-FILE` | 另存为（桌面）  | 系统保存对话框                                                         | —                                                     | 取消 / 成功                                         |
| `SYS-GALLERY`   | 存相册（移动）  | —                                                               | 系统相册写入；权限说明                                           | 已授权 / 拒绝                                        |
| `SYS-SHARE`     | 系统分享（移动） | —                                                               | Share sheet（`share_plus`）；图/视频本地文件                    | 取消 / 成功 / 失败                                    |

---

### 5.9 与现网能力映射（便于迁移对照）

现网组件 → 能力 ID（实现栈迁移时作核对清单，**不是**要求复用 Vue 组件）：

| 现网（约）                                              | 能力 ID                                             |
|----------------------------------------------------|---------------------------------------------------|
| `ModelSelect`                                      | `CHAT-MODEL`（生图/视频侧栏同能力）                          |
| `ComposerSendStop`                                 | `CHAT-COMPOSER` / `IMG-GENERATE` / `VID-GENERATE` |
| `MarkdownRenderer`                                 | `CHAT-MD`                                         |
| `SessionList`（desktop/android）                     | `CHAT-SESSION-LIST`                               |
| `SessionOverridesPanel`                            | `CHAT-OVERRIDE`                                   |
| `PromptAssist` / `PromptBuilder*`                  | `IMG-PROMPT` / `VID-PROMPT-REF`                   |
| `GenerateParamsPanel` / `Drawer`                   | `IMG-PARAMS` / `VID-PARAMS`                       |
| `GenerateTimeline*`                                | `IMG-TIMELINE`                                    |
| `ProvidersSettings` 等 settings/*                   | `SET-*`                                           |
| `TitleBar` / `CloseConfirm` / `TrayActionListener` | `NAV-TITLE` / `SHELL-TRAY` / `SET-CLOSE-BEHAVIOR` |
| `UpdateChecker`                                    | `FB-UPDATE` / `SET-ABOUT`                         |
| Android `SessionTopBar` / `useBackCloseLayer`      | `M-TopAppBar` / `NAV-BACK`                        |

---

### 5.10 原型标注约定

- 每个画板组件角落标注能力 ID（如 `F-Composer` / `M-Composer`）。
- 同一能力 ID 在 Fluent / Material 画板上**布局允许完全不同**，须都能走到关键状态列。
- 评审勾选：§5.3–5.8 每行至少一端有稿；P0 最低集：`NAV-*`（Fluent）、`CHAT-*`、`SET-PROVIDERS`、`SET-PROVIDER-EDIT`、`FB-CONFIRM`。

---

## 6. 内容与文案

- 中文为主；错误可行动（如「检查 API Key / Base URL」）。
- 不暴露堆栈；区分超时、取消、HTTP、不安全 URL。
- 两套系统可调整句式长短（桌面略完整、移动略短），**语义与错误分类一致**。

---

## 7. 无障碍与输入

| Fluent       | Material                |
|--------------|-------------------------|
| 键盘可达主路径；可见焦点 | 触控目标充足（≥48）；不依赖悬停       |
| 与系统高对比度尽量兼容  | 横屏不遮挡 Composer / NavBar |
| 失败不只靠颜色      | 失败不只靠颜色                 |

### 7.1 实现约定（WCAG 2.2 AA **自证**，非第三方认证）

| 项       | 约定                                                                                           |
|---------|----------------------------------------------------------------------------------------------|
| 语义      | 图标按钮均有 `tooltip` / `Semantics(button,label)`；列表行含 `selected` 与状态文案；输入框有可读 label（消息/提示词/搜索日志） |
| 动态播报    | 更新横幅、生图/生视频进行中条使用 `Semantics(liveRegion: true)`                                              |
| 触控 / 焦点 | Material 主操作与时间线操作钮 ≥48；Fluent 自定义控件用 HoverButton/焦点环，工具钮悬停或焦点可见                             |
| 不只靠颜色   | 错误保留文案；模型就绪/未就绪写入语义 label；会话参数「已覆盖」写入 Semantics                                              |
| 对比度     | token：`inkMuted` / 暗色 `success` / `focusRing` 已按 AA 方向微调（见 `design_*` tokens）                |
| Windows | 仅 **debug** 整树 `ExcludeSemantics` 规避 AXTree 刷错；**release / profile 语义树可用**                   |

自证范围：双端壳导航、会话列表、Composer、生图/生视频主路径、设置分类与危险操作、空态 CTA、灯箱/播放器主控件。未宣称第三方实验室认证。

---

## 8. 数据与隐私（设计约束，与 UI 无关）

- API Key：本机；新实现优先 Keychain / Keystore。
- 会话与媒体本地可清理；展示占用。
- 出站 URL 安全策略对齐现网 `urlSafety`。
- 日志不得含密钥明文。

---

## 9. 分阶段交付

### P0 — Fluent 桌面 MVP（Windows + macOS）· **已满足**

- **完整 Fluent 壳**（勿先做「临时通用壳」）
- 对话 SSE + 设置（提供商 / 密钥 / 模型）+ Markdown + 本地会话
- **验收**：双端「配 Key → 流式对话」；视觉可识别为 Fluent，而非套皮 Material
- 工程落点：`D:\Moon\tools\Ai_Studio_Flutter`（`apps/desktop_fluent` + `packages/core`）

### P1 — Fluent 生成与桌面系统力 · **已满足**

- 生图、生视频（含恢复）
- 托盘 / 关闭偏好
- **桌面直链自动更新**（对齐现网 `latest.json` / 签名校验思路；**不上架** Store）

### P2 — Material 移动双端（Android + iOS）· **主路径已满足**

- **独立 Material 壳与页面**（不复用 Fluent 布局代码）
- 接入同一业务 core：对话 → 设置 → 生图 → 生视频
- Android：相册 + **侧载清单自动更新**（对齐现网 `android-latest.json`；不上架）
- iOS：相册 + 非 Store 分发策略（内测包 / 企业签等，**不上架**；无侧载商店文案）
- **验收**：能力对等；UI 可识别为 M3；iOS 与 Android 同属 Material 系统

### P3 — 双系统抛光 · **已落地**

- ~~设置导入导出、存储清理~~（已提前落地：`SET-DATA` / `DataBackupService`）
- ~~空态 / 短动效~~（部分落地：未配置 vs 无数据文案与 CTA 对齐；Tab 切换 / 空态出现 / 灯箱 / 会话列表短 fade·slide）
- ~~各系统主题、密度专项~~（部分落地：token 表面层级/`scrim`；InfoBar·Snackbar 吃 token；comfortable/compact 作用于会话行高、Composer 内边距、设置表单项间距；字号五档极端档 overflow 微调；空态 `illustration` 插槽）
- ~~空态插画~~（已落地：双端 `CustomPainter` 简易线稿，跟随 token 亮暗；覆盖未配置提供商 / 无消息·无生图·无视频 / 会话列表空 / 设置提供商列表空；不引入 `flutter_svg`）
- ~~无障碍与键盘可达~~（已落地：双端全路径 Semantics/tooltip/触控≥48/liveRegion/焦点；Windows debug 可关语义树；**WCAG 2.2 AA 自证，非第三方认证**）
- ~~**`SYS-SHARE`**：Material 图/视频系统分享入口（`share_plus`）~~（已落地）
- ~~**`NAV-BACK`**：Material `M-BackHost` 统一托管全屏层返回~~（已落地）
- ~~**`FB-UPDATE`**：对齐现网检查更新 UX——冷启动/托盘弹窗（跳过 / 稍后 / 下载并安装）、设置入口 NEW 角标、关于页自动检查开关与 changelog；`UpdatePrefs` 持久化~~（已落地；横幅组件保留可复用，启动路径改为弹窗）
- （可选）评估是否另开 Cupertino——默认不做

### 9.1 实现对照（2026-09-07 核对 §5；更新 UX 2026-09-09 再对齐）

| 范围                              | 结论                                                                                  |
|---------------------------------|-------------------------------------------------------------------------------------|
| §5.3–5.7 壳 / 对话 / 生图 / 生视频 / 设置 | 双端 ✅（含 `SHELL-BRAND-INTRO`；Material `NAV-BACK`：`BackHost` / `M-BackHost`）           |
| §5.8 反馈与系统力                     | ✅（含 Material `SYS-SHARE`）；`FB-UPDATE`：冷启动/托盘弹窗 + 设置 NEW 角标 + 关于页/自动检查开关；跳过版本与静默失败降噪 |
| 易漏项                             | 耗时自适应、用户末条撤回、回合时间分隔、IME 藏底栏、关闭嵌关于、三模型可搜索、托盘三态均已落地                                   |

---

## 10. 原型要求

原型必须 **双设计系统对照**，禁止只出一套再标注「移动适配」：

| 画板集      | 必含                                          |
|----------|---------------------------------------------|
| Fluent   | 对话（流式态）· 生图 · 生视频（回合分隔）· 设置五分类全页 · 同主题导航联动  |
| Material | 对话 · 会话列表层（亮+暗）· 生图 · 生视频 · 设置五 Tab · 返回层示例 |

标注清楚：两套 **独立** 组件与布局；共享的仅是能力与文案语义。组件规格分开写。

**色彩画板**：

| 画板    | 必须呈现                                    |
|-------|-----------------------------------------|
| Light | 暖奶油底、墨色字、珊瑚 CTA；至少 1 页对话 + 1 页设置        |
| Dark  | 近黑 IDE 底、冷蓝强调、低对比边框；至少 1 页对话 + 1 页生图/视频 |

禁止：亮色冷灰底、暗色暖棕底、两端混用同一 primary hue。

### 10.1 OpenDesign 原型清单（已落地）

| 项            | 约定                                                                                            |
|--------------|-----------------------------------------------------------------------------------------------|
| 项目 id        | `ai-studio-flutter-proto`                                                                     |
| 仓库副本         | `design/opendesign/`（同步到本机 OpenDesign data 目录）                                                |
| 发现流程         | **禁止** `collect_brief`；用 `skipDiscoveryBrief` + `start_run`                                   |
| 联动           | 同主题主导航互跳；外观「浅色/深色」跳对侧主题稿（**无跟随系统**）                                                           |
| 字体           | Fluent / Material **分栈**（§2.2.2）；均为系统字体，无 `@font-face`、无随仓字体文件                                |
| Logo         | 沿用现网 `AI_Studio/src-tauri/icons` → 本仓 `design/brand/`；原型用 `design/opendesign/assets/logo.png` |
| 滚动条          | 细条（约 6px）、无上下箭头、半透明滑块                                                                         |
| Fluent 设置页   | `fluent-{light\|dark}-settings-{providers\|chat\|appearance\|logs\|about}.html`               |
| Material 设置  | `material-{light\|dark}-settings.html`（五 Tab 单页）                                              |
| Material 会话层 | `material-{light\|dark}-sessions.html`                                                        |

---

## 11. 工程暗示（非强制实现栈，但约束选型）

独立设计系统下推荐：

```text
apps/desktop_fluent/     # Win + Mac 入口
apps/mobile_material/    # Android + iOS 入口
packages/core/           # 无 UI
packages/design_fluent/
packages/design_material/
```

- 现网 Vue + Naive **不适合**直接拆成两套独立系统；若坚持本策略，优先 **新仓库 + Flutter（或其它多端原生 UI）**。
- 继续 Tauri 扩 mac/iOS 时，最多做到「两端壳分叉」，难以达到本文「双设计系统」纯度，需在 Q1 明确降级。

---

## 12. 待决问题

| ID | 问题                                      | 状态 / 备注                                                                                             |
|----|-----------------------------------------|-----------------------------------------------------------------------------------------------------|
| Q1 | 实现栈：Flutter 新仓库 vs Tauri 扩平台？           | **已决：Flutter 新仓库** → `D:\Moon\tools\Ai_Studio_Flutter`                                              |
| Q2 | iOS / macOS 上架 Store 还是直链 / TestFlight？ | **已决：不上架**；延续现网 **直链 / 清单自动更新**（桌面 updater + Android 侧载清单；iOS 若分发则同属非 Store 策略，另定企业/TestFlight 仅内测） |
| Q3 | 移动设置 Tab 数量？                            | **已决：五 Tab**（提供商 / 对话 / 外观 / 日志 / 关于）；Fluent 为同序五分类侧栏                                               |
| Q4 | 多窗口桌面？                                  | 首期单窗口                                                                                               |
| Q5 | iOS 是否另做 Cupertino？                     | **已决：否，移动统一 Material**                                                                              |
| Q6 | macOS 是否坚持 Fluent 还是更接近 AppKit 气质？      | 默认仍归 Fluent 系统，控件按 Mac 惯例微调                                                                         |

---

## 13. 修订记录

| 日期         | 说明                                                                                                                                     |
|------------|----------------------------------------------------------------------------------------------------------------------------------------|
| 2026-09-04 | 初稿：四端、分端气质、桌面 MVP、双端对照原型                                                                                                               |
| 2026-09-04 | **独立设计系统**：Fluent ∪ Material；能力对等 UI 不对齐；iOS 跟 Material；禁止换皮冒充                                                                         |
| 2026-09-04 | 补齐 §5 双系统组件规格表（壳/对话/生图/生视频/设置/反馈）及现网映射、原型标注约定                                                                                          |
| 2026-09-04 | 色彩气质：**亮色仿 Claude**、**暗色仿 Cursor**；写入 token 起点与原型色板约束                                                                                  |
| 2026-09-04 | **已决**：Flutter → `D:\Moon\tools\Ai_Studio_Flutter`；不上架；直链/侧载自动更新；OpenDesign 跳过 collect_brief                                           |
| 2026-09-04 | 对齐原型审稿：设置五分类/五 Tab；日志必有；关闭行为并入关于；提供商三模型；字号五档；生图/视频回合分隔；OpenDesign 清单与联动约定                                                              |
| 2026-09-04 | **字体栈按设计系统拆分**（§2.2.2）：Fluent=Segoe 系；Material=Roboto/Noto；系统字体、不内嵌专有字库；原型 HTML 已分栈                                                    |
| 2026-09-04 | 提供商模型：拉取后 **可搜索下拉** 点选；输入=搜索过滤，对齐现网 `filterable` + `tag`                                                                               |
| 2026-09-04 | 主题：**仅浅色 / 深色**，去掉「跟随系统」                                                                                                               |
| 2026-09-04 | Logo：从现网 `src-tauri/icons` 拷入 `design/brand/`；原型标题栏改用 `assets/logo.png`；Windows `app_icon.ico` 已替换                                     |
| 2026-09-04 | 各端图标批量生成：Windows ICO · macOS AppIcon · iOS AppIcon（desktop+mobile）· Android mipmap（mobile+desktop scaffold）均基于 `design/brand/icon.png` |
| 2026-09-04 | 审稿修补：§2.1 分层图对齐 `design_*`/`apps/*`；端矩阵 iOS/Android 分发与「不上架」一致；文档状态标注关键已决；补 `docs/architecture.md` 与 `SECURITY.md` 占位                  |
| 2026-09-07 | **实现对照**：P0–P2 主路径已满足；`SYS-SHARE` 列入 P3；§9 标注分期状态并补 §9.1；文档状态更新                                                                        |
| 2026-09-07 | Material `SYS-SHARE`：`share_plus` + 生图/生视频分享入口落地；§5.8 / §9 / Changelog 同步                                                              |
| 2026-09-07 | P3 空态/动效部分落地：未配置 vs 无数据语义对齐；壳切换/灯箱/列表短动效；§9 标注                                                                                         |
| 2026-09-07 | P3 无障碍部分落地：主路径 Semantics/tooltip/焦点；Windows ExcludeSemantics 仅 debug；§7 备注                                                             |
| 2026-09-07 | P3 无障碍全路径自证：双端补语义/触控48/liveRegion/对比度 token；§7.1 自证清单；不宣称第三方认证                                                                         |
| 2026-09-07 | P3 主题/密度部分落地：`scrim`、InfoBar/Snackbar token、密度作用到会话/Composer/设置；空态 `illustration` 插槽                                                   |
| 2026-09-07 | P3 空态插画落地：双端 CustomPainter 简易线稿接入 `illustration`；§9 标注                                                                                 |
| 2026-09-08 | `VID-QUEUE`：双端任务队列增加按状态筛选（全部 / 生成中 / 待恢复 / 已完成 / 失败 / 已放弃）                                                                             |
| 2026-09-08 | Material 根页返回：`NAV-BACK` 增加「再按一次退出」确认（约 2s），确认后进最近任务、不清数据；键盘可见时优先收 IME                                                                 |
