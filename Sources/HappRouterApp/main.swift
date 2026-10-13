import SwiftUI
import Combine
import Security
import CoreText
import AppKit

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
    let configured: Bool?
    var id: String { tag }
}

private struct BackupInfo: Decodable, Identifiable {
    let date: String
    let size: Int
    var id: String { date }
}

private struct RouterStatus: Decodable {
    let ok: Bool
    let vpnRunning: Bool
    let uptimeSeconds: Double
    let cpuPercent: Double?
    let memoryUsedBytes: Int64?
    let memoryTotalBytes: Int64?
    let wifi: ByteCounter
    let wan: ByteCounter
    let vpnBytes: ByteCounter?
    let devices: [Device]
    let blockedMACs: [String]
    let wifiDownloadToday: Int64
    let nodes: [Node]
    let best: String
    let fallback: Bool
    let activeOutbound: String
    let selectionMode: String?
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
    let backups: [BackupInfo]?
}

private enum Backend {
    static func run(_ command: String, input: String? = nil, expires: Int? = nil,
                    tag: String? = nil, mac: String? = nil, date: String? = nil) throws -> Data {
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
        var arguments = [script.path, command]
        if input != nil { arguments += ["--url", "-"] }
        if let expires { arguments += ["--expires", String(expires)] }
        if let tag { arguments += ["--tag", tag] }
        if let mac { arguments += ["--mac", mac] }
        if let date { arguments += ["--date", date] }
        process.arguments = arguments
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
    private static let additionalService = "HappRouter.additionalSubscription"
    private static func read(service: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    private static func write(_ value: String, service: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
        if value.isEmpty { return }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecValueData as String: Data(value.utf8)]
        SecItemAdd(item as CFDictionary, nil)
    }
    static func read() -> String { read(service: service) }
    static func readAdditional() -> String { read(service: additionalService) }
    static func write(_ value: String) { write(value, service: service) }
    static func writeAdditional(_ value: String) { write(value, service: additionalService) }
}

private enum Tone {
    case info, success, warning, error

    var color: Color {
        switch self {
        case .info: .secondary
        case .success: Theme.accent
        case .warning: .orange
        case .error: .red
        }
    }
    var symbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

private enum HelperUpdateState {
    case idle
    case running
    case success(String)
    case failure(String)
}

@MainActor
private final class DashboardModel: ObservableObject {
    @Published var status: RouterStatus?
    @Published var previewNodes: [Node] = []
    @Published var selectedNodeTag = ""
    @Published var candidateExitIP: String?
    @Published var candidateError: String?
    @Published var subscription = SecretStore.read()
    @Published var additionalSubscription = SecretStore.readAdditional()
    @Published var showSubscription = false
    @Published var busy = false
    @Published var message = "Router bağlantısı kontrol ediliyor…"
    @Published var tone: Tone = .info
    @Published var reachable: Bool?
    @Published var lastRefresh: Date?
    @Published var exitIP: String?
    @Published var exitError: String?
    @Published var exitChecking = false
    @Published var exitTestedAt: Date?
    @Published var logs = ""
    @Published var backups: [BackupInfo] = []
    @Published var selectedBackupDate = ""
    @Published var backupLog = ""
    @Published var backupLogDate = ""
    @Published var backupBusy = false
    @Published var serverActionError: String?
    private var exitProbeKey: String?
    @Published var helperUpdate: HelperUpdateState = .idle
    @Published var deviceRates: [String: Double] = [:]
    @Published var expiration = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6)) ?? Date()
    private var refreshing = false
    private var expiryLoaded = false
    private var previousDevices: [String: (bytes: Int64, at: Date)] = [:]

