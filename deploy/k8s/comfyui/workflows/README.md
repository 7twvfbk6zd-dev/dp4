# Character-consistent comic workflows

These files are ComfyUI API prompts for the two-stage comic pipeline running on
168. They target `POST /prompt`; the generated images appear in the normal
ComfyUI output directory.

| File | Stage | Output prefix |
| --- | --- | --- |
| `character-sheet.api.json` | Creates the reusable character turnaround | `character_sheet` |
| `comic-panel.api.json` | Creates a scene with the same face and outfit | `comic_panel` |

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
- A 440x1024 body crop generates a Canny edge map. SDXL ControlNet uses it at
  strength `0.38` until 40% of sampling, which keeps the silhouette without
  locking the background.
- The prompt controls clothing color, lighting, and environment. Negative
  prompts explicitly reject light-colored coats because neon light otherwise
  tends to wash out the navy fabric.

## Tuning

| Symptom | Change |
| --- | --- |
| Face drifts between panels | Raise IP-Adapter weight to `0.78` or use a tighter face crop |
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
