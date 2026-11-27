// 表单编码的序列化：`encodeForm([(key, value), ...])` 产出 `key=value&...`（保持传入顺序）。
public func encodeForm(_ fields: [(String, String)]) -> String {
    fields
        .map { "\(Encoding.formUrlEncode($0.0))=\(Encoding.formUrlEncode($0.1))" }
        .joined(separator: "&")
}