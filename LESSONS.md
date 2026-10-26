# Lessons

1. **The ENTER ACK was not recognised, yet the device entered** (26.10.2026): the screen and rings went dark at once.
   The code reads CoreMIDI's MIDI 1.0 UMP SysEx packets; the reply may come split differently or on another port.
   Until found, e16looks sends ENTER and goes on. Look at the device (the camera), not only at the reply.
2. **Labels and rings need the 8-to-7 packing too**: a leading 0 byte before every 7 bytes. Without it nothing shows
   (schwung E16_REMOTE.md; the bytes never set bit 7, so the header is always 0 there, but it must be there).
3. **Exit or it stays blank**: Remote Mode holds until EXIT (`06 00`) or a power cycle.

## A pointer out of withUnsafePointer reads a copy that is gone (26.10.2026)

`withUnsafePointer(to: packet.pointee.words) { $0 }` hands out a pointer to a temporary copy of the tuple; used after
the closure it read 0 for every word. Every turn, every push and the Remote Mode ACK were lost the whole day ("no ACK
recognised", the knobs did nothing in the app), while the device itself worked. Copy the words out inside:
`withUnsafeBytes(of: packet.pointee.words) { Array($0.bindMemory(to: UInt32.self).prefix(count)) }`. Proof it works:
`e16looks show` now says "remote mode: entered (ACK)".

## Live's Python objects are new at every access (26.10.2026)

`song.view.selected_parameter` returns a fresh wrapper each time: `a is b` is false for the same parameter, and
`list.index()` may miss it. Tell Live objects apart by `_live_ptr` (the C++ object behind the wrapper). Found when
knob 4's parameter pointer was reset at every step.

## 26.10.2026: when Live starts, whoever takes UDP 11001 first decides whether the router exists

Live was opened again for the ZOOM test. The star's `MANTRA_STAR/a1_ears.py` (started by Hammerspoon) took 11001
before Ableton Live Actions did, so A1's router on 11002 never came up. Every call this app sent to 11002 went
nowhere, and Live's log showed nothing. A command that needs no answer (ZOOM) now goes straight to AbletonOSC on
11000 (`Live.sendDirect`). The roles that read an answer (SELECTED, CLIP PITCH, PARAMETER STEP, the status line)
still need the router, so they need Live Actions' A1 to hold 11001. Test first: `lsof -nP -iUDP | grep 1100`
should show the router listening on 11002.
