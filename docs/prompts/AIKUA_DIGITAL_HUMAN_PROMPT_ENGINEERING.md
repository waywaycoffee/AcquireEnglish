# 爱快英语｜数字人 Prompt 工程文档（双工 + 单工双模）

> 项目：爱快英语 AcquireEnglish  
> 适配：OpenNuplex-Podcast 全双工数字人、单工录播数字人  
> 能力：TTS 流式输出、VAD 打断（仅双工）、表情指令分离、难度分级、RAG 会话锚点  
> 版本：v1.0.0  
> 实现源：`docs/prompts/aikua_english_coach_prompts.json` + `shared/aikua_english_prompts.py`

## 模式说明

- **双工（FullDuplex）**：实时双向对话，用户可以语音插话打断数字人，VAD 人声检测生效；适合口语实时陪练。
- **单工（Simplex）**：数字人单向输出录播脚本，**无 VAD、无用户语音实时应答、不支持打断**；适合短视频、录播课程成片。

## 调度路由

| 模式 | 场景 | Prompt Key |
| --- | --- | --- |
| fullduplex | 正常轮次 | main_realtime / main_realtime_light |
| fullduplex | VAD 打断 | vad_interrupt |
| fullduplex | 静音超时 | silence_timeout |
| fullduplex | 等级切换 | level_switch |
| fullduplex | 跑偏兜底 | error_recover |
| fullduplex | 会话锚点 | session_anchor |
| fullduplex / simplex | 录播脚本 | video_script / video_script_light |
| simplex | 任务锚点 / 难度切换 / 兜底 | session_anchor / level_switch / error_recover |

## 流式过滤

标记：`【表情：xxx】`；合法表情：平静、微笑、思考、点头、抬手示意、轻思考、认真倾听。

1. 提取表情 → 数字人渲染  
2. 删除表情标记 → 干净文本送 TTS  
3. 无标记时默认表情：平静  
4. `【停顿2s】`：视频/单工保留；双工实时删除  

Python：`filter_stream_chunk(text, mode=...)`  
路由：`compose_system_prompt(scene, mode=..., level=..., topic=..., weak_points=...)`

## 部署备注

1. 会话初始化：优先拼接 `session_anchor` + 主 prompt（`compose_system_prompt` 默认如此）  
2. 轻量模式：`light=True` → `*_light`  
3. 表情与音频分流，不混进 TTS  
4. 单工链路不接入 VAD  
5. 占位符：`{level}` `{topic}` `{weak_points}` `{new_level}`  
