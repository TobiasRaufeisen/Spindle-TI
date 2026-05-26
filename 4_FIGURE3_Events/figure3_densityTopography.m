function figure3_densityTopography()
%% FIGURE 3: Spindle Density Topography with Cluster Statistics
% Creates topographical maps showing spindle density per condition (x5HZ, x1HZ, OFF)
% and cluster-corrected statistical difference maps with significant clusters marked
%
% Density is computed as spindles/min from YASA-detected events
% Uses subject-level sign-flip permutation testing with cluster correction

clear; clc;

% Configuration
ft_defaults;

% Paths
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
RESULTS_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
DATA_FILE = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');
OUTPUT_DIR = fullfile(REPO_ROOT, '4_FIGURE3_Events', 'outputs');

% Analysis parameters
conditions = {'x5HZ', 'x1HZ', 'OFF'};
sleep_stages = {'N2'};

% Spindle filtering criteria
freq_range = [12, 16];
dur_range = [0.5, 3.0];
amp_range = [15, 100];

% Statistical parameters
stats = struct();
stats.alpha = 0.05;
stats.cluster_alpha = 0.15;
stats.n_permutations = 5000;
stats.min_cluster_size = 2;
stats.rng_seed = 20260209;

% Publication settings
pub = struct();
pub.fig_width_cm = 18;
pub.fig_height_cm = 12;
pub.font_name = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;

fprintf('=== FIGURE 3: Spindle Density Topography ===\n');
fprintf('Output directory: %s\n', OUTPUT_DIR);

% Load Data
fprintf('\nLoading data...\n');
loaded = load(DATA_FILE, 'all_spindles', 'all_condition_durations');
spindles = loaded.all_spindles;
durations = loaded.all_condition_durations;
fprintf('Loaded %d spindles and %d duration entries\n', height(spindles), height(durations));

% Filter Spindles
fprintf('\nFiltering spindles...\n');

% Extract primary channels
primary_channels = cellfun(@(x) extract_primary_channel(x), ...
    spindles.Channel, 'UniformOutput', false);
spindles.PrimaryChannel = primary_channels;

% Apply filters
spindles = spindles(ismember(spindles.SleepStage, sleep_stages), :);
fprintf('After sleep stage filter: %d spindles\n', height(spindles));

spindles = spindles(ismember(spindles.Condition, conditions), :);
fprintf('After condition filter: %d spindles\n', height(spindles));

spindles = spindles(spindles.Frequency >= freq_range(1) & ...
                   spindles.Frequency <= freq_range(2), :);
fprintf('After frequency filter: %d spindles\n', height(spindles));

spindles = spindles(spindles.Duration >= dur_range(1) & ...
                   spindles.Duration <= dur_range(2), :);
fprintf('After duration filter: %d spindles\n', height(spindles));

spindles = spindles(spindles.Amplitude >= amp_range(1) & ...
                   spindles.Amplitude <= amp_range(2), :);
fprintf('Final filtered spindles: %d\n', height(spindles));

% Setup Channels and Layout
fprintf('\nSetting up channels...\n');
channels = unique(spindles.PrimaryChannel);
channels = channels(~cellfun(@isempty, channels));
fprintf('Channels: %d\n', length(channels));

ft_layout = ft_prepare_layout(struct('layout', 'easycapM1.mat'));

% Canonicalize channel labels to match layout casing (e.g., Poz -> POz)
[channels, unmatched_channels] = harmonize_channels_to_layout(channels, ft_layout);
if ~isempty(unmatched_channels)
    fprintf('WARNING: %d channels not found in layout: %s\n', ...
        numel(unmatched_channels), strjoin(unmatched_channels, ', '));
end
fprintf('Channels after layout harmonization: %d\n', length(channels));

% Use Easycap M1 layout for electrode positioning (matches recording cap)
% Only electrodes with actual data will be plotted with markers
fprintf('Using easycapM1 layout for electrode positioning\n');

% Compute Density per Subject x Channel x Condition
fprintf('\nComputing density (spindles/min)...\n');

subjects = unique(spindles.Subject);
n_subj = length(subjects);
n_chan = length(channels);
n_cond = length(conditions);

density_data = nan(n_subj, n_chan, n_cond);

for s = 1:n_subj
    subject = subjects{s};

    for c = 1:n_cond
        condition = conditions{c};

        % Get N2 duration for this subject-condition
        dur_mask = strcmp(durations.Subject, subject) & ...
                   strcmp(durations.Condition, condition) & ...
                   ismember(durations.SleepStage, sleep_stages);

        if ~any(dur_mask)
            continue;
        end

        % Total N2 duration in minutes for this subject-condition
        total_duration_min = sum(durations.Duration_min(dur_mask));

        if total_duration_min == 0
            continue;
        end

        for ch = 1:n_chan
            channel = channels{ch};

            % Count spindles
            n_spindles = sum(strcmp(spindles.Subject, subject) & ...
                           strcmp(spindles.Condition, condition) & ...
                           strcmpi(spindles.PrimaryChannel, channel));

            % Density: spindles per minute
            density_data(s, ch, c) = n_spindles / total_duration_min;
        end
    end
end

fprintf('Density computed for %d subjects\n', n_subj);

% Compute Group-Level Means
group_density = squeeze(mean(density_data, 1, 'omitnan'));  % channels x conditions