    var expiryEpoch: Int {
        Int((Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: expiration) ?? expiration).timeIntervalSince1970)
    }

    var profileInput: String {
        let primary = subscription.trimmingCharacters(in: .whitespacesAndNewlines)
        let additional = additionalSubscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if primary.isEmpty { return "" }
        return additional.isEmpty ? primary : primary + "\n" + additional
    }

    private func saveProfiles() {
        SecretStore.write(subscription.trimmingCharacters(in: .whitespacesAndNewlines))
        SecretStore.writeAdditional(additionalSubscription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func notify(_ text: String, _ tone: Tone = .info) {
        message = text
        self.tone = tone
    }

    func refresh() {
        guard !busy && !refreshing else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("status") }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                guard result.ok else {
                    reachable = false
                    notify(result.error ?? "Router durumu okunamadı", .error)
                    return
                }
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
                if status?.activeOutbound != newStatus.activeOutbound || status?.mode != newStatus.mode {
                    exitIP = nil
                    exitError = nil
                    exitTestedAt = nil
                    exitProbeKey = nil
                }
                status = newStatus
                reachable = true
                lastRefresh = now
                if !expiryLoaded && newStatus.expiresAt > 0 {
                    expiration = Date(timeIntervalSince1970: TimeInterval(newStatus.expiresAt))
                    expiryLoaded = true
                }
                if newStatus.mode == "direct" {
                    notify("Normal internet paylaşılıyor", .info)
                } else if newStatus.vpnRunning {
                    notify("Router çalışıyor", .success)
                } else {
                    notify("VPN başlatılıyor", .warning)
                }
            } catch {
                reachable = false
                notify("Router'a bağlanılamadı: \(String(reflecting: error))", .error)
            }
        }
    }

    func measureExitIfNeeded() {
        guard let status, status.mode == "vpn", status.vpnRunning else { return }
        let key = status.activeOutbound
        guard exitProbeKey != key, !exitChecking else { return }
        test(automatic: true)
    }

    func test(automatic: Bool = false) {
        guard !exitChecking, let status, status.vpnRunning else { return }
        exitProbeKey = status.activeOutbound
        exitChecking = true
        exitIP = nil
        exitError = nil
        exitTestedAt = nil
        if !automatic { notify("VPN çıkış IPv4 adresi ölçülüyor…") }
        Task {
            defer { exitChecking = false }
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("test") }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    exitIP = result.exitIP
                    exitTestedAt = Date()
                    if !automatic { notify("VPN çıkış IPv4 adresi doğrulandı", .success) }
                } else {
                    exitError = result.error ?? "VPN çıkışı doğrulanamadı."
                    if !automatic {
                        notify(exitError!, .error)
                        loadLogs()
                    }
                }
            } catch {
                exitError = error.localizedDescription
                if !automatic {
                    notify(error.localizedDescription, .error)
                    loadLogs()
                }
            }
        }
    }

    func selectNode(_ tag: String? = nil) {
        guard !busy else { return }
        busy = true
        serverActionError = nil
        notify(tag == nil ? "En düşük gecikmeli sunucu seçiliyor…" : "Seçilen sunucu test ediliyor…")
        Task {
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run(tag == nil ? "auto-node" : "select-node", tag: tag)
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    notify(result.note ?? "Sunucu seçimi güncellendi", .success)
                } else {
                    let detail = result.error ?? "Sunucu değiştirilemedi."
                    serverActionError = detail
                    notify(detail, .error)
                }
            } catch {
                serverActionError = error.localizedDescription
                notify(error.localizedDescription, .error)
            }
            busy = false
            refresh()
        }
    }

    func install() {
        busy = true
        helperUpdate = .running
        notify("Router yardımcıları kuruluyor…")
        Task {
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("install") }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                let detail = result.note ?? result.error ?? "Güncelleme tamamlanamadı"
                helperUpdate = result.ok ? .success(detail) : .failure(detail)
                notify(detail, result.ok ? .success : .error)
                busy = false
                if result.ok { refresh() } else { loadLogs() }
            } catch {
                helperUpdate = .failure(error.localizedDescription)
                notify(error.localizedDescription, .error)
                busy = false
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

    private func updateBackups(_ entries: [BackupInfo]) {
        backups = entries
        if !entries.contains(where: { $0.date == selectedBackupDate }) {
            selectedBackupDate = entries.first?.date ?? ""
        }
    }

    func loadBackups() {
        guard !backupBusy else { return }
        backupBusy = true
        Task {
            defer { backupBusy = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run("backup-list")
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    updateBackups(result.backups ?? [])
                } else {
                    notify(result.error ?? "Yedekler okunamadı", .error)
                }
            } catch { notify(error.localizedDescription, .error) }
        }
    }

    func createBackup() {
        guard !backupBusy else { return }
        backupBusy = true
        Task {
            defer { backupBusy = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run("backup-now")
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    updateBackups(result.backups ?? [])
                    notify(result.note ?? "Tanı yedeği oluşturuldu", .success)
                } else {
                    notify(result.error ?? "Yedek oluşturulamadı", .error)
                }
            } catch { notify(error.localizedDescription, .error) }
        }
    }

    func openBackup(export: Bool = false) {
        let day = selectedBackupDate
        guard !day.isEmpty, !backupBusy else { return }
        backupBusy = true
        Task {
            defer { backupBusy = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run("backup-read", date: day)
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                guard result.ok, let text = result.logs else {
                    notify(result.error ?? "Yedek günlüğü okunamadı", .error)
                    return
                }
                if export {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "HappRouter-tani-\(day).txt"
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        try text.write(to: url, atomically: true, encoding: .utf8)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                               ofItemAtPath: url.path)
                        notify("Tanı günlüğü kaydedildi", .success)
                    }
                } else {
                    backupLog = text
                    backupLogDate = day
                }
            } catch { notify(error.localizedDescription, .error) }
        }
    }

    func preview() {
        let profile = profileInput
        guard !profile.isEmpty else { notify("Sunucu profilini girin", .warning); return }
        busy = true
        previewNodes = []
        selectedNodeTag = ""
        candidateExitIP = nil
        candidateError = nil
        notify("Sunucu profilleri okunuyor…")
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) { try Backend.run("preview", input: profile) }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                guard profileInput == profile else { return }
                if result.ok {
                    previewNodes = result.nodes ?? []
                    selectedNodeTag = previewNodes.first?.tag ?? ""
                    candidateExitIP = nil
                    candidateError = nil
                    saveProfiles()
                    notify("\(result.count ?? 0) sunucu getirildi. Şimdi bağlantıyı test edin.", .info)
                } else { notify(result.error ?? "Profil okunamadı", .error) }
            } catch { notify(error.localizedDescription, .error) }
        }
    }

    func probeProfile() {
        let profile = profileInput
        guard !profile.isEmpty, !selectedNodeTag.isEmpty, !busy else { return }
        let tag = selectedNodeTag
        busy = true
        candidateExitIP = nil
        candidateError = nil
        notify("Yeni sunucunun internet çıkışı test ediliyor…")
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run("profile-test", input: profile, tag: tag)
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                guard profileInput == profile,
                      selectedNodeTag == tag else { return }
                if result.ok {
                    candidateExitIP = result.exitIP
                    notify("Yeni sunucu çalışıyor. Çıkış IP: \(result.exitIP ?? "doğrulandı")", .success)
                } else {
                    let message = result.error ?? "Yeni sunucu test edilemedi."
                    candidateError = message
                    notify(message, .error)
                }
            } catch {
                guard profileInput == profile,
                      selectedNodeTag == tag else { return }
                let message = error.localizedDescription
                candidateError = message
                notify(message, .error)
            }
        }
    }

    func apply() {
        let profile = profileInput
        guard !profile.isEmpty else { notify("Sunucu profilini girin", .warning); return }
        guard !selectedNodeTag.isEmpty, candidateExitIP != nil else {
            notify("Önce seçilen sunucunun bağlantısını test edin.", .warning)
            return
        }
        busy = true
        notify("Sunucu router'a kuruluyor ve yeniden doğrulanıyor…")
        Task {
            defer { busy = false }
            do {
                let expiry = expiryEpoch
                let tag = selectedNodeTag
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run("apply", input: profile, expires: expiry, tag: tag)
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    saveProfiles()
                    exitIP = result.exitIP
                    exitError = nil
                    exitTestedAt = Date()
                    exitProbeKey = tag
                    notify("Yeni sunucu çalışıyor. VPN çıkış IP: \(result.exitIP ?? "doğrulandı")", .success)
                    previewNodes = []
                    selectedNodeTag = ""
                    candidateExitIP = nil
                    candidateError = nil
                    refresh()
                } else { notify(result.error ?? "Kurulum başarısız", .error) }
            } catch { notify(error.localizedDescription, .error) }
        }
    }

    func pasteProfile(additional: Bool = false) {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            notify("Panoda metin bulunamadı", .warning)
            return
        }
        if additional { additionalSubscription = value } else { subscription = value }
        previewNodes = []
        selectedNodeTag = ""
        notify("Adres yapıştırıldı. Şimdi sunucuları getirin.")
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
                if result.ok {
                    notify("Bitiş tarihi router'a kaydedildi", .success)
                } else {
                    notify(result.error ?? "Tarih kaydedilemedi", .error)
                }
                refresh()
            } catch { notify(error.localizedDescription, .error) }
        }
    }

    func changeMode(_ mode: String) {
        guard mode == "vpn" || mode == "direct" else { return }
        busy = true
        notify("Router internet modu değiştiriliyor…")
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run(mode == "vpn" ? "mode-vpn" : "mode-direct")
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    notify(mode == "vpn" ? "VPN modu açıldı" : "Normal internet paylaşımı açıldı", .success)
                    refresh()
                } else {
                    notify(result.error ?? "Mod değiştirilemedi", .error)
                }
            } catch { notify(error.localizedDescription, .error) }
        }
    }

    func setDeviceBlocked(_ mac: String, blocked: Bool) {
        busy = true
        notify(blocked ? "Cihazın interneti engelleniyor…" : "Cihaz engeli kaldırılıyor…")
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Backend.run(blocked ? "block-device" : "unblock-device", mac: mac)
                }.value
                let result = try JSONDecoder().decode(BackendResult.self, from: data)
                if result.ok {
                    notify(result.note ?? "Cihaz ayarı kaydedildi", .success)
                    busy = false
                    refresh()
                } else {
                    notify(result.error ?? "Cihaz ayarı değiştirilemedi", .error)
                }
            } catch {
                notify(error.localizedDescription, .error)
            }
        }
    }
}

