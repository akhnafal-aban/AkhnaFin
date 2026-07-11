//
//  DraftSummary.swift
//  AkhnaFin
//
//  Ringkasan satu-baris draft untuk dialog Siri/Shortcuts — dipakai
//  LogExpenseIntent & LogReceiptIntent (satu sumber).
//

import AkhnaFinCore
import ServiceInterfaces

enum DraftSummary {
    static func text(of draft: TransactionDraft) -> String {
        let amount = CurrencyFormatter.string(from: draft.amount, currencyCode: draft.currencyCode)
        let label = [draft.merchant, draft.note].first { !$0.isEmpty } ?? draft.categoryName
        return label.isEmpty ? amount : "\(amount) — \(label)"
    }
}
