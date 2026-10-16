//
//  PushImageSettingManager.swift
//  Bark
//
//  推送图片相关设置。该文件同时被主 App 与 NotificationServiceExtension 编译，
//  通过 App Group（group.bark）的共享 UserDefaults 在两个进程间同步。

import Foundation

final class PushImageSettingManager {
    static let shared = PushImageSettingManager()
    private let defaults = UserDefaults(suiteName: "group.bark")

    /// 收到带图片的推送时，是否自动将图片保存到系统相册
    var autoSaveImageToAlbum: Bool {
        get { defaults?.value(forKey: "autoSaveImageToAlbum") as? Bool ?? false }
        set { defaults?.set(newValue, forKey: "autoSaveImageToAlbum") }
    }

    private init() {}
}
