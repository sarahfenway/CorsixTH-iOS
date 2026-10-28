// Copyright (c) 2026 CorsixTH iOS port contributors. MIT licence (see
// src/native_bridge.h for the full text).
//
// The in-game chrome: a status pill (money, date, messages) at the top left
// and a toolbar (build, furnish, edit, hire, hospital screens, speed, menu)
// at the top right, floating over the game in Liquid Glass. They replace
// Theme Hospital's bottom panel and menu bar. Lua sends the state
// (SDL.native.setToolbar) whenever it changes.

import UIKit

struct ToolbarState: Decodable {
  var money = ""
  var date = ""
  var reputation: Double = 0  // 0...1
  var messages = 0
  var speed = "Normal"
  var speeds: [NamedOption] = []
  var windows: [NamedOption] = []

  init() {}

  // Missing or null values keep their defaults.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    money = (try? c.decodeIfPresent(String.self, forKey: .money)) ?? money
    date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? date
    reputation = (try? c.decodeIfPresent(Double.self, forKey: .reputation)) ?? reputation
    messages = (try? c.decodeIfPresent(Int.self, forKey: .messages)) ?? messages
    speed = (try? c.decodeIfPresent(String.self, forKey: .speed)) ?? speed
    speeds = (try? c.decodeIfPresent([NamedOption].self, forKey: .speeds)) ?? speeds
    windows = (try? c.decodeIfPresent([NamedOption].self, forKey: .windows)) ?? windows
  }

  private enum CodingKeys: String, CodingKey {
    case money, date, reputation, messages, speed, speeds, windows
  }
}

final class GameToolbar {
  private weak var parent: UIView?
  private let statusPill: UIVisualEffectView
  private let toolbar: UIVisualEffectView
  private let moneyLabel = UILabel()
  private let dateLabel = UILabel()
  private let reputationBar = UIProgressView(progressViewStyle: .bar)
  private let messageButton = UIButton(type: .system)
  private let hospitalButton = UIButton(type: .system)
  private let speedButton = UIButton(type: .system)
  private var state = ToolbarState()

