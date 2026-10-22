#!/usr/bin/env python3
"""Generate character-consistent comic panels through the ComfyUI API."""

import argparse
import copy
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


def api_json(url, payload=None, timeout=60):
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method="POST" if data is not None else "GET",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read()
    return json.loads(raw.decode("utf-8")) if raw else {}


def api_url(base_url, path, token, params=None):
    query = dict(params or {})
    query["token"] = token
    return f"{base_url}{path}?{urllib.parse.urlencode(query)}"


def slug(value):
    value = re.sub(r"[^A-Za-z0-9_-]+", "_", value.strip())
    return value.strip("_") or "panel"


def build_prompt(template, storyboard, panel, index):
    prompt = copy.deepcopy(template["prompt"])
    parts = [
        storyboard.get("character", ""),
        panel.get("prompt", ""),
        storyboard.get("style", ""),
    ]
    prompt["2"]["inputs"]["text"] = " ".join(part.strip() for part in parts if part and part.strip())
    prompt["3"]["inputs"]["text"] = panel.get("negative", storyboard.get("negative", ""))

    sampler = prompt["15"]["inputs"]
    sampler["seed"] = int(panel.get("seed", sampler["seed"] + index))
    for key in ("steps", "cfg"):
        if key in panel:
            sampler[key] = panel[key]

    latent = prompt["14"]["inputs"]
    for key in ("width", "height"):
        if key in panel:
            latent[key] = panel[key]

    control = prompt["13"]["inputs"]
    if "control_strength" in panel:
        control["strength"] = panel["control_strength"]
    if "control_end_percent" in panel:
        control["end_percent"] = panel["control_end_percent"]

    if "ipadapter_weight" in panel:
        prompt["8"]["inputs"]["weight"] = panel["ipadapter_weight"]

    name = slug(panel["name"])
    prompt["17"]["inputs"]["filename_prefix"] = f"storyboard_{index:02d}_{name}"
    return prompt


def wait_for_history(base_url, token, prompt_id, timeout, poll):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        history = api_json(api_url(base_url, f"/history/{prompt_id}", token))
        record = history.get(prompt_id)
        if record and (record.get("outputs") or record.get("status", {}).get("completed")):
            return record
        time.sleep(poll)
    raise TimeoutError(f"timed out waiting for prompt {prompt_id}")


def download_outputs(base_url, token, record, output_dir, name):
    downloaded = []
    counter = 0
    for node_output in record.get("outputs", {}).values():
        for image in node_output.get("images", []):
            counter += 1
            params = {
                "filename": image["filename"],
                "subfolder": image.get("subfolder", ""),
                "type": image.get("type", "output"),
            }
            url = api_url(base_url, "/view", token, params)
            with urllib.request.urlopen(url, timeout=120) as response:
                data = response.read()
            suffix = Path(image["filename"]).suffix or ".png"
            destination = output_dir / f"{name}_{counter:02d}{suffix}"
            destination.write_bytes(data)
            downloaded.append(destination)
    if not downloaded:
        raise RuntimeError("ComfyUI completed without returning an image")
    return downloaded


def make_contact_sheet(images, destination):
    try:
        from PIL import Image
    except ImportError:
        print("WARNING: Pillow is not installed; skipping contact sheet", file=sys.stderr)
        return None

    thumb_width = 320
    thumbs = []
    for path in images:
        with Image.open(path) as source:
            image = source.convert("RGB")
            height = max(1, round(image.height * thumb_width / image.width))
            thumbs.append(image.resize((thumb_width, height), Image.LANCZOS))

    columns = 2 if len(thumbs) <= 4 else 3
    rows = math.ceil(len(thumbs) / columns)
    cell_width = max(image.width for image in thumbs)
    cell_height = max(image.height for image in thumbs)
    gutter = 8
    canvas = Image.new(
        "RGB",
        (
            columns * cell_width + (columns + 1) * gutter,
            rows * cell_height + (rows + 1) * gutter,
        ),
        (20, 22, 28),
    )
    for index, image in enumerate(thumbs):
        row, column = divmod(index, columns)
        x = gutter + column * (cell_width + gutter) + (cell_width - image.width) // 2
        y = gutter + row * (cell_height + gutter) + (cell_height - image.height) // 2
        canvas.paste(image, (x, y))
    canvas.save(destination)
    return destination


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default=os.getenv("COMFYUI_BASE_URL", "http://127.0.0.1:30188"))
    parser.add_argument("--token", default=os.getenv("COMFYUI_TOKEN"))
    parser.add_argument("--template", default=str(Path(__file__).with_name("comic-panel.api.json")))
    parser.add_argument("--storyboard", default=str(Path(__file__).with_name("storyboard.example.json")))
    parser.add_argument("--output-dir", default="storyboard_output")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--poll", type=float, default=2.0)
    parser.add_argument("--no-contact-sheet", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.token:
        raise SystemExit("COMFYUI_TOKEN is required (or pass --token)")

    base_url = args.base_url.rstrip("/")
    template = json.loads(Path(args.template).read_text(encoding="utf-8"))
    storyboard = json.loads(Path(args.storyboard).read_text(encoding="utf-8"))
    panels = storyboard.get("panels", [])
    if not panels:
        raise SystemExit("storyboard has no panels")

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    generated = []
    total = len(panels)

    for index, panel in enumerate(panels, 1):
        if "name" not in panel or "prompt" not in panel:
            raise SystemExit(f"panel {index} needs name and prompt")
        name = slug(panel["name"])
        prompt = build_prompt(template, storyboard, panel, index)
        body = {"prompt": prompt, "client_id": f"dp4-storyboard-{index:02d}"}
        result = api_json(api_url(base_url, "/prompt", args.token), body)
        prompt_id = result.get("prompt_id")
        if not prompt_id:
            raise RuntimeError(f"submission failed: {result}")
        print(f"[{index}/{total}] queued {panel['name']} ({prompt_id})", flush=True)
        record = wait_for_history(base_url, args.token, prompt_id, args.timeout, args.poll)
        files = download_outputs(base_url, args.token, record, output_dir, name)
        generated.extend(files)
        print(f"[{index}/{total}] saved {', '.join(str(path) for path in files)}", flush=True)

    if not args.no_contact_sheet:
        sheet = make_contact_sheet(generated, output_dir / "contact-sheet.png")
        if sheet:
            print(f"contact sheet: {sheet}")
    print(f"done: {len(generated)} image(s) in {output_dir}")


if __name__ == "__main__":
    main()
