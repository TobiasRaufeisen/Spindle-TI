function figure2_tfr_timeseries()
%% FIGURE 2: Time-Frequency Representation with ROI and Statistics
% Creates TFR plots for region of interest (ROI) electrodes per condition
% with cluster-corrected statistical difference maps showing significant clusters.
%
% Demonstrates stimulation effects on spindle power dynamics over time
% without requiring event detection (unbiased power analysis).
%
% LAYOUT: 2 rows x 3 columns
%   Row 1: TFR per condition (x5HZ, x1HZ, OFF)
%   Row 2: Difference TFRs with cluster outlines (x5HZ>OFF, x1HZ>OFF, x5HZ>x1HZ)
%
% IMPORTANT: Uses trial indices from figure2_topography.m to ensure
% consistency in which trials are included across figures.

clear; clc;

%% ========================================================================
%  PARAMETERS
%  ========================================================================

% --- Paths ---
SCRIPT_FILE = matlab.desktop.editor.getActiveFilename;
SCRIPT_DIR  = fileparts(SCRIPT_FILE);
addpath(SCRIPT_DIR);
addpath(fullfile(SCRIPT_DIR, 'functions'));
addpath(fullfile(SCRIPT_DIR, 'functions_figure2_tfr_timeseries'));
OUTPUT_DIR = fullfile(SCRIPT_DIR, 'outputs');

paths = figure2_paths_config();
paths.tfr_base    = fullfile(SCRIPT_DIR, 'TFR_1HzSmoothing');
paths.tfr_spindle = fullfile(paths.tfr_base, 'spindle_trials');

TRIAL_INDICES_FILE = fullfile(OUTPUT_DIR, 'figure2_trial_indices.mat');

% --- Participants and design ---
params.participants = {'sub5','sub6','sub7','sub8','sub9','sub10','sub11','sub12','sub13','sub14','sub15','sub16','sub17','sub18','sub19', 'sub20','sub21','sub22','sub23','sub24'};
params.session    = 'ses1';
params.conditions = {'x5HZ', 'x1HZ', 'OFF'};

% --- ROI electrodes ---
params.roi_electrodes = {'CP5'};

% --- Electrode filtering mode ---
% 'trial_level': all ROI electrodes for kept trials
% 'electrode_level': only ROI electrodes that passed per trial (NaN masking)
% 'none': kept trials, ignore electrode-specific validity
params.electrode_filtering_mode = 'none';

% --- Time-frequency ranges ---
params.time_range          = [-0.5, 2.5];   % time window to load/display
params.freq_range_plot     = [9, 18];     % frequency range for display
params.freq_range_load     = [8, 20];     % load with 1 Hz buffer beyond display
params.freq_range_analysis = [12, 16];    % frequency range for cluster statistics (spindle band)

% --- Statistics ---
params.stats_alpha          = 0.05;
params.cluster_alpha        = 0.15;
params.n_permutations       = 5000;
params.apply_db_transform   = true;   % 10*log10 before statistics and plotting
params.plot_tvalues         = true;   % true = t-value maps; false = dB differences

% --- Grand average weighting ---
% 'equal': each participant contributes equally (mean of participant means)
% 'trial_pooled': pool all trials across participants (more trials = more weight)
params.grand_avg_weighting = 'trial_pooled';

% --- Condition pairs for difference plots ---
params.condition_pairs = {
    'x5HZ', 'OFF',  'x5HZ > OFF';
    'x1HZ', 'OFF',  'x1HZ > OFF';
    'x5HZ', 'x1HZ', 'x5HZ > x1HZ'};

% --- Publication figure settings ---
pub.fig_width_cm   = 24;
pub.fig_height_cm  = 14;
pub.font_name      = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;

% --- Output filename (auto-generated from ROI) ---
roi_tag = strjoin(params.roi_electrodes, '-');
filename_base = sprintf('figure2_tfr_timeseries_%s_dB_tValues', roi_tag);

%% ========================================================================
%  SETUP
%  ========================================================================

fprintf('=== FIGURE 2: TFR Time Series ===\n');
fprintf('ROI electrodes: %s\n', strjoin(params.roi_electrodes, ', '));
fprintf('Display freq:   %.0f-%.0f Hz\n', params.freq_range_plot);
fprintf('Analysis freq:  %.0f-%.0f Hz\n', params.freq_range_analysis);

if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end

%% ========================================================================
%  LOAD TRIAL INDICES
%  ========================================================================

fprintf('\nLoading trial indices from topography analysis...\n');
if ~exist(TRIAL_INDICES_FILE, 'file')
    error('Trial indices file not found: %s\nRun figure2_topography.m first.', ...
        TRIAL_INDICES_FILE);
end
load(TRIAL_INDICES_FILE, 'trial_indices');

%% ========================================================================
%  LOAD TFR DATA FOR ROI ELECTRODES
%  ========================================================================

