import Cocoa
import WebKit

// MARK: - Data Models
struct Bucket: Codable {
    let id: String?
    let name: String
    let remaining_pct: Int
    let reset_in: String?
    let detail: String?
}

struct Group: Codable {
    let name: String
    let description: String?
    let provider: String?
    let buckets: [Bucket]
}

class UrlButton: NSButton {
    var targetUrl: String?
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

struct UpdateInfo: Codable {
    let current_version: String?
    let latest_version: String?
    let update_available: Bool?
    let download_url: String?
    let release_notes: String?
}

struct AnnouncementInfo: Codable {
    let id: String?
    let type: String? // "info", "versao", "publicidade"
    let badge: String?
    let title: String?
    let message: String?
    let action_label: String?
    let action_url: String?
    let image_url: String?
    let image_fit: String?
    let image_position: String?
    let image_scale: Double?
    let duracao_segundos: Int?
}

struct QuotaData: Codable {
    let account: String
    let plan: String?
    let providers_count: Int?
    let groups: [Group]
    let updated_at: String?
    var from_cache: Bool?
    var cache_age_seconds: Int?
    var timestamp: Double?
    var needs_setup: Bool?
    var version: String?
    var tier: String?
    var update: UpdateInfo?
    var announcement: AnnouncementInfo?
    var promo: AnnouncementInfo?
}

extension QuotaData {
    /// Fixed banner shown to FREE users only (independent from the dashboard-managed notice/toast).
    static let fixedFreeBanner = AnnouncementInfo(
        id: "fixed-free-help",
        type: "promo",
        badge: nil,
        title: "Help AI GAUGE developers team",
        message: "AI GAUGE is developed by independent developers. Support this initiative by making a donation of any amount.",
        action_label: "MAKE A DONATION!",
        action_url: "https://ai-gauge.vh2c.com.br/donate?mid={machine_id}",
        image_url: nil,
        image_fit: nil,
        image_position: nil,
        image_scale: nil,
        duracao_segundos: nil
    )

    /// Advertising toast: the API's `promo`, or (older API) an `announcement` of type "publicidade".
    var adPromo: AnnouncementInfo? {
        if let p = promo { return p }
        if let a = announcement, a.type == "publicidade" { return a }
        return nil
    }

    var isFreeTier: Bool {
        let t = (tier ?? "free").lowercased()
        return t != "pro" && t != "enterprise"
    }

    /// Top-of-window banners: the dashboard notice (version/info, never an ad) first, then the fixed FREE banner.
    var banners: [AnnouncementInfo] {
        var list: [AnnouncementInfo] = []
        let fixedTitle = (QuotaData.fixedFreeBanner.title ?? "").lowercased()
        if let ann = announcement, ann.type != "publicidade",
           let msg = ann.message, !msg.isEmpty,
           (ann.title ?? "").lowercased() != fixedTitle {
            list.append(ann)
        }
        if isFreeTier { list.append(QuotaData.fixedFreeBanner) }
        return list
    }
}

struct GaugeSection {
    let name: String
    let subtitle: String?
    let tag: String // "ANTIGRAVITY", "AI STUDIO", "OPENAI", "CLAUDE"
    let accentColor: NSColor
    var items: [GaugeItem]
}

struct GaugeItem {
    let id: String
    let title: String
    let modelName: String
    let percentage: Int
    let resetIn: String?
    let detail: String?
    let provider: String?
    let sectionTag: String
}

struct ProviderConfig: Codable {
    var enabled: Bool?
    var api_key: String?
    var token: String?
}

struct AppConfig: Codable {
    var providers: [String: ProviderConfig]?
    var refresh_interval_seconds: Int?
    var hidden_hud_gauges: [String]?
    var onboarding_completed: Bool?
    var section_colors: [String: String]?
}

struct PastelColor {
    let name: String
    let hex: String
    let color: NSColor
}

struct PastelTheme {
    static let palette: [PastelColor] = [
        PastelColor(name: "Sky Blue", hex: "#8FBCFF", color: NSColor(srgbRed: 0x8F/255.0, green: 0xBC/255.0, blue: 0xFF/255.0, alpha: 1.0)),
        PastelColor(name: "Mint", hex: "#8AE39A", color: NSColor(srgbRed: 0x8A/255.0, green: 0xE3/255.0, blue: 0x9A/255.0, alpha: 1.0)),
        PastelColor(name: "Coral", hex: "#FF5265", color: NSColor(srgbRed: 0xFF/255.0, green: 0x52/255.0, blue: 0x65/255.0, alpha: 1.0)),
        PastelColor(name: "Terracotta", hex: "#D78C68", color: NSColor(srgbRed: 0xD7/255.0, green: 0x8C/255.0, blue: 0x68/255.0, alpha: 1.0)),
        PastelColor(name: "Lavender", hex: "#C084FC", color: NSColor(srgbRed: 0xC0/255.0, green: 0x84/255.0, blue: 0xFC/255.0, alpha: 1.0)),
        PastelColor(name: "Cyan", hex: "#67E8F9", color: NSColor(srgbRed: 0x67/255.0, green: 0xE8/255.0, blue: 0xF9/255.0, alpha: 1.0))
    ]
    
    static let defaultColors: [String: String] = [
        "antigravity": "#8FBCFF",
        "claude_pro": "#D78C68",
        "chatgpt_subscription": "#8AE39A",
        "cursor": "#C084FC",
        "github_copilot": "#FF5265",
        "gemini": "#67E8F9"
    ]
    
    static func parseColor(hex: String?, fallbackHex: String) -> NSColor {
        let h = (hex?.isEmpty == false) ? hex! : fallbackHex
        var str = h.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        if str.count == 6 {
            let r = Double(Int(str.prefix(2), radix: 16) ?? 0) / 255.0
            let g = Double(Int(str.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255.0
            let b = Double(Int(str.suffix(2), radix: 16) ?? 0) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        }
        return NSColor.white
    }
    
    static func getColor(for key: String, in colors: [String: String]?) -> NSColor {
        let fallback = defaultColors[key] ?? "#8FBCFF"
        let chosen = colors?[key]
        return parseColor(hex: chosen, fallbackHex: fallback)
    }
}

extension QuotaData {
    var gaugeSections: [GaugeSection] {
        var sections: [GaugeSection] = []
        let customColors = QuotaManager.loadConfig().section_colors
        let antiColor = PastelTheme.getColor(for: "antigravity", in: customColors)
        let claudeColor = PastelTheme.getColor(for: "claude_pro", in: customColors)
        let chatgptColor = PastelTheme.getColor(for: "chatgpt_subscription", in: customColors)
        let cursorColor = PastelTheme.getColor(for: "cursor", in: customColors)
        let copilotColor = PastelTheme.getColor(for: "github_copilot", in: customColors)
        let geminiColor = PastelTheme.getColor(for: "gemini", in: customColors)
        let openColor = PastelTheme.getColor(for: "openai", in: customColors)
        let antColor = PastelTheme.getColor(for: "anthropic", in: customColors)
        
        var antiGroups: [Group] = []
        var claudeProGroups: [Group] = []
        var chatgptGroups: [Group] = []
        var cursorGroups: [Group] = []
        var copilotGroups: [Group] = []
        var studioGroups: [Group] = []
        var openGroups: [Group] = []
        var antGroups: [Group] = []
        var otherGroups: [Group] = []
        
        for g in groups {
            let p = (g.provider ?? "").lowercased()
            let n = g.name.lowercased()
            if n.contains("claude and gpt") || p.contains("antigravity") || n.contains("antigravity") || n.contains("argon") {
                antiGroups.append(g)
            } else if p.contains("claude") || n.contains("claude") {
                claudeProGroups.append(g)
            } else if p.contains("chatgpt") || n.contains("chatgpt") {
                chatgptGroups.append(g)
            } else if p.contains("cursor") || n.contains("cursor") {
                cursorGroups.append(g)
            } else if p.contains("copilot") || n.contains("copilot") || p.contains("github") {
                copilotGroups.append(g)
            } else if p.contains("studio") || p == "gemini" || p == "gemini_api" || n.contains("google gemini api") || n.contains("ai studio") {
                studioGroups.append(g)
            } else if p.contains("openai") || n.contains("openai") {
                openGroups.append(g)
            } else if p.contains("anthropic") || n.contains("anthropic") {
                antGroups.append(g)
            } else {
                otherGroups.append(g)
            }
        }
        
        if !antiGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in antiGroups {
                let modelLabel: String
                let lowerG = g.name.lowercased()
                if lowerG.contains("gemini 4") || lowerG.contains("argon") {
                    modelLabel = "Argon"
                } else if lowerG.contains("claude") || lowerG.contains("gpt") {
                    modelLabel = "Claude/GPT"
                } else {
                    modelLabel = "Gemini"
                }
                for b in g.buckets {
                    let limitTitle: String
                    let lowerB = b.name.lowercased()
                    if lowerB.contains("five") || lowerB.contains("5") {
                        limitTitle = "5 hours Limit"
                    } else {
                        limitTitle = "Weekly Limit"
                    }
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: limitTitle,
                        modelName: modelLabel,
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "ANTIGRAVITY"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Antigravity",
                subtitle: "Live & Headless",
                tag: "ANTIGRAVITY",
                accentColor: antiColor,
                items: items
            ))
        }
        
        if !claudeProGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in claudeProGroups {
                for b in g.buckets {
                    let limitTitle: String
                    let lowerB = b.name.lowercased()
                    let bId = (b.id ?? "").lowercased()
                    if lowerB.contains("5") || bId.contains("5h") {
                        limitTitle = "5 hours Limit"
                    } else {
                        limitTitle = "Weekly Limit"
                    }
                    items.append(GaugeItem(
                        id: b.id ?? "claude-pro",
                        title: limitTitle,
                        modelName: "Claude",
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "CLAUDE_PRO"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Claude",
                subtitle: "Desktop Session",
                tag: "CLAUDE_PRO",
                accentColor: claudeColor,
                items: items
            ))
        }
        
        if !chatgptGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in chatgptGroups {
                for b in g.buckets {
                    let limitTitle: String
                    let lowerB = b.name.lowercased()
                    let bId = (b.id ?? "").lowercased()
                    if lowerB.contains("3") || bId.contains("3h") || bId.contains("4o") {
                        limitTitle = "3 hours Limit"
                    } else {
                        limitTitle = "Weekly Limit"
                    }
                    items.append(GaugeItem(
                        id: b.id ?? "chatgpt-sub",
                        title: limitTitle,
                        modelName: bId.contains("o1") ? "o1 Reasoning" : "GPT-4o",
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "CHATGPT"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "ChatGPT",
                subtitle: "Web Session",
                tag: "CHATGPT",
                accentColor: chatgptColor,
                items: items
            ))
        }
        
        if !cursorGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in cursorGroups {
                for b in g.buckets {
                    let limitTitle: String
                    let lowerB = b.name.lowercased()
                    if lowerB.contains("fast") || lowerB.contains("claude") {
                        limitTitle = "Fast Requests"
                    } else {
                        limitTitle = "Monthly Cycle"
                    }
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: limitTitle,
                        modelName: "Cursor Pro",
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "CURSOR"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Cursor",
                subtitle: "Cursor IDE",
                tag: "CURSOR",
                accentColor: cursorColor,
                items: items
            ))
        }
        
        if !copilotGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in copilotGroups {
                for b in g.buckets {
                    let limitTitle: String
                    let lowerB = b.name.lowercased()
                    if lowerB.contains("chat") || lowerB.contains("model") {
                        limitTitle = "Copilot Chat"
                    } else {
                        limitTitle = "Completions"
                    }
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: limitTitle,
                        modelName: "Copilot",
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "COPILOT"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Copilot",
                subtitle: "VS Code",
                tag: "COPILOT",
                accentColor: copilotColor,
                items: items
            ))
        }
        
        if !studioGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in studioGroups {
                for b in g.buckets {
                    let limitTitle: String
                    let modelLabel: String
                    let lowerB = b.name.lowercased()
                    let bId = (b.id ?? "").lowercased()
                    if lowerB.contains("flash") || bId.contains("flash") {
                        limitTitle = "Flash RPM"
                        modelLabel = "Gemini Flash"
                    } else if lowerB.contains("pro") || bId.contains("pro") {
                        limitTitle = "Pro RPM"
                        modelLabel = "Gemini Pro"
                    } else {
                        limitTitle = "API Key"
                        modelLabel = "Gemini"
                    }
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: limitTitle,
                        modelName: modelLabel,
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "STUDIO"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Gemini",
                subtitle: "Gemini API",
                tag: "AI STUDIO",
                accentColor: geminiColor,
                items: items
            ))
        }
        
        if !openGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in openGroups {
                for b in g.buckets {
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: "TPM / RPM",
                        modelName: "OpenAI",
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "OPENAI"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "OpenAI API",
                subtitle: "GPT Models",
                tag: "OPENAI",
                accentColor: openColor,
                items: items
            ))
        }
        
        if !antGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in antGroups {
                for b in g.buckets {
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: "Rate Limit",
                        modelName: "Claude API",
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "CLAUDE"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Anthropic Claude",
                subtitle: "Claude API",
                tag: "CLAUDE",
                accentColor: antColor,
                items: items
            ))
        }
        
        if !otherGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in otherGroups {
                for b in g.buckets {
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: b.name,
                        modelName: g.name,
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "OTHER"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Outros Provedores",
                subtitle: nil,
                tag: "OUTROS",
                accentColor: NSColor(white: 0.7, alpha: 1.0),
                items: items
            ))
        }
        
        return sections
    }
    
    var gaugeItems: [GaugeItem] {
        return gaugeSections.flatMap { $0.items }
    }
}

// MARK: - Quota Manager
class QuotaManager {
    static let appSupportDir: String = {
        let path = NSString(string: "~/Library/Application Support/UniversalAIQuota").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()
    
    static var cachePath: String {
        return (appSupportDir as NSString).appendingPathComponent("quota_cache.json")
    }
    
    static var configDir: String {
        let path = NSString(string: "~/.config/UniversalAIQuota").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }
    
    static var configPath: String {
        return (configDir as NSString).appendingPathComponent("config.json")
    }
    
    static func hasAntigravity() -> Bool {
        let appPath = "/Applications/Antigravity.app"
        let geminiAnti = NSString(string: "~/.gemini/antigravity").expandingTildeInPath
        if FileManager.default.fileExists(atPath: appPath) || FileManager.default.fileExists(atPath: geminiAnti) {
            return true
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-i", "Antigravity"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func hasClaudePro() -> Bool {
        if hasClaudeProKeychainSession() { return true }
        let claudeDir = NSString(string: "~/.claude").expandingTildeInPath
        let claudeApp = "/Applications/Claude.app"
        return FileManager.default.fileExists(atPath: claudeDir) || FileManager.default.fileExists(atPath: claudeApp)
    }
    
    static func hasChatGPT() -> Bool {
        if hasChatGPTKeychainSession() { return true }
        let chatgptApp = "/Applications/ChatGPT.app"
        return FileManager.default.fileExists(atPath: chatgptApp)
    }
    
    static func hasGemini() -> Bool {
        let cfg = loadConfig()
        if let key = cfg.providers?["gemini"]?.api_key, !key.isEmpty { return true }
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty { return true }
        return false
    }
    
    static func hasCursor() -> Bool {
        let appPath = "/Applications/Cursor.app"
        let cursorDir = NSString(string: "~/Library/Application Support/Cursor").expandingTildeInPath
        if FileManager.default.fileExists(atPath: appPath) || FileManager.default.fileExists(atPath: cursorDir) {
            return true
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-i", "Cursor"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func hasCopilot() -> Bool {
        let vsApp = "/Applications/Visual Studio Code.app"
        let copilotStorage = NSString(string: "~/Library/Application Support/Code/User/globalStorage/github.copilot-chat").expandingTildeInPath
        return FileManager.default.fileExists(atPath: vsApp) || FileManager.default.fileExists(atPath: copilotStorage)
    }
    
    static func hasClaudeProKeychainSession() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-a", NSUserName(), "-w", "-s", "Claude Code-credentials"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func hasChatGPTKeychainSession() -> Bool {
        let codexAuth = NSString(string: "~/.codex/auth.json").expandingTildeInPath
        if FileManager.default.fileExists(atPath: codexAuth) { return true }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-a", NSUserName(), "-w", "-s", "ChatGPT-credentials"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func loadConfig() -> AppConfig {
        var cfg: AppConfig
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            cfg = decoded
        } else {
            cfg = AppConfig(
                providers: [
                    "antigravity": ProviderConfig(enabled: true, api_key: nil, token: nil),
                    "claude_pro": ProviderConfig(enabled: true, api_key: nil, token: nil),
                    "chatgpt_subscription": ProviderConfig(enabled: true, api_key: nil, token: nil),
                    "gemini": ProviderConfig(enabled: false, api_key: "", token: nil),
                    "openai": ProviderConfig(enabled: false, api_key: "", token: nil),
                    "anthropic": ProviderConfig(enabled: false, api_key: "", token: nil)
                ],
                refresh_interval_seconds: 30,
                hidden_hud_gauges: []
            )
        }
        if cfg.providers?["claude_pro"] == nil {
            if cfg.providers == nil { cfg.providers = [:] }
            cfg.providers?["claude_pro"] = ProviderConfig(enabled: true, api_key: nil, token: nil)
        }
        if cfg.providers?["chatgpt_subscription"] == nil {
            if cfg.providers == nil { cfg.providers = [:] }
            cfg.providers?["chatgpt_subscription"] = ProviderConfig(enabled: true, api_key: nil, token: nil)
        }
        if cfg.providers?["cursor"] == nil {
            if cfg.providers == nil { cfg.providers = [:] }
            cfg.providers?["cursor"] = ProviderConfig(enabled: true, api_key: nil, token: nil)
        }
        if cfg.providers?["github_copilot"] == nil {
            if cfg.providers == nil { cfg.providers = [:] }
            cfg.providers?["github_copilot"] = ProviderConfig(enabled: true, api_key: nil, token: nil)
        }
        if cfg.hidden_hud_gauges == nil {
            cfg.hidden_hud_gauges = []
        }
        return cfg
    }
    
    static func saveConfig(_ cfg: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(cfg) {
            try? data.write(to: URL(fileURLWithPath: configPath))
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configDir)
        }
    }
    
    static var engineScript: String {
        let bundlePath = Bundle.main.bundlePath
        let candidate1 = (bundlePath as NSString).appendingPathComponent("Contents/Resources/core/engine.js")
        if FileManager.default.fileExists(atPath: candidate1) { return candidate1 }
        
        let candidate2 = NSString(string: "~/.gemini/antigravity/scratch/universal-ai-quota-monitor/core/engine.js").expandingTildeInPath
        if FileManager.default.fileExists(atPath: candidate2) { return candidate2 }
        
        return NSString(string: "~/universal-ai-quota-monitor/core/engine.js").expandingTildeInPath
    }
    
