import SwiftUI
import Combine
import Security
import CoreText

private enum AppFont {
    static func regular(_ size: CGFloat) -> Font { .custom("Gilroy-Regular", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("Gilroy-Medium", size: size) }
    static func semiBold(_ size: CGFloat) -> Font { .custom("Gilroy-SemiBold", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("Gilroy-Bold", size: size) }
    static func display(_ size: CGFloat) -> Font { .custom("QurovaDEMO-Medium", size: size) }
}

private struct ByteCounter: Decodable {
    let rx: Int64?
    let tx: Int64?
}

private struct Device: Decodable, Identifiable {
    let mac: String
    let ip: String?
    let name: String?
    let type: String?
    let uploaded: Int64?
    let downloaded: Int64?
    var id: String { mac }
}

private struct Node: Decodable, Identifiable {
    let tag: String
    let name: String
    let address: String?
    let country: String?
    let alive: Bool?
    let delay: Double?
    let lastTry: Int?
    var id: String { tag }
}

private struct RouterStatus: Decodable {
    let ok: Bool
    let vpnRunning: Bool
    let uptimeSeconds: Double
    let wifi: ByteCounter
    let wan: ByteCounter
    let vpnBytes: ByteCounter?
    let devices: [Device]
    let nodes: [Node]
    let best: String
    let fallback: Bool
    let metricsAvailable: Bool
    let expiresAt: Int
    let mode: String
    let updatedAt: Int
}

private struct BackendResult: Decodable {
    let ok: Bool
    let error: String?
    let exitIP: String?
    let count: Int?
    let nodes: [Node]?
    let note: String?
}

private enum Backend {
    static func run(_ command: String, input: String? = nil, expires: Int? = nil) throws -> Data {
        let script: URL
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("routerctl.py"),
           FileManager.default.fileExists(atPath: resource.path) {
            script = resource
        } else {
            script = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/routerctl.py")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, command] + (input == nil ? [] : ["--url", "-"]) +
            (expires.map { ["--expires", String($0)] } ?? [])
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        if let input {
            let pipe = Pipe()
            process.standardInput = pipe
            try process.run()
            pipe.fileHandleForWriting.write(Data(input.utf8))
            try? pipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if data.isEmpty {
            throw NSError(domain: "HappRouter", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                            String(data: errorData, encoding: .utf8) ?? "Router yanıt vermedi."])
        }
        return data
    }
}

private enum SecretStore {
    private static let service = "HappRouter.subscription"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecValueData as String: Data(value.utf8)]
        SecItemAdd(item as CFDictionary, nil)
    }
}

@MainActor
private final class DashboardModel: ObservableObject {
    @Published var status: RouterStatus?
    @Published var previewNodes: [Node] = []
    @Published var subscription = SecretStore.read()
    @Published var showSubscription = false
    @Published var busy = false
    @Published var message = "Router bağlantısı kontrol ediliyor…"
    @Published var exitIP: String?
    @Published var expiration = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6)) ?? Date()
    private var refreshing = false
    private var expiryLoaded = false

    var expiryEpoch: Int {
        Int((Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: expiration) ?? expiration).timeIntervalSince1970)
    }

    func refresh() {
        guard !busy && !refreshing else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("status") }.value
                let newStatus = try JSONDecoder().decode(RouterStatus.self, from: data)
                status = newStatus
                if !expiryLoaded && newStatus.expiresAt > 0 {
                    expiration = Date(timeIntervalSince1970: TimeInterval(newStatus.expiresAt))
                    expiryLoaded = true
                }
                message = newStatus.mode == "direct" ? "Abonelik bitti; normal internet paylaşılıyor" :
                    (newStatus.vpnRunning ? "Router çalışıyor" : "VPN başlatılıyor")
            } catch {
                message = "Router'a bağlanılamadı: \(String(reflecting: error))"
            }
        }
    }

    func test() {
        busy = true
        message = "VPN çıkış adresi test ediliyor…"
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("test") }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    exitIP = result.exitIP
                    message = "VPN bağlantısı başarılı"
                } else { message = result.error ?? "Test başarısız" }
            } catch { message = error.localizedDescription }
        }
    }

    func preview() {
        let url = subscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { message = "Abonelik adresini girin"; return }
        busy = true
        message = "Abonelik bağlantıları okunuyor…"
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("preview", input: url) }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    previewNodes = result.nodes ?? []
                    SecretStore.write(url)
                    message = "\(result.count ?? 0) profil bulundu. Ulaşılabilirlik router'a kurulduktan sonra ölçülür."
                } else { message = result.error ?? "Abonelik okunamadı" }
            } catch { message = error.localizedDescription }
        }
    }

    func apply() {
        let url = subscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { message = "Abonelik adresini girin"; return }
        busy = true
        message = "Router yapılandırması doğrulanıyor ve yükleniyor…"
        Task {
            defer { busy = false }
            do {
                let expiry = expiryEpoch
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run("apply", input: url, expires: expiry)
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    SecretStore.write(url)
                    message = "\(result.count ?? 0) profil kuruldu. VPN yeniden başlıyor; bu birkaç dakika sürebilir."
                    previewNodes = []
                    refresh()
                } else { message = result.error ?? "Kurulum başarısız" }
            } catch { message = error.localizedDescription }
        }
    }

    func saveExpiry() {
        let expiry = expiryEpoch
        busy = true
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run("expiry", expires: expiry)
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                message = result.ok ? "Bitiş tarihi router'a kaydedildi" : (result.error ?? "Tarih kaydedilemedi")
                refresh()
            } catch { message = error.localizedDescription }
        }
    }
}

