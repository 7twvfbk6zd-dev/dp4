#!/usr/bin/env python3
"""Build an SRT, timeline, and optional combined WAV from voiceover clips."""

import argparse
import json
import wave
from pathlib import Path


def wave_duration(path):
    with wave.open(str(path), "rb") as source:
        return source.getnframes() / source.getframerate(), source.getparams()


def timestamp(seconds):
    milliseconds = round(seconds * 1000)
    hours, milliseconds = divmod(milliseconds, 3_600_000)
    minutes, milliseconds = divmod(milliseconds, 60_000)
    seconds, milliseconds = divmod(milliseconds, 1000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{milliseconds:03d}"


def silent_frames(seconds, rate, channels, sample_width):
    return b"\x00" * (round(seconds * rate) * channels * sample_width)


def build_combined(entries, destination, lead_in, tail, gap, params):
    channels, sample_width, rate = params[:3]
    with wave.open(str(destination), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(sample_width)
        output.setframerate(rate)
        output.writeframes(silent_frames(lead_in, rate, channels, sample_width))
        for index, entry in enumerate(entries):
            with wave.open(entry["file"], "rb") as source:
                output.writeframes(source.readframes(source.getnframes()))
            if index != len(entries) - 1:
                output.writeframes(silent_frames(gap, rate, channels, sample_width))
        output.writeframes(silent_frames(tail, rate, channels, sample_width))


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--voiceover", required=True)
    parser.add_argument("--timeline", required=True)
    parser.add_argument("--srt", required=True)
    parser.add_argument("--combined")
    parser.add_argument("--gap", type=float, default=0.35)
    parser.add_argument("--lead-in", type=float, default=0.40)
    parser.add_argument("--tail", type=float, default=0.60)
    return parser.parse_args()


def main():
    args = parse_args()
    voiceover_path = Path(args.voiceover)
    voiceover_dir = voiceover_path.parent
    entries = json.loads(voiceover_path.read_text(encoding="utf-8"))
    if not entries:
        raise SystemExit("voiceover.json has no entries")

    cursor = args.lead_in
    timeline = []
    params = None
    for entry in entries:
        path = voiceover_dir / entry["file"]
        duration, clip_params = wave_duration(path)
        if params is None:
            params = clip_params
        elif clip_params[:3] != params[:3]:
            raise SystemExit(f"audio format mismatch: {path}")
        timeline.append({
            "panel": entry["panel"],
            "type": entry["type"],
            "text": entry["text"],
            "file": str(path),
            "duration": round(duration, 3),
            "start": round(cursor, 3),
            "end": round(cursor + duration, 3),
        })
        cursor += duration + args.gap

    total_duration = cursor - args.gap + args.tail
    output = {
        "lead_in": args.lead_in,
        "tail": args.tail,
        "gap": args.gap,
        "total_duration": round(total_duration, 3),
        "entries": timeline,
    }
    Path(args.timeline).write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    srt_lines = []
    for index, entry in enumerate(timeline, 1):
        srt_lines.extend([
            str(index),
            f"{timestamp(entry['start'])} --> {timestamp(entry['end'])}",
            entry["text"],
            "",
        ])
    Path(args.srt).write_text("\n".join(srt_lines), encoding="utf-8")

    if args.combined:
        build_combined(timeline, Path(args.combined), args.lead_in, args.tail, args.gap, params)

    for entry in timeline:
        print(f"{entry['start']:6.2f}-{entry['end']:6.2f}  {entry['panel']}: {entry['text']}")
    print(f"total: {total_duration:.2f}s")


if __name__ == "__main__":
    main()
