import Cocoa

// MARK: - Slider Menu Item View

class SliderMenuView: NSView {
    var slider: NSSlider!
    var label: NSTextField!
    var onValueChanged: ((Float) -> Void)?

    init(title: String, minValue: Double, maxValue: Double, currentValue: Double, width: CGFloat = 220, onChange: @escaping (Float) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        onValueChanged = onChange

        label = NSTextField(labelWithString: title)
        label.font = NSFont.menuFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 5, width: 60, height: 20)
        addSubview(label)

        slider = NSSlider(value: currentValue, minValue: minValue, maxValue: maxValue, target: self, action: #selector(sliderChanged(_:)))
        slider.frame = NSRect(x: 80, y: 5, width: width - 100, height: 20)
        slider.isContinuous = true
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func sliderChanged(_ sender: NSSlider) {
        onValueChanged?(Float(sender.doubleValue))
    }
}