private func bytes(_ value: Int64?) -> String {
    guard let value else { return "—" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useMB, .useGB, .useTB]
    return formatter.string(fromByteCount: value)
}

private struct StatCard: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.teal)
            Text(title).font(AppFont.medium(12)).foregroundStyle(.secondary)
            Text(value).font(AppFont.bold(23)).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(AppFont.regular(11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ContentView: View {
    @StateObject private var model = DashboardModel()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("HappRouter").font(AppFont.display(32))
                        Text("Xiaomi 4C · HappVPN ağı").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(model.status?.mode == "direct" ? "Normal internet" :
                          (model.status?.vpnRunning == true ? "VPN çalışıyor" : "Bağlantı kontrol ediliyor"),
                          systemImage: model.status?.mode == "direct" ? "network" :
                          (model.status?.vpnRunning == true ? "checkmark.shield.fill" : "exclamationmark.shield"))
                        .foregroundStyle(model.status?.mode == "direct" ? .blue :
                                         (model.status?.vpnRunning == true ? .green : .orange))
                }
                HStack(spacing: 12) {
                    StatCard(title: "VPN çıkış IP", value: model.exitIP ?? "Test et", caption: "Router üzerinden ölçülür", symbol: "globe.europe.africa")
                    StatCard(title: "Wi-Fi veri", value: bytes((model.status?.wifi.rx ?? 0) + (model.status?.wifi.tx ?? 0)), caption: "Son açılıştan beri", symbol: "wifi")
                    StatCard(title: "VPN veri", value: model.status?.vpnBytes == nil ? "—" : bytes((model.status?.vpnBytes?.rx ?? 0) + (model.status?.vpnBytes?.tx ?? 0)), caption: "Xray başladığından beri", symbol: "arrow.up.arrow.down")
                    StatCard(title: "Bağlı cihaz", value: "\(model.status?.devices.count ?? 0)", caption: "Wi-Fi ve kablo", symbol: "laptopcomputer.and.iphone")
                }
                HStack {
                    Button("VPN bağlantısını test et") { model.test() }.disabled(model.busy)
                    Button("Yenile") { model.refresh() }.disabled(model.busy)
                    Spacer()
                    Text(model.message).font(AppFont.regular(12)).foregroundStyle(.secondary).lineLimit(2)
                }
                nodeSection
                deviceSection
                subscriptionSection
            }
            .padding(24)
        }
        .frame(minWidth: 850, minHeight: 650)
        .font(AppFont.regular(14))
        .onAppear { model.refresh() }
        .onReceive(timer) { _ in model.refresh() }
    }

    private var nodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VPN sunucuları").font(AppFont.bold(19))
                Spacer()
                Text("Sunucu ölçümleri izlenir; otomatik geçiş doğrulanıyor")
                    .font(AppFont.regular(12)).foregroundStyle(.secondary)
            }
            if model.status?.fallback == true {
                Label("Ölçüm yoksa çalışan Happ profili kullanılır", systemImage: "arrow.uturn.backward")
                    .font(.caption).foregroundStyle(.orange)
            }
            let nodes = model.status?.nodes ?? model.previewNodes
            if nodes.isEmpty {
                Text("Henüz sunucu listesi kurulmadı.").foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                ForEach(nodes) { node in
                    HStack {
                        Text(node.name).lineLimit(1)
                        Spacer()
                        if model.status?.best == node.tag && node.alive == true {
                            Text("En düşük ms").font(.caption.bold()).foregroundStyle(.green)
                        }
                        Text(node.alive == true ? "\(Int(node.delay ?? 0)) ms" : "n/a")
                            .monospacedDigit().foregroundStyle(node.alive == true ? .primary : .secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bağlı cihazlar").font(AppFont.bold(19))
            if model.status?.devices.isEmpty != false {
                Text("Şu anda cihaz görünmüyor.").foregroundStyle(.secondary)
            }
            ForEach(model.status?.devices ?? []) { device in
                HStack {
                    Image(systemName: device.type == "Wi-Fi" ? "wifi" : "cable.connector")
                        .foregroundStyle(.teal)
                    Text(device.name?.isEmpty == false ? device.name! : device.mac)
                    Text(device.ip ?? "").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(device.type ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aboneliği yenile").font(AppFont.bold(19))
            Text("Yeni satın aldığın HTTPS abonelik adresini buraya gir. Önce profilleri oku, sonra router'a kur.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                DatePicker("Abonelik bitiş günü", selection: $model.expiration, displayedComponents: .date)
                    .datePickerStyle(.compact)
                Button("Tarihi kaydet") { model.saveExpiry() }.disabled(model.busy)
            }
            if let expires = model.status?.expiresAt, expires > 0 {
                let days = max(0, Int(ceil(Date(timeIntervalSince1970: TimeInterval(expires)).timeIntervalSinceNow / 86400)))
                Text("Kalan süre: \(days) gün · süre bittiğinde router normal interneti paylaşır")
                    .font(AppFont.medium(12)).foregroundStyle(days > 3 ? Color.secondary : Color.orange)
            }
            HStack {
                Group {
                    if model.showSubscription {
                        TextField("https://…", text: $model.subscription)
                    } else {
                        SecureField("https://…", text: $model.subscription)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button(model.showSubscription ? "Gizle" : "Göster") { model.showSubscription.toggle() }
            }
            HStack {
                Button("Profilleri kontrol et") { model.preview() }.disabled(model.busy)
                Button("Router'a kur") { model.apply() }.disabled(model.busy || model.previewNodes.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }
}

@main
struct HappRouterApp: App {
    init() {
        if let resourceURL = Bundle.main.resourceURL {
            for file in ["Gilroy-Regular.ttf", "Gilroy-Medium.ttf", "Gilroy-SemiBold.ttf",
                         "Gilroy-Bold.ttf", "Gilroy-Extrabold.ttf", "QurovaDEMO-Medium.otf"] {
                let url = resourceURL.appendingPathComponent("Fonts").appendingPathComponent(file)
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
    var body: some Scene {
        WindowGroup("HappRouter") { ContentView() }
            .defaultSize(width: 1000, height: 780)
    }
}
