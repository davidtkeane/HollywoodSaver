import Cocoa

// MARK: - Toggle Menu Item View

/// Custom NSView wrapper for a checkbox-style menu toggle. Because it's
/// assigned via `menuItem.view = self`, **clicks on this view do NOT dismiss
/// the enclosing menu** — users can flick multiple toggles on and off in a row
/// and watch the scene update live without the menu collapsing on them.
///
/// Mirrors the `SliderMenuView` pattern used for Volume / Opacity. Drop-in
/// replacement for any toggle where rapid comparison is valuable (backdrop
/// layers, Easter egg toggles, etc.).
///
/// Usage:
/// ```swift
/// let item = NSMenuItem()
/// item.view = ToggleMenuItemView(
///     title: "Background Stars",
///     isOn: Prefs.starfieldBackgroundStars
/// ) { newValue in
///     Prefs.starfieldBackgroundStars = newValue
/// }
/// menu.addItem(item)
/// ```
class ToggleMenuItemView: NSView {
    var checkbox: NSButton!
    var onToggle: ((Bool) -> Void)?

    init(title: String, isOn: Bool, width: CGFloat = 240, onToggle: @escaping (Bool) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        self.onToggle = onToggle

        checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggleClicked))
        checkbox.state = isOn ? .on : .off
        checkbox.font = NSFont.menuFont(ofSize: 13)
        checkbox.frame = NSRect(x: 20, y: 2, width: width - 30, height: 18)
        addSubview(checkbox)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleClicked() {
        onToggle?(checkbox.state == .on)
    }
}
