import SwiftUI

struct GitLabProviderView: View {
    @ObservedObject var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.globalError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
            }

            if store.states.isEmpty {
                Text("暂无仓库，请在设置中添加")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.states) { state in
                            RepositoryRowView(state: state)
                                .padding(.horizontal, 12)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
