import SwiftUI
import Combine
import Security
import CoreText

private enum AppFont {
    static func regular(_ size: CGFloat) -> Font { .custom("Gilroy-Regular", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("Gilroy-Medium", size: size) }
    static func semiBold(_ size: CGFloat) -> Font { .custom("Gilroy-SemiBold", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("Gilroy-Bold", size: size) }
    static func display(_ size: CGFloat) -> Font { .custom("Gilroy-Extrabold", size: size) }
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
    let uploadToday: Int64?
    let downloadToday: Int64?
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
    let wifiDownloadToday: Int64
    let nodes: [Node]
    let best: String
    let fallback: Bool
    let activeOutbound: String
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
    let logs: String?
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
    @Published var logs = ""
    @Published var deviceRates: [String: Double] = [:]
    @Published var expiration = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6)) ?? Date()
    private var refreshing = false
    private var expiryLoaded = false
    private var previousDevices: [String: (bytes: Int64, at: Date)] = [:]

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
                let now = Date()
                for device in newStatus.devices {
                    guard let received = device.downloaded else { continue }
                    if let previous = previousDevices[device.mac] {
                        let interval = now.timeIntervalSince(previous.at)
                        if interval > 0 && received >= previous.bytes {
                            deviceRates[device.mac] = Double(received - previous.bytes) / interval
                        }
                    }
                    previousDevices[device.mac] = (received, now)
                }
                status = newStatus
                if !expiryLoaded && newStatus.expiresAt > 0 {
                    expiration = Date(timeIntervalSince1970: TimeInterval(newStatus.expiresAt))
                    expiryLoaded = true
                }
                message = newStatus.mode == "direct" ? "Normal internet paylaşılıyor" :
                    (newStatus.vpnRunning ? "Router çalışıyor" : "VPN başlatılıyor")
            } catch {
                message = "Router'a bağlanılamadı: \(String(reflecting: error))"
            }
        }
    }

    func test() {
        busy = true
        exitIP = nil
        message = "VPN çıkış adresi test ediliyor…"
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("test") }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    exitIP = result.exitIP
                    message = "VPN bağlantısı başarılı"
                } else {
                    message = result.error ?? "Test başarısız"
                    loadLogs()
                }
            } catch {
                message = error.localizedDescription
                loadLogs()
            }
        }
    }

    func install() {
        busy = true
        message = "Router yardımcıları kuruluyor…"
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("install") }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                message = result.note ?? result.error ?? "Kurulum tamamlanamadı"
                if result.ok { refresh() } else { loadLogs() }
            } catch {
                message = error.localizedDescription
                loadLogs()
            }
        }
    }

    func loadLogs() {
        Task {
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("logs") }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                logs = result.logs ?? result.error ?? "Günlük bulunamadı"
            } catch { logs = error.localizedDescription }
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

    func changeMode(_ mode: String) {
        guard mode == "vpn" || mode == "direct" else { return }
        busy = true
        message = "Router internet modu değiştiriliyor…"
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run(mode == "vpn" ? "mode-vpn" : "mode-direct")
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                message = result.ok ? (mode == "vpn" ? "VPN modu açıldı" : "Normal internet paylaşımı açıldı") :
                    (result.error ?? "Mod değiştirilemedi")
                if result.ok { refresh() }
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

private func rate(_ value: Double?) -> String {
    guard let value else { return "Ölçülüyor" }
    if value >= 1_048_576 { return String(format: "%.1f MB/sn", value / 1_048_576) }
    return String(format: "%.0f KB/sn", value / 1024)
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

private enum AppPage: String, CaseIterable, Identifiable {
    case overview, vpn, router, devices
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Genel Bakış"
        case .vpn: "VPN Ayarları"
        case .router: "Router"
        case .devices: "Cihazlar"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .vpn: "shield.lefthalf.filled"
        case .router: "wifi.router.fill"
        case .devices: "laptopcomputer.and.iphone"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: "Bağlantı ve kullanım durumunun özeti"
        case .vpn: "Sunucular, bağlantı testi ve abonelik"
        case .router: "Ağ, trafik ve çalışma bilgileri"
        case .devices: "HappVPN ağına bağlı cihazlar"
        }
    }
}

