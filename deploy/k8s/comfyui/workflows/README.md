# Character-consistent comic workflows

These files are ComfyUI API prompts and batch helpers for the comic pipeline
running on 168. They target `POST /prompt`; the generated images appear in the
normal ComfyUI output directory.

| File | Stage | Output prefix |
| --- | --- | --- |
| `character-sheet.api.json` | Creates the reusable character turnaround | `character_sheet` |
| `comic-panel.api.json` | Creates a scene with the same face and outfit | `comic_panel` |
| `storyboard.example.json` | Four-panel shot list with per-panel overrides | n/a |
| `generate_storyboard.py` | Submits the shot list and builds a contact sheet | `storyboard_*` |
| `render_comic_page.py` | Adds captions, bubbles, and page layout | `comic-page.png` |
| `generate_voiceover.ps1` | Windows Chinese TTS for captions and dialogue | `*.wav` |
| `build_voice_timeline.py` | Builds SRT, timing JSON, and combined audio | `timeline.json` |
| `build_motion_comic.py` | Adds camera motion, subtitles, and audio | `motion-comic.mp4` |
| `generate_video.py` | Uploads a start frame and runs Wan2.2 image-to-video | `*.mp4` |

## Prerequisites

Download the starter models first:

```bash
bash deploy/k8s/comfyui/download-models.sh
```

The comic workflow expects `character_ref.png` in the ComfyUI input directory.
Use any character image with the same framing as the generated sheet, or adapt
the two `ImageCrop` nodes in the workflow.

## Run from the 168 node

```bash
BASE=http://127.0.0.1:30188
TOKEN=$(kubectl -n comfyui get secret comfyui-auth \
  -o jsonpath='{.data.token}' | base64 -d)

# 1. Generate a character sheet.
curl -fsS -H 'Content-Type: application/json' \
  --data-binary @deploy/k8s/comfyui/workflows/character-sheet.api.json \
  "$BASE/prompt?token=$TOKEN"

# 2. Copy the generated image into the input directory as the stable reference.
cp /mapdata1/comfyui/ComfyUI/output/character_sheet_00001_.png \
  /mapdata1/comfyui/ComfyUI/input/character_ref.png

# 3. Generate a comic panel using that reference.
curl -fsS -H 'Content-Type: application/json' \
  --data-binary @deploy/k8s/comfyui/workflows/comic-panel.api.json \
  "$BASE/prompt?token=$TOKEN"
```

The token query parameter is sufficient for API authentication. HTTP Basic
auth by itself redirects to the login page.

To upload an existing reference instead of copying a generated output:

```bash
curl -fsS -F 'image=@character_ref.png' -F 'overwrite=true' \
  "$BASE/upload/image?token=$TOKEN"
```

## Batch storyboard

`generate_storyboard.py` submits each panel in `storyboard.example.json`
sequentially, downloads the rendered images, and builds a 2x2 contact sheet:

```bash
export COMFYUI_TOKEN=$(kubectl -n comfyui get secret comfyui-auth \
  -o jsonpath='{.data.token}' | base64 -d)

python3 deploy/k8s/comfyui/workflows/generate_storyboard.py \
  --base-url http://127.0.0.1:30188 \
  --output-dir /mapdata1/comfyui/ComfyUI/output/storyboard_demo
```

The script uses `comic-panel.api.json` and `storyboard.example.json` from its
own directory by default. Each panel accepts these optional overrides:

| Field | Purpose |
| --- | --- |
| `name` | Output filename and storyboard label |
| `prompt` | Shot description appended to the shared character and style |
| `seed` | Reproducible noise seed |
| `width`, `height` | Per-panel canvas size |
| `steps`, `cfg` | Sampling controls |
| `ipadapter_weight` | Face identity strength, normally `0.70` to `0.78` |
| `control_strength` | Canny ControlNet strength; `0.0` disables it |
| `control_end_percent` | Fraction of sampling that keeps the ControlNet hint |

The example disables ControlNet for camera variety. The Canny hint is derived
from a 3/4 character crop, so enabling it at `0.25` to `0.40` tends to lock the
shot back to that framing. Use it when a specific silhouette matters, and leave
it at `0.0` for wide, close-up, and reaction shots.

The contact sheet is saved as `contact-sheet.png` inside the output directory.
Pillow is required for the sheet; image generation continues without it.

## Dialogue page

After the panels have been downloaded, render a comic page with Chinese
captions and speech bubbles:

```bash
python3 deploy/k8s/comfyui/workflows/render_comic_page.py \
  --storyboard deploy/k8s/comfyui/workflows/storyboard.example.json \
  --images-dir outputs/comfyui/storyboard_demo_v3 \
  --output outputs/comfyui/storyboard_demo_v3/comic-page.png
```

The page uses two columns for up to four panels and three columns for five or
more. The renderer accepts `caption`, `caption_position`, `dialogue`,
`dialogue_position`, and `focus_y` in each panel. Page-level fields are `title`,
`subtitle`, and `footer`.

On Windows the default font is Microsoft YaHei. On Linux, install a CJK font
and pass it explicitly:

```bash
python3 render_comic_page.py ... \
  --font /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
  --bold-font /usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc
```

