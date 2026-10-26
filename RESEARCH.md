# Oxi Controller: research on the OXI E16

Written 26.10.2026 for the Mac app **Oxi Controller** (presets for the E16 that drive Ableton Live,
with changes reaching the device live). Read-only research: nothing on the Mac was changed,
nothing was installed, and nothing over a few hundred kB was downloaded.

**How to read the tags**

- **[SRC]**: a published source says so. The URL sits next to the fact.
- **[MAC]**: seen on this Mac on 26.10.2026: the OXI App bundle, its logs, the scene files.
- **[MANIFEST]**: measured earlier on Marko's E16 and written in
  `~/Developer/MANTRA_MANIFEST/modules/oxi-e16.md`.
- **[INFERENCE]**: my own conclusion. Test it on the device before relying on it.

---

## 0. What was already known (the manifest, not redone)

Source: `~/Developer/MANTRA_MANIFEST/modules/oxi-e16.md` **[MANIFEST]**

- CoreMIDI shows one device with three sources, `OXI E16 Port 1/2/3`. The device and the OXI App
  call them **USB1, USB2, USB3**.
- Scenes are `*.oxie16` files in JSON, kept under `~/Documents/OXI_16/Scenes` and
  `~/Documents/OXIE16/Scenes`. Each file has 12 pages × 16 encoders. In an action, `nr1` holds
  the CC number, `color` is a 0-99 index into a hand-picked 10×10 palette (`MB.PALETTE` in
  `MANTRA_STAR/apps/a1.lua`), and the action `type` runs `0 Off, 1 Rel1, 2 Rel2, 3 Abs, 4 CC14,
  5 PC, 6 PB, 7 AT, 8 Note, 9 NRPN, 10 Snapshot`.
- **The LED rings follow plain CC sent to USB2 or USB3, never USB1.** The CC must be on the knob's own
  channel. Measured on firmware 1.3.0 on 1.10.2026. The device adopts the value it receives and
  does not echo it back.
- Plain MIDI carries no colour. Colour comes from the scene, from Remote Mode, or from Lua.

---

## 1. The official OXI App on this Mac [MAC]

| What | Finding |
|---|---|
| Bundle | `/Applications/OXI App.app`, `com.oxiinstruments.oxiapp`, **version 2.1.0** (build 21099), 63 MB |
| Built with | **Flutter (Dart AOT), not Electron.** There is no `app.asar` and no `package.json`. `Contents/Frameworks` holds `App.framework` (the compiled Dart code), `FlutterMacOS.framework`, `Sparkle.framework` (auto-update), **`rtmidi_command.framework`** (MIDI through RtMidi), `lua_minify.framework`, `file_picker`, `macos_secure_bookmarks`, `shared_preferences_foundation`, `path_provider_foundation` |
| Update feed | `SUFeedURL = https://oxi-instruments.github.io/OXI-Desktop-APP/appcast-macos.xml` (Info.plist) |
| Settings | `~/Library/Preferences/com.oxiinstruments.oxiapp.plist`. Key `flutter.BookmarkType.e16Scenes` holds a security-scoped bookmark to the scenes folder the user picked (Scenes → *Assign PC/Mac folder*) |
| Scenes on disk | `~/Documents/OXI_16/Scenes/S. 1.oxie16`, `~/Documents/OXIE16/Scenes/{HQ Edu,Mix}.oxie16` (JSON), and `~/Documents/OXI_16/Scripts/` (empty; would hold `*.e16script` Lua files) |
| Logs | `~/Library/Application Support/com.oxiinstruments.oxiapp/log.txt` and the sandbox copy at `~/Library/Containers/com.oxiinstruments.oxiapp/Data/Library/Application Support/com.oxiinstruments.oxiapp/log.txt` |
| Manuals on disk | `~/Documents/OXIE16/OXI E16 - User Manual.pdf` (74 pages, dated Feb 2026, so it predates firmware 1.x) and `OXI E16 - Quick Start.pdf` |

What the logs show:

- The app **always opens `OXI E16 Port 1` (USB1)** for its own session: `Requesting connection to
  OXI E16 Port 1... Connected`. SysEx traffic to and from the app goes through USB1.
- Firmware updates go through a separate bootloader MIDI device named `OXI E16 FW Update`, sent in
  chunks with ACKs: `Handshake ... Upload Confirmed. Starting Chunk 0 ... Sending Exit Request (0x52)`.
  The image files are `OXI_E16_x_y_z.syx`, about 670-720 kB.

