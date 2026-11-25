"""Record system output (WASAPI loopback of the default speakers) to a wav.
Usage: record_loopback.py out.wav seconds
Loopback delivers no data while nothing plays, so capture via callback and stop by wall clock."""
import sys, time, wave, pyaudiowpatch as pa

out, secs = sys.argv[1], float(sys.argv[2])
p = pa.PyAudio()
dev = p.get_default_wasapi_loopback()
ch, rate = dev["maxInputChannels"], int(dev["defaultSampleRate"])
frames = []


def cb(data, n, t, s):
    frames.append(data)
    return (None, pa.paContinue)


st = p.open(format=pa.paInt16, channels=ch, rate=rate, input=True,
            input_device_index=dev["index"], frames_per_buffer=512, stream_callback=cb)
print("recording", dev["name"], flush=True)
time.sleep(secs)
st.stop_stream(); st.close(); p.terminate()
with wave.open(out, "wb") as w:
    w.setnchannels(ch); w.setsampwidth(2); w.setframerate(rate); w.writeframes(b"".join(frames))
print("saved", out, len(frames), "buffers")
