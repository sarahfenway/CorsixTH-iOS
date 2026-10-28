// Copyright (c) 2026 CorsixTH iOS port contributors. MIT licence (see
// src/native_bridge.h for the full text).
//
// The in-game chrome: a status pill (money, date, fax messages) at the top left
// and a toolbar (build, furnish, edit, hire, hospital screens, speed, menu)
// at the top right, floating over the game in Liquid Glass. They replace
// Theme Hospital's bottom panel and menu bar. Lua sends the state
// (SDL.native.setToolbar) whenever it changes.

import UIKit

//! A fax message on the bottom panel (the game shows up to five).
struct FaxState: Decodable, Hashable {
  var index: Int
  var kind: String
  var title: String
  var image: String?
  var open: Bool
  var dismissable: Bool
  var timeLeft: Double?  // 0...1 for faxes that expire (emergencies, VIPs...)
}

struct ToolbarState: Decodable {
  var money = ""
  var date = ""
  var reputation: Double = 0  // 0...1
  var faxes: [FaxState] = []
  var faxesWaiting = 0
  var speed = "Normal"
  var speeds: [NamedOption] = []
  var windows: [NamedOption] = []
  var icons: [String: String] = [:]  // Game art for the tool buttons, by tool id.

  init() {}

  // Missing or null values keep their defaults.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    money = (try? c.decodeIfPresent(String.self, forKey: .money)) ?? money
    date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? date
    reputation = (try? c.decodeIfPresent(Double.self, forKey: .reputation)) ?? reputation
    faxes = (try? c.decodeIfPresent([FaxState].self, forKey: .faxes)) ?? faxes
    faxesWaiting = (try? c.decodeIfPresent(Int.self, forKey: .faxesWaiting)) ?? faxesWaiting
    speed = (try? c.decodeIfPresent(String.self, forKey: .speed)) ?? speed
    speeds = (try? c.decodeIfPresent([NamedOption].self, forKey: .speeds)) ?? speeds
    windows = (try? c.decodeIfPresent([NamedOption].self, forKey: .windows)) ?? windows
    icons = (try? c.decodeIfPresent([String: String].self, forKey: .icons)) ?? icons
  }

  private enum CodingKeys: String, CodingKey {
    case money, date, reputation, faxes, faxesWaiting, speed, speeds, windows, icons
  }
}

final class GameToolbar {
  private weak var parent: UIView?
  private let statusPill: UIVisualEffectView
  private let faxPill: UIVisualEffectView  // Below the status pill, while there are faxes.
  private let toolbar: UIVisualEffectView
  private let moneyLabel = UILabel()
  private let dateLabel = UILabel()
  private let reputationBar = UIProgressView(progressViewStyle: .bar)
  private let faxStack = UIStackView()
  private let faxWaitingLabel = UILabel()
  private var shownFaxes: [FaxState]?
  private let hospitalButton = UIButton(type: .system)
  private let speedButton = UIButton(type: .system)
  private var state = ToolbarState()
  private var toolButtons: [String: UIButton] = [:]