What the compiled Dart strings show (`strings` on `App.framework/App`, read-only):

- Message classes include `OxiE16SceneHeaderMessage`, `OxiE16PageMessage`, `OxiE16DataAckMessage`,
  `OxiE16DataNackMessage`, `OxiE16FirmwareVersionMessage`, `OxiE16InstrumentDefinitionMessage`,
  `SceneUploadBloc`, `SceneDownloadBloc`, `ScenePageReceived`, `E16SerializerV1`, `MIDISysExMessage`.
  These match the SysEx protocol in §3.
- The UI string **"Run in the active scene on E16 (temporary)"**, with `loadScript`,
  `printToConsole` and "Show console". This is firmware 1.3.0's *"live script loading and console
  output for debugging through OXI App"* (§4). The SysEx message behind it is **not public** (§9).
- The UI string "Check the USB connection and stop SysEx from other apps or devices before
  retrying". Uploads clash with any other app that sends SysEx at the same moment.

Conclusion: the OXI App is closed source. It edits a copy on the Mac and then **uploads the whole
scene to a slot** over SysEx. It has no live editing of plain controls, which is why Marko has to
"send scene" after every change.

---

## 2. Device model: scenes, pages, presets, control types

- 16 scenes on the device, each with 12 pages of 16 encoders. A scene also holds 16 presets, each
  storing the value of every knob. Each encoder has one push action and two turn actions.
  [SRC] https://oxiinstruments.com/e16/ ("12 pages of 16 controls"), manual p. 41/47 ("Each scene
  also contains 16 presets. A preset stores the current values of all the knobs"). [MAC]: the JSON
  has `pages[12]`, `turn_actions[2]` and `push_action`.
- Control types: *"Off, CC Rel1, CC Rel2, CC Abs, CC14 (High Resolution), PC, PB, AT, Note, NRPN,
  Snapshot"*. On firmware 1.x, Lua adds `type 11` = Script turn and `type 12` = Script push.
  [SRC] manual (local PDF, control editor pages);
  https://github.com/charlesvestal/oxi-e16-lua/blob/main/docs/e16-lua-notes.md ("`turn_actions[0]`
  with **`type` 11 = Script** ... `push_action` with **`type` 12 = Script**").
- Firmware 1.3.0 added *"selectable MSB-first or LSB-first order for CC14"* and *"NRPN push
  actions"*. Firmware 1.2.0 added *"Support inverted value ranges"* and *"setting to only expose
  only a single midi port (virtual cable) over usb"*.
  [SRC] https://github.com/OXI-Instruments/OXI-E16-Releases/releases
- **Scenes can be switched from the Mac by Program Change.** *"Sending a PC message on the defined
  channel will then change the scene to the PC message value ... Scenes 1-16 can be selected
  directly by PC"* (Settings → MIDI → *PC Receive Channel*). Firmware 1.0.0 added *"Better
  scene/page selection options via incoming PC and Bank Select"*.
  [SRC] manual p. 38 (local PDF); release 1.0.0 notes (URL above).
- The scene header has `transmitOnSceneEntry`, `transmitOnPageSwitch`, `transmitOnPresetLoad`,
  `smartTransmit` and `pcOnEntry`. These let the E16 send its current values to Live when a scene or
  page is entered. [MAC] scene JSON. Release 1.0.0 lists *"Per scene auto transmit override"*.
- Pitfall from the forum: Ableton faders "drop to zero" after leaving and re-entering a scene, and
  "Default value is not saved via the app" (Kultschar, 29.4.2026).
  [SRC] https://www.elektronauts.com/t/oxi-instruments-e16-midi-controller/238039?page=18
  [INFERENCE] Oxi Controller should send the knob values back on USB2/USB3 whenever it loads a preset,
  and not rely on the device's transmit-on-entry.

---

## 3. How the OXI App sends a scene: the SysEx upload protocol

The protocol was reverse-engineered by Charles Vestal, who logged CoreMIDI inside a re-signed copy of
the OXI App. His Python tool `e16push.py` reproduces the app's upload byte for byte, and the
device accepts it. **[SRC, confirmed on hardware by the author]**
https://github.com/charlesvestal/oxi-e16-lua/blob/main/docs/e16-lua-notes.md (section "USB-MIDI
SysEx protocol") and https://github.com/charlesvestal/oxi-e16-lua/blob/main/tools/e16push.py

- **Header:** `F0 00 21 5B 02 01 …  F7`. `00 21 5B` is OXI's manufacturer ID and `02 01` means
  E16. (The OXI One uses `00 21 5B 00 01`.)
