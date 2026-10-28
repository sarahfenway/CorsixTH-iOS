// Copyright (c) 2026 CorsixTH iOS port contributors. MIT licence (see
// src/native_bridge.h for the full text).
//
// Quick Build's overlay on the map: finger handles on the room outline's
// corners and middle, and a bar with Cancel / By Hand / Build. The outline
// itself is the game's own blueprint; Lua (lua/quick_build.lua) sends where
// its corners are on screen, in game pixels, whenever they move.

import UIKit

struct QuickBuildState: Decodable {
  var name: String
  var cost: String
  var valid: Bool
  var reason: String
  var logical: [Double]
  var corners: [[Double]]
  var centre: [Double]
}

// Lets touches through to the game except on its own controls.
private final class PassthroughView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

final class QuickBuildOverlay {
  private let container = PassthroughView()
  private var handles: [String: UIView] = [:]
  private let bar: UIVisualEffectView
  private let titleLabel = UILabel()
  private let reasonLabel = UILabel()
  private let buildButton = UIButton(type: .system)
  private var state: QuickBuildState?
  private var dragging: String?

  // Corner handle names in the order Lua sends the corners.
  private static let cornerNames = ["top", "right", "bottom", "left"]

  init(in view: UIView) {
    if #available(iOS 26.0, *) {
      bar = UIVisualEffectView(effect: UIGlassEffect())
    } else {
      bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    }
    container.frame = view.bounds
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(container)

    for name in QuickBuildOverlay.cornerNames + ["move"] {
      let handle = QuickBuildOverlay.makeHandle(move: name == "move")
      handle.accessibilityLabel = name == "move" ? "Move room" : "Resize room (\(name) corner)"
      let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
      handle.addGestureRecognizer(pan)
      handle.tag = handles.count
      handles[name] = handle
      container.addSubview(handle)
    }

    // The bar at the bottom.
    bar.overrideUserInterfaceStyle = .dark
    bar.layer.cornerRadius = 26
    bar.layer.cornerCurve = .continuous
    bar.clipsToBounds = true
    bar.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(bar)

    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    reasonLabel.font = .systemFont(ofSize: 12, weight: .medium)
    reasonLabel.textColor = .systemOrange
    let labels = UIStackView(arrangedSubviews: [titleLabel, reasonLabel])
    labels.axis = .vertical
    labels.spacing = 1

    let cancel = QuickBuildOverlay.barButton(title: nil, symbol: "xmark", label: "Cancel") {
      NativeUI.post("quick_build_cancel")
    }
    let byHand = QuickBuildOverlay.barButton(title: "By Hand", symbol: nil, label: "By Hand") {
      NativeUI.post("quick_build_by_hand")
    }
    var config = UIButton.Configuration.borderedProminent()
    config.title = "Build"
    config.image = UIImage(systemName: "hammer.fill")
    config.imagePadding = 6
    config.cornerStyle = .capsule
    buildButton.configuration = config
    buildButton.accessibilityLabel = "Build"
    buildButton.addAction(UIAction { _ in NativeUI.post("quick_build_build") }, for: .touchUpInside)

    let row = UIStackView(arrangedSubviews: [cancel, labels, byHand, buildButton])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false
    bar.contentView.addSubview(row)

    let guide = container.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      bar.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
      bar.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -10),
      bar.heightAnchor.constraint(equalToConstant: 52),
      row.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 8),
      row.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -8),
      row.centerYAnchor.constraint(equalTo: bar.contentView.centerYAnchor),
    ])
  }

  func remove() {
    container.removeFromSuperview()
  }

  func update(_ new: QuickBuildState) {
    state = new
    titleLabel.text = "\(new.name) · \(new.cost)"
    reasonLabel.text = new.reason
    reasonLabel.isHidden = new.reason.isEmpty
    buildButton.isEnabled = new.valid
    layoutHandles()
  }

  // MARK: Coordinates (game pixels <-> points, as SDL's logical scaling)

  private func fit() -> (scale: CGFloat, ox: CGFloat, oy: CGFloat) {
    guard let state = state, state.logical.count == 2, state.logical[0] > 0, state.logical[1] > 0
    else { return (1, 0, 0) }
    let size = container.bounds.size
    let lw = CGFloat(state.logical[0])
    let lh = CGFloat(state.logical[1])
    let scale = min(size.width / lw, size.height / lh)
    return (scale, (size.width - lw * scale) / 2, (size.height - lh * scale) / 2)
  }

  private func toPoints(_ p: [Double]) -> CGPoint {
    let f = fit()
    return CGPoint(x: f.ox + CGFloat(p[0]) * f.scale, y: f.oy + CGFloat(p[1]) * f.scale)
  }

  private func toLogical(_ p: CGPoint) -> (Double, Double) {
    let f = fit()
    return (Double((p.x - f.ox) / f.scale), Double((p.y - f.oy) / f.scale))
  }

  private func layoutHandles() {
    guard let state = state, state.corners.count == 4 else { return }
    for (i, name) in QuickBuildOverlay.cornerNames.enumerated() where name != dragging {
      handles[name]?.center = toPoints(state.corners[i])
    }
    if dragging != "move" {
      handles["move"]?.center = toPoints(state.centre)
    }
  }

  // MARK: Dragging

  @objc private func panned(_ pan: UIPanGestureRecognizer) {
    guard let handle = pan.view,
      let name = handles.first(where: { $0.value === handle })?.key
    else { return }
    let point = pan.location(in: container)
    switch pan.state {
    case .began, .changed:
      dragging = name
      handle.center = point
      let (x, y) = toLogical(point)
      NativeUI.post("quick_build_drag", ["handle": name, "x": x, "y": y, "ended": false])
    default:
      dragging = nil
      let (x, y) = toLogical(point)
      NativeUI.post("quick_build_drag", ["handle": name, "x": x, "y": y, "ended": true])
      layoutHandles()
    }
  }

  // MARK: Views

  private static func makeHandle(move: Bool) -> UIView {
    // A 44 pt touch target around a smaller visible knob.
    let target = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    let knob = UIView(frame: CGRect(x: 0, y: 0, width: move ? 34 : 24, height: move ? 34 : 24))
    knob.center = CGPoint(x: 22, y: 22)
    knob.backgroundColor = .white
    knob.layer.cornerRadius = knob.bounds.width / 2
    knob.layer.shadowColor = UIColor.black.cgColor
    knob.layer.shadowOpacity = 0.35
    knob.layer.shadowRadius = 3
    knob.layer.shadowOffset = CGSize(width: 0, height: 1)
    knob.layer.borderColor = UIColor.systemBlue.cgColor
    knob.layer.borderWidth = 2
    knob.isUserInteractionEnabled = false
    if move {
      let icon = UIImageView(
        image: UIImage(
          systemName: "arrow.up.and.down.and.arrow.left.and.right",
          withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
      icon.tintColor = .systemBlue
      icon.center = CGPoint(x: knob.bounds.midX, y: knob.bounds.midY)
      knob.addSubview(icon)
    }
    target.addSubview(knob)
    target.isAccessibilityElement = true
    return target
  }

  private static func barButton(
    title: String?, symbol: String?, label: String, action: @escaping () -> Void
  ) -> UIButton {
    var config = UIButton.Configuration.plain()
    config.title = title
    if let symbol = symbol {
      config.image = UIImage(systemName: symbol)
    }
    config.baseForegroundColor = .label
    let button = UIButton(configuration: config)
    button.accessibilityLabel = label
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return button
  }
}
