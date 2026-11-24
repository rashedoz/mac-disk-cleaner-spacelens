import SwiftUI

private struct Tip: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
    var command: String?
    var settingsURL: String?
    var settingsLabel: String?
}

private let tips: [Tip] = [
    Tip(icon: "internaldrive", title: "Let macOS manage storage",
        body: "Storage settings can empty the Trash automatically after 30 days, move rarely used files to iCloud and remove films you have already watched. It also lists your largest files per category.",
        settingsURL: "x-apple.systempreferences:com.apple.settings.Storage", settingsLabel: "Open Storage Settings"),
    Tip(icon: "clock.arrow.circlepath", title: "Thin Time Machine local snapshots",
        body: "Time Machine keeps hourly snapshots on the internal disk. They count as “purgeable” and can hold tens of gigabytes. The first command lists them; the second asks macOS to release up to 20 GB.",
        command: "tmutil listlocalsnapshots /\ntmutil thinlocalsnapshots / 20000000000 4"),
    Tip(icon: "shippingbox", title: "Prune Docker",
        body: "Docker’s disk image only grows. This removes stopped containers, unused images, networks and build cache. Add --volumes only if you no longer need the data in unused volumes.",
        command: "docker system prune -a"),
    Tip(icon: "iphone", title: "Delete simulators you no longer use",
        body: "Every Xcode update leaves old simulator devices behind. The first command removes the ones whose runtime is gone; the second erases the content of the rest without deleting them.",
        command: "xcrun simctl delete unavailable\nxcrun simctl erase all"),
    Tip(icon: "mug", title: "Clean up Homebrew",
        body: "Homebrew keeps old versions of every formula plus the downloaded archives. This removes both.",
        command: "brew cleanup -s --prune=all"),
    Tip(icon: "folder.badge.gearshape", title: "Find forgotten node_modules",
        body: "Old JavaScript projects each keep hundreds of megabytes of dependencies. npkill lists every node_modules folder with its size and lets you delete the ones from projects you are not working on.",
        command: "npx npkill"),
    Tip(icon: "arrow.down.circle", title: "Start with Downloads",
        body: "Installers (.dmg, .pkg), zip archives and videos pile up in Downloads. Scan your home folder here, open Downloads in the chart and trash the big slices first."),
    Tip(icon: "message", title: "Trim Messages attachments",
        body: "Photos and videos sent in Messages are stored locally. In Messages settings, set “Keep messages” to one year, or open Storage settings and review Messages to delete large attachments.",
        settingsURL: "x-apple.systempreferences:com.apple.settings.Storage", settingsLabel: "Open Storage Settings"),
    Tip(icon: "externaldrive.badge.icloud", title: "Remove old iPhone backups",
        body: "Local device backups can be tens of gigabytes each. Connect the device, select it in Finder, choose Manage Backups and delete the ones you no longer need."),
    Tip(icon: "arrow.triangle.2.circlepath", title: "Restart now and then",
        body: "A restart clears swap files, the sleep image and temporary files held open by long-running apps. If free space drops for no clear reason, restart before hunting for files."),
    Tip(icon: "questionmark.circle", title: "What “purgeable” space means",
        body: "Finder may show more free space than this app’s scan suggests. The difference is purgeable space: snapshots, caches and iCloud copies that macOS removes by itself when an app needs the room."),
    Tip(icon: "app.badge.checkmark", title: "Uninstall apps completely",
        body: "Dragging an app to the Trash leaves its data behind. Scan your home folder and look in Library › Application Support and Library › Containers for folders named after apps you removed."),
]

struct TipsView: View {
    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 14, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tips").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Things that free the most space, including a few this app leaves to you")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(tips) { TipCard(tip: $0) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .padding(.top, 28)
    }
}

private struct TipCard: View {
    let tip: Tip
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: tip.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentA.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(tip.title).font(.system(size: 14, weight: .semibold))
            }
            Text(tip.body)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            if let command = tip.command {
                HStack(alignment: .top, spacing: 8) {
                    Text(command)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.good)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(copied ? Theme.good : Theme.textDim)
                    }
                    .buttonStyle(.plain)
                    .help("Copy command")
                }
                .padding(10)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let url = tip.settingsURL, let label = tip.settingsLabel {
                Button(label) {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }
}
