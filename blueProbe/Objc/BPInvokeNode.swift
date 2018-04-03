//
//  BPInvokeNode.swift
//  blueProbe
//
//  Created by lining on 2018/4/3.
//  Copyright © 2018年 biubiublue. All rights reserved.
//

import Foundation

// MARK: - MethodInvoker

enum MethodInvoker {
    case name(String)    // 普通变量
    case method(BPInvokeNode) // 另一个方法调用
}

//extension MethodInvoker {
//    static func name(_ n: String) -> MethodInvoker {
//        return .name(n)
//    }
//
//    static func method(_ m: MethodInvokeNode) -> MethodInvoker {
//        return .method(m)
//    }
//}

// MARK: - InvokeParam

struct InvokeParam {
    var name: String // 参数的名称
    var invokes: [BPInvokeNode] // 包含在参数体中的方法调用，没有则为空
}

// MARK: - MethodInvokeNode

/// 方法调用
class BPInvokeNode: Node {
    var isSwift: Bool = false
    var invoker: MethodInvoker = .name("") // 该方法的调用者
    var methodName: String = "" // 只有解析swift用到这个属性
    var params: [InvokeParam] = [] // 参数, 只记录参数名称
}

extension BPInvokeNode {
    
    /// 找到最上层的调用者
    var topInvoker: BPInvokeNode {
        switch invoker {
        case .name(_):
            return self
        case .method(let invoke):
            return invoke.topInvoker
        }
    }
}

// MARK: - Helper

extension Array where Element == InvokeParam {
    func joinedText(separator: String) -> String {
        let texts = self.map { $0.name }
        return texts.joined(separator: separator)
    }
}

// MARK: - 数据格式化

extension BPInvokeNode: CustomStringConvertible {
    var description: String {
        if isSwift {
            return swiftDescription
        } else {
            return objcDescription
        }
    }
    
    /// 格式化成OC风格的表示
    var objcDescription: String {
        var method = "["
        
        switch invoker {
        case .method(let msg):
            method.append(contentsOf: "\(msg.objcDescription) ")
        case .name(let name):
            method.append(contentsOf: "\(name) ")
        }
        
        method.append(contentsOf: "\(params.joinedText(separator: " "))]")
        
        return method
    }
    
    /// 格式化成swift风格的表示
    var swiftDescription: String {
        var method = ""
        
        switch invoker {
        case .method(let invoke):
            method.append(contentsOf: "\(invoke.swiftDescription).")
        case .name(let name):
            if !name.isEmpty {
                method.append(contentsOf: "\(name).")
            }
        }
        
        let paramStr = params.join(go2String: { (param) -> String in
            return "\(param.name.isEmpty ? "_" : param.name):"
        }, separator: ", ")
        
        method.append(contentsOf: "\(methodName)(\(paramStr))")
        
        return method
    }
}

// MARK: - Hashable

extension BPInvokeNode: Hashable {
    
    static func ==(_ left: BPInvokeNode, _ right: BPInvokeNode) -> Bool {
        return left.hashValue == right.hashValue
    }
    
    /// 目前swift和oc之间不能判等
    var hashValue: Int {
        if isSwift {
            return swiftHashValue
        } else {
            return objcHashValue
        }
    }
    
    var objcHashValue: Int {
        return params.joinedText(separator: "").hashValue
    }
    
    var swiftHashValue: Int {
        let paramSign = params.join(go2String: { (param) -> String in
            return "\(param.name):"
        }, separator: ",")
        let methodSign = "\(methodName)\(paramSign)"
        
        return methodSign.hashValue
    }
}
