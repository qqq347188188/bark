//
//  DeliveryProcessor.swift
//  NotificationServiceExtension
//
//  记录“推送已送达”回执：在通知被设备接收时，将一条回执写入 App Group 共享目录，
//  由主 App 读取后存入 Realm，并可（可选）上报给 Bark 服务端用于送达状态查询。
//
//  该 processor 设计为“永不抛出”，放在 ciphertext 之后、其余 processor 之前，
//  以保证即便后续 processor 处理失败，送达回执也已经被记录。

import Foundation

class DeliveryProcessor: NotificationContentProcessor {
    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        let userInfo = bestAttemptContent.userInfo

        // 优先使用服务端下发的推送ID；缺失时回退到系统分配的 APNs 请求ID
        let pushId = (userInfo["pushid"] as? String)?.nilIfEmpty
            ?? (userInfo["id"] as? String)?.nilIfEmpty
            ?? identifier
        let apnsId = identifier

        let alert = (userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any]
        let title = (alert?["title"] as? String) ?? (userInfo["title"] as? String)
        let body = (alert?["body"] as? String) ?? (userInfo["body"] as? String)
        let group = userInfo["group"] as? String

        var dict: [String: Any] = [
            "pushId": pushId,
            "apnsId": apnsId,
            "receivedAt": Date().timeIntervalSince1970
        ]
        if let title { dict["title"] = title }
        if let body { dict["body"] = body }
        if let group { dict["group"] = group }

        if let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.bark") {
            let dir = groupUrl.appendingPathComponent("push_delivery")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safeName: String
            if let data = apnsId.data(using: .utf8) {
                safeName = data.map { String(format: "%02x", $0) }.joined()
            } else {
                safeName = UUID().uuidString
            }
            (dict as NSDictionary).write(to: dir.appendingPathComponent("\(safeName).plist"), atomically: true)
        }
        return bestAttemptContent
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
