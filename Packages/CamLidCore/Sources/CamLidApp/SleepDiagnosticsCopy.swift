import Foundation
import CamLidCore

/// One plain-language reason shown to people who do not know what a power
/// assertion is. Several raw assertions can collapse into one cause.
struct FriendlySleepCause: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    var activeNow: Bool
    let priority: Int
    let details: [FriendlySleepDetail]
}

struct FriendlySleepDetail: Identifiable, Equatable, Sendable {
    let id: String
    let owner: String
    let pid: Int?
    let type: String
    let source: String
}

/// Turns technical sleep requests into short, everyday sentences such as
/// “FaceTime is on a call”. Raw process names stay in the disclosure details.
enum SleepDiagnosticsCopy {
    private struct Descriptor: Sendable {
        let key: String
        let title: String
        let symbol: String
        var subtitle: String? = nil
    }

    private struct Rule: Sendable {
        let names: Set<String>
        let key: String
        let title: String
        let symbol: String
    }

    private static let rules: [Rule] = [
        Rule(names: ["facetime"], key: "facetime", title: tr("FaceTime is on a call"), symbol: "phone.fill"),
        Rule(names: ["avconferenced", "vtdecoderxpcservice"], key: "call",
             title: tr("A call is in progress"), symbol: "phone.fill"),
        Rule(names: ["cameracaptured", "vdcassistant"], key: "camera",
             title: tr("The camera is in use"), symbol: "video.fill"),
        Rule(names: ["coreaudiod", "audioaccessoryd"], key: "audio",
             title: tr("Audio is playing"), symbol: "speaker.wave.2.fill"),
        Rule(names: ["mds", "mds_stores", "mdworker", "mdworker_shared", "spotlightknowledged", "corespotlightd"],
             key: "spotlight", title: tr("Spotlight is organizing files"), symbol: "magnifyingglass"),
        Rule(names: ["dasd"], key: "background",
             title: tr("macOS is doing background work"), symbol: "gearshape.2"),
        Rule(names: ["nsurlsessiond", "cloudd", "bird", "fileproviderd"], key: "network",
             title: tr("Your Mac is downloading data in the background"), symbol: "arrow.down.circle"),
        Rule(names: ["apsd"], key: "push", title: tr("Push notifications are active"), symbol: "bell"),
        Rule(names: ["sharingd", "rapportd"], key: "handoff",
             title: tr("Handoff or AirDrop is active"), symbol: "square.and.arrow.up"),
        Rule(names: ["bluetoothd"], key: "bluetooth",
             title: tr("Bluetooth is active"), symbol: "antenna.radiowaves.left.and.right"),
        Rule(names: ["powerd"], key: "screen", title: tr("The screen is on"), symbol: "display"),
        Rule(names: ["windowserver", "loginwindow"], key: "input",
             title: tr("You recently used your Mac"), symbol: "keyboard"),
        Rule(names: ["kernel_task"], key: "kernel",
             title: tr("A connected device is asking your Mac to stay awake"), symbol: "cable.connector"),
        Rule(names: ["backupd", "timemachine", "tmutil"], key: "backup",
             title: tr("Time Machine is backing up"), symbol: "externaldrive"),
        Rule(names: ["softwareupdated", "softwareupdate", "osinstaller", "installd"], key: "update",
             title: tr("macOS is installing an update"), symbol: "arrow.triangle.2.circlepath"),
        Rule(names: ["photoanalysisd", "photolibraryd", "photos"], key: "photos",
             title: tr("Photos is analyzing your library"), symbol: "photo"),
        Rule(names: ["caffeinate"], key: "awake",
             title: tr("An app asked your Mac to stay awake"), symbol: "cup.and.saucer"),
        Rule(names: ["orca"], key: "orca", title: tr("Orca is running a task"), symbol: "terminal"),
        Rule(names: ["lidrun"], key: "lidrun", title: tr("LidRun is active"), symbol: "laptopcomputer"),
        Rule(names: ["brave", "brave browser", "brave browser helper"], key: "brave",
             title: tr("Brave Browser is active"), symbol: "globe"),
        Rule(names: ["camlid", "com.camlid.power-helper"], key: "camlid",
             title: tr("CamLid is active"), symbol: "moon.fill"),
        Rule(names: ["zoom.us", "zoom"], key: "zoom", title: tr("Zoom is on a call"), symbol: "video.fill"),
        Rule(names: ["microsoft teams", "msteams"], key: "teams",
             title: tr("Microsoft Teams is on a call"), symbol: "video.fill"),
        Rule(names: ["webex", "webexmeetings"], key: "webex",
             title: tr("Webex is on a call"), symbol: "video.fill"),
        Rule(names: ["docker", "com.docker.backend", "docker desktop"], key: "docker",
             title: tr("Docker is running tasks"), symbol: "shippingbox"),
    ]