- **Firmware version:** send `03 00`. Firmware 1.2.0 replies
  `03 00 03 01 02 0E 03 02 02 0E 03 00 00 00` (layout not decoded).
- **Read a slot's scene name:** send `07 00 <slot 0-15> 00 00 00 00 00 00`. The reply is
  `08 00 <slot> 00` + packed data (`13 00 50 00`, the name NUL-padded, …).
- **Upload:** `08 <kind> <slot 0-15> <index>` + packed data. Kind 0 = scene header (80-byte body),
  kind 1 = page (index 0-11, 976-byte body), kind 4 = script (code padded with zeros to 8192 bytes,
  one ~9.4 kB SysEx). **Each message is ACKed with `F0 00 21 5B 02 01 08 53 F7`.** The OXI App sends
  header → 12 pages → script, and does not split them further.
  > "A script can be uploaded on its own. Kind 4 alone replaces the scene's code and leaves its
  > pages and variables as they are. **The new code runs when the scene is next opened.**"
- **Packed data:** `u32 BE (body+8)`, `0x11`, `u16 BE body length`, `0x00`, body, `u32 BE CRC`.
  The whole block is then **7-bit packed**: each group of 7 bytes becomes one byte holding the high
  bits (bit j = byte j), followed by the 7 bytes with bit 7 cleared.
- **CRC:** *"the STM32 hardware CRC-32 of the body: poly `0x04C11DB7`, init `0xFFFFFFFF`, 32-bit
  little-endian words (zero-padded), no reflection, no final XOR."*
- **Header body (80 bytes):** title(16), icon(32), color, transmitMode, pcOnEntry, bankOnEntry(u16
  BE), recentPage, recentPreset, transmitOnSceneEntry, transmitOnPageSwitch, transmitOnPresetLoad,
  smartTransmit, outputOnEntry, holdMode, acceleration, scriptName(18). The order of the fields that
  were zero in the captures is assumed from the JSON.
- **Page body (976 bytes):** title(12), 0, channel, output, 0, then 16 × 60-byte encoders:
  name(8), abbr(4), color, push action (instrument, parameter, type, display, mode, channel, lower u16,
  upper u16, nr1, nr2, output, scriptId = 14 bytes), two turn actions (16 bytes each, with
  defaultValue u16 after upper), color2.
- The tool opens the first output and input whose name contains "E16". On this Mac that is
  **Port 1 / USB1**, the same port the OXI App uses [MAC log]. [INFERENCE] SysEx goes on USB1 and
  value feedback on USB2/USB3. Oxi Controller needs both open.

**What this means for "live" [INFERENCE]:** a scene upload goes to a *slot*, and the
device reads it when the scene is opened. A plain-mode preset change from Oxi Controller would
therefore be (1) upload the changed page(s), 13 kB at most and ACKed, (2) re-enter the scene,
for example by sending a Program Change on the PC Receive Channel or by switching to another slot
and back, (3) resend the knob values as CC on USB2/USB3. That is quick, but it is a reload rather than
a seamless change, and it writes flash on every upload. Whether uploading to the *active* slot takes
effect without re-entry is **untested**.

---

## 4. Lua on the device (firmware 1.0+, API 1.3.0 on firmware 1.3.0)

Sources: [SRC] https://github.com/charlesvestal/oxi-e16-lua/blob/main/docs/e16-lua-notes.md ·
https://github.com/tsln-lab/oxi-e16-lua-api (docs/src/content/docs/api/*.md) ·
https://github.com/OXI-Instruments/OXI-E16-Releases/releases (1.1.0 *"Add led.update ... and
updateByIndex"*, 1.3.0 *"Added live script loading and console output for debugging through OXI
App"*, *"incoming MIDI Note and CC handling in Lua"*, *"access to control values and settings from
Lua"*). OXI's own reference is the *Lua Scripting API Guide* (API 1.3.0, 29.9.2026) plus chapter 6
of the current manual. Neither is on this Mac; the local PDF is older.

The API calls that matter for this app:

