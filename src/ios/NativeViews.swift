// Copyright (c) 2026 CorsixTH iOS port contributors. MIT licence (see
// src/native_bridge.h for the full text).
//
// The SwiftUI screens: in-game menu, save/load, settings and the main menu.
// They show what Lua sent (NativeModel.state) and send actions back with
// NativeUI.post; Lua answers with an update when something changed.

import SwiftUI

struct NativeRootView: View {
  @EnvironmentObject var model: NativeModel

  var body: some View {
    Group {
      switch model.screen {
      case "main_menu":
        MainMenuCard()
      case "save":
        NavigationStack { SaveLoadView(mode: .save).toolbar { DoneButton() } }
      case "load":
        NavigationStack { SaveLoadView(mode: .load).toolbar { DoneButton() } }
      case "settings":
        NavigationStack { SettingsView().toolbar { DoneButton() } }
      case "room_catalog":
        if model.inPanel {
          // No navigation container in the panel: it would pad for the
          // screen's safe area, which the panel doesn't touch.
          VStack(spacing: 0) {
            HStack {
              Text("Build Room").font(.headline)
              Spacer()
              Button("Done") { NativeUI.shared.dismiss(notifyLua: true) }.bold()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RoomCatalogView()
          }
          .background(Color(uiColor: .systemBackground))
          .ignoresSafeArea(.container, edges: .horizontal)
        } else {
          NavigationStack { RoomCatalogView().toolbar { DoneButton() } }
        }
      default:
        GameMenuView()
      }
    }
    .id(model.navigationID)
    .alert(
      "Theme Hospital",
      isPresented: Binding(
        get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } }),
      actions: { Button("OK") { model.alertMessage = nil } },
      message: { Text(model.alertMessage ?? "") })
  }
}

struct DoneButton: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItem(placement: .confirmationAction) {
      Button("Done") { NativeUI.shared.dismiss(notifyLua: true) }
    }
  }
}

// MARK: - In-game menu

struct GameMenuView: View {
  @EnvironmentObject var model: NativeModel
  @State private var confirmRestart = false
  @State private var confirmQuit = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          Button {
            NativeUI.shared.dismiss(notifyLua: true)
          } label: {
            Label("Resume", systemImage: "play.fill")
          }
          if let speeds = model.state.speeds, !speeds.isEmpty {
            Picker(
              selection: Binding(
                get: { model.state.speed ?? "Normal" },
                set: { speed in
                  model.state.speed = speed
                  NativeUI.post("set_speed", ["speed": speed])
                })
            ) {
              ForEach(speeds) { Text($0.title).tag($0.id) }
            } label: {
              Label("Game speed", systemImage: "speedometer")
            }
          }
        }
        if let windows = model.state.windows, !windows.isEmpty {
          Section("Hospital") {
            ForEach(windows) { window in
              Button(window.title) { NativeUI.post("open_window", ["id": window.id]) }
            }
          }
        }
        Section {
          NavigationLink { SaveLoadView(mode: .save) } label: {
            Label("Save", systemImage: "square.and.arrow.down")
          }
          NavigationLink { SaveLoadView(mode: .load) } label: {
            Label("Load", systemImage: "folder")
          }
          NavigationLink { SettingsView() } label: {
            Label("Settings", systemImage: "gearshape")
          }
        }
        Section {
          if model.state.canRestart ?? false {
            Button("Restart Level", role: .destructive) { confirmRestart = true }
          }
          Button("Quit to Main Menu", role: .destructive) { confirmQuit = true }
        }
      }
      .navigationTitle(model.state.levelName ?? "Menu")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { DoneButton() }
      .confirmationDialog(
        "Restart this level? Anything not saved is lost.", isPresented: $confirmRestart,
        titleVisibility: .visible
      ) {
        Button("Restart Level", role: .destructive) { NativeUI.post("restart") }
      }
      .confirmationDialog(
        "Quit to the main menu? Anything not saved is lost.", isPresented: $confirmQuit,
        titleVisibility: .visible
      ) {
        Button("Quit", role: .destructive) { NativeUI.post("quit_to_menu") }
      }
    }
  }
}