% Run Cluster-Corrected Statistics
fprintf('\nRunning cluster-corrected permutation statistics...\n');
fprintf('Using deterministic RNG seed: %d\n', stats.rng_seed);
rng(stats.rng_seed, 'twister');

% Create adjacency matrix
adjacency = create_adjacency_matrix(channels, ft_layout);

% Condition pairs (specific order: 5Hz vs Off, 1Hz vs Off, 5Hz vs 1Hz)
pair_indices = [1, 3; 2, 3; 1, 2];  % [5Hz vs Off; 1Hz vs Off; 5Hz vs 1Hz]
pair_labels = cell(size(pair_indices, 1), 1);
for p = 1:size(pair_indices, 1)
    pair_labels{p} = sprintf('%s > %s', conditions{pair_indices(p,1)}, conditions{pair_indices(p,2)});
end

% Perform cluster analysis
cluster_results = perform_cluster_analysis(density_data, channels, adjacency, ...
    pair_indices, pair_labels, stats);

% Print detailed statistics to console
fprintf('\n--- Detailed Cluster Statistics ---\n');
for p = 1:length(cluster_results)
    result = cluster_results{p};
    fprintf('\n  %s\n', pair_labels{p});
    fprintf('    Channels at threshold (p < %.3f): %d/%d\n', ...
        stats.cluster_alpha, result.n_channels_at_threshold, length(channels));

    if isempty(result.observed_clusters)
        fprintf('    No clusters formed\n');
    else
        for c = 1:length(result.observed_clusters)
            is_sig = ismember(c, result.significant_clusters);
            if is_sig
                fprintf('    Cluster %d (SIGNIFICANT): mass = %.2f, p = %.4f, %d/%d electrodes\n', ...
                    c, result.cluster_stats(c), result.cluster_p_values(c), ...
                    length(result.observed_clusters{c}), length(channels));
            else
                fprintf('    Cluster %d (n.s.): mass = %.2f, p = %.4f, %d/%d electrodes\n', ...
                    c, result.cluster_stats(c), result.cluster_p_values(c), ...
                    length(result.observed_clusters{c}), length(channels));
            end
            % List electrodes
            electrode_names = channels(result.observed_clusters{c});
            fprintf('      Electrodes: %s\n', strjoin(electrode_names, ', '));
        end
        fprintf('    Null 95th percentile: %.2f\n', result.null_95pct);
    end

    % T-statistic range
    valid_t = result.t_stats(isfinite(result.t_stats));
    if ~isempty(valid_t)
        fprintf('    T-statistic range: [%.3f, %.3f]\n', min(valid_t), max(valid_t));
    end
end
fprintf('\n');

%% Descriptive Statistics for Density Topography
fprintf('\n========================================\n');
fprintf('DESCRIPTIVE STATISTICS: Spindle Density Topography\n');
fprintf('========================================\n');
fprintf('N = %d subjects, %d channels, %d conditions\n', n_subj, n_chan, n_cond);

% Global descriptives (electrode-averaged per subject)
fprintf('\n--- Global Descriptives (electrode-averaged per subject) ---\n');
subj_avg_density = squeeze(mean(density_data, 2, 'omitnan'));  % subjects x conditions
fprintf('  %-10s  %10s  %10s  %10s  %10s  %10s  %10s\n', ...
    'Condition', 'Mean', 'SD', 'SEM', 'Median', 'Min', 'Max');
fprintf('  %s\n', repmat('-', 1, 75));
for c = 1:n_cond
    vals = subj_avg_density(:, c);
    vals = vals(~isnan(vals));
    fprintf('  %-10s  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
        conditions{c}, mean(vals), std(vals), std(vals)/sqrt(length(vals)), ...
        median(vals), min(vals), max(vals));
end

% Per-condition pairwise difference descriptives (global)
fprintf('\n--- Pairwise Differences (electrode-averaged, subject-level) ---\n');
fprintf('  %-15s  %10s  %10s  %10s  %10s\n', 'Comparison', 'Mean', 'SD', 'SEM', 'Cohen''s d');
fprintf('  %s\n', repmat('-', 1, 55));
for p = 1:size(pair_indices, 1)
    c1_idx = pair_indices(p, 1);
    c2_idx = pair_indices(p, 2);
    diff_vals = subj_avg_density(:, c1_idx) - subj_avg_density(:, c2_idx);
    diff_vals = diff_vals(~isnan(diff_vals));
    d_val = mean(diff_vals) / std(diff_vals);
    fprintf('  %-15s  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
        pair_labels{p}, mean(diff_vals), std(diff_vals), ...
        std(diff_vals)/sqrt(length(diff_vals)), d_val);
end

