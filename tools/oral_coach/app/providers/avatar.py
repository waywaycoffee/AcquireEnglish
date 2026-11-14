from __future__ import annotations

from ..config import Settings
from .base import AvatarCue


class NoneAvatar:
    name = 'none'

    async def cue(self, text: str) -> AvatarCue:
        return AvatarCue(provider=self.name, action='none', text=text)


class LiveTalkingAvatar:
    name = 'livetalking'

    def __init__(self, url: str):
        self.url = url.rstrip('/')

    async def cue(self, text: str) -> AvatarCue:
        # App already has WebRTC LiveTalkingClient; sidecar returns a cue so
        # Flutter can call /human with the coach reply (same pattern as today).
        return AvatarCue(
            provider=self.name,
            action='livetalking_human',
            text=text,
            livetalking_url=self.url,
        )


class MuseTalkAvatar:
    name = 'musetalk'

    async def cue(self, text: str) -> AvatarCue:
        # LiveTalking commonly wraps MuseTalk; dedicated MuseTalk HTTP can replace this.
        return AvatarCue(
            provider=self.name,
            action='speak_text',
            text=text,
        )


class LivePortraitAvatar:
    name = 'liveportrait'

    async def cue(self, text: str) -> AvatarCue:
        return AvatarCue(
            provider=self.name,
            action='speak_text',
            text=text,
        )


def build_avatar(settings: Settings):
    name = settings.avatar_provider
    if name == 'livetalking':
        return LiveTalkingAvatar(settings.livetalking_url)
    if name == 'musetalk':
        return MuseTalkAvatar()
    if name == 'liveportrait':
        return LivePortraitAvatar()
    return NoneAvatar()