## Voiceover and subtitles

Generate one Chinese clip per caption or dialogue line with the Windows
Huihui voice:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  deploy/k8s/comfyui/workflows/generate_voiceover.ps1 `
  -Storyboard deploy/k8s/comfyui/workflows/storyboard.example.json `
  -OutputDir outputs/comfyui/storyboard_demo_v3/audio
```

Then build the timed SRT, timeline, and a single combined WAV:

```bash
python3 deploy/k8s/comfyui/workflows/build_voice_timeline.py \
  --voiceover outputs/comfyui/storyboard_demo_v3/audio/voiceover.json \
  --timeline outputs/comfyui/storyboard_demo_v3/audio/timeline.json \
  --srt outputs/comfyui/storyboard_demo_v3/audio/comic.srt \
  --combined outputs/comfyui/storyboard_demo_v3/audio/voiceover.wav
```

The voice script uses rate `-2` for dialogue and rate `0` for narration. The
timeline adds a 0.4 second lead-in and 0.35 second gaps, which are also used by
the motion-comic renderer.

## Motion comic

The final renderer uses ffmpeg inside the ComfyUI container. Copy the script,
storyboard, audio timeline, combined WAV, and a CJK font to the persistent
volume, then run:

```bash
kubectl -n comfyui exec deploy/comfyui -- python3 \
  /workspace/ComfyUI/output/storyboard_demo_v3/build_motion_comic.py \
  --storyboard /workspace/ComfyUI/output/storyboard_demo_v3/storyboard.example.json \
  --timeline /workspace/ComfyUI/output/storyboard_demo_v3/audio/timeline.json \
  --images-dir /workspace/ComfyUI/output/storyboard_demo_v3 \
  --audio /workspace/ComfyUI/output/storyboard_demo_v3/audio/voiceover.wav \
  --font /workspace/assets/fonts/msyh.ttc \
  --output /workspace/ComfyUI/output/storyboard_demo_v3/motion-comic.mp4
```

The output is vertical 1080x1920 at 25 fps. Panels alternate between slow zoom
and horizontal pan, subtitles are rendered with libass, and the voice track is
mixed with generated rain ambience. The current cut is 19.76 seconds and is
suitable for mobile short-video delivery.

## Image-to-video

`image-to-video.api.json` is the API form of the Wan2.2 TI2V 5B workflow. It
uses `Wan22ImageToVideoLatent`, `KSampler`, `CreateVideo`, and `SaveVideo`.
The default draft size is 480x832, 81 frames at 24 fps. The node requires
`length` to be `4n+1` (49, 81, or 121).

Start the separate video instance first, then upload one panel and submit the
workflow from the workstation:

```powershell
python deploy/k8s/comfyui/workflows/generate_video.py `
  --server http://172.16.0.168:30189 `
  --token BbRgXAscdqiw2amNHZQpvfK9xGPJDnjL `
  --image outputs/comfyui/storyboard_demo_v3/03_eye_closeup_01.png `
  --prompt "A detective turns toward the camera in heavy neon rain, slow push-in, consistent face" `
  --width 480 --height 832 --length 81 `
  --output outputs/comfyui/video/wan22-smoke.mp4
```

For a 5 second final shot use `--length 121`. Start at 480x832 for iteration;
switch to 704x1280 only after the draft passes, because VRAM and runtime rise
substantially at 720p.

## Output and polling

Each submission returns a `prompt_id`. Check it with:

```bash
curl -fsS "$BASE/history/$PROMPT_ID?token=$TOKEN"
```

Images are written under `/mapdata1/comfyui/ComfyUI/output` on the 168 host.

## How the consistency works

- `IPAdapterUnifiedLoader` uses the `PLUS FACE (portraits)` preset.
- A 280x300 crop around the face is upscaled to 512x512 and fed to
  `IPAdapterAdvanced` at weight `0.72`. This carries identity across panels.
- A 440x1024 body crop generates a Canny edge map. The single-panel template
  uses it at strength `0.38` until 40% of sampling. The batch example sets the
  strength to `0.0` so prompts can change camera distance and pose.
- The prompt controls clothing color, lighting, and environment. Negative
  prompts explicitly reject light-colored coats because neon light otherwise
  tends to wash out the navy fabric.

## Tuning

| Symptom | Change |
| --- | --- |
| Face drifts between panels | Raise IP-Adapter weight to `0.78` or use a tighter face crop |
| Every shot stays half-body | Set `control_strength` to `0.0` for that panel |
| Pose is too rigid | Lower ControlNet strength to `0.30` or end at `0.35` |
| Character silhouette is lost | Raise ControlNet strength to `0.45` |
| Clothing changes color | Keep `dark navy blue` early in the prompt and the light-coat terms in the negative prompt |
| Need a different pose | Replace the Canny input with a rough pose or line-art sketch instead of the character body crop |

The current image has only Canny preprocessing. There is no OpenPose or depth
preprocessor installed, so varied camera angles need either an uploaded pose
sketch or additional preprocessor custom nodes.

The workflow uses one GPU and roughly 7 GiB of VRAM at 640x1024. Keep the
same GPU allocation as the deployment, and do not schedule video generation on
top of a running panel batch.
