import CoreGraphics
import CoreText
import Foundation
import WalletDomain

/// Native paginated PDF generation works on iOS and macOS without a network service.
enum ReportPDF {
    static func data(for report: FinancialReport) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { throw CocoaError(.fileWriteUnknown) }
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw CocoaError(.fileWriteUnknown) }
        var pageNumber = 0
        var y: CGFloat = 0
        func draw(_ text: String, size: CGFloat, at top: CGFloat, bold: Bool = false) -> CGFloat {
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
            let string = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(string)
            let height = ceil(CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil,
                CGSize(width: 499, height: CGFloat.greatestFiniteMagnitude), nil).height) + 4
            let path = CGPath(rect: CGRect(x: 48, y: 842 - top - height, width: 499, height: height), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            return height
        }
        func startPage() {
            if pageNumber > 0 { context.endPDFPage() }
            pageNumber += 1
            context.beginPDFPage(nil)
            _ = draw("MY WALLET  /  FINANCIAL REPORT", size: 9, at: 30, bold: true)
            _ = draw("Page \(pageNumber)", size: 9, at: 806)
            y = 64
        }
        func line(_ text: String, size: CGFloat = 11, bold: Bool = false) {
            for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
                let attributed = NSAttributedString(string: String(paragraph), attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)
                ])
                let framesetter = CTFramesetterCreateWithAttributedString(attributed)
                var offset = 0
                while offset < attributed.length {
                    let remaining = CFRange(location: offset, length: attributed.length - offset)
                    let height = ceil(CTFramesetterSuggestFrameSizeWithConstraints(framesetter, remaining, nil,
                        CGSize(width: 499, height: CGFloat.greatestFiniteMagnitude), nil).height) + 4
                    if y > 745 || (height < 716 && y + height > 780) { startPage() }
                    let available = min(height, 780 - y)
                    let path = CGPath(rect: CGRect(x: 48, y: 842 - y - available, width: 499, height: available), transform: nil)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                    let visible = CTFrameGetVisibleStringRange(frame)
                    guard visible.length > 0 else { break }
                    context.saveGState()
                    context.textMatrix = .identity
                    CTFrameDraw(frame, context)
                    context.restoreGState()
                    offset += visible.length
                    y += available + 7
                    if offset < attributed.length { startPage() }
                }
                if attributed.length == 0 { y += 7 }
            }
        }
        startPage()
        line(report.title, size: 22, bold: true)
        line(report.subtitle, size: 10)
        for section in report.sections {
            if y > 620 { startPage() }
            y += 12
            line(section.title, size: 14, bold: true)
            for text in section.lines { line(text) }
        }
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }
}
