import SwiftUI

/// Settings: Glint's own tab bar, so the selected tab follows your accent
/// like every control below it (the system's tab bar only knows the app's
/// built-in accent). Each tab is only as tall as its settings.
struct SettingsView: View {
  enum Tab: String, CaseIterable, Identifiable {
    case general, appearance, ai, shortcuts
    var id: String { rawValue }
    var title: String {
      switch self {
      case .general: "General"
      case .appearance: "Appearance"
      case .ai: "AI"
      case .shortcuts: "Shortcuts"
      }
    }
    var icon: String {
      switch self {
      case .general: "gearshape"
      case .appearance: "paintbrush"
      case .ai: "sparkles"
      case .shortcuts: "keyboard"
      }
    }
  }

  @AppStorage("settingsTab") private var tab = Tab.general

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 4) {
        ForEach(Tab.allCases) { each in
          Button {
            tab = each
          } label: {
            VStack(spacing: 2) {
              Image(systemName: each.icon).font(.app(.title3)).frame(height: 22)
              Text(each.title).font(.app(.caption))
            }
            .frame(width: 76, height: 48)
            .foregroundStyle(tab == each ? Color.themeAccent : .secondary)
            .background(
              RoundedRectangle(cornerRadius: 6).fill(tab == each ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(tab == each ? .isSelected : [])
        }
      }
      .padding(.vertical, 8)
      Hairline()
      Group {
        switch tab {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .ai: AISettingsView()
        case .shortcuts: ShortcutsSettingsView()
        }
      }
    }
    // The whole window, not just the tab: Settings windows keep one width.
    .frame(width: 520)
    .navigationTitle(tab.title)
  }
}
