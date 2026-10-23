#!/usr/bin/env python3
"""Build an SDXL text-to-image API workflow for the Codex MCP."""

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, help="Output API workflow path")
    parser.add_argument("--checkpoint", default="sd_xl_base_1.0.safetensors")
    parser.add_argument("--prompt", default="a red apple on a white table")
    parser.add_argument("--negative", default="blurry, low quality")
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--cfg", type=float, default=7.0)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--lora", help="LoRA filename under models/loras")
    parser.add_argument("--lora-strength", type=float, default=1.0)
    parser.add_argument("--vae", help="VAE filename under models/vae")
    args = parser.parse_args()

    template = Path(__file__).with_name("sdxl-text2image.api.json")
    workflow = json.loads(template.read_text(encoding="utf-8"))

    workflow["4"]["inputs"]["ckpt_name"] = args.checkpoint
    workflow["5"]["inputs"].update(
        width=args.width, height=args.height, batch_size=1
    )
    workflow["6"]["inputs"]["text"] = args.prompt
    workflow["7"]["inputs"]["text"] = args.negative
    workflow["3"]["inputs"].update(
        seed=args.seed, steps=args.steps, cfg=args.cfg
    )

    if args.lora:
        workflow["10"] = {
            "class_type": "LoraLoader",
            "inputs": {
                "model": ["4", 0],
                "clip": ["4", 1],
                "lora_name": args.lora,
                "strength_model": args.lora_strength,
                "strength_clip": args.lora_strength,
            },
        }
        workflow["3"]["inputs"]["model"] = ["10", 0]
        workflow["6"]["inputs"]["clip"] = ["10", 1]
        workflow["7"]["inputs"]["clip"] = ["10", 1]

    if args.vae:
        workflow["11"] = {
            "class_type": "VAELoader",
            "inputs": {"vae_name": args.vae},
        }
        workflow["8"]["inputs"]["vae"] = ["11", 0]

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(workflow, indent=2), encoding="utf-8")
    print(out)


if __name__ == "__main__":
    main()