| Need | Lua call (verbatim from the sources) |
|---|---|
| Ring value + colour | `leds.updateByIndex(index, value, color)`; batch `leds.updateByIndex({{i, v, c}, …})`; `leds.reset(i)`. `value` 0-16383. *"`color` is an **index into the OXI App's 100-color palette** … read left to right, top to bottom, from 0 … 6 = dark blue, 18 = light blue, 34 = white, 50 = pink"* [HW per charlesvestal] |
| 4-character label per knob | `slots.update(i, text)` (max 4 chars, persists across pages) |
| Page title | `page.setTitle(text)` (15 chars; call `page.resetTitle()` first, then set it on the next `update` tick, or the header can freeze) |
| Receive data from the Mac | `controller.onSysex` callback; on 1.3: `midi.listen{notes=, cc=, channel=, port=}` + `midi.onCC`, `midi.onNote` |
| Send to Live | `midi.sendCC(out, ch 0-15, cc, value)`, `midi.sendMidi(out, ch, status, d1, d2)`, `midi.sendSysex` (≤128 bytes incl. F0/F7) |
| Encoders | `controller.onEncoderTurn` (filter `increment == 0` and `id == 255`), `onEncoderPress`; on 1.3 `onEncoderRelease(held_ms)`, `onEncoderHold`; `controller.set(id, {manual=true, v=8192})`, `controller.get(id, key)` |
| Timer | `system.update` global + `system.setUpdateRate(5-1000 ms)` on 1.3 |
| Storage | `var` (32 per scene), `store.data` (1 KiB per scene) on 1.3 |

Limits: 48 KB shared heap, of which about 40 KB is left for Lua. The script holds at most 8,192 bytes
after minification, and compiling is the real limit (≈28.6-29.2 KB compile peak on 1.3). Lua 5.4
with 32-bit floats; base/math/string/table only. Avoid `%f` (floats print nothing). [SRC] same notes.

**A working precedent for host-driven visuals:** Schwung's `schwung.lua` runs on the device. The
host sends only small custom SysEx messages, `F0 00 21 5B 02 01 <id> … F7`, with `0x10` PAGE
(title + 16 labels), `0x11` VALUE (index, hi, lo, 14-bit) and `0x12` TITLE. The script draws them
with `slots.update`, `leds.*` and `page.setTitle`. A value change then costs about 5 bytes, against
394 USB packets for a Remote Mode framebuffer. [SRC]
https://github.com/charlesvestal/schwung/blob/main/tools/e16-lua/README.md

[INFERENCE] **This is the best fit for "live" presets.** Oxi Controller would install one generic
Lua script per scene, once (kind-4 upload, or drag in the OXI App). From then on it could change
ring colours, labels, title and values over SysEx at any moment, with no "send scene" and no reload.
Turns would still go to Live: either as the scene's own CC turn actions, or as Script turns that
the script forwards with `midi.sendCC`. Untested: whether Script-type controls and CC-type controls
can share one page with the ring overridden (`leds.updateByIndex` takes priority over the control's
own ring, per the notes).

---

## 5. Remote Mode: the Mac takes over the whole device

Official spec, published by OXI as a Google Sheet. The tab for the E16 is gid `1057524829`; gid 0 is
the OXI One. [SRC]
https://docs.google.com/spreadsheets/d/1Yccnrluv10QL_PauMmtCt64EtYjfSeZEXKrlrw8P24w/edit
(CSV export: `.../export?format=csv&gid=1057524829`). The 1.2.0 release notes link to it, and it
refers to a fuller "E16 REMOTE GUIDE.docx" that was not found.

| Msg | ID | Payload (7-bit packed) |
|---|---|---|
| ENTER REMOTE MODE | `06 55` | none. Example `F0 00 21 5B 02 01 06 55 F7` |
| ENTERED ACK (device→host) | `06 53` | none |
| EXIT REMOTE MODE | `06 00` | none. *"The category byte 0x06 is still required."* |
| LED | `06 01` | 5-byte chunks: *"Encoder index 0-15, LED index 0-15, R 0-127, G 0-127, B 0-127"*. Several LEDs per message |
| LED RING | `06 04` | 7-byte chunks: *"Encoder index 0-15, R, G, B, Ring amount MSB, Ring amount LSB, Bipolar (0x00=normal arc, 0x01=bipolar centered)"*. *"Ring amount is a 14-bit value mapping to 0-100% of the ring."* |
| OLED FRAMEBUFFER | `06 02` | 1024 bytes, 128×64 mono, SSD1306 page/column. *"Replaces the entire display content"* |
| OLED LABELS | `06 03` | 80 bytes: *"16-char title + 16x 4-char labels"*. *"Sending a framebuffer overrides labels and vice versa."* |
| OLED SCANLINE | (`06`) `05` | Y + 16 bytes + optional CRC16. Added in firmware 1.2 (*"Add partial updates to remote mode API"*) |
| OLED RECTANGLE | (`06`) `08` | x, y, w, h + pixels |
| OLED CLEAR | (`06`) `07` | none |
| OLED UPDATE ACK / NACK | `53` / `54` (no `06`) | 6 bytes: cmd, status, address. NACK status 01 length, 02 bounds, 03 CRC, 04 inactive, 05 encoding, 06 interrupted |

