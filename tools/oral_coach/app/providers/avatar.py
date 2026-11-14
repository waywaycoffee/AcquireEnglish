from __future__ import annotations

import logging

import httpx

from ..config import Settings
from .base import AvatarCue

logger = logging.getLogger(__name__)


class NoneAvatar:
    name = "none"

    async def cue(self, text: str) -> AvatarCue:
        return AvatarCue(provider=self.name, action="none", text=text)


class LiveTalkingAvatar:
    name = "livetalking"

    def __init__(self, url: str):
        self.url = url.rstrip("/")

    async def cue(self, text: str) -> AvatarCue:
        # Do NOT POST /human without a WebRTC sessionid — LiveTalking returns
        # code:-1 ("session not found"). The App owns the /offer session and
        # should call /human after connect. We only probe readiness here.
        reachable = False
        if self.url:
            try:
                async with httpx.AsyncClient(timeout=4.0) as client:
                    health = await client.get(f"{self.url}/")
                    reachable = health.status_code < 500
            except Exception as exc:  # noqa: BLE001 — soft-fail for offline avatar
                logger.debug("livetalking probe skipped: %s", exc)
        return AvatarCue(
            provider=self.name,
            # App connects via WebRTC then speaks coach text with sessionid.
            action="livetalking_connect" if reachable else "livetalking_offline",
            text=text,
            livetalking_url=self.url,
        )


class MuseTalkAvatar:
    name = "musetalk"

    async def cue(self, text: str) -> AvatarCue:
        return AvatarCue(
            provider=self.name,
            action="speak_text",
            text=text,
        )


class LivePortraitAvatar:
    name = "liveportrait"

    async def cue(self, text: str) -> AvatarCue:
        return AvatarCue(
            provider=self.name,
            action="speak_text",
            text=text,
        )


def build_avatar(settings: Settings):
    name = settings.avatar_provider
    if name == "livetalking":
        return LiveTalkingAvatar(settings.livetalking_url)
    if name == "musetalk":
        return MuseTalkAvatar()
    if name == "liveportrait":
        return LivePortraitAvatar()
    return NoneAvatar()
