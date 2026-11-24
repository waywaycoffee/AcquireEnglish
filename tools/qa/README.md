# QA — 真机验收

## 数字人（Digital human）真机自动化验收

入口脚本（adb + uiautomator dump，无新测试框架）：

```bash
# 仅验收已安装的正式包 com.acquire.english
./tools/qa/digital_human_device_accept.sh

# 覆盖安装已有 prod debug APK（保留数据）
./tools/qa/digital_human_device_accept.sh --install --skip-build

# 重新构建并安装
./tools/qa/digital_human_device_accept.sh --install

# 多机时指定序列号
ANDROID_SERIAL=b1481470 ./tools/qa/digital_human_device_accept.sh --install --skip-build
```

产物：`tools/qa/artifacts/<时间戳>/`（`report.md`、`report.log`、截图、`ui_dump.xml`）。该目录已 gitignore。

### 自动化 vs 人工

| 项 | 自动化 | 说明 |
|----|--------|------|
| A 设备 / 正式包 / 冷启动 | ✅ | 无设备、unauthorized、`.dev` 包会硬失败 |
| B 口语入口 | ⚠ | 优先点底栏「口语」；「问我」浮球依赖播放器页，常需 MANUAL |
| C 教练页未崩 + 舞台文案 | ⚠ | dump 文案弱断言 + 截图；卡通口型目视 |
| D 麦克风「说话」 | ⚠ | 文案可见即 PASS；ValueKey 不进 uiautomator |
| E 「卡壳」 | ⚠ | dump 见文案即 PASS；否则 MANUAL |
| F oral_coach health | 可选 | curl 公网/本机；失败为 SKIP，不挡过 |
| G 截图 | ✅ | `adb exec-out screencap` |
| 双 CEFR / 知识卡文案 | 🖐 | 报告末尾人工清单 |

LiveTalking GPU **不是**本脚本硬门槛。
