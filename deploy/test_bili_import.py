import asyncio
from app.link_import import import_link


async def main() -> None:
    p = await import_link("https://www.bilibili.com/video/BV1BsWwz7Eeo/")
    print(p.external_id)
    print(p.title)
    print("en", bool(p.subtitle_en_srt), "zh", bool(p.subtitle_zh_srt))


if __name__ == "__main__":
    asyncio.run(main())
