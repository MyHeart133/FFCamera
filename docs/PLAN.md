# FFCamera 开发计划

> 产品:FFCamera(iOS,自用)
> 目标:功能对标 Doka Cam;全端侧实现;GitHub Actions 自动构建;未签名 IPA 交付全能签安装。
> 技术决策已定:最低 iOS 17(设备 iOS 26.6 直接运行) · 无内购 · 无服务器 · 无第三方 SDK。

## 功能对标(逆向结论 → iOS 实现)

| # | Doka 功能 | FFCamera 实现 | 里程碑 |
|---|---|---|---|
| 1 | 相机主界面:比例、变焦、水平仪、遮罩、滤镜条 | AVFoundation + SwiftUI 自绘控件 | M1 |
| 2 | 24 滤镜(5 组)+ 强度 | 自研 24 LUT(CIColorCube),预览/拍照/编辑一致 | M2 |
| 3 | AI 构图:主体框、引导、自动裁剪 | Vision 前景分割 → 构图算法 → 引导 UI → 全分辨率裁剪 | M3 |
| 4 | AI 滤镜推荐(名称 + 理由) | VNClassifyImageRequest + 色彩统计 → 映射表 | M3 |
| 5 | 拍照 / 保存 | AVCapturePhotoOutput + 管线烘焙 | M1/M3 |
| 6 | 编辑器:裁剪(比例集)、旋转 | SwiftUI 裁剪器 | M4 |
| 7 | 照片边框 / 水印 | Core Graphics 合成 | M4 |
| 8 | 相册:分组 / 多选删除 / 预览 / 分享 | PHPhotoLibrary 自定义相册 | M5 |
| 9 | 设置 / 关于 / 协议 | SwiftUI 页面 | M5 |
| 10 | 版本更新检查 | GitHub Releases API 对比 | M5 |
| 11 | 开屏 / 引导动效 | 原生 SwiftUI 动画 | M6 |
| — | 账号 / 支付 / 风控 | 不做(自用) | — |

## 端侧 AI 方案

- **主体检测**:VNGenerateForegroundInstanceMaskRequest(iOS 17+)/ 人像分割降级 / 显著性框兜底;540p @ ~15fps 节流分析
- **构图算法**:主体 bbox → 就近三分线目标框 → 引导环 + 移动箭头 + 稳定提示;拍照时全分辨率按归一化框裁剪
- **滤镜推荐**:场景分类标签 + 色彩统计(亮度/色温/饱和度)→ 映射表 → Top2 + 本地生成的推荐理由
- **性能预算**:单次构图分析 < 120ms(A15+),AI 可一键关闭

## 里程碑

| 里程碑 | 内容 | 验收 |
|---|---|---|
| M0 | 仓库骨架 + CI 出 IPA | Actions 绿,Artifact 可下载 |
| M1 | 相机核心 | 真机取景拍摄完整 |
| M2 | 滤镜引擎 + 24 LUT | 实时预览、拍照烘焙一致 |
| M3 | AI 构图 + 推荐 | 主体框稳定,自动裁剪可出片 |
| M4 | 编辑器 | 全分辨率合成输出 |
| M5 | 相册 / 设置 / 更新 | 完整可用 |
| M6 | 引导 / 本地化 / 性能 | 冷启动 < 1.5s |
| M7 | 打磨与发布 | Release 附 IPA |

## CI / 分发

- `macos-26` runner → XcodeGen → `xcodebuild`(未签名)→ `FFCamera-unsigned.ipa` Artifact
- tag `v*` → 自动挂 Release;App 内更新检查读取 Releases
- 安装:全能签 / AltStore / Sideloadly

## 合规与边界

- 品牌、LUT、UI 素材全部原创(避免商标与版权问题)
- 不复制 Doka 的代码、资产、接口;实现以本文档为规格从零编写
