import sounddevice as sd
import numpy as np
import time
import os

# engineer wires this to Whisper (local) — here we just dump raw audio
AUDIO_DIR = "/var/drop-os/audio"


def main():
    os.makedirs(AUDIO_DIR, exist_ok=True)
    samplerate = 16000
    duration = 5  # seconds per chunk file

    while True:
        print("DROP audio: capturing chunk...")
        data = sd.rec(int(duration * samplerate), samplerate=samplerate, channels=1, dtype="float32")
        sd.wait()
        ts = int(time.time())
        path = os.path.join(AUDIO_DIR, f"chunk_{ts}.raw")
        data.tofile(path)


if __name__ == "__main__":
    main()
