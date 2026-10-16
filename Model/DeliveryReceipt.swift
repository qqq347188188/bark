//
//  DeliveryReceipt.swift
//  Bark
//
//  推送“已送达”回执的本地存储模型（Realm）。
//  由主 App 从 App Group 共享目录读取回执 plist 后入库。
//  该文件位于 Model/，会被主 App 与扩展同时编译（扩展并不使用它，仅编译通过即可）。

import Foundation
import RealmSwift

class DeliveryReceipt: Object {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted(indexed: true) var pushId: String?
    @Persisted(indexed: true) var apnsId: String?
    @Persisted var title: String?
    @Persisted var body: String?
    @Persisted var group: String?
    @Persisted(indexed: true) var receivedAt: Date?
    /// 是否已成功上报给 Bark 服务端
    @Persisted var reported: Bool = false
    /// 服务端最近一次返回的状态（delivered / pending / sent / failed ...）
    @Persisted var serverStatus: String?
    @Persisted var serverUpdatedAt: Date?

    convenience init(dict: [String: Any]) {
        self.init()
        self.id = (dict["apnsId"] as? String) ?? UUID().uuidString
        self.pushId = dict["pushId"] as? String
        self.apnsId = dict["apnsId"] as? String
        self.title = dict["title"] as? String
        self.body = dict["body"] as? String
        self.group = dict["group"] as? String
        if let t = dict["receivedAt"] as? TimeInterval {
            self.receivedAt = Date(timeIntervalSince1970: t)
        }
    }
}
