import SwiftUI

/// The first launch: what Glint is, an AI provider and its key, then your
/// first project. Shown once; after that the plain welcome screen takes over.
struct OnboardingView: View {
  let open: () -> Void
  @State private var step = Step.welcome

  enum Step { case welcome, ai, project }

  static let doneKey = "onboardingDone"
  static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch step {
        case .welcome: WelcomeStep { step = .ai }
        case .ai:
          AIStep {
            UserDefaults.standard.set(true, forKey: Self.doneKey)
            step = .project
          }
        case .project: ProjectStep(open: open)
        }
      }
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      StepDots(step: step)
        .padding(.bottom, 24)
    }
    .padding(40)
  }
}

private struct StepDots: View {
  let step: OnboardingView.Step

  var body: some View {
    HStack(spacing: 8) {
      ForEach([OnboardingView.Step.welcome, .ai, .project], id: \.self) { each in
        Circle()
          .fill(each == step ? Color.accentColor : Color.secondary.opacity(0.3))
          .frame(width: 6, height: 6)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(label)
  }

  private var label: String {
    switch step {
    case .welcome: "Step 1 of 3"
    case .ai: "Step 2 of 3"
    case .project: "Step 3 of 3"
    }
  }
}

private struct WelcomeStep: View {
  let next: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 128, height: 128)
        .accessibilityHidden(true)
      VStack(spacing: 8) {
        Text("Glint")
          .font(.largeTitle.weight(.semibold))
        Text("Every change, at a glance.")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 12) {
        Point(symbol: "eye", text: "Read the diff the moment you change a file.")
        Point(symbol: "checklist", text: "Stage exactly what you mean: files, hunks, or single lines.")
        Point(symbol: "sparkles", text: "Commit with a message that says why, written with you by a free AI model.")
      }
      Button("Get Started", action: next)
        .keyboardShortcut(.defaultAction)
        .controlSize(.large)
    }
  }
}

private struct Point: View {
  let symbol: String
  let text: String

  var body: some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: symbol)
        .foregroundStyle(Color.accentColor)
        .frame(width: 22)
    }
  }
}

/// Pick a provider, paste its key, and Glint checks it works before you go
/// on. Keys go to the Keychain.
private struct AIStep: View {
  let next: () -> Void
  @Bindable private var settings = AISettings.shared
  @State private var key = ""
  @State private var state = CheckState.idle

  enum CheckState: Equatable {
    case idle, checking, accepted, rejected, unsure(String), failedToSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Commit messages, written for you")
          .font(.title2.weight(.semibold))
        Text("Glint writes commit messages with free models. Pick a provider and paste your API key. It's free to get one.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 8) {
        ForEach(AIProvider.allCases) { provider in
          ProviderRow(provider: provider, isSelected: settings.provider == provider) {
            settings.provider = provider
            key = ""
            state = .idle
          }
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          SecureField("\(settings.provider.name) API key", text: $key)
            .textFieldStyle(.roundedBorder)
            .onSubmit(check)
            .onChange(of: key) { if state != .checking { state = .idle } }
          Link("Get a Free Key", destination: settings.provider.keyURL)
            .font(.callout)
        }
        status
          .font(.callout)
          .frame(minHeight: 18, alignment: .leading)
        Text("Your key is kept in your Mac's Keychain. Your diff goes to \(settings.provider.name) only when you press the sparkle button.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Spacer()
        if state == .accepted || isUnsure {
          Button("Continue", action: finish)
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        } else {
          Button("Check Key", action: check)
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || state == .checking)
        }
      }
    }
    .onAppear { if settings.models.isEmpty { settings.loadModels() } }
  }

  private var isUnsure: Bool {
    if case .unsure = state { return true }
    return false
  }

  @ViewBuilder private var status: some View {
    switch state {
    case .idle: Text(" ")
    case .checking:
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text("Checking your key with \(settings.provider.name)…").foregroundStyle(.secondary)
      }
    case .accepted:
      Label("Your key works.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    case .rejected:
      Label("\(settings.provider.name) didn't accept that key. Check you copied all of it.", systemImage: "xmark.circle.fill")
        .foregroundStyle(.red)
    case .unsure(let message):
      Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
    case .failedToSave:
      Label("Couldn't save your key to the Keychain. Unlock your login keychain, then try again.", systemImage: "xmark.circle.fill")
        .foregroundStyle(.red)
    }
  }

  private func check() {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, state != .checking else { return }
    guard settings.saveKey(trimmed) else {
      state = .failedToSave
      return
    }
    state = .checking
    let provider = settings.provider
    Task {
      var model = settings.modelID
      if model == nil { model = (try? await AIClient.freeModels(for: provider))?.first?.id }
      guard let model else {
        state = .unsure("Couldn't load \(provider.name)'s free models to check the key. It's saved; you can carry on.")
        return
      }
      let result = await AIClient(provider: provider, apiKey: trimmed).check(model: model)
      guard provider == settings.provider else { return }
      switch result {
      case .accepted: state = .accepted
      case .rejected: state = .rejected
      case .unsure(let message): state = .unsure(message)
      }
    }
  }

  private func finish() {
    settings.isEnabled = true
    next()
  }
}

private struct ProviderRow: View {
  let provider: AIProvider
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 12) {
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(provider.name).font(.body.weight(.medium))
          Text(provider.privacyNote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }
      .padding(12)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct ProjectStep: View {
  let open: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "folder.badge.plus")
        .font(.system(size: 48))
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)
      VStack(spacing: 8) {
        Text("Open your first project")
          .font(.title2.weight(.semibold))
        Text("Pick a folder with a git repository, or a folder that holds several. Glint remembers it and reopens it next time.")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button(AppCommand.openRepository.title, action: open)
        .keyboardShortcut(.defaultAction)
        .controlSize(.large)
      Text("Tip: \(AppCommand.switchProject.keys) switches between recent projects.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }
}
