# course-schema

AcquireEnglish 三端共用的课程包协议。

- `course.schema.json` — JSON Schema 定义
- `examples/` — 示例课程清单

客户端（Flutter / Web）与 `services/api` 都应按此结构读写课程元数据。视频与字幕文件本身走 CDN 或本地路径，不进本协议文件。
