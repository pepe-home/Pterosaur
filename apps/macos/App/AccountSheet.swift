// 登录弹窗（ADR-062）：扫描二维码 / 自提供 Cookie 两种方式；已登录时显示账号并提供退出登录。
// 二维码由 SwiftUI 用 CoreImage 直接画（内核只产出内容 URL，见 AGENTS.md）。
import CoreImage.CIFilterBuiltins
import PterosaurCore
import SwiftUI

struct AccountSheet: View {
    @ObservedObject var account: Account
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .qr
    @State private var manualCookie = ""
    @State private var manualError: String?

    private enum Mode: String, CaseIterable { case qr = "扫描二维码", cookie = "自提供 Cookie" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("网易云音乐").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }
            }
            if account.status.logged {
                HStack(spacing: 12) {
                    if let a = account.status.avatarUrl { RemoteImage(url: a, corner: 24).frame(width: 48, height: 48) }
                    VStack(alignment: .leading) {
                        Text(account.status.nickname ?? "已登录").font(.headline)
                        if account.status.vip { Text("VIP").font(.caption).foregroundStyle(.tint) }
                    }
                    Spacer()
                    Button("退出登录", role: .destructive) {
                        account.signOut()
                        dismiss()
                    }
                }
                .frame(width: 420)
            } else {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 420)

                switch mode {
                case .qr: QrLoginView(account: account, onDone: { dismiss() })
                case .cookie:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("从浏览器开发者工具复制 Cookie（只需 MUSIC_U 的值也可以）")
                            .font(.callout).foregroundStyle(.secondary)
                        TextEditor(text: $manualCookie)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 420, height: 120)
                            .border(.quaternary)
                        if let manualError { Text(manualError).foregroundStyle(.red).font(.caption) }
                        HStack {
                            Spacer()
                            Button("登录") {
                                Task {
                                    if account.signInNetease(rawCookie: manualCookie) {
                                        try? await Task.sleep(for: .milliseconds(600))
                                        account.refreshStatus()
                                        dismiss()
                                    } else {
                                        manualError = "没有识别到会话 cookie（MUSIC_U / __csrf）"
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}

private struct QrLoginView: View {
    @ObservedObject var account: Account
    var onDone: () -> Void
    @State private var content: String?
    @State private var status = "正在生成二维码…"
    @State private var failed = false

    var body: some View {
        VStack(spacing: 12) {
            if let content, let img = QRImage.make(content) {
                Image(nsImage: img).interpolation(.none).resizable().frame(width: 220, height: 220)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ProgressView().frame(width: 220, height: 220)
            }
            Text(status).font(.callout).foregroundStyle(failed ? Color.red : Color.secondary)
        }
        .frame(width: 420)
        .task(id: failed) { if !failed { await loop() } }
    }

    private func loop() async {
        do {
            let key = try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
                DispatchQueue.global().async { c.resume(with: Result { qrKey() }) }
            }
            guard !key.isEmpty else {
                failed = true
                status = "无法生成二维码，请稍后再试"
                return
            }
            content = qrLoginUrl(key: key)
            status = "请用网易云音乐 App 扫码"
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(1))
                let r = await withCheckedContinuation { (c: CheckedContinuation<QrCheckResult, Never>) in
                    DispatchQueue.global().async { c.resume(returning: qrCheck(key: key)) }
                }
                switch r.code {
                case 800: status = "二维码已过期"; failed = true; return
                case 802: status = "已扫码，请在手机上确认"
                case 803:
                    account.signInNetease(setCookies: r.cookies ?? [])
                    status = "登录成功"
                    onDone()
                    return
                default: break
                }
            }
        } catch {
            status = "生成二维码失败：\(error.localizedDescription)"
            failed = true
        }
    }
}

/// 二维码内容 → NSImage（CoreImage CIQRCodeGenerator，纠正级别 M、不加静区——界面已留白）。
enum QRImage {
    static func make(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: out.extent.width, height: out.extent.height))
    }
}