% Descriptives for significant cluster electrodes
fprintf('\n--- Significant Cluster Descriptives ---\n');
for p = 1:length(cluster_results)
    result = cluster_results{p};
    if isempty(result.significant_clusters), continue; end

    c1_idx = pair_indices(p, 1);
    c2_idx = pair_indices(p, 2);

    for sci = 1:length(result.significant_clusters)
        cl_idx = result.significant_clusters(sci);
        elec_idx = result.observed_clusters{cl_idx};
        elec_names = channels(elec_idx);

        fprintf('\n  %s (p = %.4f, %d electrodes)\n', ...
            pair_labels{p}, result.cluster_p_values(cl_idx), length(elec_idx));
        fprintf('  Electrodes: %s\n', strjoin(elec_names, ', '));

        % Cluster-averaged density per subject
        cl_dens_1 = mean(density_data(:, elec_idx, c1_idx), 2, 'omitnan');
        cl_dens_2 = mean(density_data(:, elec_idx, c2_idx), 2, 'omitnan');
        cl_diff = cl_dens_1 - cl_dens_2;
        valid = ~isnan(cl_diff);

        fprintf('  %-10s  %10s  %10s  %10s  %10s  %10s\n', ...
            '', 'Mean', 'SD', 'SEM', 'Min', 'Max');
        fprintf('  %s\n', repmat('-', 1, 60));
        fprintf('  %-10s  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
            conditions{c1_idx}, mean(cl_dens_1(valid)), std(cl_dens_1(valid)), ...
            std(cl_dens_1(valid))/sqrt(sum(valid)), min(cl_dens_1(valid)), max(cl_dens_1(valid)));
        fprintf('  %-10s  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
            conditions{c2_idx}, mean(cl_dens_2(valid)), std(cl_dens_2(valid)), ...
            std(cl_dens_2(valid))/sqrt(sum(valid)), min(cl_dens_2(valid)), max(cl_dens_2(valid)));
        fprintf('  %-10s  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
            'Diff', mean(cl_diff(valid)), std(cl_diff(valid)), ...
            std(cl_diff(valid))/sqrt(sum(valid)), min(cl_diff(valid)), max(cl_diff(valid)));
        fprintf('  Cohen''s d (paired): %.3f\n', mean(cl_diff(valid))/std(cl_diff(valid)));

        % Per-electrode descriptives within cluster
        fprintf('\n  Per-electrode density (group mean):\n');
        fprintf('  %-8s  %12s  %12s  %12s  %10s\n', ...
            'Elec', [conditions{c1_idx} ' (sp/min)'], [conditions{c2_idx} ' (sp/min)'], 'Diff', 't-stat');
        fprintf('  %s\n', repmat('-', 1, 55));
        for ei = 1:length(elec_idx)
            e_idx = elec_idx(ei);
            e_d1 = density_data(:, e_idx, c1_idx);
            e_d2 = density_data(:, e_idx, c2_idx);
            fprintf('  %-8s  %12.3f  %12.3f  %12.3f  %10.3f\n', ...
                elec_names{ei}, mean(e_d1, 'omitnan'), mean(e_d2, 'omitnan'), ...
                mean(e_d1, 'omitnan') - mean(e_d2, 'omitnan'), result.t_stats(e_idx));
        end
    end
end

% Export Statistics to Text File
fprintf('\nExporting statistics to text file...\n');
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end
export_statistics_to_text(cluster_results, channels, pair_labels, conditions, ...
    stats, freq_range, dur_range, amp_range, n_subj, ...
    fullfile(OUTPUT_DIR, 'figure3_statistics.txt'));

% Create Figures
fprintf('\nCreating figures...\n');

if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

% FIGURE 1: Average Spindle Density by Condition
fprintf('  Creating Figure 1: Average density by condition...\n');
fig_width_avg = pub.fig_width_cm;
fig_height_avg = pub.fig_height_cm / 2;  % Half height for single row

fig1 = figure('Units', 'centimeters', ...
              'Position', [2, 10, fig_width_avg, fig_height_avg], ...
              'Color', 'white', ...
              'PaperUnits', 'centimeters', ...
              'PaperSize', [fig_width_avg, fig_height_avg], ...
              'PaperPosition', [0, 0, fig_width_avg, fig_height_avg]);

% Calculate global color limits for conditions
global_min = min(group_density(:));
global_max = max(group_density(:));
zlim_avg = [global_min, global_max];

% Plot individual conditions (1 row x 3 columns)
cb_avg = cell(n_cond, 1);
for c = 1:n_cond
    subplot(1, 3, c);
    cb_avg{c} = plot_condition_topography(group_density(:, c), channels, ft_layout, ...
        conditions{c}, pub, zlim_avg);
end

% Synchronize colorbar sizes for averages
sync_colorbar_sizes(cb_avg);

% FIGURE 2: Difference Maps with Significant Clusters
fprintf('  Creating Figure 2: Difference maps with clusters...\n');
fig_width_diff = pub.fig_width_cm;
fig_height_diff = pub.fig_height_cm / 2;  % Half height for single row

fig2 = figure('Units', 'centimeters', ...
              'Position', [2, 2, fig_width_diff, fig_height_diff], ...
              'Color', 'white', ...
              'PaperUnits', 'centimeters', ...
              'PaperSize', [fig_width_diff, fig_height_diff], ...
              'PaperPosition', [0, 0, fig_width_diff, fig_height_diff]);

% Calculate global color limits for differences
all_diffs = [];
for p = 1:size(pair_indices, 1)
    c1_idx = pair_indices(p, 1);
    c2_idx = pair_indices(p, 2);
    diff_data = group_density(:, c1_idx) - group_density(:, c2_idx);
    all_diffs = [all_diffs; diff_data(:)];
end
max_abs_diff = max(abs(all_diffs));
zlim_diff = [-max_abs_diff, max_abs_diff];

