# Take over Oxi Controller

1. Read `momentaryupdates.md` (his words), then `RESEARCH.md`, then MANTRA_MANIFEST `modules/oxi-e16.md`.
2. The E16 is on USB with three CoreMIDI ports: SysEx and Remote Mode on **USB1** ("OXI E16 Port 1"); ring values as
   plain CC on **USB2/USB3** on the knob's own channel.
3. The Pixel 7 camera (Mantra Manual Camera) looks at the E16: `adb -s 41241FDH2S10SJ exec-out screencap -p` shows the
   device's rings and screen. Use it instead of asking Marko to look.
4. Always end a Remote Mode test with `build/e16looks exit`, or the E16 stays blank and Live loses it.
5. Open: why the ACK (`06 53`) is not recognised (the device does enter) — see LESSONS 1.

## v18 (26.10.2026): prompt, chat, Settings

The note field is now the knob's **prompt**. A chat per knob (app/Chat.swift) asks Claude whether the app can do
what the prompt says, against the catalogue of TURN/PUSH roles. Settings (app/Keys.swift) holds the Anthropic key by
file picker, using the Keyring parser of MANTRA_MANIFEST, and the model family (newest model resolved from
/v1/models). How it works and why Opus is the default: README, "The Anthropic key and the chat". Tested from the
Terminal with `--import` and `--ask` on Haiku, Sonnet and Opus. The window itself has not yet been tried by Marko.

## v19–v24 (26.10.2026): verdicts, ZOOM, fixed numbers, own screen, pages, profiles

- **v19:** the chat has four verdicts (possible / partly / buildable / impossible). The system prompt lists the routes the app can be extended through.
- **v20:** ZOOM is a turn role. It is sent straight to AbletonOSC on 11000, because the A1 router on 11002 is missing when a1_ears.py holds 11001 (see LESSONS). The handler is in AbletonOSC view.py, and a copy is in tools/AbletonOSC-view.py.
- **v21:** knob i on page p sends CC/note (p·16+i) mod 112 + 1 on channel (p·16+i)/112 + 1, giving 112 pages. The TURN/PUSH columns carry ✎ for Marko's own words. Each ring has a colour and an intensity.
- **v22:** app/Screen.swift draws the 128×64 framebuffer: two 5-letter lines a knob, and Live's answer shown big for 2 s.
- **v23:** tap Shift twice for the page turner (Marko's name, 26.10.2026; v25 makes knob 16 red). Knob 16 turns the pages, pushes 1–15 jump to a page, Shift twice exits.
- **v24:** PROFILES… → PLACE puts a profile on a page. Page names are kept in layout.json, loaded at start.
- **Test door** (UDP 11010): `turn N STEP`, `push N`, `release N`, `shift 0|1`, `present`, `role N ROLE`, `nav`, `place NAME PAGE`.
- **Open for Marko's hand:** the picker and PLACE on the E16, a real MIDI Map in Live with the new numbers, and the ring colours.

## v27 (29.10.2026): E16 FOR DAVINCI RESOLVE

app/Resolve.swift: ResolveMixer (Python through the DaVinci Resolve Actions router, POST 127.0.0.1:8940/run, its
`result`) and the Engine extension (resolveTurn, resolvePress, resolveCells, resolveRings, resolveRefresh). Engine hooks
when `resolveMode`: heard() (turns/pushes; Shift and the page turner kept), drawLabels, flushRings, goTo (refresh).
App.swift: --resolve or a bundle identifier with "resolve" turns it on, refresh every 2 s. build.sh copies the app as
"E16 for DaVinci Resolve (Mantra).app". Resolve facts (measured on his timeline): SetTrackEnable / SetClipEnabled answer
False for audio, so MUTE/SOLO turn the clips down to −100 dB and give back their own levels (kept in the mixer);
AudioVolume is dB, AudioPan −100…100. No Mackie Control in Resolve 21.1; no level meters in its scripting.
Test door: knob numbers are 1-based for turn and push (push 9 = knob 9 = SOLO of the third track).

## v31, 31.10.2026: the first row ON OFF … name … TOP PERMISSIONS ✕

`TopRow` in app/App.swift above both views; TOP in UserDefaults "onTop" (each bundle its own); PERMISSIONS moved there
from the button row; ✕ closes the window only (the app no longer quits with its last window; OFF quits). Accessibility
identifiers `off`, `top`, `permissions`, `close`: a build can quit a running copy through `off`.

## v32, 31.10.2026: press = note, turn = CC
Resolve.swift resolveTurn: a turn never calls setSolo/setMute (only resolvePress does); knob 1 turned = scrollTimeline
(12 frames a click, 1 with Shift; pending turns added up while Resolve answers; ResolveMixer.movePlayhead). Tested via the
test door (UDP 11010 "turn 1 3"): +36 frames. Found: Ableton Live Actions' MIDI to key stroke row 1 (CC 1 on "Port 1" =
System volume) also hears knob 1 and moves the Mac's volume: two apps on one E16 port.

## v34, 31.10.2026: MIDI to keyboard
app/ResolveHotkeys.swift: Marko's keyboard profile (keyboard.preset.xml, a Qt data stream, re-read on change) + the knob map
~/.config/e16-resolve-map.json (knob -> press/right/left action id; first layout written on first use) -> the key posted to
Resolve's pid; the screen "(Play/Stop) SPACE" or "(Solo Tracks) NO KEY"; missing ones in ~/.config/e16-resolve-missing.json.
Unmapped knobs/directions keep the mixer (volume, pan, knob 1's playhead). tools/resolve_keys.py = the same reader in Python.
