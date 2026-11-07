import SwiftUI

// MARK: - Full privacy policy, v5
// Native scrollable view rendering the COMPLETE privacy policy
// from LegalText (templates/privacy_policy.html on the site).
// No web view, no outside link, no summary. Reachable from
// Settings (Legal section) and from Account (Your data section).

struct FullPrivacyPolicyView: View {
    var body: some View {
        LegalDocumentView(document: LegalText.privacyPolicy) {
            NavigationLink {
                FullTermsView()
            } label: {
                Label("Read the terms of service", systemImage: "doc.plaintext.fill")
                    .font(.psBody)
            }
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared native legal document renderer

struct LegalDocumentView<Footer: View>: View {
    let document: LegalDocument
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(document.title)
                    .font(.psTitle)
                Text("Effective Date: \(document.effectiveDate)")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                ForEach(document.sections.indices, id: \.self) { index in
                    let section = document.sections[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.heading)
                            .font(.psHeadline)
                            .padding(.top, 8)
                        ForEach(section.blocks.indices, id: \.self) { blockIndex in
                            switch section.blocks[blockIndex] {
                            case .paragraph(let text):
                                Text(text)
                                    .font(.psBody)
                                    .foregroundStyle(.psMuted)
                            case .bullet(let text):
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .font(.psBody)
                                        .foregroundStyle(.psMuted)
                                        .accessibilityHidden(true)
                                    Text(text)
                                        .font(.psBody)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                        }
                    }
                }
                Divider()
                    .padding(.top, 8)
                footer()
                Text("Full text from the \(document.title.lowercased()) page on premiumslots.tech, effective \(document.effectiveDate).")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            .psScreenPadding()
        }
        .scrollIndicators(.hidden)
        .background(Color.psBackground)
    }
}
