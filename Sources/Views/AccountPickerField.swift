import SwiftUI

/// 口座選択ピッカー。親口座とその仮想口座を階層表示する。
struct AccountPickerField: View {
    @EnvironmentObject private var store: AppStore
    let title: String
    @Binding var selection: Int64?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("選択してください").tag(Int64?.none)
            ForEach(store.orderedAccounts, id: \.account.id) { entry in
                Text(entry.depth == 0 ? entry.account.name : "　└ \(entry.account.name)")
                    .tag(Int64?.some(entry.account.id ?? 0))
            }
        }
    }
}
