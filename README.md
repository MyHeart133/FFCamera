# FFCamera

端侧 **AI 构图 + 电影感滤镜** 相机(iOS · 自用)。功能对标 Doka Cam,实现全自研:
**无服务器、无账号、无内购、无第三方 SDK** —— AI 与图像处理全部在设备本地完成。

## 状态

- [x] **M0** 仓库骨架 + GitHub Actions 自动构建(未签名 IPA)
- [ ] **M1** 相机核心:取景 / 比例 / 变焦 / 水平仪 / 拍摄
- [x] **M2** 滤镜引擎:24 LUT + 强度 + 实时预览
- [ ] **M3** AI 构图与滤镜推荐(Vision / Core ML,端侧)
- [ ] **M4** 编辑器:裁剪 / 边框 / 水印
- [ ] **M5** 相册 / 设置 / 更新检查(GitHub Releases)
- [ ] **M6** 引导 / 动效 / 中英本地化 / 性能
- [ ] **M7** 打磨与发布

## 构建与安装

1. 推送到 GitHub 后,`Actions → iOS` 自动构建,产物为 Artifact `FFCamera-unsigned-ipa`
2. 打 tag 自动发 Release:`git tag v0.1.0 && git push --tags`
3. 用 **全能签 / AltStore / Sideloadly** 对未签名 IPA 签名安装

## 本地开发(macOS)

```bash
brew install xcodegen
xcodegen generate
open FFCamera.xcodeproj
```

- 最低 iOS 17.0(Xcode 16+ / 26 均可构建)
- 工程文件由 `project.yml` 生成,**不要手改 `.xcodeproj`**

## 目录结构

```
FFCamera/
├── project.yml                    # XcodeGen 工程定义
├── FFCamera/
│   ├── App/                       # 入口 + 根视图
│   ├── Core/                      # 应用信息 / 日志
│   ├── Filters/                   # LUT 引擎(解析器 + 滤镜目录)
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── LUTs/                  # 24 个 33³ .cube(由 tools/gen_luts.py 生成)
│   │   └── PrivacyInfo.xcprivacy
│   └── ...
├── FFCameraTests/                 # 单元测试(LUT 解析 / 滤镜目录)
├── tools/gen_luts.py              # LUT 生成器(纯标准库,可复现)
└── .github/workflows/ios.yml      # 构建 / 测试 / 发布流水线
```

## 里程碑规划

见 [`docs/PLAN.md`](docs/PLAN.md)。