% Plot difference maps with clusters (1 row x 3 columns)
cb_diff = cell(size(pair_indices, 1), 1);
for p = 1:size(pair_indices, 1)
    subplot(1, 3, p);
    c1_idx = pair_indices(p, 1);
    c2_idx = pair_indices(p, 2);

    diff_data = group_density(:, c1_idx) - group_density(:, c2_idx);

    cb_diff{p} = plot_difference_with_clusters(diff_data, cluster_results{p}, channels, ...
        ft_layout, pair_labels{p}, pub, zlim_diff);
end

% Synchronize colorbar sizes for differences
sync_colorbar_sizes(cb_diff);

%% Save Figures
fprintf('\nSaving figures...\n');

% Save Figure 1 (Average densities)
filename_avg = 'figure3_densityAverages';
print(fig1, fullfile(OUTPUT_DIR, [filename_avg '.png']), '-dpng', '-r300');
set(fig1, 'Renderer', 'painters');  % Ensure vector output
print(fig1, fullfile(OUTPUT_DIR, [filename_avg '.svg']), '-dsvg', '-painters');
savefig(fig1, fullfile(OUTPUT_DIR, [filename_avg '.fig']));

% Save Figure 2 (Differences with clusters)
filename_diff = 'figure3_densityDifferences';
print(fig2, fullfile(OUTPUT_DIR, [filename_diff '.png']), '-dpng', '-r300');
set(fig2, 'Renderer', 'painters');  % Ensure vector output
print(fig2, fullfile(OUTPUT_DIR, [filename_diff '.svg']), '-dsvg', '-painters');
savefig(fig2, fullfile(OUTPUT_DIR, [filename_diff '.fig']));

% Save data to MAT file
save(fullfile(OUTPUT_DIR, 'figure3_data.mat'), ...
     'density_data', 'group_density', 'cluster_results', 'channels', ...
     'conditions', 'subjects', 'stats', 'pub', '-v7.3');

fprintf('\nFigures saved to: %s\n', OUTPUT_DIR);
fprintf('  Figure 1 (Average densities):\n');
fprintf('    - %s.png (300 DPI)\n', filename_avg);
fprintf('    - %s.svg\n', filename_avg);
fprintf('    - %s.fig\n', filename_avg);
fprintf('  Figure 2 (Differences with clusters):\n');
fprintf('    - %s.png (300 DPI)\n', filename_diff);
fprintf('    - %s.svg\n', filename_diff);
fprintf('    - %s.fig\n', filename_diff);
fprintf('  Data and statistics:\n');
fprintf('    - figure3_data.mat\n');
fprintf('    - figure3_statistics.txt\n');
fprintf('=== Done ===\n');

end

%% Helper Functions

function primary = extract_primary_channel(ch)
    if iscell(ch), ch = ch{1}; end
    if isstring(ch), ch = char(ch); end
    ch = strtrim(ch);
    % Remove any linked reference notation (e.g., "C3+C4" -> "C3")
    ch = strtok(ch, '+');
    % Remove A1/A2 reference notation
    ch = regexprep(ch, 'A[12]', '');
    % Remove any non-alphanumeric characters
    ch = regexprep(ch, '[^A-Za-z0-9]', '');

    % Preserve standard EEG electrode naming to match FieldTrip layout labels
    % Standard 10-20: Fp1, Fp2, Fpz (frontopolar), Fz, Cz (midline), C3, F4 (lateral)
    if ~isempty(ch)
        % Handle frontopolar electrodes: Fp1, Fp2, Fpz (NOT FP1, FP2)
        if length(ch) >= 2 && strcmpi(ch(1:2), 'FP')
            primary = ['Fp', ch(3:end)];
        elseif endsWith(lower(ch), 'z')
            % Midline: capitalize first letter, lowercase 'z' at end
            primary = [upper(ch(1)), lower(ch(2:end))];
        else
            % Lateral: fully uppercase (e.g., C3, F4, FC1, CP2)
            primary = upper(ch);
        end
    else
        primary = '';
    end
end

function adjacency = create_adjacency_matrix(channels, ft_layout)
    n_chan = length(channels);
    adjacency = zeros(n_chan, n_chan);

    % Use FieldTrip to determine neighbors
    cfg = [];
    cfg.method = 'distance';
    cfg.neighbourdist = 0.25;
    cfg.layout = ft_layout;
    neighbors = ft_prepare_neighbours(cfg);

    % Build adjacency matrix
    for i = 1:n_chan
        ch_name = channels{i};
        idx = find(strcmpi({neighbors.label}, ch_name));
        if ~isempty(idx)
            neighb_labels = neighbors(idx).neighblabel;
            for j = 1:length(neighb_labels)
                neighb_idx = find(strcmpi(channels, neighb_labels{j}));
                if ~isempty(neighb_idx)
                    adjacency(i, neighb_idx) = 1;
                end
            end
        end
    end
end

