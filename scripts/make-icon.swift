import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

for (size, scale) in sizes {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    let paper = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 190, yRadius: 190)
    NSColor(white: 0.09, alpha: 1).setFill()
    paper.fill()
    NSShadow().set()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let font = NSFont.systemFont(ofSize: 710, weight: .light)
    ("d" as NSString).draw(in: NSRect(x: 76, y: 77, width: 872, height: 860), withAttributes: [
        .font: font,
        .foregroundColor: NSColor(white: 0.72, alpha: 1),
        .paragraphStyle: paragraph
    ])
    image.unlockFocus()

    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    let suffix = scale == 2 ? "@2x" : ""
    try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
}
