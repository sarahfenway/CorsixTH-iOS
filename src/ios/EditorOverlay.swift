// Copyright (c) 2026 CorsixTH iOS port contributors. MIT licence (see
// src/native_bridge.h for the full text).
//
// Native controls for the game's room editor and corridor furnishing
// (lua/room_editor.lua): a bar of buttons at the bottom, markers on wall
// segments for doors and windows, and a tray of items to place or buy.
// Placing itself happens on the map with direct touch; the game draws the
// items being placed.

import SwiftUI
import UIKit

struct EditorButton: Decodable, Hashable {
  var id: String
  var title: String?
  var symbol: String?
  var enabled: Bool
  var prominent: Bool
}

struct EditorMarker: Decodable, Hashable {
  var id: String
  var x: Double
  var y: Double
  // "wall", "door", "bad" (a door that can't go there), "window",
  // "door_fixed" (the door, shown in the windows stage; not tappable)
  var state: String
}

struct TrayPlaceRow: Decodable, Hashable, Identifiable {
  var index: Int
  var name: String
  var qty: Int
  var active: Bool
  var image: String?
  var id: Int { index }
}

struct TrayBuyRow: Decodable, Hashable, Identifiable {
  var index: Int
  var name: String
  var qty: Int
  var min: Int
  var cost: String
  var image: String?
  var id: Int { index }
}

struct EditorTray: Decodable, Hashable {
  var place: [TrayPlaceRow]?
  var buy: [TrayBuyRow]?
  var total: String?
  var buying: Bool
}

struct EditorState: Decodable {
  var title: String
  var hint: String?
  var logical: [Double]
  var markers: [EditorMarker]
  var buttons: [EditorButton]
  var tray: EditorTray?
}

final class EditorTrayModel: ObservableObject {
  @Published var tray: EditorTray?
}

final class EditorOverlay {
  private let container = PassthroughView()
  private let bar: UIVisualEffectView
  private let titleLabel = UILabel()
  private let hintLabel = UILabel()
  private let buttonRow = UIStackView()
  private var markerViews: [String: UIButton] = [:]
  private var state: EditorState?
  private let trayModel = EditorTrayModel()
  private let trayHost: UIHostingController<AnyView>
  private weak var parentController: UIViewController?

  init(in parent: UIViewController) {
    parentController = parent
    if #available(iOS 26.0, *) {
      bar = UIVisualEffectView(effect: UIGlassEffect())
    } else {
      bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    }
    trayHost = UIHostingController(rootView: AnyView(ItemTrayView().environmentObject(trayModel)))
    let view = parent.view!
    container.frame = view.bounds
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(container)

