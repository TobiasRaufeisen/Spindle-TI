function figure2_topography()
%% FIGURE 2: Spindle-Band Power Topography with Cluster Statistics
% Creates topographical maps of spindle power per condition (x5HZ, x1HZ, OFF)
% and cluster-corrected difference maps with significant clusters marked.
%
% OUTPUTS:
%   condition-average topographies (parula colormap)
%   difference topographies with significant clusters marked
%   t-value topographies with significant clusters marked
%   Statistics text file, data .mat files, trial indices for downstream scripts
%
% DEPENDENCIES:
%   Shared pipeline functions in functions/:
%     spindlePilot_visual_topographyTFR_config, _load, _filter,
%     _compute_from_filtered, _stats
%   Helper functions in functions_figure2_topography/

clear; clc;

%% ========================================================================
%  PARAMETERS - all key analysis settings in one place
%  ========================================================================

% --- Paths ---
SCRIPT_FILE = matlab.desktop.editor.getActiveFilename;
SCRIPT_DIR  = fileparts(SCRIPT_FILE);

addpath(SCRIPT_DIR);
addpath(fullfile(SCRIPT_DIR, 'functions'));
addpath(fullfile(SCRIPT_DIR, 'functions_figure2_topography'));
OUTPUT_DIR = fullfile(SCRIPT_DIR, 'outputs');

%% --- Participants and design ---
params.participants = {'sub5','sub6','sub7','sub8','sub9','sub10','sub11','sub12', 'sub13','sub14','sub15','sub16','sub17','sub18','sub19','sub20','sub21','sub22','sub23','sub24'};
params.session        = 'ses1';
params.conditions     = {'x5HZ', 'x1HZ', 'OFF'};
params.condition_labels = {'5 Hz', '1 Hz', 'Off'};

% --- Event type ---
params.event_type = 'spindle';  % 'spindle' or 'slowwave'

% --- Frequency and time: loading ---
params.load_freq_range = [4, 20];   % Broad range for reference-band access
params.load_time_range = [-6, 6];   % Full window for filter flexibility

% --- Time-frequency windows for analysis/plotting ---
%   Format: {freq_lo, freq_hi, time_lo, time_hi, label}
params.time_freq_windows = { ...
    12, 16, 0.5, 1.5, 'StimClean'; ...
     4,  8, 0.5, 1.5, 'Theta'};

% --- Sleep stage filter ---
params.sleep_stage_filter.enabled = true;
params.sleep_stage_filter.stages  = {'N2'};
params.sleep_stage_analysis_window = [0.25, 1.75];  % Window for stage overlap check

% --- Filter pipeline (applied in this order) ---
params.filter_order = {'sleep_stage', 'artifact', 'zscore_spindle_power', 'log_transform'};

% --- Artifact rejection ---
params.artifact.apply         = true;
params.artifact.mad_threshold = 3;
params.artifact.handling      = 'reject_trial';

% --- Log transform ---
params.log_transform = true;  % 10*log10(power) -> dB

% --- Trial summarization ---
params.summary_method        = 'trimmed_mean';
params.trimmed_mean_percent  = 0;  % 0% trimming = standard mean

% --- Z-score spindle power filter ---
params.zscore_filter.enabled      = true;
params.zscore_filter.spindle_band = [12, 16];
params.zscore_filter.time_window  = [-1, 3];
params.zscore_filter.z_threshold  = 2;
params.zscore_filter.min_channels = 1;

% --- Electrode filtering mode ---
params.electrode_filtering_mode = 'trial_level';  % 'trial_level' or 'electrode_level'

% --- Cluster-corrected permutation statistics ---
params.stats.alpha            = 0.05;
params.stats.cluster_alpha    = 0.15;
params.stats.n_permutations   = 5000;
params.stats.min_cluster_size = 2;
params.stats.run              = true;

% --- Condition comparison pairs for topography difference maps ---
params.condition_pairs = { ...
    'x5HZ', 'OFF',  'x5HZ > OFF'; ...
    'x1HZ', 'OFF',  'x1HZ > OFF'; ...
    'x5HZ', 'x1HZ', 'x5HZ > x1HZ'};

% --- Publication figure settings ---
params.pub.fig_width_cm    = 18;
params.pub.fig_height_cm   = 12;
params.pub.font_name       = 'Arial';
params.pub.font_size_axis  = 7;
params.pub.font_size_label = 8;
params.pub.font_size_title = 9;
params.pub.condition_colors = [ ...
    1.0, 0.55, 0.0;   ... % orange: 5 Hz
    0.0, 0.2,  0.6;   ... % blue:   1 Hz
    0.6, 0.6,  0.6];      % gray:   Off

