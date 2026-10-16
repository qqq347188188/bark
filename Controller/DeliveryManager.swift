//
//  DeliveryManager.swift
//  Bark
//
//  将本地未上报的送达回执上报给服务端。
//

import Foundation
import Moya
import RealmSwift
import RxSwift

final class DeliveryManager {
    static let shared = DeliveryManager()
    private let disposeBag = DisposeBag()
    /// 专用串行队列执行 Realm 写入，彻底避免跨线程访问 Realm。
    private let realmWriteQueue = DispatchQueue(label: "com.bark.delivery.write")
    private init() {}

    /// 将本地未上报的送达回执上报给服务端
    func reportPendingDeliveries() {
        guard DeliverySettingManager.shared.reportToServer else { return }
        guard let realm = try? Realm() else { return }
        let pending = realm.objects(DeliveryReceipt.self).filter("reported == false")
        guard !pending.isEmpty else { return }

        // 在当前线程提取上报内容（primitive），避免跨线程持有 Realm 对象
        let deliveries: [[String: Any]] = pending.map { r in
            var d: [String: Any] = [:]
            if let pushId = r.pushId { d["pushid"] = pushId }
            if let apnsId = r.apnsId { d["apnsid"] = apnsId }
            if let receivedAt = r.receivedAt { d["received_at"] = Int(receivedAt.timeIntervalSince1970) }
            d["status"] = "delivered"
            return d
        }

        let key = ServerManager.shared.currentServer.key
        let target = BarkApi.pushDeliveryReport(deviceKey: key, deliveries: deliveries)
        BarkApi.provider.request(target)
            .subscribe(onNext: { [weak self] _ in
                // 网络回调线程不确定，统一切到专用串行队列，并在该队列上“重新打开 Realm、
                // 重新查询”后再写入，绝不跨线程持有/枚举任何 Realm 对象或集合。
                self?.realmWriteQueue.async {
                    do {
                        let r = try Realm()
                        let toReport = r.objects(DeliveryReceipt.self).filter("reported == false")
                        try r.write {
                            for obj in toReport {
                                obj.reported = true
                            }
                        }
                    } catch {
                        // 上报已成功，本地标记失败则下次启动会再次上报（接口幂等），不影响主流程
                    }
                }
            }, onError: { _ in
                // 上报失败保留未上报状态，下次再试
            })
            .disposed(by: disposeBag)
    }
}
