//
//  BodyDisplayResult.swift
//  
//
//  Created by Ernest Cunningham on 16/02/2026.
//

import SwiftUI
import AppKit

enum BodyDisplayResult {
    case loading
    case json(String)
    case plain(String)
    case binary(Int)
    case empty
    
    func bodyDisplayResultToOverviewString() -> String {
        switch self {
        case .loading, .empty: return ""
        case .json(let s), .plain(let s): return s
        case .binary(let count): return "(binary data \(count) bytes)"
        }
    }
}
