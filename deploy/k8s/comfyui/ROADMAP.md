# AI comic roadmap

Goal: turn the character-consistent image pipeline into a short, publishable
AI motion comic on the 168 node.

## 1. Dialogue and page layout

Status: done.

- Compose generated panels into a comic page.
- Add Chinese captions and speech bubbles with automatic wrapping.
- Keep titles, subtitles, and footer metadata in the storyboard JSON.
- Output: `render_comic_page.py`, `comic-page.png`.

## 2. Six-panel storyboard

Status: done.

- Generate establishing, reaction, close-up, action, insert, and cliffhanger
  shots with the same character reference.
- Keep per-panel seeds and prompts reproducible.
- Output: six panels and `contact-sheet.png` under `storyboard_demo_v3`.

## 3. Chinese voiceover and subtitles

Status: done.

- Generate one voice clip per spoken line.
- Produce an SRT file with timings derived from the audio durations.
- Prefer a neutral, restrained detective voice.
- Acceptance: all six lines are audible, timed, and match the panel text.
- Output: `generate_voiceover.ps1`, `build_voice_timeline.py`, `voiceover.wav`,
  `timeline.json`, and `comic.srt`.

## 4. Motion comic

Status: pending.

- Animate still panels with slow zoom and pan.
- Add rain ambience and panel transitions.
- Burn in subtitles and mix the voice track.
- Target: 20-30 second 1080p H.264/AAC teaser.

## 5. Image-to-video

Status: pending, requires a separate evaluation.

- Evaluate a small image-to-video model that fits one 24 GB RTX 4090.
- Prefer a separate ComfyUI deployment or job queue so `ds4` GPU 4-7 remain
  untouched.
- Do not replace the current SDXL deployment until a video workflow passes a
  smoke test.

## 6. Assembly and delivery

Status: pending.

- Add background music or sound design.
- Normalize audio, encode the final file, and write a short release note.
- Keep generated media under `outputs/` and out of Git.

## Resource rules

- Use only GPUs 0-3; never schedule work on `ds4` GPUs 4-7.
- Keep one GPU per ComfyUI pod.
- Check VRAM and disk usage before downloading video checkpoints.
- Record every new model in `download-models.sh` or a separate video download
  script.
