# ── CONFIG ────────────────────────────────────────────────────────────────────
import mne
from pathlib import Path
CONFIG = {
    # Source data -------------------------------------------------------------
    "participants": [
        {"subject": 5, "session": 1},
        {"subject": 6, "session": 1},
        {"subject": 7, "session": 1},
        {"subject": 8, "session": 1},
        {"subject": 9, "session": 1},
        {"subject": 10, "session": 1},
        {"subject": 11, "session": 1},
        {"subject": 12, "session": 1},
        {"subject": 13, "session": 1},
        {"subject": 14, "session": 1},
        {"subject": 15, "session": 1},
        {"subject": 16, "session": 1},
        {"subject": 17, "session": 1},
        {"subject": 18, "session": 1},
        {"subject": 19, "session": 1},
        {"subject": 20, "session": 1},
        {"subject": 21, "session": 1},
        {"subject": 22, "session": 1},
        {"subject": 23, "session": 1},
        {"subject": 24, "session": 1},
    ],
    "edf_dir"     : Path(__file__).resolve().parents[1] / "data" / "EDF",   # in-repo, gitignored (see README "Data Availability")
    "channels"    : "all -EMG1EMG2 -LOCA2 -ROCA2 -XX -XXX",      # Options:
    #"channels"    : "Cz",
                                                        # "all" = use all EEG channels
                                                        # "all -CHAN1 -CHAN2" = all except specified channels
                                                        # ["C3A2", "Cz", "C4A1", ...] = specific channel list

    # Output directory --------------------------------------------------------
    "out_dir"     : Path(__file__).resolve().parent / "eventDetectionResults" / "SleepStagingAndEvents",

    # Detection parameters ----------------------------------------------------
    "spindle"  : {"duration": (0.3, 3), "freq_sp": (10, 16)},
    "slowwave" : {"amp_neg": (15, 200),
                  "amp_pos": (15, 200),
                  "amp_ptp": (30, 400),
                  "coupling": True},

    # Plot saving -------------------------------------------------------------
    "plot_fmt"     : "png",   # png / pdf / svg …
    "plot_dpi"     : 300,
}
# ──────────────────────────────────────────────────────────────────────────────

# ── Imports & warning filter (optional) ──────────────────────────────────────
import warnings, re
warnings.filterwarnings(
        "ignore",
        category=FutureWarning,
        message=re.escape("The `ci` parameter is deprecated."),
)

import mne, yasa, pandas as pd, matplotlib.pyplot as plt
# -----------------------------------------------------------------------------

def get_eeg_channels(raw, channel_config):
    """
    Get EEG channels based on configuration.
    
    Parameters:
    -----------
    raw : mne.io.Raw
        Raw MNE object
    channel_config : str or list
        Options:
        - "all": use all EEG channels
        - "all -CHAN1 -CHAN2": use all channels except specified ones
        - list: use specific channel names
    
    Returns:
    --------
    list : List of channel names to use
    """
    if isinstance(channel_config, str):
        if channel_config.startswith("all"):
            # Get all EEG channels (exclude non-EEG channels like EOG, EMG, etc.)
            eeg_channels = []
            for ch_name in raw.ch_names:
                ch_type = raw.get_channel_types([ch_name])[0]
                if ch_type == 'eeg':
                    eeg_channels.append(ch_name)
            
            # If no channels are marked as EEG, use all channels (common in EDF files)
            if not eeg_channels:
                print("No channels marked as EEG type, using all available channels")
                eeg_channels = raw.ch_names.copy()
            
            # Handle exclusions (e.g., "all -LOC2 -ROC1 -EMG1")
            if " -" in channel_config:
                exclusions_part = channel_config.split("all", 1)[1].strip()
                if exclusions_part.startswith("-"):
                    # Parse exclusions: split by spaces and remove the "-" prefix
                    exclusions = []
                    for part in exclusions_part.split():
                        if part.startswith("-"):
                            exclusions.append(part[1:])  # Remove the "-" prefix
                    
                    # Remove excluded channels
                    original_count = len(eeg_channels)
                    eeg_channels = [ch for ch in eeg_channels if ch not in exclusions]
                    excluded_count = original_count - len(eeg_channels)
                    
                    print(f"Excluded {excluded_count} channels: {[ch for ch in exclusions if ch in raw.ch_names]}")
                    
                    # Warn about exclusions that weren't found
                    not_found = [ch for ch in exclusions if ch not in raw.ch_names]
                    if not_found:
                        print(f"Warning: Exclusion channels not found in data: {not_found}")
            
            return eeg_channels
        else:
            # Single channel name as string
            if channel_config in raw.ch_names:
                return [channel_config]
            else:
                print(f"Warning: Channel {channel_config} not found in data")
                return []
    else:
        # Use specified channels (list), but filter out any that don't exist in the data
        available_channels = [ch for ch in channel_config if ch in raw.ch_names]
        if len(available_channels) != len(channel_config):
            missing = set(channel_config) - set(available_channels)
            print(f"Warning: Missing channels {missing}")
        return available_channels

