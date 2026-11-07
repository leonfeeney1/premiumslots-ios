import SwiftUI

// MARK: - Keyboard dismissal, v4
// Reusable tap-to-dismiss helper plus a Done button for the keyboard
// toolbar. Applied in the catalogue search, the platform detail and
// any other view in this batch that holds a text field. Every
// ScrollView, List and Form touched in this batch also uses
// .scrollDismissesKeyboard(.interactively).

extension View {
    /// Resigns the first responder, hiding the keyboard.
    static func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// Tapping an empty part of this view hides the keyboard.
    /// Apply it to a container around a text field, never on the
    /// field itself: a tap on the field would resign it again and
    /// the keyboard would close as soon as it opens. In the
    /// catalogue it goes on the results grid, not the search bar.
    func hideKeyboardOnTap() -> some View {
        onTapGesture { Self.hideKeyboard() }
    }

    /// Done button shown above the keyboard for text fields.
    /// Use inside .toolbar on the view that owns the field.
    @ToolbarContentBuilder var dismissKeyboardButton: some ToolbarContent {
        ToolbarItem(placement: .keyboard) {
            Button("Done") { Self.hideKeyboard() }
                .font(.psBody)
        }
    }
}
