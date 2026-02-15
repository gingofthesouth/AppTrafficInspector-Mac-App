//
//  KeyValue.swift
//  App Traffic Inspector
//

import Cocoa

class KeyValue: Codable {
    
    var key: String?
    var value: String?
    
    init(key: String?, value: String?) {
        self.key = key
        self.value = value
    }
}