  init(in view: UIView) {
    parent = view
    statusPill = GameToolbar.glassView()
    faxPill = GameToolbar.glassView()
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
    // Fax messages: the game's own icons, oldest first, as on its bottom panel.
    faxStack.axis = .horizontal
    faxStack.alignment = .center
    faxStack.spacing = 4
    faxWaitingLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    faxWaitingLabel.textColor = .secondaryLabel
    let faxRow = UIStackView(arrangedSubviews: [faxStack, faxWaitingLabel])
    faxRow.axis = .horizontal
    faxRow.alignment = .center
    faxRow.spacing = 6
    faxRow.translatesAutoresizingMaskIntoConstraints = false
    faxPill.contentView.addSubview(faxRow)
    let statusStack = UIStackView(arrangedSubviews: [moneyStack, dateLabel])
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
    toolButtons = ["build": build, "furnish": furnish, "edit": edit, "hire": hire]
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

    for pill in [statusPill, faxPill, toolbar] {
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

      faxPill.topAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: 6),
      faxPill.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor),
      faxPill.heightAnchor.constraint(equalToConstant: 46),
      faxRow.leadingAnchor.constraint(equalTo: faxPill.contentView.leadingAnchor, constant: 10),
      faxRow.trailingAnchor.constraint(equalTo: faxPill.contentView.trailingAnchor, constant: -10),
      faxRow.centerYAnchor.constraint(equalTo: faxPill.contentView.centerYAnchor),

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
    faxPill.removeFromSuperview()
    toolbar.removeFromSuperview()
  }

  private var hidden = false

  func setHidden(_ hidden: Bool) {
    self.hidden = hidden
    statusPill.isHidden = hidden
    toolbar.isHidden = hidden
    faxPill.isHidden = hidden || state.faxes.isEmpty
  }

  func update(_ new: ToolbarState) {
    state = new
    moneyLabel.text = new.money
    dateLabel.text = new.date
    reputationBar.progress = Float(max(0, min(1, new.reputation)))
    reputationBar.progressTintColor =
      new.reputation < 0.3 ? .systemRed : new.reputation < 0.5 ? .systemOrange : .systemGreen
    faxPill.isHidden = hidden || new.faxes.isEmpty
    if shownFaxes != new.faxes {
      shownFaxes = new.faxes
      rebuildFaxes(new.faxes)
    }
    faxWaitingLabel.text = new.faxesWaiting > 0 ? "+\(new.faxesWaiting)" : nil
    faxWaitingLabel.isHidden = new.faxesWaiting == 0
    faxWaitingLabel.accessibilityLabel = "\(new.faxesWaiting) more messages waiting"

    // The game's own button art where Lua has made it; symbols otherwise.
    for (tool, button) in toolButtons {
      if let image = GameArt.image(new.icons[tool], height: 30) {
        button.setImage(image, for: .normal)
        button.imageView?.layer.cornerRadius = 5
        button.imageView?.clipsToBounds = true
      }
    }
    hospitalButton.menu = UIMenu(
      title: "Hospital",
      children: new.windows.map { window in
        UIAction(
          title: window.title,
          image: GameArt.image(window.image, height: 26)
            ?? UIImage(systemName: GameToolbar.symbol(for: window.id))
        ) { _ in
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

  // One button per fax: tap opens (or closes) it; long press offers Dismiss
  // when the game allows it (its right click). Faxes that expire show how
  // long they have left.
  private func rebuildFaxes(_ faxes: [FaxState]) {
    faxStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    faxStack.isHidden = faxes.isEmpty
    for fax in faxes {
      let button = UIButton(type: .custom)
      let image = GameArt.image(fax.image, height: 28)
      button.setImage(image ?? UIImage(systemName: "envelope.fill"), for: .normal)
      button.tintColor = .systemRed
      button.layer.cornerRadius = 6
      button.layer.borderWidth = fax.open ? 2 : 0
      button.layer.borderColor = UIColor.white.cgColor
      button.accessibilityLabel = fax.title
      button.accessibilityValue = fax.open ? "Open" : nil
      button.largeContentTitle = fax.title
      button.showsLargeContentViewer = true
      let index = fax.index
      button.addAction(
        UIAction { _ in NativeUI.post("open_message", ["index": index]) }, for: .touchUpInside)
      if fax.dismissable {
        button.menu = UIMenu(children: [
          UIAction(title: "Open", image: UIImage(systemName: "doc.text")) { _ in
            NativeUI.post("open_message", ["index": index])
          },
          UIAction(title: "Dismiss", image: UIImage(systemName: "xmark"), attributes: .destructive) { _ in
            NativeUI.post("dismiss_message", ["index": index])
          },
        ])
      }
      button.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 32),
        button.heightAnchor.constraint(equalToConstant: 30),
      ])
      let cell = UIStackView(arrangedSubviews: [button])
      cell.axis = .vertical
      cell.alignment = .center
      cell.spacing = 2
      if let left = fax.timeLeft {
        let bar = UIProgressView(progressViewStyle: .bar)
        bar.progress = Float(max(0, min(1, left)))
        bar.progressTintColor = left < 0.25 ? .systemRed : .systemOrange
        bar.trackTintColor = UIColor.label.withAlphaComponent(0.15)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: 26).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
        bar.isAccessibilityElement = false
        cell.addArrangedSubview(bar)
        button.accessibilityValue = [button.accessibilityValue, "\(Int(left * 100))% of time left"]
          .compactMap { $0 }.joined(separator: ", ")
      }
      faxStack.addArrangedSubview(cell)
    }
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