    static func causes(for snapshot: DiagnosticSnapshot) -> [FriendlySleepCause] {
        var groups: [String: (descriptor: Descriptor, effect: SleepEffect, blockers: [DiagnosticBlocker])] = [:]
        for blocker in snapshot.blockers {
            let descriptor = descriptor(for: blocker)
            var group = groups[descriptor.key] ?? (descriptor, blocker.effect, [])
            group.effect = strongest(group.effect, blocker.effect)
            group.blockers.append(blocker)
            groups[descriptor.key] = group
        }
        let prevented = Set(snapshot.preventedBy.map { $0.lowercased() })
        let preventingKnown = snapshot.coverage["preventing"] == .complete
        var causes = groups.values.map { group -> FriendlySleepCause in
            let active = preventingKnown && group.blockers.contains { blocker in
                guard let owner = blocker.owner?.lowercased() else { return false }
                return prevented.contains(owner)
            }
            return FriendlySleepCause(
                id: group.descriptor.key,
                title: group.descriptor.title,
                subtitle: group.descriptor.subtitle ?? subtitle(for: group.effect),
                symbol: group.descriptor.symbol,
                activeNow: active,
                priority: priority(of: group.effect),
                details: group.blockers.map { blocker in
                    FriendlySleepDetail(id: blocker.id, owner: blocker.owner ?? tr("Unknown process"),
                        pid: blocker.pid, type: blocker.type, source: blocker.source)
                }.sorted {
                    if $0.owner != $1.owner { return $0.owner.localizedStandardCompare($1.owner) == .orderedAscending }
                    return $0.id < $1.id
                })
        }
        if preventingKnown {
            // pmset can name a process that IOKit does not expose as an
            // assertion. Keep that plain-language cause instead of hiding it.
            let matchedOwners = Set(snapshot.blockers.compactMap { $0.owner?.lowercased() })
            for name in snapshot.preventedBy where !matchedOwners.contains(name.lowercased()) {
                let descriptor = descriptor(forOwner: name, effect: .unknown)
                if let index = causes.firstIndex(where: { $0.id == descriptor.key }) {
                    causes[index].activeNow = true
                } else {
                    causes.append(FriendlySleepCause(
                        id: descriptor.key,
                        title: descriptor.title,
                        subtitle: tr("macOS says this is preventing sleep right now"),
                        symbol: descriptor.symbol,
                        activeNow: true,
                        priority: 0,
                        details: [FriendlySleepDetail(id: "pmset-\(name.lowercased())", owner: name,
                            pid: nil, type: tr("Sleep prevented by"), source: "pmset")]))
                }
            }
        }
        return causes.sorted { lhs, rhs in
            if lhs.activeNow != rhs.activeNow { return lhs.activeNow }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// The sentence at the top of the report. When app coverage is incomplete
    /// and nothing was found, say so instead of claiming the Mac is idle.
    static func summary(_ causes: [FriendlySleepCause], appsCoverage: DiagnosticCoverage?) -> String {
        if causes.isEmpty {
            switch appsCoverage ?? .unavailable {
            case .complete:
                return tr("Nothing is keeping your Mac awake right now.")
            case .partial:
                return tr("We couldn't check everything keeping your Mac awake.")
            case .unavailable:
                return tr("We couldn't check what's keeping your Mac awake.")
            }
        }
        return headline(causes)
    }

    static func headline(_ causes: [FriendlySleepCause]) -> String {
        guard let first = causes.first else { return tr("Nothing is keeping your Mac awake right now.") }
        if causes.count == 1 { return trf("%@. That's keeping your Mac awake.", first.title) }
        if causes.count == 2 { return trf("%@. One other thing is also keeping your Mac awake.", first.title) }
        let others = causes.count - 1
        return trf("%@. %@ other things are also keeping your Mac awake.", first.title, word(others))
    }

    /// Spells out small counts so the headline reads like a sentence.
    private static func word(_ value: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five",
                     "Six", "Seven", "Eight", "Nine", "Ten"]
        return words.indices.contains(value) ? tr(words[value]) : String(value)
    }

    private static func descriptor(for blocker: DiagnosticBlocker) -> Descriptor {
        descriptor(forOwner: blocker.owner, effect: blocker.effect)
    }

    private static func descriptor(forOwner ownerName: String?, effect: SleepEffect) -> Descriptor {
        switch effect {
        case .global:
            return Descriptor(key: "global", title: tr("Sleep is turned off in macOS settings"),
                              symbol: "gearshape", subtitle: tr("This applies to the whole Mac"))
        case .kernel:
            return Descriptor(key: "kernel", title: tr("A connected device is asking your Mac to stay awake"),
                              symbol: "cable.connector", subtitle: tr("This applies to connected hardware"))
        default:
            break
        }
        let owner = (ownerName ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if let rule = rules.first(where: { $0.names.contains(owner) }) {
            return Descriptor(key: rule.key, title: rule.title, symbol: rule.symbol)
        }
        if owner.contains("spotlight") {
            return Descriptor(key: "spotlight", title: tr("Spotlight is organizing files"), symbol: "magnifyingglass")
        }
        if owner.contains("backup") || owner.contains("time machine") {
            return Descriptor(key: "backup", title: tr("Time Machine is backing up"), symbol: "externaldrive")
        }
        if let name = appDisplayName(ownerName) {
            return Descriptor(key: "app-" + name.lowercased(), title: trf("%@ is active", name), symbol: "macwindow")
        }
        switch effect {
        case .displayIdle:
            return Descriptor(key: "display", title: tr("Something is keeping your screen on"), symbol: "display")
        case .systemIdle:
            return Descriptor(key: "system", title: tr("Something is keeping your Mac awake"),
                              symbol: "moon.zzz", subtitle: tr("A background process is holding a sleep request"))
        case .userActivity:
            return Descriptor(key: "input", title: tr("You recently used your Mac"), symbol: "keyboard")
        case .unknown, .global, .kernel:
            return Descriptor(key: "unknown", title: tr("Something is using your Mac"), symbol: "questionmark.circle")
        }
    }

    private static func appDisplayName(_ owner: String?) -> String? {
        guard let name = owner?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              !name.contains("."), !name.contains("/"), !name.contains("_"),
              name.rangeOfCharacter(from: .uppercaseLetters) != nil else { return nil }
        return name
    }

    private static func strongest(_ lhs: SleepEffect, _ rhs: SleepEffect) -> SleepEffect {
        priority(of: lhs) >= priority(of: rhs) ? lhs : rhs
    }

    private static func priority(of effect: SleepEffect) -> Int {
        switch effect {
        case .global: 4
        case .displayIdle: 3
        case .systemIdle: 2
        case .kernel: 2
        case .userActivity: 1
        case .unknown: 0
        }
    }

    private static func subtitle(for effect: SleepEffect) -> String {
        switch effect {
        case .displayIdle: tr("Keeps your Mac and screen awake")
        case .systemIdle: tr("Keeps your Mac awake")
        case .userActivity: tr("Recent activity. Sleep resumes after a short pause")
        case .global: tr("Sleep is turned off for the whole Mac")
        case .kernel: tr("A connected device is asking macOS to stay awake")
        case .unknown: tr("macOS reports activity")
        }
    }
}
