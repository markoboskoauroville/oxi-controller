# DJ Mantra Ableton Remote for OXI E16

**The OXI E16 as the Mac's own controller for Ableton Live.** (Marko, 26.10.2026: "can you name this project DJ Mantra
Ableton Remote for Oxi E16?") The app holds the E16 in Remote Mode and is its brain: every knob has a setup (name,
colour, what a turn sends: CC, channel, range, speed; what a push does: toggle or momentary, a note or a CC), the
rings and the screen are drawn from the values, and the result goes to Live through the app's own MIDI port
**"DJ Mantra Remote"**. Setups are saved and recalled. **PRESENT THE OXI** is the light show: the sixteen knobs as a
4 × 4 picture, 22 pictures crossfading in turning colours, the same picture on the screen. The app's name is on the
E16's screen at every start, its signature.

- App: `./build.sh` → /Applications/DJ Mantra Ableton Remote.app (v1, signed "Mantra Apps").
- Tool: `build/e16looks seed | list | show NAME | cycle 4 | present [s] | exit`.
- Setups: ~/Library/Application Support/DJ Mantra Ableton Remote/setups/<NAME>.json.

---

# Oxi Controller

A Mac app (Swift) for the **OXI Instruments E16**: presets the E16 can load to drive **Ableton Live**, with every change
reaching the device at once (the OXI App edits a copy and needs a "send scene"). In the star under **Ableton Live**.
Requests word for word: `momentaryupdates.md`. What is known about the device and where it comes from: `RESEARCH.md`
and MANTRA_MANIFEST `modules/oxi-e16.md`.

## What works (26.10.2026)

- **Looks: store and recall the device's visible side.** `tools/e16looks` (Swift, CoreMIDI) keeps looks as JSON in
  `~/Library/Application Support/Oxi Controller/looks/` — a 16-character title, sixteen 4-character labels, sixteen
  rings (RGB 0-127 and how much is lit) — and puts one on the E16 through **Remote Mode** (SysEx on USB1:
  `06 55` enter, `06 03` labels, `06 04` rings, `06 00` exit). Proven through the camera: OCEAN and LIVE MIX recalled,
  rings and screen changed at once.
- **A moving picture:** `tools/e16wave` sends plain CC 1-16 on USB3 (a sine around the rings) — the camera's stress test.

Build: `swiftc -O Sources/E16/E16Remote.swift tools/e16looks/main.swift -o build/e16looks`, then
`build/e16looks seed | list | show NAME | cycle 4 | exit`. `exit` gives the device back to its scene: without it the
E16 stays blank.

## Next

1. The app itself (Swift, the camera's rail language): looks and presets on a page, edited live.
2. Ableton Live: AbletonOSC (as Ableton Assistant A1 uses it), MIDI, and Mackie Control (MANTRA_MACKIE) — combined, so a
   preset says what each knob does in Live and its ring shows Live's value.
3. A Lua script on the E16 (firmware 1.3) for live colours and labels without Remote Mode's takeover (RESEARCH.md §4).

Third-party knowledge: OXI's Remote Mode sheet; charlesvestal/schwung and charlesvestal/oxi-e16-lua (packing, ACK,
upload protocol). Nothing of theirs is copied into this repository.
