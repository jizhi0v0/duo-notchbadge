// 画 app 图标(1024 PNG)。主题:刘海下用吊线挂着一个带红角标的 app。
import AppKit

let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
func C(_ r: CGFloat,_ g: CGFloat,_ b: CGFloat,_ a: CGFloat = 1) -> NSColor { NSColor(srgbRed:r/255,green:g/255,blue:b/255,alpha:a) }

ctx.saveGState()
NSBezierPath(roundedRect: NSRect(x:0,y:0,width:S,height:S), xRadius:229, yRadius:229).addClip()
NSGradient(colors:[C(48,53,82), C(13,15,26)])!.draw(in: NSRect(x:0,y:0,width:S,height:S), angle:-90)
ctx.restoreGState()

let nw: CGFloat = 520, nh: CGFloat = 176, br: CGFloat = 86
let nx = (S-nw)/2, nbot = S-nh
let notch = NSBezierPath()
notch.move(to: NSPoint(x:nx, y:S))
notch.line(to: NSPoint(x:nx, y:nbot+br))
notch.appendArc(withCenter: NSPoint(x:nx+br, y:nbot+br), radius:br, startAngle:180, endAngle:270)
notch.line(to: NSPoint(x:nx+nw-br, y:nbot))
notch.appendArc(withCenter: NSPoint(x:nx+nw-br, y:nbot+br), radius:br, startAngle:270, endAngle:360)
notch.line(to: NSPoint(x:nx+nw, y:S)); notch.close()
C(0,0,0).setFill(); notch.fill()

let cx = S/2, tTop = nbot, tLen: CGFloat = 150
let thread = NSBezierPath(); thread.lineWidth = 11
C(255,255,255,0.5).setStroke()
thread.move(to: NSPoint(x:cx, y:tTop)); thread.line(to: NSPoint(x:cx, y:tTop-tLen)); thread.stroke()

let gw: CGFloat = 380, gx = cx-gw/2, gy = tTop-tLen-gw
ctx.saveGState()
NSBezierPath(roundedRect: NSRect(x:gx,y:gy,width:gw,height:gw), xRadius:90, yRadius:90).addClip()
NSGradient(colors:[C(92,176,255), C(36,108,240)])!.draw(in: NSRect(x:gx,y:gy,width:gw,height:gw), angle:-90)
C(255,255,255,0.18).setFill()
NSBezierPath(ovalIn: NSRect(x:gx-60, y:gy+gw*0.42, width:gw+120, height:gw*0.9)).fill()
ctx.restoreGState()

let bd: CGFloat = 168, bx = gx+gw-bd*0.66, by = gy+gw-bd*0.66
C(13,15,26).setFill(); NSBezierPath(ovalIn: NSRect(x:bx-14,y:by-14,width:bd+28,height:bd+28)).fill()
C(255,69,58).setFill(); NSBezierPath(ovalIn: NSRect(x:bx,y:by,width:bd,height:bd)).fill()
C(255,255,255).setFill()
NSBezierPath(ovalIn: NSRect(x:bx+bd/2-26, y:by+bd/2-26, width:52, height:52)).fill()

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon1024.png"
try! rep.representation(using:.png, properties:[:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
