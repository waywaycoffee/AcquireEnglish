# 卡通 / 真人形象

四个形象 Mia、Leo、Emma、Arun 的原始 JPG 保留；卡通版使用透明 PNG 九宫格动画图集。该版本是精灵帧动画，不是分层骨骼绑定模型。

图集每行 3 格，顺序：闭嘴、AH、EE、OO、FV、眨眼、倾听、思考、鼓励。手机端裁切单格，身体呼吸与轻微位移由固定动画驱动，不请求视频生成。

数字人页面可选择四位外教，以及卡通版/真人版，选择保存在本地设置。
真人照片模式只显示照片和说话状态；LiveTalking 是独立的实时真人口型服务。

口型实现限制：手机 TTS 使用词级进度回调映射近似嘴型；远程音频按实际播放位置、时长和文本分配近似嘴型。都不是音素级精准同步。未来可通过 CoachAnimationTimeline 接收实际音素时间戳；暂停/停止应回到闭嘴。不能用此动画示范准确发音口型。

生成方式：内置 image_gen，使用各角色 JPG 为参考。提示词：

> Use case: style-transfer. Create a production 2D cartoon English tutor sprite atlas based on this reference portrait, preserving hairstyle, skin tone and outfit. Exact square 3 by 3 equal-cell grid, NO borders, NO labels, transparent background. Each cell has the SAME front-facing waist-up cartoon character at EXACTLY same scale and location. Cells in row-major order: relaxed eyes open mouth closed; open AH; wide EE; rounded OO; FV; eyes closed blink; listening head nod; thinking; encouraging smile and thumbs up. No photography, no speech bubbles, no text. Character is {mia|leo|emma|arun}.

素材路径：apps/mobile/assets/img/digital_human/{角色}-cartoon.png。
