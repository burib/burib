#!/usr/bin/env swift
// Regenerate ../terminal/burib-dark.terminal and burib-light.terminal from the
// palettes below.
//
//   ./scripts/generate_terminal_profiles.swift
//
// Why a generator: a .terminal file stores every color as an NSKeyedArchiver
// blob, so hand-editing one means editing base64 - and a diff of it is
// unreviewable. The palettes here are the source of truth; the .terminal files
// are build output. Colors are the "EyeComfort" warm low-contrast set
// (Gruvbox-Material-based): ~8:1 text/background contrast in both modes instead
// of the 21:1 that white-on-black gives you, which is the main driver of eye
// strain over a long day.
//
// Color space, the one subtle part: Terminal stores NSColor values, and writing
// "0.157 0.157 0.157" (#282828) into the legacy *calibrated* RGB space renders
// as #353535 - Apple's generic space uses gamma 1.8, sRGB uses ~2.2, so naive
// values come out lighter than intended. The hexes below are therefore treated
// as sRGB and converted through AppKit before archiving, so what Terminal
// paints is exactly the hex you read here. (The previous Catppuccin profiles
// did not do this: their #1e1e2e background was really displaying as ~#2a2a3c.)

import AppKit
import Foundation

// MARK: - Palettes

struct Palette {
    let name: String
    let background, text, bold, cursor, selection: String
    let black, red, green, yellow, blue, magenta, cyan, white: String
    let brightBlack, brightRed, brightGreen, brightYellow: String
    let brightBlue, brightMagenta, brightCyan, brightWhite: String
}

let dark = Palette(
    name: "burib-dark",
    background: "#282828", text: "#d4be98", bold: "#ddc7a1",
    cursor: "#a89984", selection: "#45403d",
    black: "#32302f", red: "#ea6962", green: "#a9b665", yellow: "#d8a657",
    blue: "#7daea3", magenta: "#d3869b", cyan: "#89b482", white: "#d4be98",
    // brights deliberately equal the normals (except grey/white): the usual
    // neon bright set is the harshest thing in a terminal. Bright black stays
    // distinct because dim/comment text uses it.
    brightBlack: "#928374", brightRed: "#ea6962", brightGreen: "#a9b665", brightYellow: "#d8a657",
    brightBlue: "#7daea3", brightMagenta: "#d3869b", brightCyan: "#89b482", brightWhite: "#ddc7a1"
)

let light = Palette(
    name: "burib-light",
    // warm paper tone, not near-white: #f2e5bc rather than #fbf1c7 or #eff1f5
    background: "#f2e5bc", text: "#4f3829", bold: "#3c2b1f",
    cursor: "#af3a03", selection: "#d5c4a1",
    // white/brightWhite mirror dark's white=text, brightWhite=bold: ANSI "white"
    // is the theme's prominent-foreground slot, not literally a light color. The
    // first pass used near-paper hexes here (brightWhite was *exactly* the
    // background), so anything printed in ANSI white vanished entirely.
    black: "#654735", red: "#953333", green: "#515b23", yellow: "#7a4c06",
    blue: "#385b63", magenta: "#724862", cyan: "#3a5e47", white: "#4f3829",
    // accents darkened from the first pass, which sat at 3.1-4.3:1 against this
    // background (vs. 4.7-6.7:1 for the dark palette's equivalents) - hue held
    // constant, lightness reduced until each clears ~5.8:1, matching dark's range.
    brightBlack: "#5d5349", brightRed: "#953333", brightGreen: "#515b23", brightYellow: "#7a4c06",
    brightBlue: "#385b63", brightMagenta: "#724862", brightCyan: "#3a5e47", brightWhite: "#3c2b1f"
)

let fontName = "JetBrainsMonoNFM-Regular"   // Brewfile: font-jetbrains-mono-nerd-font
let fontSize = 15.0                          // larger glyphs = less squinting
let lineSpacing = 1.18                       // air between rows, easier line tracking

// MARK: - Encoding

