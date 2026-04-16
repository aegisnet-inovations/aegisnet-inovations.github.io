import sounddevice as sd
import numpy as np
import whisper
import time
import os

AUDIO_DIR = "/var/drop-os/audio"
# Use 'base' model — best balance for CPU-only (AMD system, no CUDA)
# Options: tiny, base, small, medium, large
WHISPER_MODEL = "base"


def main():
    os.makedirs(AUDIO_DIR, exist_ok=True)
    samplerate = 16000
    duration = 5  # seconds per chunk

    print(f"DROP audio: loading Whisper model '{WHISPER_MODEL}'...")
    model = whisper.load_model(WHISPER_MODEL)
    print("DROP audio: Whisper loaded. Listening...")

    while True:
        print("DROP audio: capturing chunk...")
        data = sd.rec(int(duration * samplerate), samplerate=samplerate, channels=1, dtype="float32")
        sd.wait()

        ts = int(time.time())

        # Save raw audio
        raw_path = os.path.join(AUDIO_DIR, f"chunk_{ts}.raw")
        data.tofile(raw_path)

        # Transcribe with Whisper
        audio_np = data.flatten().astype(np.float32)
        result = model.transcribe(audio_np, fp16=False)
        text = result.get("text", "").strip()

        if text:
            txt_path = os.path.join(AUDIO_DIR, f"chunk_{ts}.txt")
            with open(txt_path, "w") as f:
                f.write(text)
            print(f"DROP audio: [{ts}] {text}")


if __name__ == "__main__":
    main()
