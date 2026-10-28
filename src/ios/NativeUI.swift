// Copyright (c) 2026 CorsixTH iOS port contributors. MIT licence (see
// src/native_bridge.h for the full text).
//
// Native (SwiftUI) screens shown over the game. The Lua UI decides what to
// show and sends the data as JSON (src/native_bridge.cpp); the screens send
// actions back with `NativeUI.post`, which Lua receives in
// App:onNativeAction (lua/native_ui.lua).

import SwiftUI
import UIKit

// MARK: - C entry points (called from src/native_bridge.cpp)

@_cdecl("cth_native_show")
public func cthNativeShow(_ screen: UnsafePointer<CChar>, _ json: UnsafePointer<CChar>) {
  NativeUI.shared.show(screen: String(cString: screen), json: String(cString: json))
}

@_cdecl("cth_native_update")
public func cthNativeUpdate(_ json: UnsafePointer<CChar>) {
  NativeUI.shared.model.apply(json: String(cString: json), replace: false)
}

@_cdecl("cth_native_dismiss")
public func cthNativeDismiss() {
  NativeUI.shared.dismiss(notifyLua: false)
}

@_cdecl("cth_native_set_toolbar")
public func cthNativeSetToolbar(_ json: UnsafePointer<CChar>) {
  NativeUI.shared.setToolbar(json: String(cString: json))
}

@_cdecl("cth_native_screen")
public func cthNativeScreen() -> UnsafePointer<CChar>? {
  return NativeUI.shared.currentScreenCString()
}

// Test hook: activates the native control with this accessibility label (as
// VoiceOver would), since automation scripts can't tap UIKit views.
@_cdecl("cth_native_tap")
public func cthNativeTap(_ label: UnsafePointer<CChar>) -> Bool {
  return NativeUI.shared.activate(label: String(cString: label))
}

// MARK: - Presentation

final class NativeUI: NSObject, UIAdaptivePresentationControllerDelegate {
  static let shared = NativeUI()

  let model = NativeModel()
  private var host: UIViewController?
  private var hostIsMainMenu = false
  private var toolbar: GameToolbar?
  private weak var textAlert: UIAlertController?
  private var screenCString: UnsafeMutablePointer<CChar>?

  //! Sends an action to Lua. Values must be JSON compatible.
  static func post(_ action: String, _ payload: [String: Any] = [:]) {
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    let json = String(decoding: data, as: UTF8.self)
    cth_native_post(action, json)
  }

  func show(screen: String, json: String) {
    if screen == "text_input" {
      showTextInput(json: json)
      return
    }
    model.apply(json: json, replace: true)
    let isMainMenu = screen == "main_menu"
    if host != nil && hostIsMainMenu != isMainMenu {
      host?.dismiss(animated: false)
      host = nil
    }
    model.screen = screen
    model.navigationID = UUID()
    if host == nil {
      present(mainMenu: isMainMenu)
    }
  }

  func dismiss(notifyLua: Bool) {
    if !notifyLua, let alert = textAlert {
      alert.dismiss(animated: true)
    }
    guard let host = host else { return }
    self.host = nil
    model.screen = ""
    if let coordinator = host.transitionCoordinator, host.isBeingPresented {
      // Still appearing (e.g. the main menu just before a resumed game
      // loads): close it once it's up.
      coordinator.animate(alongsideTransition: nil) { _ in host.dismiss(animated: true) }
    } else if host.presentingViewController != nil {
      host.dismiss(animated: true)
    }
    if notifyLua {
      NativeUI.post("dismissed")
    }
  }

  func currentScreenCString() -> UnsafePointer<CChar>? {
    free(screenCString)
    screenCString = strdup(host == nil ? "" : model.screen)
    return UnsafePointer(screenCString)
  }