func archivedColor(_ hex: String) -> Data {
    var h = hex
    h.removeFirst()
    guard h.count == 6, let v = UInt32(h, radix: 16) else {
        fatalError("bad hex: \(hex)")
    }
    let srgb = NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255.0,
                       green: CGFloat((v >> 8) & 0xff) / 255.0,
                       blue: CGFloat(v & 0xff) / 255.0,
                       alpha: 1.0)
    // see the color-space note in the header
    let converted = srgb.usingColorSpace(.genericRGB) ?? srgb
    return try! NSKeyedArchiver.archivedData(withRootObject: converted, requiringSecureCoding: false)
}

func archivedFont() -> Data {
    guard let font = NSFont(name: fontName, size: CGFloat(fontSize)) else {
        FileHandle.standardError.write("font not installed: \(fontName)\n".data(using: .utf8)!)
        exit(1)
    }
    return try! NSKeyedArchiver.archivedData(withRootObject: font, requiringSecureCoding: false)
}

func profile(_ p: Palette) -> [String: Any] {
    [
        "name": p.name,
        "type": "Window Settings",
        "ProfileCurrentVersion": 2.04,

        "BackgroundColor": archivedColor(p.background),
        "TextColor": archivedColor(p.text),
        // NOTE: the key is TextBoldColor. The older profiles said BoldTextColor,
        // which Terminal ignores, so bold text silently fell back to TextColor.
        "TextBoldColor": archivedColor(p.bold),
        "CursorColor": archivedColor(p.cursor),
        "SelectionColor": archivedColor(p.selection),

        "ANSIBlackColor": archivedColor(p.black),
        "ANSIRedColor": archivedColor(p.red),
        "ANSIGreenColor": archivedColor(p.green),
        "ANSIYellowColor": archivedColor(p.yellow),
        "ANSIBlueColor": archivedColor(p.blue),
        "ANSIMagentaColor": archivedColor(p.magenta),
        "ANSICyanColor": archivedColor(p.cyan),
        "ANSIWhiteColor": archivedColor(p.white),
        "ANSIBrightBlackColor": archivedColor(p.brightBlack),
        "ANSIBrightRedColor": archivedColor(p.brightRed),
        "ANSIBrightGreenColor": archivedColor(p.brightGreen),
        "ANSIBrightYellowColor": archivedColor(p.brightYellow),
        "ANSIBrightBlueColor": archivedColor(p.brightBlue),
        "ANSIBrightMagentaColor": archivedColor(p.brightMagenta),
        "ANSIBrightCyanColor": archivedColor(p.brightCyan),
        "ANSIBrightWhiteColor": archivedColor(p.brightWhite),
        "DisableANSIColor": false,

        "Font": archivedFont(),
        "FontAntialias": true,
        "FontHeightSpacing": lineSpacing,
        "FontWidthSpacing": 1.0,
        "UseBrightBold": false,   // bold must not jump to the neon palette

        // nothing on screen may move or flash on its own
        "CursorType": 0,          // block
        "CursorBlink": false,
        "BlinkText": false,
        "Bell": false,
        "VisualBell": false,
        "VisualBellOnlyWhenBellIsAudible": false,
        "BellBadge": false,
        "BellBounce": false,

        "BackgroundBlur": 0.0,
        "BackgroundSettingsForInactiveWindows": false,  // no dimming when unfocused
        "columnCount": 100,
        "rowCount": 28,
    ]
}

// MARK: - Write

let terminalDir = URL(fileURLWithPath: #filePath)   // scripts/generate_terminal_profiles.swift
    .deletingLastPathComponent()                    // scripts/
    .deletingLastPathComponent()                    // repo root
    .appendingPathComponent("terminal")

for p in [dark, light] {
    let url = terminalDir.appendingPathComponent("\(p.name).terminal")
    let data = try PropertyListSerialization.data(fromPropertyList: profile(p), format: .xml, options: 0)
    try data.write(to: url)
    print("wrote \(url.path)")
}
