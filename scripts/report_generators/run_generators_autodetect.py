#!/usr/bin/env python3
"""
Auto-run visualization generators for a generated_reports directory.

The project's generators expect files prefixed with `urllc_`.
Many test dirs use other prefixes (e.g., `eMBB_`, `embb_`, `best_effort_`).
This script detects the existing prefix, creates temporary symlinks with the
`urllc_` names the generators look for, runs both generators, and then
removes the symlinks.

Usage: python3 scripts/report_generators/run_generators_autodetect.py <generated_reports_dir>
"""
import os
import sys
import glob
import subprocess
import shutil
import tempfile
from pathlib import Path


def find_prefix(d: Path):
    # Look for files like <prefix>_ecdf_rtt_*.csv or <prefix>_latencia_stats_* or <prefix>_odte_*
    patterns = ['*_ecdf_rtt_*.csv', '*_latencia_stats_middts_to_simulator_*.csv', '*_odte_*.csv', '*_windows_*.csv']
    for p in patterns:
        matches = list(d.glob(p))
        if matches:
            name = matches[0].name
            # determine which known suffix appears and split on it to extract full prefix
            for suf in ['_ecdf_rtt_', '_latencia_stats_middts_to_simulator_', '_latencia_stats_simulator_to_middts_', '_odte_', '_windows_']:
                if suf in name:
                    return name.split(suf, 1)[0]
    return None


def copy_to_temp_with_urllc_names(d: Path, prefix: str, tmp: Path):
    """Copy CSVs from d into tmp, renaming them to the urllc_* names the generators expect.

    Returns list of dest paths created.
    """
    created = []
    mapping_suffixes = [
        ('ecdf_rtt', '_ecdf_rtt_'),
        ('lat_m2s', '_latencia_stats_middts_to_simulator_'),
        ('lat_s2m', '_latencia_stats_simulator_to_middts_'),
        ('odte', '_odte_'),
        ('windows', '_windows_'),
    ]

    for _name, suf in mapping_suffixes:
        candidates = list(d.glob(f"{prefix}{suf}*.csv"))
        if not candidates:
            candidates = list(d.glob(f"{prefix.lower()}{suf}*.csv"))
        if not candidates:
            candidates = list(d.glob(f"{prefix.upper()}{suf}*.csv"))
        if candidates:
            src = candidates[-1]
            dest_name = f"urllc{suf}{src.name.split(suf)[-1]}"
            dest = tmp / dest_name
            try:
                shutil.copy2(src, dest)
                created.append(dest)
                print(f'Copied {src} -> {dest}')
            except Exception as e:
                print('Failed to copy', src, '->', dest, e)
    return created


def cleanup(links):
    for p in links:
        try:
            if p.exists() or p.is_symlink():
                p.unlink()
                print('Removed', p)
        except Exception as e:
            print('Failed to remove', p, e)


def run_generators(d: Path):
    scripts = ['enhanced_visualize.py', 'visualize_reports.py']
    base = Path(__file__).resolve().parent
    # We'll run the generators in the tmpdir we created/copied files into (tmpd)
    # so they write plots to tmpd/plots and we can copy them back deterministically.
    def run_in_dir(tmpd: Path):
        for s in scripts:
            script_path = base / s
            if not script_path.exists():
                print('Generator not found:', script_path)
                continue
            print('Running', script_path, 'in', tmpd)
            try:
                subprocess.run(['python3', str(script_path), str(tmpd)], check=True)
            except subprocess.CalledProcessError as e:
                print('Generator failed:', e)

    return run_in_dir


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    d = Path(sys.argv[1])
    if not d.is_dir():
        print('dir not found:', d)
        sys.exit(2)

    plots = d / 'plots'
    if plots.exists() and any(plots.iterdir()):
        print('Plots already exist in', plots)
        return

    prefix = find_prefix(d)
    if not prefix:
        print('Could not detect CSV prefix in', d)
        sys.exit(3)

    print('Detected prefix:', prefix)
    with tempfile.TemporaryDirectory() as tdir:
        tmpd = Path(tdir)
        created = copy_to_temp_with_urllc_names(d, prefix, tmpd)
        run_in_dir = run_generators(d)
        try:
            # run generators inside tmpd where the urllc_* files exist
            run_in_dir(tmpd)
            # copy generated PNGs back to the original generated_reports/plots
            src_plots = tmpd / 'plots'
            dest_plots = d / 'plots'
            if src_plots.exists():
                dest_plots.mkdir(exist_ok=True)
                for f in src_plots.iterdir():
                    if f.suffix.lower() in ['.png', '.jpg', '.jpeg']:
                        dst = dest_plots / f.name
                        try:
                            shutil.copy2(f, dst)
                            print('Copied plot', f, '->', dst)
                        except Exception as e:
                            print('Failed to copy', f, '->', dst, e)
        finally:
            # cleanup temp files
            for p in created:
                try:
                    if p.exists():
                        p.unlink()
                except Exception:
                    pass
            # tmpdir is automatically removed


if __name__ == '__main__':
    main()
