//
//  BarkApi.swift
//  Bark
//
//  Created by huangfeng on 2018/6/25.
//  Copyright © 2018 Fin. All rights reserved.
//

import Moya
import UIKit

enum BarkApi {
    case ping(baseURL: String?)
    case register(address: String, key: String?, devicetoken: String) // 注册设备
    /// 上报送达回执给 Bark 服务端（设备已收到推送时调用）
    case pushDeliveryReport(deviceKey: String, deliveries: [[String: Any]])
}

extension BarkApi: BarkTargetType {
    var baseURL: URL {
        switch self {
        case let .ping(urlStr):
            if let url = URL(string: urlStr ?? "") {
                return url
            }
        case let .register(address, _, _):
            if let url = try? address.asURL() {
                return url
            }
        case .pushDeliveryReport:
            return try! ServerManager.shared.currentServer.address.asURL()
        }
        return try! ServerManager.shared.currentServer.address.asURL()
    }

    var parameters: [String: Any]? {
        switch self {
        case let .register(_, key, devicetoken):
            var params = ["devicetoken": devicetoken]
            if let key = key {
                params["key"] = key
            }
            return params
        case let .pushDeliveryReport(deviceKey, deliveries):
            return ["device_key": deviceKey, "deliveries": deliveries]
        default:
            return nil
        }
    }

    var path: String {
        switch self {
        case .ping:
            return "/ping"
        case .register:
            return "/register"
        case .pushDeliveryReport:
            return "/push/delivery"
        }
    }

    var method: Moya.Method {
        switch self {
        case .pushDeliveryReport:
            return .post
        default:
            return .get
        }
    }

    var parameterEncoding: ParameterEncoding {
        switch self {
        case .pushDeliveryReport:
            return JSONEncoding.default
        default:
            return URLEncoding.default
        }
    }
}
