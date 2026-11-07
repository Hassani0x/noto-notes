import SwiftUI
import UIKit

@MainActor final class TextBridge: ObservableObject {
    weak var view: UITextView?
    func replace(_ range: NSRange, with replacement: String) {
        guard let view, let start = view.position(from: view.beginningOfDocument, offset: range.location),
              let end = view.position(from: start, offset: range.length),
              let selection = view.textRange(from: start, to: end) else { return }
        view.selectedTextRange = selection
        view.insertText(replacement)
    }
    func prefix(_ prefix: String) {
        guard let view else {return}
        let range = (view.text as NSString).paragraphRange(for: view.selectedRange)
        replace(NSRange(location: range.location,length: 0), with: prefix)
    }
}

struct BodyEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let spell: Bool
    let highlights: [NSRange]
    let bridge: TextBridge
    let onRewrite: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.backgroundColor = .clear
        v.textColor = .label
        v.font = UIFont.preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.textContainerInset = UIEdgeInsets(top: 8,left: 20,bottom: 20,right: 20)
        v.accessibilityLabel = "Note body"
        v.accessibilityIdentifier = "body"
        v.textAlignment = .natural
        v.text = text
        bridge.view = v
        v.delegate = context.coordinator
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.parent = self
        if v.text != text && v.markedTextRange == nil { v.text = text }
        Self.configureSpelling(v, enabled: spell)
        if context.coordinator.decorations != highlights {
            v.textStorage.removeAttribute(.backgroundColor, range: NSRange(location:0,length:v.text.utf16.count))
            for range in highlights where NSMaxRange(range) <= v.text.utf16.count {
                v.textStorage.addAttribute(.backgroundColor,value: UIColor(Color.sage).withAlphaComponent(0.15),range: range)
            }
            context.coordinator.decorations = highlights
        }
    }
    static func configureSpelling(_ view: UITextView, enabled: Bool) {
        view.spellCheckingType = enabled ? .yes : .no
        view.autocorrectionType = enabled ? .yes : .no
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BodyEditor
        var decorations = [NSRange]()
        init(_ parent: BodyEditor) {self.parent = parent}
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidChangeSelection(_ textView: UITextView) { parent.selection = textView.selectedRange }
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return nil }
            return UIMenu(children: suggestedActions + [UIAction(title:"Rewrite selection",image:UIImage(systemName:"pencil.line")) { [weak self] _ in self?.parent.onRewrite() }])
        }
    }
}
