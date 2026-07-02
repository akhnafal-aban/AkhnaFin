import Foundation
import SwiftData
import RezekiCore

/// Seed kategori bawaan — idempotent: hanya berjalan bila store belum punya kategori sama sekali.
public enum CategorySeeder {
    public static func seedIfNeeded(context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<TransactionCategory>()) == 0 else { return }

        let mainFood  = TransactionCategory(name: "Main Food", iconName: "fork.knife", colorHex: "#F97316", kind: .expense, isBuiltIn: true)
        let lifestyle = TransactionCategory(name: "Lifestyle", iconName: "sparkles", colorHex: "#8B5CF6", kind: .expense, isBuiltIn: true)
        let tagihan   = TransactionCategory(name: "Tagihan", iconName: "doc.text", colorHex: "#EF4444", kind: .expense, isBuiltIn: true)
        let transport = TransactionCategory(name: "Transport", iconName: "car", colorHex: "#3B82F6", kind: .expense, isBuiltIn: true)
        let kesehatan = TransactionCategory(name: "Kesehatan", iconName: "cross.case", colorHex: "#10B981", kind: .expense, isBuiltIn: true)
        let gaji      = TransactionCategory(name: "Gaji", iconName: "banknote", colorHex: "#22C55E", kind: .income, isBuiltIn: true)
        let bonus     = TransactionCategory(name: "Bonus", iconName: "gift", colorHex: "#EAB308", kind: .income, isBuiltIn: true)

        let jajan    = TransactionCategory(name: "Jajan", iconName: "takeoutbag.and.cup.and.straw", colorHex: "#A78BFA", kind: .expense, isBuiltIn: true, parent: lifestyle)
        let hiburan  = TransactionCategory(name: "Hiburan", iconName: "gamecontroller", colorHex: "#C084FC", kind: .expense, isBuiltIn: true, parent: lifestyle)
        let olahraga = TransactionCategory(name: "Olahraga", iconName: "figure.run", colorHex: "#7C3AED", kind: .expense, isBuiltIn: true, parent: lifestyle)

        let all = [mainFood, lifestyle, tagihan, transport, kesehatan, gaji, bonus, jajan, hiburan, olahraga]
        for category in all {
            context.insert(category)
        }
        try context.save()
    }
}
