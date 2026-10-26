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

## The Anthropic key and the chat

*(v18, 26.10.2026.)* Every knob has a **prompt**: in the LIST view, the field where the note used to be. Write in
your own words what the knob should do and press Return. The CHAT beside the knobs opens and Claude answers.

**What Claude answers.** The app gives Claude a catalogue of everything a knob can do today (the TURN and PUSH roles of
the knob's SETUP) and asks for one of three verdicts:

- **POSSIBLE**: the roles that do it, with an **APPLY** button that sets them on the knob.
- **PARTLY**: what works now, and under *To make it possible* what is missing.
- **NOT YET · CAN BE BUILT** *(v19)*: the app cannot do it today but can be extended. Claude names the route: a new
  AbletonOSC handler on Live's API, acting as a Mackie Control unit, a Live keyboard shortcut, or MIDI Map.
- **IMPOSSIBLE**: only when no route can do it at all (Live exposes nothing for it, or the E16 cannot), and why.
  *(v18 called the zoom "impossible"; Marko: "it is possible ... with the Mackie protocol". v19 makes the difference.)*

Nothing Claude writes runs by itself. The app accepts only roles from its own list and changes a knob only when
APPLY is pressed. Answer back in the chat to go another round. Each knob keeps its own conversation (CLEAR starts
again), stored in `~/Library/Application Support/DJ Mantra Ableton Remote/chats.json`.

**Settings (⌘,).**
- **Choose key files…** opens the file dialog, several files at once. The files can be ordinary notes with other text
  in them: the key is found by its shape (`sk-ant-…`), and the words beside it become its title. This is the Keyring
  parser of MANTRA_MANIFEST `modules/keyring.md` §4, §6b and §10d.
- The keys picked are stored with their titles in `~/Library/Application Support/DJ Mantra Ableton Remote/keys.txt`
  (keyring v1 format, permissions 0600), never in this repository. A radio chooses the key in force. On screen a key
  is named only by its position and title, never shown.
- **The order a key is looked for:** `ANTHROPIC_API_KEY` in the environment, then the keys picked in Settings, then
  `keyring get anthropic`, then the notes in `~/Downloads/API` (files named Claude or Anthropic first).
- **Model:** Opus, Sonnet or Haiku. The app asks the API (`GET /v1/models`) for the newest model of that family once a
  session, so no model version is written in the code (`modules/model-names.md`).

**Which model** (measured 26.10.2026, the same three questions on each):

| | Simple ("turn = parameter I clicked, push = play/stop") | Tempo | Hard ("record a take, loop the last N bars") | Per question |
|---|---|---|---|---|
| Haiku 5.5 | right, 4.8 s | right, 6.6 s | "impossible", one confused sentence | ~0.05 cent |
| Sonnet 5.5 | right, 4.2 s | right, 7.5 s | "impossible", contradicts itself on loop length | ~0.7 cent |
| **Opus 5.5** | right, 4.8 s, suggests renaming the knob | right, 7.2 s, and advises a narrow tempo range | **"partly", accurate: map record by MIDI, loop by a new role** | ~1.5 cents |

Opus is the default. The point of the chat is an honest *possible / impossible*, and that is where Opus was clearly
better, at about a cent and a half a question.

**From the Terminal** (the same code as the window):

    "DJ Mantra Ableton Remote.app/Contents/MacOS/DJMantraAbletonRemote" --import ~/Downloads/API/HAIKU-KEY.txt
    "DJ Mantra Ableton Remote.app/Contents/MacOS/DJMantraAbletonRemote" --family opus --ask 6 "Turning this knob should change the tempo."

`--ask` opens no window and leaves the E16 alone. Little Snitch asks once whether the app may reach `anthropic.com`;
allow that domain.

## ZOOM (v20, 26.10.2026)

The TURN role **ZOOM** zooms the timeline of Live's arrangement: to the right zooms in, to the left zooms out. It
uses Live's own `Application.View.zoom_view`, the same call Live's Mackie Control script makes for Zoom + the
cursor keys, through a handler added to AbletonOSC (`/live/view/zoom_arrangement`, copy in `tools/AbletonOSC-view.py`).
Knob 15 has it. Tested in Live 12.4.6 on "01 Jai Ganesha Pahi Mam": four steps left went from bars 21–121 out to
1–673, two steps right came back in to about 33–289.

## Pages, fixed numbers, your own words, the ring (v21, 26.10.2026)

- **Fixed numbers.** Knob 1 turns CC 1 and pushes note 1, knob 16 is CC 16 and note 16. Page 2 goes on from 17, and so
  on. The numbers can no longer be changed; only the ring's colour and intensity, the name and the role can.
- **The last page.** A MIDI channel has 128 CC and 128 note numbers. CC 0 is bank select, and CC 120–127 are MIDI's
  channel mode messages (all notes off, reset controllers…), which a knob must never send. So a channel uses 1–112,
  7 pages of 16. After page 7 the numbers start again from 1 on channel 2, and so on through channel 16:
  **112 pages, 1,792 knobs.** The window shows the page, its numbers and its channel.
- **Turning the pages.** ◀ PAGE / PAGE ▶ / FIRST in the window. On the E16, hold Shift and turn knob 16.
- **No help knob.** Knob 16 is an ordinary knob now (Marko: "help is already written in this application").
- **TURN and PUSH columns** in the LIST view. The app writes what each one does; ✎ lets you write your own words over
  it (for example after a MIDI Map in Live: "filter cutoff, Bass"). An empty field gives the app's words back.
- **The ring.** Under RING: thirteen colours (twelve hues and white), any other colour from the colour picker, and the
  intensity from 10 to 100 %.
- Pushes are **momentary** by default: note on when pressed, off when released. Live's MIDI-mapped buttons then flip
  on every press.

## Next

1. The app itself (Swift, the camera's rail language): looks and presets on a page, edited live.
2. Ableton Live: AbletonOSC (as Ableton Assistant A1 uses it), MIDI, and Mackie Control (MANTRA_MACKIE) — combined, so a
   preset says what each knob does in Live and its ring shows Live's value.
3. A Lua script on the E16 (firmware 1.3) for live colours and labels without Remote Mode's takeover (RESEARCH.md §4).

Third-party knowledge: OXI's Remote Mode sheet; charlesvestal/schwung and charlesvestal/oxi-e16-lua (packing, ACK,
upload protocol). Nothing of theirs is copied into this repository.
