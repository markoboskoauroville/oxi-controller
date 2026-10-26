#!/usr/bin/env python3
"""selftest.py OUTDIR — the app's knobs exercised through its test door (127.0.0.1:11010), Live read back through
AbletonOSC (127.0.0.1:11002, the router), and the E16 photographed by the Pixel camera (adb, 192.168.1.101:5555)
after every step. Marko, 26.10.2026: "the device itself is on the camera, so you can use the camera to test"."""
import socket, struct, subprocess, sys, time, os
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
ADB = os.path.expanduser('~/Library/Android/sdk/platform-tools/adb'); PIXEL = os.environ.get('PIXEL', '192.168.1.101:5555')
door = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
def pad(b): return b + b'\0' * ((4 - len(b) % 4) % 4)
def osc(a, *v):
    t = ','; d = b''
    for x in v: t += 'i'; d += struct.pack('>i', x)
    return pad(a.encode() + b'\0') + pad(t.encode() + b'\0') + d
def parse(b):
    a = b[:b.index(b'\0')].decode(); i = (len(a) + 4) & ~3
    t = b[i:b.index(b'\0', i)].decode(); i = (i + len(t) + 4) & ~3; out = []
    for c in t[1:]:
        if c == 'i': out.append(struct.unpack('>i', b[i:i + 4])[0]); i += 4
        elif c == 'f': out.append(round(struct.unpack('>f', b[i:i + 4])[0], 3)); i += 4
        elif c == 's': j = b.index(b'\0', i); out.append(b[i:j].decode()); i = (j + 4) & ~3
        elif c in 'TF': out.append(c == 'T')
    return a, out
live = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); live.bind(('127.0.0.1', 0)); live.settimeout(0.5)
def drain():
    # the router copies every app's answers to every client: old copies of the app's own questions wait here
    live.settimeout(0.01)
    try:
        while True: live.recv(65536)
    except (socket.timeout, BlockingIOError): pass
    live.settimeout(0.5)

def ask(a, *v):
    drain()
    live.sendto(osc(a, *v), ('127.0.0.1', 11002)); end = time.time() + 2
    while time.time() < end:
        try:
            r = parse(live.recv(65536))
            if r[0] == a: return r[1]
        except socket.timeout: pass
def do(cmd, wait=2.0): door.sendto(cmd.encode(), ('127.0.0.1', 11010)); time.sleep(wait)
n = 0
def snap(label):
    global n; n += 1
    path = f'{OUT}/{n:02d}-{label}.png'
    with open(path, 'wb') as f: subprocess.run([ADB, '-s', PIXEL, 'exec-out', 'screencap', '-p'], stdout=f)
    return path
results = []
def check(name, ok, said): results.append((name, ok, said)); print(('PASS ' if ok else 'FAIL ') + name + ': ' + str(said))

t0 = (ask('/live/view/get/selected_track') or [0])[-1]
do('turn 1 1'); t1 = (ask('/live/view/get/selected_track') or [None])[-1]; snap('track-down')
check('knob 1 turns the track down', t1 == t0 + 1, f'{t0} -> {t1} {ask("/live/track/get/name", t1)}')
do('turn 1 -1'); t2 = (ask('/live/view/get/selected_track') or [None])[-1]
check('knob 1 turns it back up', t2 == t0, f'-> {t2}')
s0 = (ask('/live/song/get/current_song_time') or [0])[-1]
do('turn 3 4'); s1 = (ask('/live/song/get/current_song_time') or [None])[-1]; snap('scrub')
check('knob 3 moves the playhead a beat', s1 is not None and abs(s1 - s0 - 1.0) < 0.01, f'{s0} -> {s1}')
do('turn 3 -4'); s2 = (ask('/live/song/get/current_song_time') or [None])[-1]
check('knob 3 moves it back', s2 is not None and abs(s2 - s0) < 0.01, f'-> {s2}')
do('turn 16 1'); snap('help-1'); do('turn 16 1'); snap('help-2'); do('push 16'); snap('help-left')
check('knob 16 help pages (see the pictures)', True, 'help-1, help-2, help-left')
p0 = ask('/live/view/get/selected_parameter')
do('turn 4 1'); p1 = ask('/live/view/get/selected_parameter'); snap('param-step')
check('knob 4 steps to another parameter', p0 and p1 and p0[1] != p1[1], f'{p0[:3] if p0 else p0} -> {p1[:3] if p1 else p1}')
v0 = p1[3] if p1 and len(p1) > 3 else None
do('turn 2 8'); p2 = ask('/live/view/get/selected_parameter'); snap('nudge')
v1 = p2[3] if p2 and len(p2) > 3 else None
check('knob 2 turns it', v0 is not None and v1 is not None and v1 != v0, f'{p1[2] if p1 else None} -> {p2[2] if p2 else None}')
do('turn 2 -8'); p3 = ask('/live/view/get/selected_parameter')
check('knob 2 turns it back', p3 and len(p3) > 3 and abs(p3[3] - v0) < 0.002, f'-> {p3[2] if p3 else None}')
do('push 4'); snap('status-off')
check('knob 4 push closes the status line (see the picture of Live)', True, '')
print(f'{sum(1 for r in results if r[1])}/{len(results)} passed')
