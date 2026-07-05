//
//  My_RezekiKuApp.swift
//  My RezekiKu
//

import SwiftUI
import SwiftData

@main
struct My_RezekiKuApp: App {
    private let container: ModelContainer
    private let dependencies: AppDependencies

    init() {
        container = AppContainer.shared
        dependencies = AppContainer.dependencies
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
        .modelContainer(container)
    }
}
