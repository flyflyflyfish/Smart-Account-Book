# 智能记账助手（HarmonyOS ArkTS）

一款使用鸿蒙 ArkTS + ArkUI（Stage 模型）开发的个人记账应用：本地关系型数据库（RDB）存储，可选华为账号登录实现端云同步；支持图片/语音/AI 对话多种记账方式。

> 本项目基于开源项目 [account_app_harmonyos](https://github.com/banggx/account_app_harmonyos)（作者 banggx）二次开发，原始代码遵循 Apache License 2.0。来源与修改说明详见 [NOTICE](./NOTICE)。

## 功能特性

### 记账与统计

- 首页月度收支总览、当日收支卡片
- 手动记账：分类 / 金额 / 日期 / 支付时间 / 备注，账单编辑与批量管理
- 自定义分类：新增图标与配色的自定义分类、隐藏不用的默认分类、一键恢复默认
- 数据统计：月账单 / 年账单，按日或按分类视图，分类下钻明细
- 便捷记账：周期账单（每天 / 每周 / 每月），到点自动记入并通知，也支持一键添加
- 月度消费额度：自定义额度，超支弹窗与系统通知提醒
- 账单导出：Word（.docx）/ PDF / CSV（可回导本应用），支持本月 / 上月 / 近三月 / 本年，可预览与分享

### 智能识别

- 图片记账：拍照或选图，端侧 OCR + 自训练小模型本地识别金额、商家与支付时间，无需联网；结果可疑时自动回退云端大模型（需配置）
- 云端大模型识别：多服务商配置（接口地址 / API Key / 视觉模型），可测试连通性
- AI 助手：对话式记账与消费分析，支持语音输入
- 识别流水线：金额归一化 → 重复检测（疑似重复提示）→ 分类（学习分类器 + 规则分类器）→ 校验
- 商家→分类学习记忆：同商家下次优先命中上次确认的分类
- 训练数据采集（开发期工具，仅 main 分支）：识别过程可并行采集端侧样本（仅存本机，不上传），用于迭代训练端侧模型；发行分支（release）已剥离

### 数据与同步

- 华为账号登录（AGC 认证服务），账单与账本端云同步（AGC 云数据库）：
  - 账单按主键双向合并，`create_time` 新者胜，换机重装不丢数据
  - 账本与账本记录按 `updated_at` 新者胜双向合并
  - 设置与自定义分类全量同步，分类配置并集合并（双方新增都保留）
  - 删除墓碑（tombstone）机制防止已删账单/账本在其他设备"复活"
  - 商家→分类学习记忆同步，识别习惯跨设备保留
- API Key 等敏感配置仅存本机，不上云
- 不登录时全部本地功能可正常使用

### 个性化

- 外观：7 套主题配色（松绿 / 暖橘 / 清爽蓝 / 雅紫 / 极简灰 / 曜石灰 + 自定义主题）、深浅色模式、字体大小、光感调节
- 桌面小部件：2×2 / 2×4 双布局，今日收支、本月口径与快捷记账入口，跟随主题配色

## 技术栈

- 纯 ArkTS + ArkUI，Stage 模型，无 C++ / JS / 跨端框架
- 数据：关系型数据库（RDB）+ Preferences
- 云端：AppGallery Connect（认证服务 + 云数据库，`@hw-agconnect/auth`）
- 依赖：dayjs

## 运行环境

- DevEco Studio 5.0 及以上
- HarmonyOS SDK：compatibleSdkVersion 5.0.0(12)，targetSdkVersion 26
- 真机或模拟器（云同步需真机华为账号环境）

## 快速开始

1. 使用 DevEco Studio 打开本目录，等待 `oh_modules` 自动同步。
2. 配置自动签名：**File → Project Structure → Signing Configs → 勾选 "Automatically generate signature"**。
3. 连接设备，点击 Run。不配置云同步也能正常使用全部本地功能。

### 云同步配置（可选）

1. 在 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/joss/agc/index.html) 创建项目并开通「认证服务」（华为账号）与「云数据库」。
2. 下载 `agconnect-services.json` 放入 `AppScope/resources/rawfile/` 目录。
3. 云数据库控制台创建存储区与对象类型，字段需与 `AppScope/resources/rawfile/schema.json` 一致（`user_setting` / `account` / `bill_tombstone`）。
4. 在 AGC 控制台修改云数据库结构后，注意同步更新本地 `schema.json` 的 `schemaVersion` 为控制台显示的版本号，否则会报"object type is not found"。

## 测试

单元测试位于 `entry/src/ohosTest/ets/test/`，覆盖识别流水线各步骤（归一化、分类、去重、校验）、分类器、云端结果解析、识别器装饰器与统计服务，共 10 个测试文件。

在 DevEco Studio 中：连接设备或启动模拟器 → 右键 `entry/src/ohosTest` → **Run 'entry ohosTest'**。

资源一致性检查（无需设备，CI 亦会执行）：

```bash
node scripts/check_strings.mjs
```

校验资源 JSON 语法，保证 zh_CN / en_US 不含无效 key，并检查代码中引用的 `$r('app.string.*')` 均有定义。

## 持续集成

