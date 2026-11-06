import AppKit
let destination=CommandLine.arguments[1]
let image=NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
NSColor(calibratedRed:0.025,green:0.03,blue:0.045,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:40,y:40,width:944,height:944),xRadius:210,yRadius:210).fill()
let red=NSColor(calibratedRed:0.83,green:0.075,blue:0.13,alpha:1)
red.setStroke()
let border=NSBezierPath(roundedRect:NSRect(x:92,y:92,width:840,height:840),xRadius:150,yRadius:150);border.lineWidth=12;border.stroke()
red.setFill()
NSBezierPath(rect:NSRect(x:104,y:190,width:24,height:610)).fill()
let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:475,weight:.medium),.foregroundColor:NSColor(calibratedRed:0.96,green:0.22,blue:0.15,alpha:1)]
let text="02" as NSString;let size=text.size(withAttributes:attrs);text.draw(at:NSPoint(x:(1024-size.width)/2+10,y:284),withAttributes:attrs)
let label="E V A" as NSString
let labelAttrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:65,weight:.medium),.foregroundColor:NSColor(calibratedRed:0.94,green:0.79,blue:0.63,alpha:1)]
let labelSize=label.size(withAttributes:labelAttrs);label.draw(at:NSPoint(x:(1024-labelSize.width)/2,y:192),withAttributes:labelAttrs)
NSColor(calibratedRed:1,green:0.48,blue:0.14,alpha:1).setFill()
for i in 0..<8 {let x=Double(260+i*64);let p=NSBezierPath();p.move(to:NSPoint(x:x,y:812));p.line(to:NSPoint(x:x+32,y:812));p.line(to:NSPoint(x:x+50,y:840));p.line(to:NSPoint(x:x+18,y:840));p.close();p.fill()}
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination))
