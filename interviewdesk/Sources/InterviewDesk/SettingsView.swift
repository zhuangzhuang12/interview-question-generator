import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LLM 设置")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("用于简历结构化和题卷生成（OpenAI 兼容接口）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding(22)
            Divider()

            Form {
                Section("接口") {
                    TextField("Base URL，如 https://api.openai.com/v1", text: $settings.settings.baseURL)
                    SecureField("API Key", text: $settings.settings.apiKey)
                    TextField("模型名，如 gpt-4o", text: $settings.settings.model)
                }
                Section {
                    Text("千帆/文心等平台提供 OpenAI 兼容模式，填入对应 base_url 与 key 即可。配置保存在本机。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 540, height: 320)
    }
}
