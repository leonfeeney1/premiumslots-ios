import SwiftUI

// MARK: - Full terms of service, v5
// Native scrollable view rendering the COMPLETE terms of service
// from LegalText (templates/terms_of_service.html on the site).
// No web view, no outside link, no summary. Reachable from
// Settings (Legal section) and from Account (Your data section).
// NOTE: the terms page on the site carries the same body text as
// the privacy policy page (only the title differs). This screen
// shows that real text as it stands on the site; it does not
// invent different terms. See LegalText.swift.

struct FullTermsView: View {
    var body: some View {
        LegalDocumentView(document: LegalText.termsOfService) {
            NavigationLink {
                FullPrivacyPolicyView()
            } label: {
                Label("Read the privacy policy", systemImage: "hand.raised.fill")
                    .font(.psBody)
            }
        }
        .navigationTitle("Terms of service")
        .navigationBarTitleDisplayMode(.inline)
    }
}
