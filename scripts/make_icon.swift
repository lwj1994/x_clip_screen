import AppKit

// 宿主自己的图标；不使用 QQ 的品牌图标。
let output = URL(fileURLWithPath:CommandLine.arguments[1], isDirectory:true)
try FileManager.default.createDirectory(at:output, withIntermediateDirectories:true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size:NSSize(width:pixels, height:pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by:factor); transform.concat()
        let tile = NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:210,yRadius:210)
        let gradient = NSGradient(starting:NSColor(calibratedRed:0.08,green:0.84,blue:0.78,alpha:1),
                                  ending:NSColor(calibratedRed:0.01,green:0.40,blue:0.65,alpha:1))!
        gradient.draw(in:tile, angle:-60)
        NSColor.white.setStroke()
        let viewfinder = NSBezierPath(); viewfinder.lineWidth = 53; viewfinder.lineCapStyle = .round; viewfinder.lineJoinStyle = .round
        for (x,y,sx,sy) in [(CGFloat(268),CGFloat(268),CGFloat(1),CGFloat(1)), (756,268,-1,1), (268,756,1,-1), (756,756,-1,-1)] {
            viewfinder.move(to:NSPoint(x:x,y:y+sy*116)); viewfinder.line(to:NSPoint(x:x,y:y+sy*33))
            viewfinder.curve(to:NSPoint(x:x+sx*33,y:y), controlPoint1:NSPoint(x:x,y:y+sy*10), controlPoint2:NSPoint(x:x+sx*10,y:y))
            viewfinder.line(to:NSPoint(x:x+sx*116,y:y))
        }
        viewfinder.stroke()
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect:NSRect(x:452,y:452,width:120,height:120),xRadius:34,yRadius:34).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using:.png, properties:[:])!.write(to:output.appendingPathComponent(filename))
    }
}
