from functools import partial
from typing import Optional, Tuple, Any
from .handler import AbletonOSCHandler

class ViewHandler(AbletonOSCHandler):
    def __init__(self, manager):
        super().__init__(manager)
        self.class_identifier = "view"

    def init_api(self):
        def get_selected_scene(params: Optional[Tuple] = ()):
            return (list(self.song.scenes).index(self.song.view.selected_scene),)

        def get_selected_track(params: Optional[Tuple] = ()):
            return (list(self.song.tracks).index(self.song.view.selected_track),)

        def get_selected_clip(params: Optional[Tuple] = ()):
            return (get_selected_track()[0], get_selected_scene()[0])
        
        def get_selected_device(params: Optional[Tuple] = ()):
            return (get_selected_track()[0], list(self.song.view.selected_track.devices).index(self.song.view.selected_track.view.selected_device))

        def set_selected_scene(params: Optional[Tuple] = ()):
            self.song.view.selected_scene = self.song.scenes[params[0]]

        def set_selected_track(params: Optional[Tuple] = ()):
            self.song.view.selected_track = self.song.tracks[params[0]]

        def set_selected_clip(params: Optional[Tuple] = ()):
            set_selected_track((params[0],))
            set_selected_scene((params[1],))

        def set_selected_device(params: Optional[Tuple] = ()):
            device = self.song.tracks[params[0]].devices[params[1]]
            self.song.view.select_device(device)
            return params[0], params[1]

        # DJ Mantra Ableton Remote (Marko Bosko, 26.10.2026): the parameter last clicked in Live, read and turned by a
        # knob of the OXI E16 ("I cannot change parameters by selecting them")
        # the parameter knob 4 has stepped to (None: Live's own selected parameter); a new click in Live resets it
        self._dj_param = None
        self._dj_seen = None
        # the status line (Marko, 26.10.2026: "this status line is always disappearing. Please keep it always on
        # screen"): Live fades its messages, so the last one is written again every 15 ticks (about 1.5 s)
        self._dj_line = ""
        self._dj_keeping = False
        # a reload of AbletonOSC makes a new handler while the old one's loop goes on rewriting its old line (seen
        # 26.10.2026: "off" did not take): every old ViewHandler is silenced, and a loop runs only for the newest one
        import gc
        for old in gc.get_objects():
            if type(old).__name__ == "ViewHandler" and old is not self and hasattr(old, "_dj_line"):
                old._dj_line = ""
                old._dj_line_on = False
        self.manager._dj_view = self

        def keep_line():
            if self._dj_line and getattr(self.manager, "_dj_view", None) is self:
                self.manager.show_message(self._dj_line)
                self.manager.schedule_message(15, keep_line)
            else:
                self._dj_keeping = False

        # switched off and on at will (Marko, 26.10.2026: "Some kind of closing of that status with my own will")
        self._dj_line_on = getattr(self.manager, "_dj_line_on", True)

        def set_status_line(params: Optional[Tuple] = ()):
            on = bool(int(params[0])) if params else (not self._dj_line_on)
            self._dj_line_on = on
            self.manager._dj_line_on = on
            if not on:
                self._dj_line = ""
                self.manager.show_message("")
            return (1 if on else 0,)

        self.osc_server.add_handler("/live/view/set/status_line", set_status_line)

        # Automation Arm (song.session_automation_record): AbletonOSC's song handler does not know it
        # (log 26.10.2026: "Unknown OSC address: /live/song/get/session_automation_record")
        def set_automation_arm(params: Optional[Tuple] = ()):
            self.song.session_automation_record = bool(int(params[0])) if params else (not self.song.session_automation_record)
            return (1 if self.song.session_automation_record else 0,)

        self.osc_server.add_handler("/live/view/set/automation_arm", set_automation_arm)
        self.osc_server.add_handler("/live/view/get/automation_arm", lambda params=(): (1 if self.song.session_automation_record else 0,))

        def say(line):
            if not self._dj_line_on:
                return
            self._dj_line = line
            self.manager.show_message(line)
            if not self._dj_keeping:
                self._dj_keeping = True
                self.manager.schedule_message(15, keep_line)

        def key(p):
            # Live hands out a new Python wrapper at every access: the object behind it is told by its _live_ptr
            return getattr(p, "_live_ptr", None) if p is not None else None

        def current_parameter():
            live = self.song.view.selected_parameter
            if key(live) != self._dj_seen:
                self._dj_seen = key(live)
                self._dj_param = None
            return self._dj_param if self._dj_param is not None else live

        def selected_parameter_info():
            p = current_parameter()
            if p is None:
                return None, ("", "", "")
            owner = p.canonical_parent
            name = getattr(owner, "name", "")
            if owner is not None and type(owner).__name__ == "MixerDevice":
                name = getattr(owner.canonical_parent, "name", "") + " MIXER"
            return p, (name, p.name, str(p))

        def get_selected_parameter(params: Optional[Tuple] = ()):
            p, info = selected_parameter_info()
            if p is None:
                return info
            return info + (float(p.value), float(p.min), float(p.max))

        def step_parameter(params: Optional[Tuple] = ()):
            # stepping again shows the line again (closed by a push of knob 4 while it is not needed)
            self._dj_line_on = True
            self.manager._dj_line_on = True
            base = current_parameter()
            if base is None:
                # nothing clicked yet: the selected track's selected device (or its first), from its first parameter
                track = self.song.view.selected_track
                device = track.view.selected_device or (track.devices[0] if len(track.devices) else None)
                if device is None or not len(device.parameters):
                    return ("", "", "")
                self._dj_param = device.parameters[0]
                base = self._dj_param
            device = base.canonical_parent
            plist = list(getattr(device, "parameters", []))
            if not plist:
                return selected_parameter_info()[1]
            keys = [key(x) for x in plist]
            i = keys.index(key(base)) if key(base) in keys else 0
            n = int(params[0]) if params else 1
            self._dj_param = plist[max(0, min(len(plist) - 1, i + (1 if n > 0 else -1)))]
            p, info = selected_parameter_info()
            where = "%d/%d" % (keys.index(key(p)) + 1 if key(p) in keys else 0, len(plist))
            # Live's square stays on the clicked parameter (no script can move it): Live's status bar says where knob 4 is
            say("\u25b6 %s \u00b7 %s \u00b7 %s \u00b7 %s   (OXI E16 knob 4; knob 2 turns it)" % (info[0], info[1], info[2], where))
            return info + (where,)

        self.osc_server.add_handler("/live/view/step_parameter", step_parameter)

        def nudge_selected_parameter(params: Optional[Tuple] = ()):
            p, info = selected_parameter_info()
            if p is None or not p.is_enabled:
                return info
            step = float(params[0]) if params else 1.0
            if p.is_quantized:
                v = p.value + (1 if step > 0 else -1)
            else:
                v = p.value + (p.max - p.min) / 127.0 * step
            p.value = max(p.min, min(p.max, v))
            info = selected_parameter_info()[1]
            say("\u25b6 %s \u00b7 %s \u00b7 %s   (OXI E16 knob 2)" % info)
            return info

        # DJ Mantra Ableton Remote (26.10.2026, Marko: "make a special case for pitch sliders"): the pitch of the clip in
        # Clip View (song.view.detail_clip), Transpose and Detune as one number of cents
        def clip_pitch_info(clip):
            cents = clip.pitch_coarse * 100 + clip.pitch_fine
            return (clip.name, "%+d st %+d ct" % (clip.pitch_coarse, clip.pitch_fine), float(cents))

        def get_clip_pitch(params: Optional[Tuple] = ()):
            clip = self.song.view.detail_clip
            if clip is None:
                return ("", "NO CLIP IN CLIP VIEW", 0.0)
            if not clip.is_audio_clip:
                return (clip.name, "A MIDI CLIP HAS NO PITCH", 0.0)
            return clip_pitch_info(clip)

        def nudge_clip_pitch(params: Optional[Tuple] = ()):
            clip = self.song.view.detail_clip
            if clip is None or not clip.is_audio_clip:
                return get_clip_pitch()
            cents = clip.pitch_coarse * 100 + clip.pitch_fine + float(params[0] if params else 0)
            cents = max(-4850.0, min(4849.0, cents))
            coarse = int(round(cents / 100.0))
            fine = int(round(cents - coarse * 100))
            clip.pitch_coarse = max(-48, min(48, coarse))
            clip.pitch_fine = max(-50, min(49, fine))
            return clip_pitch_info(clip)

        self.osc_server.add_handler("/live/view/get/clip_pitch", get_clip_pitch)
        self.osc_server.add_handler("/live/view/nudge_clip_pitch", nudge_clip_pitch)
        self.osc_server.add_handler("/live/view/get/selected_parameter", get_selected_parameter)
        self.osc_server.add_handler("/live/view/nudge_selected_parameter", nudge_selected_parameter)

        self.osc_server.add_handler("/live/view/get/selected_scene", get_selected_scene)
        self.osc_server.add_handler("/live/view/get/selected_track", get_selected_track)
        self.osc_server.add_handler("/live/view/get/selected_clip", get_selected_clip)
        self.osc_server.add_handler("/live/view/get/selected_device", get_selected_device)
        self.osc_server.add_handler("/live/view/set/selected_scene", set_selected_scene)
        self.osc_server.add_handler("/live/view/set/selected_track", set_selected_track)
        self.osc_server.add_handler("/live/view/set/selected_clip", set_selected_clip)
        self.osc_server.add_handler("/live/view/set/selected_device", set_selected_device)
        
        self.osc_server.add_handler('/live/view/start_listen/selected_scene', partial(self._start_listen, self.song.view, "selected_scene", getter=get_selected_scene))
        self.osc_server.add_handler('/live/view/start_listen/selected_track', partial(self._start_listen, self.song.view, "selected_track", getter=get_selected_track))
        self.osc_server.add_handler('/live/view/stop_listen/selected_scene', partial(self._stop_listen, self.song.view, "selected_scene"))
        self.osc_server.add_handler('/live/view/stop_listen/selected_track', partial(self._stop_listen, self.song.view, "selected_track"))