    static func findNodeBinary() -> String {
        let fileManager = FileManager.default
        let wellKnownPaths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            "/bin/node"
        ]
        for path in wellKnownPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        let nvmBase = NSString(string: "~/.nvm/versions/node").expandingTildeInPath
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmBase) {
            for v in versions.sorted().reversed() {
                let candidate = (nvmBase as NSString).appendingPathComponent("\(v)/bin/node")
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return "node"
    }
    
    static func loadQuota(force: Bool = false, maxRetries: Int = 3) -> QuotaData? {
        if !force {
            if let cached = readCache(), let ts = cached.timestamp, (Date().timeIntervalSince1970 - ts) < 30 {
                var c = cached
                c.from_cache = true
                c.cache_age_seconds = Int(Date().timeIntervalSince1970 - ts)
                return c
            }
        }
        
        for attempt in 1...maxRetries {
            if let live = fetchLive() {
                return live
            }
            if attempt < maxRetries {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        
        if let cached = readCache() {
            return cached
        }
        return nil
    }
    
    static func readCache() -> QuotaData? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)) else { return nil }
        return try? JSONDecoder().decode(QuotaData.self, from: data)
    }
    
    static func fetchLive() -> QuotaData? {
        let nodeBin = findNodeBinary()
        let task = Process()
        if nodeBin.hasPrefix("/") {
            task.executableURL = URL(fileURLWithPath: nodeBin)
            task.arguments = [engineScript]
        } else {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["node", engineScript]
        }
        
        var env = ProcessInfo.processInfo.environment
        var searchPaths: [String] = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let nvmBase = NSString(string: "~/.nvm/versions/node").expandingTildeInPath
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            for v in versions.sorted().reversed() {
                searchPaths.append((nvmBase as NSString).appendingPathComponent("\(v)/bin"))
            }
        }
        if let currentPath = env["PATH"] {
            searchPaths.append(currentPath)
        }
        env["PATH"] = searchPaths.joined(separator: ":")
        env["HOME"] = NSHomeDirectory()
        env["USER"] = NSUserName()
        task.environment = env
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if task.terminationStatus == 0, let quota = try? JSONDecoder().decode(QuotaData.self, from: data) {
                if let ad = quota.adPromo {
                    PromoDockManager.shared.presentIfNeeded(ad)
                }
                var qWithTs = quota
                qWithTs.timestamp = Date().timeIntervalSince1970
                if let encoded = try? JSONEncoder().encode(qWithTs) {
                    try? encoded.write(to: URL(fileURLWithPath: cachePath))
                }
                return qWithTs
            }
        } catch {
            print("Fetch error: \(error)")
        }
        return nil
    }
}

// MARK: - Tachometer Gauge View
class TachometerGaugeView: NSView {
    var item: GaugeItem
    
    init(item: GaugeItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 88, height: 96))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let cx = bounds.midX
        let cy: CGFloat = 52.0
        let radius: CGFloat = 34.0
        let center = CGPoint(x: cx, y: cy)
        
        let startAngleDeg: Double = 220.0
        let endAngleDeg: Double = -40.0
        let totalSweepDeg: Double = 260.0
        
        let toRad = { (deg: Double) -> Double in deg * Double.pi / 180.0 }
        
        // 1. Fundo do dial circular
        let dialBgRect = CGRect(x: cx - radius - 5, y: cy - radius - 5, width: (radius + 5) * 2, height: (radius + 5) * 2)
        context.setFillColor(NSColor(srgbRed: 0x14/255.0, green: 0x14/255.0, blue: 0x15/255.0, alpha: 0.95).cgColor)
        context.fillEllipse(in: dialBgRect)
        
        // 2. Trilho do Tacômetro
        let trackPath = CGMutablePath()
        trackPath.addArc(
            center: center,
            radius: radius,
            startAngle: CGFloat(toRad(startAngleDeg)),
            endAngle: CGFloat(toRad(endAngleDeg)),
            clockwise: true
        )
        context.setStrokeColor(NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2D/255.0, alpha: 1.0).cgColor)
        context.setLineWidth(5.5)
        context.setLineCap(.round)
        context.addPath(trackPath)
        context.strokePath()
        
        // 3. Ticks e Graduações
        let numTicks = 24
        for i in 0...numTicks {
            let frac = Double(i) / Double(numTicks)
            let angleDeg = startAngleDeg - frac * totalSweepDeg
            let rad = toRad(angleDeg)
            let isMajor = (i % 6 == 0)
            let tickLen: CGFloat = isMajor ? 5.0 : 3.0
            let rInner = radius - 3.5
            let rOuter = rInner - tickLen
            
            let p1 = CGPoint(x: cx + CGFloat(cos(rad)) * rInner, y: cy + CGFloat(sin(rad)) * rInner)
            let p2 = CGPoint(x: cx + CGFloat(cos(rad)) * rOuter, y: cy + CGFloat(sin(rad)) * rOuter)
            
            let tickColor = isMajor
                ? NSColor(white: 0.55, alpha: 0.85).cgColor
                : NSColor(white: 0.32, alpha: 0.50).cgColor
            context.setStrokeColor(tickColor)
            context.setLineWidth(isMajor ? 1.2 : 0.8)
            context.strokeLineSegments(between: [p1, p2])
        }
        
        // 4. Arco Preenchido Dinâmico
        let pct = Double(min(max(item.percentage, 0), 100))
        let sweepPctDeg = (pct / 100.0) * totalSweepDeg
        let currentAngleDeg = startAngleDeg - sweepPctDeg
        
        let customColors = QuotaManager.loadConfig().section_colors
        let colorHealthy: NSColor
        if item.sectionTag == "STUDIO" || item.sectionTag == "AI STUDIO" || item.sectionTag == "GEMINI" {
            colorHealthy = PastelTheme.getColor(for: "gemini", in: customColors)
        } else if item.sectionTag == "CLAUDE_PRO" {
            colorHealthy = PastelTheme.getColor(for: "claude_pro", in: customColors)
        } else if item.sectionTag == "CHATGPT" {
            colorHealthy = PastelTheme.getColor(for: "chatgpt_subscription", in: customColors)
        } else if item.sectionTag == "CURSOR" {
            colorHealthy = PastelTheme.getColor(for: "cursor", in: customColors)
        } else if item.sectionTag == "COPILOT" {
            colorHealthy = PastelTheme.getColor(for: "github_copilot", in: customColors)
        } else if item.sectionTag == "OPENAI" {
            colorHealthy = PastelTheme.getColor(for: "openai", in: customColors)
        } else if item.sectionTag == "CLAUDE" {
            colorHealthy = PastelTheme.getColor(for: "anthropic", in: customColors)
        } else {
            colorHealthy = PastelTheme.getColor(for: "antigravity", in: customColors)
        }
        let colorYellow = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
        let colorRed = NSColor(srgbRed: 0xFF/255.0, green: 0x4D/255.0, blue: 0x4F/255.0, alpha: 1.0)
        
        let activeColor: NSColor
        if pct >= 50.0 {
            activeColor = colorHealthy
        } else if pct >= 20.0 {
            activeColor = colorYellow
        } else {
            activeColor = colorRed
        }
        
        if sweepPctDeg > 1.0 {
            let activePath = CGMutablePath()
            activePath.addArc(
                center: center,
                radius: radius,
                startAngle: CGFloat(toRad(startAngleDeg)),
                endAngle: CGFloat(toRad(currentAngleDeg)),
                clockwise: true
            )
            context.setStrokeColor(activeColor.cgColor)
            context.setLineWidth(5.5)
            context.setLineCap(.round)
            context.addPath(activePath)
            context.strokePath()
        }
        
        // 5. Ponteiro / Agulha Estilo Tacômetro
        let needleAngleRad = toRad(currentAngleDeg)
        let needleLen = radius - 8.0
        let tipPoint = CGPoint(
            x: cx + CGFloat(cos(needleAngleRad)) * needleLen,
            y: cy + CGFloat(sin(needleAngleRad)) * needleLen
        )
        let baseAngle1 = needleAngleRad + Double.pi / 2.0
        let baseAngle2 = needleAngleRad - Double.pi / 2.0
        let baseR: CGFloat = 2.5
        let baseP1 = CGPoint(x: cx + CGFloat(cos(baseAngle1)) * baseR, y: cy + CGFloat(sin(baseAngle1)) * baseR)
        let baseP2 = CGPoint(x: cx + CGFloat(cos(baseAngle2)) * baseR, y: cy + CGFloat(sin(baseAngle2)) * baseR)
        
        let needlePath = CGMutablePath()
        needlePath.move(to: baseP1)
        needlePath.addLine(to: tipPoint)
        needlePath.addLine(to: baseP2)
        needlePath.closeSubpath()
        
        context.setFillColor(NSColor(white: 0.95, alpha: 0.95).cgColor)
        context.addPath(needlePath)
        context.fillPath()
        
        // Hub central
        let hubRect = CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8)
        context.setFillColor(NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2E/255.0, alpha: 1.0).cgColor)
        context.fillEllipse(in: hubRect)
        context.setStrokeColor(activeColor.cgColor)
        context.setLineWidth(1.2)
        context.strokeEllipse(in: hubRect)
        
        // 6. Texto Curvado Superior
        drawCurvedText(
            text: item.title.uppercased(),
            center: center,
            radius: radius + 7.0,
            startAngleRad: toRad(170.0),
            totalSweepRad: toRad(160.0),
            context: context
        )
        
        // 7. Porcentagem no Centro Inferior
        let pctStr = "\(item.percentage)%" as NSString
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let pctSize = pctStr.size(withAttributes: pctAttrs)
        pctStr.draw(at: CGPoint(x: cx - pctSize.width / 2.0, y: cy - 23.0), withAttributes: pctAttrs)
        
        // 8. Nome do Modelo e Reset Inferior
        let modelStr = item.modelName as NSString
        let modelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor(white: 0.70, alpha: 1.0)
        ]
        let mSize = modelStr.size(withAttributes: modelAttrs)
        modelStr.draw(at: CGPoint(x: cx - mSize.width / 2.0, y: 12.0), withAttributes: modelAttrs)
        
        if let reset = item.resetIn, !reset.isEmpty {
            let rStr = reset as NSString
            let rAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .regular),
                .foregroundColor: NSColor(white: 0.50, alpha: 1.0)
            ]
            let rSize = rStr.size(withAttributes: rAttrs)
            rStr.draw(at: CGPoint(x: cx - rSize.width / 2.0, y: 1.0), withAttributes: rAttrs)
        }
    }
    
    private func drawCurvedText(text: String, center: CGPoint, radius: CGFloat, startAngleRad: Double, totalSweepRad: Double, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.0, weight: .semibold),
            .foregroundColor: NSColor(white: 0.45, alpha: 0.9)
        ]
        let chars = Array(text)
        guard !chars.isEmpty else { return }
        
        var totalWidth: CGFloat = 0
        var charWidths: [CGFloat] = []
        for ch in chars {
            let sz = String(ch).size(withAttributes: attrs)
            charWidths.append(sz.width)
            totalWidth += sz.width
        }
        
        let perimeterSpan = radius * CGFloat(totalSweepRad)
        let spacing = (perimeterSpan - totalWidth) / CGFloat(max(chars.count - 1, 1))
        
        var currentAngle = startAngleRad
        let charHeight: CGFloat = 7.0
        
        for (i, ch) in chars.enumerated() {
            let w = charWidths[i]
            let charAngle = Double(w + spacing) / Double(radius)
            let midAngle = currentAngle - (charAngle / 2.0)
            
            context.saveGState()
            let x = center.x + CGFloat(cos(midAngle)) * radius
            let y = center.y + CGFloat(sin(midAngle)) * radius
            
            context.translateBy(x: x, y: y)
            context.rotate(by: CGFloat(midAngle - Double.pi / 2.0))
            
            let chStr = String(ch) as NSString
            chStr.draw(at: CGPoint(x: -w / 2.0, y: -charHeight / 2.0), withAttributes: attrs)
            context.restoreGState()
            
            currentAngle -= charAngle
        }
    }
}

// MARK: - HUD Container View
class HudContainerView: NSView {
    weak var delegate: AppDelegate?
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "m" {
                delegate?.switchToFullMode()
                return
            } else if event.charactersIgnoringModifiers == "o" {
                delegate?.toggleHudOrientation()
                return
            } else if event.charactersIgnoringModifiers == "r" {
                delegate?.refreshClicked()
                return
            } else if event.charactersIgnoringModifiers == "," {
                delegate?.openSettings()
                return
            }
        }
        if event.keyCode == 53 {
            delegate?.closeClicked()
            return
        }
        super.keyDown(with: event)
    }
}

enum DisplayMode: String {
    case full
    case hud
}

enum HudOrientation: String {
    case vertical
    case horizontal
}

class FlippedContentView: NSView {
    override var isFlipped: Bool { return true }
}

class FlippedBox: NSView {
    override var isFlipped: Bool { return true }
    
    var boxType: NSBox.BoxType = .custom
    
    var fillColor: NSColor = .clear {
        didSet {
            wantsLayer = true
            layer?.backgroundColor = fillColor.cgColor
        }
    }
    
    var borderColor: NSColor = .clear {
        didSet {
            wantsLayer = true
            layer?.borderColor = borderColor.cgColor
        }
    }
    
    var borderWidth: CGFloat = 0 {
        didSet {
            wantsLayer = true
            layer?.borderWidth = borderWidth
        }
    }
    
    var cornerRadius: CGFloat = 0 {
        didSet {
            wantsLayer = true
            layer?.cornerRadius = cornerRadius
            layer?.masksToBounds = true
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
}

class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds theRect: NSRect) -> NSRect {
        var r = theRect
        let textSize = cellSize(forBounds: theRect)
        let delta = (theRect.size.height - textSize.height) / 2.0
        if delta > 0 {
            r.origin.y += delta.rounded()
            r.size.height = textSize.height
        }
        r.origin.x += 12.0
        r.size.width = max(theRect.size.width - 24.0, 10.0)
        return r
    }
    
    override func titleRect(forBounds theRect: NSRect) -> NSRect {
        return drawingRect(forBounds: theRect)
    }
    
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
    
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

func makeCenteredDarkField(frame: NSRect, placeholder: String, value: String) -> NSTextField {
    let field = NSTextField(frame: frame)
    field.cell = VerticallyCenteredTextFieldCell(textCell: value)
    field.isBordered = false
    field.focusRingType = .none
    field.wantsLayer = true
    field.backgroundColor = NSColor(srgbRed: 0x14/255.0, green: 0x14/255.0, blue: 0x16/255.0, alpha: 1.0)
    field.textColor = .white
    field.font = NSFont.systemFont(ofSize: 12.0)
    field.layer?.borderColor = NSColor(srgbRed: 0x2E/255.0, green: 0x2E/255.0, blue: 0x33/255.0, alpha: 1.0).cgColor
    field.layer?.borderWidth = 1.0
    field.layer?.cornerRadius = 6.0
    field.placeholderAttributedString = NSAttributedString(
        string: placeholder,
        attributes: [
            .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 12.0)
        ]
    )
    field.stringValue = value
    return field
}

func makeCenteredDarkSecureField(frame: NSRect, placeholder: String, value: String) -> NSSecureTextField {
    let field = NSSecureTextField(frame: frame)
    field.isBordered = false
    field.focusRingType = .none
    field.wantsLayer = true
    field.backgroundColor = NSColor(srgbRed: 0x14/255.0, green: 0x14/255.0, blue: 0x16/255.0, alpha: 1.0)
    field.textColor = .white
    field.font = NSFont.systemFont(ofSize: 12.0)
    field.layer?.borderColor = NSColor(srgbRed: 0x2E/255.0, green: 0x2E/255.0, blue: 0x33/255.0, alpha: 1.0).cgColor
    field.layer?.borderWidth = 1.0
    field.layer?.cornerRadius = 6.0
    field.placeholderAttributedString = NSAttributedString(
        string: placeholder,
        attributes: [
            .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 12.0)
        ]
    )
    field.stringValue = value
    return field
}

class ContrastCheckbox: NSButton {
    var checkAccentColor: NSColor = NSColor(srgbRed: 0x0A/255.0, green: 0x84/255.0, blue: 0xFF/255.0, alpha: 1.0)
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?
    
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    
    override var state: NSControl.StateValue {
        didSet {
            needsDisplay = true
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        self.isBordered = false
        self.wantsLayer = true
        self.focusRingType = .none
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        state = (state == .on) ? .off : .on
        needsDisplay = true
        if let action = action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.characters == " " {
            guard isEnabled else { return }
            state = (state == .on) ? .off : .on
            needsDisplay = true
            if let action = action {
                NSApp.sendAction(action, to: target, from: self)
            }
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let boxSize: CGFloat = min(16, max(14, bounds.height - 4))
        let boxY = (bounds.height - boxSize) / 2.0
        let boxX: CGFloat = 1.0
        let boxRect = NSRect(x: boxX, y: boxY, width: boxSize, height: boxSize)
        let cornerRadius: CGFloat = 3.5
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        let isChecked = (state == .on)
        
        if isChecked {
            // Marcado: fundo de destaque + borda refinada + checkmark branco puro
            checkAccentColor.setFill()
            boxPath.fill()
            
            let strokeColor = isHovered ? NSColor.white : (checkAccentColor.blended(withFraction: 0.25, of: .white) ?? checkAccentColor)
            strokeColor.setStroke()
            boxPath.lineWidth = 1.2
            boxPath.stroke()
            
            let check = NSBezierPath()
            check.move(to: NSPoint(x: boxRect.minX + boxSize * 0.22, y: boxRect.minY + boxSize * 0.50))
            check.line(to: NSPoint(x: boxRect.minX + boxSize * 0.44, y: boxRect.minY + boxSize * 0.74))
            check.line(to: NSPoint(x: boxRect.minX + boxSize * 0.78, y: boxRect.minY + boxSize * 0.26))
            check.lineWidth = 2.0
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            // DESMARCADO: ALTO CONTRASTE - Fundo escuro visível + Borda de aço/platina bem destacada
            let bgFill = isHovered
                ? NSColor(srgbRed: 0x36/255.0, green: 0x3E/255.0, blue: 0x4D/255.0, alpha: 1.0)
                : NSColor(srgbRed: 0x22/255.0, green: 0x26/255.0, blue: 0x30/255.0, alpha: 1.0)
            bgFill.setFill()
            boxPath.fill()
            
            let borderColor = isHovered
                ? NSColor.white
                : NSColor(srgbRed: 0xB0/255.0, green: 0xBC/255.0, blue: 0xD0/255.0, alpha: 1.0)
            borderColor.setStroke()
            boxPath.lineWidth = 1.8
            boxPath.stroke()
        }
        
        let textX = boxRect.maxX + 8.0
        let maxTextW = max(0, bounds.width - textX)
        if attributedTitle.length > 0 {
            let attr = attributedTitle
            let plain = attr.string
            let trimmed = plain.trimmingCharacters(in: .whitespaces)
            let drawAttr: NSAttributedString
            if trimmed != plain {
                let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 11, weight: .medium)
                let color = attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor ?? NSColor.white
                drawAttr = NSAttributedString(string: trimmed, attributes: [.font: font, .foregroundColor: color])
            } else {
                drawAttr = attr
            }
            let size = drawAttr.size()
            let textY = max(0, (bounds.height - size.height) / 2.0)
            drawAttr.draw(in: NSRect(x: textX, y: textY, width: maxTextW, height: size.height))
        } else if !title.isEmpty {
            let font = self.font ?? NSFont.systemFont(ofSize: 11, weight: .medium)
            let textColor = isEnabled ? NSColor(white: 0.9, alpha: 1.0) : NSColor(white: 0.5, alpha: 1.0)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let size = (title as NSString).size(withAttributes: attrs)
            let textY = max(0, (bounds.height - size.height) / 2.0)
            (title as NSString).draw(in: NSRect(x: textX, y: textY, width: maxTextW, height: size.height), withAttributes: attrs)
        }
    }
}

class PastelColorPickerView: NSView {
    var selectedHex: String {
        didSet {
            updateSelection()
        }
    }
    var onColorChanged: ((String) -> Void)?
    private var buttons: [NSButton] = []
    
