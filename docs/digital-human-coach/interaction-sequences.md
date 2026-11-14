# 交互时序 — 数字人口语外教

> 证据分级：  
> - **假设 (H)**：由公开产品面 + 行业常规推导  
> - **设计 (D)**：AcquireEnglish 目标实现  
> - **观测 (O)**：REA/ADB/mitm 抓包后填写（当前无设备，暂无 O）

## 1. 总览：一次完整练习

```mermaid
sequenceDiagram
  participant U as 用户
  participant App as Flutter App
  participant LK as LiveKit Server
  participant Ag as LiveKit Agent
  participant Pron as 发音评测
  participant Avatar as 数字人
  participant Learn as learning/ 业务层

  U->>App: 进入口语陪练 / 选任务
  App->>Learn: 创建 session + 任务快照
  App->>LK: 取 token / 进房
  LK->>Ag: 分配 Job
  Ag->>Avatar: 开场 cue + TTS
  Avatar-->>U: 数字人说话
  loop 全双工回合
    U->>LK: 上行音频
    LK->>Ag: 音频轨
    Ag->>Ag: VAD / turn / barge-in
    Note over Ag: 用户打断 → 停 TTS (D)
    Ag->>Ag: STT 流式转写
    opt 核对模式 (D / ChatterPal)
      Ag-->>App: draft transcript
      U->>App: 编辑并确认
      App->>Learn: confirm transcription
    end
    par 异步评测不抢麦 (H/D)
      Ag->>Pron: audio + reference
      Pron-->>App: 发音/音素卡片
    and 外教回复
      Ag->>Ag: LLM coach
      Ag->>Avatar: TTS + lip sync
      Avatar-->>U: 数字人追问
    end
    App->>Learn: 落库回合
  end
  U->>App: 结束练习
  App->>Learn: 生成反馈(≤2 重点) + 错题/复习
  Learn-->>App: 报告 + 复习到期
```

## 2. 打断（Barge-in）— LiveKit Agents (D)

```mermaid
sequenceDiagram
  participant U as 用户
  participant VAD as Silero VAD
  participant Sess as AgentSession
  participant TTS as TTS 播放

  TTS->>U: 外教播报中
  U->>VAD: 开始说话
  VAD->>Sess: speech_started
  alt interruption.mode = vad (D)
    Sess->>TTS: interrupt / stop
    Note over Sess: min_duration 过滤咳嗽
  else false interruption
    Sess->>Sess: false_interruption_timeout
    Sess->>TTS: resume (可选)
  end
  Sess->>Sess: 收集本轮音频 → STT → LLM
```

配置要点（LiveKit）：

- `TurnHandlingOptions.interruption.mode`: `"vad"` 或 `"adaptive"`
- `min_duration` / `min_words`：抑制误打断
- `resume_false_interruption`: 噪音误打断后恢复播报

## 3. 边聊边评 vs 回合后评（H → 待 O）

| 阶段 | Hi Echo（公开） | 我们的设计 (D) |
|------|-----------------|----------------|
| 用户说话中 | 不打断节奏 | 同左；评测异步 |
| 间隙 | 发音/语法轻量卡片 | DataChannel 推送 `score.partial` |
| 结束任务 | 三维分数 + 建议 | ChatterPal：原话引用 ≤2 + 重练入口 |

```mermaid
sequenceDiagram
  participant Ag as Agent
  participant Pron as Pronunciation
  participant App as App
  participant Learn as learning/

  Ag->>Pron: score(audio, reference, transcript)
  Pron-->>Ag: overall / words / phonemes
  Ag-->>App: data: score.partial
  Note over App: UI 不抢麦，可折叠
  Ag->>Learn: attach_scores(turn_id)
```

## 4. ChatterPal 学习闭环 (D)

对齐 [likebeans/ChatterPal](https://github.com/likebeans/ChatterPal) 的产品语义（MIT）：

```mermaid
stateDiagram-v2
  [*] --> TaskSelect: 选情境/视频句
  TaskSelect --> Recording: 说话
  Recording --> DraftASR: ASR 草稿
  DraftASR --> Confirm: 用户核对文字
  Confirm --> CoachTurn: 提交确认文
  CoachTurn --> MoreTurns: 多轮追问
  MoreTurns --> Recording
  MoreTurns --> Feedback: 结束任务
  Feedback --> Repractice: 单句重练
  Feedback --> ReviewQueue: 保存表达
  ReviewQueue --> ReviewDue: 次日换题
  ReviewDue --> Recording
  Feedback --> [*]
```

关键不变量：

1. **草稿与确认分离**：未确认不进 LLM / 不记成绩  
2. **反馈必须引用用户原话**（校验失败则丢弃该条）  
3. **复习调度**：存档 → ~1 天 → 独立作答成功再 ~3/~7 天  
4. **提示/看答案** 与 **独立作答** 分轨记账  

## 5. 数字人播报 (D)

```mermaid
sequenceDiagram
  participant Ag as Agent
  participant TTS as TTS
  participant Av as MuseTalk/LivePortrait/LiveTalking
  participant App as App

  Ag->>TTS: synthesize(coach_text)
  TTS-->>Ag: wav
  alt LiveTalking
    Ag->>Av: POST /human {text}
    Av-->>App: WebRTC 画面
  else MuseTalk / LivePortrait HTTP
    Ag->>Av: audio + 参考脸
    Av-->>App: 视频帧 / 流地址
  end
```

## 6. 视频语境注入 (D — AcquireEnglish 特有)

```text
App 当前句 current_english + 前后句
        │
        ▼
Agent system prompt / tool context
        │
        ▼
外教围绕「视频里这句话」追问，而不是泛闲聊
```

事件：`session.context.updated`（用户拖进度条换句时刷新）。

## 7. 抓包后应补的观测表（O）

| ID | 问题 | 证据类型 | 状态 |
|----|------|----------|------|
| O1 | Hi Echo 是否 WebRTC？信令域名？ | mitm + pcap | 待设备 |
| O2 | 打断事件在客户端还是服务端判定？ | 日志 / 流量时序 | 待设备 |
| O3 | 评分 API 路径与触发点 | mitm HAR | 待设备 |
| O4 | Midoo 会话创建请求体字段 | mitm | 待设备 |
| O5 | 数字人视频流协议 | REA 网络 / Media | 待设备 |

执行步骤见 [capture-playbook.md](./capture-playbook.md)。
