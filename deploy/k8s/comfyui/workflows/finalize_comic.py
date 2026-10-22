#!/usr/bin/env python3
"""Add procedural sound design, normalize loudness, and finalize a comic."""

import argparse
import json
import subprocess
from pathlib import Path


def run(command, capture=False):
    print("+ " + " ".join(str(part) for part in command), flush=True)
    result = subprocess.run(
        [str(part) for part in command],
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "").strip()
        raise SystemExit(f"command failed ({result.returncode}): {message}")
    return result


def probe_duration(ffprobe, path):
    result = subprocess.run(
        [
            str(ffprobe), "-v", "error", "-show_entries", "format=duration",
            "-of", "json", str(path),
        ],
        check=True, text=True, capture_output=True,
    )
    return float(json.loads(result.stdout)["format"]["duration"])


def measure_loudness(ffmpeg, path, target_i, target_tp, target_lra):
    filter_graph = (
        f"loudnorm=I={target_i}:TP={target_tp}:LRA={target_lra}:print_format=json"
    )
    result = run([
        ffmpeg, "-hide_banner", "-nostats", "-i", path, "-vn",
        "-af", filter_graph, "-f", "null", "-",
    ], capture=True)
    text = result.stderr
    start = text.rfind("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        raise SystemExit("could not parse loudnorm output")
    return json.loads(text[start:end + 1])


def build_sound_design(ffmpeg, video, duration, work_dir, drone_level, heart_level):
    mix_path = work_dir / "sound-design.wav"
    drone = (
        f"aevalsrc=0.03*sin(2*PI*55*t)*(0.7+0.3*sin(2*PI*0.2*t))"
        f":s=48000:d={duration:.3f}"
    )
    heart = (
        f"aevalsrc=0.05*sin(2*PI*48*t)*exp(-18*(t-floor(t/0.9)*0.9))"
        f":s=48000:d={duration:.3f}"
    )
    fade_out = max(0.0, duration - 1.0)
    graph = (
        "[0:a]aresample=48000,pan=stereo|c0=c0|c1=c0[base];"
        f"[1:a]volume={drone_level},afade=t=in:st=0:d=2[drone];"
        f"[2:a]volume={heart_level},afade=t=in:st=0:d=1.5[heart];"
        "[base][drone][heart]amix=inputs=3:duration=first:"
        "dropout_transition=2:normalize=0,"
        f"afade=t=in:st=0:d=0.4,afade=t=out:st={fade_out:.3f}:d=1.0[a]"
    )
    run([
        ffmpeg, "-y", "-i", video,
        "-f", "lavfi", "-i", drone,
        "-f", "lavfi", "-i", heart,
        "-filter_complex", graph, "-map", "[a]",
        "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le",
        "-t", f"{duration:.3f}", mix_path,
    ])
    return mix_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    parser.add_argument("--drone-level", type=float, default=0.06)
    parser.add_argument("--heart-level", type=float, default=0.08)
    parser.add_argument("--target-i", type=float, default=-16.0)
    parser.add_argument("--target-tp", type=float, default=-1.6)
    parser.add_argument("--target-lra", type=float, default=11.0)
    parser.add_argument("--title", default="Rainy Night Motion Comic")
    args = parser.parse_args()

    if not args.video.is_file():
        raise SystemExit(f"video not found: {args.video}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    work_dir = args.work_dir or args.output.parent / "finalize-build"
    work_dir.mkdir(parents=True, exist_ok=True)

    duration = probe_duration(args.ffprobe, args.video)
    mix_path = build_sound_design(
        args.ffmpeg, args.video, duration, work_dir,
        args.drone_level, args.heart_level,
    )
    measured = measure_loudness(
        args.ffmpeg, mix_path, args.target_i, args.target_tp, args.target_lra
    )
    loudnorm = (
        f"loudnorm=I={args.target_i}:TP={args.target_tp}:LRA={args.target_lra}"
        f":measured_I={measured['input_i']}"
        f":measured_TP={measured['input_tp']}"
        f":measured_LRA={measured['input_lra']}"
        f":measured_thresh={measured['input_thresh']}"
        f":offset={measured['target_offset']}:linear=true"
    )
    run([
        args.ffmpeg, "-y", "-i", args.video, "-i", mix_path,
        "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy",
        "-af", loudnorm, "-c:a", "aac", "-b:a", "192k",
        "-ar", "48000", "-t", f"{duration:.3f}", "-movflags", "+faststart",
        "-metadata", f"title={args.title}", args.output,
    ])
    print(
        f"saved {args.output} ({args.output.stat().st_size} bytes, "
        f"target {args.target_i} LUFS / {args.target_tp} dBTP)"
    )


if __name__ == "__main__":
    main()
