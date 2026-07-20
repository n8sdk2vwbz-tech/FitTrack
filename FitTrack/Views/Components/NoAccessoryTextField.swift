import SwiftUI
import UIKit

/// Eigene `UITextField`-Einbindung mit explizit unterdrückter
/// Tastatur-Zubehörleiste (`inputAccessoryView = nil`). SwiftUIs normales
/// `TextField` mit `.keyboardType(.numberPad/.decimalPad)` hat in dieser App
/// wiederholt (über mehrere grundverschiedene Lösungsversuche hinweg - eigener
/// Navigationsleisten-Button, eigene Tastatur-Zubehörleiste) eine zusätzliche,
/// irgendwann nicht mehr reagierende "Fertig"-Leiste über der Tastatur gezeigt.
/// Das deutet auf eine systemseitige Leiste hin, auf die SwiftUIs `.toolbar`-API
/// keinerlei Einfluss hat - nur der direkte Zugriff auf `UITextField` erlaubt,
/// sie zuverlässig zu unterbinden.
struct NoAccessoryTextField: UIViewRepresentable {
    @Binding var text: String
    var keyboardType: UIKeyboardType
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = keyboardType
        textField.textAlignment = .center
        textField.inputAccessoryView = nil
        textField.borderStyle = .roundedRect
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Nur überschreiben, wenn sich der Wert von außen geändert hat (z.B.
        // +/- Button) - sonst würde jede Neuzeichnung während des Tippens den
        // Cursor zurücksetzen.
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NoAccessoryTextField

        init(_ parent: NoAccessoryTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onEditingChanged(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEditingChanged(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