function cluster_results = perform_cluster_analysis(data, channels, adjacency, ...
    pair_indices, pair_labels, stats)

    [n_subj, n_chan, ~] = size(data);
    n_pairs = size(pair_indices, 1);
    cluster_results = cell(n_pairs, 1);

    for p = 1:n_pairs
        c1_idx = pair_indices(p, 1);
        c2_idx = pair_indices(p, 2);

        fprintf('  %s\n', pair_labels{p});

        % Within-subject differences
        D = data(:, :, c1_idx) - data(:, :, c2_idx);

        % Paired t-test per channel
        [t_obs, p_obs] = paired_t_per_channel(D);

        % Cluster-forming threshold
        sig_mask = (p_obs < stats.cluster_alpha) & isfinite(t_obs);

        fprintf('    Cluster-forming: %d/%d channels (p < %.3f)\n', ...
            sum(sig_mask), n_chan, stats.cluster_alpha);

        % Find observed clusters
        all_clusters = find_clusters(sig_mask, adjacency);

        if isempty(all_clusters)
            fprintf('    No clusters found\n');
            cluster_results{p} = struct('significant_clusters', [], ...
                'observed_clusters', {{}}, 'cluster_p_values', [], ...
                'cluster_stats', [], ...
                'null_distribution', [], 'null_95pct', NaN, ...
                'n_channels_at_threshold', sum(sig_mask), ...
                't_stats', t_obs, 'p_values', p_obs);
            continue;
        end

        % Filter by minimum size
        observed_clusters = {};
        for i = 1:numel(all_clusters)
            if numel(all_clusters{i}) >= stats.min_cluster_size
                observed_clusters{end+1} = all_clusters{i};
            end
        end

        if isempty(observed_clusters)
            fprintf('    No clusters meeting minimum size\n');
            cluster_results{p} = struct('significant_clusters', [], ...
                'observed_clusters', {{}}, 'cluster_p_values', [], ...
                'cluster_stats', [], ...
                'null_distribution', [], 'null_95pct', NaN, ...
                'n_channels_at_threshold', sum(sig_mask), ...
                't_stats', t_obs, 'p_values', p_obs);
            continue;
        end

        % Observed cluster statistics
        cluster_stats = zeros(1, numel(observed_clusters));
        for i = 1:numel(observed_clusters)
            cluster_stats(i) = sum(abs(t_obs(observed_clusters{i})));
        end

        % Permutation testing
        fprintf('    Running %d permutations...\n', stats.n_permutations);
        max_cluster_stats = zeros(stats.n_permutations, 1);

        for perm = 1:stats.n_permutations
            subj_flips = randsample([-1, 1], n_subj, true)';
            Dp = bsxfun(@times, D, subj_flips);

            [t_perm, p_perm] = paired_t_per_channel(Dp);
            perm_sig = (p_perm < stats.cluster_alpha) & isfinite(t_perm);

            perm_clusters = find_clusters(perm_sig, adjacency);
            if ~isempty(perm_clusters)
                perm_cluster_stats = zeros(1, numel(perm_clusters));
                for i = 1:numel(perm_clusters)
                    if numel(perm_clusters{i}) >= stats.min_cluster_size
                        perm_cluster_stats(i) = sum(abs(t_perm(perm_clusters{i})));
                    end
                end
                max_cluster_stats(perm) = max(perm_cluster_stats);
            end
        end

        % Compute null distribution percentiles
        null_95pct = prctile(max_cluster_stats, 95);

        % Compute p-values
        cluster_p = zeros(1, numel(observed_clusters));
        for i = 1:numel(observed_clusters)
            cluster_p(i) = sum(max_cluster_stats >= cluster_stats(i)) / stats.n_permutations;
        end

        sig_clusters = find(cluster_p < stats.alpha);

        fprintf('    Clusters: %d observed, %d significant (p < %.3f)\n', ...
            numel(observed_clusters), numel(sig_clusters), stats.alpha);
        fprintf('    Null distribution 95th percentile: %.2f\n', null_95pct);

        cluster_results{p} = struct(...
            'significant_clusters', sig_clusters, ...
            'observed_clusters', {observed_clusters}, ...
            'cluster_p_values', cluster_p, ...
            'cluster_stats', cluster_stats, ...
            'null_distribution', max_cluster_stats, ...
            'null_95pct', null_95pct, ...
            'n_channels_at_threshold', sum(sig_mask), ...
            't_stats', t_obs, ...
            'p_values', p_obs);
    end
end

function [t_stats, p_values] = paired_t_per_channel(D)
    n_chan = size(D, 2);
    t_stats = nan(n_chan, 1);
    p_values = nan(n_chan, 1);

    for ch = 1:n_chan
        vals = D(:, ch);
        vals = vals(~isnan(vals));

        if length(vals) < 3
            continue;
        end

        [~, p, ~, stats_out] = ttest(vals);
        t_stats(ch) = stats_out.tstat;
        p_values(ch) = p;
    end
end

function clusters = find_clusters(mask, adjacency)
    clusters = {};
    visited = false(size(mask));

    for i = 1:length(mask)
        if mask(i) && ~visited(i)
            cluster = grow_cluster(i, mask, adjacency, visited);
            visited(cluster) = true;
            clusters{end+1} = cluster;
        end
    end
end

function cluster = grow_cluster(seed, mask, adjacency, visited)
    cluster = seed;
    to_check = seed;

    while ~isempty(to_check)
        current = to_check(1);
        to_check(1) = [];

        neighbors = find(adjacency(current, :));
        for n = neighbors
            if mask(n) && ~visited(n) && ~ismember(n, cluster)
                cluster(end+1) = n;
                to_check(end+1) = n;
                visited(n) = true;
            end
        end
    end
end

