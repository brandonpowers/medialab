#!/usr/bin/env python3
"""
Strip non-English audio tracks from large media files.
This script runs inside the ARM container which has ffmpeg/ffprobe.

Usage:
    python3 strip-non-english-audio.py [--min-size GB] [--dry-run] [--file PATH]

Examples:
    python3 strip-non-english-audio.py --min-size 50 --dry-run
    python3 strip-non-english-audio.py --min-size 50
    python3 strip-non-english-audio.py --file "/path/to/movie.mkv" --dry-run
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def get_file_size_gb(path: str) -> float:
    """Get file size in GB."""
    return os.path.getsize(path) / (1024 ** 3)


def get_audio_streams(path: str) -> list:
    """Get audio stream info from file using ffprobe."""
    cmd = [
        'ffprobe', '-v', 'quiet', '-print_format', 'json',
        '-show_streams', path
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        data = json.loads(result.stdout)
        streams = []
        for s in data.get('streams', []):
            if s.get('codec_type') == 'audio':
                streams.append({
                    'index': s.get('index'),
                    'codec': s.get('codec_name'),
                    'lang': s.get('tags', {}).get('language', 'und'),
                    'channels': s.get('channels'),
                    'title': s.get('tags', {}).get('title', '')
                })
        return streams
    except Exception as e:
        print(f"  Error probing file: {e}")
        return []


def is_english_track(track: dict) -> bool:
    """Check if audio track is English or undefined."""
    lang = track.get('lang', '').lower()
    return lang in ('eng', 'en', 'und', '')


def process_file(path: str, temp_dir: str, dry_run: bool = True) -> tuple:
    """
    Process a single file, removing non-English audio tracks.
    Returns (success, saved_gb).
    """
    filename = os.path.basename(path)
    original_size = get_file_size_gb(path)

    print(f"\n{'='*60}")
    print(f"File: {filename}")
    print(f"Size: {original_size:.2f} GB")

    # Get audio track info
    audio_streams = get_audio_streams(path)
    if not audio_streams:
        print("  Status: Could not read audio streams, skipping")
        return False, 0

    eng_tracks = [t for t in audio_streams if is_english_track(t)]
    non_eng_tracks = [t for t in audio_streams if not is_english_track(t)]

    print(f"  Audio tracks: {len(audio_streams)} total")
    print(f"    - English/und: {len(eng_tracks)} tracks")
    for t in eng_tracks:
        print(f"      [{t['index']}] {t['codec']} {t['channels']}ch - {t['lang']}")
    print(f"    - Non-English: {len(non_eng_tracks)} tracks")
    for t in non_eng_tracks:
        print(f"      [{t['index']}] {t['codec']} {t['channels']}ch - {t['lang']}")

    if not non_eng_tracks:
        print("  Status: No non-English audio to remove, skipping")
        return False, 0

    if not eng_tracks:
        print("  Status: No English audio found, skipping (safety check)")
        return False, 0

    # Build ffmpeg command
    temp_file = os.path.join(temp_dir, filename)

    # Map arguments: all video, only English audio, all subtitles, all attachments
    map_args = ['-map', '0:v']
    for t in eng_tracks:
        map_args.extend(['-map', f"0:{t['index']}"])
    map_args.extend(['-map', '0:s?', '-map', '0:t?'])

    cmd = ['ffmpeg', '-y', '-i', path] + map_args + ['-c', 'copy', temp_file]

    if dry_run:
        print(f"  Status: DRY RUN - Would remove {len(non_eng_tracks)} non-English tracks")
        # Estimate savings (rough: ~500kbps per AC3 track, ~1.5Mbps per DTS track)
        estimated_savings = 0
        for t in non_eng_tracks:
            if t['codec'] in ('dts', 'truehd'):
                estimated_savings += 1.5 * 3600 * 2.5 / 8 / 1024  # ~1.7GB for 2.5hr movie
            else:
                estimated_savings += 0.5 * 3600 * 2.5 / 8 / 1024  # ~0.6GB for 2.5hr movie
        print(f"  Estimated savings: ~{estimated_savings:.1f} GB")
        return True, estimated_savings

    print(f"  Status: Processing (removing {len(non_eng_tracks)} tracks)...")

    try:
        # Create temp directory if needed
        os.makedirs(temp_dir, exist_ok=True)

        # Run ffmpeg
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)

        if result.returncode != 0:
            print(f"  Status: ERROR - ffmpeg failed")
            print(f"  {result.stderr[:500]}")
            if os.path.exists(temp_file):
                os.remove(temp_file)
            return False, 0

        new_size = get_file_size_gb(temp_file)
        saved = original_size - new_size

        print(f"  New size: {new_size:.2f} GB (saved {saved:.2f} GB)")

        # Replace original
        os.replace(temp_file, path)
        print(f"  Status: Complete - replaced original file")

        return True, saved

    except subprocess.TimeoutExpired:
        print("  Status: ERROR - ffmpeg timed out")
        if os.path.exists(temp_file):
            os.remove(temp_file)
        return False, 0
    except Exception as e:
        print(f"  Status: ERROR - {e}")
        if os.path.exists(temp_file):
            os.remove(temp_file)
        return False, 0


def find_large_files(media_dir: str, min_size_gb: float) -> list:
    """Find all video files larger than min_size_gb."""
    files = []
    for ext in ('*.mkv', '*.mp4', '*.avi'):
        for path in Path(media_dir).rglob(ext):
            if path.is_file():
                size = get_file_size_gb(str(path))
                if size >= min_size_gb:
                    files.append(str(path))
    return sorted(files, key=lambda x: get_file_size_gb(x), reverse=True)


def main():
    parser = argparse.ArgumentParser(description='Strip non-English audio from large media files')
    parser.add_argument('--min-size', type=float, default=50, help='Minimum file size in GB (default: 50)')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without making changes')
    parser.add_argument('--file', type=str, help='Process a specific file instead of scanning')
    parser.add_argument('--media-dir', type=str, default='/home/arm/movies/movies', help='Media directory to scan')
    parser.add_argument('--temp-dir', type=str, default='/home/arm/movies/transcode', help='Temp directory for processing')

    args = parser.parse_args()

    print("=" * 60)
    print("Strip Non-English Audio Script")
    print("=" * 60)
    print(f"Minimum size: {args.min_size} GB")
    print(f"Dry run: {args.dry_run}")
    print(f"Media dir: {args.media_dir}")

    if args.file:
        files = [args.file]
    else:
        print(f"\nScanning for files > {args.min_size} GB...")
        files = find_large_files(args.media_dir, args.min_size)
        print(f"Found {len(files)} files")

    total_saved = 0
    processed = 0

    for path in files:
        success, saved = process_file(path, args.temp_dir, args.dry_run)
        if success:
            total_saved += saved
            processed += 1

    print(f"\n{'=' * 60}")
    print("Summary")
    print("=" * 60)
    print(f"Files processed: {processed}")
    if args.dry_run:
        print(f"Estimated savings: ~{total_saved:.1f} GB")
    else:
        print(f"Total saved: {total_saved:.2f} GB")


if __name__ == '__main__':
    main()
