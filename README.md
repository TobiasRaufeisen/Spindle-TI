# SpindlePilot Analysis

Analysis pipeline for the SpindlePilot study investigating the effects of temporal interference (TI) stimulation on sleep spindles during nap sessions.

**Subjects**: sub5-sub24 (20 participants), Session 1
**Conditions**: 5 Hz TI stimulation (`x5HZ`), 1 Hz TI stimulation (`x1HZ`), Sham/OFF (`OFF`)
**Key data file**: `comprehensive_analysis.mat` (all event tables, sleep stages, trial info)

---

## Directory Structure

```
Spindle-TI/
  config/                                    # Central configuration & utility functions
  0_preprocessing/                           # EEG preprocessing pipeline
    functions/                               # preprocessing helper functions
  1_eventDetection/                          # Spindle & slow wave detection
    functions/                               # Event loading, browser, verification
    eventDetectionResults/                   # Output: comprehensive_analysis.mat
  2_FIGURE1_MethodsAndDetection/             # Figure 1: Methods overview
    functions/                               # Save helpers
    outputs/                                 # Generated figures
  3_FIGURE2_Power/                           # Figure 2: Spectral power analysis
    functions/                               # Shared TFR/topography helpers
    functions_figure2_topography/            # Topography helpers
    functions_figure2_tfr_timeseries/        # TFR time-series helpers
    functions_powerSpectrum/                 # Power-spectrum helpers
    TFR_1HzSmoothing/                        # Pre-computed TFR data (external archive)
    outputs/                                 # Generated figures + stats
  4_FIGURE3_Events/                          # Figure 3: Event-based analysis
    outputs/                                 # Generated figures + R statistics
  recordingScripts/                          # Experiment-time stimulation scripts (archival)
    setupTesting/                            # Hardware/trigger testing scripts
```

---

## Analysis Pipeline Overview

### 1. Preprocessing (`0_preprocessing/`)

**Main script**: `spindlePilot_AutomaticPreprocess.m`

Pipeline: Load XDF -> Separate channels -> Filter (FIR + notch) -> Clean artifacts -> ICA -> Interpolate -> Re-reference -> Epoch -> Trial rejection -> Save

| Function | Purpose |
|----------|---------|
| `spindlePilot_loadData.m` | Load XDF files from BIDS directory |
| `spindlePilot_separateChannels.m` | Split main EEG from AUX/marker channels |
| `spindlePilot_cleanMainEEG.m` | Slope-based artifact detection + filtering + interpolation |
| `spindlePilot_interpolateChannels.m` | Interpolate rejected channels (EasyCap layout) |
| `spindlePilot_rereferenceMainData.m` | Average or mastoid re-reference |
| `spindlePilot_createEpochsAllData.m` | Epoch by condition (OFF/1HZ/5HZ + ramp/refractory) |
| `spindlePilot_createEpochsAllData2.m` | Extended epoching with TI sync + first-OFF removal |
| `spindlePilot_matchTrialCounts.m` | Balance trial counts across conditions |
| `spindlePilot_finalizeAndSave.m` | Save complete + analysis-ready + EDF outputs |

Other helpers: `alignTimestamps`, `autoRejectChannelsMain`, `mergeChannels`, `relabelElectrodes`, `transferCleaningArtifacts`, `rejectArtifactsSeparated`, `loadEasycapLayout`, `interactiveDataExplorer`

### 2. Event Detection (`1_eventDetection/`)

**MATLAB**: `spindlePilot_comprehensiveEventAnalysis.m`
Loads preprocessed data + YASA outputs, creates sample-accurate event tables with trial context, generates `comprehensive_analysis.mat`.

**Python**: `spindlePilot_automaticSpindleSlowwavesYASA.py`
Uses YASA toolbox for automatic spindle and slow wave detection from EDF files. Outputs CSV tables + sleep stage classification per subject.

| Function | Purpose |
|----------|---------|
| `addSlowwavePhaseInformation.m` | Compute phase vectors for slow wave coupling analysis |
| `spindlePilot_launchBrowser.m` | Launch interactive EEG browser with event overlays |
| `spindlePilot_EnhancedBrowser.m` | Interactive browser class with sleep stage filtering |

### 3. Figure 1 - Methods & Detection (`2_FIGURE1_MethodsAndDetection/`)

Figures demonstrating the experimental setup, sleep staging, and detection quality.