  private func present(mainMenu: Bool, attempt: Int = 0) {
    guard let parent = topViewController(), parent.view.window != nil else {
      // At start-up the game's view may not be on screen yet; try again
      // once the run loop has turned.
      if attempt < 50 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          guard let self = self, self.host == nil, !self.model.screen.isEmpty else { return }
          self.present(mainMenu: mainMenu, attempt: attempt + 1)
        }
      }
      return
    }
    let controller = UIHostingController(rootView: NativeRootView().environmentObject(model))
    if mainMenu {
      // A card over the game's own menu background, which can't be swiped
      // away.
      controller.modalPresentationStyle = .overFullScreen
      controller.modalTransitionStyle = .crossDissolve
      controller.view.backgroundColor = .clear
      controller.isModalInPresentation = true
    } else {
      controller.modalPresentationStyle = .formSheet
      controller.presentationController?.delegate = self
    }
    host = controller
    hostIsMainMenu = mainMenu
    parent.present(controller, animated: true)
  }

  // Swiped away by the player.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    host = nil
    model.screen = ""
    NativeUI.post("dismissed")
  }

  // MARK: Toolbar

  //! Shows the in-game toolbar with this state, or hides it (empty json).
  func setToolbar(json: String) {
    guard !json.isEmpty else {
      toolbar?.setHidden(true)
      return
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let state = try? decoder.decode(ToolbarState.self, from: Data(json.utf8)) else {
      print("Native UI: can't read the toolbar state: \(json)")
      return
    }
    if toolbar == nil, let view = rootViewController()?.view {
      toolbar = GameToolbar(in: view)
    }
    toolbar?.setHidden(false)
    toolbar?.update(state)
  }

  // MARK: Text input

  private func showTextInput(json: String) {
    let info = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    let id = info["id"] as? Int ?? 0
    let alert = UIAlertController(
      title: info["title"] as? String, message: nil, preferredStyle: .alert)
    alert.addTextField { field in
      field.text = info["text"] as? String
      field.clearButtonMode = .whileEditing
      field.autocapitalizationType = .words
      field.returnKeyType = .done
    }
    alert.addAction(
      UIAlertAction(title: "Cancel", style: .cancel) { _ in
        NativeUI.post("text_input_cancel", ["id": id])
      })
    alert.addAction(
      UIAlertAction(title: "OK", style: .default) { _ in
        NativeUI.post("text_input", ["id": id, "text": alert.textFields?.first?.text ?? ""])
      })
    textAlert = alert
    topViewController()?.present(alert, animated: true)
  }

  // MARK: Accessibility (tests)

  func activate(label: String) -> Bool {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .reversed()  // front-most first
    // UIKit controls (the toolbar, alerts' buttons) are found by their label
    // whether or not accessibility is running.
    for window in windows where !window.isHidden {
      if let control = findControl(label: label, in: window) {
        control.sendActions(for: .touchUpInside)
        return true
      }
    }
    // SwiftUI only builds its accessibility tree while accessibility is on.
    for window in windows where !window.isHidden {
      if let element = find(label: label, in: window, depth: 0) {
        if element.accessibilityActivate() { return true }
        // Plain views (and some SwiftUI rows) don't implement activation.
        if let control = element as? UIControl {
          control.sendActions(for: .touchUpInside)
          return true
        }
        return false
      }
    }
    // Help whoever writes the test: list what can be activated.
    var labels: [String] = []
    for window in windows { collectLabels(in: window, depth: 0, into: &labels) }
    print("Native UI: no control called \"\(label)\". Labels: \(labels.joined(separator: " | "))")
    return false
  }

  private func findControl(label: String, in view: UIView) -> UIControl? {
    if view.isHidden || view.alpha < 0.01 { return nil }
    if let control = view as? UIControl, control.isEnabled, control.accessibilityLabel == label {
      return control
    }
    for subview in view.subviews.reversed() {
      if let found = findControl(label: label, in: subview) { return found }
    }
    return nil
  }

  private func collectLabels(in object: NSObject, depth: Int, into labels: inout [String]) {
    if depth > 80 { return }
    if let label = object.accessibilityLabel, !label.isEmpty, object.isAccessibilityElement {
      labels.append(label)
    }
    for child in accessibilityChildren(of: object) {
      collectLabels(in: child, depth: depth + 1, into: &labels)
    }
  }

  private func accessibilityChildren(of object: NSObject) -> [NSObject] {
    if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return [] }
    var children: [NSObject] = []
    if let elements = object.accessibilityElements as? [NSObject] {
      children += elements
    } else {
      let count = object.accessibilityElementCount()
      if count != NSNotFound && count > 0 {
        for i in 0..<count {
          if let element = object.accessibilityElement(at: i) as? NSObject { children.append(element) }
        }
      }
    }
    if let view = object as? UIView {
      children += view.subviews.reversed()
    }
    return children
  }

  private func find(label: String, in object: NSObject, depth: Int) -> NSObject? {
    if depth > 80 { return nil }
    if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return nil }
    if object.isAccessibilityElement, object.accessibilityLabel == label {
      return object
    }
    for child in accessibilityChildren(of: object) {
      if let found = find(label: label, in: child, depth: depth + 1) { return found }
    }
    return nil
  }

  // MARK: View controllers

  private func rootViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
  }

  private func topViewController() -> UIViewController? {
    var controller = rootViewController()
    while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
      controller = presented
    }
    return controller
  }
}

