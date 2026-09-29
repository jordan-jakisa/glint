import SwiftUI

/// Settings, laid out like Zed's settings window (crates/settings_ui): a
/// sidebar with search and the pages, and each page a column of settings.
/// Every row is the setting's name with a one-line description under it,
/// its control on the right, and, once you change it, a reset button beside
/// the name.
struct SettingsView: View {
  enum Page: String, CaseIterable, Identifiable {
    case general, appearance, ai, keymap
    var id: String { rawValue }
    var title: String {
      switch self {
      case .general: "General"
      case .appearance: "Appearance"
      case .ai: "AI"
      case .keymap: "Keymap"
      }
    }
    var icon: String {
      switch self {
      case .general: "gearshape"
      case .appearance: "paintbrush"
      case .ai: "sparkles"
      case .keymap: "keyboard"
      }
    }
  }

  @AppStorage("settingsPage") private var page = Page.general
  @State private var search = ""

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Hairline(axis: .vertical)
      Group {
        switch page {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .ai: AISettingsView()
        case .keymap: ShortcutsSettingsView()
        }
      }
      .environment(\.settingsSearch, search)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Color(nsColor: Theme.shared.editorBackground))
    }
    .frame(width: 780, height: 560)
    .navigationTitle("Settings")
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search settings", text: $search)
          .textFieldStyle(.plain)
      }
      .padding(.horizontal, 8)
      .frame(height: 28)
      .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
      .padding(.bottom, 8)
      ForEach(Page.allCases) { each in
        Button {
          page = each
        } label: {
          Label(each.title, systemImage: each.icon)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .foregroundStyle(page == each ? .primary : .secondary)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(page == each ? Color(nsColor: Theme.shared.isZed ? ZedPalette.elementSelected : .selectedContentBackgroundColor).opacity(Theme.shared.isZed ? 1 : 0.25) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(page == each ? .isSelected : [])
      }
      Spacer()
    }
    .font(.app(.body))
    .padding(12)
    .frame(width: 200)
    .background(Theme.shared.panelBackground.map { Color(nsColor: $0) } ?? Color(nsColor: .windowBackgroundColor))
  }
}

// MARK: - Building blocks

extension EnvironmentValues {
  /// What's typed in Settings' search; rows that don't match hide.
  @Entry var settingsSearch = ""
}

/// One page: its title, then its sections.
struct SettingsPage<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.app(.title2))
          .padding(.horizontal, 32)
          .padding(.top, 24)
          .padding(.bottom, 8)
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 24)
    }
  }
}

/// A group's name, small and dimmed.
struct SettingsSection: View {
  let title: String
  @Environment(\.settingsSearch) private var search

  var body: some View {
    if search.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.app(.caption))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 32)
      .padding(.top, 20)
    }
  }
}

/// A setting: name, reset button once changed, one-line description, and
/// the control on the right.
struct SettingsRow<Control: View>: View {
  let title: String
  let description: String
  var isModified = false
  var reset: (() -> Void)? = nil
  @ViewBuilder let control: Control
  @Environment(\.settingsSearch) private var search

  var body: some View {
    if matches {
      VStack(spacing: 0) {
        HStack(alignment: .center, spacing: 16) {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
              Text(title)
              if isModified, let reset {
                Button(action: reset) {
                  Image(systemName: "arrow.uturn.backward")
                    .font(.app(.caption))
                    .hitTarget()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reset \(title) to default")
                .help("Reset to Default")
              }
            }
            if !description.isEmpty {
              Text(description)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(description)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          // The control keeps its size; the description gives way, as in Zed.
          control.layoutPriority(1)
        }
        .padding(.vertical, 10)
      }
      .padding(.horizontal, 32)
    }
  }

  private var matches: Bool {
    let query = search.trimmingCharacters(in: .whitespaces)
    return query.isEmpty || title.localizedCaseInsensitiveContains(query)
      || description.localizedCaseInsensitiveContains(query)
  }
}
