# 越狱环境（iOS 16.6 + TrollStore）构建与运行说明

本分支在官方 Bark 基础上扩展了两个面向越狱 / TrollStore 设备的能力：

1. **图片推送自动保存相册**：收到带 `image` 的推送时，自动把图片保存到系统相册。
2. **推送送达状态验证 API**：记录设备端“已送达”回执，并支持按 `pushid` / 时间戳查询。

目标平台：**已越狱的 iOS 16.6** + **TrollStore** 安装。无需 Apple 开发者证书。

---

## 1. 构建方式（GitHub Actions 零证书）

仓库已包含 `.github/workflows/trollstore.yaml`：

- 在 macOS runner 上执行 `pod install`；
- 运行 `ruby scripts/setup_xcodeproj.rb`：
  - 把新增的源文件加入对应 target；
  - 为 `NotificationServiceExtension` 链接系统 `Photos.framework`（自动保存相册必需）。
- `xcodebuild` 关闭签名（`CODE_SIGNING_ALLOWED=NO`）；
- 用系统 `codesign -` 做 ad-hoc 签名并嵌入 `Bark/Bark.entitlements` 与
  `NotificationServiceExtension/NotificationServiceExtension.entitlements`；
- 打包为 `Bark-TrollStore.ipa` 并作为构建产物上传。

手动触发：仓库 **Actions → Build TrollStore IPA → Run workflow**，或打 `v*` tag 自动触发。

---

## 2. 权限与越狱适配要点

- **相册写入**：`NotificationServiceExtension/Info.plist` 已加入
  `NSPhotoLibraryAddUsageDescription`。在 TrollStore 下，TCC 隐私授权被绕过，
  `PHPhotoLibrary` 可直接写入，无需弹窗、也无需在扩展中申请权限。
- **文件系统回退**：若 `PHPhotoLibrary` 因故不可用（极少数非越狱场景），
  `NotificationServiceExtension/PhotoAlbumSaver.swift` 会回退到越狱文件系统方案：
  直接把图片写入 `/var/mobile/Media/DCIM/100APPLE/IMG_xxxx.<ext>` 并发送
  `com.apple.mobileslideshow.databaseschanged` 通知触发相册重新扫描（best-effort）。
- **推送权限**：`Bark.entitlements` 中的 `aps-environment` 需与目标 bark-server 使用的
  APNs 环境（development / production）一致；TrollStore 会保留嵌入的 entitlements。

---

## 3. 功能使用

### 3.1 自动保存图片到相册

- 设置入口：首页「设置」卡片 → 「送达状态查询」→ 顶部开关
  「收到图片自动保存到相册」（对应 `PushImageSettingManager.autoSaveImageToAlbum`）。
- 开启后，任何带图片的推送在被设备接收时都会自动存入相册，无需手动操作。

### 3.2 送达状态查询

- 首页「设置」卡片 → 「送达状态查询」：
  - 输入 `pushid`（建议服务端在 APNs 载荷中携带，见 `docs/delivery-api.md`）；
  - 或输入秒级时间戳（±30s 范围匹配本地记录）；
  - 点击「查询送达状态」，结果展示本地（设备已收到）与服务端（bark-server 侧）状态。

### 3.3 与服务端联调

- 若你的 bark-server 已实现 `docs/delivery-api.md` 中的 `/push/delivery`
  上报 / 查询接口，客户端会自动上报回执，并在查询时融合服务端状态。
- 若服务端未实现，本地“已送达”记录与查询仍可正常工作，仅缺少“待发送 / 失败”等
  服务端侧状态。

---

## 4. 注意事项

- 本构建产物通过 TrollStore 永久安装，绕过 App Store 签名体系；仅用于自用 / 测试。
- 扩展进程受 30s 时限约束，图片下载 + 保存均在此窗口内完成，通常不会影响通知及时展示。
- `Photos.framework` 必须在 `NotificationServiceExtension` target 中链接，否则
  `PhotoAlbumSaver` 无法编译（CI 脚本已自动处理）。
