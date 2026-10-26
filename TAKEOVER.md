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
