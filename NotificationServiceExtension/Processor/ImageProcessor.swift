//
//  ImageProcessor.swift
//  NotificationServiceExtension
//
//  Created by huangfeng on 2024/5/29.
//  Copyright © 2024 Fin. All rights reserved.
//

import Foundation
import MobileCoreServices

class ImageProcessor: NotificationContentProcessor {
    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        let userInfo = bestAttemptContent.userInfo
        guard let imageUrl = userInfo["image"] as? String,
              let imageFileUrl = await ImageDownloader.downloadImage(imageUrl)
        else {
            return bestAttemptContent
        }
        
        let copyDestUrl = URL(fileURLWithPath: imageFileUrl).appendingPathExtension(".tmp")
        // 将图片缓存复制一份，推送使用完后会自动删除，但图片缓存需要留着以后在历史记录里查看
        try? FileManager.default.copyItem(
            at: URL(fileURLWithPath: imageFileUrl),
            to: copyDestUrl
        )
        
        if let attachment = try? UNNotificationAttachment(
            identifier: "image",
            url: copyDestUrl,
            options: [UNNotificationAttachmentOptionsTypeHintKey: kUTTypePNG]
        ) {
            bestAttemptContent.attachments = [attachment]
        }

        // 功能1：收到带图片的推送时，自动将图片保存到系统相册（越狱 / TrollStore 环境）
        // 使用后台任务非阻塞保存：避免在扩展进程里等待相册写入（PHPhotoLibrary 在扩展中
        // 可能等待授权/卡顿）而阻塞整条通知处理，导致推送“失败”。通知会先被投递，
        // 保存随后在后台完成（TrollStore/越狱环境下 PHPhotoLibrary 通常很快返回）。
        if PushImageSettingManager.shared.autoSaveImageToAlbum,
           let data = try? Data(contentsOf: URL(fileURLWithPath: imageFileUrl))
        {
            Task.detached(priority: .background) {
                _ = await PhotoAlbumSaver.save(imageData: data, fileNameHint: "bark_image")
            }
        }
        return bestAttemptContent
    }
}
