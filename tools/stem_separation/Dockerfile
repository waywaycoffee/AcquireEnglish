FROM python:3.11-slim

WORKDIR /app
# Demucs AudioFile needs ffmpeg + ffprobe. Use Aliyun Debian mirror for ECS/CN builds.
RUN set -eux; \
    . /etc/os-release; \
    codename="${VERSION_CODENAME}"; \
    printf '%s\n' \
      "deb http://mirrors.aliyun.com/debian/ ${codename} main contrib non-free non-free-firmware" \
      "deb http://mirrors.aliyun.com/debian/ ${codename}-updates main contrib non-free non-free-firmware" \
      "deb http://mirrors.aliyun.com/debian-security/ ${codename}-security main contrib non-free non-free-firmware" \
      > /etc/apt/sources.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ffmpeg; \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt app.py ./
RUN pip install --no-cache-dir torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir -r requirements.txt demucs==4.0.1

ENV OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8790"]
