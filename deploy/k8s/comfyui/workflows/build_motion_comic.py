#!/usr/bin/env python3
"""Build a short motion comic with ffmpeg from panels and a voice timeline."""

import argparse
import json
import math
import subprocess
from pathlib import Path


def ass_time(seconds):
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    remaining = seconds % 60
    return f"{hours}:{minutes:02d}:{remaining:05.2f}"


def write_ass(timeline, destination, width, height):
    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {width}
PlayResY: {height}
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Microsoft YaHei,56,&H00FFFFFF,&H000000FF,&H00101010,&H90000000,0,0,0,0,100,100,0,0,1,3,1,2,60,60,110,1
Style: Caption,Microsoft YaHei,50,&H0060D0FF,&H000000FF,&H00101010,&H90000000,0,0,0,0,100,100,0,0,1,3,1,2,70,70,110,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    lines = [header]
    for entry in timeline["entries"]:
        text = entry["text"].replace("\n", r"\N")
        style = "Caption" if entry["type"] == "caption" else "Default"
        lines.append(
            "Dialogue: 0,{},{},{},,0,0,0,,{}\n".format(
                ass_time(entry["start"]),
                ass_time(entry["end"]),
                style,
                text,
            )
        )
    destination.write_text("".join(lines), encoding="utf-8")


def run(command):
    print("+ " + " ".join(str(part) for part in command), flush=True)
    subprocess.run([str(part) for part in command], check=True)


def find_panel_image(images_dir, name):
    matches = sorted(images_dir.glob(f"{name}_*.png"))
    if not matches:
        matches = sorted(images_dir.glob(f"*{name}*.png"))
    if not matches:
        raise SystemExit(f"no image found for panel {name} in {images_dir}")
    return matches[0]


def panel_groups(storyboard, timeline):
    entries = timeline["entries"]
    groups = []
    for panel in storyboard["panels"]:
        matching = [entry for entry in entries if entry["panel"] == panel["name"]]
        if not matching:
            raise SystemExit(f"no voice timeline for panel {panel['name']}")
        groups.append({
            "panel": panel,
            "start": matching[0]["start"],
            "end": matching[-1]["end"],
        })

    total = float(timeline["total_duration"])
    for index, group in enumerate(groups):
        group["start"] = 0.0 if index == 0 else group["start"]
        group["end"] = groups[index + 1]["start"] if index + 1 < len(groups) else total
        group["duration"] = max(0.8, group["end"] - group["start"])
    return groups


def make_clip(ffmpeg, image, clip, duration, width, height, fps, index):
    zoom_step = 0.0008
    zoom_filter = (
        f"scale={width}:{height}:force_original_aspect_ratio=increase,"
        f"crop={width}:{height},"
        f"zoompan=z='min(zoom+{zoom_step},1.08)':"
        f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
        f"d=1:s={width}x{height}:fps={fps}"
    )
    if index % 2 == 1:
        zoom_filter = (
            f"scale={width}:{height}:force_original_aspect_ratio=increase,"
            f"crop={width}:{height},"
            f"zoompan=z='min(zoom+{zoom_step},1.06)':"
            f"x='(iw-iw/zoom)*min(on/{max(1, round(duration * fps))},1)':"
            f"y='ih/2-(ih/zoom/2)':d=1:s={width}x{height}:fps={fps}"
        )
    run([
        ffmpeg, "-y", "-loop", "1", "-i", image, "-t", f"{duration:.3f}",
        "-vf", zoom_filter, "-an", "-c:v", "libx264", "-preset", "medium",
        "-crf", "20", "-pix_fmt", "yuv420p", "-r", str(fps), clip,
    ])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--storyboard", required=True)
    parser.add_argument("--timeline", required=True)
    parser.add_argument("--images-dir", required=True)
    parser.add_argument("--audio", required=True)
    parser.add_argument("--font", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--work-dir")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--width", type=int, default=1080)
    parser.add_argument("--height", type=int, default=1920)
    parser.add_argument("--fps", type=int, default=25)
    args = parser.parse_args()

    storyboard = json.loads(Path(args.storyboard).read_text(encoding="utf-8"))
    timeline = json.loads(Path(args.timeline).read_text(encoding="utf-8"))
    images_dir = Path(args.images_dir)
    output = Path(args.output)
    font = Path(args.font)
    if not font.exists():
        raise SystemExit(f"font not found: {font}")
    output.parent.mkdir(parents=True, exist_ok=True)
    work_dir = Path(args.work_dir) if args.work_dir else output.parent / "motion-build"
    work_dir.mkdir(parents=True, exist_ok=True)

    ass_path = work_dir / "comic.ass"
    write_ass(timeline, ass_path, args.width, args.height)

    groups = panel_groups(storyboard, timeline)
    clips = []
    for index, group in enumerate(groups):
        image = find_panel_image(images_dir, group["panel"]["name"])
        clip = work_dir / f"panel-{index + 1:02d}.mp4"
        print(
            f"[{index + 1}/{len(groups)}] {group['panel']['name']} "
            f"{group['duration']:.2f}s",
            flush=True,
        )
        make_clip(
            args.ffmpeg,
            image,
            clip,
            group["duration"],
            args.width,
            args.height,
            args.fps,
            index,
        )
        clips.append(clip)

    concat_file = work_dir / "concat.txt"
    concat_file.write_text(
        "".join(f"file '{clip.resolve()}'\n" for clip in clips),
        encoding="utf-8",
    )
    silent = work_dir / "silent.mp4"
    run([
        args.ffmpeg, "-y", "-f", "concat", "-safe", "0", "-i", concat_file,
        "-c", "copy", silent,
    ])

    total = float(timeline["total_duration"])
    fade_start = max(0.0, total - 0.7)
    subtitle_filter = (
        f"subtitles={ass_path.resolve()}:fontsdir={font.parent.resolve()},"
        f"fade=t=in:st=0:d=0.4,fade=t=out:st={fade_start:.3f}:d=0.7"
    )
    audio_filter = (
        "[1:a]aresample=48000,pan=stereo|c0=c0|c1=c0,volume=1.0[voice];"
        "[2:a]highpass=f=500,lowpass=f=6500,volume=0.08[rain];"
        "[voice][rain]amix=inputs=2:duration=first:dropout_transition=2[a]"
    )
    run([
        args.ffmpeg, "-y", "-i", silent, "-i", args.audio,
        "-f", "lavfi", "-i", f"anoisesrc=color=pink:amplitude=0.12:duration={total:.3f}",
        "-filter_complex", audio_filter,
        "-map", "0:v", "-map", "[a]", "-vf", subtitle_filter,
        "-c:v", "libx264", "-preset", "medium", "-crf", "20",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
        "-shortest", "-movflags", "+faststart", output,
    ])
    print(f"saved {output}")


if __name__ == "__main__":
    main()
