# Phase 5 Implementation Brief: Receipt Capture and On-Device OCR

## Scope

Phase 5 adds receipt capture from the Add Transaction flow, editable OCR review, receipt charge allocation, receipt attachment persistence, saved receipt management, Files import support, pending shared receipts, receipt-aware Transaction search/filtering, and quick-add widget routing. It preserves Phase 1-4 behavior.

## Schema and Migration

Phase 5 uses the existing production models:

- `Transaction.receipt`
- `ReceiptCapture`
- `ReceiptLineItem`
- externally stored `ReceiptCapture.imageData`

No production `@Model` properties were added, removed, renamed, or changed. The Phase 5 migration decision is no schema change. Existing Phase 4 stores open under the same `CanISchema` container, and Phase 5 receipt attachment is proven after reopening a Phase 4 store.

## OCR Architecture

Receipt OCR is isolated behind `ReceiptScanningService`. `VisionReceiptScanningService` performs Vision text recognition on-device and off the main actor, returns structured in-memory suggestions, supports cancellation, and never writes SwiftData. Tests and UI tests can inject deterministic fake scanner output.

OCR suggestions distinguish recognized lines, merchant, dates, totals, product line-item candidates, charge candidates, parsing warnings, and processed image data. OCR confidence is not persisted.

## Image Policy

Images are normalized before OCR and storage. The stored image is the edited result, not a duplicate original. The production policy caps the longest image dimension at 1600 px and stores JPEG at 0.78 compression quality.

Files import uses SwiftUI `fileImporter` for user-selected images and PDFs. The selected file is copied into app-controlled temporary storage while security-scoped access is active, then processed after access is stopped. JPEG, PNG, HEIC/HEIF and other system-decodable images use `UIImage(data:)`. PDFs use PDFKit; multi-page PDFs show page selection and scan one chosen page at a time. Unsupported, corrupt, empty, invalid-page, or unreadable files surface recoverable errors and persist nothing.

## Parsing Rules

Receipt parsing is separate from Vision and uses `Decimal` for money. It supports common Malaysian receipt formats, including `RM 12.30`, bare decimal values, comma thousands separators, discounts, and dates in `dd/MM/yyyy`, `dd-MM-yyyy`, and `yyyy-MM-dd`. Explicit total labels are preferred, while subtotal, tendered cash, change, tax, service charge, card, approval, phone, and unrelated number lines are excluded from total selection.

Tax, service charge, surcharge, delivery fee, packaging fee, gratuity/tip, and user-added charges are presented separately from purchased products. Charge classification is label-driven and intentionally conservative so ordinary purchased products are not classified as charges merely because their names contain ambiguous words. Each charge retains the reviewed name, original amount, applied amount, and OCR/manual source during review. Persisted applied charges are stored as reviewed `ReceiptLineItem` records with the original OCR wording retained in `rawText`.

Ambiguous or missing OCR output remains visibly reviewable; recognized text is never authoritative.

## Review and Save

Receipt capture begins in Add Transaction and defaults the draft to Expense. The user chooses Camera or Photo Library, reviews rotation/crop, runs OCR with progress and cancellation, reviews every suggestion, chooses Whole Receipt or Selected Items, and saves only through the ordinary Transaction confirmation.

Cancellation before final Save persists nothing. Saving atomically creates the Transaction, one ReceiptCapture, reviewed ReceiptLineItems, and inverse relationships.

Whole Receipt uses the reviewed receipt total as the Transaction amount. Printed receipt charges are shown as included and are not added again. Users may add an additional fixed or percentage tip on top of the reviewed receipt total.

Selected Items uses exact `Decimal` arithmetic for selected products, applied charges, and additional tips. Each charge can be excluded, included in full, included by percentage greater than 0 and at most 100, or divided equally by a positive whole-number divisor. Percentage and division round only the final applied charge to the active currency minor units using the existing formatter policy. Selected-mode transaction total is selected product subtotal plus included charges plus additional manual tip. Fixed and percentage tips are shown with their calculation base before save.

## Saved Receipts

Transactions with receipts show a compact attachment indicator. Transaction editing allows viewing saved receipt metadata and lines, replacing/rescanning without creating a second ReceiptCapture, and removing the receipt with confirmation while preserving the Transaction. Deleting a Transaction still cascades its receipt graph and explains that impact.

## Search and Filtering

Submitted Transaction search now includes receipt merchant, reviewed receipt line names, and raw recognized receipt text with the existing case- and diacritic-insensitive matching. The staged receipt filter supports All, Has Receipt, and No Receipt while preserving Apply, chips, Clear All, hierarchy, and tab-survival behavior.

## Shared Inbox and Quick Add

`SharedReceiptInboxService` provides the shared App Group inbox contract for the app and Share Extension: supported image/PDF validation, UUID filenames, versioned JSON manifest records, atomic temporary-file writes followed by moves, oversized-file rejection, unsupported-type rejection, pending receipt listing, explicit deletion, and incomplete temporary-file cleanup. It does not open or write SwiftData and does not run OCR.

`CanIReceiptShare` accepts only supported images and PDFs. It loads supported `NSItemProvider` attachments, saves each valid attachment independently into the App Group inbox, reports success/partial failure/failure, and completes or cancels the extension request without opening CanI automatically.

Pending Receipts are inspected on launch and foreground activation. The Budgets tab shows a nonintrusive entry only when pending records exist. The pending screen lists receipt type and import date, previews image/PDF content without OCR text, supports multi-page PDF page choice, allows Review Later, and deletes only after explicit confirmation or after a reviewed receipt is saved through the ordinary Transaction flow.

`QuickAddRoute`, `QuickAddRouteRouter`, and `WidgetDestinationSnapshotStore` provide WidgetKit routing support. Routes cover Add Expense and Scan Receipt with an optional destination UUID, encode no amounts, salary, merchant names, receipt text, or other financial data, and suppress duplicate route handling. The widget destination snapshot is a minimal read-only JSON file containing only Item UUID, Item name, Plan name, and update timestamp.

`CanIQuickAddWidgetExtension` supports system small, system medium, accessory circular, and accessory rectangular families. It uses WidgetKit links to open Add Expense or Scan Receipt and does not write SwiftData, run OCR, create Transactions, or display balances, amounts, salary, merchant names, or receipt details. Widget configuration currently exposes default action and a destination UUID string backed by the App Group snapshot contract; a richer picker UI can be layered on that snapshot without allowing the widget to open SwiftData.

The app root parses quick-add URLs centrally and emits coordinator navigation commands. UI tests inject the same URLs at launch to prove Add Expense opens the Transaction form and Scan Receipt opens the receipt source chooser. A production custom URL scheme registration must be confirmed in Xcode build settings before external widget taps can be certified outside launch injection.

## Privacy and Accessibility

Receipt images and OCR text remain on-device. Receipt contents are not logged, added to launch arguments, analytics, debug output, or error descriptions. The camera permission string states that the camera is used only when the user chooses to capture a receipt for on-device OCR.

Receipt acquisition, rotation, crop, product-line selection, charge allocation, subtotals, scan progress, and errors use explicit labels and do not expose the entire OCR output as a single uncontrolled VoiceOver block.
