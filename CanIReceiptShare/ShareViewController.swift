//
//  ShareViewController.swift
//  CanIReceiptShare
//
//  Created by Ramon Jr Bahio on 8/31/26.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var didStartImport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartImport else { return }
        didStartImport = true
        Task { await importSharedReceipts() }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        statusLabel.text = "Saving receipt to CanI..."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.font = .preferredFont(forTextStyle: .body)

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.isHidden = true
        doneButton.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }, for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: SharedReceiptInboxError.unreadable)
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [statusLabel, doneButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func importSharedReceipts() async {
        do {
            let inboxURL = try SharedReceiptInboxLocator().inboxURL()
            let inbox = SharedReceiptInboxService(inboxURL: inboxURL)
            let providers = extensionContext?.inputItems
                .compactMap { $0 as? NSExtensionItem }
                .flatMap { $0.attachments ?? [] } ?? []
            var savedCount = 0
            var failedCount = 0

            for provider in providers {
                do {
                    let imported = try await loadSupportedAttachment(from: provider)
                    _ = try await inbox.savePendingReceipt(
                        data: imported.data,
                        originalExtension: imported.filenameExtension,
                        contentType: imported.contentType
                    )
                    savedCount += 1
                } catch {
                    failedCount += 1
                }
            }

            await MainActor.run {
                if savedCount > 0, failedCount == 0 {
                    statusLabel.text = "Saved to CanI. Open CanI to review and create the transaction."
                } else if savedCount > 0 {
                    statusLabel.text = "Saved \(savedCount) to CanI. \(failedCount) could not be saved. Open CanI to review and create the transaction."
                } else {
                    statusLabel.text = "No supported receipt image or PDF could be saved."
                }
                doneButton.isHidden = false
                cancelButton.isHidden = true
            }
        } catch {
            await MainActor.run {
                statusLabel.text = "The receipt could not be saved to CanI."
                doneButton.isHidden = false
                cancelButton.isHidden = true
            }
        }
    }

    private func loadSupportedAttachment(from provider: NSItemProvider) async throws -> ImportedReceiptAttachment {
        for type in SharedReceiptContentType.supported {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                    do {
                        guard let url else { throw SharedReceiptInboxError.unreadable }
                        let didAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if didAccess { url.stopAccessingSecurityScopedResource() }
                        }
                        let data = try Data(contentsOf: url)
                        let fileExtension = url.pathExtension.isEmpty ? SharedReceiptContentType.fileExtension(for: type.identifier) : url.pathExtension
                        continuation.resume(returning: ImportedReceiptAttachment(data: data, filenameExtension: fileExtension, contentType: type.identifier))
                    } catch {
                        continuation.resume(throwing: SharedReceiptInboxError.unreadable)
                    }
                }
            }
        }
        throw SharedReceiptInboxError.unsupportedType
    }
}

private struct ImportedReceiptAttachment {
    var data: Data
    var filenameExtension: String
    var contentType: String
}