// MARK: - Save and load

struct SaveLoadView: View {
  enum Mode { case save, load }
  let mode: Mode
  @EnvironmentObject var model: NativeModel
  @State private var newName = ""
  @State private var overwrite: SaveFile?
  @State private var loadConfirm: SaveFile?
  @State private var renaming: SaveFile?
  @State private var renameText = ""
  @FocusState private var nameFocused: Bool

  private var saves: [SaveFile] {
    let all = model.state.saves ?? []
    // Autosaves and the resume file can be loaded but not overwritten.
    return mode == .save ? all.filter { $0.folder == nil || $0.folder == "" } : all
  }

  var body: some View {
    List {
      if mode == .save {
        Section {
          HStack {
            TextField("New save name", text: $newName)
              .focused($nameFocused)
              .submitLabel(.done)
              .onSubmit(saveNew)
            Button("Save", action: saveNew)
              .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
      }
      Section {
        if saves.isEmpty {
          Text("No saved games yet").foregroundStyle(.secondary)
        }
        ForEach(saves) { save in
          Button {
            if mode == .save {
              overwrite = save
            } else if model.state.inGame ?? false {
              loadConfirm = save
            } else {
              NativeUI.post("load", ["path": save.path])
            }
          } label: {
            SaveRow(save: save)
          }
          .swipeActions {
            Button("Delete", role: .destructive) {
              NativeUI.post("delete_save", ["path": save.path])
            }
            Button("Rename") {
              renameText = save.name
              renaming = save
            }
          }
        }
      } header: {
        Text(model.state.saveLocation ?? "")
      } footer: {
        if !saves.isEmpty { Text("Swipe left on a save to rename or delete it.") }
      }
    }
    .navigationTitle(mode == .save ? "Save Game" : "Load Game")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      "Replace “\(overwrite?.name ?? "")”?",
      isPresented: Binding(get: { overwrite != nil }, set: { if !$0 { overwrite = nil } }),
      titleVisibility: .visible
    ) {
      Button("Replace", role: .destructive) {
        if let save = overwrite { NativeUI.post("save", ["name": save.name]) }
      }
    }
    .confirmationDialog(
      "Load “\(loadConfirm?.name ?? "")”? Anything not saved in this game is lost.",
      isPresented: Binding(get: { loadConfirm != nil }, set: { if !$0 { loadConfirm = nil } }),
      titleVisibility: .visible
    ) {
      Button("Load") {
        if let save = loadConfirm { NativeUI.post("load", ["path": save.path]) }
      }
    }
    .alert(
      "Rename",
      isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    ) {
      TextField("Name", text: $renameText)
      Button("Cancel", role: .cancel) {}
      Button("Rename") {
        if let save = renaming {
          NativeUI.post("rename_save", ["path": save.path, "name": renameText])
        }
      }
    }
  }

  private func saveNew() {
    let name = newName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    if let existing = saves.first(where: { $0.name.lowercased() == name.lowercased() }) {
      overwrite = existing
    } else {
      NativeUI.post("save", ["name": name])
    }
    nameFocused = false
  }
}

struct SaveRow: View {
  let save: SaveFile

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(save.name).foregroundStyle(.primary)
        if let folder = save.folder, !folder.isEmpty {
          Text(folder)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.2)))
            .foregroundStyle(.secondary)
        }
      }
      Text(Date(timeIntervalSince1970: save.modified), format: .dateTime.day().month().hour().minute())
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Settings

struct SettingsView: View {
  @EnvironmentObject var model: NativeModel

  private var settings: GameSettings { model.state.settings ?? GameSettings() }

