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
        container = AppContainer.make()
        dependencies = AppDependencies(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
        .modelContainer(container)
    }
}
