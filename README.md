# 记账助手（鸿蒙 ArkTS 版）

使用鸿蒙 ArkTS + ArkUI 的 Stage 模型开发实现的记账助手 App。数据使用鸿蒙本地关系型数据库（RDB）独立存储，不依赖服务端。

> 本项目基于开源项目 [account_app_harmonyos](https://github.com/banggx)（作者 banggx）二次开发，原始代码遵循 Apache License 2.0。来源与修改说明详见 [NOTICE](./NOTICE)。

<div align="center">
<img src="./preview.gif" width="390px" />
</div>

## 功能列表

- 首页：当月记账数据总览
- 添加记账：收入/支出分类录入
- 数据统计：按月统计收支情况

> 新增功能（图片识别记账等）将随后续阶段补充。

## 运行环境

- DevEco Studio 4.0 及以上
- HarmonyOS SDK（API 10 及以上）
- 纯 ArkTS + ArkUI，Stage 模型，无 C++ / JS / 跨端框架

## 运行步骤

1. 使用 DevEco Studio 打开本目录。
2. 等待依赖安装完成（`oh_modules` 自动同步）。
3. 配置自动签名（首次运行需在 DevEco Studio 中生成调试证书，见下方说明）。
4. 连接真机或启动模拟器，点击 Run 运行。

> 签名说明：本仓库不包含任何签名配置。首次构建前请在 DevEco Studio 中执行：
> **File → Project Structure → Signing Configs → 勾选 "Automatically generate signature"**，
> 由 IDE 在本机自动生成调试证书。生成的签名信息位于 `build-profile.json5`，
> 该文件已通过 `.gitignore` 忽略签名产物，请勿将个人证书路径或密码提交到仓库。

## 目录结构

```
account_app_harmonyos
├── AppScope/                    # 应用级配置
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/    # EntryAbility 入口
│       │   ├── pages/           # 页面（Index、AddAccount、AccountDetail）
│       │   ├── views/           # 页面视图（home、stats）
│       │   ├── components/      # 通用组件
│       │   ├── models/          # 数据模型（account、accountType、stats）
│       │   ├── service/         # 业务逻辑
│       │   ├── utils/           # 工具类（DB、Preferences、Logger 等）
│       │   └── common/          # 常量与断点配置
│       └── resources/           # 资源文件
├── build-profile.json5          # 构建配置（不含签名）
├── oh-package.json5             # 依赖配置
├── NOTICE                       # 来源与修改声明
├── THIRD_PARTY.md               # 第三方依赖许可
├── LICENSE                      # Apache License 2.0
└── README.md
```

## 联系与致谢

本项目为作者（banggx）首个自学 HarmonyOS 开发项目，原始仓库存在不完善之处，欢迎提交 Issue 反馈。

> ![](https://open.weixin.qq.com/zh_CN/htmledition/res/assets/res-design-download/icon16_wx_logo.png) *banggx*（添加请备注 account_app_harmonyos）

## 许可证

本项目遵循 [Apache License 2.0](./LICENSE)。上游代码版权归原作者 banggx 所有。
