import asyncio
from app.audio_extract import extract_audio_for_url


async def main() -> None:
    path = await extract_audio_for_url(
        "https://www.bilibili.com/video/BV1BsWwz7Eeo/",
        max_seconds=20,
    )
    print("ok", path, path.stat().st_size)


if __name__ == "__main__":
    asyncio.run(main())
