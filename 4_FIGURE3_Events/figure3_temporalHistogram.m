function figure3_temporalHistogram()
%% FIGURE 3: Temporal Distribution of Spindles
% Shows histogram of spindle onset distribution around trial/condition onset
% Demonstrates temporal dynamics of spindle occurrence per condition

clear; clc;

% Configuration
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
roi_electrodes = 'all';

% Spindle filtering criteria
freq_range = [12, 16];
dur_range = [0.5, 3.0];
amp_range = [15, 100];

% Histogram parameters
window_before = 0.5;     % seconds before trial onset (stored as positive)
window_after = 2.0;      % seconds after trial onset
bin_width = 0.5;         % seconds

% Analysis options
use_zscore_for_stats = false;   % Z-score normalize data for LME statistics
zscore_method = 'all';          % 'off' = baseline z-score using OFF-condition mean/SD only
                                % 'all' = z-score using mean/SD across ALL conditions
stats_alpha = 0.05;            % Statistical significance threshold

% Plotting options (plots are ALWAYS created for both z-scored and non-z-scored)
show_sig_across_conditions = false;   % Show significance bars between conditions at same bin
show_sig_within_conditions = false;   % Show significance bars for pre-vs-post within conditions

% Publication settings
pub = struct();
pub.fig_width_cm = 21;   % Wider to accommodate 3 subplots
pub.fig_height_cm = 7;
pub.font_name = 'Arial';
pub.font_size_axis = 8;
pub.font_size_label = 9;
pub.font_size_title = 10;
pub.line_width = 2;

% Colors
colors = struct();
colors.x1HZ = [0.0 0.2 0.6];   % Blue
colors.x5HZ = [1.0 0.55 0.0];   % Orange
colors.OFF = [0.6 0.6 0.6];    % Gray

fprintf('=== FIGURE 3: Temporal Histogram ===\n');

%% Load Data
fprintf('\nLoading data...\n');
loaded = load(DATA_FILE, 'all_spindles', 'trial_level_table', 'all_sleep_stages');
spindles = loaded.all_spindles;
trials = loaded.trial_level_table;
all_sleep_stages = loaded.all_sleep_stages;
fprintf('Loaded %d spindles, %d trials, and %d sleep stage epochs\n', ...
    height(spindles), height(trials), height(all_sleep_stages));

%% Add Sleep Stage Information to Trials
fprintf('Matching trials to sleep stages...\n');
fprintf('Sleep stage table columns: %s\n', strjoin(all_sleep_stages.Properties.VariableNames, ', '));

% Identify the correct column name for sleep stage
stage_col = 'Stage';
if ismember('SleepStage', all_sleep_stages.Properties.VariableNames)
    stage_col = 'SleepStage';
end

trials.SleepStage = cell(height(trials), 1);

% Get unique subjects to process
unique_subjects = unique(trials.Subject);