    // The tray, at the side.
    if #available(iOS 16.4, *) {
      trayHost.safeAreaRegions = []
    }
    parent.addChild(trayHost)
    let tray = trayHost.view!
    tray.translatesAutoresizingMaskIntoConstraints = false
    tray.layer.cornerRadius = 20
    tray.layer.cornerCurve = .continuous
    tray.clipsToBounds = true
    tray.isHidden = true
    container.addSubview(tray)
    trayHost.didMove(toParent: parent)

    // The bar.
    bar.overrideUserInterfaceStyle = .dark
    bar.layer.cornerRadius = 26
    bar.layer.cornerCurve = .continuous
    bar.clipsToBounds = true
    bar.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(bar)
    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    hintLabel.font = .systemFont(ofSize: 12)
    hintLabel.textColor = .secondaryLabel
    let labels = UIStackView(arrangedSubviews: [titleLabel, hintLabel])
    labels.axis = .vertical
    labels.spacing = 1
    buttonRow.axis = .horizontal
    buttonRow.spacing = 6
    buttonRow.alignment = .center
    let row = UIStackView(arrangedSubviews: [labels, buttonRow])
    row.axis = .horizontal
    row.spacing = 14
    row.alignment = .center
    row.translatesAutoresizingMaskIntoConstraints = false
    bar.contentView.addSubview(row)

    let guide = container.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      bar.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
      bar.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -10),
      bar.heightAnchor.constraint(equalToConstant: 52),
      bar.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -16),
      row.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 16),
      row.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -8),
      row.centerYAnchor.constraint(equalTo: bar.contentView.centerYAnchor),

      tray.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
      tray.topAnchor.constraint(equalTo: guide.topAnchor, constant: 58),
      tray.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),
      tray.widthAnchor.constraint(equalToConstant: 290),
    ])
  }

  func remove() {
    trayHost.willMove(toParent: nil)
    trayHost.view.removeFromSuperview()
    trayHost.removeFromParent()
    container.removeFromSuperview()
  }

  func update(_ new: EditorState) {
    let old = state
    state = new
    titleLabel.text = new.title
    hintLabel.text = new.hint
    hintLabel.isHidden = (new.hint ?? "").isEmpty
    if old?.buttons != new.buttons {
      rebuildButtons(new.buttons)
    }
    layoutMarkers()
    trayModel.tray = new.tray
    trayHost.view.isHidden = new.tray == nil
  }

  // MARK: Buttons

  private func rebuildButtons(_ buttons: [EditorButton]) {
    buttonRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
    // A full bar (placing: Rotate, Auto, Extras, Place, Done) doesn't fit a
    // phone with every title; the plain buttons then show just their symbol.
    let compact = buttons.count > 5
    for spec in buttons {
      var config: UIButton.Configuration = spec.prominent ? .borderedProminent() : .plain()
      config.title = compact && !spec.prominent && spec.symbol != nil ? nil : spec.title
      if let symbol = spec.symbol {
        config.image = UIImage(
          systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        config.imagePadding = 4
      }
      config.cornerStyle = .capsule
      config.buttonSize = .small
      if !spec.prominent {
        config.baseForegroundColor = spec.id == "cancel" ? .systemRed : .label
      }
      let b = UIButton(configuration: config)
      b.isEnabled = spec.enabled
      b.accessibilityLabel = spec.title ?? (spec.id == "cancel" ? "Cancel" : spec.id)
      let id = spec.id
      b.addAction(UIAction { _ in NativeUI.post("editor_button", ["id": id]) }, for: .touchUpInside)
      buttonRow.addArrangedSubview(b)
    }
  }

  // MARK: Markers (game pixels -> points, as SDL's logical scaling)

  private func toPoints(_ x: Double, _ y: Double) -> CGPoint {
    guard let state = state, state.logical.count == 2, state.logical[0] > 0, state.logical[1] > 0
    else { return .zero }
    let size = container.bounds.size
    let lw = CGFloat(state.logical[0])
    let lh = CGFloat(state.logical[1])
    let scale = min(size.width / lw, size.height / lh)
    return CGPoint(
      x: (size.width - lw * scale) / 2 + CGFloat(x) * scale,
      y: (size.height - lh * scale) / 2 + CGFloat(y) * scale)
  }

  private func layoutMarkers() {
    let markers = state?.markers ?? []
    let ids = Set(markers.map { $0.id })
    for (id, view) in markerViews where !ids.contains(id) {
      view.removeFromSuperview()
      markerViews[id] = nil
    }
    for marker in markers {
      let view = markerViews[marker.id] ?? makeMarker(id: marker.id)
      view.center = toPoints(marker.x, marker.y)
      style(view, state: marker.state)
    }
    // Keep the bar and tray above the markers.
    container.bringSubviewToFront(trayHost.view)
    container.bringSubviewToFront(bar)
  }

  private func makeMarker(id: String) -> UIButton {
    let b = UIButton(type: .custom)
    b.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
    b.layer.cornerRadius = 17
    b.layer.borderWidth = 2
    b.layer.borderColor = UIColor.white.cgColor
    b.layer.shadowColor = UIColor.black.cgColor
    b.layer.shadowOpacity = 0.3
    b.layer.shadowRadius = 2
    b.addAction(UIAction { _ in NativeUI.post("editor_marker", ["id": id]) }, for: .touchUpInside)
    b.accessibilityLabel = "Wall \(id)"
    markerViews[id] = b
    container.addSubview(b)
    return b
  }

  private func style(_ b: UIButton, state: String) {
    let symbol: String
    let colour: UIColor
    switch state {
    case "door", "door_fixed":
      symbol = "door.left.hand.open"
      colour = .systemGreen
    case "bad":
      symbol = "xmark"
      colour = .systemRed
    case "window":
      symbol = "window.vertical.closed"
      colour = .systemBlue
    default:
      symbol = "plus"
      colour = UIColor.black.withAlphaComponent(0.45)
    }
    b.backgroundColor = colour
    b.setImage(
      UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)),
      for: .normal)
    b.tintColor = .white
    b.adjustsImageWhenDisabled = false
    b.isEnabled = state != "door_fixed"
    b.accessibilityValue = state == "door_fixed" ? "door" : state
  }
}

// MARK: - The item tray

struct ItemTrayView: View {
  @EnvironmentObject var model: EditorTrayModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        if let tray = model.tray {
          if let place = tray.place {
            Text(place.isEmpty ? "Everything is placed" : "To place")
              .font(.headline)
            ForEach(place) { row in
              Button {
                NativeUI.post("editor_select", ["index": row.index])
              } label: {
                HStack(spacing: 10) {
                  GamePicture(path: row.image).frame(width: 44, height: 40)
                  VStack(alignment: .leading) {
                    Text(row.name).font(.subheadline.weight(.semibold))
                    if row.qty > 1 {
                      Text("\(row.qty) to place").font(.caption).foregroundStyle(.secondary)
                    }
                  }
                  Spacer()
                  if row.active {
                    Image(systemName: "hand.point.up.left.fill").foregroundStyle(.tint)
                  }
                }
                .padding(8)
                .background(
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(row.active ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground)))
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Place \(row.name)")
            }
          }
          if let buy = tray.buy {
            HStack {
              Text("Buy").font(.headline)
              Spacer()
              if let total = tray.total {
                Text(total).font(.subheadline.weight(.semibold)).monospacedDigit()
              }
            }
            ForEach(buy) { row in
              VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                  GamePicture(path: row.image).frame(width: 44, height: 40)
                  VStack(alignment: .leading) {
                    Text(row.name).font(.subheadline.weight(.semibold))
                    Text(row.cost).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                  }
                  Spacer(minLength: 0)
                }
                HStack {
                  Text(row.qty == 0 ? "None" : "\(row.qty)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(row.qty == 0 ? .secondary : .primary)
                  Spacer()
                  Stepper(
                    "",
                    value: Binding(
                      get: { row.qty },
                      set: { new in
                        NativeUI.post("editor_buy", ["index": row.index, "delta": new - row.qty])
                      }), in: row.min...99
                  )
                  .labelsHidden()
                  .accessibilityLabel("\(row.name), \(row.qty)")
                }
              }
              .padding(8)
              .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .fill(Color(uiColor: .secondarySystemBackground)))
            }
          }
        }
      }
      .padding(12)
    }
    .background(Color(uiColor: .systemBackground))
  }
}
