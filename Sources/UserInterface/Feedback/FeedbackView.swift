// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FeedbackView: View {
    @Binding var urlString: String
    @ObservedObject var viewModel: FeedbackViewModel
    @State private var isShowingFileImporter: Bool = false
    private let maxDescriptionLength = 4096
    
    var onPrivacyPolicyTap: (() -> Void)?
    var onTermsOfServiceTap: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSend: (() -> Void)?

    private let attachmentRowHeight: CGFloat = 22
    private let attachmentRowSpacing: CGFloat = 6
    private let attachmentScrollIndicatorInset: CGFloat = 16
    private let maxVisibleAttachmentRows = 4

    private var attachmentListHeight: CGFloat {
        let count = CGFloat(min(viewModel.attachments.count, maxVisibleAttachmentRows))
        guard count > 0 else { return 0 }
        return count * attachmentRowHeight + max(0, count - 1) * attachmentRowSpacing
    }

    private var shouldScrollAttachments: Bool {
        viewModel.attachments.count > maxVisibleAttachmentRows
    }
    
    private var legalText: AttributedString {
        var string = AttributedString(NSLocalizedString("Some account and system information may be sent to Phinomenon. We will use the information you give us to help address technical issues and to improve our services, subject to our Privacy Policy and Terms of Service.", comment: "Feedback form - Legal disclaimer text explaining data usage, contains links to Privacy Policy and Terms of Service"))
        
        if let range = string.range(of: "Privacy Policy") {
            string[range].link = URL(string: "privacy")
            string[range].underlineStyle = .single
        }
        
        if let range = string.range(of: "Terms of Service") {
            string[range].link = URL(string: "terms")
            string[range].underlineStyle = .single
        }
        
        return string
    }
    
    init(viewModel: FeedbackViewModel,
         onPrivacyPolicyTap: (() -> Void)? = nil,
         onTermsOfServiceTap: (() -> Void)? = nil,
         onCancel: (() -> Void)? = nil,
         onSend: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self._urlString = Binding(
            get: { viewModel.urlString },
            set: { viewModel.urlString = $0 }
        )
        self.onPrivacyPolicyTap = onPrivacyPolicyTap
        self.onTermsOfServiceTap = onTermsOfServiceTap
        self.onCancel = onCancel
        self.onSend = onSend
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                HStack {
                    Text(NSLocalizedString("Describe the issue in detail", comment: "Feedback form - Label prompting user to describe the issue"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                Spacer()
                    .frame(height: 16)
                
                TextEditor(text: $viewModel.descriptionText)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .frame(height: 144)
                    .padding(4)
                    .background(Color(NSColor.black.withAlphaComponent(0.02)))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .onChange(of: viewModel.descriptionText, { oldValue, newValue in
                        if newValue.count > maxDescriptionLength {
                            viewModel.descriptionText = String(newValue.prefix(maxDescriptionLength))
                        }
                    })
                
                if viewModel.descriptionText.count >= 3000 {
                    Spacer()
                        .frame(height: 5)
                    
                    Text("\(viewModel.descriptionText.count)/\(maxDescriptionLength)")
                        .font(.caption)
                        .foregroundStyle(viewModel.descriptionText.count >= maxDescriptionLength ? .red : .yellow)
                }
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("Additional info (optional)", comment: "Feedback form - Section header for optional additional information"))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 11) {
                    HStack {
                        Text(NSLocalizedString("URL", comment: "Feedback form - Label for URL input field"))
                            .foregroundColor(.primary)
                        Spacer()
                        TextField("URL", text: $urlString)
                            .textFieldStyle(.plain)
                            .focusEffectDisabled()
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Divider()
                    
                    attachmentPickerRow

                    if !viewModel.attachments.isEmpty {
                        Divider()
                        if shouldScrollAttachments {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    attachmentList(trailingInset: attachmentScrollIndicatorInset)
                                }
                                .frame(height: attachmentListHeight)
                                .onAppear {
                                    scrollToLastAttachment(proxy)
                                }
                                .onChange(of: viewModel.attachments.count, { _, _ in
                                    scrollToLastAttachment(proxy)
                                })
                            }
                        } else {
                            attachmentList()
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.black.withAlphaComponent(0.02)))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .padding(.top, 24)
            
            VStack {
                Spacer()
                    .frame(height: 24)
                
                Text(legalText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.absoluteString == "privacy" {
                            openPrivacyPolicy()
                            return .handled
                        } else if url.absoluteString == "terms" {
                            openTermsOfService()
                            return .handled
                        }
                        return .discarded
                    })
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button(NSLocalizedString("Cancel", comment: "Feedback form - Cancel button to dismiss feedback form")) {
                        onCancel?()
                    }
                    .buttonStyle(CancelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    
                    Button(NSLocalizedString("Send", comment: "Feedback form - Send button to submit feedback")) {
                        guard viewModel.canSend else {
                            onCancel?()
                            return
                        }
                        onSend?()
                    }
                    .disabled(!viewModel.canSend)
                    .buttonStyle(SendButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    Spacer()
                }
//                .padding(.top, 2)
            }
//            .debugBorder()
        }
        .padding(36)
        .frame(width: 520)
        .background(FeedbackPasteImageMonitor { image in
            viewModel.addPastedImage(image)
        })
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.addFileURLs(urls)
            case .failure(let error):
                AppLogError("File selection error: \(error.localizedDescription)")
            }
        }
        .alert(
            NSLocalizedString("Could Not Save Feedback", comment: "Feedback form - Alert title when local outbox save fails"),
            isPresented: Binding(
                get: { viewModel.localSaveError != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.localSaveError = nil
                    }
                }
            )
        ) {
            Button(NSLocalizedString("OK", comment: "Generic - OK button to dismiss an alert"), role: .cancel) { }
        } message: {
            Text(viewModel.localSaveError ?? "")
        }
        .alert(
            NSLocalizedString("Could Not Add Attachment", comment: "Feedback form - Alert title when selected attachments cannot be added"),
            isPresented: Binding(
                get: { viewModel.attachmentError != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.attachmentError = nil
                    }
                }
            )
        ) {
            Button(NSLocalizedString("OK", comment: "Generic - OK button to dismiss an alert"), role: .cancel) { }
        } message: {
            Text(viewModel.attachmentError ?? "")
        }
    }

    private var attachmentPickerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("Attach files", comment: "Feedback form - Label for file attachment section"))
                    .foregroundStyle(.primary)

                Text(NSLocalizedString("Or paste an image", comment: "Feedback form - Hint explaining pasted images can be added as attachments"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {
                isShowingFileImporter = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text(NSLocalizedString("Choose Files", comment: "Feedback form - Button to open file picker for attachments"))
                }
            }
        }
    }

    private func attachmentList(trailingInset: CGFloat = 0) -> some View {
        VStack(spacing: attachmentRowSpacing) {
            ForEach(viewModel.attachments) { attachment in
                FeedbackAttachmentRow(attachment: attachment) {
                    viewModel.removeAttachment(id: attachment.id)
                }
                .padding(.trailing, trailingInset)
                .frame(height: attachmentRowHeight)
                .id(attachment.id)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scrollToLastAttachment(_ proxy: ScrollViewProxy) {
        guard let lastID = viewModel.attachments.last?.id else {
            return
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
    
    private func openPrivacyPolicy() {
        onPrivacyPolicyTap?()
    }
    
    private func openTermsOfService() {
        onTermsOfServiceTap?()
    }
}

private struct FeedbackAttachmentRow: View {
    let attachment: FeedbackDraftAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.kind == .image ? "photo" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(attachment.filename)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("Remove attachment", comment: "Feedback form - Tooltip for removing an attachment"))
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity)
    }
}

private struct FeedbackPasteImageMonitor: NSViewRepresentable {
    let onPasteImage: (NSImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPasteImage: onPasteImage)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.installIfNeeded()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
    }

    final class Coordinator {
        weak var view: NSView?
        private var monitor: Any?
        private let onPasteImage: (NSImage) -> Void

        init(onPasteImage: @escaping (NSImage) -> Void) {
            self.onPasteImage = onPasteImage
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.isCommandPaste(event),
                      event.window === self.view?.window,
                      let image = NSImage(pasteboard: .general) else {
                    return event
                }
                onPasteImage(image)
                return nil
            }
        }

        private func isCommandPaste(_ event: NSEvent) -> Bool {
            event.charactersIgnoringModifiers?.lowercased() == "v" &&
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        }
    }
}

struct CancelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .frame(width: 110, height: 28)
            .background(Color(NSColor.controlBackgroundColor))
            .foregroundColor(.primary)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .frame(width: 110, height: 28)
            .background(isEnabled ? Color.blue : Color.gray.opacity(0.5))
            .foregroundColor(.white)
            .cornerRadius(5)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

#Preview {
    FeedbackView(viewModel: FeedbackViewModel())
}
