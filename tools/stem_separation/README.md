# 配音人声分离

在 ECS 上构建容器，将 8790 端口绑定到回环地址。手机经认证后的 `/api/stem/separate` 请求分离，API 转发给容器。

```sh
docker build -t acquireenglish-stem .
docker run -d --name acquireenglish-stem --restart unless-stopped \
  --cpus=1 --memory=1500m -e TORCH_HOME=/models \
  -v /opt/acquireenglish/stem_separation/model-cache:/models \
  -p 127.0.0.1:8790:8790 acquireenglish-stem
```

Demucs 将输入分成 vocals 和 no_vocals。接口返回 PCM WAV；分离失败返回 503。
