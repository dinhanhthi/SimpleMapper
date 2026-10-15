# Keys

Every key SimpleMapper can use as From or To. Names follow Karabiner-Elements `key_code` names. The HID usage is `(page << 32) | usage`, the value `hidutil` expects in `UserKeyMapping`: keyboard keys are on page `0x07`, `fn` is page `0xFF` usage `0x03`.

The Japanese keys are aliases: they share their usage with a `lang*` or `international*` key, so the selected From/To label and Detect key show the primary name.

## Modifiers

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `caps_lock` | ⇪ Caps Lock | `0x700000039` |
| `left_control` | ⌃ Left Control | `0x7000000E0` |
| `left_shift` | ⇧ Left Shift | `0x7000000E1` |
| `left_option` | ⌥ Left Option | `0x7000000E2` |
| `left_command` | ⌘ Left Command | `0x7000000E3` |
| `right_control` | ⌃ Right Control | `0x7000000E4` |
| `right_shift` | ⇧ Right Shift | `0x7000000E5` |
| `right_option` | ⌥ Right Option | `0x7000000E6` |
| `right_command` | ⌘ Right Command | `0x7000000E7` |
| `fn` | fn / Globe | `0xFF00000003` |

## Controls & Symbols

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `return_or_enter` | Return | `0x700000028` |
| `escape` | Escape | `0x700000029` |
| `delete_or_backspace` | Delete (Backspace) | `0x70000002A` |
| `delete_forward` | Forward Delete | `0x70000004C` |
| `tab` | Tab | `0x70000002B` |
| `spacebar` | Space | `0x70000002C` |
| `hyphen` | - \_ | `0x70000002D` |
| `equal_sign` | = + | `0x70000002E` |
| `open_bracket` | \[ { | `0x70000002F` |
| `close_bracket` | \] } | `0x700000030` |
| `backslash` | \\ \| | `0x700000031` |
| `non_us_pound` | Non-US # | `0x700000032` |
| `semicolon` | ; : | `0x700000033` |
| `quote` | ' " | `0x700000034` |
| `grave_accent_and_tilde` | \` ~ | `0x700000035` |
| `comma` | , \< | `0x700000036` |
| `period` | . > | `0x700000037` |
| `slash` | / ? | `0x700000038` |
| `non_us_backslash` | § / non-US \\ | `0x700000064` |

## Arrows

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `up_arrow` | ↑ Up | `0x700000052` |
| `down_arrow` | ↓ Down | `0x700000051` |
| `left_arrow` | ← Left | `0x700000050` |
| `right_arrow` | → Right | `0x70000004F` |
| `page_up` | Page Up | `0x70000004B` |
| `page_down` | Page Down | `0x70000004E` |
| `home` | Home | `0x70000004A` |
| `end` | End | `0x70000004D` |

## Letters

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `a` | A | `0x700000004` |
| `b` | B | `0x700000005` |
| `c` | C | `0x700000006` |
| `d` | D | `0x700000007` |
| `e` | E | `0x700000008` |
| `f` | F | `0x700000009` |
| `g` | G | `0x70000000A` |
| `h` | H | `0x70000000B` |
| `i` | I | `0x70000000C` |
| `j` | J | `0x70000000D` |
| `k` | K | `0x70000000E` |
| `l` | L | `0x70000000F` |
| `m` | M | `0x700000010` |
| `n` | N | `0x700000011` |
| `o` | O | `0x700000012` |
| `p` | P | `0x700000013` |
| `q` | Q | `0x700000014` |
| `r` | R | `0x700000015` |
| `s` | S | `0x700000016` |
| `t` | T | `0x700000017` |
| `u` | U | `0x700000018` |
| `v` | V | `0x700000019` |
| `w` | W | `0x70000001A` |
| `x` | X | `0x70000001B` |
| `y` | Y | `0x70000001C` |
| `z` | Z | `0x70000001D` |

## Numbers

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `1` | 1 | `0x70000001E` |
| `2` | 2 | `0x70000001F` |
| `3` | 3 | `0x700000020` |
| `4` | 4 | `0x700000021` |
| `5` | 5 | `0x700000022` |
| `6` | 6 | `0x700000023` |
| `7` | 7 | `0x700000024` |
| `8` | 8 | `0x700000025` |
| `9` | 9 | `0x700000026` |
| `0` | 0 | `0x700000027` |

## Function Keys

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `f1` | F1 | `0x70000003A` |
| `f2` | F2 | `0x70000003B` |
| `f3` | F3 | `0x70000003C` |
| `f4` | F4 | `0x70000003D` |
| `f5` | F5 | `0x70000003E` |
| `f6` | F6 | `0x70000003F` |
| `f7` | F7 | `0x700000040` |
| `f8` | F8 | `0x700000041` |
| `f9` | F9 | `0x700000042` |
| `f10` | F10 | `0x700000043` |
| `f11` | F11 | `0x700000044` |
| `f12` | F12 | `0x700000045` |
| `f13` | F13 | `0x700000068` |
| `f14` | F14 | `0x700000069` |
| `f15` | F15 | `0x70000006A` |
| `f16` | F16 | `0x70000006B` |
| `f17` | F17 | `0x70000006C` |
| `f18` | F18 | `0x70000006D` |
| `f19` | F19 | `0x70000006E` |
| `f20` | F20 | `0x70000006F` |
| `f21` | F21 | `0x700000070` |
| `f22` | F22 | `0x700000071` |
| `f23` | F23 | `0x700000072` |
| `f24` | F24 | `0x700000073` |

## Keypad

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `keypad_num_lock` | Keypad Num Lock / Clear | `0x700000053` |
| `keypad_slash` | Keypad / | `0x700000054` |
| `keypad_asterisk` | Keypad \* | `0x700000055` |
| `keypad_hyphen` | Keypad - | `0x700000056` |
| `keypad_plus` | Keypad + | `0x700000057` |
| `keypad_enter` | Keypad Enter | `0x700000058` |
| `keypad_1` | Keypad 1 | `0x700000059` |
| `keypad_2` | Keypad 2 | `0x70000005A` |
| `keypad_3` | Keypad 3 | `0x70000005B` |
| `keypad_4` | Keypad 4 | `0x70000005C` |
| `keypad_5` | Keypad 5 | `0x70000005D` |
| `keypad_6` | Keypad 6 | `0x70000005E` |
| `keypad_7` | Keypad 7 | `0x70000005F` |
| `keypad_8` | Keypad 8 | `0x700000060` |
| `keypad_9` | Keypad 9 | `0x700000061` |
| `keypad_0` | Keypad 0 | `0x700000062` |
| `keypad_period` | Keypad . | `0x700000063` |
| `keypad_equal_sign` | Keypad = | `0x700000067` |
| `keypad_comma` | Keypad , | `0x700000085` |

## PC Keys

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `print_screen` | Print Screen | `0x700000046` |
| `scroll_lock` | Scroll Lock | `0x700000047` |
| `pause` | Pause | `0x700000048` |
| `insert` | Insert | `0x700000049` |
| `application` | Application (PC Menu) | `0x700000065` |
| `help` | Help | `0x700000075` |
| `power` | Power | `0x700000066` |
| `execute` | Execute | `0x700000074` |
| `menu` | Menu | `0x700000076` |
| `select` | Select | `0x700000077` |
| `stop` | Stop | `0x700000078` |
| `again` | Again | `0x700000079` |
| `undo` | Undo | `0x70000007A` |
| `cut` | Cut | `0x70000007B` |
| `copy` | Copy | `0x70000007C` |
| `paste` | Paste | `0x70000007D` |
| `find` | Find | `0x70000007E` |

## International

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `international1` | International 1 | `0x700000087` |
| `international2` | International 2 | `0x700000088` |
| `international3` | International 3 | `0x700000089` |
| `international4` | International 4 | `0x70000008A` |
| `international5` | International 5 | `0x70000008B` |
| `international6` | International 6 | `0x70000008C` |
| `international7` | International 7 | `0x70000008D` |
| `international8` | International 8 | `0x70000008E` |
| `international9` | International 9 | `0x70000008F` |
| `lang1` | Lang 1 | `0x700000090` |
| `lang2` | Lang 2 | `0x700000091` |
| `lang3` | Lang 3 | `0x700000092` |
| `lang4` | Lang 4 | `0x700000093` |
| `lang5` | Lang 5 | `0x700000094` |
| `lang6` | Lang 6 | `0x700000095` |
| `lang7` | Lang 7 | `0x700000096` |
| `lang8` | Lang 8 | `0x700000097` |
| `lang9` | Lang 9 | `0x700000098` |

## Japanese

| Karabiner name | Label | HID usage |
| --- | --- | --- |
| `japanese_eisuu` | 英数 (Eisuu) | `0x700000091` |
| `japanese_kana` | かな (Kana) | `0x700000090` |
| `japanese_pc_nfer` | 無変換 (PC Nfer) | `0x70000008B` |
| `japanese_pc_xfer` | 変換 (PC Xfer) | `0x70000008A` |
| `japanese_pc_katakana` | カタカナ (PC Katakana) | `0x700000088` |

## ISO keyboards

On ISO keyboards (with a key left of `1` and a key right of the left Shift), macOS may swap `non_us_backslash` (`0x700000064`) and `grave_accent_and_tilde` (`0x700000035`), so the key labelled § can report either one. Use Detect key to see what a physical key actually sends before picking From.

## Equivalent command

Equivalent to what SimpleMapper sends to `hidutil` for your mappings (it uses decimal usages and sorted keys). First the All keyboards list is set globally (example: `caps_lock` to `escape`):

```sh
hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x700000029}]}'
```

Then, for each keyboard that has its own list, the merged list (the All list, with the keyboard's entries overriding the same From key and adding the others) is set for that keyboard only. Example for a keyboard with vendor ID 1452 and product ID 832 that also maps `right_command` to `right_control`:

```sh
hidutil property --matching '{"VendorID":1452,"ProductID":832,"PrimaryUsagePage":1,"PrimaryUsage":6}' --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x700000029},{"HIDKeyboardModifierMappingSrc":0x7000000E7,"HIDKeyboardModifierMappingDst":0x7000000E4}]}'
```

The order matters: a global `--set` also overwrites the per-keyboard values, so the global command always runs first and the per-keyboard commands follow. Built-in keyboards are matched with `{"Built-In":1,"PrimaryUsagePage":1,"PrimaryUsage":6}` instead of the vendor and product IDs. Only enabled rows are sent.

Clear everything with the global command, then once per keyboard that had its own list:

```sh
hidutil property --set '{"UserKeyMapping":[]}'
hidutil property --matching '{"VendorID":1452,"ProductID":832,"PrimaryUsagePage":1,"PrimaryUsage":6}' --set '{"UserKeyMapping":[]}'
```
