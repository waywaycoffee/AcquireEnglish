FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt app.py ./
RUN pip install --no-cache-dir torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir -r requirements.txt demucs==4.0.1 imageio-ffmpeg==0.6.0 \
    && ln -s "$(python -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')" /usr/local/bin/ffmpeg

ENV OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8790"]