  var body: some View {
    Form {
      Section("Sound") {
        Toggle("Sound effects", isOn: toggle(\.playSounds, "play_sounds"))
        if settings.playSounds {
          VolumeSlider(value: slider(\.soundVolume, "sound_volume"), key: "sound_volume")
        }
        Toggle("Announcements", isOn: toggle(\.playAnnouncements, "play_announcements"))
        if settings.playAnnouncements {
          VolumeSlider(
            value: slider(\.announcementVolume, "announcement_volume"), key: "announcement_volume")
        }
        if settings.hasMusic {
          Toggle("Music", isOn: toggle(\.playMusic, "play_music"))
          if settings.playMusic {
            VolumeSlider(value: slider(\.musicVolume, "music_volume"), key: "music_volume")
          }
        }
      }
      Section {
        Picker("Touch controls", selection: choice(\.touchControls, "touch_controls")) {
          Text("Trackpad").tag("trackpad")
          Text("Direct").tag("direct")
        }
        .pickerStyle(.segmented)
        if settings.touchControls == "trackpad" {
          HStack {
            Text("Cursor speed")
            Slider(value: slider(\.cursorSpeed, "cursor_speed"), in: 0.5...2.5) { editing in
              if !editing {
                NativeUI.post("setting", ["key": "cursor_speed", "value": settings.cursorSpeed])
              }
            }
          }
        }
        Toggle("Scroll at screen edges", isOn: toggle(\.edgeScrolling, "edge_scrolling"))
      } header: {
        Text("Controls")
      } footer: {
        Text(
          settings.touchControls == "trackpad"
            ? "Slide a finger to move the cursor, tap to click."
            : "Tap where you want to click. Long press to right click.")
      }
      Section("Game") {
        Toggle("Adviser", isOn: toggle(\.adviser, "adviser"))
        Toggle("24-hour clock", isOn: toggle(\.twentyfourHourClock, "twentyfour_hour_clock"))
        if !settings.autosaveOptions.isEmpty {
          Picker(
            "Autosave",
            selection: Binding(
              get: { String(settings.autosaveFrequency) },
              set: { value in
                model.state.settings?.autosaveFrequency = Int(value) ?? 0
                NativeUI.post("setting", ["key": "autosave_frequency", "value": Int(value) ?? 0])
              })
          ) {
            ForEach(settings.autosaveOptions) { Text($0.title).tag($0.id) }
          }
        }
        if !settings.languages.isEmpty {
          Picker("Language", selection: choice(\.language, "language")) {
            ForEach(settings.languages) { Text($0.title).tag($0.id) }
          }
        }
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func toggle(_ path: WritableKeyPath<GameSettings, Bool>, _ key: String) -> Binding<Bool> {
    Binding(
      get: { settings[keyPath: path] },
      set: { value in
        var updated = settings
        updated[keyPath: path] = value
        model.state.settings = updated
        NativeUI.post("setting", ["key": key, "value": value])
      })
  }

  private func choice(_ path: WritableKeyPath<GameSettings, String>, _ key: String)
    -> Binding<String>
  {
    Binding(
      get: { settings[keyPath: path] },
      set: { value in
        var updated = settings
        updated[keyPath: path] = value
        model.state.settings = updated
        NativeUI.post("setting", ["key": key, "value": value])
      })
  }

  // Sliders update the screen as they move and tell Lua when they stop.
  private func slider(_ path: WritableKeyPath<GameSettings, Double>, _ key: String)
    -> Binding<Double>
  {
    Binding(
      get: { settings[keyPath: path] },
      set: { value in
        var updated = settings
        updated[keyPath: path] = value
        model.state.settings = updated
      })
  }
}

struct VolumeSlider: View {
  @Binding var value: Double
  let key: String

  var body: some View {
    HStack {
      Image(systemName: "speaker.fill").foregroundStyle(.secondary)
      Slider(value: $value, in: 0...1) { editing in
        if !editing { NativeUI.post("setting", ["key": key, "value": value]) }
      }
      Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
    }
  }
}

// MARK: - Main menu

struct MainMenuCard: View {
  @EnvironmentObject var model: NativeModel
  // The page showing: nil for the menu itself. (Simple navigation of our
  // own: a NavigationStack pads the card for the notch it doesn't touch.)
  @State private var page: String?

  private func picture(_ name: String) -> String? { model.state.pictures?[name] }

  private let titles = [
    "new_game": "New Game", "campaigns": "Campaigns", "levels": "Single Levels",
    "load": "Load Game", "settings": "Settings",
  ]

  var body: some View {
    ZStack {
      Color.black.opacity(0.25).ignoresSafeArea()
      VStack(spacing: 0) {
        ZStack {
          Text(page.flatMap { titles[$0] } ?? "Theme Hospital").font(.headline)
          if page != nil {
            HStack {
              Button {
                withAnimation(.easeInOut(duration: 0.2)) { page = nil }
              } label: {
                Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
              }
              Spacer()
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        Group {
          switch page {
          case "new_game": NewGameView()
          case "campaigns": CampaignListView()
          case "levels": LevelListView()
          case "load": SaveLoadView(mode: .load)
          case "settings": SettingsView()
          default: menu
          }
        }
        .transition(.move(edge: page == nil ? .leading : .trailing))
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .frame(maxWidth: 460, maxHeight: 440)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .shadow(radius: 20)
      .padding()
    }
  }

  private func open(_ name: String) {
    withAnimation(.easeInOut(duration: 0.2)) { page = name }
  }

  private var menu: some View {
    List {
      Section {
        if model.state.canContinue ?? false {
          Button {
            NativeUI.post("continue")
          } label: {
            MenuRow(title: "Continue", picture: picture("status"), symbol: "play.fill")
          }
        }
        Button { open("new_game") } label: {
          MenuRow(title: "New Game", picture: picture("build"), symbol: "cross.case", more: true)
        }
        if !(model.state.campaigns ?? []).isEmpty {
          Button { open("campaigns") } label: {
            MenuRow(title: "Campaigns", picture: picture("town_map"), symbol: "map", more: true)
          }
        }
        if !(model.state.levels ?? []).isEmpty {
          Button { open("levels") } label: {
            MenuRow(title: "Single Levels", picture: picture("casebook"), symbol: "building.2", more: true)
          }
        }
        Button { open("load") } label: {
          MenuRow(title: "Load Game", picture: picture("policy"), symbol: "folder", more: true)
        }
        Button { open("settings") } label: {
          MenuRow(title: "Settings", picture: nil, symbol: "gearshape", more: true)
        }
      } header: {
        StaffBanner(model: model).textCase(nil)
      }
    }
  }
}

//! A menu row with a picture from the game's art (or a symbol without one).
struct MenuRow: View {
  let title: String
  let picture: String?
  let symbol: String
  var more = false  // Shows a chevron: the row opens a page.

  var body: some View {
    HStack(spacing: 14) {
      if picture != nil {
        GamePicture(path: picture)
          .frame(width: 32, height: 32)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      } else {
        Image(systemName: symbol)
          .font(.title3)
          .frame(width: 32, height: 32)
          .foregroundStyle(.tint)
      }
      Text(title).foregroundStyle(.primary)
      if more {
        Spacer()
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
    }
    // Rows that open a page read like navigation rows, not like buttons.
    .tint(more ? Color.primary : Color.accentColor)
  }
}

//! The four kinds of staff, as the game's hire window pictures them.
struct StaffBanner: View {
  @ObservedObject var model: NativeModel

  var body: some View {
    let names = ["doctor", "nurse", "handyman", "receptionist"]
    let paths = names.compactMap { model.state.pictures?[$0] }
    if paths.count == names.count {
      HStack(spacing: 10) {
        ForEach(paths, id: \.self) { path in
          GamePicture(path: path)
            .frame(height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
    }
  }
}

struct NewGameView: View {
  @EnvironmentObject var model: NativeModel
  @State private var difficulty = ""
  @State private var tutorial = false

  var body: some View {
    Form {
      Section {
      } header: {
        StaffBanner(model: model).textCase(nil)
      }
      if let difficulties = model.state.difficulties, difficulties.count > 1 {
        Picker("Difficulty", selection: $difficulty) {
          ForEach(difficulties) { Text($0.title).tag($0.id) }
        }
        .pickerStyle(.segmented)
      }
      if model.state.canTutorial ?? true {
        Toggle("Tutorial", isOn: $tutorial)
      }
      Section {
        Button("Start") {
          NativeUI.post("new_game", ["difficulty": difficulty, "tutorial": tutorial])
        }
        .bold()
      }
    }
    .navigationTitle("New Game")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if difficulty.isEmpty {
        difficulty = model.state.defaultDifficulty ?? model.state.difficulties?.first?.id ?? ""
      }
    }
  }
}

struct CampaignListView: View {
  @EnvironmentObject var model: NativeModel

  var body: some View {
    List(model.state.campaigns ?? []) { campaign in
      Button {
        NativeUI.post("start_campaign", ["path": campaign.path])
      } label: {
        DescribedRow(title: campaign.name, description: campaign.description)
      }
    }
    .navigationTitle("Campaigns")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct LevelListView: View {
  @EnvironmentObject var model: NativeModel

  var body: some View {
    List(model.state.levels ?? []) { level in
      Button {
        NativeUI.post("start_level", ["level_file": level.levelFile])
      } label: {
        DescribedRow(title: level.name, description: level.description)
      }
    }
    .navigationTitle("Single Levels")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct DescribedRow: View {
  let title: String
  let description: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).foregroundStyle(.primary)
      if let description = description, !description.isEmpty {
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(4)
      }
    }
  }
}

// MARK: - Build room catalogue

struct RoomCatalogView: View {
  @EnvironmentObject var model: NativeModel

  private var categories: [String] {
    var seen: [String] = []
    for room in model.state.rooms ?? [] where !seen.contains(room.category) {
      seen.append(room.category)
    }
    return seen
  }

  private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
        ForEach(categories, id: \.self) { category in
          Section {
            ForEach((model.state.rooms ?? []).filter { $0.category == category }) { room in
              RoomCard(room: room)
            }
          } header: {
            Text(category)
              .font(.headline)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 6)
              .background(Color(uiColor: .systemBackground))
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 12)
    }
    .navigationTitle("Build Room")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct RoomCard: View {
  let room: RoomOption

  var body: some View {
    Button {
      NativeUI.post("pick_room", ["id": room.id])
    } label: {
      VStack(spacing: 6) {
        GamePicture(path: room.image)
          .frame(height: 64)
          .frame(maxWidth: .infinity)
        Text(room.name)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
          .multilineTextAlignment(.center)
        HStack(spacing: 4) {
          if room.quick {
            Image(systemName: "bolt.fill").foregroundStyle(.tint)
          }
          Text(room.cost).monospacedDigit()
            .foregroundStyle(room.affordable ? Color.secondary : Color.red)
        }
        .font(.caption)
      }
      .padding(10)
      .frame(maxWidth: .infinity, minHeight: 140)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color(uiColor: .secondarySystemBackground)))
      .overlay(alignment: .topTrailing) {
        if room.quick {
          Text("Quick")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
            .foregroundStyle(.white)
            .padding(6)
        }
      }
      .opacity(room.affordable ? 1 : 0.5)
    }
    .buttonStyle(.plain)
    .disabled(!room.affordable)
    .accessibilityLabel(room.quick ? "\(room.name), Quick Build, \(room.cost)" : "\(room.name), \(room.cost)")
  }
}

// A picture made from the game's own art (see NativeUI:pictureDir in
// lua/native_ui.lua), scaled up with sharp pixels like the game itself.
struct GamePicture: View {
  let path: String?
  private static var cache: [String: UIImage] = [:]

  var body: some View {
    if let path = path, let image = GamePicture.load(path) {
      Image(uiImage: image)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
        .accessibilityHidden(true)
    } else {
      Color.clear
    }
  }

  private static func load(_ path: String) -> UIImage? {
    if let image = cache[path] { return image }
    guard let image = UIImage(contentsOfFile: path) else { return nil }
    cache[path] = image
    return image
  }
}