    init(frame: NSRect, selectedHex: String, onColorChanged: @escaping (String) -> Void) {
        self.selectedHex = selectedHex.uppercased()
        self.onColorChanged = onColorChanged
        super.init(frame: frame)
        self.wantsLayer = true
        setupSwatches()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    
    private func setupSwatches() {
        subviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        
        let swatchSize: CGFloat = 13
        let gap: CGFloat = 4
        var x: CGFloat = 0
        
        for pc in PastelTheme.palette {
            let hexNorm = pc.hex.uppercased()
            let isSelected = (hexNorm == selectedHex)
            let btn = NSButton(frame: NSRect(x: x, y: (bounds.height - swatchSize) / 2.0, width: swatchSize, height: swatchSize))
            btn.title = ""
            btn.attributedTitle = NSAttributedString(string: "")
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = swatchSize / 2.0
            btn.layer?.backgroundColor = pc.color.cgColor
            btn.layer?.borderColor = isSelected ? NSColor.white.cgColor : NSColor(white: 0.28, alpha: 1.0).cgColor
            btn.layer?.borderWidth = isSelected ? 2.0 : 1.0
            btn.toolTip = "\(pc.name) (\(pc.hex))"
            btn.target = self
            btn.action = #selector(swatchClicked(_:))
            btn.identifier = NSUserInterfaceItemIdentifier(hexNorm)
            addSubview(btn)
            buttons.append(btn)
            x += swatchSize + gap
        }
    }
    
    private func updateSelection() {
        for btn in buttons {
            let isSel = (btn.identifier?.rawValue == selectedHex)
            btn.layer?.borderColor = isSel ? NSColor.white.cgColor : NSColor(white: 0.28, alpha: 1.0).cgColor
            btn.layer?.borderWidth = isSel ? 2.0 : 1.0
        }
    }
    
    @objc private func swatchClicked(_ sender: NSButton) {
        guard let hex = sender.identifier?.rawValue else { return }
        selectedHex = hex
        onColorChanged?(hex)
    }
}

class SectionFrameView: NSView {
    let title: String
    let accentColor: NSColor
    
    init(frame: NSRect, title: String, accentColor: NSColor) {
        self.title = title
        self.accentColor = accentColor
        super.init(frame: frame)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isFlipped: Bool { return true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: accentColor
        ]
        let titleStr = title as NSString
        let titleSize = titleStr.size(withAttributes: titleAttrs)
        
        let strokeW: CGFloat = 1.8
        let r: CGFloat = 12.0
        let inset = strokeW / 2.0
        let topY: CGFloat = 8.0
        let boxRect = CGRect(
            x: inset,
            y: topY,
            width: bounds.width - strokeW,
            height: bounds.height - topY - inset
        )
        
        let cx = bounds.midX
        let halfGap = (titleSize.width / 2.0) + 5.0
        let gapStart = cx - halfGap
        let gapEnd = cx + halfGap
        
        // Rounded border with open top gap for the title
        let path = CGMutablePath()
        path.move(to: CGPoint(x: gapEnd, y: boxRect.minY))
        path.addLine(to: CGPoint(x: boxRect.maxX - r, y: boxRect.minY))
        path.addArc(
            tangent1End: CGPoint(x: boxRect.maxX, y: boxRect.minY),
            tangent2End: CGPoint(x: boxRect.maxX, y: boxRect.minY + r),
            radius: r
        )
        path.addLine(to: CGPoint(x: boxRect.maxX, y: boxRect.maxY - r))
        path.addArc(
            tangent1End: CGPoint(x: boxRect.maxX, y: boxRect.maxY),
            tangent2End: CGPoint(x: boxRect.maxX - r, y: boxRect.maxY),
            radius: r
        )
        path.addLine(to: CGPoint(x: boxRect.minX + r, y: boxRect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: boxRect.minX, y: boxRect.maxY),
            tangent2End: CGPoint(x: boxRect.minX, y: boxRect.maxY - r),
            radius: r
        )
        path.addLine(to: CGPoint(x: boxRect.minX, y: boxRect.minY + r))
        path.addArc(
            tangent1End: CGPoint(x: boxRect.minX, y: boxRect.minY),
            tangent2End: CGPoint(x: boxRect.minX + r, y: boxRect.minY),
            radius: r
        )
        path.addLine(to: CGPoint(x: gapStart, y: boxRect.minY))
        
        ctx.setStrokeColor(accentColor.cgColor)
        ctx.setLineWidth(strokeW)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
        
        // Draw title text exactly centered on the top gap line
        let textX = cx - (titleSize.width / 2.0)
        let textY = topY - (titleSize.height / 2.0)
        titleStr.draw(at: CGPoint(x: textX, y: textY), withAttributes: titleAttrs)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    var fullWindow: NSWindow?
    var hudWindow: NSPanel?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    
    var currentMode: DisplayMode = .full
    var hudOrientation: HudOrientation = .vertical
    var isAlwaysOnTop: Bool = true
    
    var autoRefreshTimer: Timer?
    var refreshBtn: NSButton?
    var isRefreshing: Bool = false
    var isFirstLaunch: Bool = true
    var latestQuota: QuotaData?
    
    // Settings fields
    var geminiCheck: NSButton?
    var geminiKeyField: NSTextField?
    var geminiTestBtn: NSButton?
    var geminiStatusLabel: NSTextField?
    var antigravityCheck: NSButton?
    var claudeProCheck: NSButton?
    var claudeProTokenField: NSTextField?
    var claudeProStatusLabel: NSTextField?
    var chatgptCheck: NSButton?
    var chatgptTokenField: NSTextField?
    var chatgptStatusLabel: NSTextField?
    var cursorCheck: NSButton?
    var cursorTokenField: NSTextField?
    var copilotCheck: NSButton?
    var copilotTokenField: NSTextField?
    var openaiCheck: NSButton?
    var openaiKeyField: NSTextField?
    var anthropicCheck: NSButton?
    var anthropicKeyField: NSTextField?
    
    var hudGaugeCheckboxes: [String: NSButton] = [:]
    var selectedSectionColors: [String: String] = [:]
    
    // Onboarding fields
    var onboardingWindow: NSWindow?
    var obAntigravityCheck: NSButton?
    var obClaudeCheck: NSButton?
    var obChatgptCheck: NSButton?
    var obCursorCheck: NSButton?
    var obCopilotCheck: NSButton?
    var obGeminiCheck: NSButton?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        // Telemetry heartbeat is sent by the Node engine (core/telemetry.js, throttled to 6h) so launches
        // are not counted twice and the API answer (announcements) is cached in one place.
        
        if let savedMode = UserDefaults.standard.string(forKey: "uaqm_display_mode"),
           let mode = DisplayMode(rawValue: savedMode) {
            currentMode = mode
        }
        if let savedOrient = UserDefaults.standard.string(forKey: "uaqm_hud_orientation"),
           let orient = HudOrientation(rawValue: savedOrient) {
            hudOrientation = orient
        }
        
        let cfg = QuotaManager.loadConfig()
        let configExists = FileManager.default.fileExists(atPath: QuotaManager.configPath)
        let onboardingDone = UserDefaults.standard.bool(forKey: "aigauge_onboarding_completed") || (cfg.onboarding_completed == true)
        
        if !onboardingDone && !configExists {
            openOnboarding()
            return
        }
        
        let force = CommandLine.arguments.contains("--force")
        if let initialQuota = QuotaManager.loadQuota(force: force, maxRetries: 3) {
            self.latestQuota = initialQuota
            renderCurrentMode()
            startAutoRefreshTimer()
            if CommandLine.arguments.contains("--settings") || initialQuota.needs_setup == true || initialQuota.groups.isEmpty {
                openSettings()
            } else if CommandLine.arguments.contains("--onboarding") {
                openOnboarding()
            }
        } else {
            openSettings()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if currentMode == .full {
            switchToFullMode()
            fullWindow?.makeKeyAndOrderFront(nil)
        } else {
            switchToHudMode()
            hudWindow?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let img = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "AI Gauge") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                button.image = img.withSymbolConfiguration(cfg)
            } else {
                button.title = "⚡"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    func getMachineId() -> String {
        let devFile = NSString(string: "~/.config/UniversalAIQuota/device_id").expandingTildeInPath
        if let existing = try? String(contentsOfFile: devFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }
        let fallback = UUID().uuidString.lowercased()
        try? fallback.write(toFile: devFile, atomically: true, encoding: .utf8)
        return fallback
    }
    
    func sendTelemetryHeartbeat() {
        guard let url = URL(string: "https://ai-gauge.vh2c.com.br/v1/geminigauje") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AIGauge/1.1 (macOS; VH2C)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 2.5
        
        let payload: [String: Any] = [
            "app": "ai-gauge",
            "version": "1.1.1",
            "os": "macOS",
            "arch": "arm64",
            "machine_id": getMachineId(),
            "timestamp": Int(Date().timeIntervalSince1970)
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
    
    @objc func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            toggleWindowVisibility()
            return
        }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let titleItem = NSMenuItem(title: "⚡ AI Gauge", action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(
                string: "⚡ AI Gauge",
                attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold)]
            )
            menu.addItem(titleItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Open Main Window", action: #selector(switchToFullMode), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "HUD Bar Mode", action: #selector(switchToHudMode), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Settings... (⚙️)", action: #selector(openSettings), keyEquivalent: ","))
            menu.addItem(NSMenuItem(title: "Setup Assistant...", action: #selector(openOnboarding), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Refresh Data Now", action: #selector(refreshClicked), keyEquivalent: "r"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit AI Gauge", action: #selector(closeClicked), keyEquivalent: "q"))
            for item in menu.items { item.target = self }
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleWindowVisibility()
        }
    }
    
    func toggleWindowVisibility() {
        if currentMode == .full {
            if let win = fullWindow, win.isVisible {
                win.orderOut(nil)
            } else {
                renderCurrentMode()
                fullWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            if let win = hudWindow, win.isVisible {
                win.orderOut(nil)
            } else {
                renderCurrentMode()
                hudWindow?.orderFront(nil)
            }
        }
    }
    
    func updateStatusItemTitle() {
        guard let quota = latestQuota else { return }
        var minPct = 100
        for g in quota.groups {
            for b in g.buckets {
                if b.remaining_pct < minPct { minPct = b.remaining_pct }
            }
        }
        if minPct < 100 {
            statusItem?.button?.title = " \(minPct)%"
        } else {
            statusItem?.button?.title = ""
        }
    }
    
    func startAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.performRefresh(animated: false)
        }
    }
    
    @objc func refreshClicked() {
        performRefresh(animated: true)
    }
    
    func performRefresh(animated: Bool) {
        // Pausar auto-refresh periódico em background enquanto o usuário estiver na tela de configurações
        if !animated && settingsWindow != nil && settingsWindow?.isVisible == true {
            return
        }
        if isRefreshing { return }
        isRefreshing = true
        
        if animated {
            refreshBtn?.isEnabled = false
            refreshBtn?.attributedTitle = NSAttributedString(
                string: "Atualizando...",
                attributes: [
                    .foregroundColor: NSColor(white: 0.50, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ]
            )
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let quota = QuotaManager.loadQuota(force: true, maxRetries: 2)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshing = false
                if let quota = quota {
                    self.latestQuota = quota
                    // Não reconstruir UI nem roubar foco se o usuário estiver com as Configurações abertas
                    if self.settingsWindow == nil || self.settingsWindow?.isVisible == false {
                        self.renderCurrentMode()
                    }
                    self.updateStatusItemTitle()
                }
                self.resetRefreshBtn()
            }
        }
    }
    
    func resetRefreshBtn() {
        let btnText = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        refreshBtn?.isEnabled = true
        refreshBtn?.attributedTitle = NSAttributedString(
            string: "Refresh",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        )
        if let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                refreshBtn?.image = symbol.withSymbolConfiguration(tinted)
            } else {
                refreshBtn?.image = symbol.withSymbolConfiguration(config)
                refreshBtn?.contentTintColor = btnText
            }
        }
    }
    
    func renderCurrentMode() {
        guard let quota = latestQuota else { return }
        updateStatusItemTitle()
        switch currentMode {
        case .full:
            hudWindow?.orderOut(nil)
            setupFullUI(with: quota)
        case .hud:
            fullWindow?.orderOut(nil)
            setupHudUI(with: quota)
        }
    }
    
    @objc func switchToHudMode() {
        currentMode = .hud
        UserDefaults.standard.set(currentMode.rawValue, forKey: "uaqm_display_mode")
        renderCurrentMode()
    }
    
    @objc func switchToFullMode() {
        currentMode = .full
        UserDefaults.standard.set(currentMode.rawValue, forKey: "uaqm_display_mode")
        renderCurrentMode()
    }
    
    @objc func toggleHudOrientation() {
        hudOrientation = (hudOrientation == .vertical) ? .horizontal : .vertical
        UserDefaults.standard.set(hudOrientation.rawValue, forKey: "uaqm_hud_orientation")
        renderCurrentMode()
    }
    
    @objc func toggleAlwaysOnTop() {
        isAlwaysOnTop = !isAlwaysOnTop
        hudWindow?.level = isAlwaysOnTop ? .floating : .normal
    }
    
    @objc func closeWindowClicked() {
        fullWindow?.orderOut(nil)
        hudWindow?.orderOut(nil)
    }
    
    @objc func toggleModeClicked() {
        if currentMode == .full {
            switchToHudMode()
        } else {
            switchToFullMode()
        }
    }
    
    func setupHudUI(with quota: QuotaData) {
        let cfg = QuotaManager.loadConfig()
        let hiddenSet = Set(cfg.hidden_hud_gauges ?? [])
        
        var filteredSections: [GaugeSection] = []
        for s in quota.gaugeSections {
            let visibleItems = s.items.filter { !hiddenSet.contains($0.id) }
            if !visibleItems.isEmpty {
                var vs = s
                vs.items = visibleItems
                filteredSections.append(vs)
            }
        }
        let sections = filteredSections
        let isVertical = (hudOrientation == .vertical)
        let totalItems = sections.reduce(0) { $0 + $1.items.count }
        
        let hudW: CGFloat
        let hudH: CGFloat
        let maxScreenH = (NSScreen.main?.visibleFrame.height ?? 800) - 60
        
        if totalItems == 0 {
            hudW = isVertical ? 124 : 260
            hudH = isVertical ? 180 : 100
        } else if isVertical {
            hudW = 114
            var totalSectionsH: CGFloat = 0
            for s in sections {
                totalSectionsH += 15.0 + CGFloat(s.items.count) * 96 + 8.0
            }
            let totalGaps = CGFloat(max(sections.count - 1, 0)) * 10.0
            let calcH = 26 + totalSectionsH + totalGaps + 26
            hudH = min(calcH, maxScreenH)
        } else {
            let totalFrameW = sections.reduce(0) { $0 + 12.0 + CGFloat($1.items.count) * 96 + 8.0 } + CGFloat(max(sections.count - 1, 0)) * 10.0
            hudW = max(16 + totalFrameW + 40, 260)
            hudH = 126
        }
        
        if hudWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 100, y: 100, width: hudW, height: hudH),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = isAlwaysOnTop ? .floating : .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.delegate = self
            hudWindow = panel
        }
        
        guard let panel = hudWindow else { return }
        
        let currentFrame = panel.frame
        let newX: CGFloat
        let newY: CGFloat
        if isFirstLaunch {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                newX = screenFrame.maxX - hudW - 20
                newY = screenFrame.maxY - hudH - 20
            } else {
                newX = 100
                newY = 100
            }
        } else {
            newX = currentFrame.origin.x
            newY = currentFrame.origin.y + (currentFrame.height - hudH)
        }
        
        panel.setFrame(NSRect(x: newX, y: newY, width: hudW, height: hudH), display: true, animate: false)
        