**Input in Remote Mode is fixed:** turns arrive as *"CC number = encoder 1-16, MIDI channel 1 …
Clockwise TURN: 0x01 to 0x08, Counter-Clockwise TURN: 0x7F to 0x78"* (relative with acceleration).
Encoder buttons arrive as Note 0-15 on channel 1 and Shift as Note 16. [SRC] the sheet.

Practical notes [SRC] https://github.com/charlesvestal/schwung/blob/main/docs/E16_REMOTE.md:

- Send ENTER repeatedly until the ACK arrives. *"the device blanks its screen and rings"* once it
  takes over. *"Send EXIT when giving the device back, or it stays blank."* Unplugging power-cycles
  it out of Remote Mode.
- The packing trap: LABELS and RING bytes never set bit 7, so a packer that always writes a zero
  header byte looks correct and fails only on FRAMEBUFFER.
- Measured cost on their (slow) host: FRAMEBUFFER 394 USB packets, LABELS 34, all 16 RINGs 46.
  Long SysEx messages corrupted occasionally. Design rule from that work: *"the LABEL carries the
  NAME … the RING carries the VALUE … the TITLE carries the READING"*.
- Firmware 1.3.0 *"Restored compatibility with existing Remote Mode integrations that 1.2
  introduced"*. 1.2 had broken it. [SRC] the releases page.

**Remote Mode is the only route that gives a free RGB colour** (0-127 per channel, per LED or per
ring) rather than one of the 100 palette entries. The price is that the scene stops working: no CC
to Live, no pages, no presets on the device. Oxi Controller would then have to be the whole
brain, turning relative CC 1-16 into AbletonOSC / Mackie / MIDI itself. [INFERENCE] This is a
good fit for a "Live surface" mode in which the app is always running, and a poor fit for a
standalone preset.

---

## 6. LED feedback in plain mode (no SysEx)

- The rings follow plain CC on the knob's own channel on **USB2/USB3**. USB1 only makes the ring
  flash. [MANIFEST, measured 1.10.2026]
- Firmware 1.1.0 *"Add push toggle midi feedback"* and *"Add toggle color indicator"*. Firmware 0.6.0
  *"Improve MIDI feedback high traffic handling"*. [SRC] releases page. OXI does not document which
  port takes feedback; the USB2/USB3 finding is our own measurement.
- Colour cannot be changed by plain MIDI. Only the scene, Lua or Remote Mode can change it.
  [MANIFEST] [SRC: spec sheet has no plain-mode colour message]

---

## 7. Other people's projects

| Project | What it is | Use for us |
|---|---|---|
| https://github.com/charlesvestal/oxi-e16-lua | Lua scripts (Euclid, LFO×16, Chords, ModSeq, TB-3PO), the field notes, `tools/e16push.py` (scene/script upload without the OXI App), `tools/make_scene.py` (builds scenes from a template) | **The upload protocol and its encoder/CRC**: port them to Swift |
| https://github.com/charlesvestal/schwung | Ableton *Move* firmware extension that drives an E16 in Remote Mode and through Lua (`docs/E16_REMOTE.md`, `docs/SYSEX.md`, `src/shared/e16_protocol.mjs`, `tools/e16-lua/schwung.lua`, `docs/plans/2026-09-11-oxi-questions.md`) | Remote Mode in practice, pacing and corruption lessons, the Lua-as-display pattern |
| https://github.com/tsln-lab/oxi-e16-lua-api | Unofficial Starlight docs site for the Lua API (leds, controller, midi, slots, var, gotchas, open questions) | API reference. Note: its colour table predates 1.2 and calls the range a "0-100 rotation", which disagrees with charlesvestal's hardware finding of a palette index |
| https://github.com/brentvatne/oxi-e16-config | `generate-scene.js` that builds `.oxie16` from simple JSON, plus a Claude skill (SKILL.md) for the scene format and `.oxiindef` instrument definitions | Scene JSON generation, field defaults |
| https://github.com/buba447/OXI-E16-Patcher | Browser editor that copies encoders across pages and scenes; has `docs/oxie16-schema.json` | A JSON schema for `.oxie16` |
| perrinennen/oxi-e16 ("oxi e16 max4live"), SebastianSchlag/e16_utils | Empty, or only a LICENSE (checked through the GitHub API) | Nothing |
| https://llllllll.co/t/remote-control-of-oxi-e16-with-maxmsp/74110 | lines thread on Remote Mode from Max/MSP, where the spec link and the packing rule were worked out. The page returns 403 to bots; content known only through schwung's citation | Background |

