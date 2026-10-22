# Release note: Rainy Night

## Deliverable

- Runtime: 19.76 seconds.
- Picture: 1080x1920 vertical, 25 fps, H.264 High, yuv420p.
- Audio: 48 kHz stereo AAC, 192 kbps.
- Loudness target: -16 LUFS integrated, -1.6 dBTP true peak.
- Local copy: `outputs/comfyui/storyboard_demo_v3/motion-comic-final.mp4`.
- 168 copy: `/mapdata1/comfyui/ComfyUI/output/storyboard_demo_v3/motion-comic-final.mp4`.

## Contents

- Six SDXL panels with a consistent lead character.
- Six Chinese voice lines with burned-in subtitles and a timed SRT.
- Rain ambience, slow push-ins, horizontal pans, and panel transitions.
- Procedural low drone and heartbeat added during the final mix.

## Production notes

- The motion-comic cut was assembled from still panels so that every shot is
  reproducible and remains inside the 20 second target.
- Wan2.2 TI2V 5B is available on the isolated `comfyui-video` service at
  `http://172.16.0.168:30189` for future shots.
- Wan2.2 5B is stable at 704x1280 and 81 frames (3.375 seconds). A 121-frame
  single shot at 720p reached 23.9 GB and showed end-of-clip artifacts, so it
  is not used for delivery.

## Reproduction

1. Build the still-panel timeline with `build_motion_comic.py`.
2. Run `finalize_comic.py` to add sound design and normalize loudness.
3. Keep generated media under `outputs/`; do not commit render artifacts.
