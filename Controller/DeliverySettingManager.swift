//
//  DeliverySettingManager.swift
//  Bark
//
//  送达状态相关设置（主 App 使用，通过 App Group UserDefaults 与扩展共享开关位）。

import Foundation

final class DeliverySettingManager {
    static let shared = DeliverySettingManager()
    private let defaults = UserDefaults(suiteName: "group.bark")

    /// 是否将送达回执上报给 Bark 服务端（用于服务端侧的送达状态查询）
    var reportToServer: Bool {
        get { defaults?.value(forKey: "deliveryReportToServer") as? Bool ?? true }
        set { defaults?.set(newValue, forKey: "deliveryReportToServer") }
    }

    private init() {}
}