| Script | Content |
|--------|---------|
| `figure1_sleepStagesBarplot.m` | Sleep stage durations per condition (grouped barplot) |
| `figure1_averageHypnogram.m` | Average hypnogram across all subjects |
| `figure1_singleHypnogram.m` | Representative single-subject hypnogram |
| `figure1_hypnoProbability.m` | Hypnodensity: proportion of subjects per sleep stage over time |
| `figure1_spindleDetection.m` | Example trials with detected spindles marked |
| `figure1_spindleWaveform.m` | Average spindle waveforms aligned to peak per condition |
| `figure1_overviewTFR_multitaper.m` | Whole-night multitaper TFR with integrated hypnogram and condition coloring |


### 4. Figure 2 - Spectral Power (`3_FIGURE2_Power/`)

TFR-based analysis of stimulation effects on spindle-band power.

**TFR Computation** (run first):
| Script | Purpose |
|--------|---------|
| `spindlePilot_compute_TFR_1HzSmoothing.m` | FieldTrip multitaper TFR (1 Hz spectral smoothing) per participant/condition/trial; writes the per-trial TFR files |

**Figure scripts**:
| Script | Content |
|--------|---------|
| `figure2_topography.m` | Spindle-band power topography + cluster statistics |
| `figure2_thetaBarplot.m` | Theta-band power barplot (supplementary control) |
| `figure2_tfr_timeseries.m` | Time-frequency representation with ROI + cluster differences |
| `figure2_powerSpectrum.m` | Power-spectrum comparison across conditions + cluster statistics |

**Configuration**: `figure2_paths_config.m` - Centralized paths for Figure 2

Helper functions live in `functions_figure2_topography/`, `functions_figure2_tfr_timeseries/`, and `functions_powerSpectrum/` (the latter for `figure2_powerSpectrum.m`). Shared **key functions in `functions/`**:
| Function | Purpose |
|----------|---------|
| `spindlePilot_visual_topographyTFR_load.m` | Load pre-computed per-trial TFR data |
| `spindlePilot_visual_topographyTFR_filter.m` | Non-destructive trial filtering (sleep stage -> artifact -> power) |
| `spindlePilot_visual_topographyTFR_compute_from_filtered.m` | Topographic power from the filtered trials |
| `spindlePilot_visual_topographyTFR_stats.m` | Cluster-corrected permutation statistics |
| `spindlePilot_visual_topographyTFR_config.m` | Default TFR topography configuration |
| `initialize_fieldtrip.m` | FieldTrip toolbox initialization |
| `create_diverging_colormap.m` | Blue-white-red colormap for difference / t-value maps |

### 5. Figure 3 - Event Statistics (`4_FIGURE3_Events/`)

Event-level analysis of spindle properties across stimulation conditions.

**Figure scripts**:
| Script | Content |
|--------|---------|
| `figure3_densityTopography.m` | Spindle density topography + cluster statistics |
| `figure3_onsetDelayBarplot.m` | Onset delay from trial start to first spindle (LMM) |
| `figure3_onsetDelayTimecourse.m` | "Horse race" timecourse of spindle onsets |
| `figure3_temporalHistogram.m` | Spindle onset distribution around trial onset (LMM + FDR) |
| `figure3_temporalHistogram_zscoreOnly.m` | Temporal-histogram variant (z-scored rates) |
| `figure3_emmFromTextReport.m` | EMM +/- CI figure built from the R GLMM text report |
| `figure3_metricsBarplot.m` | Spindle metrics comparison (Duration, Amplitude, Frequency) |
| `figure3_densityBarplot.m` | Spindle density barplot with LME statistics |
| `figure3_M0_barplot.m` | Spindle-occurrence (M0) barplot from precomputed stats |

**Statistics**:
| Script | Purpose |
|--------|---------|
| `eventHistStats.R` | Binomial GLMM of per-trial spindle occurrence (`lme4`); writes `outputs/GLMM_statistical_results.txt`, consumed by `figure3_emmFromTextReport.m` |

Most statistical models are computed *inside* the figure scripts above (e.g. the density/metrics LMEs in `figure3_metricsBarplot.m` and `figure3_densityBarplot.m`, and the LMM + FDR contrasts in `figure3_temporalHistogram.m`). The binomial GLMM of spindle occurrence is run in R (`eventHistStats.R`).

---

## Configuration (`config/`)

| File | Purpose |
|------|---------|
| `spindlePilot_paths.m` | Central path resolver for all project directories |
| `analysis_config.m` | Global analysis parameters + figure appearance defaults |
| `spindlePilot_add_brewermap.m` | Optional BrewerMap colormap toolbox loader |
| `spindlePilot_resolve_data_file.m` | Flexible file resolver with wildcard patterns |

