import Foundation

/// Key picker categories, in the order of Karabiner-Elements' simple_modifications.json.
enum Category: String, CaseIterable {
    case modifiers, controlsSymbols, arrows, letters, numbers, function, keypad, pc, international, japanese
}

/// One remappable key. `usage` is `(usagePage << 32) | usageID`, the format hidutil expects.
struct Key: Identifiable, Hashable {
    let name: String
    let label: String
    let usage: UInt64
    let category: Category

    var id: String { name }
}

/// Keyboard page 0x07 keys plus `fn`, named as in Karabiner-Elements' key_code.hpp.
enum KeyCatalog {
    static let defaultFrom: UInt64 = 0x700000064 // non_us_backslash
    static let defaultTo: UInt64 = 0x700000035 // grave_accent_and_tilde

    /// Japanese aliases come last so `key(usage:)` returns the primary name.
    static let all: [Key] = [
        Key(name: "caps_lock", label: "⇪ Caps Lock", usage: 0x700000039, category: .modifiers),
        Key(name: "left_control", label: "⌃ Left Control", usage: 0x7000000E0, category: .modifiers),
        Key(name: "left_shift", label: "⇧ Left Shift", usage: 0x7000000E1, category: .modifiers),
        Key(name: "left_option", label: "⌥ Left Option", usage: 0x7000000E2, category: .modifiers),
        Key(name: "left_command", label: "⌘ Left Command", usage: 0x7000000E3, category: .modifiers),
        Key(name: "right_control", label: "⌃ Right Control", usage: 0x7000000E4, category: .modifiers),
        Key(name: "right_shift", label: "⇧ Right Shift", usage: 0x7000000E5, category: .modifiers),
        Key(name: "right_option", label: "⌥ Right Option", usage: 0x7000000E6, category: .modifiers),
        Key(name: "right_command", label: "⌘ Right Command", usage: 0x7000000E7, category: .modifiers),
        Key(name: "fn", label: "fn / Globe", usage: 0xFF00000003, category: .modifiers),

        Key(name: "return_or_enter", label: "Return", usage: 0x700000028, category: .controlsSymbols),
        Key(name: "escape", label: "Escape", usage: 0x700000029, category: .controlsSymbols),
        Key(name: "delete_or_backspace", label: "Delete (Backspace)", usage: 0x70000002A, category: .controlsSymbols),
        Key(name: "delete_forward", label: "Forward Delete", usage: 0x70000004C, category: .controlsSymbols),
        Key(name: "tab", label: "Tab", usage: 0x70000002B, category: .controlsSymbols),
        Key(name: "spacebar", label: "Space", usage: 0x70000002C, category: .controlsSymbols),
        Key(name: "hyphen", label: "-  _", usage: 0x70000002D, category: .controlsSymbols),
        Key(name: "equal_sign", label: "=  +", usage: 0x70000002E, category: .controlsSymbols),
        Key(name: "open_bracket", label: "[  {", usage: 0x70000002F, category: .controlsSymbols),
        Key(name: "close_bracket", label: "]  }", usage: 0x700000030, category: .controlsSymbols),
        Key(name: "backslash", label: "\\  |", usage: 0x700000031, category: .controlsSymbols),
        Key(name: "non_us_pound", label: "Non-US #", usage: 0x700000032, category: .controlsSymbols),
        Key(name: "semicolon", label: ";  :", usage: 0x700000033, category: .controlsSymbols),
        Key(name: "quote", label: "'  \"", usage: 0x700000034, category: .controlsSymbols),
        Key(name: "grave_accent_and_tilde", label: "`  ~", usage: 0x700000035, category: .controlsSymbols),
        Key(name: "comma", label: ",  <", usage: 0x700000036, category: .controlsSymbols),
        Key(name: "period", label: ".  >", usage: 0x700000037, category: .controlsSymbols),
        Key(name: "slash", label: "/  ?", usage: 0x700000038, category: .controlsSymbols),
        Key(name: "non_us_backslash", label: "§ / non-US \\", usage: 0x700000064, category: .controlsSymbols),

        Key(name: "up_arrow", label: "↑ Up", usage: 0x700000052, category: .arrows),
        Key(name: "down_arrow", label: "↓ Down", usage: 0x700000051, category: .arrows),
        Key(name: "left_arrow", label: "← Left", usage: 0x700000050, category: .arrows),
        Key(name: "right_arrow", label: "→ Right", usage: 0x70000004F, category: .arrows),
        Key(name: "page_up", label: "Page Up", usage: 0x70000004B, category: .arrows),
        Key(name: "page_down", label: "Page Down", usage: 0x70000004E, category: .arrows),
        Key(name: "home", label: "Home", usage: 0x70000004A, category: .arrows),
        Key(name: "end", label: "End", usage: 0x70000004D, category: .arrows),

        Key(name: "a", label: "A", usage: 0x700000004, category: .letters),
        Key(name: "b", label: "B", usage: 0x700000005, category: .letters),
        Key(name: "c", label: "C", usage: 0x700000006, category: .letters),
        Key(name: "d", label: "D", usage: 0x700000007, category: .letters),
        Key(name: "e", label: "E", usage: 0x700000008, category: .letters),
        Key(name: "f", label: "F", usage: 0x700000009, category: .letters),
        Key(name: "g", label: "G", usage: 0x70000000A, category: .letters),
        Key(name: "h", label: "H", usage: 0x70000000B, category: .letters),
        Key(name: "i", label: "I", usage: 0x70000000C, category: .letters),
        Key(name: "j", label: "J", usage: 0x70000000D, category: .letters),
        Key(name: "k", label: "K", usage: 0x70000000E, category: .letters),
        Key(name: "l", label: "L", usage: 0x70000000F, category: .letters),
        Key(name: "m", label: "M", usage: 0x700000010, category: .letters),
        Key(name: "n", label: "N", usage: 0x700000011, category: .letters),
        Key(name: "o", label: "O", usage: 0x700000012, category: .letters),
        Key(name: "p", label: "P", usage: 0x700000013, category: .letters),
        Key(name: "q", label: "Q", usage: 0x700000014, category: .letters),
        Key(name: "r", label: "R", usage: 0x700000015, category: .letters),
        Key(name: "s", label: "S", usage: 0x700000016, category: .letters),
        Key(name: "t", label: "T", usage: 0x700000017, category: .letters),
        Key(name: "u", label: "U", usage: 0x700000018, category: .letters),
        Key(name: "v", label: "V", usage: 0x700000019, category: .letters),
        Key(name: "w", label: "W", usage: 0x70000001A, category: .letters),
        Key(name: "x", label: "X", usage: 0x70000001B, category: .letters),
        Key(name: "y", label: "Y", usage: 0x70000001C, category: .letters),
        Key(name: "z", label: "Z", usage: 0x70000001D, category: .letters),

        Key(name: "1", label: "1", usage: 0x70000001E, category: .numbers),
        Key(name: "2", label: "2", usage: 0x70000001F, category: .numbers),
        Key(name: "3", label: "3", usage: 0x700000020, category: .numbers),
        Key(name: "4", label: "4", usage: 0x700000021, category: .numbers),
        Key(name: "5", label: "5", usage: 0x700000022, category: .numbers),
        Key(name: "6", label: "6", usage: 0x700000023, category: .numbers),
        Key(name: "7", label: "7", usage: 0x700000024, category: .numbers),
        Key(name: "8", label: "8", usage: 0x700000025, category: .numbers),
        Key(name: "9", label: "9", usage: 0x700000026, category: .numbers),
        Key(name: "0", label: "0", usage: 0x700000027, category: .numbers),

        Key(name: "f1", label: "F1", usage: 0x70000003A, category: .function),
        Key(name: "f2", label: "F2", usage: 0x70000003B, category: .function),
        Key(name: "f3", label: "F3", usage: 0x70000003C, category: .function),
        Key(name: "f4", label: "F4", usage: 0x70000003D, category: .function),
        Key(name: "f5", label: "F5", usage: 0x70000003E, category: .function),
        Key(name: "f6", label: "F6", usage: 0x70000003F, category: .function),
        Key(name: "f7", label: "F7", usage: 0x700000040, category: .function),
        Key(name: "f8", label: "F8", usage: 0x700000041, category: .function),
        Key(name: "f9", label: "F9", usage: 0x700000042, category: .function),
        Key(name: "f10", label: "F10", usage: 0x700000043, category: .function),
        Key(name: "f11", label: "F11", usage: 0x700000044, category: .function),
        Key(name: "f12", label: "F12", usage: 0x700000045, category: .function),
        Key(name: "f13", label: "F13", usage: 0x700000068, category: .function),
        Key(name: "f14", label: "F14", usage: 0x700000069, category: .function),
        Key(name: "f15", label: "F15", usage: 0x70000006A, category: .function),
        Key(name: "f16", label: "F16", usage: 0x70000006B, category: .function),
        Key(name: "f17", label: "F17", usage: 0x70000006C, category: .function),
        Key(name: "f18", label: "F18", usage: 0x70000006D, category: .function),
        Key(name: "f19", label: "F19", usage: 0x70000006E, category: .function),
        Key(name: "f20", label: "F20", usage: 0x70000006F, category: .function),
        Key(name: "f21", label: "F21", usage: 0x700000070, category: .function),
        Key(name: "f22", label: "F22", usage: 0x700000071, category: .function),
        Key(name: "f23", label: "F23", usage: 0x700000072, category: .function),
        Key(name: "f24", label: "F24", usage: 0x700000073, category: .function),

        Key(name: "keypad_num_lock", label: "Keypad Num Lock / Clear", usage: 0x700000053, category: .keypad),
        Key(name: "keypad_slash", label: "Keypad /", usage: 0x700000054, category: .keypad),
        Key(name: "keypad_asterisk", label: "Keypad *", usage: 0x700000055, category: .keypad),
        Key(name: "keypad_hyphen", label: "Keypad -", usage: 0x700000056, category: .keypad),
        Key(name: "keypad_plus", label: "Keypad +", usage: 0x700000057, category: .keypad),
        Key(name: "keypad_enter", label: "Keypad Enter", usage: 0x700000058, category: .keypad),
        Key(name: "keypad_1", label: "Keypad 1", usage: 0x700000059, category: .keypad),
        Key(name: "keypad_2", label: "Keypad 2", usage: 0x70000005A, category: .keypad),
        Key(name: "keypad_3", label: "Keypad 3", usage: 0x70000005B, category: .keypad),
        Key(name: "keypad_4", label: "Keypad 4", usage: 0x70000005C, category: .keypad),
        Key(name: "keypad_5", label: "Keypad 5", usage: 0x70000005D, category: .keypad),
        Key(name: "keypad_6", label: "Keypad 6", usage: 0x70000005E, category: .keypad),
        Key(name: "keypad_7", label: "Keypad 7", usage: 0x70000005F, category: .keypad),
        Key(name: "keypad_8", label: "Keypad 8", usage: 0x700000060, category: .keypad),
        Key(name: "keypad_9", label: "Keypad 9", usage: 0x700000061, category: .keypad),
        Key(name: "keypad_0", label: "Keypad 0", usage: 0x700000062, category: .keypad),
        Key(name: "keypad_period", label: "Keypad .", usage: 0x700000063, category: .keypad),
        Key(name: "keypad_equal_sign", label: "Keypad =", usage: 0x700000067, category: .keypad),
        Key(name: "keypad_comma", label: "Keypad ,", usage: 0x700000085, category: .keypad),

        Key(name: "print_screen", label: "Print Screen", usage: 0x700000046, category: .pc),
        Key(name: "scroll_lock", label: "Scroll Lock", usage: 0x700000047, category: .pc),
        Key(name: "pause", label: "Pause", usage: 0x700000048, category: .pc),
        Key(name: "insert", label: "Insert", usage: 0x700000049, category: .pc),
        Key(name: "application", label: "Application (PC Menu)", usage: 0x700000065, category: .pc),
        Key(name: "help", label: "Help", usage: 0x700000075, category: .pc),
        Key(name: "power", label: "Power", usage: 0x700000066, category: .pc),
        Key(name: "execute", label: "Execute", usage: 0x700000074, category: .pc),
        Key(name: "menu", label: "Menu", usage: 0x700000076, category: .pc),
        Key(name: "select", label: "Select", usage: 0x700000077, category: .pc),
        Key(name: "stop", label: "Stop", usage: 0x700000078, category: .pc),
        Key(name: "again", label: "Again", usage: 0x700000079, category: .pc),
        Key(name: "undo", label: "Undo", usage: 0x70000007A, category: .pc),
        Key(name: "cut", label: "Cut", usage: 0x70000007B, category: .pc),
        Key(name: "copy", label: "Copy", usage: 0x70000007C, category: .pc),
        Key(name: "paste", label: "Paste", usage: 0x70000007D, category: .pc),
        Key(name: "find", label: "Find", usage: 0x70000007E, category: .pc),

        Key(name: "international1", label: "International 1", usage: 0x700000087, category: .international),
        Key(name: "international2", label: "International 2", usage: 0x700000088, category: .international),
        Key(name: "international3", label: "International 3", usage: 0x700000089, category: .international),
        Key(name: "international4", label: "International 4", usage: 0x70000008A, category: .international),
        Key(name: "international5", label: "International 5", usage: 0x70000008B, category: .international),
        Key(name: "international6", label: "International 6", usage: 0x70000008C, category: .international),
        Key(name: "international7", label: "International 7", usage: 0x70000008D, category: .international),
        Key(name: "international8", label: "International 8", usage: 0x70000008E, category: .international),
        Key(name: "international9", label: "International 9", usage: 0x70000008F, category: .international),
        Key(name: "lang1", label: "Lang 1", usage: 0x700000090, category: .international),
        Key(name: "lang2", label: "Lang 2", usage: 0x700000091, category: .international),
        Key(name: "lang3", label: "Lang 3", usage: 0x700000092, category: .international),
        Key(name: "lang4", label: "Lang 4", usage: 0x700000093, category: .international),
        Key(name: "lang5", label: "Lang 5", usage: 0x700000094, category: .international),
        Key(name: "lang6", label: "Lang 6", usage: 0x700000095, category: .international),
        Key(name: "lang7", label: "Lang 7", usage: 0x700000096, category: .international),
        Key(name: "lang8", label: "Lang 8", usage: 0x700000097, category: .international),
        Key(name: "lang9", label: "Lang 9", usage: 0x700000098, category: .international),

        Key(name: "japanese_eisuu", label: "英数 (Eisuu)", usage: 0x700000091, category: .japanese),
        Key(name: "japanese_kana", label: "かな (Kana)", usage: 0x700000090, category: .japanese),
        Key(name: "japanese_pc_nfer", label: "無変換 (PC Nfer)", usage: 0x70000008B, category: .japanese),
        Key(name: "japanese_pc_xfer", label: "変換 (PC Xfer)", usage: 0x70000008A, category: .japanese),
        Key(name: "japanese_pc_katakana", label: "カタカナ (PC Katakana)", usage: 0x700000088, category: .japanese),
    ]

    static func key(usage: UInt64) -> Key? {
        all.first { $0.usage == usage }
    }

    static func key(name: String) -> Key? {
        all.first { $0.name == name }
    }
}