  init(in view: UIView) {
    parent = view
    statusPill = GameToolbar.glassView()
    toolbar = GameToolbar.glassView()

    // Status pill: money and reputation, date, unread messages.
    moneyLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
    dateLabel.font = .systemFont(ofSize: 13, weight: .medium)
    dateLabel.textColor = .secondaryLabel
    reputationBar.progressTintColor = .systemGreen
    reputationBar.trackTintColor = UIColor.label.withAlphaComponent(0.15)
    reputationBar.layer.cornerRadius = 1.5
    reputationBar.clipsToBounds = true
    reputationBar.accessibilityLabel = "Reputation"
    let moneyStack = UIStackView(arrangedSubviews: [moneyLabel, reputationBar])
    moneyStack.axis = .vertical
    moneyStack.spacing = 3
    configure(messageButton, symbol: "envelope.fill", label: "Messages") {
      NativeUI.post("open_message")
    }
    messageButton.tintColor = .systemRed
    let statusStack = UIStackView(arrangedSubviews: [moneyStack, dateLabel, messageButton])
    statusStack.axis = .horizontal
    statusStack.alignment = .center
    statusStack.spacing = 12
    statusStack.translatesAutoresizingMaskIntoConstraints = false
    statusPill.contentView.addSubview(statusStack)

    // Toolbar buttons.
    let build = button(symbol: "hammer.fill", label: "Build Room") { NativeUI.post("tool", ["id": "build"]) }
    let furnish = button(symbol: "sofa.fill", label: "Furnish Corridor") {
      NativeUI.post("tool", ["id": "furnish"])
    }
    let edit = button(symbol: "pencil.and.outline", label: "Edit Room") {
      NativeUI.post("tool", ["id": "edit"])
    }
    let hire = button(symbol: "person.badge.plus", label: "Hire Staff") {
      NativeUI.post("tool", ["id": "hire"])
    }
    configure(hospitalButton, symbol: "building.2.fill", label: "Hospital", action: nil)
    hospitalButton.showsMenuAsPrimaryAction = true
    configure(speedButton, symbol: "play.fill", label: "Game Speed", action: nil)
    speedButton.showsMenuAsPrimaryAction = true
    let menu = button(symbol: "ellipsis.circle", label: "Menu") { NativeUI.post("menu_button") }
    let separator = UIView()
    separator.backgroundColor = UIColor.label.withAlphaComponent(0.2)
    separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
    separator.heightAnchor.constraint(equalToConstant: 22).isActive = true
    let toolStack = UIStackView(arrangedSubviews: [
      build, furnish, edit, hire, separator, hospitalButton, speedButton, menu,
    ])
    toolStack.axis = .horizontal
    toolStack.alignment = .center
    toolStack.spacing = 2
    toolStack.translatesAutoresizingMaskIntoConstraints = false
    toolbar.contentView.addSubview(toolStack)

    for pill in [statusPill, toolbar] {
      pill.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(pill)
    }
    let guide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      statusPill.topAnchor.constraint(equalTo: guide.topAnchor, constant: 6),
      statusPill.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
      statusPill.heightAnchor.constraint(equalToConstant: 44),
      statusStack.leadingAnchor.constraint(equalTo: statusPill.contentView.leadingAnchor, constant: 16),
      statusStack.trailingAnchor.constraint(
        equalTo: statusPill.contentView.trailingAnchor, constant: -10),
      statusStack.centerYAnchor.constraint(equalTo: statusPill.contentView.centerYAnchor),
      reputationBar.heightAnchor.constraint(equalToConstant: 3),

      toolbar.topAnchor.constraint(equalTo: guide.topAnchor, constant: 6),
      toolbar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
      toolbar.heightAnchor.constraint(equalToConstant: 44),
      toolStack.leadingAnchor.constraint(equalTo: toolbar.contentView.leadingAnchor, constant: 6),
      toolStack.trailingAnchor.constraint(equalTo: toolbar.contentView.trailingAnchor, constant: -6),
      toolStack.centerYAnchor.constraint(equalTo: toolbar.contentView.centerYAnchor),
    ])
    update(state)
  }

  func remove() {
    statusPill.removeFromSuperview()
    toolbar.removeFromSuperview()
  }

  func setHidden(_ hidden: Bool) {
    statusPill.isHidden = hidden
    toolbar.isHidden = hidden
  }

  func update(_ new: ToolbarState) {
    state = new
    moneyLabel.text = new.money
    dateLabel.text = new.date
    reputationBar.progress = Float(max(0, min(1, new.reputation)))
    reputationBar.progressTintColor =
      new.reputation < 0.3 ? .systemRed : new.reputation < 0.5 ? .systemOrange : .systemGreen
    messageButton.isHidden = new.messages == 0
    messageButton.accessibilityValue = "\(new.messages) unread"

    hospitalButton.menu = UIMenu(
      title: "Hospital",
      children: new.windows.map { window in
        UIAction(title: window.title, image: UIImage(systemName: GameToolbar.symbol(for: window.id))) { _ in
          NativeUI.post("open_window", ["id": window.id])
        }
      })
    speedButton.setImage(UIImage(systemName: GameToolbar.speedSymbol(new.speed)), for: .normal)
    speedButton.menu = UIMenu(
      title: "Game Speed",
      children: new.speeds.reversed().map { speed in
        UIAction(
          title: speed.title, image: UIImage(systemName: GameToolbar.speedSymbol(speed.id)),
          state: speed.id == new.speed ? .on : .off
        ) { _ in
          NativeUI.post("toolbar_speed", ["speed": speed.id])
        }
      })
  }

  // MARK: Helpers

  private static func glassView() -> UIVisualEffectView {
    let view: UIVisualEffectView
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect()
      glass.isInteractive = true
      view = UIVisualEffectView(effect: glass)
    } else {
      view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    }
    view.layer.cornerRadius = 22
    view.layer.cornerCurve = .continuous
    view.clipsToBounds = true
    view.overrideUserInterfaceStyle = .dark
    return view
  }

  private func button(symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .system)
    configure(button, symbol: symbol, label: label, action: action)
    return button
  }

  private func configure(
    _ button: UIButton, symbol: String, label: String, action: (() -> Void)?
  ) {
    button.setImage(
      UIImage(
        systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)),
      for: .normal)
    button.tintColor = .label
    button.accessibilityLabel = label
    button.largeContentTitle = label
    button.showsLargeContentViewer = true
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 40),
      button.heightAnchor.constraint(equalToConstant: 40),
    ])
    if let action = action {
      button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
  }

  static func speedSymbol(_ speed: String) -> String {
    switch speed {
    case "Pause": return "pause.fill"
    case "Slowest": return "tortoise.fill"
    case "Slower": return "hare"
    case "Max speed": return "forward.fill"
    case "And then some more": return "forward.end.alt.fill"
    default: return "play.fill"
    }
  }

  static func symbol(for window: String) -> String {
    switch window {
    case "staff": return "person.3.fill"
    case "town_map": return "map.fill"
    case "research": return "flask.fill"
    case "casebook": return "cross.case.fill"
    case "status": return "chart.bar.fill"
    case "charts": return "chart.xyaxis.line"
    case "policy": return "doc.text.fill"
    case "bank": return "banknote.fill"
    case "statement": return "list.bullet.rectangle.fill"
    case "adviser_history": return "bubble.left.and.text.bubble.right.fill"
    case "briefing": return "flag.fill"
    default: return "square.grid.2x2"
    }
  }
}
