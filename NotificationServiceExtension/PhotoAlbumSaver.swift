//
//  PhotoAlbumSaver.swift
//  NotificationServiceExtension
//
//  将推送图片保存到系统相册。
//
//  越狱 / TrollStore 环境说明：
//  TrollStore 安装的应用会以特殊身份运行，TCC 隐私授权被绕过，因此 PHPhotoLibrary
//  可以直接写入相册，无需弹窗、也无需在扩展进程里申请权限。
//  对于少数 PHPhotoLibrary 因故不可用（如非越狱且未授权）的场景，提供越狱文件系统
//  回退：把图片直接写入 DCIM 目录并通知相册重新扫描（best-effort）。

import Darwin
import Foundation
import Photos

struct PhotoAlbumSaver {
    /// 保存图片二进制数据到系统相册，返回是否成功
    /// - Parameters:
    ///   - imageData: 图片原始数据
    ///   - fileNameHint: 临时文件名前缀
    static func save(imageData: Data, fileNameHint: String = "bark_image") async -> Bool {
        let ext = Self.imageExtension(for: imageData)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileNameHint)_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString).\(ext)")
        do {
            try imageData.write(to: tmpURL)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // 优先走 PHPhotoLibrary（越狱 / TrollStore 下直接可用）
        if await saveViaPhotoLibrary(fileURL: tmpURL) {
            return true
        }
        if await saveViaPhotoLibraryUIImage(data: imageData) {
            return true
        }
        // 越狱文件系统回退：直接写 DCIM 并触发重新扫描
        return saveViaDCIMFallback(fileURL: tmpURL, ext: ext)
    }

    private static let barkAlbumTitle = "Bark"

    /// 将图片写入系统相册，并归入名为 "Bark" 的相簿（相簿不存在则创建）。
    /// 注：iOS 的“相簿”是引用集合，图片仍会同时存在于相机胶卷/最近项目，这是系统正常行为。
    private static func saveImageToBarkAlbum(_ image: UIImage) async -> Bool {
        // 先读取是否已存在同名相簿（只读，放在 performChanges 之外）
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var existingAlbum: PHAssetCollection?
        fetch.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == Self.barkAlbumTitle {
                existingAlbum = collection
                stop.pointee = true
            }
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetChangeRequest.creationRequestForAsset(from: image)
                guard let placeholder = creation.placeholderForCreatedAsset else { return }
                if let existingAlbum,
                   let albumRequest = PHAssetCollectionChangeRequest(for: existingAlbum) {
                    albumRequest.addAssets([placeholder] as NSArray)
                } else {
                    let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: Self.barkAlbumTitle)
                    albumRequest.addAssets([placeholder] as NSArray)
                }
            } completionHandler: { success, error in
                if let error {
                    print("[PhotoAlbumSaver] 写入 Bark 相簿失败: \(error.localizedDescription)")
                }
                continuation.resume(returning: success)
            }
        }
    }

    private static func saveViaPhotoLibrary(fileURL: URL) async -> Bool {
        guard let image = UIImage(contentsOfFile: fileURL.path) else { return false }
        return await saveImageToBarkAlbum(image)
    }

    private static func saveViaPhotoLibraryUIImage(data: Data) async -> Bool {
        guard let image = UIImage(data: data) else { return false }
        return await saveImageToBarkAlbum(image)
    }

    /// 越狱文件系统回退：直接写入 DCIM 并通知相册重新扫描
    private static func saveViaDCIMFallback(fileURL: URL, ext: String) -> Bool {
        guard isJailbroken() else { return false }
        let dcimDir = URL(fileURLWithPath: "/var/mobile/Media/DCIM/100APPLE")
        try? FileManager.default.createDirectory(at: dcimDir, withIntermediateDirectories: true)
        let existing = (try? FileManager.default.contentsOfDirectory(at: dcimDir, includingPropertiesForKeys: nil)) ?? []
        var index = max(existing.count, 1) + 1
        var dest: URL
        repeat {
            dest = dcimDir.appendingPathComponent(String(format: "IMG_%04d.%@", index, ext.uppercased()))
            index += 1
        } while FileManager.default.fileExists(atPath: dest.path)
        guard (try? FileManager.default.copyItem(at: fileURL, to: dest)) != nil else { return false }
        // 通知系统相册重新扫描 DCIM 目录（与 NotificationService.swift 一致，使用 CoreFoundation 通知，无需 notify.h）
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.apple.mobileslideshow.databaseschanged" as CFString),
            nil,
            nil,
            true
        )
        return true
    }

    private static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let indicators = ["/var/jb", "/Applications/Cydia.app", "/Library/MobileSubstrate", "/usr/bin/ssh"]
        return indicators.contains { FileManager.default.fileExists(atPath: $0) }
        #endif
    }

    /// 根据文件头魔数推断图片扩展名
    private static func imageExtension(for data: Data) -> String {
        guard data.count >= 4 else { return "png" }
        let b = Array(data.prefix(4))
        if b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return "png" }
        if b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF { return "jpg" }
        if b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 { return "gif" }
        if b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x00 { return "heic" }
        return "png"
    }
}
