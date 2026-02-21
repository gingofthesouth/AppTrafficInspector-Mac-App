//
//  BodyViewAsync.swift
//  
//
//  Created by Ernest Cunningham on 16/02/2026.
//

import SwiftUI
import AppKit

struct BodyViewAsync: View {
    let base64: String?
    @State private var result: BodyDisplayResult = .loading

    var body: some View {
        bodyContent
            .task(id: base64) {
                result = .loading
                guard base64 != nil else {
                    result = .empty
                    return
                }
                let resolved = await Task.detached(priority: .userInitiated) {
                    base64?.convertBase64ToPrettyJson() ?? .empty
                }.value
                result = resolved
            }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch result {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .json(let string):
            JSONTextView(text: string)
        case .plain(let string):
            ScrollView {
                Text(string)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
        case .binary(let count):
            ScrollView {
                Text("(binary data \(count) bytes)")
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
        case .empty:
            EmptyBodyView()
        }
    }
}

extension String {
    func convertBase64ToPrettyJson() -> BodyDisplayResult {
        guard let data = Data(base64Encoded: self, options: .ignoreUnknownCharacters) else {
            return .empty
        }
        
        if let obj = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let json = String(data: pretty, encoding: .utf8) {
            return .json(json.replacingOccurrences(of: "\\/", with: "/"))
        }
        
        if let str = String(data: data, encoding: .utf8) {
            return .plain(str)
        }
        
        return .binary(data.count)
    }
}
