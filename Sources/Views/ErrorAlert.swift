import SwiftUI

extension View {
    /// 保存・削除の失敗を知らせる共通アラート。
    /// メッセージが入っている間だけ表示し、OK で消す。
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: .constant(message.wrappedValue != nil)) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
