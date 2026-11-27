// App 层的网络注入：音质采样率探测要读 fMP4 **原始字节**。
//
// Core 的 `URLSessionFetcher` 既能给文本也能给字节，这里只是把「字节」这件事显式接到 App 的启动流程
// （宿主端口注入见 `HostPorts`——原生端没有服务端，网络、设备身份都在应用启动时装进 Core）。
import Foundation
import PterosaurCore

struct ByteTransport: BinaryFetcher {
    func fetch(_ url: String, _ req: FetchRequest) -> FetchResult {
        let (status, data, cookies) = send(url, req)
        return FetchResult(status: status, body: data.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                           setCookies: cookies)
    }

    func fetchBytes(_ url: String, _ req: FetchRequest) -> [UInt8]? {
        let (status, data, _) = send(url, req)
        guard (200..<300).contains(status), let data else { return nil }
        return [UInt8](data)
    }

    private final class Box: @unchecked Sendable {
        var value: (Int, Data?, [String]) = (0, nil, [])
    }

    private func send(_ url: String, _ req: FetchRequest) -> (Int, Data?, [String]) {
        guard let u = URL(string: url) else { return (0, nil, []) }
        var r = URLRequest(url: u)
        r.httpMethod = req.method
        r.timeoutInterval = Double(req.timeoutMs) / 1000
        for (k, v) in req.headers { r.setValue(v, forHTTPHeaderField: k) }
        if let b = req.body { r.httpBody = Data(b.utf8) }
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: r) { data, resp, _ in
            let http = resp as? HTTPURLResponse
            let decoded = data.flatMap { Self.decode($0, encoding: (http?.value(forHTTPHeaderField: "Content-Encoding") ?? "").lowercased()) }
            var cookies: [String] = []
            if let raw = http?.value(forHTTPHeaderField: "Set-Cookie") {
                cookies = raw.components(separatedBy: ", ").filter { $0.contains("=") }
            }
            box.value = (http?.statusCode ?? 0, decoded, cookies)
            sem.signal()
        }.resume()
        sem.wait()
        return box.value
    }

    /// 只认 URLSession 已解压后的明文；声明了 gzip / br 却仍是压缩态时**逐段兜底**解码。
    private static func decode(_ data: Data, encoding: String) -> Data? {
        guard !encoding.isEmpty, encoding != "identity" else { return data }
        if let gz = try? (data as NSData).decompressed(using: .zlib) { return gz as Data }
        return data
    }
}
