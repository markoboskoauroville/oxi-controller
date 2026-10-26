# Oxi Controller: the requests, word for word

## 26.10.2026 — the start (from the Mantra Manual Camera session in ~/Developer/claude-code)

> "already developed controlling of this Oxi device A16 over the USB in my computer, so you can animate the LED rings if you want to have some kind of moving picture. You can check for the drop frames or whatever you need to check when the picture is not static. If it's not developed, then you need to develop it. You need to check controlling the Oxi over MIDI: its colors of its LEDs. The next project is Oxi Presets Maker, which is going to improve the function of the original Oxi app, which is on my computer. The idea is to create an app which is going to store presets for my Oxi to control Ableton Live. I will set up different presets, and then I'm going to load them. It will then adapt to my workflow to work with Ableton Live through this Oxi device. We are going in that direction. Make a base for this kind of app. For sure, this app needs to have real-time response. While changing the settings, which the original Oxi doesn't have, you can research Oxi. You can reverse engineer it. Maybe it's open source. Maybe some other people also build controllers for this beautiful device called Oxi E16, which is right on the lens on the camera. So you can play with it" (Marko, 26.10.2026)

> "this goes under the section of Ableton Live. We can call it Oxi Controller" (Marko, 26.10.2026)

> "there are manuals and documentation about this app online and make a repository for this device in GitHub, and we need to develop the software to control it" (Marko, 26.10.2026)

1. The Oxi E16's LEDs (ring colours) driven over MIDI from the Mac: checked, and animated for the camera's moving-picture test. — **Status:** done 26.10.2026: `tools/e16wave` (plain CC on USB3, the rings' values); colours through Remote Mode (5).
2. OXI CONTROLLER (first called Oxi Presets Maker): a Mac app that stores and loads presets for the E16 to control Ableton Live, better than the OXI App: settings change in real time. Research first: the manuals and documentation online, the OXI App, whether it is open source, other people's controllers; reverse engineer what is needed. — **Status:** research done (RESEARCH.md): the OXI App is Flutter, closed, uploads whole scenes on USB1; the upload protocol is reverse-engineered (charlesvestal/oxi-e16-lua e16push.py); Remote Mode is published by OXI; Lua on firmware 1.3 can set colours and labels live. The app itself is next.
3. A GitHub repository for the device and its software. — **Status:** this repository, markoboskoauroville/oxi-controller (private).
4. In the star under Ableton Live, named Oxi Controller. — **Status:** asked.

> "first test with this app is: can you store different configurations and recall different configurations? You find your own configurances. It will be good if they can be actually visual, maybe changing the colors of rings or text display on the screen. Basically controlling visual aspects of this device" (Marko, 26.10.2026)

> "then the OSC plugin for Ableton Live and MIDI protocol. We need to combine everything in Oxi to be able to control our Ableton device" (Marko, 26.10.2026)

5. FIRST TEST: store several configurations and recall them, configurations chosen here, and visible on the device — the rings' colours, the text on its display: the device's visual side under the app's control. — **Status:** PASSED 26.10.2026 07:30: `tools/e16looks` stores looks as JSON (title, 16 labels, 16 RGB rings) and recalls them through Remote Mode; four of my own (SUNRISE, OCEAN, FOREST, LIVE MIX); OCEAN and LIVE MIX recalled and photographed through the Pixel 7 camera — rings and screen changed at once. Then given back (EXIT).
6. THEN: Ableton Live through OSC (AbletonOSC, already on the Mac for Ableton Assistant A1) and MIDI, all combined in Oxi Controller, so the E16 drives Live. — **Status:** asked.

> "m key is also very important to control because it can control parts of Ableton Live, which otherwise we cannot control. M key from the protocol: we already work with it" (Marko, 26.10.2026; read as MACKIE, the Mackie Control protocol of ~/Developer/MANTRA_MACKIE)

7. Mackie Control too: Oxi Controller speaks the Mackie protocol to Live (MANTRA_MACKIE already does, through IAC to Live's MackieControl), for the parts of Live that nothing else reaches. — **Status:** asked, with 6.

> "please search other rappers which already work with E16, if there are any, and learn from their experience" (Marko, 26.10.2026; "rappers" read as repositories, then:)
>
> "Amen. Repro. Repro. Repro. Repro. No triper" (Marko, 26.10.2026, dictated: "repo", repositories)

8. Other people's repositories that already work with the E16 (charlesvestal/schwung, charlesvestal/oxi-e16-lua and whatever else exists), read for what they learned. — **Status:** in the research (RESEARCH.md).

> "also, as a step toward making the Oxi E16 application, Swift One, control all its functions. Basically, make a setup for each of its knobs: what push does, etc. What color is the LED right now? Just use it to test the picture of the camera. Please. Now, just make a light show with my LEDs. They need to go in different directions, making you imagine you have a screen of 4 by 4 pixels, so 16 pixels. Just choose 22 ASCII art images and just crossfade between each of them with different colors. For now, let's make this in app. We can call this mode "Present the Oxi." Then it is going to do this kind of different effects, like entertaining the audience, and also entertaining the dot matrix display at the top. You can also display the same ASCII art that is down on the knobs. "Entertaining mode, please."" / "first project for Oxi, and then we continue to be useful, same as the Oxi app. You can open it on my computer, click on it, and research what it has. There is also a manual for it online, and you can research how it works and all the functions that are there. All of these need to be in our app" (Marko, 26.10.2026)

9. PRESENT THE OXI ("Entertaining mode"): the 16 knobs as a 4 × 4 picture, 22 ASCII-art pictures crossfaded in changing colours, moving in different directions; the same picture on the E16's display; seen through the camera (the Pixel looks at the E16). Then: every function of OXI's own app and the manual in our Swift app, a setup per knob (turn, push …). — **Status:** in work.