fprintf('=== FIGURE 2: Power Topography ===\n');

%% ========================================================================
%  STEP 1: SETUP
%  ========================================================================
config = build_pipeline_config(params);
ft_defaults;

%% ========================================================================
%  STEP 2: LOAD DATA
%  ========================================================================
fprintf('\n--- Loading TFR data ---\n');
fprintf('Load freq range: [%.0f, %.0f] Hz | Load time range: [%.1f, %.1f] s\n', ...
    config.freq_range(1), config.freq_range(2), ...
    config.load_time_range(1), config.load_time_range(2));

[all_data, trial_indices] = spindlePilot_visual_topographyTFR_load( ...
    config.participants, config.session, config.conditions, ...
    config.load_time_range, config.freq_range, config.paths.tfr);

%% ========================================================================
%  STEP 3: FILTER DATA
%  ========================================================================
fprintf('\n--- Filtering (pipeline: %s) ---\n', strjoin(params.filter_order, ' -> '));

[all_data_filtered, trial_indices_filtered] = ...
    spindlePilot_visual_topographyTFR_filter(all_data, trial_indices, config);

%% ========================================================================
%  STEP 4: COMPUTE TOPOGRAPHY
%  ========================================================================
fprintf('\n--- Computing topography ---\n');

compute_results = spindlePilot_visual_topographyTFR_compute_from_filtered( ...
    all_data_filtered, trial_indices_filtered, config);

%% ========================================================================
%  STEP 5: CLUSTER-CORRECTED STATISTICS
%  ========================================================================
fprintf('\n--- Cluster-corrected permutation statistics ---\n');

stats_results = spindlePilot_visual_topographyTFR_stats(compute_results, config);

%% ========================================================================
%  STEP 6: DESCRIPTIVE STATISTICS
%  ========================================================================
run_descriptive_statistics(compute_results, stats_results, config);

%% ========================================================================
%  STEP 7: CREATE FIGURES
%  ========================================================================
if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end

topo_data        = compute_results.topo_data_computed;
layout           = compute_results.layout;
matched_channels = compute_results.matched_channels;
window_label     = params.time_freq_windows{1, 5};

fprintf('\n--- Creating figures ---\n');

fig1 = plot_condition_topographies(topo_data, window_label, ...
    params.conditions, matched_channels, layout, params.pub);

fig2 = plot_difference_topographies(topo_data, stats_results, ...
    window_label, params.condition_pairs, matched_channels, layout, params.pub);

fig3 = plot_tvalue_topographies(topo_data, stats_results, ...
    window_label, params.condition_pairs, matched_channels, layout, params.pub);

%% ========================================================================
%  STEP 8: EXPORT STATISTICS
%  ========================================================================
export_statistics_to_text(stats_results, matched_channels, ...
    params.conditions, config, fullfile(OUTPUT_DIR, 'figure2_statistics.txt'));

%% ========================================================================
%  STEP 9: SAVE OUTPUTS
%  ========================================================================
fprintf('\n=== SAVING RESULTS ===\n');

fn = struct( ...
    'avg',  'figure2_powerAverages', ...
    'diff', 'figure2_powerDifferences', ...
    'tval', 'figure2_tValues');

figs  = {fig1,    fig2,     fig3};
names = {fn.avg,  fn.diff,  fn.tval};
for i = 1:length(figs)
    save_figure(figs{i}, OUTPUT_DIR, names{i});
end

% Save data
pub = params.pub; %#ok<NASGU>
save(fullfile(OUTPUT_DIR, 'figure2_data.mat'), ...
    'topo_data', 'stats_results', 'compute_results', 'config', 'pub', '-v7.3');

% Save trial indices for downstream scripts
trial_indices = compute_results.trial_indices; %#ok<NASGU>
save(fullfile(OUTPUT_DIR, 'figure2_trial_indices.mat'), 'trial_indices', '-v7.3');

fprintf('\n=== COMPLETE ===\n');
fprintf('Output directory: %s\n', OUTPUT_DIR);
fprintf('Figures: %s\n', strjoin(names, ', '));
fprintf('Data:    figure2_data.mat, figure2_trial_indices.mat\n');
fprintf('Stats:   figure2_statistics.txt\n');

end

%% ========================================================================
%  LOCAL HELPERS
%  ========================================================================

function save_figure(fig, output_dir, name)
    set(fig, 'InvertHardcopy', 'off', 'Color', 'white');
    print(fig, fullfile(output_dir, [name '.png']), '-dpng', '-r300');
    print(fig, fullfile(output_dir, [name '.svg']), '-dsvg', '-vector');
    savefig(fig, fullfile(output_dir, [name '.fig']));
end
