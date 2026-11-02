import AppKit

let path = CommandLine.arguments[1]
let names = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
let configuration = NSImage.SymbolConfiguration(textStyle: .body)
for name in names {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { continue }
    let ratio = image.size.width / image.size.height
    print(String(format: "SYMBOL %@ %.1f %.1f %.2f", name, image.size.width, image.size.height, ratio))
}