**Startup**: `spindlePilot_startup.m` (root level) initializes paths, FieldTrip, and environment.

---

## Recording Scripts (`recordingScripts/`) - Archival

These scripts were used during the actual experiment for stimulation control and are preserved for documentation. They reference the recording computer's file system (D: drive) and are **not** part of the analysis pipeline.

| Script | Purpose |
|--------|---------|
| `spindlePilot_counterbalancedConditions.m` | Generate counterbalanced condition CSV files |
| `spindlePilot_TIControlGUI_continuous.m` | Step-through stimulator with LSL markers + DAQ |
| `spindlePilot_TIControlGUI_manual.m` | Manual stimulation GUI for testing |
| `spindlePilot_TIControl_manual.m` | Basic LSL + NIDAQ trigger testing |
| `spindlePilot_startup_recording.m` | Recording-PC environment startup (archival; separate from the analysis `spindlePilot_startup.m`) |
| `setupTesting/*.m` | Trigger timing analysis and first-participant tests |

---

## Data Locations

| Data | Location |
|------|----------|
| Analysis-ready `.mat` files | `data/analysis/` (gitignored) |
| EDF exports (YASA input) | `data/EDF/` (gitignored) |
| Full preprocessing `.mat` (`*_COMPLETE.mat`) | `data/COMPLETE/` (gitignored) |
| Event detection results | `1_eventDetection/eventDetectionResults/` |
| Sleep staging (YASA) | `1_eventDetection/eventDetectionResults/SleepStagingAndEvents/` |
| Pre-computed TFR data | `3_FIGURE2_Power/TFR_1HzSmoothing/` (gitignored) |
| Figure outputs | `{figure_folder}/outputs/` |

### Data Availability

Raw EEG, processed `*_ANALYSIS.mat` files, the per-trial TFR data, and the large result `.mat` files are not included in the repository and are available from **[external archive -- DOI to add]**. After download, place files under the in-repo `data/` folder (gitignored by default):

```
Spindle-TI/data/analysis/sub*_ses1_ANALYSIS.mat   # processed EEG (event detection + figures)
Spindle-TI/data/EDF/sub*_ses1.edf                 # 256 Hz exports (YASA detection)
Spindle-TI/data/COMPLETE/sub*_ses1_COMPLETE.mat   # full preprocessing outputs (rejection stats)
Spindle-TI/3_FIGURE2_Power/TFR_1HzSmoothing/      # pre-computed TFR (also gitignored)
```

---

## External Dependencies

**MATLAB** (primary analysis environment) with the Signal Processing and Statistics & Machine Learning toolboxes, plus:
- **FieldTrip** (Oostenveld et al., 2011) -- preprocessing, TFR, topography, cluster statistics
- **EEGLAB** -- EEG data structures / electrode layouts
- **xdfimport** (`load_xdf`, `xdf2fieldtrip`) -- reading raw XDF recordings
- **shadedErrorBar** -- mean +/- error plotting
- **BrewerMap** (optional) -- colormaps

**Python >= 3.8** (automatic event detection): see `1_eventDetection/requirements.txt` --
`yasa` (Vallat & Walker, 2021), `mne`, `numpy`, `scipy`, `pandas`, `matplotlib`.

**R** (GLMM sensitivity analysis in `4_FIGURE3_Events/eventHistStats.R`):
`lme4`, `lmerTest`, `car`, `emmeans`, `multcomp`, `DHARMa`, `performance`, `ggplot2`, `dplyr`, `tidyr`
(installed automatically via `pacman::p_load`).

---

## Quick Start

```matlab
% 1. Initialize the environment (run from the repo root). This adds all
%    function folders to the MATLAB path and sets up FieldTrip.
spindlePilot_startup();

% 2. Run any figure script, e.g. Figure 1
figure1_sleepStagesBarplot();

% 3. (Optional) recompute the time-frequency data first -- large; see Data Locations
spindlePilot_compute_TFR_1HzSmoothing();
```

All scripts resolve their paths relative to their own location (via `mfilename`), so the repository can be cloned anywhere. Large data files (raw EEG and pre-computed TFR) are not included in the repository and live in an external archive -- see **Data Locations** above.

---

## License

Released under the MIT License -- see [LICENSE](LICENSE). (c) 2026 Tobias Raufeisen.

## Citation

If you use this code, please cite the associated publication (metadata in [CITATION.cff](CITATION.cff)).
