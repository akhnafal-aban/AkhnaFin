//
//  RootView.swift
//  AkhnaFin
//
//  UI dibangun ulang dari nol: hanya TabView, tiap tab placeholder kosong.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "chart.pie") {
                DashboardView()
            }
            Tab("Transaksi", systemImage: "list.bullet.rectangle") {
                TransactionListView()
            }
            Tab("Pengaturan", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}