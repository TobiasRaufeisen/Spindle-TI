function figure2_powerSpectrum()
%% Power Spectrum: Stimulation Condition Comparison
% Compares Welch power spectra across stimulation conditions (5Hz, 1Hz, OFF)
% during 2-second stimulation windows in N2 sleep.
%
% Analysis pipeline:
%   1. Load and compute per-subject, per-channel Welch PSD (with optional caching)
%   2. Average selected channels per subject and compute grand means
%   3. Fit LME models on band-averaged power (Spindle, Artifact bands)
%   4. Run cluster-based permutation tests over frequency bins (Maris & Oostenveld, 2007)
%   5. Visualise power spectra with significance markers
%   6. Save figures, data, and statistical report

clear; clc;

%% ========== PARAMETERS ==========

% Paths
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
PROCESSED_DATA_DIR = fullfile(REPO_ROOT, 'data');  % in-repo, gitignored (see README "Data Availability")
OUTPUT_DIR         = fullfile(REPO_ROOT, '3_FIGURE2_Power', 'outputs');
COMPREHENSIVE_PATH = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults', 'comprehensive_analysis.mat');

% Subjects and session ('all' or cell array of subject IDs)
participants = 'all';
session      = 'ses1';

% Conditions
conditions_to_compare = {'x5HZ', 'x1HZ', 'OFF'};

% Electrodes ('all' or cell array of channel names)
channels_to_compute = 'all';
channels_to_plot    = 'all';

% Sleep stage filter
sleep_stages_filter = 2;  % N2 only

% Cache
USE_CACHE = false;
CACHE_DIR = fullfile(REPO_ROOT, '3_FIGURE2_Power', 'cache');

% Epoch time range (seconds relative to trial onset; [] = full epoch)
time_range = [0.25 1.75];

% Frequency ranges
freq_range    = [0.5, 20];
spindle_band  = [12, 16];
artifact_band = [4.5, 5.5];

% LME settings: 'average' or 'random' electrode handling
ELECTRODE_HANDLING = 'average';

% Cluster-based permutation test (Maris & Oostenveld, 2007)
cluster_cfg = struct();
cluster_cfg.n_permutations = 5000;
cluster_cfg.forming_alpha  = 0.15;
cluster_cfg.cluster_alpha  = 0.05;
cluster_cfg.comparisons    = {'x5HZ','OFF'; 'x1HZ','OFF'; 'x5HZ','x1HZ'};
cluster_cfg.comp_labels    = {'x5HZ vs OFF', 'x1HZ vs OFF', 'x5HZ vs x1HZ'};

% Plot settings
SHOW_SHADED_ERROR = true;
pub = struct();
pub.fig_width_cm   = 8.5;
pub.fig_height_cm  = 6;
pub.font_name      = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;
pub.line_width     = 1.2;

%% ========== SETUP ==========
addpath(fullfile(REPO_ROOT, '3_FIGURE2_Power', 'functions_powerSpectrum'));

analysis_data_path = fullfile(PROCESSED_DATA_DIR, 'analysis');

participants = ps_resolve_participants(participants, analysis_data_path, session);
n_participants = length(participants);

fprintf('=== Power Spectrum Comparison ===\n');
fprintf('Subjects (%d): %s\n', n_participants, strjoin(participants, ', '));
fprintf('Session: %s  |  Conditions: %s\n', session, strjoin(conditions_to_compare, ', '));

% Pack computation config
comp_cfg = struct();
comp_cfg.session               = session;
comp_cfg.conditions_to_compare = conditions_to_compare;
comp_cfg.channels_to_compute   = channels_to_compute;
comp_cfg.sleep_stages_filter   = sleep_stages_filter;
comp_cfg.time_range            = time_range;
comp_cfg.comprehensive_path    = COMPREHENSIVE_PATH;
comp_cfg.USE_CACHE             = USE_CACHE;
comp_cfg.CACHE_DIR             = CACHE_DIR;

%% 1. Compute per-subject power spectra
[spectra_data, freq, subjects_used, channels_computed] = ...
    ps_compute_spectra(comp_cfg, participants, analysis_data_path);

%% 2. Average channels and compute grand means
[condition_stats, plot_ch_indices, channels_to_plot_resolved] = ...
    ps_average_conditions(spectra_data, freq, conditions_to_compare, ...
        channels_computed, channels_to_plot, subjects_used);

%% 3. LME statistics on band-averaged power
lme_results = ps_fit_lme(spectra_data, freq, conditions_to_compare, ...
    channels_computed, plot_ch_indices, subjects_used, ELECTRODE_HANDLING);

%% 4. Cluster-based permutation test
cluster_results = ps_cluster_permutation_test(condition_stats, spectra_data, ...
    freq, freq_range, cluster_cfg);

%% 5. Visualise power spectra with significance markers
fig = ps_plot_spectrum(condition_stats, conditions_to_compare, freq, ...
    freq_range, spindle_band, artifact_band, cluster_results, ...
    cluster_cfg, subjects_used, channels_to_plot_resolved, pub, SHOW_SHADED_ERROR);

%% 6. Descriptive statistics for significant clusters
ps_print_cluster_descriptives(cluster_results, condition_stats, spectra_data, ...
    freq, freq_range, cluster_cfg.cluster_alpha);

%% 7. Save figures, data, and statistics report
ps_save_results(fig, OUTPUT_DIR, condition_stats, spectra_data, ...
    conditions_to_compare, channels_computed, channels_to_plot_resolved, ...
    participants, subjects_used, session, freq, freq_range, ...
    spindle_band, artifact_band, sleep_stages_filter, pub, ...
    lme_results, cluster_results, ELECTRODE_HANDLING, cluster_cfg);

fprintf('=== Power Spectrum Analysis Complete ===\n');

end