private struct ContentView: View {
    @StateObject private var model = DashboardModel()
    @State private var selectedPage: AppPage? = .overview
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Section("HAPPROUTER") {
                    ForEach(AppPage.allCases) { page in
                        Label(page.title, systemImage: page.symbol)
                            .font(AppFont.medium(13))
                            .tag(page)
                            .padding(.vertical, 5)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 245)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    switch selectedPage ?? .overview {
                    case .overview: overviewPage
                    case .vpn: vpnPage
                    case .router: routerPage
                    case .devices: devicesPage
                    }
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 940, minHeight: 660)
        .font(AppFont.regular(14))
        .onAppear { model.refresh() }
        .onReceive(timer) { _ in model.refresh() }
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text((selectedPage ?? .overview).title)
                    .font(AppFont.display(30))
                Text((selectedPage ?? .overview).subtitle)
                    .font(AppFont.regular(13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
        .padding(.bottom, 4)
    }

    private var statusPill: some View {
        let direct = model.status?.mode == "direct"
        let running = model.status?.vpnRunning == true
        return Label(direct ? "Normal internet" : (running ? "Xray çalışıyor" : "Kontrol ediliyor"),
                     systemImage: direct ? "network" : (running ? "checkmark.shield.fill" : "hourglass"))
            .font(AppFont.semiBold(12))
            .foregroundStyle(direct ? Color.blue : (running ? Color.green : Color.orange))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(direct ? Color.blue.opacity(0.11) : (running ? Color.green.opacity(0.11) : Color.orange.opacity(0.11)),
                        in: Capsule())
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(title: "VPN çıkış IP", value: model.exitIP ?? "Test et",
                         caption: "Router üzerinden doğrulanır", symbol: "globe.europe.africa")
                StatCard(title: "Wi-Fi verisi", value: bytes((model.status?.wifi.rx ?? 0) + (model.status?.wifi.tx ?? 0)),
                         caption: "Son açılıştan beri", symbol: "wifi")
                StatCard(title: "Bağlı cihaz", value: "\(model.status?.devices.count ?? 0)",
                         caption: "Wi-Fi ve kablo", symbol: "laptopcomputer.and.iphone")
                StatCard(title: "Kalan gün", value: daysRemaining.map(String.init) ?? "—",
                         caption: "Abonelik süresi", symbol: "calendar")
            }
            actionBar
            sectionPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bağlantı").font(AppFont.bold(18))
                    Text(model.status?.mode == "direct"
                         ? "Router şu anda normal interneti paylaşıyor."
                         : "HappVPN ağı router üzerindeki VPN yapılandırmasını kullanıyor.")
                        .foregroundStyle(.secondary)
                    if let exitIP = model.exitIP {
                        Label("Test edilen çıkış: \(exitIP)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Text("Sunucu listesi ve abonelik için VPN Ayarları bölümünü aç.")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var vpnPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("VPN bağlantısı").font(AppFont.bold(18))
                        Spacer()
                        Text(model.exitIP ?? "Henüz test edilmedi")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text("Çıkış IP testi router'ın VPN bağlantısı üzerinden yapılır.")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                    Button("VPN bağlantısını test et") { model.test() }
                        .disabled(model.busy || model.status?.vpnRunning != true)
                        .buttonStyle(.borderedProminent)
                }
            }
            subscriptionSection
            sectionPanel { nodeSection }
            diagnosticsSection
            feedbackLine
        }
    }

    private var routerPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(title: "Wi-Fi trafiği", value: bytes((model.status?.wifi.rx ?? 0) + (model.status?.wifi.tx ?? 0)),
                         caption: "Son açılıştan beri", symbol: "wifi")
                StatCard(title: "WAN trafiği", value: bytes((model.status?.wan.rx ?? 0) + (model.status?.wan.tx ?? 0)),
                         caption: "Son açılıştan beri", symbol: "network")
                StatCard(title: "VPN trafiği", value: model.status?.vpnBytes == nil ? "—" :
                         bytes((model.status?.vpnBytes?.rx ?? 0) + (model.status?.vpnBytes?.tx ?? 0)),
                         caption: "Xray başladığından beri", symbol: "arrow.up.arrow.down")
                StatCard(title: "Çalışma süresi", value: uptimeText,
                         caption: "Router son açılıştan beri", symbol: "clock")
            }
            sectionPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ağ bilgileri").font(AppFont.bold(18))
                    LabeledContent("Router adresi", value: "192.168.1.1")
                    LabeledContent("Wi-Fi ağı", value: "HappVPN")
                    LabeledContent("İnternet modu", value: model.status?.mode == "direct" ? "Doğrudan" : "VPN")
                    LabeledContent("Xray", value: model.status?.vpnRunning == true ? "Çalışıyor" : "Kontrol ediliyor")
                    Button("Durumu yenile") { model.refresh() }.disabled(model.busy)
                }
            }
            sectionPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Router kurulumu").font(AppFont.bold(18))
                    Text("Mac'i router LAN portuna bağla. Kurulum, mevcut OpenWrt ve Xray üzerinde ölçüm, kullanım ve abonelik süresi görevlerini yükler. VPN ayarlarını değiştirmez.")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                    Button("Gerekli yardımcıları yükle") { model.install() }
                        .disabled(model.busy)
                        .buttonStyle(.borderedProminent)
                }
            }
            sectionPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("İnternet paylaşım modu").font(AppFont.bold(18))
                    Text("VPN modunda bağlı cihazlar Happ üzerinden çıkar. Normal internet modunda router WAN bağlantısını paylaşır.")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                    HStack {
                        Button("VPN modunu aç") { model.changeMode("vpn") }
                            .disabled(model.busy || model.status?.mode == "vpn" || model.status?.vpnRunning != true)
                        Button("Normal interneti aç") { model.changeMode("direct") }
                            .disabled(model.busy || model.status?.mode == "direct")
                    }
                }
            }
            feedbackLine
        }
    }

    private var diagnosticsSection: some View {
        sectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Bağlantı günlükleri").font(AppFont.bold(18))
                    Spacer()
                    Button("Günlükleri yenile") { model.loadLogs() }
                }
                Text("Test başarısız olduğunda router'ın son Xray olayları burada görünür.")
                    .font(AppFont.regular(12)).foregroundStyle(.secondary)
                if !model.logs.isEmpty {
                    ScrollView([.horizontal, .vertical]) {
                        Text(model.logs)
                            .font(AppFont.regular(11))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private var devicesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(title: "Bugün indirilen", value: bytes(model.status?.wifiDownloadToday),
                         caption: "Wi-Fi cihazları · bugün", symbol: "arrow.down.circle")
                StatCard(title: "Şimdi bağlı", value: "\(model.status?.devices.count ?? 0)",
                         caption: "Wi-Fi ve kablo", symbol: "laptopcomputer.and.iphone")
            }
            sectionPanel { deviceSection }
            Button("Cihazları yenile") { model.refresh() }.disabled(model.busy)
            feedbackLine
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("VPN çıkışını test et") { model.test() }
                .disabled(model.busy || model.status?.vpnRunning != true)
                .buttonStyle(.borderedProminent)
            Button("Yenile") { model.refresh() }.disabled(model.busy)
            Spacer()
            Text(model.message).font(AppFont.regular(12))
                .foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var feedbackLine: some View {
        Text(model.message).font(AppFont.regular(12))
            .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionPanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 16))
    }

    private var daysRemaining: Int? {
        guard let expires = model.status?.expiresAt, expires > 0 else { return nil }
        return max(0, Int(ceil(Date(timeIntervalSince1970: TimeInterval(expires)).timeIntervalSinceNow / 86400)))
    }

    private var uptimeText: String {
        let seconds = Int(model.status?.uptimeSeconds ?? 0)
        return seconds >= 86400 ? "\(seconds / 86400) gün" : "\(seconds / 3600) saat"
    }

    private var activeRouteLabel: String {
        guard model.status?.mode != "direct" else { return "Normal internet modu açık" }
        guard let active = model.status?.activeOutbound, active != "happ-vpn" else {
            return "Trafik Happ profili üzerinden yönleniyor"
        }
        let name = model.status?.nodes.first(where: { $0.tag == active })?.name ?? active
        return "Aktif VPN sunucusu: \(name)"
    }

    private var nodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VPN sunucuları").font(AppFont.bold(18))
                Spacer()
                Text("TCP erişimi · 30 dakikada bir")
                    .font(AppFont.regular(12)).foregroundStyle(.secondary)
            }
            Label(activeRouteLabel, systemImage: "info.circle")
                .font(AppFont.regular(12)).foregroundStyle(.secondary)
            Text("Bu ms değeri yalnızca sunucunun TCP erişimini ölçer. Gerçek VPN bağlantısı için çıkış IP testinin başarılı olması gerekir. Otomatik sunucu değişimi şu anda etkin değil.")
                .font(AppFont.regular(11)).foregroundStyle(.secondary)
            let nodes = model.status?.nodes ?? model.previewNodes
            if nodes.isEmpty {
                Text("Henüz sunucu listesi kurulmadı.")
                    .foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                ForEach(nodes) { node in
                    HStack(spacing: 12) {
                        Text(node.name).lineLimit(1)
                        Spacer()
                        if model.status?.best == node.tag && node.alive == true {
                            Text("En düşük TCP").font(AppFont.bold(11)).foregroundStyle(.green)
                        }
                        Text(node.alive == true ? "\(Int(node.delay ?? 0)) ms" : "n/a")
                            .monospacedDigit()
                            .foregroundStyle(node.alive == true ? .primary : .secondary)
                            .frame(width: 78, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    if node.id != nodes.last?.id { Divider() }
                }
            }
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bağlı cihazlar").font(AppFont.bold(18))
                Spacer()
                Text("\(model.status?.devices.count ?? 0) cihaz")
                    .font(AppFont.regular(12)).foregroundStyle(.secondary)
            }
            if model.status?.devices.isEmpty != false {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2).foregroundStyle(.secondary)
                    Text("Cihaz görünmüyor").font(AppFont.semiBold(14))
                    Text("Telefon veya bilgisayar HappVPN ağına bağlandığında burada görünür.")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 22)
            }
            ForEach(model.status?.devices ?? []) { device in
                HStack(spacing: 12) {
                    Image(systemName: device.type == "Wi-Fi" ? "wifi" : "cable.connector")
                        .foregroundStyle(.teal)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.name?.isEmpty == false ? device.name! : device.mac)
                            .font(AppFont.semiBold(13))
                        Text(device.ip ?? device.mac).font(AppFont.regular(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(device.type == "Wi-Fi" ? "↓ " + rate(model.deviceRates[device.mac]) : "Kablolu")
                            .font(AppFont.semiBold(12))
                        Text(device.downloadToday.map { "Bugün " + bytes($0) } ?? "Günlük veri yok")
                            .font(AppFont.regular(11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private var subscriptionSection: some View {
        sectionPanel {
            VStack(alignment: .leading, spacing: 13) {
                Text("Abonelik").font(AppFont.bold(18))
                Text("Yeni HTTPS abonelik adresini önce kontrol et, sonra router'a kur.")
                    .font(AppFont.regular(12)).foregroundStyle(.secondary)
                HStack {
                    DatePicker("Bitiş günü", selection: $model.expiration, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    Button("Tarihi kaydet") { model.saveExpiry() }.disabled(model.busy)
                }
                if let days = daysRemaining {
                    Label("\(days) gün kaldı · süre dolunca normal internet paylaşılır", systemImage: "calendar")
                        .font(AppFont.medium(12))
                        .foregroundStyle(days > 3 ? Color.secondary : Color.orange)
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
                    Button(model.showSubscription ? "Gizle" : "Göster") {
                        model.showSubscription.toggle()
                    }
                }
                HStack(spacing: 10) {
                    Button("Profilleri kontrol et") { model.preview() }.disabled(model.busy)
                    Button("Router'a kur") { model.apply() }
                        .disabled(model.busy || model.previewNodes.isEmpty)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

@main
struct HappRouterApp: App {
    init() {
        if let resourceURL = Bundle.main.resourceURL {
            for file in ["Gilroy-Regular.ttf", "Gilroy-Medium.ttf", "Gilroy-SemiBold.ttf",
                         "Gilroy-Bold.ttf", "Gilroy-Extrabold.ttf"] {
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