No Ableton Remote Script and no working Max for Live device for the E16 were found. OXI's own Ableton
path is ordinary MIDI Map (there is a video "OXI E16 — Mapping to Ableton", listed at
https://equipboard.com/items/oxi-instruments-e16).

---

## 8. Does OXI publish formats or sources?

- **Firmware:** binaries only (`OXI_E16_1_3_0.syx`, 718,734 bytes) with release notes.
  [SRC] https://github.com/OXI-Instruments/OXI-E16-Releases (README: *"Here you can find all the
  firmware releases of the E16 with their respective release notes"*). Firmware sources are not
  published.
- **OXI App:** binaries and appcast at https://github.com/OXI-Instruments/OXI-Desktop-APP/releases.
  Closed source.
- **Remote Mode:** published as the Google Sheet (§5).
- **Lua API:** published as OXI's *Lua Scripting API Guide* and in manual chapter 6.
- **The scene file `.oxie16` and the scene-upload SysEx:** not published by OXI. They are known only
  through the community reverse engineering (§3), so they **may change with any firmware or app
  update**. The app's class name `E16SerializerV1` hints at a versioned format.
- Manual: https://drive.google.com/file/d/1yZn1i96nRkosn2o6eDlj5wzuErPQEe9N/view (linked from
  https://oxiinstruments.com/e16/). The copy on this Mac is older (Feb 2026).

---

## 9. Still unknown: test on the device

1. **The SysEx message behind "Run in the active scene on E16 (temporary)"** (firmware 1.3 live
   script loading). It is probably a kind-4 variant that runs at once without saving. To find it,
   log CoreMIDI while the OXI App does it (charlesvestal's method: a logging dylib in a re-signed
   copy, or a MIDI monitor on USB1). This is the key to installing or changing a script with no reload.
2. **Does a kind-1 page upload to the *active* slot take effect without re-entering the scene?**
   And does a PC on the PC Receive Channel re-enter the current scene cleanly?
3. **Whether Lua `controller.onSysex` receives custom SysEx with the OXI header on USB1, and its
   size limit.** Schwung's `schwung.lua` assumes it does.
4. **Whether the Lua `color` (0-99 index, or "0-100") is the same scale as the scene's `color`**.
   charlesvestal says yes (palette index, from hardware). tsln-lab's table is stale.
5. Whether `leds.updateByIndex` can override the ring of a **CC-type** control (not a Script control)
   on the normal view on 1.3. That decides whether "CC to Live, Lua for colour" works on one page.
6. The firmware-version reply layout (`03 00`), and the exact meaning of the encoder-level
   `output` value 12 seen in the scene files (the app shows it as "Page").
7. Whether Remote Mode on 1.3.0 (it was broken in 1.2) works over USB1 on macOS with Multi Port
   left On. [INFERENCE] It should: the Move problem was the Move's USB host, not macOS.

---

## 10. What this suggests for Oxi Controller [INFERENCE]

- **Presets = `.oxie16` JSON** (the format the OXI App uses), kept by Oxi Controller with extra
  metadata. Writing them and pushing them with the §3 upload makes them compatible with the OXI
  App both ways.
- **For live changes, use three layers:**
  1. *Values*: plain CC on USB2/USB3, already proven.
  2. *Colours, labels, title*: a resident Lua script fed by small SysEx messages (§4), with no
     reload.
  3. *Structure* (which CC, channel, type, range): a page upload (§3), then a scene re-entry.
     This is the only layer that is not seamless.
- **Optional "Surface" mode:** Remote Mode (§5) for full RGB and screen control, with the app doing
  all the mapping to AbletonOSC and Mackie.
- **Ports:** SysEx and the app session on **USB1**; value feedback on **USB2/USB3**. Open the
  CoreMIDI sources rather than the device. Expect the device to drop off for a few seconds and
  retry (manifest §1, §10).
- Close the OXI App while Oxi Controller uploads: it holds a session on USB1, and its own message is
  *"stop SysEx from other apps or devices before retrying"*.
