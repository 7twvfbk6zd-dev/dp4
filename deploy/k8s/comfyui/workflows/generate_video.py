#!/usr/bin/env python3
"""Submit a Wan2.2 image-to-video workflow and download the result."""

import argparse
import json
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


def api_url(server, path, token, **params):
    query = {"token": token}
    query.update({key: value for key, value in params.items() if value is not None})
    return f"{server.rstrip('/')}{path}?{urllib.parse.urlencode(query)}"


def read_json(request, timeout):
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code} from {request.full_url}: {body}") from exc


def upload_image(server, token, image_path, timeout):
    boundary = "----comfyui" + uuid.uuid4().hex
    content = image_path.read_bytes()
    parts = [
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="image"; filename="' +
        image_path.name.encode() + b'"\r\n',
        b"Content-Type: application/octet-stream\r\n\r\n",
        content,
        b"\r\n",
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="overwrite"\r\n\r\n',
        b"true\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    request = urllib.request.Request(
        api_url(server, "/upload/image", token),
        data=b"".join(parts),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    result = read_json(request, timeout)
    name = result["name"]
    subfolder = result.get("subfolder", "")
    return f"{subfolder}/{name}" if subfolder else name


def submit(server, token, workflow, client_id, timeout):
    body = json.dumps({"prompt": workflow, "client_id": client_id}).encode("utf-8")
    request = urllib.request.Request(
        api_url(server, "/prompt", token),
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return read_json(request, timeout)


def wait_for_history(server, token, prompt_id, timeout, poll_interval):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        request = urllib.request.Request(api_url(server, f"/history/{prompt_id}", token))
        history = read_json(request, 60)
        if prompt_id in history:
            return history[prompt_id]
        time.sleep(poll_interval)
    raise SystemExit(f"timed out waiting for prompt {prompt_id}")


def download_outputs(server, token, history, output_path, timeout):
    files = []
    for node_output in history.get("outputs", {}).values():
        for value in node_output.values():
            if not isinstance(value, list):
                continue
            for item in value:
                if isinstance(item, dict) and item.get("filename"):
                    files.append(item)
    if not files:
        raise SystemExit(f"no output files found: {json.dumps(history, ensure_ascii=False)}")

    files.sort(key=lambda item: Path(item["filename"]).suffix not in {".mp4", ".webm"})
    output_path.parent.mkdir(parents=True, exist_ok=True)
    for index, item in enumerate(files):
        suffix = Path(item["filename"]).suffix
        target = output_path if index == 0 else output_path.with_name(
            f"{output_path.stem}-{index + 1}{output_path.suffix}"
        )
        if target.suffix.lower() != suffix.lower():
            target = target.with_suffix(suffix)
        query = urllib.parse.urlencode({
            "token": token,
            "filename": item["filename"],
            "subfolder": item.get("subfolder", ""),
            "type": item.get("type", "output"),
        })
        request = urllib.request.Request(f"{server.rstrip('/')}/view?{query}")
        with urllib.request.urlopen(request, timeout=timeout) as response:
            target.write_bytes(response.read())
        print(f"saved {target} ({target.stat().st_size} bytes)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", default="http://172.16.0.168:30189")
    parser.add_argument("--token", required=True)
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--workflow", type=Path,
                        default=Path(__file__).with_name("image-to-video.api.json"))
    parser.add_argument("--prompt")
    parser.add_argument("--negative")
    parser.add_argument("--width", type=int)
    parser.add_argument("--height", type=int)
    parser.add_argument("--length", type=int, default=81)
    parser.add_argument("--fps", type=int, default=24)
    parser.add_argument("--steps", type=int)
    parser.add_argument("--cfg", type=float)
    parser.add_argument("--seed", type=int, default=random.randint(0, 2**32 - 1))
    parser.add_argument("--poll-interval", type=float, default=5)
    parser.add_argument("--timeout", type=int, default=3600)
    args = parser.parse_args()

    if not args.image.is_file():
        raise SystemExit(f"image not found: {args.image}")
    if args.length < 5 or (args.length - 1) % 4 != 0:
        raise SystemExit("--length must be 4n+1, for example 49, 81, or 121")
    if args.width is not None and args.width % 16 != 0:
        raise SystemExit("--width must be divisible by 16")
    if args.height is not None and args.height % 16 != 0:
        raise SystemExit("--height must be divisible by 16")

    workflow = json.loads(args.workflow.read_text(encoding="utf-8"))
    image_name = upload_image(args.server, args.token, args.image, 120)
    workflow["56"]["inputs"]["image"] = image_name
    workflow["3"]["inputs"]["seed"] = args.seed
    workflow["3"]["inputs"]["steps"] = args.steps or workflow["3"]["inputs"]["steps"]
    workflow["3"]["inputs"]["cfg"] = args.cfg or workflow["3"]["inputs"]["cfg"]
    workflow["55"]["inputs"]["length"] = args.length
    workflow["57"]["inputs"]["fps"] = args.fps
    if args.width is not None:
        workflow["55"]["inputs"]["width"] = args.width
    if args.height is not None:
        workflow["55"]["inputs"]["height"] = args.height
    if args.prompt:
        workflow["6"]["inputs"]["text"] = args.prompt
    if args.negative:
        workflow["7"]["inputs"]["text"] = args.negative

    client_id = uuid.uuid4().hex
    response = submit(args.server, args.token, workflow, client_id, 120)
    if "prompt_id" not in response:
        raise SystemExit(f"prompt rejected: {json.dumps(response, ensure_ascii=False)}")
    prompt_id = response["prompt_id"]
    print(f"queued {prompt_id} (seed={args.seed})")
    history = wait_for_history(
        args.server, args.token, prompt_id, args.timeout, args.poll_interval
    )
    download_outputs(args.server, args.token, history, args.output, 300)


if __name__ == "__main__":
    main()
