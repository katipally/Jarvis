import MarkdownUI
import SwiftUI

extension MarkdownUI.Theme {
    /// Compact dark theme tuned for the notch's narrow width.
    @MainActor
    static var jarvis: MarkdownUI.Theme {
        MarkdownUI.Theme()
            .text {
                ForegroundColor(.white.opacity(0.9))
                FontSize(13)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(12)
                ForegroundColor(Color(red: 0.85, green: 0.9, blue: 1.0))
                BackgroundColor(.white.opacity(0.1))
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(Color(red: 0.4, green: 0.7, blue: 1.0)) }
            .heading1 { config in
                config.label
                    .markdownMargin(top: 8, bottom: 4)
                    .markdownTextStyle { FontSize(17); FontWeight(.bold) }
            }
            .heading2 { config in
                config.label
                    .markdownMargin(top: 6, bottom: 3)
                    .markdownTextStyle { FontSize(15); FontWeight(.semibold) }
            }
            .heading3 { config in
                config.label
                    .markdownMargin(top: 4, bottom: 2)
                    .markdownTextStyle { FontSize(14); FontWeight(.semibold) }
            }
            .codeBlock { config in
                ScrollView(.horizontal, showsIndicators: false) {
                    config.label
                        .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(12) }
                        .padding(10)
                }
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .markdownMargin(top: 6, bottom: 6)
            }
            .listItem { config in
                config.label.markdownMargin(top: 2, bottom: 2)
            }
            .blockquote { config in
                config.label
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 2)
                    }
            }
    }
}