GitHub Actions 工作流（`.github/workflows/ci.yml`）在 push / PR 时自动执行资源一致性检查，配合 DevEco Studio 的 ArkTS 静态检查（`codelinter` / 编译期检查）保证内部质量。

## 分支策略

| 分支        | 用途                                           |
| ----------- | ---------------------------------------------- |
| `main`     | 开发主线，包含训练数据采集等开发期工具功能     |
| `release`  | 发行分支，剥离开发期工具，面向最终用户（推荐体验） |
| `feat/*`   | 功能开发分支，完成后合回 `main`                |

发行流程：`main` 功能稳定后挑选用户可见特性入 `release`，打 tag 发布。

## 团队与分工

本项目由 2 人按**两条纵向条线**协作完成，每人对一条线端到端负责；模块级归属见 [`.github/CODEOWNERS`](./.github/CODEOWNERS)，git 度量证据见 [工作量分配与 KPI](./docs/工作量分配与KPI.md)。

| 成员 | 主责条线 | 覆盖范围 | GitHub |
| ---- | -------- | -------- | ------ |
| 潘妍朵 | 智能识别与云能力<br>（技术主线） | 端侧模型与识别流水线、云端大模型接入、AGC 端云同步、云端 schema 版本迁移、账单文件解析与导出、CI 与工程脚本 | [@flyflyflyfish](https://github.com/flyflyflyfish) |
| 伍翰彬 | 产品体验与数据<br>（界面主线） | 全部页面级实现（首页 / 记账 / 详情 / 统计 / 账本 / 预算 / 周期账单 / 搜索 / 设置 / 识别确认页）、本地数据层（RDB 仓储 `LedgerRepository` / `RdbAccountRepository` / `MerchantCategoryRepository`、表结构与版本迁移、账本 / 周期账单 / 分类存储等模型）、桌面小部件（2×2 / 2×4 双布局、卡片视觉、快捷入口、双击进首页）、六套主题与自定义主题编辑器、跨进程主题一致性、真机验收与演示 | [@wuhanbinnnnnn](https://github.com/wuhanbinnnnnn) |

页面实现与数据层由伍翰彬主责、潘妍朵评审；识别与云能力由潘妍朵主责、伍翰彬负责页面对接与本地数据落地。联调与上架合规材料由两人共同承担。协作方式：功能在 `feat/*` 分支开发 → 发起 PR 并请求对应模块负责人评审 → 合入 `main`；剩余工作以 issue 跟踪与认领。

## 文档

- [用户手册](./docs/用户手册.md)：功能使用说明
- [设计与重构报告](./docs/设计与重构报告.md)：重构前后系统对比、UML、设计模式与量化增益
- [量化实验报告](./docs/量化实验报告.md)：识别模型实验数据、指标与环境参数
- [工作量分配与 KPI](./docs/工作量分配与KPI.md)：团队分工与 git 度量证据
- [安全设计](./docs/安全设计.md)：隐私与信息安全设计说明
- [贡献指南](./CONTRIBUTING.md)：提交规范、代码风格、协作流程

## 目录结构

```
account_app_harmonyos
├── AppScope/
│   └── resources/rawfile/schema.json   # 云数据库对象类型定义
├── entry/src/main/
│   ├── ets/
│   │   ├── entryability/               # EntryAbility 入口
│   │   ├── widget/                     # 桌面小部件（EntryFormAbility）
│   │   ├── pages/                      # 页面（登录、识别、导出、预算、周期账单、外观等）
│   │   ├── views/                      # 页面视图（home、stats、settings、aiAssistant）
│   │   ├── components/                 # 通用组件与统计图表
│   │   ├── models/                     # 数据模型（账单、分类、识别、云端模型）
│   │   ├── data/                       # RDB / 云数据库仓储
│   │   ├── service/                    # 业务逻辑（同步、识别、导出、预算、周期账单）
│   │   │   └── recognition/            # 识别流水线、分类器、端侧模型、装饰器
│   │   ├── utils/                      # 工具类（DB、Preferences、Logger 等）
│   │   └── common/                     # 常量、主题、断点配置
│   ├── ohosTest/                       # 单元测试（识别流水线、分类器、解析、统计）
│   └── resources/                      # 资源文件
├── scripts/check_strings.mjs           # 三语言资源一致性检查（CI 执行）
├── .github/workflows/ci.yml            # GitHub Actions 持续集成
├── docs/                               # 用户手册、设计报告、实验报告、KPI、安全设计
├── NOTICE                              # 来源与修改声明
├── THIRD_PARTY.md                      # 第三方依赖许可
├── LICENSE                             # PolyForm Noncommercial 1.0.0（修改与新增部分）
├── LICENSE-Apache-2.0                  # Apache License 2.0（上游原始代码）
└── README.md
```

## 许可证

本项目采用双许可结构，详见 [NOTICE](./NOTICE)：

- **修改与新增部分**：[PolyForm Noncommercial License 1.0.0](./LICENSE) —— 仅限非商业目的使用、修改与分发；商业使用需联系开发者取得授权（3855757949@qq.com）
- **上游原始代码**：[Apache License 2.0](./LICENSE-Apache-2.0)，版权归原作者 banggx 所有

本项目基于开源项目 [account_app_harmonyos](https://github.com/banggx/account_app_harmonyos) 二次开发。