// MARK: - Model

final class NativeModel: ObservableObject {
  @Published var screen = ""
  @Published var state = NativeState()
  @Published var alertMessage: String?
  //! Changes whenever Lua shows a screen, to start its navigation afresh.
  @Published var navigationID = UUID()
  private var raw: [String: Any] = [:]

  func apply(json: String, replace: Bool) {
    guard var update = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    else { return }
    if let message = update.removeValue(forKey: "message") as? String, !message.isEmpty {
      alertMessage = message
    }
    if replace {
      raw = update
    } else {
      raw.merge(update) { $1 }
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
      let data = try JSONSerialization.data(withJSONObject: raw)
      state = try decoder.decode(NativeState.self, from: data)
    } catch {
      print("Native UI: can't read the game's data: \(error)")
    }
  }
}

struct NamedOption: Codable, Hashable, Identifiable {
  var id: String
  var title: String
}

struct SaveFile: Codable, Hashable, Identifiable {
  var name: String
  var path: String
  var modified: Double
  var folder: String?
  var id: String { path }
}

struct Campaign: Codable, Hashable, Identifiable {
  var name: String
  var description: String?
  var path: String
  var id: String { path }
}

struct Level: Codable, Hashable, Identifiable {
  var name: String
  var description: String?
  var levelFile: String
  var mapFile: String?
  var id: String { levelFile }
}

struct GameSettings: Codable, Hashable {
  var soundVolume: Double = 1
  var announcementVolume: Double = 1
  var musicVolume: Double = 1
  var playSounds = true
  var playAnnouncements = true
  var playMusic = false
  var hasMusic = false
  var adviser = true
  var edgeScrolling = false
  var twentyfourHourClock = true
  var touchControls = "trackpad"
  var cursorSpeed: Double = 1
  var autosaveFrequency: Int = 0
  var autosaveOptions: [NamedOption] = []
  var language = ""
  var languages: [NamedOption] = []
}

struct NativeState: Codable {
  var inGame: Bool?
  var levelName: String?
  var speed: String?
  var speeds: [NamedOption]?
  var windows: [NamedOption]?
  var canRestart: Bool?
  var saves: [SaveFile]?
  var saveLocation: String?
  var settings: GameSettings?
  var difficulties: [NamedOption]?
  var defaultDifficulty: String?
  var canTutorial: Bool?
  var campaigns: [Campaign]?
  var levels: [Level]?
  var canContinue: Bool?
}