function cb = plot_condition_topography(data, channels, layout, condition, pub, zlim_range)
    cfg = [];
    cfg.layout = layout;
    cfg.figure = 'gca';
    cfg.marker = 'on';
    cfg.markersymbol = '.';
    cfg.markersize = 4;
    cfg.markercolor = [1 1 1];
    cfg.comment = 'no';
    cfg.colorbar = 'yes';
    cfg.colormap = parula(256);
    cfg.gridscale = 200;
    cfg.interplimits = 'head';  % Limit interpolation to head outline
    cfg.style = 'straight';     % Use straight interpolation
    cfg.shading = 'flat';       % Use flat shading for better SVG compatibility
    cfg.contournum = 0;         % Disable contours

    % Apply consistent color limits across conditions
    if nargin >= 6 && ~isempty(zlim_range)
        cfg.zlim = zlim_range;
    end

    % Create FieldTrip data structure with actual channels only
    [ft_data] = expand_to_layout_channels(data, channels, layout);

    ft_topoplotER(cfg, ft_data);

    % Make head outline thinner
    h_lines = findobj(gca, 'Type', 'line');
    set(h_lines, 'LineWidth', 0.5);

    % Force all children to clip to axes
    ax = gca;
    set(ax.Children, 'Clipping', 'on');

    title_str = strrep(condition, 'x', '');
    title_str = strrep(title_str, 'HZ', ' Hz');
    title(title_str, 'FontName', pub.font_name, 'FontSize', pub.font_size_title, ...
        'FontWeight', 'bold');

    cb = colorbar;
    ylabel(cb, 'Density (spindles/min)', 'FontName', pub.font_name, ...
        'FontSize', pub.font_size_label);
    set(cb, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis);

    % Adjust position to prevent clipping
    ax = gca;
    ax_pos = ax.Position;
    ax_pos(3) = ax_pos(3) * 0.85;  % Reduce width slightly
    ax.Position = ax_pos;

    % Make colorbar shorter (60% of original height)
    cb_pos = cb.Position;
    original_height = cb_pos(4);
    cb_pos(4) = original_height * 0.6;
    cb_pos(2) = cb_pos(2) + original_height * 0.2;  % Center vertically
    cb.Position = cb_pos;
end

