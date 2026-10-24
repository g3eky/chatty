/// Built-in color schemes. Values come from the official Catppuccin terminal themes
/// (github.com/catppuccin/ghostty, themes/catppuccin-*.conf).
struct Theme {
    let name: String
    let foreground: String
    let background: String
    let cursor: String
    let selection: String
    let ansi: [String]  // the 16 ANSI colors: 0–7 normal, 8–15 bright

    static func named(_ name: String?) -> Theme? {
        all.first { $0.name == name }
    }

    static let all = [
        Theme(name: "Catppuccin Latte", foreground: "#4C4F69", background: "#EFF1F5", cursor: "#DC8A78",
              selection: "#D8DAE1",
              ansi: ["#5C5F77", "#D20F39", "#40A02B", "#DF8E1D", "#1E66F5", "#EA76CB", "#179299", "#ACB0BE",
                     "#6C6F85", "#D20F39", "#40A02B", "#DF8E1D", "#1E66F5", "#EA76CB", "#179299", "#BCC0CC"]),
        Theme(name: "Catppuccin Frappé", foreground: "#C6D0F5", background: "#303446", cursor: "#F2D5CF",
              selection: "#44495D",
              ansi: ["#51576D", "#E78284", "#A6D189", "#E5C890", "#8CAAEE", "#F4B8E4", "#81C8BE", "#A5ADCE",
                     "#626880", "#E78284", "#A6D189", "#E5C890", "#8CAAEE", "#F4B8E4", "#81C8BE", "#B5BFE2"]),
        Theme(name: "Catppuccin Macchiato", foreground: "#CAD3F5", background: "#24273A", cursor: "#F4DBD6",
              selection: "#3A3E53",
              ansi: ["#494D64", "#ED8796", "#A6DA95", "#EED49F", "#8AADF4", "#F5BDE6", "#8BD5CA", "#A5ADCB",
                     "#5B6078", "#ED8796", "#A6DA95", "#EED49F", "#8AADF4", "#F5BDE6", "#8BD5CA", "#B8C0E0"]),
        Theme(name: "Catppuccin Mocha", foreground: "#CDD6F4", background: "#1E1E2E", cursor: "#F5E0DC",
              selection: "#353749",
              ansi: ["#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#A6ADC8",
                     "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE"]),
    ]
}