// MARK: - Biçimlendirme

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

private func latencyColor(_ ms: Double) -> Color {
    ms < 150 ? Theme.accent : (ms < 400 ? .orange : .red)
}

// MARK: - Ortak bileşenler

private enum Theme {
    static let accent = Color(red: 0.16, green: 0.39, blue: 0.93)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let stroke = Color.primary.opacity(0.08)
}

private struct AppActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Theme.accent
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.semiBold(12))
            .foregroundStyle(isEnabled ? (prominent ? Color.white :
                                          destructive ? tint : Color.primary) : Color.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(isEnabled ? (prominent ? tint : tint.opacity(0.10))
                                  : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(isEnabled ? tint.opacity(prominent ? 0 : 0.18) : Theme.stroke))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Başlıklı, açıklamalı kart. Tüm sayfalar aynı görsel dili kullanır.
private struct Card<Content: View, Accessory: View>: View {
    let title: String?
    let subtitle: String?
    let symbol: String?
    let accessory: Accessory
    let content: Content

    init(_ title: String? = nil, subtitle: String? = nil, symbol: String? = nil,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                HStack(alignment: .top, spacing: 10) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let title { Text(title).font(AppFont.bold(16)) }
                        if let subtitle {
                            Text(subtitle).font(AppFont.regular(12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    accessory
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.13), in: Circle())
                Text(title).font(AppFont.medium(12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(AppFont.bold(24))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption.isEmpty ? " " : caption)
                .font(AppFont.regular(11)).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 14, alignment: .leading)
                .opacity(caption.isEmpty ? 0 : 1)
                .accessibilityHidden(caption.isEmpty)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(AppFont.semiBold(11))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(AppFont.medium(13)).foregroundStyle(valueColor).textSelection(.enabled)
        }
        .font(AppFont.regular(13))
    }
}

private struct StepHeader: View {
    let number: Int
    let title: String
    let done: Bool
    let active: Bool
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done || active ? Theme.accent : Color.secondary.opacity(0.25))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(AppFont.bold(12))
                        .foregroundStyle(active ? .white : .secondary)
                }
            }
            .frame(width: 24, height: 24)
            Text(title).font(AppFont.semiBold(14))
                .foregroundStyle(active || done ? .primary : .secondary)
        }
    }
}

private enum HealthState {
    case good, warn, bad, unknown
    var color: Color {
        switch self {
        case .good: Theme.accent
        case .warn: .orange
        case .bad: .red
        case .unknown: .secondary
        }
    }
    var symbol: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .bad: "xmark.circle.fill"
        case .unknown: "circle.dotted"
        }
    }
}

private struct HealthRow: View {
    let state: HealthState
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: state.symbol).foregroundStyle(state.color).frame(width: 20)
            Text(title).font(AppFont.semiBold(13))
            Spacer(minLength: 12)
            Text(detail).font(AppFont.regular(12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Router modunu seçmek için büyük, tıklanabilir kart.
private struct ModeCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(AppFont.bold(15))
                    Text(selected ? "Açık" : "Seç")
                        .font(AppFont.semiBold(11))
                        .foregroundStyle(selected ? tint : .secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? tint : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .padding(16)
            .background(selected ? tint.opacity(0.08) : Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? tint.opacity(0.6) : Theme.stroke, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!(disabled || selected))
        .opacity(disabled && !selected ? 0.5 : 1)
    }
}

// MARK: - Sayfalar

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
        case .overview: "square.grid.2x2"
        case .vpn: "shield"
        case .router: "wifi.router"
        case .devices: "laptopcomputer.and.iphone"
        }
    }
}

