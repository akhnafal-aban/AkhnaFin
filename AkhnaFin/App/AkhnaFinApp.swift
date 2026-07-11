//
//  AkhnaFinApp.swift
//  AkhnaFin
//

import SwiftUI
import SwiftData

@main
struct AkhnaFinApp: App {
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
