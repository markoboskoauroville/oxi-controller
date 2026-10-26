# Take over Oxi Controller

1. Read `momentaryupdates.md` (his words), then `RESEARCH.md`, then MANTRA_MANIFEST `modules/oxi-e16.md`.
2. The E16 is on USB with three CoreMIDI ports: SysEx and Remote Mode on **USB1** ("OXI E16 Port 1"); ring values as
   plain CC on **USB2/USB3** on the knob's own channel.
3. The Pixel 7 camera (Mantra Manual Camera) looks at the E16: `adb -s 41241FDH2S10SJ exec-out screencap -p` shows the
   device's rings and screen. Use it instead of asking Marko to look.
4. Always end a Remote Mode test with `build/e16looks exit`, or the E16 stays blank and Live loses it.
5. Open: why the ACK (`06 53`) is not recognised (the device does enter) — see LESSONS 1.