for subj_idx = 1:length(unique_subjects)
    subject = unique_subjects{subj_idx};

    % Get sleep stages for this subject
    subj_stages = all_sleep_stages(strcmp(all_sleep_stages.Subject, subject), :);

    if isempty(subj_stages)
        warning('No sleep stages found for subject %s', subject);
        continue;
    end

    % Convert datetime Timestamp to seconds relative to first timestamp
    % This matches the convention used in addPreciseContextToEvents
    stage_times_sec = seconds(subj_stages.Timestamp - subj_stages.Timestamp(1));

    % Get trials for this subject
    subj_trial_idx = strcmp(trials.Subject, subject);
    subj_trials = trials(subj_trial_idx, :);

    % For each trial, find the sleep stage
    for t_idx = 1:height(subj_trials)
        trial_start = subj_trials.StartTime(t_idx);
        trial_end = subj_trials.EndTime(t_idx);
        trial_midpoint = (trial_start + trial_end) / 2;

        % Find the last sleep stage epoch that started before or at the trial midpoint
        % This follows the same logic as addPreciseContextToEvents
        stage_idx = find(stage_times_sec <= trial_midpoint, 1, 'last');

        if ~isempty(stage_idx)
            trials.SleepStage{find(subj_trial_idx, 1, 'first') + t_idx - 1} = subj_stages.(stage_col){stage_idx};
        else
            % Trial occurs before first sleep stage epoch (shouldn't happen normally)
            trials.SleepStage{find(subj_trial_idx, 1, 'first') + t_idx - 1} = 'Unknown';
        end
    end
end

% Report sleep stage distribution
stage_counts = groupsummary(trials, 'SleepStage');
fprintf('Trial sleep stage distribution:\n');
for i = 1:height(stage_counts)
    fprintf('  %s: %d trials (%.1f%%)\n', ...
        stage_counts.SleepStage{i}, stage_counts.GroupCount(i), ...
        100 * stage_counts.GroupCount(i) / height(trials));
end

% Filter trials to only include specified sleep stages
trials_before = height(trials);
trials = trials(ismember(trials.SleepStage, sleep_stages), :);
fprintf('Filtered trials: %d -> %d (kept only %s trials)\n', ...
    trials_before, height(trials), strjoin(sleep_stages, ', '));

%% Export Comprehensive Trial-Level Table for GLMM/LME
fprintf('\n=== Creating Comprehensive Trial-Level Table ===\n');

% Create histogram bins early (needed for trial-level table)
temp_bin_edges = -window_before:bin_width:window_after;
temp_bin_centers = temp_bin_edges(1:end-1) + bin_width/2;
temp_n_bins = length(temp_bin_centers);

fprintf('Creating detailed trial-level table with %d time bins...\n', temp_n_bins);

% Pre-process spindles for this export
spindles_export = spindles;
primary_channels_export = cellfun(@(x) extract_primary_channel(x), ...
    spindles_export.Channel, 'UniformOutput', false);
spindles_export.PrimaryChannel = primary_channels_export;

% Apply sleep stage filter
spindles_export = spindles_export(ismember(spindles_export.SleepStage, sleep_stages), :);

% Apply quality filters to exported spindles
fprintf('Applying quality filters to export spindles...\n');
fprintf('  Frequency range: [%.1f, %.1f] Hz\n', freq_range(1), freq_range(2));
fprintf('  Duration range: [%.1f, %.1f] s\n', dur_range(1), dur_range(2));
fprintf('  Amplitude range: [%.1f, %.1f]\n', amp_range(1), amp_range(2));

spindles_before_quality = height(spindles_export);
spindles_export = spindles_export(spindles_export.Frequency >= freq_range(1) & ...
                   spindles_export.Frequency <= freq_range(2), :);
spindles_export = spindles_export(spindles_export.Duration >= dur_range(1) & ...
                   spindles_export.Duration <= dur_range(2), :);
spindles_export = spindles_export(spindles_export.Amplitude >= amp_range(1) & ...
                   spindles_export.Amplitude <= amp_range(2), :);

fprintf('  Spindles after quality filters: %d (removed %d)\n', ...
    height(spindles_export), spindles_before_quality - height(spindles_export));

% Get all unique subjects
all_subjects = unique(trials.Subject);

% Collect all unique electrodes across all subjects
all_electrodes_set = {};
for s_idx = 1:length(all_subjects)
    subj = all_subjects{s_idx};
    subj_spindles = spindles_export(strcmp(spindles_export.Subject, subj), :);
    if ~isempty(subj_spindles)
        all_electrodes_set = [all_electrodes_set; unique(subj_spindles.PrimaryChannel)];
    end
end
all_electrodes_set = unique(all_electrodes_set);

% Filter electrodes if ROI specified
if strcmp(roi_electrodes, 'all')
    electrodes_to_include = all_electrodes_set;
else
    if ~iscell(roi_electrodes)
        roi_electrodes_cell = {roi_electrodes};
    else
        roi_electrodes_cell = roi_electrodes;
    end
    electrodes_to_include = roi_electrodes_cell;
end

fprintf('Including %d electrodes in the comprehensive table\n', length(electrodes_to_include));

% Pre-calculate total number of rows for pre-allocation
n_subjects = length(all_subjects);
total_trials = height(trials);
n_electrodes = length(electrodes_to_include);
n_rows_total = total_trials * n_electrodes * temp_n_bins;

% Pre-allocate comprehensive data array
comprehensive_data = cell(n_rows_total, 8);
row_idx = 0;

% Build the comprehensive table
for s_idx = 1:n_subjects
    subject = all_subjects{s_idx};

    % Get subject trials (already filtered by sleep stage and condition above)
    subj_trials = trials(strcmp(trials.Subject, subject), :);
    subj_trials = subj_trials(ismember(subj_trials.Condition, conditions), :);

    subj_spindles = spindles_export(strcmp(spindles_export.Subject, subject), :);

    fprintf('Processing %s: %d trials (conditions: %s)...\n', ...
        subject, height(subj_trials), strjoin(conditions, ', '));

    for t_idx = 1:height(subj_trials)
        trial_row = subj_trials(t_idx, :);
        trial_id = t_idx;  % Trial number within subject
        trial_onset = trial_row.StartTime;
        trial_condition = trial_row.Condition;

        % Define time window for this trial
        trial_window_start = trial_onset - window_before;
        trial_window_end = trial_onset + window_after;

        % For each electrode
        for e_idx = 1:length(electrodes_to_include)
            electrode = electrodes_to_include{e_idx};

            % Get spindles for this electrode in this trial's time window
            trial_elec_spindles = subj_spindles(...
                strcmp(subj_spindles.PrimaryChannel, electrode) & ...
                subj_spindles.Start >= trial_window_start & ...
                subj_spindles.Start < trial_window_end, :);

            % Convert spindle times to trial-relative times
            if ~isempty(trial_elec_spindles)
                spindle_times_relative = trial_elec_spindles.Start - trial_onset;
            else
                spindle_times_relative = [];
            end

            % For each time bin
            for b_idx = 1:temp_n_bins
                bin_start = temp_bin_edges(b_idx);
                bin_end = temp_bin_edges(b_idx + 1);
                bin_center = temp_bin_centers(b_idx);

                % Check if any spindle occurred in this bin
                spindles_in_bin = (spindle_times_relative >= bin_start) & ...
                                  (spindle_times_relative < bin_end);
                has_spindle = any(spindles_in_bin);

                % Convert boolean to binary (1 or 0)
                spindle_binary = double(has_spindle);

                % Store row using indexing (MUCH faster than concatenation)
                row_idx = row_idx + 1;
                comprehensive_data(row_idx, :) = {subject, char(trial_condition), b_idx, ...
                    bin_center, b_idx, trial_id, electrode, spindle_binary};
            end
        end
    end
end

% Trim any unused pre-allocated rows (if any)
comprehensive_data = comprehensive_data(1:row_idx, :);

% Convert to table
comprehensive_tbl = cell2table(comprehensive_data, ...
    'VariableNames', {'Subject', 'Condition', 'BinIdx', 'BinCenter', ...
                      'TimeBin', 'Trial', 'Electrode', 'Spindle'});

fprintf('\nComprehensive table created: %d rows\n', height(comprehensive_tbl));
fprintf('  Unique subjects: %d\n', length(unique(comprehensive_tbl.Subject)));
fprintf('  Unique conditions: %d\n', length(unique(comprehensive_tbl.Condition)));
fprintf('  Unique electrodes: %d\n', length(unique(comprehensive_tbl.Electrode)));
fprintf('  Unique trials per subject: ~%d\n', round(height(comprehensive_tbl) / (temp_n_bins * length(electrodes_to_include) * length(all_subjects))));
fprintf('  Time bins: %d\n', temp_n_bins);
fprintf('  Total spindle events: %d (%.2f%% of observations)\n', ...
    sum(comprehensive_tbl.Spindle), 100 * sum(comprehensive_tbl.Spindle) / height(comprehensive_tbl));
fprintf('  Filters applied to BOTH trials and spindles:\n');
fprintf('    - Sleep stage: %s\n', strjoin(sleep_stages, ', '));
fprintf('    - Conditions: %s\n', strjoin(conditions, ', '));
fprintf('  Additional spindle quality filters:\n');
fprintf('    - Frequency: [%.1f, %.1f] Hz\n', freq_range(1), freq_range(2));
fprintf('    - Duration: [%.1f, %.1f] s\n', dur_range(1), dur_range(2));
fprintf('    - Amplitude: [%.1f, %.1f]\n', amp_range(1), amp_range(2));

% Filter Spindles
fprintf('\nFiltering spindles...\n');

% Extract primary channels
primary_channels = cellfun(@(x) extract_primary_channel(x), ...
    spindles.Channel, 'UniformOutput', false);
spindles.PrimaryChannel = primary_channels;

% Apply quality filters (but don't filter by time window yet - we'll do that per trial)
spindles = spindles(ismember(spindles.SleepStage, sleep_stages), :);

% Apply ROI electrode filter only if specific electrodes are requested
if ~strcmp(roi_electrodes, 'all')
    spindles = spindles(ismember(spindles.PrimaryChannel, roi_electrodes), :);
end

spindles = spindles(spindles.Frequency >= freq_range(1) & ...
                   spindles.Frequency <= freq_range(2), :);
spindles = spindles(spindles.Duration >= dur_range(1) & ...
                   spindles.Duration <= dur_range(2), :);
spindles = spindles(spindles.Amplitude >= amp_range(1) & ...
                   spindles.Amplitude <= amp_range(2), :);

fprintf('Quality-filtered spindles: %d\n', height(spindles));

% Create Histogram Bins (centered at zero for trial onset)
bin_edges = -window_before:bin_width:window_after;
bin_centers = bin_edges(1:end-1) + bin_width/2;
n_bins = length(bin_centers);

fprintf('\nBin edges: %d bins from %.2f to %.2f s\n', n_bins, bin_edges(1), bin_edges(end));

% Get unique subjects
subjects = unique(trials.Subject);
n_subj = length(subjects);
n_cond = length(conditions);

% Build electrode-level data table for LME
fprintf('\nBuilding electrode-level data table...\n');

% Pre-allocate electrode_data (rough upper bound: all electrodes * conditions * bins * subjects)
max_electrodes = 30;  % Conservative estimate
n_rows_elec = n_subj * n_cond * max_electrodes * n_bins;
electrode_data = cell(n_rows_elec, 6);
elec_row_idx = 0;

for s = 1:n_subj
    subject = subjects{s};
    subj_spindles = spindles(strcmp(spindles.Subject, subject), :);
    subj_trials = trials(strcmp(trials.Subject, subject), :);

    % Get electrodes for this subject
    if strcmp(roi_electrodes, 'all')
        unique_electrodes = unique(subj_spindles.PrimaryChannel);
    else
        unique_electrodes = roi_electrodes;
        if ~iscell(unique_electrodes), unique_electrodes = {unique_electrodes}; end
    end

    for c = 1:n_cond
        condition = conditions{c};
        cond_trials = subj_trials(strcmp(subj_trials.Condition, condition), :);
        if isempty(cond_trials), continue; end

        for e = 1:length(unique_electrodes)
            electrode = unique_electrodes{e};

            % Collect spindle times across all trials for this electrode
            % Use vectorized approach to avoid repeated concatenation
            n_trials_elec = height(cond_trials);
            all_spindle_times = [];

            % Pre-filter electrode spindles once
            elec_mask = strcmp(subj_spindles.PrimaryChannel, electrode);
            elec_spindles_all = subj_spindles(elec_mask, :);

            % Collect spindles from all trials at once
            if ~isempty(elec_spindles_all)
                % Use cell array to collect, then concatenate once (faster)
                relative_times_cell = cell(n_trials_elec, 1);
                for t = 1:n_trials_elec
                    trial_onset = cond_trials.StartTime(t);
                    window_start = trial_onset - window_before;
                    window_end = trial_onset + window_after;

                    % Find spindles in this trial window
                    trial_mask = elec_spindles_all.Start >= window_start & ...
                                 elec_spindles_all.Start < window_end;

                    if any(trial_mask)
                        relative_times_cell{t} = elec_spindles_all.Start(trial_mask) - trial_onset;
                    end
                end
                % Concatenate all at once
                all_spindle_times = vertcat(relative_times_cell{:});
            end

            % Compute rate per bin for this subject-electrode-condition
            rate = compute_bin_rate(all_spindle_times, bin_edges, n_trials_elec);

            % Store one row per bin using indexing (MUCH faster)
            for b = 1:n_bins
                elec_row_idx = elec_row_idx + 1;
                electrode_data(elec_row_idx, :) = {subject, electrode, condition, b, bin_centers(b), rate(b)};
            end
        end
    end
    fprintf('  %s: %d electrodes processed\n', subject, length(unique_electrodes));
end

% Trim unused pre-allocated rows
electrode_data = electrode_data(1:elec_row_idx, :);

% Convert to table
electrode_tbl = cell2table(electrode_data, ...
    'VariableNames', {'Subject', 'Electrode', 'Condition', 'BinIdx', 'BinCenter', 'SpindleProb'});
electrode_tbl.Subject = categorical(electrode_tbl.Subject);
electrode_tbl.Electrode = categorical(electrode_tbl.Electrode);
electrode_tbl.Condition = categorical(electrode_tbl.Condition);
electrode_tbl.TimeBin = categorical(electrode_tbl.BinIdx);
electrode_tbl.SubjElec = categorical(strcat(string(electrode_tbl.Subject), ':', string(electrode_tbl.Electrode)));

fprintf('Electrode-level table: %d rows\n', height(electrode_tbl));

% Compute subject-level means for plotting (aggregate across electrodes)
subject_probs = nan(n_subj, n_bins, n_cond);
for s = 1:n_subj
    for c = 1:n_cond
        for b = 1:n_bins
            mask = electrode_tbl.Subject == subjects{s} & ...
                   electrode_tbl.Condition == conditions{c} & ...
                   electrode_tbl.BinIdx == b;
            subject_probs(s, b, c) = mean(electrode_tbl.SpindleProb(mask), 'omitnan');
        end
    end
end
fprintf('Computed subject-level means for plotting\n');

% ALWAYS compute both raw and z-scored versions for plotting
fprintf('\nComputing z-score normalization per participant (method: %s)...\n', zscore_method);

subject_probs_z = nan(size(subject_probs));

if strcmp(zscore_method, 'off')
    % OFF-condition baseline: mean/SD from OFF bins only
    fprintf('Using OFF condition bins as normalization reference\n');
    off_idx = find(strcmp(conditions, 'OFF'));
    if isempty(off_idx)
        error('OFF condition not found in conditions list. Required for zscore_method=''off''.');
    end

    for s = 1:n_subj
        off_vals = subject_probs(s, :, off_idx);
        if sum(~isnan(off_vals(:))) >= 2
            m = mean(off_vals(:), 'omitnan');
            sd = std(off_vals(:), 'omitnan');
            if sd > 0
                for c = 1:n_cond
                    subject_probs_z(s, :, c) = (subject_probs(s, :, c) - m) / sd;
                end
            else
                subject_probs_z(s, :, :) = 0;
            end
        end
    end

elseif strcmp(zscore_method, 'all')
    % All-condition: mean/SD from ALL bins across ALL conditions
    fprintf('Using ALL conditions/bins as normalization reference\n');

    for s = 1:n_subj
        all_vals = subject_probs(s, :, :);
        if sum(~isnan(all_vals(:))) >= 2
            m = mean(all_vals(:), 'omitnan');
            sd = std(all_vals(:), 'omitnan');
            if sd > 0
                for c = 1:n_cond
                    subject_probs_z(s, :, c) = (subject_probs(s, :, c) - m) / sd;
                end
            else
                subject_probs_z(s, :, :) = 0;
            end
        end
    end

else
    error('Unknown zscore_method ''%s''. Use ''off'' or ''all''.', zscore_method);
end

% Average across subjects for plotting - compute for BOTH raw and z-scored
% Raw (non-z-scored) averages
mean_probs_raw = squeeze(mean(subject_probs, 1, 'omitnan'));
sem_probs_raw = squeeze(std(subject_probs, 0, 1, 'omitnan') ./ sqrt(sum(~isnan(subject_probs), 1)));

% Z-scored averages
mean_probs_z = squeeze(mean(subject_probs_z, 1, 'omitnan'));
sem_probs_z = squeeze(std(subject_probs_z, 0, 1, 'omitnan') ./ sqrt(sum(~isnan(subject_probs_z), 1)));

% Prepare ROI string for figure titles
if strcmp(roi_electrodes, 'all')
    roi_str = 'all';
else
    if iscell(roi_electrodes)
        roi_str = strjoin(roi_electrodes, ', ');
    else
        roi_str = roi_electrodes;
    end
end

%% Descriptive Statistics: Spindle Probability per Condition x TimeBin
fprintf('\n========================================\n');
fprintf('DESCRIPTIVE STATISTICS: Spindle Probability\n');
fprintf('========================================\n');
fprintf('N = %d subjects, %d conditions, %d time bins\n', n_subj, n_cond, n_bins);
fprintf('Values: spindle rate (events/trial), subject-level (electrode-averaged)\n\n');

% Per-condition x time bin descriptive table (raw)
fprintf('--- Raw Spindle Probability per Condition x TimeBin ---\n');
fprintf('%-10s', 'Bin (s)');
for c = 1:n_cond
    fprintf('  %18s', sprintf('%s M(SD)', conditions{c}));
end
fprintf('\n');
fprintf('%s\n', repmat('-', 1, 10 + n_cond * 20));
for b = 1:n_bins
    fprintf('%-10.2f', bin_centers(b));
    for c = 1:n_cond
        vals = subject_probs(:, b, c);
        vals = vals(~isnan(vals));
        fprintf('  %8.4f (%6.4f)', mean(vals), std(vals));
    end
    fprintf('\n');
end

% Per-condition marginal descriptives (collapsed across bins)
fprintf('\n--- Marginal Descriptives per Condition (collapsed across bins) ---\n');
fprintf('%-10s  %10s  %10s  %10s  %10s  %10s  %10s\n', ...
    'Condition', 'Mean', 'SD', 'SEM', 'Median', 'Min', 'Max');
fprintf('%s\n', repmat('-', 1, 75));
for c = 1:n_cond
    subj_marginal = squeeze(mean(subject_probs(:, :, c), 2, 'omitnan'));
    vals = subj_marginal(~isnan(subj_marginal));
    fprintf('%-10s  %10.4f  %10.4f  %10.4f  %10.4f  %10.4f  %10.4f\n', ...
        conditions{c}, mean(vals), std(vals), std(vals)/sqrt(length(vals)), ...
        median(vals), min(vals), max(vals));
end

% Per-time-bin marginal descriptives (collapsed across conditions)
fprintf('\n--- Marginal Descriptives per TimeBin (collapsed across conditions) ---\n');
fprintf('%-10s  %10s  %10s  %10s\n', 'Bin (s)', 'Mean', 'SD', 'SEM');
fprintf('%s\n', repmat('-', 1, 45));
for b = 1:n_bins
    vals_all = squeeze(mean(subject_probs(:, b, :), 3, 'omitnan'));
    vals_all = vals_all(~isnan(vals_all));
    fprintf('%-10.2f  %10.4f  %10.4f  %10.4f\n', ...
        bin_centers(b), mean(vals_all), std(vals_all), std(vals_all)/sqrt(length(vals_all)));
end

% Full descriptive table (for text export): Condition x TimeBin with N, Mean, SD, SEM
fprintf('\n--- Full Descriptive Table (subject-level) ---\n');
fprintf('%-10s  %-10s  %5s  %10s  %10s  %10s\n', ...
    'Condition', 'Bin (s)', 'N', 'Mean', 'SD', 'SEM');
fprintf('%s\n', repmat('-', 1, 60));
for c = 1:n_cond
    for b = 1:n_bins
        vals = subject_probs(:, b, c);
        vals = vals(~isnan(vals));
        fprintf('%-10s  %-10.2f  %5d  %10.4f  %10.4f  %10.4f\n', ...
            conditions{c}, bin_centers(b), length(vals), mean(vals), std(vals), ...
            std(vals)/sqrt(length(vals)));
    end
end

% Statistical Testing - Linear Mixed Effects Models
fprintf('\n=== LME Statistical Analysis ===\n');

% Prepare LME table - conditionally z-score based on parameter
lme_tbl = electrode_tbl;

if use_zscore_for_stats
    fprintf('Using z-scored data for statistics (method: %s)...\n', zscore_method);
    if ~ismember(zscore_method, {'off', 'all'})
        error('Unknown zscore_method ''%s''. Use ''off'' or ''all''.', zscore_method);
    end
    lme_tbl.SpindleProb = nan(height(lme_tbl), 1);

    for s = 1:n_subj
        subj_mask = lme_tbl.Subject == subjects{s};

        if strcmp(zscore_method, 'off')
            % OFF-condition baseline: mean/SD from OFF condition only
            ref_mask = subj_mask & strcmp(lme_tbl.Condition, 'OFF');
            ref_vals = electrode_tbl.SpindleProb(ref_mask);
        else
            % All-condition: mean/SD from all conditions
            ref_vals = electrode_tbl.SpindleProb(subj_mask);
        end

        if sum(~isnan(ref_vals)) >= 2
            m = mean(ref_vals, 'omitnan');
            sd = std(ref_vals, 'omitnan');

            if sd > 0
                all_vals = electrode_tbl.SpindleProb(subj_mask);
                lme_tbl.SpindleProb(subj_mask) = (all_vals - m) / sd;
            else
                lme_tbl.SpindleProb(subj_mask) = 0;
            end
        end
    end
else
    fprintf('Using raw (non-z-scored) data for statistics...\n');
    % Keep original SpindleProb values
end

% Remove NaN rows
lme_tbl = lme_tbl(~isnan(lme_tbl.SpindleProb), :);
fprintf('LME table: %d valid rows\n', height(lme_tbl));

% Initialize text output
stats_txt = {};
stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = 'LME Statistical Analysis Results';
stats_txt{end+1} = 'Figure 3: Temporal Histogram of Spindle Probability';
stats_txt{end+1} = sprintf('Date: %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
stats_txt{end+1} = sprintf('Z-scored for stats: %s (method: %s)', string(use_zscore_for_stats), zscore_method);
stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = '';
stats_txt{end+1} = sprintf('N subjects: %d', n_subj);
stats_txt{end+1} = sprintf('N electrodes: %d unique', length(unique(lme_tbl.Electrode)));
stats_txt{end+1} = sprintf('N observations: %d', height(lme_tbl));
stats_txt{end+1} = sprintf('Time bins: %d (%.2f to %.2f s)', n_bins, bin_centers(1), bin_centers(end));
stats_txt{end+1} = '';

%% MODEL 1: Main effects only
fprintf('\n--- Model 1: Main Effects ---\n');
formula1 = 'SpindleProb ~ Condition + TimeBin + Electrode + (1|Subject)';
fprintf('Formula: %s\n', formula1);

stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = 'MODEL 1: Main Effects';
stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = sprintf('Formula: %s', formula1);
stats_txt{end+1} = '';

lme1 = fitlme(lme_tbl, formula1);
anova1 = anova(lme1);

stats_txt{end+1} = 'ANOVA:';
stats_txt{end+1} = sprintf('%-20s %5s %8s %10s %12s', 'Term', 'DF1', 'DF2', 'F', 'p');
stats_txt{end+1} = repmat('-', 1, 60);

for r = 1:height(anova1)
    term = anova1.Term{r};
    sig = get_sig_str(anova1.pValue(r));
    stats_txt{end+1} = sprintf('%-20s %5d %8.1f %10.3f %12.6f %s', ...
        term, anova1.DF1(r), anova1.DF2(r), anova1.FStat(r), anova1.pValue(r), sig);
    fprintf('  %-20s F(%d,%.1f)=%.3f, p=%.6f %s\n', ...
        term, anova1.DF1(r), anova1.DF2(r), anova1.FStat(r), anova1.pValue(r), sig);
end
stats_txt{end+1} = '';

%% MODEL 2: Interaction model with contrasts
fprintf('\n--- Model 2: Interaction + Contrasts ---\n');
formula2 = 'SpindleProb ~ Condition * TimeBin + (1|Subject) ';
fprintf('Formula: %s\n', formula2);

stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = 'MODEL 2: Interaction + Contrasts';
stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = sprintf('Formula: %s', formula2);
stats_txt{end+1} = '';

lme2 = fitlme(lme_tbl, formula2);
anova2 = anova(lme2);

stats_txt{end+1} = 'ANOVA:';
stats_txt{end+1} = sprintf('%-25s %5s %8s %10s %12s', 'Term', 'DF1', 'DF2', 'F', 'p');
stats_txt{end+1} = repmat('-', 1, 65);

for r = 1:height(anova2)
    term = anova2.Term{r};
    sig = get_sig_str(anova2.pValue(r));
    stats_txt{end+1} = sprintf('%-25s %5d %8.1f %10.3f %12.6f %s', ...
        term, anova2.DF1(r), anova2.DF2(r), anova2.FStat(r), anova2.pValue(r), sig);
    fprintf('  %-25s F(%d,%.1f)=%.3f, p=%.6f %s\n', ...
        term, anova2.DF1(r), anova2.DF2(r), anova2.FStat(r), anova2.pValue(r), sig);
end
stats_txt{end+1} = '';

% Contrasts: condition differences at each time bin
fprintf('\nContrasts by time bin:\n');
[beta, bn] = fixedEffects(lme2);
coefNames = bn.Name;
covB = lme2.CoefficientCovariance;
bins_cat = categories(lme_tbl.TimeBin);

contrast_pairs = {{'x5HZ', 'OFF'}, {'x1HZ', 'OFF'}, {'x5HZ', 'x1HZ'}};
n_pairs = numel(contrast_pairs);

% Storage for all contrasts
contrast_results = struct();
for pr = 1:n_pairs
    cond1 = contrast_pairs{pr}{1};
    cond2 = contrast_pairs{pr}{2};
    pair_name = sprintf('%s_vs_%s', cond1, cond2);

    est_vec = nan(n_bins, 1);
    se_vec = nan(n_bins, 1);
    t_vec = nan(n_bins, 1);
    df_vec = nan(n_bins, 1);
    p_vec = nan(n_bins, 1);

    for b = 1:n_bins
        bin = bins_cat{b};
        H = zeros(1, numel(beta));

        % Main effects
        idx1 = strcmp(coefNames, sprintf('Condition_%s', cond1));
        idx2 = strcmp(coefNames, sprintf('Condition_%s', cond2));
        if any(idx1), H(idx1) = 1; end
        if any(idx2), H(idx2) = -1; end

        % Interaction terms (non-reference bins)
        if ~strcmp(bin, bins_cat{1})
            idx1_int = strcmp(coefNames, sprintf('Condition_%s:TimeBin_%s', cond1, bin));
            idx2_int = strcmp(coefNames, sprintf('Condition_%s:TimeBin_%s', cond2, bin));
            if any(idx1_int), H(idx1_int) = 1; end
            if any(idx2_int), H(idx2_int) = -1; end
        end

        [p, ~, ~, df2] = coefTest(lme2, H);
        est = H * beta;
        se_val = sqrt(H * covB * H');

        est_vec(b) = est;
        se_vec(b) = se_val;
        t_vec(b) = est / se_val;
        df_vec(b) = df2;
        p_vec(b) = p;
    end

    % FDR correction within this contrast family (5 bins)
    [~, ~, ~, p_fdr] = fdr_bh(p_vec', stats_alpha, 'pdep');
    p_fdr = p_fdr(:);

    contrast_results.(pair_name).est = est_vec;
    contrast_results.(pair_name).se = se_vec;
    contrast_results.(pair_name).t = t_vec;
    contrast_results.(pair_name).df = df_vec;
    contrast_results.(pair_name).p = p_vec;
    contrast_results.(pair_name).p_fdr = p_fdr;

    % Output
    pair_label = sprintf('%s vs %s', cond1, cond2);
    fprintf('\n  %s:\n', pair_label);
    stats_txt{end+1} = sprintf('--- %s ---', pair_label);
    stats_txt{end+1} = sprintf('%-10s %10s %10s %10s %8s %12s %12s %6s', ...
        'Bin(s)', 'Est', 'SE', 't', 'df', 'p', 'p_FDR', 'Sig');
    stats_txt{end+1} = repmat('-', 1, 85);

    for b = 1:n_bins
        sig = get_sig_str(p_fdr(b));
        stats_txt{end+1} = sprintf('%-10.2f %10.4f %10.4f %10.3f %8.1f %12.6f %12.6f %6s', ...
            bin_centers(b), est_vec(b), se_vec(b), t_vec(b), df_vec(b), p_vec(b), p_fdr(b), sig);
        fprintf('    %.2fs: Est=%.4f, SE=%.4f, t(%.1f)=%.3f, p=%.4f, p_FDR=%.4f %s\n', ...
            bin_centers(b), est_vec(b), se_vec(b), df_vec(b), t_vec(b), p_vec(b), p_fdr(b), sig);
    end
    stats_txt{end+1} = '';
end

%% Within-Condition Pre vs Post Contrasts
fprintf('\n=== Within-Condition Pre vs Post Contrasts ===\n');
stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = 'WITHIN-CONDITION CONTRASTS: Pre (Bin 1) vs Post (Bins 2-5)';
stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = 'Tests whether spindle rate changes from pre-onset to each post-onset bin';
stats_txt{end+1} = 'within each stimulation condition.';
stats_txt{end+1} = '';

% Storage for within-condition contrasts
within_cond_results = struct();

% Post bins to compare against pre-onset bin (bin 1)
post_bins = bins_cat(2:end);  % Bins 2-5

for c = 1:n_cond
    condition = conditions{c};

    est_vec = nan(length(post_bins), 1);
    se_vec = nan(length(post_bins), 1);
    t_vec = nan(length(post_bins), 1);
    df_vec = nan(length(post_bins), 1);
    p_vec = nan(length(post_bins), 1);

    for pb = 1:length(post_bins)
        post_bin = post_bins{pb};
        H = zeros(1, numel(beta));

        % The effect of going from bin 1 to bin pb+1 within this condition:
        % For reference condition (first alphabetically): just TimeBin_X
        % For other conditions: TimeBin_X + Condition_C:TimeBin_X

        % Find the TimeBin main effect
        idx_timebin = strcmp(coefNames, sprintf('TimeBin_%s', post_bin));
        if any(idx_timebin)
            H(idx_timebin) = 1;
        end

        % If not the reference condition, also add the interaction term
        % Check if this condition has an interaction (i.e., is not reference)
        idx_interaction = strcmp(coefNames, sprintf('Condition_%s:TimeBin_%s', condition, post_bin));
        if any(idx_interaction)
            H(idx_interaction) = 1;
        end

        % Compute contrast
        [p, ~, ~, df2] = coefTest(lme2, H);
        est = H * beta;
        se_val = sqrt(H * covB * H');

        est_vec(pb) = est;
        se_vec(pb) = se_val;
        t_vec(pb) = est / se_val;
        df_vec(pb) = df2;
        p_vec(pb) = p;
    end

    % FDR correction within this condition (4 post-bins)
    [~, ~, ~, p_fdr] = fdr_bh(p_vec', stats_alpha, 'pdep');
    p_fdr = p_fdr(:);

    % Store results
    within_cond_results.(condition).est = est_vec;
    within_cond_results.(condition).se = se_vec;
    within_cond_results.(condition).t = t_vec;
    within_cond_results.(condition).df = df_vec;
    within_cond_results.(condition).p = p_vec;
    within_cond_results.(condition).p_fdr = p_fdr;
    within_cond_results.(condition).post_bin_centers = bin_centers(2:end);

    % Output
    cond_label = strrep(strrep(condition, 'x', ''), 'HZ', ' Hz');
    fprintf('\n  %s (Pre vs Post):\n', cond_label);
    stats_txt{end+1} = sprintf('--- %s: Pre (%.2fs) vs Post ---', cond_label, bin_centers(1));
    stats_txt{end+1} = sprintf('%-12s %10s %10s %10s %8s %12s %12s %6s', ...
        'Post Bin(s)', 'Est', 'SE', 't', 'df', 'p', 'p_FDR', 'Sig');
    stats_txt{end+1} = repmat('-', 1, 85);

    for pb = 1:length(post_bins)
        sig = get_sig_str(p_fdr(pb));
        post_bin_center = bin_centers(pb + 1);  % +1 because post_bins starts at bin 2
        stats_txt{end+1} = sprintf('%-12.2f %10.4f %10.4f %10.3f %8.1f %12.6f %12.6f %6s', ...
            post_bin_center, est_vec(pb), se_vec(pb), t_vec(pb), df_vec(pb), p_vec(pb), p_fdr(pb), sig);
        fprintf('    Pre vs %.2fs: Est=%.4f, SE=%.4f, t(%.1f)=%.3f, p=%.4f, p_FDR=%.4f %s\n', ...
            post_bin_center, est_vec(pb), se_vec(pb), df_vec(pb), t_vec(pb), p_vec(pb), p_fdr(pb), sig);
    end
    stats_txt{end+1} = '';
end

%% Effect Sizes (Cohen's d for key contrasts)
filename_base = 'figure3_temporalHistogram';

% Extract variance components for effect size calculation.
% With (1|Subject): covparam{1} is a scalar (Subject intercept variance).
% Total variance = sigma2_Subject + sigma2_resid (same for all pairs).
[covparam, mse] = covarianceParameters(lme2);
sigma2_subj  = covparam{1}(1,1);    % Subject random intercept variance
sigma2_resid = mse;                  % residual variance
sigma_pooled = sqrt(sigma2_subj + sigma2_resid);

fprintf('\n--- Effect Sizes (Cohen''s d) ---\n');
stats_txt{end+1} = '--- Effect Sizes (Cohen''s d) ---';
stats_txt{end+1} = 'Note: d = Estimate / sqrt(sigma2_Subject + sigma2_resid)';
stats_txt{end+1} = sprintf('Variance components: sigma2_Subject = %.6f, sigma2_resid = %.6f', ...
    sigma2_subj, sigma2_resid);
stats_txt{end+1} = 'Interpretation: |d| < 0.2 = negligible, 0.2-0.5 = small, 0.5-0.8 = medium, > 0.8 = large';
stats_txt{end+1} = '';

for pr = 1:n_pairs
    cond1 = contrast_pairs{pr}{1};
    cond2 = contrast_pairs{pr}{2};
    pair_name = sprintf('%s_vs_%s', cond1, cond2);
    pair_label = sprintf('%s vs %s', cond1, cond2);

    est_vec = contrast_results.(pair_name).est;
    d_vec = est_vec / sigma_pooled;
    contrast_results.(pair_name).cohens_d = d_vec;

    stats_txt{end+1} = sprintf('--- %s ---', pair_label);
    stats_txt{end+1} = sprintf('%-10s %10s %10s %15s', 'Bin(s)', 'Estimate', 'Cohen''s d', 'Interpretation');
    stats_txt{end+1} = repmat('-', 1, 50);

    fprintf('  %s:\n', pair_label);
    for b = 1:n_bins
        d_interp = interpret_cohens_d(d_vec(b));
        stats_txt{end+1} = sprintf('%-10.2f %10.4f %10.4f %15s', ...
            bin_centers(b), est_vec(b), d_vec(b), d_interp);
        fprintf('    %.2fs: d=%.4f (%s)\n', bin_centers(b), d_vec(b), d_interp);
    end
    stats_txt{end+1} = '';
end

%% Subject-Level Robustness Check
% Collapses all electrodes to one mean per Subject x Condition x TimeBin.
% Every subject contributes exactly one observation per cell regardless of
% how many spindles or electrodes it produced.  No z-scoring needed --
% equal weighting is structural.
fprintf('\n=== Subject-Level Robustness Check ===\n');

% subject_probs is already computed: n_subj x n_bins x n_cond (raw rates)
% Pre-allocate subj_data (exact size known)
n_rows_subj = n_subj * n_cond * n_bins;
subj_data = cell(n_rows_subj, 5);
subj_row_idx = 0;

for s = 1:n_subj
    for c = 1:n_cond
        for b = 1:n_bins
            subj_row_idx = subj_row_idx + 1;
            subj_data(subj_row_idx, :) = {subjects{s}, conditions{c}, b, bin_centers(b), subject_probs(s, b, c)};
        end
    end
end

subj_tbl = cell2table(subj_data, ...
    'VariableNames', {'Subject', 'Condition', 'BinIdx', 'BinCenter', 'SpindleProb'});
subj_tbl.Subject   = categorical(subj_tbl.Subject);
subj_tbl.Condition = categorical(subj_tbl.Condition);
subj_tbl.TimeBin   = categorical(subj_tbl.BinIdx);
subj_tbl = subj_tbl(~isnan(subj_tbl.SpindleProb), :);   % drop any missing cells

fprintf('Subject-level table: %d rows (%d subjects x %d conditions x %d bins)\n', ...
    height(subj_tbl), n_subj, n_cond, n_bins);

% Fit interaction model -- only Subject as grouping factor
formula_subj = 'SpindleProb ~ Condition * TimeBin + (1|Subject)';
fprintf('Formula: %s\n', formula_subj);
lme_subj   = fitlme(subj_tbl, formula_subj);
anova_subj = anova(lme_subj);

% --- Output: header + ANOVA ---
stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = 'ROBUSTNESS CHECK: Subject-Level Analysis';
stats_txt{end+1} = '=========================================================';
stats_txt{end+1} = 'Electrodes collapsed to per-subject means. Each subject';
stats_txt{end+1} = 'contributes one obs per Condition x TimeBin (equal weighting).';
stats_txt{end+1} = sprintf('Formula: %s', formula_subj);
stats_txt{end+1} = sprintf('N subjects: %d, N observations: %d', n_subj, height(subj_tbl));
stats_txt{end+1} = '';
stats_txt{end+1} = 'ANOVA:';
stats_txt{end+1} = sprintf('%-25s %5s %8s %10s %12s', 'Term', 'DF1', 'DF2', 'F', 'p');
stats_txt{end+1} = repmat('-', 1, 65);

for r = 1:height(anova_subj)
    term = anova_subj.Term{r};
    sig  = get_sig_str(anova_subj.pValue(r));
    stats_txt{end+1} = sprintf('%-25s %5d %8.1f %10.3f %12.6f %s', ...
        term, anova_subj.DF1(r), anova_subj.DF2(r), anova_subj.FStat(r), anova_subj.pValue(r), sig);
    fprintf('  %-25s F(%d,%.1f)=%.3f, p=%.6f %s\n', ...
        term, anova_subj.DF1(r), anova_subj.DF2(r), anova_subj.FStat(r), anova_subj.pValue(r), sig);
end
stats_txt{end+1} = '';

% --- Between-condition contrasts at each time bin (same H-vector logic) ---
fprintf('\nSubject-level contrasts:\n');
[beta_subj, bn_subj] = fixedEffects(lme_subj);
coefNames_subj = bn_subj.Name;
covB_subj      = lme_subj.CoefficientCovariance;
bins_cat_subj  = categories(subj_tbl.TimeBin);

for pr = 1:n_pairs
    cond1 = contrast_pairs{pr}{1};
    cond2 = contrast_pairs{pr}{2};
    pair_label = sprintf('%s vs %s', cond1, cond2);

    est_vec = nan(n_bins, 1);
    se_vec  = nan(n_bins, 1);
    t_vec   = nan(n_bins, 1);
    df_vec  = nan(n_bins, 1);
    p_vec   = nan(n_bins, 1);

    for b = 1:n_bins
        bin = bins_cat_subj{b};
        H = zeros(1, numel(beta_subj));

        idx1 = strcmp(coefNames_subj, sprintf('Condition_%s', cond1));
        idx2 = strcmp(coefNames_subj, sprintf('Condition_%s', cond2));
        if any(idx1), H(idx1) =  1; end
        if any(idx2), H(idx2) = -1; end

        if ~strcmp(bin, bins_cat_subj{1})
            idx1_int = strcmp(coefNames_subj, sprintf('Condition_%s:TimeBin_%s', cond1, bin));
            idx2_int = strcmp(coefNames_subj, sprintf('Condition_%s:TimeBin_%s', cond2, bin));
            if any(idx1_int), H(idx1_int) =  1; end
            if any(idx2_int), H(idx2_int) = -1; end
        end

        [p, ~, ~, df2] = coefTest(lme_subj, H);
        est    = H * beta_subj;
        se_val = sqrt(H * covB_subj * H');

        est_vec(b) = est;
        se_vec(b)  = se_val;
        t_vec(b)   = est / se_val;
        df_vec(b)  = df2;
        p_vec(b)   = p;
    end

    [~, ~, ~, p_fdr] = fdr_bh(p_vec', stats_alpha, 'pdep');
    p_fdr = p_fdr(:);

    fprintf('\n  %s:\n', pair_label);
    stats_txt{end+1} = sprintf('--- %s ---', pair_label);
    stats_txt{end+1} = sprintf('%-10s %10s %10s %10s %8s %12s %12s %6s', ...
        'Bin(s)', 'Est', 'SE', 't', 'df', 'p', 'p_FDR', 'Sig');
    stats_txt{end+1} = repmat('-', 1, 85);

    for b = 1:n_bins
        sig = get_sig_str(p_fdr(b));
        stats_txt{end+1} = sprintf('%-10.2f %10.4f %10.4f %10.3f %8.1f %12.6f %12.6f %6s', ...
            bin_centers(b), est_vec(b), se_vec(b), t_vec(b), df_vec(b), p_vec(b), p_fdr(b), sig);
        fprintf('    %.2fs: Est=%.4f, SE=%.4f, t(%.1f)=%.3f, p=%.4f, p_FDR=%.4f %s\n', ...
            bin_centers(b), est_vec(b), se_vec(b), df_vec(b), t_vec(b), p_vec(b), p_fdr(b), sig);
    end
    stats_txt{end+1} = '';
end
stats_txt{end+1} = '';

%% Create Figures
fprintf('\n=== Creating Figures ===\n');

if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

% Create BOTH z-scored and non-z-scored figures
plot_configs = struct();
plot_configs(1).mean_probs = mean_probs_raw;
plot_configs(1).sem_probs = sem_probs_raw;
plot_configs(1).is_zscore = false;
plot_configs(1).suffix = '';
plot_configs(1).ylabel_str = 'Spindle Rate (events/trial)';

plot_configs(2).mean_probs = mean_probs_z;
plot_configs(2).sem_probs = sem_probs_z;
plot_configs(2).is_zscore = true;
plot_configs(2).suffix = '_zscore';
plot_configs(2).ylabel_str = 'Spindle Rate (z-scored)';

for cfg_idx = 1:2
    cfg = plot_configs(cfg_idx);
    fprintf('\nCreating %s figure...\n', ternary(cfg.is_zscore, 'z-scored', 'raw'));

    % Determine global y-limit across all conditions
    if cfg.is_zscore
        % For normalized data, use symmetrical limits around zero
        max_abs_y = max(abs(cfg.mean_probs(:)) + abs(cfg.sem_probs(:)), [], 'omitnan');
        if isnan(max_abs_y) || max_abs_y <= 0
            max_abs_y = 0.5;
        else
            max_abs_y = max_abs_y * 1.5;  % Extra margin for significance bars
        end
        min_y = -max_abs_y;
        max_y = max_abs_y;
    else
        % For non-normalized data, use standard limits from zero
        max_y = max(cfg.mean_probs(:) + cfg.sem_probs(:), [], 'omitnan');
        if isnan(max_y) || max_y <= 0
            max_y = 0.5;
        else
            max_y = max_y * 1.5;  % Extra margin for significance bars
        end
        min_y = 0;
    end

    % ---------------------------------------------------------------
    % 1.  Pre-collect & sort significance comparisons BEFORE layout,
    %     so we know how much vertical space to reserve.
    % ---------------------------------------------------------------
    all_comps = struct('bin', {}, 'cond1_idx', {}, 'cond2_idx', {}, ...
                       'sig_str', {}, 'p_fdr', {}, 'span', {}, ...
                       'cond1', {}, 'cond2', {});

    if show_sig_across_conditions
        for pr = 1:n_pairs
            cond1     = contrast_pairs{pr}{1};
            cond2     = contrast_pairs{pr}{2};
            pair_name = sprintf('%s_vs_%s', cond1, cond2);
            cr        = contrast_results.(pair_name);

            idx1 = find(strcmp(conditions, cond1));
            idx2 = find(strcmp(conditions, cond2));
            if idx1 > idx2, [idx1, idx2] = deal(idx2, idx1); end

            for b = 1:n_bins
                if cr.p_fdr(b) < stats_alpha
                    n = length(all_comps);
                    all_comps(n+1).bin        = b;
                    all_comps(n+1).cond1_idx  = idx1;
                    all_comps(n+1).cond2_idx  = idx2;
                    all_comps(n+1).sig_str    = get_sig_str(cr.p_fdr(b));
                    all_comps(n+1).p_fdr      = cr.p_fdr(b);
                    all_comps(n+1).span       = idx2 - idx1;
                    all_comps(n+1).cond1      = cond1;
                    all_comps(n+1).cond2      = cond2;
                end
            end
        end

        % Sort: adjacent subplot pairs first (shorter lines, lower),
        % then wider pairs; within same span sort by bin left-to-right.
        if ~isempty(all_comps)
            [~, order] = sortrows([[all_comps.bin]', [all_comps.span]']);
            all_comps  = all_comps(order);
        end
    end
    n_sig_levels = length(all_comps);

    % ---------------------------------------------------------------
    % 2.  Layout  --  five non-overlapping vertical bands in [0, 1]:
    %       [0.00 -- bottom_margin]        x-labels
    %       [bottom_margin -- plot_top]    plot axes
    %       [plot_top -- cond_lbl_top]     condition labels
    %       [cond_lbl_top -- sig_top]      significance brackets
    %       [sig_top -- 1.00]              figure title
    % ---------------------------------------------------------------
    left_margin   = 0.08;
    right_margin  = 0.02;
    gap           = 0.04;
    bottom_margin = 0.15;

    % Fixed bands for title and condition labels
    fig_title_bot = 0.93;               % title text sits above this
    cond_lbl_h    = 0.04;               % height of condition-label band
    sig_pad       = 0.01;               % gap between cond labels and first bracket

    % Sig-bracket band is between cond_lbl_top and fig_title_bot
    cond_lbl_bot  = fig_title_bot - cond_lbl_h ...
                    - n_sig_levels * 0.025 - sig_pad;
    cond_lbl_top  = cond_lbl_bot + cond_lbl_h;

    % Plot area sits below the condition labels
    plot_top      = cond_lbl_bot - 0.005;
    plot_height   = plot_top - bottom_margin;
    plot_width    = (1 - left_margin - right_margin - (n_cond-1)*gap) / n_cond;

    % Dynamic sig-bar step that fills the available band exactly
    sig_bot       = cond_lbl_top + sig_pad;
    sig_top       = fig_title_bot - 0.022;  % leave room for label text above topmost bracket
    if n_sig_levels > 1
        sig_bar_step = (sig_top - sig_bot) / (n_sig_levels - 1);
    else
        sig_bar_step = 0.025;           % irrelevant when 0 or 1 bars
    end
    sig_bar_tick  = 0.006;

    % ---------------------------------------------------------------
    % 3.  Create figure  (height scales with number of sig levels)
    % ---------------------------------------------------------------
    fig_width_cm  = 18;
    fig_height_cm = max(7, 5.5 + n_sig_levels * 0.3);

    fig = figure('Units', 'centimeters', ...
                 'Position', [2, 2, fig_width_cm, fig_height_cm], ...
                 'Color', 'white', ...
                 'PaperUnits', 'centimeters', ...
                 'PaperSize', [fig_width_cm, fig_height_cm], ...
                 'PaperPosition', [0, 0, fig_width_cm, fig_height_cm]);

    cond_display = {'5 Hz', '1 Hz', 'OFF'};

    % ---------------------------------------------------------------
    % 4.  Draw subplot axes
    % ---------------------------------------------------------------
    ax_handles = gobjects(1, n_cond);
    for c = 1:n_cond
        condition = conditions{c};
        left_pos  = left_margin + (c-1) * (plot_width + gap);
        ax_handles(c) = axes('Position', [left_pos, bottom_margin, plot_width, plot_height]);
        hold on;

        bar(bin_centers, cfg.mean_probs(:, c), ...
            'FaceColor', colors.(condition), ...
            'EdgeColor', 'none', ...
            'FaceAlpha', 0.8, ...
            'BarWidth', 0.85);

        errorbar(bin_centers, cfg.mean_probs(:, c), cfg.sem_probs(:, c), ...
            'LineStyle', 'none', ...
            'Color', [0.2, 0.2, 0.2], ...
            'LineWidth', 1.2, ...
            'CapSize', 4);

        xline(0, '--', 'Color', [0.4, 0.4, 0.4], 'LineWidth', 1.2);
        hold off;

        set(gca, 'FontName', pub.font_name, ...
                 'FontSize', pub.font_size_axis, ...
                 'Box', 'off', ...
                 'TickDir', 'out', ...
                 'TickLength', [0.02, 0.02], ...
                 'LineWidth', 0.8, ...
                 'XColor', [0, 0, 0], ...
                 'YColor', [0, 0, 0]);

        xlabel('Time from trial onset (s)', 'FontName', pub.font_name, ...
            'FontSize', pub.font_size_label);
        xlim([-window_before - 0.1, window_after + 0.1]);

        if c == 1
            ylabel(cfg.ylabel_str, 'FontName', pub.font_name, ...
                'FontSize', pub.font_size_label);
        else
            set(gca, 'YTickLabel', []);
        end
        ylim([min_y, max_y]);
    end

    % ---------------------------------------------------------------
    % 5.  Condition labels  (manual annotations -- avoids title() fighting
    %     the axes layout engine)
    % ---------------------------------------------------------------
    for c = 1:n_cond
        pos      = get(ax_handles(c), 'Position');
        x_center = pos(1) + pos(3) / 2;
        annotation(fig, 'textbox', ...
            [x_center - 0.06, cond_lbl_bot, 0.12, cond_lbl_h], ...
            'String', cond_display{c}, ...
            'FontSize', pub.font_size_title, ...
            'FontName', pub.font_name, ...
            'FontWeight', 'bold', ...
            'EdgeColor', 'none', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'Margin', 0);
    end

    % ---------------------------------------------------------------
    % 6.  Significance brackets
    % ---------------------------------------------------------------
    if n_sig_levels > 0
        xl_range = (window_after + 0.1) - (-window_before - 0.1);

        for k = 1:n_sig_levels
            comp  = all_comps(k);
            y_bar = sig_bot + (k - 1) * sig_bar_step;

            x_norm = (bin_centers(comp.bin) - (-window_before - 0.1)) / xl_range;
            pos1   = get(ax_handles(comp.cond1_idx), 'Position');
            pos2   = get(ax_handles(comp.cond2_idx), 'Position');
            x1     = pos1(1) + x_norm * pos1(3);
            x2     = pos2(1) + x_norm * pos2(3);

            % Horizontal line
            annotation(fig, 'line', [x1, x2], [y_bar, y_bar], ...
                'Color', 'k', 'LineWidth', 0.8);
            % End-ticks
            annotation(fig, 'line', [x1, x1], [y_bar - sig_bar_tick, y_bar], ...
                'Color', 'k', 'LineWidth', 0.8);
            annotation(fig, 'line', [x2, x2], [y_bar - sig_bar_tick, y_bar], ...
                'Color', 'k', 'LineWidth', 0.8);

            % Label above the bracket
            x_mid = (x1 + x2) / 2;
            annotation(fig, 'textbox', ...
                [x_mid - 0.018, y_bar + 0.002, 0.036, 0.018], ...
                'String', comp.sig_str, ...
                'FontSize', 7, ...
                'FontName', pub.font_name, ...
                'EdgeColor', 'none', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', ...
                'Margin', 0);

            cond1_label = strrep(strrep(comp.cond1, 'x', ''), 'HZ', ' Hz');
            cond2_label = strrep(strrep(comp.cond2, 'x', ''), 'HZ', ' Hz');
            fprintf('  Sig: %s vs %s at %.2fs (%s, p=%.4f)\n', ...
                cond1_label, cond2_label, bin_centers(comp.bin), comp.sig_str, comp.p_fdr);
        end
    end

    % ---------------------------------------------------------------
    % 7.  Figure title
    % ---------------------------------------------------------------
    title_str = sprintf('Temporal Distribution of Spindles (ROI: %s)', roi_str);
    if cfg.is_zscore
        if strcmp(zscore_method, 'off')
            title_str = [title_str ' [Z-scored, OFF baseline]'];
        else
            title_str = [title_str ' [Z-scored, all conditions]'];
        end
    end
    annotation(fig, 'textbox', [0.0, fig_title_bot, 1.0, 1.0 - fig_title_bot], ...
        'String', title_str, ...
        'FontSize', pub.font_size_title + 1, ...
        'FontName', pub.font_name, ...
        'FontWeight', 'bold', ...
        'EdgeColor', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'Margin', 0);

    % Store figure handle
    if cfg.is_zscore
        fig_zscore = fig;
    else
        fig_raw = fig;
    end
end

%% Save Data
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'subject_probs', 'subject_probs_z', 'mean_probs_raw', 'sem_probs_raw', ...
     'mean_probs_z', 'sem_probs_z', 'electrode_tbl', ...
     'bin_centers', 'bin_edges', 'subjects', 'conditions', 'roi_electrodes', ...
     'lme1', 'lme2', 'anova1', 'anova2', 'contrast_results', 'within_cond_results', ...
     'contrast_pairs', 'stats_alpha', 'use_zscore_for_stats', 'zscore_method', ...
     'show_sig_across_conditions', 'show_sig_within_conditions', ...
     'pub', '-v7.3');

% Save LME statistics to text file
stats_txt_file = fullfile(OUTPUT_DIR, [filename_base '_LME_stats.txt']);
fid = fopen(stats_txt_file, 'w');
for i = 1:length(stats_txt)
    fprintf(fid, '%s\n', stats_txt{i});
end
fclose(fid);

% Save figures
fprintf('\nSaving figures...\n');
% Raw figure
print(fig_raw, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig_raw, 'Renderer', 'painters');  % Ensure vector output
print(fig_raw, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig_raw, fullfile(OUTPUT_DIR, [filename_base '.fig']));
fprintf('  Saved: %s.png/.svg/.fig\n', filename_base);

% Z-scored figure
print(fig_zscore, fullfile(OUTPUT_DIR, [filename_base '_zscore.png']), '-dpng', '-r300');
set(fig_zscore, 'Renderer', 'painters');  % Ensure vector output
print(fig_zscore, fullfile(OUTPUT_DIR, [filename_base '_zscore.svg']), '-dsvg', '-painters');
savefig(fig_zscore, fullfile(OUTPUT_DIR, [filename_base '_zscore.fig']));
fprintf('  Saved: %s_zscore.png/.svg/.fig\n', filename_base);

fprintf('\nOutputs saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png/.svg/.fig (raw data)\n', filename_base);
fprintf('  - %s_zscore.png/.svg/.fig (z-scored data)\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('  - %s_LME_stats.txt (statistics)\n', filename_base);
fprintf('=== Done ===\n');

end

%% Ternary operator helper
function result = ternary(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end

%% Helper Functions

function rate = compute_bin_rate(spindle_times, bin_edges, n_total_obs)
    % Compute spindle rate per bin (spindles per observation per bin)
    % Rate = total count of spindle onsets in bin / number of observations
    %
    % INPUTS:
    %   spindle_times - vector of spindle onset times relative to trial onset
    %   bin_edges     - bin edges for histogram
    %   n_total_obs   - total number of observations (trial-electrode pairs)
    %
    % OUTPUT:
    %   rate          - vector of spindle rates per bin (spindles/observation/bin)

    n_bins = numel(bin_edges) - 1;
    rate = zeros(1, n_bins);

    if isempty(spindle_times) || n_total_obs == 0
        return;
    end

    % For each bin, count all spindle onsets (not just unique observations)
    for i = 1:n_bins
        bin_start = bin_edges(i);
        bin_end   = bin_edges(i+1);

        % Find spindles falling within this bin
        in_bin = (spindle_times >= bin_start) & (spindle_times < bin_end);

        % Count all spindles in this bin and divide by total observations
        rate(i) = sum(in_bin) / n_total_obs;
    end
end

function primary = extract_primary_channel(ch)
    if iscell(ch), ch = ch{1}; end
    ch = strtok(ch, '+');
    ch = regexprep(ch, 'A[12]', '');
    ch = regexprep(ch, '[^A-Za-z0-9]', '');
    primary = upper(ch);
end

function sig = get_sig_str(p)
    if p < 0.001,     sig = '***';
    elseif p < 0.01,  sig = '**';
    elseif p < 0.05,  sig = '*';
    else,             sig = 'n.s.';
    end
end

function [h, crit_p, adj_ci_cvrg, adj_p] = fdr_bh(pvals, q, method, report)
    % FDR_BH - Executes the Benjamini & Hochberg (1995) and Benjamini & Yekutieli (2001)
    % procedure for controlling the false discovery rate (FDR) of a family of
    % hypothesis tests.
    %
    % Usage: [h, crit_p, adj_ci_cvrg, adj_p] = fdr_bh(pvals, q, method, report)
    %
    % Arguments:
    % pvals   - A vector or matrix (2D or 3D) of p-values (NaN entries are excluded)
    % q       - The desired false discovery rate (default: 0.05)
    % method  - 'pdep' (default) for positive dependence or 'dep' for any dependence
    % report  - If 'yes', display results; otherwise, suppress output (default: 'no')

    if nargin < 1
        error('You need to provide a vector or matrix of p-values.');
    end
    if isempty(pvals)
        error('pvals is empty');
    end
    if nargin < 2, q = 0.05; end
    if nargin < 3, method = 'pdep'; end
    if nargin < 4, report = 'no'; end

    s = size(pvals);

    % Handle NaN: exclude from FDR, return NaN for those positions
    nan_mask = isnan(pvals(:));
    p_valid = pvals(~nan_mask);

    if isempty(p_valid)
        h = nan(s);
        crit_p = NaN;
        adj_ci_cvrg = NaN;
        adj_p = nan(s);
        return;
    end

    [p_sorted, sort_ids] = sort(p_valid(:)');  % Always row vector
    m = length(p_sorted);

    if strcmp(method, 'pdep')
        % BH procedure for independence or positive dependence
        thresh = (1:m) * q / m;
    elseif strcmp(method, 'dep')
        % BH procedure for any dependency
        denom = sum(1 ./ (1:m));
        thresh = (1:m) * q / (m * denom);
    else
        error('Argument ''method'' must be ''pdep'' or ''dep''.');
    end

    % Find largest p-value that is less than or equal to threshold
    wtd_p = m * p_sorted ./ (1:m);
    rej = p_sorted <= thresh;
    max_id = find(rej, 1, 'last');

    if isempty(max_id)
        crit_p = 0;
        h_valid = zeros(1, m);
        adj_ci_cvrg = NaN;
    else
        crit_p = p_sorted(max_id);
        h_valid = zeros(1, m);
        h_valid(sort_ids(1:max_id)) = 1;
        adj_ci_cvrg = 1 - thresh(max_id);
    end

    % Adjusted p-values
    [~, unsort_ids] = sort(sort_ids);
    adj_p_sorted = min([wtd_p; ones(1, m)], [], 1);
    % Enforce monotonicity
    for i = m-1:-1:1
        adj_p_sorted(i) = min(adj_p_sorted(i), adj_p_sorted(i+1));
    end
    adj_p_valid = adj_p_sorted(unsort_ids);

    % Map back to original shape, placing NaN where input was NaN
    h = nan(s);
    adj_p = nan(s);
    h(~nan_mask) = h_valid;
    adj_p(~nan_mask) = adj_p_valid;

    if strcmpi(report, 'yes')
        n_sig = sum(h_valid);
        fprintf('Total number of tests: %d (excl. NaN)\n', m);
        fprintf('FDR level: %.3f\n', q);
        fprintf('FDR procedure: %s\n', method);
        fprintf('Number of significant tests: %d\n', n_sig);
        fprintf('Critical p-value: %.6f\n', crit_p);
    end
end

function interp = interpret_cohens_d(d)
    % Interpret Cohen's d effect size
    % Based on Cohen (1988) conventions
    abs_d = abs(d);
    if abs_d < 0.2
        interp = 'negligible';
    elseif abs_d < 0.5
        interp = 'small';
    elseif abs_d < 0.8
        interp = 'medium';
    else
        interp = 'large';
    end
end
