# Lessons

1. **The ENTER ACK was not recognised, yet the device entered** (26.10.2026): the screen and rings went dark at once.
   The code reads CoreMIDI's MIDI 1.0 UMP SysEx packets; the reply may come split differently or on another port.
   Until found, e16looks sends ENTER and goes on. Look at the device (the camera), not only at the reply.
2. **Labels and rings need the 8-to-7 packing too**: a leading 0 byte before every 7 bytes. Without it nothing shows
   (schwung E16_REMOTE.md; the bytes never set bit 7, so the header is always 0 there, but it must be there).
3. **Exit or it stays blank**: Remote Mode holds until EXIT (`06 00`) or a power cycle.
