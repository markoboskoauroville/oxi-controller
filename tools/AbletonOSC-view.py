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
        def selected_parameter_info():
            p = self.song.view.selected_parameter
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
            return selected_parameter_info()[1]

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