def process_participant(subject, session, config):
    print(f"\n=== Processing Subject {subject}, Session {session} ===")
    
    # ── Helper paths ─────────────────────────────────────────────────────────
    edf_path = config["edf_dir"] / f"sub{subject}_ses{session}.edf"
    
    if not edf_path.exists():
        print(f"Error: File not found: {edf_path}")
        return {"subject": subject, "session": session, "status": "file_not_found"}
    
    out_dir = config["out_dir"]
    out_dir.mkdir(parents=True, exist_ok=True)
    
    # Filenames include subject and session
    spindle_csv   = out_dir / f"subject{subject}_spindles.csv"
    slowwave_csv  = out_dir / f"subject{subject}_slowwaves.csv"
    spindle_plot  = out_dir / f"subject{subject}_spindles.{config['plot_fmt']}"
    slowwave_plot = out_dir / f"subject{subject}_slowwaves.{config['plot_fmt']}"
    
    try:
        # ── Load data ────────────────────────────────────────────────────────
        raw = mne.io.read_raw_edf(edf_path.as_posix(), preload=True)
        print(f"Available channels: {raw.ch_names}")
        print(f"Sampling rate: {raw.info['sfreq']} Hz")
        
        # Get channels to use
        channels_to_use = get_eeg_channels(raw, config["channels"])
        print(f"Using channels: {channels_to_use}")
        
        if not channels_to_use:
            print("Error: No valid channels found")
            return {"subject": subject, "session": session, "status": "no_valid_channels"}
        
        raw_sel = raw.copy().pick_channels(channels_to_use).rescale(1e-6)
        sfreq = raw_sel.info["sfreq"]
        
        # ── Spindle detection & plot saving ─────────────────────────────────
        print("Detecting spindles...")
        sp = yasa.spindles_detect(
                raw_sel, sfreq,
                ch_names=channels_to_use,
                duration=config["spindle"]["duration"],
                freq_sp=config["spindle"]["freq_sp"],
        )
        
        if sp is not None:
            sp_df = sp.summary()
            ax_sp = sp.plot_average(errorbar=None, palette=['tab:grey'])
            ax_sp.figure.savefig(spindle_plot,
                                 dpi=config["plot_dpi"],
                                 bbox_inches="tight")
            plt.close(ax_sp.figure)      # free memory
            sp_df.to_csv(spindle_csv, index=False)
            spindle_count = len(sp_df)
        else:
            spindle_count = 0
            print("No spindles detected")
        
        # ── Slow-wave detection & plot saving ────────────────────────────────
        print("Detecting slow waves...")
        # raw_sel = raw.copy().pick_channels(channels_to_use).rescale(1e6)
        sw = yasa.sw_detect(
                raw_sel, sfreq,
                ch_names=channels_to_use,
                coupling=config["slowwave"]["coupling"],
                amp_neg=config["slowwave"]["amp_neg"],
                amp_pos=config["slowwave"]["amp_pos"],
                amp_ptp=config["slowwave"]["amp_ptp"],
        )
        
        if sw is not None:
            sw_df = sw.summary()
            ax_sw = sw.plot_average(errorbar=('ci', 95), palette="Reds_r")
            ax_sw.figure.savefig(slowwave_plot,
                                 dpi=config["plot_dpi"],
                                 bbox_inches="tight")
            plt.close(ax_sw.figure)
            sw_df.to_csv(slowwave_csv, index=False)
            slowwave_count = len(sw_df)
        else:
            slowwave_count = 0
            print("No slow waves detected")
        
        print(f"✓ Subject {subject}, Session {session} completed!")
        print(f"   Spindles: {spindle_count}, Slow waves: {slowwave_count}")
        print(f"   Files saved in: {out_dir}")
        
        return {
            "subject": subject,
            "session": session,
            "status": "success",
            "spindle_count": spindle_count,
            "slowwave_count": slowwave_count,
            "channels_used": len(channels_to_use)
        }
        
    except Exception as e:
        print(f"Error processing Subject {subject}, Session {session}: {str(e)}")
        return {"subject": subject, "session": session, "status": "error", "error": str(e)}

# ── Main processing loop ──────────────────────────────────────────────────────
def main():
    print("Starting multi-participant sleep analysis...")
    print(f"Output directory: {CONFIG['out_dir']}")
    print(f"Channel configuration: {CONFIG['channels']}")
    
    # Show what the channel config means
    if isinstance(CONFIG['channels'], str) and CONFIG['channels'].startswith('all'):
        if ' -' in CONFIG['channels']:
            exclusions = [part[1:] for part in CONFIG['channels'].split() if part.startswith('-')]
            print(f"  → Using all EEG channels except: {exclusions}")
        else:
            print(f"  → Using all available EEG channels")
    elif isinstance(CONFIG['channels'], list):
        print(f"  → Using {len(CONFIG['channels'])} specified channels")
    
    results = []
    
    for participant in CONFIG["participants"]:
        subject = participant["subject"]
        session = participant["session"]
        
        result = process_participant(subject, session, CONFIG)
        results.append(result)
    
    # ── Summary ──────────────────────────────────────────────────────────────
    print("\n" + "="*60)
    print("PROCESSING SUMMARY")
    print("="*60)
    
    successful = [r for r in results if r["status"] == "success"]
    failed = [r for r in results if r["status"] != "success"]
    
    print(f"Successfully processed: {len(successful)}/{len(results)} participants")
    
    if successful:
        total_spindles = sum(r["spindle_count"] for r in successful)
        total_slowwaves = sum(r["slowwave_count"] for r in successful)
        print(f"Total spindles detected: {total_spindles}")
        print(f"Total slow waves detected: {total_slowwaves}")
        
        print("\nSuccessful participants:")
        for r in successful:
            print(f"  Subject {r['subject']}, Session {r['session']}: "
                  f"{r['spindle_count']} spindles, {r['slowwave_count']} slow waves")
    
    if failed:
        print(f"\nFailed participants ({len(failed)}):")
        for r in failed:
            print(f"  Subject {r['subject']}, Session {r['session']}: {r['status']}")
            if "error" in r:
                print(f"    Error: {r['error']}")
    
    # Save summary to CSV
    summary_df = pd.DataFrame(results)
    summary_file = CONFIG["out_dir"] / "processing_summary.csv"
    summary_df.to_csv(summary_file, index=False)
    print(f"\nProcessing summary saved to: {summary_file}")

if __name__ == "__main__":
    main()