private struct ContentView: View {
    @StateObject private var model = DashboardModel()
    @AppStorage("HappRouterAppearance") private var appearance = "system"
    @State private var selectedPage: AppPage? = .overview
    @State private var confirmDirect = false
    @State private var showHelpersSheet = false
    @State private var showServerHelp = false
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let statColumns = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    private var page: AppPage { selectedPage ?? .overview }
    private var isDirect: Bool { model.status?.mode == "direct" }
    private var vpnRunning: Bool { model.status?.vpnRunning == true }
    private var vpnExitText: String {
        if isDirect { return "Normal internet" }
        if let ip = model.exitIP { return ip }
        if model.exitChecking { return "Ölçülüyor…" }
        if model.exitError != nil { return "Doğrulanamadı" }
        return vpnRunning ? "Henüz ölçülmedi" : "VPN kapalı"
    }
    private var vpnExitDetail: String {
        if isDirect { return "VPN çıkışı kullanılmıyor." }
        if let date = model.exitTestedAt {
            return "Son ölçüm: \(date.formatted(date: .omitted, time: .shortened))"
        }
        return model.exitError ?? "Router üzerinden IPv4 çıkışı ölçülür."
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    switch page {
                    case .overview: overviewPage
                    case .vpn: vpnPage
                    case .router: routerPage
                    case .devices: devicesPage
                    }
                }
                .frame(maxWidth: page == .devices ? 760 : 940, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .ignoresSafeArea(.container, edges: .top)
            .buttonStyle(AppActionButtonStyle())
            .background(Color(nsColor: .windowBackgroundColor))
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        }
        .frame(minWidth: 960, minHeight: 680)
        .font(AppFont.regular(14))
        .tint(Theme.accent)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .onAppear { model.refresh() }
        .onReceive(timer) { _ in model.refresh() }
        .onChange(of: model.status?.updatedAt) { _, _ in model.measureExitIfNeeded() }
        .confirmationDialog("Normal internete geçilsin mi?", isPresented: $confirmDirect, titleVisibility: .visible) {
            Button("Normal interneti aç", role: .destructive) { model.changeMode("direct") }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("VPN kapanır; HappVPN ağındaki tüm cihazlar gerçek IP adresiyle internete çıkar.")
        }
        .sheet(isPresented: $showHelpersSheet) { helperUpdateSheet }
    }

    // MARK: Çerçeve

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.router.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("HappRouter").font(AppFont.bold(15))
                    Text("Mi Router 4C").font(AppFont.regular(11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)

            VStack(spacing: 4) {
                ForEach(AppPage.allCases) { item in
                    sidebarButton(item)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    appearanceButton("system", title: "Sistem", symbol: "display")
                    appearanceButton("light", title: "Açık", symbol: "sun.max")
                    appearanceButton("dark", title: "Koyu", symbol: "moon.stars")
                }
                .padding(4)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke))
                HStack(spacing: 8) {
                    Circle().fill(heroTint).frame(width: 8, height: 8)
                    Text(heroTitle).font(AppFont.medium(12)).lineLimit(1)
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
    }

    private func sidebarButton(_ item: AppPage) -> some View {
        let selected = page == item
        return Button { selectedPage = item } label: {
            HStack(spacing: 11) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? Theme.accent : Color.primary.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(selected ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 8))
                Text(item.title)
                    .font(selected ? AppFont.semiBold(13) : AppFont.medium(13))
                    .foregroundStyle(selected ? Theme.accent : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.white : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func appearanceButton(_ value: String, title: String, symbol: String) -> some View {
        let selected = appearance == value
        return Button { appearance = value } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(AppFont.semiBold(10))
            }
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(selected ? Theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) görünüm")
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(page.title).font(AppFont.display(28))
            Spacer()
            Button {
                model.refresh()
            } label: {
                Label("Yenile", systemImage: "arrow.clockwise")
            }
            .disabled(model.busy)
        }
    }

    /// Tüm sayfalarda sabit duran durum çubuğu: son mesaj, meşgul göstergesi, güncelleme zamanı.
    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if model.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.tone.symbol).foregroundStyle(model.tone.color)
                }
                Text(model.message)
                    .font(AppFont.medium(12))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 12)
                if let last = model.lastRefresh {
                    Text("Güncellendi: ").font(AppFont.regular(11)).foregroundStyle(.secondary)
                    + Text(last, style: .relative).font(AppFont.regular(11)).foregroundStyle(.secondary)
                    + Text(" önce").font(AppFont.regular(11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.bar)
        }
    }

    // MARK: Durum özeti

    private var heroTint: Color {
        if model.reachable == false { return .red }
        if model.status == nil { return .orange }
        if isDirect { return .blue }
        if model.exitError != nil { return .orange }
        return vpnRunning ? Theme.accent : .orange
    }

    private var heroSymbol: String {
        if model.reachable == false { return "wifi.exclamationmark" }
        if model.status == nil { return "hourglass" }
        if isDirect { return "network" }
        return vpnRunning ? "checkmark.shield.fill" : "hourglass"
    }

    private var heroTitle: String {
        if model.reachable == false { return "Router'a ulaşılamıyor" }
        if model.status == nil { return "Kontrol ediliyor…" }
        if isDirect { return "Normal internet açık" }
        if model.exitError != nil { return "VPN çıkışı doğrulanamadı" }
        return vpnRunning ? "VPN servisi açık" : "VPN başlatılıyor"
    }

    private var heroDetail: String {
        if model.reachable == false {
            return "Mac'in router'ın LAN portuna ya da HappVPN Wi-Fi ağına bağlı olduğundan emin ol. Bağlantı gelince bu ekran kendiliğinden güncellenir."
        }
        if model.status == nil { return "Router'dan durum bilgisi bekleniyor." }
        if isDirect { return "HappVPN ağındaki cihazlar VPN kullanmadan, gerçek IP adresiyle internete çıkıyor." }
        if model.exitError != nil { return "Router VPN servisi açık, fakat internet çıkışı son testte doğrulanamadı." }
        return vpnRunning
            ? "HappVPN cihazlarının internette görünen IPv4 adresi aşağıda ölçülür."
            : "VPN servisi hazır olunca durum otomatik güncellenir."
    }

    private var heroCard: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: heroSymbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(heroTint)
                .frame(width: 64, height: 64)
                .background(heroTint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(heroTitle).font(AppFont.display(22))
                Text(heroDetail)
                    .font(AppFont.regular(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            if !isDirect && model.reachable != false {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("VPN çıkış IPv4").font(AppFont.medium(11)).foregroundStyle(.secondary)
                    Text(vpnExitText)
                        .font(AppFont.bold(model.exitIP == nil ? 13 : 18))
                        .foregroundStyle(model.exitIP == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                    Button { model.test() } label: {
                        Label("IP'yi yeniden ölç", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(AppActionButtonStyle(prominent: true))
                    .disabled(model.exitChecking || !vpnRunning)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [heroTint.opacity(0.14), heroTint.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(heroTint.opacity(0.25)))
    }

    // MARK: Genel Bakış

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroCard
            LazyVGrid(columns: statColumns, spacing: 12) {
                StatCard(title: "Bağlı cihaz", value: "\(model.status?.devices.count ?? 0)",
                         caption: "Wi-Fi ve kablolu", symbol: "laptopcomputer.and.iphone")
                StatCard(title: "Bugün indirilen", value: bytes(model.status?.wifiDownloadToday),
                         caption: "Wi-Fi cihazları toplamı", symbol: "arrow.down.circle")
                StatCard(title: "Wi-Fi verisi", value: bytes((model.status?.wifi.rx ?? 0) + (model.status?.wifi.tx ?? 0)),
                         caption: "Router açıldığından beri", symbol: "wifi")
                StatCard(title: "Abonelik", value: daysRemaining.map { "\($0) gün" } ?? "—",
                         caption: daysRemaining == nil ? "Bitiş tarihi ayarlanmadı" : "kaldı",
                         symbol: "calendar", tint: subscriptionTint)
            }
            Card("Sistem sağlığı", symbol: "stethoscope") {
                VStack(alignment: .leading, spacing: 12) {
                    healthRows
                }
            }
            if !isDirect && !(model.exitIP == nil && vpnRunning) {
                Card("Sonraki adım", symbol: "lightbulb") {
                    HStack {
                        Text(nextStepText).font(AppFont.regular(13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(nextStepButton) { runNextStep() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var healthRows: some View {
        HealthRow(state: model.reachable == true ? .good : (model.reachable == false ? .bad : .unknown),
                  title: "Router erişimi",
                  detail: model.reachable == true ? "192.168.1.1 yanıt veriyor"
                      : (model.reachable == false ? "Yanıt yok" : "Kontrol ediliyor"))
        Divider()
        HealthRow(state: isDirect ? .unknown : (vpnRunning ? .good : (model.status == nil ? .unknown : .warn)),
                  title: "VPN servisi",
                  detail: isDirect ? "Normal internet modunda kapalı"
                      : (vpnRunning ? "Shadowsocks çalışıyor" : (model.status == nil ? "Bilinmiyor" : "Başlatılıyor")))
        Divider()
        HealthRow(state: model.exitIP != nil ? .good : (model.exitError != nil ? .warn : .unknown),
                  title: "Çıkış IP doğrulaması",
                  detail: model.exitIP.map { "IPv4 · \($0)" } ?? vpnExitText)
        Divider()
        HealthRow(state: serverHealth.state, title: "Sunucu erişimi", detail: serverHealth.detail)
        Divider()
        HealthRow(state: subscriptionHealth.state, title: "Abonelik süresi", detail: subscriptionHealth.detail)
    }

    private var serverHealth: (state: HealthState, detail: String) {
        let nodes = model.status?.nodes ?? []
        guard !nodes.isEmpty else { return (.unknown, "Sunucu listesi yok") }
        let alive = nodes.filter { $0.alive == true }
        guard !alive.isEmpty else { return (.bad, "Hiçbir sunucuya TCP ile ulaşılamıyor") }
        let fastest = alive.compactMap(\.delay).min().map { " · en düşük \(Int($0)) ms" } ?? ""
        return (alive.count == nodes.count ? .good : .warn, "\(alive.count)/\(nodes.count) sunucu erişilebilir\(fastest)")
    }

    private var subscriptionHealth: (state: HealthState, detail: String) {
        guard let days = daysRemaining else { return (.unknown, "Bitiş tarihi ayarlanmadı") }
        if days == 0 { return (.bad, "Süre doldu") }
        if days <= 3 { return (.warn, "\(days) gün kaldı · yakında bitiyor") }
        return (.good, "\(days) gün kaldı")
    }

    private var subscriptionTint: Color {
        guard let days = daysRemaining else { return .secondary }
        return days <= 3 ? .orange : Theme.accent
    }

    private var nextStepText: String {
        if let days = daysRemaining, days <= 3 {
            return "Abonelik süresi dolmak üzere. Yeni sunucu profilini yükleyip bitiş tarihini güncelle."
        }
        if model.exitIP == nil && vpnRunning {
            return "VPN'in gerçekten çalıştığını görmek için çıkış IP testini yap."
        }
        return "Sunucuyu değiştirmek ya da abonelik süresini güncellemek için VPN Ayarları sayfasını aç."
    }

    private var nextStepButton: String {
        if let days = daysRemaining, days <= 3 { return "Sunucuyu yenile" }
        if model.exitIP == nil && vpnRunning { return "Testi başlat" }
        return "VPN Ayarları"
    }

    private func runNextStep() {
        if model.exitIP == nil && vpnRunning && (daysRemaining ?? 99) > 3 {
            model.test()
        } else {
            selectedPage = .vpn
        }
    }

    // MARK: VPN Ayarları

    private var vpnPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card("Mevcut bağlantı", symbol: "checkmark.shield") {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("İnternette görünen VPN IPv4").font(AppFont.regular(12)).foregroundStyle(.secondary)
                        Text(vpnExitText)
                            .font(AppFont.bold(model.exitIP == nil ? 15 : 20))
                            .foregroundStyle(model.exitIP == nil ? .secondary : .primary)
                            .textSelection(.enabled)
                        Text(vpnExitDetail)
                            .font(AppFont.regular(11))
                            .foregroundStyle(model.exitError == nil ? Color.secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button { model.test() } label: {
                        Label(model.exitIP == nil ? "IP'yi ölç" : "IP'yi yenile",
                              systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(AppActionButtonStyle())
                    .disabled(model.exitChecking || !vpnRunning || isDirect)
                }
                if isDirect || !vpnRunning {
                    Label(isDirect ? "Normal internet modunda VPN çıkış IP'si paylaşılmaz."
                                   : "VPN servisi çalışmıyor.",
                          systemImage: "info.circle")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                }
            }
            serverChangeCard
            serversCard
            subscriptionCard
            diagnosticsCard
        }
    }

    private var hasProfile: Bool {
        !model.subscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Adımlar, önceki aşama tamamlandıktan sonra sırayla görünür.
    private var serverChangeCard: some View {
        Card("Yeni sunucu kur", subtitle: "Adresi ekle, bağlantıyı dene, sonra kur.",
             symbol: "arrow.triangle.2.circlepath",
             accessory: {
                 Badge(text: "\(model.candidateExitIP != nil ? 3 : (model.previewNodes.isEmpty ? 1 : 2))/3",
                       color: Theme.accent)
             }) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    StepHeader(number: 1, title: "Bağlantıyı ekle",
                               done: !model.previewNodes.isEmpty, active: true)
                    Text("1. abonelik veya sunucu profili")
                        .font(AppFont.medium(12)).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Group {
                            if model.showSubscription {
                                TextEditor(text: $model.subscription)
                                    .font(AppFont.regular(12))
                                    .scrollContentBackground(.hidden)
                                    .padding(6)
                                    .frame(height: 92)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                            } else {
                                SecureField("JSON, ss:// veya HTTPS bağlantısı", text: $model.subscription)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .disabled(model.busy)
                        .onChange(of: model.subscription) { _, _ in
                            model.previewNodes = []
                            model.selectedNodeTag = ""
                            model.candidateExitIP = nil
                            model.candidateError = nil
                        }
                        Button { model.pasteProfile() } label: {
                            Label("Yapıştır", systemImage: "doc.on.clipboard")
                        }
                        .disabled(model.busy)
                        Button { model.showSubscription.toggle() } label: {
                            Image(systemName: model.showSubscription ? "eye.slash" : "eye")
                        }
                        .help(model.showSubscription ? "Profili gizle" : "Profili göster")
                    }
                    Text("2. abonelik · isteğe bağlı")
                        .font(AppFont.medium(12)).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Group {
                            if model.showSubscription {
                                TextEditor(text: $model.additionalSubscription)
                                    .font(AppFont.regular(12))
                                    .scrollContentBackground(.hidden)
                                    .padding(6)
                                    .frame(height: 58)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                            } else {
                                SecureField("İkinci HTTPS abonelik adresi", text: $model.additionalSubscription)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .disabled(model.busy)
                        .onChange(of: model.additionalSubscription) { _, _ in
                            model.previewNodes = []
                            model.selectedNodeTag = ""
                            model.candidateExitIP = nil
                            model.candidateError = nil
                        }
                        Button { model.pasteProfile(additional: true) } label: {
                            Label("Yapıştır", systemImage: "doc.on.clipboard")
                        }
                        .disabled(model.busy)
                        if !model.additionalSubscription.isEmpty {
                            Button { model.additionalSubscription = "" } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .help("İkinci aboneliği kaldır")
                            .disabled(model.busy)
                        }
                    }
                    HStack {
                        Button { model.preview() } label: {
                            Label("Sunucuları getir", systemImage: "arrow.down.to.line")
                        }
                        .disabled(model.busy || !hasProfile)
                        Spacer()
                    }
                    DisclosureGroup(isExpanded: $showServerHelp) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Happ'te çalışan sunucuyu seçip “Copy Server JSON” ile kopyala.")
                            Text("ss:// ve Shadowsocks içeren HTTPS bağlantıları desteklenir. happ:// bağlantısını önce Happ'te aç. Hysteria ve VLESS bu router'da desteklenmez.")
                                .foregroundStyle(.secondary)
                            Text("Birden fazla ss:// adresi için göz simgesini açıp her adresi ayrı satıra yapıştır.")
                                .foregroundStyle(.secondary)
                            Text("İki HTTPS aboneliği için adresleri 1. ve 2. alanlara ayrı ayrı yapıştır.")
                                .foregroundStyle(.secondary)
                        }
                        .font(AppFont.regular(12))
                        .padding(.top, 6)
                    } label: {
                        Text("Profil nasıl alınır?").font(AppFont.medium(12)).foregroundStyle(Theme.accent)
                    }
                }
                if !model.previewNodes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            StepHeader(number: 2, title: "Bağlantıyı test et",
                                       done: model.candidateExitIP != nil, active: true)
                            Spacer()
                            Badge(text: "\(model.previewNodes.count) sunucu", color: Theme.accent)
                        }
                        if model.previewNodes.count > 1 {
                            VStack(spacing: 0) {
                                ForEach(model.previewNodes) { node in
                                    Button {
                                        model.selectedNodeTag = node.tag
                                        model.candidateExitIP = nil
                                        model.candidateError = nil
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: model.selectedNodeTag == node.tag ? "largecircle.fill.circle" : "circle")
                                                .foregroundStyle(model.selectedNodeTag == node.tag ? Theme.accent : .secondary)
                                            Text(node.name).lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.vertical, 7).padding(.horizontal, 10)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(model.busy)
                                    if node.id != model.previewNodes.last?.id { Divider() }
                                }
                            }
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        } else if let only = model.previewNodes.first {
                            Label(only.name, systemImage: "server.rack").font(AppFont.medium(13))
                        }
                        if let ip = model.candidateExitIP {
                            Label("Bağlantı başarılı · Çıkış IP: \(ip)", systemImage: "checkmark.circle.fill")
                                .font(AppFont.medium(12)).foregroundStyle(Theme.accent)
                        } else if let error = model.candidateError {
                            Label(error, systemImage: "xmark.circle.fill")
                                .font(AppFont.regular(12)).foregroundStyle(.red)
                        } else {
                            Text("Test, kurulu VPN bağlantısını değiştirmez.")
                                .font(AppFont.regular(12)).foregroundStyle(.secondary)
                        }
                        Button { model.probeProfile() } label: {
                            Label(model.candidateExitIP == nil ? "Bağlantıyı test et" : "Tekrar test et",
                                  systemImage: "play.fill")
                        }
                        .buttonStyle(AppActionButtonStyle(prominent: model.candidateExitIP == nil))
                        .disabled(model.busy)
                    }
                }
                if model.candidateExitIP != nil {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        StepHeader(number: 3, title: "Router'a kur", done: false, active: true)
                        Text("Bağlantı doğrulandı. Kurulumdan sonra Wi-Fi bu sunucuyu kullanır.")
                            .font(AppFont.regular(12)).foregroundStyle(.secondary)
                        Button { model.apply() } label: {
                            Label("Sunucuyu kur", systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(AppActionButtonStyle(prominent: true))
                        .disabled(model.busy)
                        .help("Kurulum sırasında sunucu yeniden doğrulanır; başarısızsa mevcut bağlantı korunur.")
                    }
                }
            }
        }
    }

    private var serversCard: some View {
        let nodes = model.status?.nodes ?? []
        return Card("Sunucular",
                    subtitle: isDirect ? "Normal internet etkin" : nil,
                    symbol: "server.rack",
                    accessory: { Badge(text: "30 dk'da ölçüm", color: .secondary) }) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Otomatik seçim").font(AppFont.semiBold(13))
                    Text("Erişilebilir en düşük ms")
                        .font(AppFont.regular(11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.status?.selectionMode == "unavailable" {
                    Badge(text: "Yardımcılar gerekli", color: .orange)
                } else if model.status?.selectionMode != "manual" {
                    Badge(text: "Açık", color: Theme.accent)
                } else {
                    Button("Otomatiğe dön") { model.selectNode() }
                        .disabled(model.busy || model.reachable != true)
                }
            }
            .padding(12)
            .background(Theme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if nodes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                    Text("Henüz sunucu listesi yok").font(AppFont.semiBold(13))
                    Text("Çoklu Shadowsocks profili ekle.")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(nodes) { node in
                        nodeRow(node)
                        if node.id != nodes.last?.id { Divider() }
                    }
                }
            }
            if nodes.count == 1 {
                Text("Diğer Shadowsocks sunucularını abonelikle ekle. Hysteria bu router'da çalışmaz.")
                    .font(AppFont.regular(11)).foregroundStyle(.secondary)
            }
            if let error = model.serverActionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.medium(12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup {
                Text("ms, sunucuya TCP bağlantı süresidir; VPN hızını göstermez. Otomatik seçim yalnızca VPN çıkışı doğrulanan sunuculara geçer. “Ulaşılamıyor”, ölçüm olmadığı veya TCP bağlantısı kurulamadığı anlamına gelir.")
                    .font(AppFont.regular(12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } label: {
                Text("Ölçüm bilgisi").font(AppFont.medium(12)).foregroundStyle(Theme.accent)
            }
        }
    }

    private func nodeRow(_ node: Node) -> some View {
        let alive = node.alive == true
        let delay = node.delay ?? 0
        let isBest = model.status?.best == node.tag && alive
        let isActive = model.status?.activeOutbound == node.tag
        let configured = node.configured == true || (node.configured == nil && isActive)
        return HStack(spacing: 12) {
            Circle().fill(alive ? latencyColor(delay) : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
            Text(node.name).font(AppFont.medium(13)).lineLimit(1)
            if isActive { Badge(text: "Aktif", color: Theme.accent) }
            if isBest { Badge(text: "En düşük ms", color: Theme.accent) }
            Spacer()
            if alive {
                Text("\(Int(delay)) ms")
                    .font(AppFont.semiBold(12)).monospacedDigit()
                    .frame(width: 75, alignment: .trailing)
            } else {
                Text("n/a").font(AppFont.regular(12)).foregroundStyle(.secondary)
                    .frame(width: 75, alignment: .trailing)
            }
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 48)
                    .accessibilityLabel("Etkin")
            } else if configured {
                Button("Seç") { model.selectNode(node.tag) }
                    .disabled(model.busy || model.reachable != true ||
                              model.status?.selectionMode == "unavailable")
                    .frame(width: 48)
            } else {
                Text("Profil gerekli")
                    .font(AppFont.medium(11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
    }

    private var subscriptionCard: some View {
        Card("Abonelik",
             subtitle: "Süre dolunca normal internete geçer.",
             symbol: "calendar",
             accessory: {
                 if let days = daysRemaining {
                     Badge(text: days == 0 ? "Süre doldu" : "\(days) gün kaldı", color: subscriptionTint)
                 }
             }) {
            HStack(spacing: 12) {
                DatePicker("Bitiş günü", selection: $model.expiration, displayedComponents: .date)
                    .datePickerStyle(.compact)
                Button { model.saveExpiry() } label: {
                    Label("Router'a kaydet", systemImage: "square.and.arrow.down")
                }
                .disabled(model.busy)
                Spacer()
            }
            if let days = daysRemaining, days <= 3 {
                Label("Yeni profil yükleyip bitiş tarihini güncelle.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.medium(12)).foregroundStyle(.orange)
            }
        }
    }

    private var diagnosticsCard: some View {
        Card {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button { model.loadLogs() } label: {
                            Label("Günlükleri yenile", systemImage: "arrow.clockwise")
                        }
                        Spacer()
                    }
                    if model.logs.isEmpty {
                        Text("Henüz günlük yüklenmedi.")
                            .font(AppFont.regular(12)).foregroundStyle(.secondary)
                    } else {
                        ScrollView([.horizontal, .vertical]) {
                            Text(model.logs)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 220)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Günlükler", systemImage: "doc.text.magnifyingglass")
                    .font(AppFont.semiBold(14))
            }
        }
    }

    // MARK: Router

    private var routerPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("İnternet modu").font(AppFont.bold(16))
                HStack(alignment: .top, spacing: 12) {
                    ModeCard(title: "VPN modu",
                             symbol: "checkmark.shield.fill", tint: Theme.accent,
                             selected: !isDirect && model.status != nil,
                             disabled: model.busy || model.status == nil || !vpnRunning) {
                        model.changeMode("vpn")
                    }
                    ModeCard(title: "Normal internet",
                             symbol: "network", tint: .blue,
                             selected: isDirect,
                             disabled: model.busy || model.status == nil) {
                        confirmDirect = true
                    }
                }
                if !isDirect && model.status != nil && !vpnRunning {
                    Label("VPN servisi çalışmıyor, bu yüzden VPN moduna şu an geçilemez.",
                          systemImage: "info.circle")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Trafik").font(AppFont.bold(16))
                    Spacer()
                    if let vpnBytes = model.status?.vpnBytes {
                        Label("VPN \(bytes((vpnBytes.rx ?? 0) + (vpnBytes.tx ?? 0)))",
                              systemImage: "shield.lefthalf.filled")
                            .font(AppFont.medium(12)).foregroundStyle(.secondary)
                    }
                }
                .help("Trafik sayaçları router yeniden başladığında sıfırlanır.")
                LazyVGrid(columns: columns, spacing: 12) {
                    StatCard(title: "Wi-Fi trafiği", value: bytes((model.status?.wifi.rx ?? 0) + (model.status?.wifi.tx ?? 0)),
                             caption: "", symbol: "wifi")
                    StatCard(title: "İnternet (WAN)", value: bytes((model.status?.wan.rx ?? 0) + (model.status?.wan.tx ?? 0)),
                             caption: "", symbol: "network")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sistem").font(AppFont.bold(16))
                    Spacer()
                    Label(uptimeText, systemImage: "clock")
                        .font(AppFont.medium(12)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    StatCard(title: "CPU", value: cpuText, caption: "", symbol: "cpu")
                    StatCard(title: "RAM", value: ramText, caption: ramDetail, symbol: "memorychip")
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                Text("Router yardımcıları").font(AppFont.bold(15))
                Spacer()
                Button {
                    model.helperUpdate = .idle
                    showHelpersSheet = true
                } label: {
                    Label("Yardımcıları güncelle", systemImage: "arrow.down.circle")
                }
                .disabled(model.busy)
                .help("Mevcut OpenWrt üzerindeki HappRouter betiklerini ve zamanlayıcıları günceller. Paket veya firmware yüklemez; VPN sunucu profilini değiştirmez.")
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))

            Card("Tanı yedekleri", subtitle: "Günlük · son 30 gün", symbol: "archivebox") {
                HStack(spacing: 10) {
                    Picker("Gün", selection: $model.selectedBackupDate) {
                        if model.backups.isEmpty {
                            Text("Yedek yok").tag("")
                        } else {
                            ForEach(model.backups) { entry in
                                Text(entry.date).tag(entry.date)
                            }
                        }
                    }
                    .frame(width: 190)
                    .disabled(model.backups.isEmpty || model.backupBusy)
                    Button("Göster") { model.openBackup() }
                        .disabled(model.selectedBackupDate.isEmpty || model.backupBusy)
                    Button("Günlüğü kaydet") { model.openBackup(export: true) }
                        .disabled(model.selectedBackupDate.isEmpty || model.backupBusy)
                    Spacer(minLength: 8)
                    if model.backupBusy { ProgressView().controlSize(.small) }
                    Button("Şimdi yedekle") { model.createBackup() }
                        .disabled(model.backupBusy)
                }
                if !model.backupLog.isEmpty {
                    Text(model.backupLogDate)
                        .font(AppFont.semiBold(12)).foregroundStyle(.secondary)
                    ScrollView([.horizontal, .vertical]) {
                        Text(model.backupLog)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                Text("Alan azalınca en eski yedekler otomatik silinir.")
                    .font(AppFont.regular(11)).foregroundStyle(.secondary)
            }
            .onAppear { model.loadBackups() }
        }
    }

    private var helperUpdateSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Router yardımcıları").font(AppFont.display(22))
                    Text("Mi Router 4C · 192.168.1.1")
                        .font(AppFont.regular(12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showHelpersSheet = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.busy)
                .accessibilityLabel("Kapat")
            }

            VStack(spacing: 0) {
                helperUpdateRow("Router kontrolü", detail: "Model ve OpenWrt bileşenleri", symbol: "checkmark.shield")
                Divider().padding(.leading, 44)
                helperUpdateRow("Yardımcı dosyalar", detail: "VPN, süre ve trafik betikleri", symbol: "square.stack.3d.up")
                Divider().padding(.leading, 44)
                helperUpdateRow("Ölçüm görevleri", detail: "Sunucu ve cihaz verileri", symbol: "chart.bar.xaxis")
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))

            helperUpdateFeedback

            HStack(spacing: 12) {
                Label("Mevcut VPN profili korunur", systemImage: "lock.shield")
                    .font(AppFont.medium(12)).foregroundStyle(.secondary)
                Spacer()
                switch model.helperUpdate {
                case .idle, .failure:
                    Button { model.install() } label: {
                        Label("Güncellemeyi başlat", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(AppActionButtonStyle(prominent: true))
                    .disabled(model.busy)
                case .running:
                    ProgressView().controlSize(.small)
                    Text("Güncelleniyor").font(AppFont.medium(12)).foregroundStyle(.secondary)
                case .success:
                    Button("Bitti") { showHelpersSheet = false }
                        .buttonStyle(AppActionButtonStyle(prominent: true))
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .font(AppFont.regular(14))
        .tint(Theme.accent)
        .interactiveDismissDisabled(model.busy)
    }

    private func helperUpdateRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.semiBold(13))
                Text(detail).font(AppFont.regular(11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder private var helperUpdateFeedback: some View {
        switch model.helperUpdate {
        case .idle:
            EmptyView()
        case .running:
            Label("Dosyalar router'a aktarılıyor. İşlem bitene kadar bekle.", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.accent)
        case .success(let detail):
            Label(detail, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        case .failure(let detail):
            Label(detail, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: Cihazlar

    private var sortedDevices: [Device] {
        (model.status?.devices ?? []).sorted {
            ($0.downloadToday ?? 0) > ($1.downloadToday ?? 0)
        }
    }

    private var connectedWifiDownloadToday: Int64 {
        sortedDevices.filter { $0.type == "Wi-Fi" }
            .reduce(0) { $0 + ($1.downloadToday ?? 0) }
    }

    private var offlineBlockedMACs: [String] {
        let connected = Set(sortedDevices.map { $0.mac.lowercased() })
        return (model.status?.blockedMACs ?? []).filter { !connected.contains($0) }
    }

    private func deviceSymbol(_ device: Device) -> String {
        if device.type != "Wi-Fi" { return "cable.connector" }
        let name = (device.name ?? "").lowercased()
        if name.contains("iphone") || name.contains("android") || name.contains("galaxy")
            || name.contains("xiaomi") || name.contains("redmi") || name.contains("pixel")
            || name.hasSuffix("-a34") || name == "a34" { return "iphone" }
        if name.contains("ipad") || name.contains("tablet") { return "ipad" }
        if name.contains("mac") || name.contains("book") || name.contains("pc") || name.contains("laptop") {
            return "laptopcomputer"
        }
        return "wifi"
    }

    private var devicesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card("IP adresleri", subtitle: "VPN çıkışı ve router'ın cihazlara verdiği yerel IPv4 adresleri.",
                 symbol: "network") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("İnternette görünen VPN IPv4")
                            .font(AppFont.regular(12)).foregroundStyle(.secondary)
                        Text(vpnExitText)
                            .font(AppFont.bold(model.exitIP == nil ? 15 : 20))
                            .textSelection(.enabled)
                        Text(vpnExitDetail)
                            .font(AppFont.regular(11))
                            .foregroundStyle(model.exitError == nil ? Color.secondary : Color.orange)
                    }
                    Spacer()
                    if !isDirect {
                        Button { model.test() } label: {
                            Label("IP'yi yenile", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.exitChecking || !vpnRunning)
                    }
                }
            }
            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(title: "Bağlı cihaz", value: "\(model.status?.devices.count ?? 0)",
                         caption: "", symbol: "laptopcomputer.and.iphone")
                StatCard(title: "Bağlı Wi-Fi indirmesi · bugün",
                         value: model.status == nil ? "—" : bytes(connectedWifiDownloadToday),
                         caption: "", symbol: "arrow.down.circle")
            }
            Card {
                if sortedDevices.isEmpty && offlineBlockedMACs.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(.secondary)
                        Text("Cihaz görünmüyor").font(AppFont.semiBold(14))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                } else {
                    VStack(spacing: 0) {
                        ForEach(sortedDevices) { device in
                            deviceRow(device)
                            if device.id != sortedDevices.last?.id || !offlineBlockedMACs.isEmpty {
                                Divider()
                            }
                        }
                        ForEach(offlineBlockedMACs, id: \.self) { mac in
                            offlineBlockedRow(mac)
                            if mac != offlineBlockedMACs.last { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func deviceRow(_ device: Device) -> some View {
        let isWifi = device.type == "Wi-Fi"
        let blocked = model.status?.blockedMACs.contains(device.mac.lowercased()) == true
        let live = model.deviceRates[device.mac]
        let maxToday = max(sortedDevices.compactMap(\.downloadToday).max() ?? 1, 1)
        let share = Double(device.downloadToday ?? 0) / Double(maxToday)
        let localIP = device.ip.flatMap { $0.isEmpty ? nil : $0 } ?? "Henüz görünmüyor"
        return HStack(spacing: 14) {
            Image(systemName: deviceSymbol(device))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.name?.isEmpty == false ? device.name! : "Bilinmeyen cihaz")
                        .font(AppFont.semiBold(13)).lineLimit(1)
                    Badge(text: isWifi ? "Wi-Fi" : "Kablolu", color: isWifi ? Theme.accent : .secondary)
                    if blocked { Badge(text: "Engelli", color: .red) }
                }
                Text("Yerel IPv4 · \(localIP)")
                    .font(AppFont.medium(11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            if isWifi, let live, live > 50 * 1024 {
                Badge(text: "↓ " + rate(live), color: Theme.accent)
            } else if isWifi {
                Text("↓ " + rate(live)).font(AppFont.regular(11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 5) {
                Text(device.downloadToday.map { bytes($0) } ?? "Veri yok")
                    .font(AppFont.semiBold(13)).monospacedDigit()
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Theme.accent).frame(width: max(4, 90 * share))
                }
                .frame(width: 90, height: 5)
                .opacity(device.downloadToday == nil ? 0 : 1)
            }
            .frame(width: 100, alignment: .trailing)
            Button {
                model.setDeviceBlocked(device.mac, blocked: !blocked)
            } label: {
                Label(blocked ? "Engeli kaldır" : "İnterneti engelle",
                      systemImage: blocked ? "lock.open" : "hand.raised")
            }
            .buttonStyle(AppActionButtonStyle(tint: blocked ? Theme.accent : .red,
                                              destructive: !blocked))
            .disabled(model.busy || model.reachable != true)
        }
        .padding(.vertical, 10)
    }

    private func offlineBlockedRow(_ mac: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Text(mac).font(AppFont.semiBold(13))
            Badge(text: "Engelli · çevrimdışı", color: .red)
            Spacer()
            Button("Engeli kaldır") { model.setDeviceBlocked(mac, blocked: false) }
                .buttonStyle(AppActionButtonStyle())
                .disabled(model.busy || model.reachable != true)
        }
        .padding(.vertical, 10)
    }

    // MARK: Yardımcılar

    private var daysRemaining: Int? {
        guard let expires = model.status?.expiresAt, expires > 0 else { return nil }
        return max(0, Int(ceil(Date(timeIntervalSince1970: TimeInterval(expires)).timeIntervalSinceNow / 86400)))
    }

    private var uptimeText: String {
        let seconds = Int(model.status?.uptimeSeconds ?? 0)
        if seconds >= 86400 { return "\(seconds / 86400) gün" }
        return seconds >= 3600 ? "\(seconds / 3600) saat" : "\(max(1, seconds / 60)) dk"
    }

    private var cpuText: String {
        guard let value = model.status?.cpuPercent else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var ramText: String {
        guard let used = model.status?.memoryUsedBytes,
              let total = model.status?.memoryTotalBytes, total > 0 else { return "—" }
        return "\(Int((Double(used) * 100 / Double(total)).rounded()))%"
    }

    private var ramDetail: String {
        guard let used = model.status?.memoryUsedBytes,
              let total = model.status?.memoryTotalBytes, total > 0 else { return "" }
        return "\(used / 1_048_576) / \(total / 1_048_576) MB"
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
            .defaultSize(width: 1040, height: 800)
            .windowStyle(.hiddenTitleBar)
    }
}