fprintf('\nLoading TFR data (electrode filtering: %s)...\n', params.electrode_filtering_mode);
[all_data, freq_axis, time_axis] = load_roi_tfr_data( ...
    paths.tfr_spindle, params.participants, params.session, ...
    params.conditions, params.roi_electrodes, trial_indices, ...
    params.time_range, params.freq_range_load, params.electrode_filtering_mode);

%% ========================================================================
%  COMPUTE GRAND AVERAGES
%  ========================================================================

fprintf('\nComputing grand averages (%d freq x %d time)...\n', ...
    length(freq_axis), length(time_axis));
grand_avg = compute_grand_averages(all_data, params.participants, ...
    params.conditions, freq_axis, time_axis, params.grand_avg_weighting);

%% ========================================================================
%  CLUSTER-CORRECTED STATISTICS
%  ========================================================================

fprintf('\nRunning cluster-corrected permutation statistics...\n');
stats_cfg = struct( ...
    'alpha',            params.stats_alpha, ...
    'cluster_alpha',    params.cluster_alpha, ...
    'n_permutations',   params.n_permutations, ...
    'apply_db_transform', params.apply_db_transform);

stats_results = run_tfr_cluster_statistics(all_data, params.participants, ...
    params.conditions, freq_axis, stats_cfg, params.freq_range_analysis);

%% ========================================================================
%  PREPARE PLOTTING DATA (dB transform if enabled)
%  ========================================================================

if params.apply_db_transform
    fprintf('\nApplying dB transformation for plotting...\n');
    grand_avg_plot = struct();
    for c = 1:length(params.conditions)
        grand_avg_plot.(params.conditions{c}) = 10 * log10(grand_avg.(params.conditions{c}));
    end
else
    grand_avg_plot = grand_avg;
end

%% ========================================================================
%  DESCRIPTIVE STATISTICS
%  ========================================================================

fprintf('\nComputing descriptive statistics...\n');
run_tfr_descriptive_statistics(all_data, grand_avg, stats_results, ...
    params.participants, params.conditions, params.condition_pairs, ...
    freq_axis, time_axis, params);

%% ========================================================================
%  CREATE FIGURE
%  ========================================================================

fprintf('\nCreating figure...\n');

fig = figure('Units', 'centimeters', ...
    'Position', [2, 2, pub.fig_width_cm, pub.fig_height_cm], ...
    'Color', 'white', ...
    'PaperUnits', 'centimeters', ...
    'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
    'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% -- Color limits --
% Conditions: percentile-based
all_cond_vals = [];
for c = 1:length(params.conditions)
    vals = grand_avg_plot.(params.conditions{c})(:);
    all_cond_vals = [all_cond_vals; vals]; %#ok<AGROW>
end
clim_avg = [prctile(all_cond_vals, 1), prctile(all_cond_vals, 99)];

% Differences / t-values: symmetric percentile-based
clim_diff = compute_difference_clim(grand_avg_plot, stats_results, ...
    params.condition_pairs, params.plot_tvalues);

% -- Row 1: TFR per condition --
ax_handles = gobjects(2, 3);
for c = 1:length(params.conditions)
    ax_handles(1, c) = subplot(2, 3, c);
    plot_tfr_condition(grand_avg_plot.(params.conditions{c}), freq_axis, time_axis, ...
        params.conditions{c}, pub, clim_avg, params.freq_range_analysis, ...
        params.freq_range_plot, params.apply_db_transform);
end

% -- Row 2: Difference TFRs with cluster outlines --
for p = 1:size(params.condition_pairs, 1)
    ax_handles(2, p) = subplot(2, 3, 3 + p);
    plot_tfr_difference_with_clusters(grand_avg_plot, stats_results, ...
        params.condition_pairs{p,1}, params.condition_pairs{p,2}, ...
        params.condition_pairs{p,3}, freq_axis, time_axis, ...
        params.stats_alpha, pub, clim_diff, params.plot_tvalues, ...
        params.freq_range_analysis, params.freq_range_plot, params.apply_db_transform);
end

% Tighten subplot spacing
for i = 1:numel(ax_handles)
    pos = get(ax_handles(i), 'Position');
    pos(1) = pos(1) * 0.98;
    pos(2) = pos(2) * 0.98;
    pos(3) = pos(3) * 1.04;
    pos(4) = pos(4) * 1.04;
    set(ax_handles(i), 'Position', pos);
end

%% ========================================================================
%  SAVE OUTPUTS
%  ========================================================================

fprintf('\nExporting statistics report...\n');
export_tfr_statistics_to_text(stats_results, params, params.condition_pairs, ...
    all_data, freq_axis, ...
    fullfile(OUTPUT_DIR, [filename_base '_statistics.txt']));

fprintf('\nSaving outputs...\n');

print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');

set(fig, 'Renderer', 'painters');
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');

savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
    'grand_avg', 'stats_results', 'all_data', 'freq_axis', 'time_axis', ...
    'params', 'pub', 'roi_tag', '-v7.3');

fprintf('Saved to: %s/%s.{png,svg,fig,mat,_statistics.txt}\n', OUTPUT_DIR, filename_base);
fprintf('=== Done ===\n');

end
