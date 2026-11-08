import SwiftUI

/// A popup whose list opens on the button's own edges, with the chosen item over the label. AppKit's
/// own lines the chosen item's text up on the label's, so its checkmark column pushed the list left
/// of the button, and SwiftUI's pull-down opened one narrower than the button.
struct PopUp: NSViewRepresentable {
    let items: [String]
    let selected: Int
    let pick: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = EdgePopUpButton(frame: .zero, pullsDown: false)
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.pick = pick
        // Into the menu directly: addItem(withTitle:) drops an item whose title is already there.
        let menu = button.menu!
        menu.removeAllItems()
        for (i, item) in items.enumerated() {
            let menuItem = NSMenuItem(title: item, action: #selector(Coordinator.picked(_:)), keyEquivalent: "")
            menuItem.target = context.coordinator
            menuItem.tag = i
            menu.addItem(menuItem)
        }
        button.selectItem(at: selected)
    }

    final class Coordinator: NSObject {
        var pick: (Int) -> Void = { _ in }
        @objc func picked(_ item: NSMenuItem) { pick(item.tag) }
    }
}

final class EdgePopUpButton: NSPopUpButton {
    override func mouseDown(with event: NSEvent) {
        guard let menu, isEnabled else { return }
        menu.minimumWidth = bounds.width
        for item in menu.items { item.state = item == selectedItem ? .on : .off }
        // The chosen item's top-left on the button's: the list's edges are then the button's.
        let top = isFlipped ? bounds.minY : bounds.maxY
        menu.popUp(positioning: selectedItem, at: NSPoint(x: bounds.minX, y: top), in: self)
    }
}
