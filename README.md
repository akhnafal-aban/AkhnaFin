<!-- AkhnaFin — personal finance iOS app. Facts below; no marketing. -->

# AkhnaFin

Personal finance iOS app built around one problem: logging expenses is tedious, so it does not happen. AkhnaFin makes capture nearly frictionless — every input path funnels into a single pipeline, and every result is an editable draft you confirm before anything is saved.

## Input paths

- **Siri / App Intents** — log an expense without opening the app
- **Natural language** — type or dictate "kopi 25rb tadi pagi"; parsed on-device via Foundation Models
- **Voice** — speech transcription through the Speech framework
- **Receipt photos** — text extraction via the Vision framework
- **Manual / batch entry**

All paths converge on one pipeline:

```
input (text/voice/image) → TransactionParsing → TransactionDraft (editable)
    → user confirmation → TransactionRepository.commit() → SwiftData + CloudKit
```

Nothing is committed without an explicit confirm. AI output always lands as a draft first.

## Architecture

Logic lives in a local Swift package; the app target owns UI and composition only.

```
AkhnaFin/                 app target — all UI, DI, composition root
  App/                    ModelContainer (CloudKit → local-only fallback, seeding)
  DesignSystem/           AmountField, CategoryPicker, TransactionRow
  Features/              one folder per feature (Transactions, …)
  Intents/               App Intents (app-bundle requirement)

Packages/AkhnaFinKit/     logic only — every target has a test target
  AkhnaFinCore           @Model types, enums, formatters, grouping
  ServiceInterfaces      draft models + protocols (parsing, speech, receipts) + mocks
  Persistence            container factory, category seeding, repository
  Services               concrete implementations (FoundationModelsParser, …)
```

## Running it

Requires Xcode with an iOS simulator runtime. The SwiftData macro plugin needs the full Xcode toolchain:

```bash
# Logic tests (fastest validation — seconds, no simulator)
cd Packages/AkhnaFinKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Build the app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AkhnaFin.xcodeproj -scheme AkhnaFin \
  -destination 'generic/platform=iOS Simulator' build
```

## Tech

Swift, SwiftUI, SwiftData + CloudKit, App Intents, Foundation Models, Speech, Vision, Swift Testing.

MIT license. Development notes and session docs live in `Docs/`.