        let container = HudContainerView(frame: NSRect(x: 0, y: 0, width: hudW, height: hudH))
        container.delegate = self
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 0.94).cgColor
        container.layer?.cornerRadius = 14
        container.layer?.borderColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2E/255.0, alpha: 1.0).cgColor
        container.layer?.borderWidth = 1.0
        
        if isVertical {
            // Barra superior de controle vertical: [⤢ Alternar] [⋯ Opções] [✕ Fechar]
            let topBarY = hudH - 26
            
            let toggleBtn = NSButton(title: "", target: self, action: #selector(toggleModeClicked))
            toggleBtn.isBordered = false
            toggleBtn.frame = NSRect(x: 8, y: topBarY, width: 22, height: 20)
            toggleBtn.toolTip = "Switch to Full Window (Cmd+M)"
            if let sym = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Alternar Modo") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                toggleBtn.image = sym.withSymbolConfiguration(cfg)
                toggleBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(toggleBtn)
            
            let menuBtn = NSButton(title: "", target: self, action: #selector(showHudContextMenu(_:)))
            menuBtn.isBordered = false
            menuBtn.frame = NSRect(x: (hudW - 22) / 2.0, y: topBarY, width: 22, height: 20)
            menuBtn.toolTip = "Options Menu"
            if let sym = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Options") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                menuBtn.image = sym.withSymbolConfiguration(cfg)
                menuBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(menuBtn)
            
            let closeBtn = NSButton(title: "", target: self, action: #selector(closeWindowClicked))
            closeBtn.isBordered = false
            closeBtn.frame = NSRect(x: hudW - 30, y: topBarY, width: 22, height: 20)
            closeBtn.toolTip = "Close Window (✕)"
            if let sym = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                closeBtn.image = sym.withSymbolConfiguration(cfg)
                closeBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(closeBtn)
            
            if totalItems == 0 {
                // Empty state vertical
                let iconLabel = NSTextField(labelWithString: "📡")
                iconLabel.font = NSFont.systemFont(ofSize: 22)
                iconLabel.alignment = .center
                iconLabel.frame = NSRect(x: 10, y: hudH - 58, width: hudW - 20, height: 26)
                container.addSubview(iconLabel)
                
                let emptyTitle = NSTextField(labelWithString: "Sem Cotas")
                emptyTitle.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
                emptyTitle.textColor = .white
                emptyTitle.alignment = .center
                emptyTitle.frame = NSRect(x: 4, y: hudH - 82, width: hudW - 8, height: 16)
                container.addSubview(emptyTitle)
                
                let emptySub = NSTextField(labelWithString: "Open the IDE or\nenter an API Key")
                emptySub.font = NSFont.systemFont(ofSize: 9, weight: .regular)
                emptySub.textColor = NSColor(white: 0.60, alpha: 1.0)
                emptySub.alignment = .center
                emptySub.frame = NSRect(x: 4, y: hudH - 118, width: hudW - 8, height: 28)
                container.addSubview(emptySub)
                
                let cfgBtn = NSButton(title: "Settings", target: self, action: #selector(openSettings))
                cfgBtn.isBordered = false
                cfgBtn.wantsLayer = true
                cfgBtn.layer?.backgroundColor = NSColor(srgbRed: 0x24/255.0, green: 0x24/255.0, blue: 0x28/255.0, alpha: 1.0).cgColor
                cfgBtn.layer?.cornerRadius = 5
                cfgBtn.frame = NSRect(x: 12, y: 26, width: hudW - 24, height: 22)
                cfgBtn.attributedTitle = NSAttributedString(
                    string: "⚙️ Settings",
                    attributes: [
                        .foregroundColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                        .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold)
                    ]
                )
                container.addSubview(cfgBtn)
            } else {
                let footerH: CGFloat = 20
                let topBarH: CGFloat = 26
                let scrollH = hudH - topBarH - footerH
                
                var totalSectionsH: CGFloat = 0
                for s in sections {
                    totalSectionsH += 15.0 + CGFloat(s.items.count) * 96 + 8.0
                }
                let totalGaps = CGFloat(max(sections.count - 1, 0)) * 10.0
                let contentH = totalSectionsH + totalGaps + 8.0
                
                let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerH, width: hudW, height: scrollH))
                scrollView.hasVerticalScroller = (contentH > scrollH)
                scrollView.autohidesScrollers = true
                scrollView.drawsBackground = false
                
                let contentView = FlippedContentView(frame: NSRect(x: 0, y: 0, width: hudW, height: max(contentH, scrollH)))
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.clear.cgColor
                
                let frameW: CGFloat = 102
                let frameX = (hudW - frameW) / 2.0
                var curY: CGFloat = 4.0
                
                for s in sections {
                    let frameH = 15.0 + CGFloat(s.items.count) * 96 + 8.0
                    let sectionFrame = SectionFrameView(
                        frame: NSRect(x: frameX, y: curY, width: frameW, height: frameH),
                        title: s.name,
                        accentColor: s.accentColor
                    )
                    
                    for (idx, item) in s.items.enumerated() {
                        let gauge = TachometerGaugeView(item: item)
                        gauge.frame = NSRect(x: (frameW - 88) / 2.0, y: 15.0 + CGFloat(idx) * 96, width: 88, height: 96)
                        sectionFrame.addSubview(gauge)
                    }
                    
                    contentView.addSubview(sectionFrame)
                    curY += frameH + 10.0
                }
                
                scrollView.documentView = contentView
                container.addSubview(scrollView)
            }
            
            let annUrl = quota.announcement?.action_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveAnnUrl = (annUrl != nil && !annUrl!.isEmpty) ? annUrl : nil
            let updateUrl = quota.update?.download_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveUpdateUrl = (updateUrl != nil && !updateUrl!.isEmpty) ? updateUrl : nil
            let versionUrl = effectiveAnnUrl ?? effectiveUpdateUrl ?? "https://github.com/vh2c/ai-gauge/releases/latest"
            let hasVersionNotice = (quota.announcement?.type == "versao") || (quota.update?.update_available == true)
            
            if hasVersionNotice {
                let upBtn = UrlButton(title: "", target: self, action: #selector(openExternalUrl(_:)))
                upBtn.isBordered = false
                upBtn.targetUrl = versionUrl
                upBtn.frame = NSRect(x: 2, y: 3, width: hudW - 4, height: 16)
                upBtn.toolTip = "New version available. Click to download now."
                upBtn.attributedTitle = NSAttributedString(
                    string: "● NOVA VERSÃO",
                    attributes: [
                        .foregroundColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                        .font: NSFont.systemFont(ofSize: 8.5, weight: .bold)
                    ]
                )
                container.addSubview(upBtn)
            } else {
                let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
                brandBtn.isBordered = false
                brandBtn.frame = NSRect(x: 4, y: 3, width: hudW - 8, height: 16)
                brandBtn.attributedTitle = NSAttributedString(
                    string: "vh2c.com.br",
                    attributes: [
                        .foregroundColor: NSColor(white: 0.45, alpha: 1.0),
                        .font: NSFont.systemFont(ofSize: 8.5, weight: .medium)
                    ]
                )
                container.addSubview(brandBtn)
            }
        } else {
            // Horizontal HUD
            if totalItems == 0 {
                let msgLabel = NSTextField(labelWithString: "📡 Sem cotas ativas no momento")
                msgLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                msgLabel.textColor = .white
                msgLabel.frame = NSRect(x: 14, y: hudH - 36, width: hudW - 60, height: 16)
                container.addSubview(msgLabel)
                
                let subLabel = NSTextField(labelWithString: "Open the Antigravity IDE or add an API key")
                subLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
                subLabel.textColor = NSColor(white: 0.60, alpha: 1.0)
                subLabel.frame = NSRect(x: 14, y: hudH - 56, width: hudW - 60, height: 14)
                container.addSubview(subLabel)
                
                let cfgBtn = NSButton(title: "Configure Providers", target: self, action: #selector(openSettings))
                cfgBtn.isBordered = false
                cfgBtn.wantsLayer = true
                cfgBtn.layer?.backgroundColor = NSColor(srgbRed: 0x24/255.0, green: 0x24/255.0, blue: 0x28/255.0, alpha: 1.0).cgColor
                cfgBtn.layer?.cornerRadius = 5
                cfgBtn.frame = NSRect(x: 14, y: 16, width: 140, height: 22)
                cfgBtn.attributedTitle = NSAttributedString(
                    string: "⚙️ Configure Providers",
                    attributes: [
                        .foregroundColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                        .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
                    ]
                )
                container.addSubview(cfgBtn)
            } else {
                var curX: CGFloat = 12
                for s in sections {
                    let frameW = 12.0 + CGFloat(s.items.count) * 96 + 8.0
                    let frameH: CGFloat = 112.0
                    let sectionFrame = SectionFrameView(
                        frame: NSRect(x: curX, y: 6.0, width: frameW, height: frameH),
                        title: s.name,
                        accentColor: s.accentColor
                    )
                    for (idx, item) in s.items.enumerated() {
                        let gauge = TachometerGaugeView(item: item)
                        gauge.frame = NSRect(x: 10.0 + CGFloat(idx) * 96, y: 10.0, width: 88, height: 96)
                        sectionFrame.addSubview(gauge)
                    }
                    container.addSubview(sectionFrame)
                    curX += frameW + 10.0
                }
            }
            
            let colX = hudW - 30
            let closeBtn = NSButton(title: "", target: self, action: #selector(closeWindowClicked))
            closeBtn.isBordered = false
            closeBtn.frame = NSRect(x: colX, y: hudH - 28, width: 22, height: 20)
            closeBtn.toolTip = "Close Window (✕)"
            if let sym = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                closeBtn.image = sym.withSymbolConfiguration(cfg)
                closeBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(closeBtn)
            
            let toggleBtn = NSButton(title: "", target: self, action: #selector(toggleModeClicked))
            toggleBtn.isBordered = false
            toggleBtn.frame = NSRect(x: colX, y: (hudH - 20) / 2.0, width: 22, height: 20)
            toggleBtn.toolTip = "Switch to Full Window (Cmd+M)"
            if let sym = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Alternar Modo") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                toggleBtn.image = sym.withSymbolConfiguration(cfg)
                toggleBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(toggleBtn)
            
            let menuBtn = NSButton(title: "", target: self, action: #selector(showHudContextMenu(_:)))
            menuBtn.isBordered = false
            menuBtn.frame = NSRect(x: colX, y: 10, width: 22, height: 20)
            menuBtn.toolTip = "Options Menu"
            if let sym = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Options") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                menuBtn.image = sym.withSymbolConfiguration(cfg)
                menuBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(menuBtn)
            
            let annUrl = quota.announcement?.action_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveAnnUrl = (annUrl != nil && !annUrl!.isEmpty) ? annUrl : nil
            let updateUrl = quota.update?.download_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveUpdateUrl = (updateUrl != nil && !updateUrl!.isEmpty) ? updateUrl : nil
            let versionUrl = effectiveAnnUrl ?? effectiveUpdateUrl ?? "https://github.com/vh2c/ai-gauge/releases/latest"
            let hasVersionNotice = (quota.announcement?.type == "versao") || (quota.update?.update_available == true)
            
            if hasVersionNotice {
                let upBtn = UrlButton(title: "", target: self, action: #selector(openExternalUrl(_:)))
                upBtn.isBordered = false
                upBtn.targetUrl = versionUrl
                upBtn.frame = NSRect(x: 12, y: 2, width: 100, height: 14)
                upBtn.toolTip = "New version available. Click to download now."
                upBtn.attributedTitle = NSAttributedString(
                    string: "● NOVA VERSÃO",
                    attributes: [
                        .foregroundColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                        .font: NSFont.systemFont(ofSize: 8.5, weight: .bold)
                    ]
                )
                container.addSubview(upBtn)
            } else {
                let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
                brandBtn.isBordered = false
                brandBtn.frame = NSRect(x: 12, y: 2, width: 90, height: 12)
                brandBtn.attributedTitle = NSAttributedString(
                    string: "vh2c.com.br",
                    attributes: [
                        .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
                        .font: NSFont.systemFont(ofSize: 8.0, weight: .medium)
                    ]
                )
                container.addSubview(brandBtn)
            }
        }
        
        panel.contentView = container
        panel.orderFront(nil)
    }
    
    @objc func showHudContextMenu(_ sender: NSButton) {
        let menu = buildContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.midX, y: sender.bounds.midY), in: sender)
    }
    
    func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "AI Gauge Options")
        
        let titleItem = NSMenuItem(title: "⚡ AI Gauge", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "⚡ AI Gauge",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold)]
        )
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        let fullItem = NSMenuItem(title: "Toggle Display Mode (Window / HUD)", action: #selector(toggleModeClicked), keyEquivalent: "m")
        fullItem.target = self
        menu.addItem(fullItem)
        
        let orientTitle = (hudOrientation == .vertical) ? "Switch to Horizontal Bar" : "Switch to Vertical Bar"
        let orientItem = NSMenuItem(title: orientTitle, action: #selector(toggleHudOrientation), keyEquivalent: "o")
        orientItem.target = self
        menu.addItem(orientItem)
        
        let refreshItem = NSMenuItem(title: "Refresh Data Now", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let settingsItem = NSMenuItem(title: "Settings... (⚙️)", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let pinItem = NSMenuItem(title: "Always on Top (Floating)", action: #selector(toggleAlwaysOnTop), keyEquivalent: "p")
        pinItem.target = self
        pinItem.state = isAlwaysOnTop ? .on : .off
        menu.addItem(pinItem)
        
        let brandItem = NSMenuItem(title: "Support / Donate (Stripe)", action: #selector(brandClicked), keyEquivalent: "")
        brandItem.target = self
        menu.addItem(brandItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let closeWinItem = NSMenuItem(title: "Close Window (✕)", action: #selector(closeWindowClicked), keyEquivalent: "w")
        closeWinItem.target = self
        menu.addItem(closeWinItem)
        
        let closeItem = NSMenuItem(title: "Quit AI Gauge", action: #selector(closeClicked), keyEquivalent: "q")
        closeItem.target = self
        menu.addItem(closeItem)
        
        return menu
    }
    
    func setupFullUI(with quota: QuotaData) {
        let colorBg18 = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        let colorField1F = NSColor(srgbRed: 0x1E/255.0, green: 0x1E/255.0, blue: 0x22/255.0, alpha: 1.0)
        let colorBorder = NSColor(srgbRed: 0x2C/255.0, green: 0x2C/255.0, blue: 0x30/255.0, alpha: 1.0)
        let colorSep = NSColor(srgbRed: 0x28/255.0, green: 0x28/255.0, blue: 0x2E/255.0, alpha: 1.0)
        let colorTrack = NSColor(srgbRed: 0x28/255.0, green: 0x28/255.0, blue: 0x2D/255.0, alpha: 1.0)
        
        let windowWidth: CGFloat = 460
        let footerHeight: CGFloat = 68
        
        // Calcular altura total do conteúdo
        var calcContentH: CGFloat = 18 // padding do topo
        calcContentH += 22 // Título do app e link vh2c
        calcContentH += 18 // Conta e plano
        calcContentH += 16 // Status e timestamp
        calcContentH += 18 // Divisor e espaçamento generoso antes dos cards
        
        if quota.update?.update_available == true {
            calcContentH += 46 + 12
        }
        for ann in quota.banners {
            let hasAct = (ann.type == "versao") || !((ann.action_label ?? "").isEmpty) || !((ann.action_url ?? "").isEmpty)
            calcContentH += (ann.type == "versao" ? 62 : (hasAct ? 100 : 64)) + 12
        }
        
        if quota.groups.isEmpty {
            calcContentH += 110 + 16
        } else {
            for g in quota.groups {
                calcContentH += 44 + CGFloat(g.buckets.count * 44 + 6) + 14
            }
        }
        calcContentH += 16 // padding inferior
        
        let windowHeight = min(calcContentH + footerHeight, 720)
        
        if fullWindow == nil {
            let windowRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
            let win = NSWindow(
                contentRect: windowRect,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "AI Gauge - Universal AI Quota Cockpit"
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.level = .normal
            win.center()
            fullWindow = win
        } else if let win = fullWindow {
            let cur = win.frame
            let newY = cur.origin.y + (cur.height - windowHeight)
            win.setFrame(NSRect(x: cur.origin.x, y: newY, width: windowWidth, height: windowHeight), display: true, animate: false)
        }
        
        guard let window = fullWindow else { return }
        window.backgroundColor = colorBg18
        window.isOpaque = true
        
        let mainView = NSView(frame: window.contentView!.bounds)
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = colorBg18.cgColor
        mainView.autoresizingMask = [.width, .height]
        window.contentView = mainView
        
        let scrollViewHeight = window.contentView!.bounds.height - footerHeight
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerHeight, width: windowWidth, height: scrollViewHeight))
        scrollView.hasVerticalScroller = calcContentH > scrollViewHeight
        scrollView.drawsBackground = true
        scrollView.backgroundColor = colorBg18
        scrollView.autoresizingMask = [.width, .height]
        
        let contentView = FlippedContentView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: max(calcContentH, scrollViewHeight)))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = colorBg18.cgColor
        
        var y: CGFloat = 18
        
        // ----------------- HEADER COM ESPAÇAMENTO -----------------
        let appTitle = NSTextField(labelWithString: "AI Gauge")
        appTitle.font = NSFont.systemFont(ofSize: 15.5, weight: .bold)
        appTitle.textColor = .white
        appTitle.frame = NSRect(x: 20, y: y, width: 220, height: 20)
        contentView.addSubview(appTitle)
        y += 24
        
        let accountText = "\(quota.account)  •  Plan \(quota.plan ?? "Universal")"
        let accountLabel = NSTextField(labelWithString: accountText)
        accountLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        accountLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        accountLabel.frame = NSRect(x: 20, y: y, width: windowWidth - 40, height: 16)
        contentView.addSubview(accountLabel)
        y += 18
        
        let cacheInfo = (quota.from_cache ?? false) ? " (Cache \(quota.cache_age_seconds ?? 0)s ago)" : " (Live)"
        let timeText = "Updated at \(quota.updated_at ?? "now")\(cacheInfo)"
        let timeLabel = NSTextField(labelWithString: timeText)
        timeLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        timeLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        timeLabel.frame = NSRect(x: 20, y: y, width: windowWidth - 40, height: 14)
        contentView.addSubview(timeLabel)
        y += 20
        
        let headerDivider = NSBox(frame: NSRect(x: 18, y: y, width: windowWidth - 36, height: 1))
        headerDivider.boxType = .custom
        headerDivider.fillColor = colorSep
        headerDivider.borderColor = .clear
        contentView.addSubview(headerDivider)
        y += 16 // Espaçamento generoso entre o header e os primeiros indicadores de cota!
        
        // ----------------- UPDATE BANNER -----------------
        if let update = quota.update, update.update_available == true {
            let bannerH: CGFloat = 46
            let banner = FlippedContentView(frame: NSRect(x: 18, y: y, width: windowWidth - 36, height: bannerH))
            banner.wantsLayer = true
            banner.layer?.backgroundColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 0.12).cgColor
            banner.layer?.borderColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 0.7).cgColor
            banner.layer?.borderWidth = 1
            banner.layer?.cornerRadius = 6
            contentView.addSubview(banner)
            
            let btnW: CGFloat = 84
            let btnH: CGFloat = 26
            let btnY: CGFloat = ((bannerH - btnH) / 2.0).rounded()
            let upBtn = UrlButton(frame: NSRect(x: banner.frame.width - btnW - 12, y: btnY, width: btnW, height: btnH))
            upBtn.bezelStyle = .inline
            upBtn.isBordered = false
            upBtn.wantsLayer = true
            upBtn.layer?.backgroundColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0).cgColor
            upBtn.layer?.cornerRadius = 4
            upBtn.attributedTitle = NSAttributedString(
                string: "Download",
                attributes: [
                    .foregroundColor: NSColor(srgbRed: 0x12/255.0, green: 0x12/255.0, blue: 0x12/255.0, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 11.5, weight: .bold)
                ]
            )
            upBtn.targetUrl = update.download_url ?? "https://github.com/vh2c/ai-gauge/releases/latest"
            upBtn.target = self
            upBtn.action = #selector(openExternalUrl(_:))
            banner.addSubview(upBtn)
            
            let titleH: CGFloat = 20
            let titleY: CGFloat = ((bannerH - titleH) / 2.0).rounded()
            
            var textX: CGFloat = 14
            if let sym = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil) {
                let symConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                let iconImg = sym.withSymbolConfiguration(symConfig)
                let iconH: CGFloat = 16
                let iconY: CGFloat = ((bannerH - iconH) / 2.0).rounded()
                let imgView = NSImageView(frame: NSRect(x: 12, y: iconY, width: 16, height: iconH))
                imgView.image = iconImg
                imgView.contentTintColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
                banner.addSubview(imgView)
                textX = 34
            }
            
            let upTitle = NSTextField(labelWithString: "New release v\(update.latest_version ?? "") available")
            upTitle.font = NSFont.systemFont(ofSize: 12.0, weight: .bold)
            upTitle.textColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
            upTitle.frame = NSRect(x: textX, y: titleY, width: banner.frame.width - btnW - textX - 16, height: titleH)
            banner.addSubview(upTitle)
            
            y += bannerH + 12
        }

        // ----------------- ANNOUNCEMENT / PRO STATUS -----------------
        // The ad ("publicidade") is an independent toast window; banners are drawn at the top.
        if let promo = quota.adPromo {
            PromoDockManager.shared.presentIfNeeded(promo)
        }
        for ann in quota.banners {
            let msg = ann.message ?? ""
            let isVersao = (ann.type == "versao")
            let annUrl = ann.action_url?
                .replacingOccurrences(of: "{machine_id}", with: getMachineId())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveAnnUrl = (annUrl != nil && !annUrl!.isEmpty) ? annUrl : nil
            let updateUrl = quota.update?.download_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveUpdateUrl = (updateUrl != nil && !updateUrl!.isEmpty) ? updateUrl : nil
            let defaultVersionUrl = effectiveAnnUrl ?? effectiveUpdateUrl ?? "https://github.com/vh2c/ai-gauge/releases/latest"
            
            let hasAction = isVersao || (ann.action_label != nil && !ann.action_label!.isEmpty) || (effectiveAnnUrl != nil)
            // Version notice = compact strip (action button on the right, vertically centered)
            var compactBtnW: CGFloat = 0
            if isVersao {
                let l = (ann.action_label ?? "").isEmpty ? "Download Now" : ann.action_label!
                let t = (l.hasSuffix("!") || l.contains("→")) ? l : "\(l) →"
                compactBtnW = max(150, CGFloat(t.count) * 8 + 28)
            }
            let textW: CGFloat = isVersao ? (windowWidth - 36) - 24 - compactBtnW - 12 : (windowWidth - 36) - 24
            let annH: CGFloat = isVersao ? 62 : (hasAction ? 100 : 64)
            let annBox = FlippedBox(frame: NSRect(x: 18, y: y, width: windowWidth - 36, height: annH))
            annBox.boxType = .custom
            
            if isVersao {
                // Nova versão = Verde (#10B981)
                annBox.fillColor = NSColor(srgbRed: 0x06/255.0, green: 0x2A/255.0, blue: 0x1E/255.0, alpha: 0.5)
                annBox.borderColor = NSColor(srgbRed: 0x10/255.0, green: 0xB9/255.0, blue: 0x81/255.0, alpha: 0.6)
            } else {
                // Informativo = Âmbar (#F59E0B)
                annBox.fillColor = NSColor(srgbRed: 0x2D/255.0, green: 0x24/255.0, blue: 0x18/255.0, alpha: 0.5)
                annBox.borderColor = NSColor(srgbRed: 0xF5/255.0, green: 0x9E/255.0, blue: 0x0B/255.0, alpha: 0.6)
            }
            annBox.borderWidth = 1
            annBox.cornerRadius = 8
            contentView.addSubview(annBox)
            
            // 1. Título limpo (SEM '[AVISO]')
            let titleText = ann.title ?? (isVersao ? "New Version Available" : "Notice")
            let titleLabel = NSTextField(labelWithString: titleText)
            titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
            titleLabel.textColor = isVersao
                ? NSColor(srgbRed: 0x34/255.0, green: 0xD3/255.0, blue: 0x99/255.0, alpha: 1.0)
                : NSColor(srgbRed: 0xFB/255.0, green: 0xBF/255.0, blue: 0x24/255.0, alpha: 1.0)
            titleLabel.frame = NSRect(x: 12, y: 10, width: textW, height: 16)
            annBox.addSubview(titleLabel)
            
            // 2. Multiline Message (Wrapping)
            let msgLabel = NSTextField(wrappingLabelWithString: msg)
            msgLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
            msgLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
            msgLabel.frame = NSRect(x: 12, y: 28, width: textW, height: 30)
            annBox.addSubview(msgLabel)
            
            // 3. Action Button (Botão 'Download Now' para Versão; ou 'Ver Detalhes' para Info)
            if hasAction {
                let defaultLabel = isVersao ? "Download Now" : "View Details"
                let actLabel = (ann.action_label != nil && !ann.action_label!.isEmpty) ? ann.action_label! : defaultLabel
                let actUrl = isVersao ? defaultVersionUrl : (effectiveAnnUrl ?? "https://ai-gauge.vh2c.com.br/donate")
                
                let btnText = (actLabel.hasSuffix("!") || actLabel.contains("→")) ? actLabel : "\(actLabel) →"
                let btnW: CGFloat = isVersao ? compactBtnW : max(170, CGFloat(btnText.count * 8 + 36))
                let btnX: CGFloat = isVersao ? (annBox.frame.width - btnW - 12) : (annBox.frame.width - btnW) / 2
                let btnY: CGFloat = isVersao ? ((annH - 26) / 2).rounded() : 64
                
                let actBtn = UrlButton(frame: NSRect(x: btnX, y: btnY, width: btnW, height: 26))
                actBtn.target = self
                actBtn.action = #selector(openExternalUrl(_:))
                actBtn.targetUrl = actUrl
                actBtn.wantsLayer = true
                actBtn.isBordered = false
                actBtn.layer?.cornerRadius = 6
                
                if isVersao {
                    actBtn.layer?.backgroundColor = NSColor(srgbRed: 0x10/255.0, green: 0xB9/255.0, blue: 0x81/255.0, alpha: 0.22).cgColor
                    actBtn.layer?.borderColor = NSColor(srgbRed: 0x10/255.0, green: 0xB9/255.0, blue: 0x81/255.0, alpha: 0.7).cgColor
                    actBtn.layer?.borderWidth = 1.0
                    actBtn.attributedTitle = NSAttributedString(
                        string: btnText,
                        attributes: [
                            .foregroundColor: NSColor(srgbRed: 0x34/255.0, green: 0xD3/255.0, blue: 0x99/255.0, alpha: 1.0),
                            .font: NSFont.systemFont(ofSize: 11.0, weight: .bold)
                        ]
                    )
                } else {
                    actBtn.layer?.backgroundColor = NSColor(srgbRed: 0xF5/255.0, green: 0x9E/255.0, blue: 0x0B/255.0, alpha: 0.22).cgColor
                    actBtn.layer?.borderColor = NSColor(srgbRed: 0xF5/255.0, green: 0x9E/255.0, blue: 0x0B/255.0, alpha: 0.7).cgColor
                    actBtn.layer?.borderWidth = 1.0
                    actBtn.attributedTitle = NSAttributedString(
                        string: btnText,
                        attributes: [
                            .foregroundColor: NSColor(srgbRed: 0xFB/255.0, green: 0xBF/255.0, blue: 0x24/255.0, alpha: 1.0),
                            .font: NSFont.systemFont(ofSize: 11.0, weight: .bold)
                        ]
                    )
                }
                annBox.addSubview(actBtn)
            }
            
            y += annH + 12
        }

        // ----------------- CARDS POR PROVEDOR / GRUPO -----------------
        if quota.groups.isEmpty {
            let emptyH: CGFloat = 110
            let cardView = FlippedBox(frame: NSRect(x: 16, y: y, width: windowWidth - 32, height: emptyH))
            cardView.boxType = .custom
            cardView.fillColor = colorField1F
            cardView.borderColor = colorBorder
            cardView.borderWidth = 1
            cardView.cornerRadius = 8
            contentView.addSubview(cardView)
            
            let eTitle = NSTextField(labelWithString: "No Active Provider")
            eTitle.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            eTitle.textColor = .white
            eTitle.frame = NSRect(x: 16, y: 14, width: cardView.frame.width - 32, height: 18)
            cardView.addSubview(eTitle)
            
            let eDesc = NSTextField(labelWithString: "No active AI sessions were found (Antigravity, Claude, ChatGPT, Cursor, Copilot). Configure an API key (Gemini, OpenAI, Claude) or access token:")
            eDesc.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            eDesc.textColor = NSColor(white: 0.65, alpha: 1.0)
            eDesc.lineBreakMode = .byWordWrapping
            eDesc.frame = NSRect(x: 16, y: 38, width: cardView.frame.width - 32, height: 32)
            cardView.addSubview(eDesc)
            
            let openCfgBtn = NSButton(title: "Configure Providers", target: self, action: #selector(openSettings))
            openCfgBtn.isBordered = false
            openCfgBtn.wantsLayer = true
            openCfgBtn.layer?.backgroundColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x30/255.0, alpha: 1.0).cgColor
            openCfgBtn.layer?.cornerRadius = 5
            openCfgBtn.frame = NSRect(x: 16, y: 76, width: 170, height: 22)
            openCfgBtn.attributedTitle = NSAttributedString(
                string: "⚙️ Configure Providers",
                attributes: [
                    .foregroundColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold)
                ]
            )
            cardView.addSubview(openCfgBtn)
            y += emptyH + 14
        } else {
            for g in quota.groups {
                let cardHeight = 44 + CGFloat(g.buckets.count * 44 + 6)
                let cardView = FlippedBox(frame: NSRect(x: 16, y: y, width: windowWidth - 32, height: cardHeight))
                cardView.boxType = .custom
                cardView.fillColor = colorField1F
                cardView.borderColor = colorBorder
                cardView.borderWidth = 1
                cardView.cornerRadius = 8
                contentView.addSubview(cardView)
                
                let pLower = (g.provider ?? "").lowercased()
                let isStudio = pLower.contains("studio") || (pLower == "gemini" || pLower == "gemini_api") || g.name.lowercased().contains("gemini api")
                let isClaudePro = !isStudio && !pLower.contains("antigravity") && (pLower.contains("claude") || g.name.lowercased().contains("claude")) && !g.name.lowercased().contains("claude and gpt")
                let isChatGpt = pLower.contains("chatgpt") || g.name.lowercased().contains("chatgpt")
                let isCursor = pLower.contains("cursor") || g.name.lowercased().contains("cursor")
                let isCopilot = pLower.contains("copilot") || g.name.lowercased().contains("copilot") || pLower.contains("github")
                
                let customColors = QuotaManager.loadConfig().section_colors
                let accentColor: NSColor
                let tagText: String
                if isClaudePro {
                    accentColor = PastelTheme.getColor(for: "claude_pro", in: customColors)
                    tagText = "CLAUDE"
                } else if isChatGpt {
                    accentColor = PastelTheme.getColor(for: "chatgpt_subscription", in: customColors)
                    tagText = "CHATGPT"
                } else if isCursor {
                    accentColor = PastelTheme.getColor(for: "cursor", in: customColors)
                    tagText = "CURSOR"
                } else if isCopilot {
                    accentColor = PastelTheme.getColor(for: "github_copilot", in: customColors)
                    tagText = "COPILOT"
                } else if isStudio {
                    accentColor = PastelTheme.getColor(for: "gemini", in: customColors)
                    tagText = "GEMINI"
                } else {
                    accentColor = PastelTheme.getColor(for: "antigravity", in: customColors)
                    tagText = "ANTIGRAVITY"
                }
                
                // Group Title (Top Left)
                let cleanGroupName: String
                if isClaudePro {
                    cleanGroupName = "Claude"
                } else if isChatGpt {
                    cleanGroupName = "ChatGPT"
                } else if isCursor {
                    cleanGroupName = "Cursor"
                } else if isCopilot {
                    cleanGroupName = "Copilot"
                } else if isStudio {
                    cleanGroupName = "Google Gemini"
                } else {
                    cleanGroupName = g.name
                }
                let gTitle = NSTextField(labelWithString: cleanGroupName)
                gTitle.font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
                gTitle.textColor = NSColor(white: 0.95, alpha: 1.0)
                gTitle.frame = NSRect(x: 14, y: 12, width: cardView.frame.width - 170, height: 16)
                cardView.addSubview(gTitle)
                
                // Group Tag (Top Right)
                let tagLabel = NSTextField(labelWithString: tagText)
                tagLabel.font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
                tagLabel.textColor = accentColor
                tagLabel.alignment = .right
                tagLabel.frame = NSRect(x: cardView.frame.width - 150, y: 12, width: 136, height: 16)
                cardView.addSubview(tagLabel)
                
                // Header Separator
                let hSep = NSBox(frame: NSRect(x: 14, y: 34, width: cardView.frame.width - 28, height: 1))
                hSep.boxType = .custom
                hSep.fillColor = colorSep
                hSep.borderColor = .clear
                cardView.addSubview(hSep)
                
                var cardY: CGFloat = 44
                for (idx, b) in g.buckets.enumerated() {
                    if idx > 0 {
                        let sep = NSBox(frame: NSRect(x: 14, y: cardY - 5, width: cardView.frame.width - 28, height: 1))
                        sep.boxType = .custom
                        sep.fillColor = colorSep
                        sep.borderColor = .clear
                        cardView.addSubview(sep)
                        cardY += 4
                    }
                    
                    let bTitle = NSTextField(labelWithString: b.name)
                    bTitle.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
                    bTitle.textColor = .white
                    bTitle.frame = NSRect(x: 14, y: cardY, width: cardView.frame.width - 210, height: 16)
                    cardView.addSubview(bTitle)
                    
                    if let reset = b.reset_in, !reset.isEmpty {
                        let resetLabel = NSTextField(labelWithString: reset == "Now" ? "Renews now" : (reset == "Active" ? "Active" : "Renews in \(reset)"))
                        resetLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
                        resetLabel.textColor = NSColor(white: 0.50, alpha: 1.0)
                        resetLabel.alignment = .right
                        resetLabel.frame = NSRect(x: cardView.frame.width - 210, y: cardY + 2, width: 140, height: 13)
                        cardView.addSubview(resetLabel)
                    }
                    
                    let valStr = "\(b.remaining_pct)%"
                    let bVal = NSTextField(labelWithString: valStr)
                    bVal.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
                    if b.remaining_pct >= 50 {
                        bVal.textColor = accentColor
                    } else if b.remaining_pct >= 20 {
                        bVal.textColor = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
                    } else {
                        bVal.textColor = NSColor(srgbRed: 0xFF/255.0, green: 0x4D/255.0, blue: 0x4F/255.0, alpha: 1.0)
                    }
                    bVal.alignment = .right
                    bVal.frame = NSRect(x: cardView.frame.width - 66, y: cardY - 1, width: 52, height: 17)
                    cardView.addSubview(bVal)
                    
                    let barBg = NSBox(frame: NSRect(x: 14, y: cardY + 22, width: cardView.frame.width - 28, height: 6))
                    barBg.boxType = .custom
                    barBg.fillColor = colorTrack
                    barBg.borderColor = .clear
                    barBg.cornerRadius = 3
                    cardView.addSubview(barBg)
                    
                    let fillWidth = max(CGFloat(barBg.frame.width) * CGFloat(b.remaining_pct) / 100.0, 4)
                    let barFill = NSBox(frame: NSRect(x: 14, y: cardY + 22, width: fillWidth, height: 6))
                    barFill.boxType = .custom
                    barFill.fillColor = bVal.textColor ?? NSColor.systemGreen
                    barFill.borderColor = .clear
                    barFill.cornerRadius = 3
                    cardView.addSubview(barFill)
                    
                    cardY += 38
                }
                
                y += cardHeight + 14
            }
        }
        
        scrollView.documentView = contentView
        mainView.addSubview(scrollView)
        
        let btnBg = NSColor(srgbRed: 0xEE/255.0, green: 0xEE/255.0, blue: 0xF0/255.0, alpha: 1.0)
        let btnText = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        
        // ----------------- RODAPÉ (Linha 1: Botões com tamanho uniforme e distribuição igual) -----------------
        let footerY: CGFloat = 30
        let footerMargin: CGFloat = 16
        let footerGap: CGFloat = 8
        let totalBtnCount: CGFloat = 4
        let eachBtnW: CGFloat = floor((windowWidth - (footerMargin * 2) - (footerGap * (totalBtnCount - 1))) / totalBtnCount)
        
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        
        // 1. Atualizar
        let refreshBtn = NSButton(title: "", target: self, action: #selector(refreshClicked))
        refreshBtn.isBordered = false
        refreshBtn.wantsLayer = true
        refreshBtn.layer?.backgroundColor = btnBg.cgColor
        refreshBtn.layer?.cornerRadius = 6
        refreshBtn.frame = NSRect(x: footerMargin, y: footerY, width: eachBtnW, height: 28)
        refreshBtn.keyEquivalent = "r"
        refreshBtn.keyEquivalentModifierMask = .command
        refreshBtn.imagePosition = .imageLeading
        refreshBtn.imageHugsTitle = true
        refreshBtn.attributedTitle = NSAttributedString(
            string: "Refresh",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                .paragraphStyle: pStyle
            ]
        )
        if let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                refreshBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                refreshBtn.image = symbol.withSymbolConfiguration(config)
            }
        }
        self.refreshBtn = refreshBtn
        mainView.addSubview(refreshBtn)
        
        // 2. Alternar Modo de Tela (HUD Bar)
        let hudBtn = NSButton(title: "", target: self, action: #selector(toggleModeClicked))
        hudBtn.isBordered = false
        hudBtn.wantsLayer = true
        hudBtn.layer?.backgroundColor = btnBg.cgColor
        hudBtn.layer?.cornerRadius = 6
        hudBtn.frame = NSRect(x: footerMargin + (eachBtnW + footerGap), y: footerY, width: eachBtnW, height: 28)
        hudBtn.keyEquivalent = "m"
        hudBtn.keyEquivalentModifierMask = .command
        hudBtn.imagePosition = .imageLeading
        hudBtn.imageHugsTitle = true
        hudBtn.toolTip = "Switch to HUD Bar Mode (Cmd+M)"
        hudBtn.attributedTitle = NSAttributedString(
            string: "HUD Bar",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                .paragraphStyle: pStyle
            ]
        )
        if let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "HUD Bar") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                hudBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                hudBtn.image = symbol.withSymbolConfiguration(config)
            }
        }
        mainView.addSubview(hudBtn)
        
        // 3. Settings (⚙️)
        let settingsBtn = NSButton(title: "", target: self, action: #selector(openSettings))
        settingsBtn.isBordered = false
        settingsBtn.wantsLayer = true
        settingsBtn.layer?.backgroundColor = btnBg.cgColor
        settingsBtn.layer?.cornerRadius = 6
        settingsBtn.frame = NSRect(x: footerMargin + 2 * (eachBtnW + footerGap), y: footerY, width: eachBtnW, height: 28)
        settingsBtn.keyEquivalent = ","
        settingsBtn.keyEquivalentModifierMask = .command
        settingsBtn.imagePosition = .imageLeading
        settingsBtn.imageHugsTitle = true
        settingsBtn.toolTip = "Configure Providers & API Keys (Cmd+,)"
        settingsBtn.attributedTitle = NSAttributedString(
            string: "Settings",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                .paragraphStyle: pStyle
            ]
        )
        if let symbol = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                settingsBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                settingsBtn.image = symbol.withSymbolConfiguration(config)
            }
        }
        mainView.addSubview(settingsBtn)
        
        // 4. Botão '✕' Close (Encerra o aplicativo)
        let closeBtn = NSButton(title: "", target: self, action: #selector(closeClicked))
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = btnBg.cgColor
        closeBtn.layer?.cornerRadius = 6
        closeBtn.frame = NSRect(x: footerMargin + 3 * (eachBtnW + footerGap), y: footerY, width: eachBtnW, height: 28)
        closeBtn.keyEquivalent = "q"
        closeBtn.keyEquivalentModifierMask = .command
        closeBtn.imagePosition = .imageLeading
        closeBtn.imageHugsTitle = true
        closeBtn.toolTip = "Quit AI Gauge (Cmd+Q)"
        closeBtn.attributedTitle = NSAttributedString(
            string: "Close",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                .paragraphStyle: pStyle
            ]
        )
        if let symbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                closeBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                closeBtn.image = symbol.withSymbolConfiguration(config)
            }
        }
        mainView.addSubview(closeBtn)
        
        // ----------------- RODAPÉ (Linha 2: Menção vh2c.com.br SEMPRE padrão) -----------------
        let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
        brandBtn.isBordered = false
        brandBtn.frame = NSRect(x: 14, y: 5, width: windowWidth - 28, height: 20)
        brandBtn.toolTip = "Support AI Gauge via Stripe Donation"
        brandBtn.attributedTitle = NSAttributedString(
            string: "Developed by vh2c.com.br",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x9C/255.0, green: 0xA3/255.0, blue: 0xAF/255.0, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium)
            ]
        )
        mainView.addSubview(brandBtn)
        
        if isFirstLaunch {
            isFirstLaunch = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Evitar roubar foco da janela de configurações se o usuário estiver nela
            if settingsWindow == nil || settingsWindow?.isVisible == false {
                window.orderFront(nil)
            }
        }
    }
    
    // MARK: - Settings Window
    @objc func openSettings() {
        if settingsWindow == nil {
            let w: CGFloat = 520
            let h: CGFloat = 660
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Settings - AI Gauge"
            win.appearance = NSAppearance(named: .darkAqua)
            win.backgroundColor = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
            win.isReleasedWhenClosed = false
            win.level = .floating // Permanece flutuando sobre a janela principal sem ser ocultada
            win.center()
            settingsWindow = win
        }
        
        guard let win = settingsWindow else { return }
        win.appearance = NSAppearance(named: .darkAqua)
        setupSettingsUI(in: win)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupSettingsUI(in win: NSWindow) {
        let cfg = QuotaManager.loadConfig()
        let providers = cfg.providers ?? [:]
        let hiddenSet = Set(cfg.hidden_hud_gauges ?? [])
        self.hudGaugeCheckboxes.removeAll()
        var currentColors = cfg.section_colors ?? PastelTheme.defaultColors
        self.selectedSectionColors = currentColors
        
        func addPastelPicker(providerKey: String, in parent: NSView) {
            let pickerW: CGFloat = 114
            let pickerX = cardW - pickerW - 8
            let labelX = pickerX - 38
            
            let lbl = NSTextField(labelWithString: "Color:")
            lbl.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
            lbl.textColor = NSColor(white: 0.60, alpha: 1.0)
            lbl.frame = NSRect(x: labelX, y: 13, width: 36, height: 16)
            parent.addSubview(lbl)
            
            let curHex = currentColors[providerKey] ?? (PastelTheme.defaultColors[providerKey] ?? "#8FBCFF")
            let picker = PastelColorPickerView(
                frame: NSRect(x: pickerX, y: 12, width: pickerW, height: 18),
                selectedHex: curHex
            ) { [weak self] newHex in
                self?.selectedSectionColors[providerKey] = newHex
            }
            parent.addSubview(picker)
        }
        
        let colorBg18 = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        let colorCard = NSColor(srgbRed: 0x1E/255.0, green: 0x1E/255.0, blue: 0x22/255.0, alpha: 1.0)
        let colorBorder = NSColor(srgbRed: 0x2E/255.0, green: 0x2E/255.0, blue: 0x33/255.0, alpha: 1.0)
        let colorSep = NSColor(srgbRed: 0x28/255.0, green: 0x28/255.0, blue: 0x2E/255.0, alpha: 1.0)
        let claudeColor = NSColor(srgbRed: 0xD7/255.0, green: 0x8C/255.0, blue: 0x68/255.0, alpha: 1.0)
        
        let mainView = FlippedContentView(frame: win.contentView!.bounds)
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = colorBg18.cgColor
        win.contentView = mainView
        
        let winW = win.contentView!.bounds.width
        let winH = win.contentView!.bounds.height
        
        let headerH: CGFloat = 62
        let footerH: CGFloat = 56
        
        // ----------------- HEADER FIXO NO TOPO -----------------
        let headerView = FlippedContentView(frame: NSRect(x: 0, y: 0, width: winW, height: headerH))
        let titleLabel = NSTextField(labelWithString: "⚙️ AI Providers & Gauge Selection")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 18, y: 12, width: winW - 36, height: 20)
        headerView.addSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: "Enable providers and select which Gauges appear in the HUD Side Bar:")
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        subLabel.frame = NSRect(x: 18, y: 34, width: winW - 36, height: 16)
        headerView.addSubview(subLabel)
        
        let headerDiv = NSBox(frame: NSRect(x: 18, y: headerH - 1, width: winW - 36, height: 1))
        headerDiv.boxType = .custom
        headerDiv.fillColor = colorSep
        headerDiv.borderColor = .clear
        headerView.addSubview(headerDiv)
        mainView.addSubview(headerView)
        
        // ----------------- SCROLL VIEW DE CARDS -----------------
        let scrollY = headerH
        let scrollH = winH - headerH - footerH
        let cardW = winW - 36
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: scrollY, width: winW, height: scrollH))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        
        let scrollContent = FlippedContentView(frame: NSRect(x: 0, y: 0, width: winW, height: 1100))
        
        var cy: CGFloat = 12.0
        
        func createHudSectionLabel(y: CGFloat, in parent: NSView) -> CGFloat {
            let sep = NSBox(frame: NSRect(x: 14, y: y, width: cardW - 28, height: 1))
            sep.boxType = .custom
            sep.fillColor = colorSep
            sep.borderColor = .clear
            parent.addSubview(sep)
            
            let lbl = NSTextField(labelWithString: "Gauges in HUD Side Bar:")
            lbl.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            lbl.textColor = NSColor(white: 0.55, alpha: 1.0)
            lbl.frame = NSRect(x: 14, y: y + 6, width: cardW - 28, height: 14)
            parent.addSubview(lbl)
            return y + 24
        }
        
        func addCheckbox(id: String, title: String, frame: NSRect, in parent: NSView) {
            let btn = ContrastCheckbox(frame: frame)
            btn.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor(white: 0.92, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .medium)
                ]
            )
            btn.state = hiddenSet.contains(id) ? .off : .on
            parent.addSubview(btn)
            self.hudGaugeCheckboxes[id] = btn
        }
        
        let colW = (cardW - 36) / 2.0
        
        // 1. Antigravity IDE Card
        let antiCardH: CGFloat = 150
        let antiCard = FlippedBox(frame: NSRect(x: 18, y: cy, width: cardW, height: antiCardH))
        antiCard.boxType = .custom
        antiCard.fillColor = colorCard
        antiCard.borderColor = colorBorder
        antiCard.borderWidth = 1
        antiCard.cornerRadius = 8
        scrollContent.addSubview(antiCard)
        
        let antiCfg = providers["antigravity"]
        let antiBtn = ContrastCheckbox(frame: NSRect(x: 14, y: 12, width: cardW - 225, height: 20))
        antiBtn.state = (antiCfg?.enabled ?? true) ? .on : .off
        antiBtn.attributedTitle = NSAttributedString(
            string: "Antigravity",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        antiCard.addSubview(antiBtn)
        self.antigravityCheck = antiBtn
        addPastelPicker(providerKey: "antigravity", in: antiCard)
        
        let antiDesc = NSTextField(labelWithString: "Detects quotas from the running IDE, or via a headless probe when it is closed.")
        antiDesc.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        antiDesc.textColor = NSColor(white: 0.55, alpha: 1.0)
        antiDesc.frame = NSRect(x: 36, y: 34, width: cardW - 50, height: 15)
        antiCard.addSubview(antiDesc)
        
        let antiHudY = createHudSectionLabel(y: 54, in: antiCard)
        addCheckbox(id: "gemini-weekly", title: "Gemini Weekly", frame: NSRect(x: 14, y: antiHudY, width: colW, height: 18), in: antiCard)
        addCheckbox(id: "gemini-5h", title: "Gemini (5 Horas)", frame: NSRect(x: 14 + colW, y: antiHudY, width: colW, height: 18), in: antiCard)
        addCheckbox(id: "3p-weekly", title: "Claude / GPT Weekly", frame: NSRect(x: 14, y: antiHudY + 22, width: colW, height: 18), in: antiCard)
        addCheckbox(id: "3p-5h", title: "Claude / GPT (5 Horas)", frame: NSRect(x: 14 + colW, y: antiHudY + 22, width: colW, height: 18), in: antiCard)
        addCheckbox(id: "gemini-argon-wtu-weekly", title: "Argon Weekly", frame: NSRect(x: 14, y: antiHudY + 44, width: colW, height: 18), in: antiCard)
        
        cy += antiCardH + 12
        
        // 2. Claude Pro Card (#D78C68)
        let claudeCardH: CGFloat = 154
        let claudeCard = FlippedBox(frame: NSRect(x: 18, y: cy, width: cardW, height: claudeCardH))
        claudeCard.boxType = .custom
        claudeCard.fillColor = colorCard
        claudeCard.borderColor = colorBorder
        claudeCard.borderWidth = 1
        claudeCard.cornerRadius = 8
        scrollContent.addSubview(claudeCard)
        
        let claudeCfg = providers["claude_pro"]
        let claudeBtn = ContrastCheckbox(frame: NSRect(x: 14, y: 12, width: cardW - 225, height: 20))
        claudeBtn.state = (claudeCfg?.enabled ?? true) ? .on : .off
        claudeBtn.attributedTitle = NSAttributedString(
            string: "Claude",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        claudeCard.addSubview(claudeBtn)
        self.claudeProCheck = claudeBtn
        addPastelPicker(providerKey: "claude_pro", in: claudeCard)
        
        let hasKeychain = QuotaManager.hasClaudeProKeychainSession()
        let statusMsg = hasKeychain
            ? "✓ Active session detected in macOS Keychain (Claude Code / Antigravity)"
            : "ℹ️ Session not found in Keychain. Sign in to Antigravity or paste a token:"
        let claudeStatus = NSTextField(labelWithString: statusMsg)
        claudeStatus.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        claudeStatus.textColor = hasKeychain ? claudeColor : NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
        claudeStatus.frame = NSRect(x: 36, y: 34, width: cardW - 50, height: 15)
        claudeCard.addSubview(claudeStatus)
        self.claudeProStatusLabel = claudeStatus
        
        let claudeToken = makeCenteredDarkSecureField(
            frame: NSRect(x: 14, y: 52, width: cardW - 28, height: 32),
            placeholder: hasKeychain ? "Token OAuth gerenciado automaticamente pelo Keychain" : "Token OAuth Claude (sk-ant-oat01-...)",
            value: claudeCfg?.token ?? ""
        )
        claudeCard.addSubview(claudeToken)
        self.claudeProTokenField = claudeToken
        
        let claudeHudY = createHudSectionLabel(y: 92, in: claudeCard)
        addCheckbox(id: "claude-pro-5h", title: "5-Hour Window (5h)", frame: NSRect(x: 14, y: claudeHudY, width: colW, height: 18), in: claudeCard)
        addCheckbox(id: "claude-pro-7d", title: "Weekly Quota (7 days)", frame: NSRect(x: 14 + colW, y: claudeHudY, width: colW, height: 18), in: claudeCard)
        
        cy += claudeCardH + 12
        
        // 3. ChatGPT Plus / Pro Card (#10A37F)
        let chatgptCardH: CGFloat = 154
        let chatgptCard = FlippedBox(frame: NSRect(x: 18, y: cy, width: cardW, height: chatgptCardH))
        chatgptCard.boxType = .custom
        chatgptCard.fillColor = colorCard
        chatgptCard.borderColor = colorBorder
        chatgptCard.borderWidth = 1
        chatgptCard.cornerRadius = 8
        scrollContent.addSubview(chatgptCard)
        
        let chatgptCfg = providers["chatgpt_subscription"]
        let chatgptBtn = ContrastCheckbox(frame: NSRect(x: 14, y: 12, width: cardW - 225, height: 20))
        chatgptBtn.state = (chatgptCfg?.enabled ?? true) ? .on : .off
        chatgptBtn.attributedTitle = NSAttributedString(
            string: "ChatGPT",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        chatgptCard.addSubview(chatgptBtn)
        self.chatgptCheck = chatgptBtn
        addPastelPicker(providerKey: "chatgpt_subscription", in: chatgptCard)
        
        let hasGptKeychain = QuotaManager.hasChatGPTKeychainSession()
        let gptStatusMsg = hasGptKeychain
            ? "✓ Active session detected (ChatGPT App / Codex)"
            : "ℹ️ Track the GPT-4o window and weekly o1 quota:"
        let gptStatus = NSTextField(labelWithString: gptStatusMsg)
        gptStatus.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        gptStatus.textColor = hasGptKeychain ? NSColor(srgbRed: 0x10/255.0, green: 0xA3/255.0, blue: 0x7F/255.0, alpha: 1.0) : NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
        gptStatus.frame = NSRect(x: 36, y: 34, width: cardW - 50, height: 15)
        chatgptCard.addSubview(gptStatus)
        self.chatgptStatusLabel = gptStatus
        
        let chatgptToken = makeCenteredDarkSecureField(
            frame: NSRect(x: 14, y: 52, width: cardW - 28, height: 32),
            placeholder: hasGptKeychain ? "Token managed automatically" : "ChatGPT Access Token / Session Token",
            value: chatgptCfg?.token ?? ""
        )
        chatgptCard.addSubview(chatgptToken)
        self.chatgptTokenField = chatgptToken
        
        let gptHudY = createHudSectionLabel(y: 92, in: chatgptCard)
        addCheckbox(id: "chatgpt-4o-3h", title: "GPT-4o (3h Window)", frame: NSRect(x: 14, y: gptHudY, width: colW, height: 18), in: chatgptCard)
        addCheckbox(id: "chatgpt-o1-weekly", title: "o1 Reasoning (Weekly)", frame: NSRect(x: 14 + colW, y: gptHudY, width: colW, height: 18), in: chatgptCard)
        
        cy += chatgptCardH + 12
        
        // 4. Cursor IDE Card
        let cursorCardH: CGFloat = 138
        let cursorCard = FlippedBox(frame: NSRect(x: 18, y: cy, width: cardW, height: cursorCardH))
        cursorCard.boxType = .custom
        cursorCard.fillColor = colorCard
        cursorCard.borderColor = colorBorder
        cursorCard.borderWidth = 1
        cursorCard.cornerRadius = 8
        scrollContent.addSubview(cursorCard)
        
        let cursorCfg = providers["cursor"]
        let cursorBtn = ContrastCheckbox(frame: NSRect(x: 14, y: 12, width: cardW - 225, height: 20))
        cursorBtn.state = (cursorCfg?.enabled ?? true) ? .on : .off
        cursorBtn.attributedTitle = NSAttributedString(
            string: "Cursor",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        cursorCard.addSubview(cursorBtn)
        self.cursorCheck = cursorBtn
        addPastelPicker(providerKey: "cursor", in: cursorCard)
        
        let hasCursor = QuotaManager.hasCursor()
        let cursorStatus = NSTextField(labelWithString: hasCursor ? "✓ Cursor editor detected on this Mac (Claude 3.5 & GPT-4o)" : "ℹ️ Monthly Fast Requests quota of the Pro plan:")
        cursorStatus.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        cursorStatus.textColor = hasCursor ? NSColor(srgbRed: 0xA8/255.0, green: 0x55/255.0, blue: 0xF7/255.0, alpha: 1.0) : NSColor(white: 0.6, alpha: 1.0)
        cursorStatus.frame = NSRect(x: 36, y: 34, width: cardW - 50, height: 15)
        cursorCard.addSubview(cursorStatus)
        
        let cursorToken = makeCenteredDarkSecureField(
            frame: NSRect(x: 14, y: 52, width: cardW - 28, height: 32),
            placeholder: "Cursor Session Token (optional if signed in to Cursor)",
            value: cursorCfg?.token ?? ""
        )
        cursorCard.addSubview(cursorToken)
        self.cursorTokenField = cursorToken
        
        let cursorHudY = createHudSectionLabel(y: 92, in: cursorCard)
        addCheckbox(id: "cursor-fast-requests", title: "Fast Requests", frame: NSRect(x: 14, y: cursorHudY, width: colW, height: 18), in: cursorCard)
        addCheckbox(id: "cursor-monthly-cycle", title: "Monthly Cycle", frame: NSRect(x: 14 + colW, y: cursorHudY, width: colW, height: 18), in: cursorCard)
        
        cy += cursorCardH + 12
        
        // 5. GitHub Copilot (VS Code) Card
        let copilotCardH: CGFloat = 138
        let copilotCard = FlippedBox(frame: NSRect(x: 18, y: cy, width: cardW, height: copilotCardH))
        copilotCard.boxType = .custom
        copilotCard.fillColor = colorCard
        copilotCard.borderColor = colorBorder
        copilotCard.borderWidth = 1
        copilotCard.cornerRadius = 8
        scrollContent.addSubview(copilotCard)
        
        let copilotCfg = providers["github_copilot"]
        let copilotBtn = ContrastCheckbox(frame: NSRect(x: 14, y: 12, width: cardW - 225, height: 20))
        copilotBtn.state = (copilotCfg?.enabled ?? true) ? .on : .off
        copilotBtn.attributedTitle = NSAttributedString(
            string: "Copilot",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        copilotCard.addSubview(copilotBtn)
        self.copilotCheck = copilotBtn
        addPastelPicker(providerKey: "github_copilot", in: copilotCard)
        
        let hasCopilot = QuotaManager.hasCopilot()
        let copilotStatus = NSTextField(labelWithString: hasCopilot ? "✓ Visual Studio Code & Copilot detected on this Mac" : "ℹ️ VS Code Copilot Chat and Code Completions:")
        copilotStatus.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        copilotStatus.textColor = hasCopilot ? NSColor(srgbRed: 0xFF/255.0, green: 0x52/255.0, blue: 0x65/255.0, alpha: 1.0) : NSColor(white: 0.6, alpha: 1.0)
        copilotStatus.frame = NSRect(x: 36, y: 34, width: cardW - 50, height: 15)
        copilotCard.addSubview(copilotStatus)
        
        let copilotToken = makeCenteredDarkSecureField(
            frame: NSRect(x: 14, y: 52, width: cardW - 28, height: 32),
            placeholder: "GitHub Personal Access Token (opcional)",
            value: copilotCfg?.token ?? ""
        )
        copilotCard.addSubview(copilotToken)
        self.copilotTokenField = copilotToken
        
        let copilotHudY = createHudSectionLabel(y: 92, in: copilotCard)
        addCheckbox(id: "copilot-chat-limit", title: "Copilot Chat Limits", frame: NSRect(x: 14, y: copilotHudY, width: colW, height: 18), in: copilotCard)
        addCheckbox(id: "copilot-completions-rate", title: "Completions Rate Limits", frame: NSRect(x: 14 + colW, y: copilotHudY, width: colW, height: 18), in: copilotCard)
        
        cy += copilotCardH + 12
        
        // 4. Google Gemini API Card
        let geminiCardH: CGFloat = 196
        let geminiCard = FlippedBox(frame: NSRect(x: 18, y: cy, width: cardW, height: geminiCardH))
        geminiCard.boxType = .custom
        geminiCard.fillColor = colorCard
        geminiCard.borderColor = colorBorder
        geminiCard.borderWidth = 1
        geminiCard.cornerRadius = 8
        scrollContent.addSubview(geminiCard)
        
        let geminiCfg = providers["gemini"]
        let geminiBtn = ContrastCheckbox(frame: NSRect(x: 14, y: 12, width: cardW - 225, height: 20))
        geminiBtn.state = (geminiCfg?.enabled ?? false) ? .on : .off
        geminiBtn.attributedTitle = NSAttributedString(
            string: "Google Gemini",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        geminiCard.addSubview(geminiBtn)
        self.geminiCheck = geminiBtn
        addPastelPicker(providerKey: "gemini", in: geminiCard)
        
        let geminiHint = NSTextField(labelWithString: "💡 Google AI Studio keys start with AIzaSy...")
        geminiHint.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        geminiHint.textColor = NSColor(white: 0.55, alpha: 1.0)
        geminiHint.frame = NSRect(x: 36, y: 34, width: cardW - 50, height: 15)
        geminiCard.addSubview(geminiHint)
        
        let fieldW: CGFloat = cardW - 28 - 92
        let geminiField = makeCenteredDarkSecureField(
            frame: NSRect(x: 14, y: 52, width: fieldW, height: 34),
            placeholder: "Gemini API Key (AIzaSy...)",
            value: geminiCfg?.api_key ?? ""
        )
        geminiCard.addSubview(geminiField)
        self.geminiKeyField = geminiField
        
        let testBtn = NSButton(title: "Test", target: self, action: #selector(testGeminiKeyClicked))
        testBtn.isBordered = false
        testBtn.wantsLayer = true
        testBtn.layer?.backgroundColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x30/255.0, alpha: 1.0).cgColor
        testBtn.layer?.cornerRadius = 6
        testBtn.frame = NSRect(x: 14 + fieldW + 8, y: 52, width: 84, height: 34)
        testBtn.attributedTitle = NSAttributedString(
            string: "Test",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
        )
        geminiCard.addSubview(testBtn)
        self.geminiTestBtn = testBtn
        
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        statusLabel.textColor = NSColor(white: 0.60, alpha: 1.0)
        statusLabel.frame = NSRect(x: 14, y: 92, width: cardW - 28, height: 16)
        geminiCard.addSubview(statusLabel)
        self.geminiStatusLabel = statusLabel
        
        let geminiLink = NSButton(title: "", target: self, action: #selector(openAiStudioLink))
        geminiLink.isBordered = false
        geminiLink.frame = NSRect(x: 14, y: 112, width: cardW - 28, height: 18)
        geminiLink.attributedTitle = NSAttributedString(
            string: "Get a Free Key at Google AI Studio (aistudio.google.com) ↗",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular)
            ]
        )
        geminiCard.addSubview(geminiLink)
        
        let geminiHudY = createHudSectionLabel(y: 136, in: geminiCard)
        let gColW = (cardW - 36) / 3.0
        addCheckbox(id: "gemini-flash-rpm", title: "Flash RPM", frame: NSRect(x: 14, y: geminiHudY, width: gColW, height: 18), in: geminiCard)
        addCheckbox(id: "gemini-pro-rpm", title: "Pro RPM", frame: NSRect(x: 14 + gColW, y: geminiHudY, width: gColW, height: 18), in: geminiCard)
        addCheckbox(id: "gemini-key-status", title: "Key Status", frame: NSRect(x: 14 + gColW * 2, y: geminiHudY, width: gColW, height: 18), in: geminiCard)
        
        cy += geminiCardH + 12
        
        // 4. OpenAI Card
        let openCardH: CGFloat = 88
        let openCard = FlippedBox(frame: NSRect(x: 18, y: cy, width: cardW, height: openCardH))
        openCard.boxType = .custom
        openCard.fillColor = colorCard
        openCard.borderColor = colorBorder
        openCard.borderWidth = 1
        openCard.cornerRadius = 8
        scrollContent.addSubview(openCard)
        
        let openCfg = providers["openai"]
        let openBtn = ContrastCheckbox(frame: NSRect(x: 14, y: 12, width: cardW - 225, height: 20))
        openBtn.state = (openCfg?.enabled ?? false) ? .on : .off
        openBtn.attributedTitle = NSAttributedString(
            string: "OpenAI",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        openCard.addSubview(openBtn)
        self.openaiCheck = openBtn
        addPastelPicker(providerKey: "openai", in: openCard)
        
        let openField = makeCenteredDarkSecureField(
            frame: NSRect(x: 14, y: 38, width: cardW - 28, height: 34),
            placeholder: "OpenAI API Key (sk-...)",
            value: openCfg?.api_key ?? ""
        )
        openCard.addSubview(openField)
        self.openaiKeyField = openField
        
        cy += openCardH + 12
        
        // 5. Anthropic Claude API Card
        let antCardH: CGFloat = 88
        let antCard = FlippedBox(frame: NSRect(x: 18, y: cy, width: cardW, height: antCardH))
        antCard.boxType = .custom
        antCard.fillColor = colorCard
        antCard.borderColor = colorBorder
        antCard.borderWidth = 1
        antCard.cornerRadius = 8
        scrollContent.addSubview(antCard)
        
        let antCfg = providers["anthropic"]
        let antBtn = ContrastCheckbox(frame: NSRect(x: 14, y: 12, width: cardW - 225, height: 20))
        antBtn.state = (antCfg?.enabled ?? false) ? .on : .off
        antBtn.attributedTitle = NSAttributedString(
            string: "Anthropic",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        antCard.addSubview(antBtn)
        self.anthropicCheck = antBtn
        addPastelPicker(providerKey: "anthropic", in: antCard)
        
        let antField = makeCenteredDarkSecureField(
            frame: NSRect(x: 14, y: 38, width: cardW - 28, height: 34),
            placeholder: "Anthropic API Key (sk-ant-...)",
            value: antCfg?.api_key ?? ""
        )
        antCard.addSubview(antField)
        self.anthropicKeyField = antField
        
        cy += antCardH + 16
        
        scrollContent.setFrameSize(NSSize(width: winW, height: cy))
        scrollView.documentView = scrollContent
        mainView.addSubview(scrollView)
        
        // ----------------- RODAPÉ FIXO NA PARTE INFERIOR -----------------
        let footerView = FlippedContentView(frame: NSRect(x: 0, y: winH - footerH, width: winW, height: footerH))
        
        let footerDiv = NSBox(frame: NSRect(x: 18, y: 0, width: winW - 36, height: 1))
        footerDiv.boxType = .custom
        footerDiv.fillColor = colorSep
        footerDiv.borderColor = .clear
        footerView.addSubview(footerDiv)
        
        let saveBtn = NSButton(title: "Save & Refresh", target: self, action: #selector(saveSettingsClicked))
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.backgroundColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0).cgColor
        saveBtn.layer?.cornerRadius = 6
        saveBtn.frame = NSRect(x: 14, y: 11, width: 130, height: 34)
        saveBtn.attributedTitle = NSAttributedString(
            string: "Save & Refresh",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x12/255.0, green: 0x12/255.0, blue: 0x12/255.0, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .bold)
            ]
        )
        footerView.addSubview(saveBtn)
        
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelSettingsClicked))
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.backgroundColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2E/255.0, alpha: 1.0).cgColor
        cancelBtn.layer?.cornerRadius = 6
        cancelBtn.frame = NSRect(x: 150, y: 11, width: 80, height: 34)
        cancelBtn.attributedTitle = NSAttributedString(
            string: "Cancel",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        footerView.addSubview(cancelBtn)
        
        let obBtn = NSButton(title: "Assistente Inicial...", target: self, action: #selector(openOnboardingFromSettings))
        obBtn.isBordered = false
        obBtn.wantsLayer = true
        obBtn.layer?.backgroundColor = NSColor(srgbRed: 0x24/255.0, green: 0x24/255.0, blue: 0x2C/255.0, alpha: 1.0).cgColor
        obBtn.layer?.cornerRadius = 6
        obBtn.frame = NSRect(x: 238, y: 11, width: 140, height: 34)
        obBtn.attributedTitle = NSAttributedString(
            string: "Assistente Inicial...",
            attributes: [
                .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium)
            ]
        )
        footerView.addSubview(obBtn)
        
        let brandBtn = NSButton(title: "vh2c.com.br", target: self, action: #selector(brandClicked))
        brandBtn.isBordered = false
        brandBtn.frame = NSRect(x: winW - 110, y: 18, width: 96, height: 20)
        brandBtn.attributedTitle = NSAttributedString(
            string: "vh2c.com.br",
            attributes: [
                .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11, weight: .medium)
            ]
        )
        footerView.addSubview(brandBtn)
        
        mainView.addSubview(footerView)
    }
    
    @objc func testGeminiKeyClicked() {
        let key = geminiKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if key.isEmpty {
            geminiStatusLabel?.stringValue = "⚠️ Enter an API key to test"
            geminiStatusLabel?.textColor = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
            return
        }
        
        if key.hasPrefix("AQ.") || key.hasPrefix("ya29.") {
            geminiStatusLabel?.stringValue = "⚠️ Use a Google AI Studio key (starts with AIzaSy...)"
            geminiStatusLabel?.textColor = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
            return
        }
        
        geminiTestBtn?.isEnabled = false
        geminiStatusLabel?.stringValue = "Testing connection to Google AI..."
        geminiStatusLabel?.textColor = NSColor(white: 0.70, alpha: 1.0)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let nodeBin = QuotaManager.findNodeBinary()
            let task = Process()
            if nodeBin.hasPrefix("/") {
                task.executableURL = URL(fileURLWithPath: nodeBin)
                task.arguments = [QuotaManager.engineScript, "--test-gemini", key]
            } else {
                task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                task.arguments = ["node", QuotaManager.engineScript, "--test-gemini", key]
            }
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            task.environment = env
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    self?.geminiTestBtn?.isEnabled = true
                    if output.contains("\"ok\":true") {
                        self?.geminiStatusLabel?.stringValue = "✓ Valid key! Gemini models connected."
                        self?.geminiStatusLabel?.textColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
                        self?.geminiCheck?.state = .on
                    } else {
                        self?.geminiStatusLabel?.stringValue = "✕ Not authorized. Get a key at aistudio.google.com"
                        self?.geminiStatusLabel?.textColor = NSColor(srgbRed: 0xFF/255.0, green: 0x4D/255.0, blue: 0x4F/255.0, alpha: 1.0)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.geminiTestBtn?.isEnabled = true
                    self?.geminiStatusLabel?.stringValue = "✕ Error: \(error.localizedDescription)"
                    self?.geminiStatusLabel?.textColor = NSColor.systemRed
                }
            }
        }
    }
    
    @objc func openAiStudioLink() {
        if let url = URL(string: "https://aistudio.google.com/app/apikey") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func saveSettingsClicked() {
        var cfg = QuotaManager.loadConfig()
        if cfg.providers == nil { cfg.providers = [:] }
        
        cfg.providers?["antigravity"] = ProviderConfig(
            enabled: antigravityCheck?.state == .on,
            api_key: nil,
            token: nil
        )
        cfg.providers?["claude_pro"] = ProviderConfig(
            enabled: claudeProCheck?.state == .on,
            api_key: nil,
            token: claudeProTokenField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        cfg.providers?["chatgpt_subscription"] = ProviderConfig(
            enabled: chatgptCheck?.state == .on,
            api_key: nil,
            token: chatgptTokenField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        cfg.providers?["cursor"] = ProviderConfig(
            enabled: cursorCheck?.state == .on,
            api_key: nil,
            token: cursorTokenField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        cfg.providers?["github_copilot"] = ProviderConfig(
            enabled: copilotCheck?.state == .on,
            api_key: nil,
            token: copilotTokenField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        cfg.providers?["gemini"] = ProviderConfig(
            enabled: geminiCheck?.state == .on,
            api_key: geminiKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            token: nil
        )
        cfg.providers?["openai"] = ProviderConfig(
            enabled: openaiCheck?.state == .on,
            api_key: openaiKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            token: nil
        )
        cfg.providers?["anthropic"] = ProviderConfig(
            enabled: anthropicCheck?.state == .on,
            api_key: anthropicKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            token: nil
        )
        
        var hiddenList: [String] = []
        for (id, btn) in hudGaugeCheckboxes {
            if btn.state == .off {
                hiddenList.append(id)
            }
        }
        cfg.hidden_hud_gauges = hiddenList
        cfg.section_colors = self.selectedSectionColors
        
        QuotaManager.saveConfig(cfg)
        settingsWindow?.orderOut(nil)
        performRefresh(animated: true)
    }
    
    @objc func cancelSettingsClicked() {
        settingsWindow?.orderOut(nil)
    }
    
    @objc func brandClicked() {
        let mid = getMachineId()
        let donateUrlStr = mid.isEmpty
            ? "https://ai-gauge.vh2c.com.br/donate"
            : "https://ai-gauge.vh2c.com.br/donate?mid=\(mid)"
        if let url = URL(string: donateUrlStr) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func openExternalUrl(_ sender: Any?) {
        var target: String?
        if let btn = sender as? UrlButton {
            target = btn.targetUrl
        }
        let urlStr = target?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = urlStr, !s.isEmpty, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "https://github.com/vh2c/ai-gauge/releases/latest") {
            NSWorkspace.shared.open(fallback)
        }
    }
    
    // MARK: - Onboarding Window
    @objc func openOnboardingFromSettings() {
        settingsWindow?.orderOut(nil)
        openOnboarding()
    }
    
    @objc func openOnboarding() {
        if onboardingWindow == nil {
            let w: CGFloat = 520
            let h: CGFloat = 670
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "AI Gauge - Setup Assistant"
            win.appearance = NSAppearance(named: .darkAqua)
            win.backgroundColor = NSColor(srgbRed: 0x14/255.0, green: 0x14/255.0, blue: 0x18/255.0, alpha: 1.0)
            win.isReleasedWhenClosed = false
            win.level = .floating
            win.center()
            win.delegate = self
            onboardingWindow = win
        }
        
        guard let win = onboardingWindow else { return }
        setupOnboardingUI(in: win)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupOnboardingUI(in win: NSWindow) {
        let winW = win.contentView!.bounds.width
        
        let colorBg = NSColor(srgbRed: 0x14/255.0, green: 0x14/255.0, blue: 0x18/255.0, alpha: 1.0)
        let colorCard = NSColor(srgbRed: 0x1E/255.0, green: 0x1E/255.0, blue: 0x24/255.0, alpha: 1.0)
        let colorBorder = NSColor(srgbRed: 0x2E/255.0, green: 0x2E/255.0, blue: 0x36/255.0, alpha: 1.0)
        let colorSep = NSColor(srgbRed: 0x26/255.0, green: 0x26/255.0, blue: 0x2E/255.0, alpha: 1.0)
        let colorGreen = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
        let colorGreenBg = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 0.12)
        let colorGrayBg = NSColor(white: 0.25, alpha: 0.25)
        
        let mainView = FlippedContentView(frame: win.contentView!.bounds)
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = colorBg.cgColor
        win.contentView = mainView
        
        // Header
        let titleLabel = NSTextField(labelWithString: "⚡ AI Gauge - Initial Setup")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 24, y: 18, width: winW - 48, height: 22)
        mainView.addSubview(titleLabel)
        
        let subLabel = NSTextField(wrappingLabelWithString: "We detected the AI apps available on this Mac. Select which quotas you want to monitor in your Cockpit:")
        subLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subLabel.textColor = NSColor(white: 0.72, alpha: 1.0)
        subLabel.frame = NSRect(x: 24, y: 44, width: winW - 48, height: 32)
        mainView.addSubview(subLabel)
        
        let headerDiv = NSBox(frame: NSRect(x: 24, y: 82, width: winW - 48, height: 1))
        headerDiv.boxType = .custom
        headerDiv.fillColor = colorSep
        headerDiv.borderColor = .clear
        mainView.addSubview(headerDiv)
        
        // Detection checks
        let hasAnti = QuotaManager.hasAntigravity()
        let hasClaude = QuotaManager.hasClaudePro()
        let hasChatgpt = QuotaManager.hasChatGPT()
        let hasCursor = QuotaManager.hasCursor()
        let hasCopilot = QuotaManager.hasCopilot()
        let hasGemini = QuotaManager.hasGemini()
        
        let cardW = winW - 48
        let cardH: CGFloat = 58
        var cy: CGFloat = 94
        
        func buildAppCard(y: CGFloat, title: String, subtitle: String, detected: Bool, detectedText: String, defaultChecked: Bool) -> (NSView, NSButton) {
            let card = FlippedBox(frame: NSRect(x: 24, y: y, width: cardW, height: cardH))
            card.wantsLayer = true
            card.layer?.backgroundColor = colorCard.cgColor
            card.layer?.borderColor = colorBorder.cgColor
            card.layer?.borderWidth = 1
            card.layer?.cornerRadius = 8
            
            let btn = ContrastCheckbox(frame: NSRect(x: 12, y: 10, width: 220, height: 20))
            btn.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 12, weight: .bold)
                ]
            )
            btn.state = defaultChecked ? .on : .off
            card.addSubview(btn)
            
            let desc = NSTextField(labelWithString: subtitle)
            desc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            desc.textColor = NSColor(white: 0.55, alpha: 1.0)
            desc.frame = NSRect(x: 34, y: 32, width: 280, height: 15)
            card.addSubview(desc)
            
            // Badge
            let badgeW: CGFloat = 145
            let badgeH: CGFloat = 22
            let badge = FlippedBox(frame: NSRect(x: cardW - badgeW - 12, y: 18, width: badgeW, height: badgeH))
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 11
            badge.layer?.backgroundColor = (detected ? colorGreenBg : colorGrayBg).cgColor
            
            let badgeLbl = NSTextField(labelWithString: detected ? detectedText : "○ Opcional")
            badgeLbl.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
            badgeLbl.textColor = detected ? colorGreen : NSColor(white: 0.6, alpha: 1.0)
            badgeLbl.alignment = .center
            badgeLbl.frame = NSRect(x: 0, y: 3, width: badgeW, height: 16)
            badge.addSubview(badgeLbl)
            
            card.addSubview(badge)
            return (card, btn)
        }
        
        // 1. Antigravity
        let (antiCard, antiBtn) = buildAppCard(
            y: cy,
            title: "Antigravity",
            subtitle: "Google Antigravity IDE (Gemini, Claude, Argon)",
            detected: hasAnti,
            detectedText: "✓ Detectado no Mac",
            defaultChecked: true
        )
        mainView.addSubview(antiCard)
        self.obAntigravityCheck = antiBtn
        cy += cardH + 8
        
        // 2. Claude
        let (claudeCard, claudeBtn) = buildAppCard(
            y: cy,
            title: "Claude",
            subtitle: "Anthropic Claude Pro & Code (5h and Weekly)",
            detected: hasClaude,
            detectedText: "✓ Active Session / Token",
            defaultChecked: hasClaude
        )
        mainView.addSubview(claudeCard)
        self.obClaudeCheck = claudeBtn
        cy += cardH + 8
        
        // 3. ChatGPT
        let (chatgptCard, chatgptBtn) = buildAppCard(
            y: cy,
            title: "ChatGPT",
            subtitle: "OpenAI ChatGPT Plus & Pro (3h and Weekly)",
            detected: hasChatgpt,
            detectedText: "✓ Active Desktop Session",
            defaultChecked: hasChatgpt
        )
        mainView.addSubview(chatgptCard)
        self.obChatgptCheck = chatgptBtn
        cy += cardH + 8
        
        // 4. Cursor
        let (cursorCard, cursorBtn) = buildAppCard(
            y: cy,
            title: "Cursor",
            subtitle: "Cursor IDE (Claude 3.5 & GPT-4o Fast Requests)",
            detected: hasCursor,
            detectedText: "✓ Detectado no Mac",
            defaultChecked: hasCursor
        )
        mainView.addSubview(cursorCard)
        self.obCursorCheck = cursorBtn
        cy += cardH + 8
        
        // 5. Copilot
        let (copilotCard, copilotBtn) = buildAppCard(
            y: cy,
            title: "Copilot",
            subtitle: "Visual Studio Code (Copilot Chat & Completions)",
            detected: hasCopilot,
            detectedText: "✓ Detectado (VS Code)",
            defaultChecked: hasCopilot
        )
        mainView.addSubview(copilotCard)
        self.obCopilotCheck = copilotBtn
        cy += cardH + 8
        
        // 6. Gemini
        let (geminiCard, geminiBtn) = buildAppCard(
            y: cy,
            title: "Gemini",
            subtitle: "Google AI Studio API (RPM, TPM, RPD)",
            detected: hasGemini,
            detectedText: "✓ Key Configured",
            defaultChecked: hasGemini
        )
        mainView.addSubview(geminiCard)
        self.obGeminiCheck = geminiBtn
        cy += cardH + 12
        
        // Notice Info Box
        let infoBox = FlippedBox(frame: NSRect(x: 24, y: cy, width: cardW, height: 44))
        infoBox.wantsLayer = true
        infoBox.layer?.backgroundColor = NSColor(srgbRed: 0x14/255.0, green: 0x22/255.0, blue: 0x36/255.0, alpha: 0.6).cgColor
        infoBox.layer?.borderColor = NSColor(srgbRed: 0x20/255.0, green: 0x3A/255.0, blue: 0x5C/255.0, alpha: 0.8).cgColor
        infoBox.layer?.borderWidth = 1
        infoBox.layer?.cornerRadius = 6
        
        let infoLbl = NSTextField(wrappingLabelWithString: "💡 You can add, remove or hide specific gauges at any time in Settings (⌘,) from the menu bar icon.")
        infoLbl.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        infoLbl.textColor = NSColor(srgbRed: 0x90/255.0, green: 0xC0/255.0, blue: 0xF0/255.0, alpha: 1.0)
        infoLbl.frame = NSRect(x: 12, y: 6, width: cardW - 24, height: 32)
        infoBox.addSubview(infoLbl)
        mainView.addSubview(infoBox)
        cy += 44 + 14
        
        // Footer Buttons
        let allBtn = NSButton(title: "Enable All", target: self, action: #selector(onboardingEnableAllClicked))
        allBtn.isBordered = false
        allBtn.wantsLayer = true
        allBtn.layer?.backgroundColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x30/255.0, alpha: 1.0).cgColor
        allBtn.layer?.cornerRadius = 6
        allBtn.frame = NSRect(x: 24, y: cy, width: 120, height: 36)
        allBtn.attributedTitle = NSAttributedString(
            string: "Enable All",
            attributes: [
                .foregroundColor: NSColor(white: 0.9, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
        )
        mainView.addSubview(allBtn)
        
        let startBtn = NSButton(title: "Start Cockpit 🚀", target: self, action: #selector(onboardingFinishClicked))
        startBtn.isBordered = false
        startBtn.wantsLayer = true
        startBtn.layer?.backgroundColor = colorGreen.cgColor
        startBtn.layer?.cornerRadius = 6
        startBtn.frame = NSRect(x: winW - 24 - 190, y: cy, width: 190, height: 36)
        startBtn.attributedTitle = NSAttributedString(
            string: "Start Cockpit 🚀",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x10/255.0, green: 0x10/255.0, blue: 0x14/255.0, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold)
            ]
        )
        mainView.addSubview(startBtn)
    }
    
    @objc func onboardingFinishClicked() {
        saveOnboardingSelection(all: false)
    }
    
    @objc func onboardingEnableAllClicked() {
        saveOnboardingSelection(all: true)
    }
    
    func saveOnboardingSelection(all: Bool) {
        var cfg = QuotaManager.loadConfig()
        if cfg.providers == nil { cfg.providers = [:] }
        
        let antiEnabled = all ? true : (obAntigravityCheck?.state == .on)
        let claudeEnabled = all ? true : (obClaudeCheck?.state == .on)
        let chatgptEnabled = all ? true : (obChatgptCheck?.state == .on)
        let cursorEnabled = all ? true : (obCursorCheck?.state == .on)
        let copilotEnabled = all ? true : (obCopilotCheck?.state == .on)
        let geminiEnabled = all ? true : (obGeminiCheck?.state == .on)
        
        cfg.providers?["antigravity"] = ProviderConfig(enabled: antiEnabled, api_key: nil, token: nil)
        cfg.providers?["claude_pro"] = ProviderConfig(enabled: claudeEnabled, api_key: nil, token: nil)
        cfg.providers?["chatgpt_subscription"] = ProviderConfig(enabled: chatgptEnabled, api_key: nil, token: nil)
        cfg.providers?["cursor"] = ProviderConfig(enabled: cursorEnabled, api_key: nil, token: nil)
        cfg.providers?["github_copilot"] = ProviderConfig(enabled: copilotEnabled, api_key: nil, token: nil)
        if cfg.providers?["gemini"] == nil {
            cfg.providers?["gemini"] = ProviderConfig(enabled: geminiEnabled, api_key: "", token: nil)
        } else {
            cfg.providers?["gemini"]?.enabled = geminiEnabled
        }
        cfg.onboarding_completed = true
        
        QuotaManager.saveConfig(cfg)
        UserDefaults.standard.set(true, forKey: "aigauge_onboarding_completed")
        
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil
        
        switchToHudMode()
        performRefresh(animated: true)
        startAutoRefreshTimer()
    }
    
    @objc func closeClicked() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        NSApp.terminate(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow {
            if win == fullWindow {
                closeClicked()
            } else if win == onboardingWindow {
                saveOnboardingSelection(all: false)
            }
        }
    }
}

// MARK: - Promo Dock (Publicidade para Versões Gratuitas)
class PromoDockManager: NSObject, WKScriptMessageHandler {
    static let shared = PromoDockManager()
    private var promoWindow: NSWindow?
    private var lastShownAt: TimeInterval = 0
    private let intervalSeconds: TimeInterval = 6 * 3600 // 6 horas
    private let initialDelay: TimeInterval = 60          // espera 1 minuto após abrir o app
    private let launchTime = Date().timeIntervalSince1970
    private var scheduled = false

    private var lastShownFile: String {
        return NSHomeDirectory() + "/.config/UniversalAIQuota/promo_last_shown"
    }

    private func persistedLastShown() -> TimeInterval {
        guard let raw = try? String(contentsOfFile: lastShownFile, encoding: .utf8) else { return 0 }
        return TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func persistLastShown(_ ts: TimeInterval) {
        try? String(Int(ts)).write(toFile: lastShownFile, atomically: true, encoding: .utf8)
    }

    func presentIfNeeded(_ ann: AnnouncementInfo) {
        let now = Date().timeIntervalSince1970
        let last = max(lastShownAt, persistedLastShown())
        if last > 0 && (now - last) < intervalSeconds {
            return
        }
        if scheduled || promoWindow != nil { return }
        scheduled = true
        let wait = max(0, initialDelay - (now - launchTime))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self = self else { return }
            self.scheduled = false
            let shownAt = Date().timeIntervalSince1970
            self.lastShownAt = shownAt
            self.persistLastShown(shownAt)
            self.showWindow(ann)
        }
    }

    private func escapeHTML(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func showWindow(_ ann: AnnouncementInfo) {
        promoWindow?.close()
        var rawImg = ann.image_url ?? ""
        if rawImg.hasPrefix("http://") {
            rawImg = rawImg.replacingOccurrences(of: "http://", with: "https://")
        }
        let hasImage = !rawImg.isEmpty
        let width: CGFloat = 380
        let height: CGFloat = hasImage ? 440 : 250
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let x = screenFrame.midX - (width / 2)
        let y = screenFrame.midY - (height / 2)

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = true
        win.isReleasedWhenClosed = false

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "promoAction")
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 24
        webView.layer?.masksToBounds = true

        let title = escapeHTML(ann.title ?? "AI Gauge Pro")
        let text = escapeHTML(ann.message ?? "")
        let fit = escapeHTML(ann.image_fit ?? "cover")
        let pos = escapeHTML(ann.image_position ?? "center")
        let sc = ann.image_scale ?? 1.0
        let imgHtml = hasImage
            ? "<div class=\"promo-media\" id=\"mediaBox\"><img src=\"\(escapeHTML(rawImg))\" alt=\"\" style=\"object-fit:\(fit); object-position:\(pos); transform:scale(\(sc)); transform-origin:\(pos);\" onerror=\"document.getElementById('mediaBox').style.display='none';\" /></div>"
            : ""
        let actionLabel = escapeHTML((ann.action_label != nil && !ann.action_label!.isEmpty) ? ann.action_label! : "Ver Detalhes")
        let actionUrl = escapeHTML(ann.action_url ?? "")
        let tempo = ann.duracao_segundos ?? 0

        var appIconTag = ""
        if let iconUrl = Bundle.main.url(forResource: "icon", withExtension: "png"),
           let iconData = try? Data(contentsOf: iconUrl) {
            let b64 = iconData.base64EncodedString()
            appIconTag = "<img src=\"data:image/png;base64,\(b64)\" width=\"16\" height=\"16\" style=\"display:block; object-fit:contain;\" />"
        } else if let iconImg = NSApp.applicationIconImage,
           let tiff = iconImg.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let b64 = png.base64EncodedString()
            appIconTag = "<img src=\"data:image/png;base64,\(b64)\" width=\"16\" height=\"16\" style=\"display:block; object-fit:contain;\" />"
        }

        let hasAction = !actionUrl.isEmpty
        let primaryBtnHtml = hasAction
            ? "<a href=\"#\" class=\"btn-primary\" onclick=\"openAction('\(actionUrl)');return false;\">\(actionLabel)</a>"
            : ""

        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        :root {
          --card-bg: #16171F;
          --card-border: rgba(255, 255, 255, 0.1);
          --text-primary: #FFFFFF;
          --text-secondary: #94A3B8;
          --btn-secondary: rgba(255, 255, 255, 0.08);
          --btn-secondary-hover: rgba(255, 255, 255, 0.14);
          --primary-gradient: linear-gradient(135deg, #6366F1 0%, #4F46E5 100%);
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        html, body { width: 100%; height: 100%; background: transparent; overflow: hidden; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; -webkit-user-select: none; }
        .card-container {
          position: relative;
          display: flex;
          flex-direction: column;
          width: 100%;
          height: 100%;
          background: var(--card-bg);
          border: 1px solid var(--card-border);
          border-radius: 24px;
          padding: 14px 18px 18px;
          box-shadow: 0 20px 45px rgba(0,0,0,0.6);
        }
        .card-header-brand {
          display: flex;
          align-items: center;
          gap: 8px;
          height: 20px;
          margin-bottom: 12px;
          font-size: 11.5px;
          font-weight: 700;
          letter-spacing: 0.05em;
          text-transform: uppercase;
          color: var(--text-secondary);
        }
        .card-header-brand img {
          width: 16px;
          height: 16px;
          object-fit: contain;
        }
        .promo-media {
          width: 100%;
          height: 185px;
          border-radius: 16px;
          overflow: hidden;
          background: #0E1015;
          margin-bottom: 14px;
          flex-shrink: 0;
        }
        .promo-media img {
          width: 100%;
          height: 100%;
          display: block;
        }
        .promo-content {
          flex: 1;
          display: flex;
          flex-direction: column;
          min-height: 0;
        }
        .promo-title {
          font-size: 19px;
          font-weight: 700;
          color: var(--text-primary);
          line-height: 1.25;
          margin-bottom: 6px;
          letter-spacing: -0.01em;
        }
        .promo-desc {
          font-size: 13.5px;
          line-height: 1.45;
          color: var(--text-secondary);
          margin-bottom: 16px;
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .promo-actions {
          margin-top: auto;
          display: flex;
          align-items: center;
          gap: 10px;
          width: 100%;
        }
        .btn-secondary {
          flex: 1;
          height: 44px;
          border-radius: 13px;
          background: var(--btn-secondary);
          border: 1px solid rgba(255, 255, 255, 0.08);
          color: #E2E8F0;
          font-size: 14px;
          font-weight: 600;
          cursor: pointer;
          transition: background 0.15s;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          text-align: center;
        }
        .btn-secondary:hover { background: var(--btn-secondary-hover); }
        .btn-secondary:disabled { opacity: 0.4; cursor: not-allowed; }
        .btn-primary {
          flex: 1;
          height: 44px;
          border-radius: 13px;
          background: var(--primary-gradient);
          border: none;
          color: #FFFFFF;
          font-size: 14px;
          font-weight: 600;
          text-decoration: none;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          box-shadow: 0 4px 14px rgba(99, 102, 241, 0.35);
          transition: filter 0.15s, transform 0.1s;
          text-align: center;
        }
        .btn-primary:hover { filter: brightness(1.08); }
        .btn-primary:active { transform: scale(0.98); }
        </style></head><body>
        <div class="card-container">
          <div class="card-header-brand">
            \(appIconTag)
            <span>AI GAUGE - Advertising</span>
          </div>
          \(imgHtml)
          <div class="promo-content">
            <h3 class="promo-title">\(title)</h3>
            <p class="promo-desc">\(text)</p>
            <div class="promo-actions">
              <button id="btnLater" class="btn-secondary" onclick="closePromo()">Not now</button>
              \(primaryBtnHtml)
            </div>
          </div>
        </div>
        <script>
          let rem = \(tempo);
          const btnLater = document.getElementById('btnLater');
          function closePromo() {
            if (rem > 0) return;
            window.webkit.messageHandlers.promoAction.postMessage({type:'close'});
          }
          function openAction(url) {
            if (url) {
              window.webkit.messageHandlers.promoAction.postMessage({type:'open', url: url});
            } else {
              closePromo();
            }
          }
          if (rem > 0) {
            btnLater.disabled = true;
            btnLater.innerText = 'Not now (' + rem + 's)';
            const t = setInterval(() => {
              rem--;
              if (rem <= 0) {
                clearInterval(t);
                btnLater.disabled = false;
                btnLater.innerText = 'Not now';
              } else {
                btnLater.innerText = 'Not now (' + rem + 's)';
              }
            }, 1000);
          }
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        win.contentView = webView
        win.makeKeyAndOrderFront(nil)
        self.promoWindow = win
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        DispatchQueue.main.async {
            if type == "close" {
                self.promoWindow?.orderOut(nil)
                self.promoWindow = nil
            } else if type == "open", let urlStr = body["url"] as? String, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
                self.promoWindow?.orderOut(nil)
                self.promoWindow = nil
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