function cb = plot_difference_with_clusters(data, cluster_result, channels, layout, ...
    title_str, pub, zlim_range)

    cfg = [];
    cfg.layout = layout;
    cfg.figure = 'gca';
    cfg.marker = 'on';
    cfg.markersymbol = '.';
    cfg.markersize = 4;
    cfg.markercolor = [0.5 0.5 0.5];
    cfg.comment = 'no';
    cfg.colorbar = 'yes';
    % Create red-blue diverging colormap (alternative to brewermap)
    n = 128;
    r = [(0:n-1)'/max(n-1,1); ones(n,1)];
    g = [(0:n-1)'/max(n-1,1); flipud((0:n-1)'/max(n-1,1))];
    b = [ones(n,1); flipud((0:n-1)'/max(n-1,1))];
    cfg.colormap = [r g b];
    cfg.gridscale = 200;
    cfg.interplimits = 'head';  % Limit interpolation to head outline
    cfg.style = 'straight';     % Use straight interpolation
    cfg.contournum = 0;

    % Use consistent color limits across all difference plots
    if nargin >= 7 && ~isempty(zlim_range)
        cfg.zlim = zlim_range;
    else
        max_abs = max(abs(data));
        cfg.zlim = [-max_abs, max_abs];
    end

    % Create FieldTrip data structure with actual channels only
    [ft_data] = expand_to_layout_channels(data, channels, layout);

    ft_topoplotER(cfg, ft_data);

    % Make head outline thinner
    h_lines = findobj(gca, 'Type', 'line');
    set(h_lines, 'LineWidth', 0.5);

    % Overlay significant clusters with black stars
    if ~isempty(cluster_result.significant_clusters)
        hold on;
        sig_electrode_idx = [];
        for i = 1:length(cluster_result.significant_clusters)
            cluster_idx = cluster_result.significant_clusters(i);
            sig_electrode_idx = [sig_electrode_idx; cluster_result.observed_clusters{cluster_idx}(:)];
        end
        sig_electrode_idx = unique(sig_electrode_idx);
        n_expected = numel(sig_electrode_idx);
        n_plotted = 0;
        missing_channels = {};

        for i = 1:length(cluster_result.significant_clusters)
            cluster_idx = cluster_result.significant_clusters(i);
            electrode_idx = cluster_result.observed_clusters{cluster_idx};

            for j = 1:length(electrode_idx)
                ch_name = channels{electrode_idx(j)};
                chan_idx = find(strcmpi(layout.label, ch_name), 1);
                if ~isempty(chan_idx)
                    x = layout.pos(chan_idx(1), 1);
                    y = layout.pos(chan_idx(1), 2);
                    plot(x, y, 'k*', 'MarkerSize', 4, 'LineWidth', 0.3);
                    n_plotted = n_plotted + 1;
                else
                    missing_channels{end+1} = ch_name; %#ok<AGROW>
                end
            end
        end

        fprintf('    Marker overlay (%s): plotted %d/%d significant electrodes\n', ...
            title_str, n_plotted, n_expected);
        if ~isempty(missing_channels)
            fprintf('    WARNING: Missing layout matches for channels: %s\n', ...
                strjoin(unique(missing_channels), ', '));
        end
        hold off;
    end

    title(title_str, 'FontName', pub.font_name, 'FontSize', pub.font_size_title, ...
        'FontWeight', 'bold');

    cb = colorbar;
    ylabel(cb, '\Delta Density (spindles/min)', 'FontName', pub.font_name, ...
        'FontSize', pub.font_size_label);
    set(cb, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis);

    % Adjust position to prevent clipping
    ax = gca;
    ax_pos = ax.Position;
    ax_pos(3) = ax_pos(3) * 0.85;  % Reduce width slightly
    ax.Position = ax_pos;

    % Make colorbar shorter (60% of original height)
    cb_pos = cb.Position;
    original_height = cb_pos(4);
    cb_pos(4) = original_height * 0.6;
    cb_pos(2) = cb_pos(2) + original_height * 0.2;  % Center vertically
    cb.Position = cb_pos;
end

function sync_colorbar_sizes(colorbars)
    % Synchronize colorbar sizes across multiple plots
    if isempty(colorbars)
        return;
    end

    % Get all colorbar positions
    positions = zeros(length(colorbars), 4);
    for i = 1:length(colorbars)
        if isvalid(colorbars{i})
            positions(i, :) = colorbars{i}.Position;
        end
    end

    % Find the maximum height and width
    max_height = max(positions(:, 4));
    max_width = max(positions(:, 3));

    % Apply uniform size to all colorbars
    for i = 1:length(colorbars)
        if isvalid(colorbars{i})
            pos = colorbars{i}.Position;
            pos(3) = max_width;
            pos(4) = max_height;
            colorbars{i}.Position = pos;
        end
    end
end

function ft_data = expand_to_layout_channels(data, channels, layout)
    % Create FieldTrip data structure with only the channels that exist in the data
    % This ensures markers only appear for electrodes we actually have data for

    % Create FieldTrip data structure with only actual channels
    ft_data = [];
    ft_data.label = channels;
    ft_data.avg = data;
    ft_data.time = 0;
    ft_data.dimord = 'chan_time';
end

function [channels_out, unmatched_channels] = harmonize_channels_to_layout(channels_in, layout)
    % Map channel labels to exact layout casing using case-insensitive matching.
    channels_out = cell(size(channels_in));
    unmatched_channels = {};

    for i = 1:numel(channels_in)
        ch = channels_in{i};
        idx = find(strcmpi(layout.label, ch), 1);
        if ~isempty(idx)
            channels_out{i} = layout.label{idx};
        else
            channels_out{i} = ch;
            unmatched_channels{end+1} = ch; %#ok<AGROW>
        end
    end

    % Keep stable order and avoid duplicates if multiple casings collapsed.
    channels_out = unique(channels_out, 'stable');
    unmatched_channels = unique(unmatched_channels, 'stable');
end

function [n_plotted, n_expected, missing_channels] = overlay_all_channel_markers(channels, layout, marker_size, marker_color)
    n_expected = numel(channels);
    n_plotted = 0;
    missing_channels = {};

    for i = 1:numel(channels)
        ch_name = channels{i};
        chan_idx = find(strcmpi(layout.label, ch_name), 1);
        if ~isempty(chan_idx)
            x = layout.pos(chan_idx, 1);
            y = layout.pos(chan_idx, 2);
            plot(x, y, '.', 'Color', marker_color, 'MarkerSize', marker_size);
            n_plotted = n_plotted + 1;
        else
            missing_channels{end+1} = ch_name; %#ok<AGROW>
        end
    end

    missing_channels = unique(missing_channels, 'stable');
end

function export_statistics_to_text(cluster_results, channels, pair_labels, conditions, ...
    stats, freq_range, dur_range, amp_range, n_subj, output_file)
    % Export comprehensive statistics to a text file for publication

    fid = fopen(output_file, 'w');
    if fid == -1
        error('Could not open file for writing: %s', output_file);
    end

    % Header
    fprintf(fid, '========================================\n');
    fprintf(fid, 'FIGURE 3: SPINDLE DENSITY TOPOGRAPHY\n');
    fprintf(fid, 'CLUSTER-CORRECTED PERMUTATION STATISTICS\n');
    fprintf(fid, '========================================\n\n');
    fprintf(fid, 'Generated: %s\n\n', datestr(now));

    % Analysis Parameters
    fprintf(fid, 'ANALYSIS PARAMETERS\n');
    fprintf(fid, '-------------------\n');
    fprintf(fid, 'Number of subjects: %d\n', n_subj);
    fprintf(fid, 'Conditions: %s\n', strjoin(conditions, ', '));
    fprintf(fid, 'Sleep stage: N2\n\n');

    fprintf(fid, 'Spindle filtering criteria:\n');
    fprintf(fid, '  Frequency: %.1f - %.1f Hz\n', freq_range(1), freq_range(2));
    fprintf(fid, '  Duration: %.1f - %.1f s\n', dur_range(1), dur_range(2));
    fprintf(fid, '  Amplitude: %.1f - %.1f uV\n\n', amp_range(1), amp_range(2));

    fprintf(fid, 'Statistical parameters:\n');
    fprintf(fid, '  Significance level (alpha): %.3f\n', stats.alpha);
    fprintf(fid, '  Cluster-forming threshold: %.3f\n', stats.cluster_alpha);
    fprintf(fid, '  Number of permutations: %d\n', stats.n_permutations);
    fprintf(fid, '  RNG seed: %d\n', stats.rng_seed);
    fprintf(fid, '  Minimum cluster size: %d electrodes\n\n', stats.min_cluster_size);

    % Results for each comparison
    for p = 1:length(cluster_results)
        fprintf(fid, '\n========================================\n');
        fprintf(fid, 'COMPARISON %d: %s\n', p, pair_labels{p});
        fprintf(fid, '========================================\n\n');

        result = cluster_results{p};

        % Report channels at cluster-forming threshold
        fprintf(fid, 'Channels at cluster-forming threshold (p < %.3f): %d/%d\n', ...
            stats.cluster_alpha, result.n_channels_at_threshold, length(channels));
        if ~isnan(result.null_95pct)
            fprintf(fid, 'Null distribution 95th percentile: %.2f\n', result.null_95pct);
        end
        fprintf(fid, '\n');

        if isempty(result.significant_clusters)
            fprintf(fid, 'No significant clusters found.\n\n');

            % Still report observed clusters even if not significant
            if ~isempty(result.observed_clusters)
                fprintf(fid, 'Observed clusters (not significant):\n');
                fprintf(fid, '  Total clusters: %d\n\n', length(result.observed_clusters));

                for c = 1:length(result.observed_clusters)
                    fprintf(fid, '  Cluster %d:\n', c);
                    fprintf(fid, '    Size: %d electrodes\n', length(result.observed_clusters{c}));
                    fprintf(fid, '    p-value: %.4f\n', result.cluster_p_values(c));

                    % List electrodes
                    electrode_names = channels(result.observed_clusters{c});
                    fprintf(fid, '    Electrodes: %s\n', strjoin(electrode_names, ', '));

                    % Cluster statistic
                    fprintf(fid, '    Cluster statistic (sum|t|): %.2f\n\n', result.cluster_stats(c));
                end
            end
        else
            fprintf(fid, 'SIGNIFICANT CLUSTERS: %d\n\n', length(result.significant_clusters));

            for i = 1:length(result.significant_clusters)
                cluster_idx = result.significant_clusters(i);
                electrode_idx = result.observed_clusters{cluster_idx};

                fprintf(fid, '--- Cluster %d (SIGNIFICANT) ---\n', i);
                fprintf(fid, 'Cluster size: %d electrodes\n', length(electrode_idx));
                fprintf(fid, 'Cluster p-value: %.4f (p < %.3f)\n', ...
                    result.cluster_p_values(cluster_idx), stats.alpha);
                fprintf(fid, 'Cluster statistic (sum|t|): %.2f\n', ...
                    result.cluster_stats(cluster_idx));
                fprintf(fid, 'Null distribution 95th percentile: %.2f\n\n', ...
                    result.null_95pct);

                % List electrodes with their individual statistics
                fprintf(fid, 'Electrodes in cluster:\n');
                electrode_names = channels(electrode_idx);

                for e = 1:length(electrode_idx)
                    ch_idx = electrode_idx(e);
                    fprintf(fid, '  %s: t = %.3f, p = %.4f\n', ...
                        electrode_names{e}, result.t_stats(ch_idx), result.p_values(ch_idx));
                end
                fprintf(fid, '\n');

                % Summary line for easy copy-paste
                fprintf(fid, 'Summary: %d-electrode cluster (p = %.4f) including: %s\n\n', ...
                    length(electrode_idx), result.cluster_p_values(cluster_idx), ...
                    strjoin(electrode_names, ', '));
            end

            % Also list non-significant observed clusters if any
            non_sig_clusters = setdiff(1:length(result.observed_clusters), result.significant_clusters);
            if ~isempty(non_sig_clusters)
                fprintf(fid, '\nOBSERVED CLUSTERS (not significant):\n\n');
                for i = 1:length(non_sig_clusters)
                    cluster_idx = non_sig_clusters(i);
                    electrode_idx = result.observed_clusters{cluster_idx};

                    fprintf(fid, '--- Cluster %d (not significant) ---\n', cluster_idx);
                    fprintf(fid, 'Cluster size: %d electrodes\n', length(electrode_idx));
                    fprintf(fid, 'Cluster p-value: %.4f (p >= %.3f)\n', ...
                        result.cluster_p_values(cluster_idx), stats.alpha);
                    fprintf(fid, 'Cluster statistic: %.2f\n', result.cluster_stats(cluster_idx));

                    electrode_names = channels(electrode_idx);
                    fprintf(fid, 'Electrodes: %s\n\n', strjoin(electrode_names, ', '));
                end
            end
        end

        % Additional statistics summary
        fprintf(fid, 'CHANNEL-LEVEL STATISTICS SUMMARY:\n');
        fprintf(fid, '  Channels with p < %.3f: %d/%d\n', ...
            stats.cluster_alpha, sum(result.p_values < stats.cluster_alpha), length(channels));
        fprintf(fid, '  Channels with p < %.3f: %d/%d\n', ...
            stats.alpha, sum(result.p_values < stats.alpha), length(channels));

        % Report range of t-statistics
        valid_t = result.t_stats(isfinite(result.t_stats));
        if ~isempty(valid_t)
            fprintf(fid, '  T-statistic range: [%.3f, %.3f]\n', min(valid_t), max(valid_t));
        end
        fprintf(fid, '\n');
    end

    % Footer
    fprintf(fid, '\n========================================\n');
    fprintf(fid, 'END OF STATISTICS REPORT\n');
    fprintf(fid, '========================================\n');

    fclose(fid);
    fprintf('Statistics exported to: %s\n', output_file);
end
