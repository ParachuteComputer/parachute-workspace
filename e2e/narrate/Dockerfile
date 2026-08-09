FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      espeak-ng ffmpeg git fonts-dejavu-core && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir kokoro>=0.9 soundfile pillow
WORKDIR /work
