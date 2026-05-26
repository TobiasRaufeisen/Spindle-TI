function figure3_temporalHistogram_zscoreOnly()
%% FIGURE 3 (Z-SCORE ONLY): Temporal Distribution of Spindles
% Loads data, processes them, and creates ONLY the z-scored plot.
% No statistical tests or comparisons are computed.

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

% Z-score parameters
zscore_method = 'all';   % 'off' = baseline z-score using OFF-condition mean/SD only
                         % 'all' = z-score using mean/SD across ALL conditions

% Publication settings
pub = struct();
pub.fig_width_cm = 21;
pub.fig_height_cm = 7;
pub.font_name = 'Arial';
pub.font_size_axis = 8;
pub.font_size_label = 9;
pub.font_size_title = 10;
pub.line_width = 2;

% Colors
colors = struct();
colors.x1HZ = [0.0 0.2 0.6];   % Blue
colors.x5HZ = [1.0 0.55 0.0];  % Orange
colors.OFF  = [0.6 0.6 0.6];   % Gray

fprintf('=== FIGURE 3 (Z-SCORE ONLY): Temporal Histogram ===\n');

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

stage_col = 'Stage';
if ismember('SleepStage', all_sleep_stages.Properties.VariableNames)
    stage_col = 'SleepStage';
end

trials.SleepStage = cell(height(trials), 1);

unique_subjects = unique(trials.Subject);

for subj_idx = 1:length(unique_subjects)
    subject = unique_subjects{subj_idx};

    subj_stages = all_sleep_stages(strcmp(all_sleep_stages.Subject, subject), :);
    if isempty(subj_stages)
        warning('No sleep stages found for subject %s', subject);
        continue;
    end

    stage_times_sec = seconds(subj_stages.Timestamp - subj_stages.Timestamp(1));

    subj_trial_idx = strcmp(trials.Subject, subject);
    subj_trials = trials(subj_trial_idx, :);

    for t_idx = 1:height(subj_trials)
        trial_start = subj_trials.StartTime(t_idx);
        trial_end = subj_trials.EndTime(t_idx);
        trial_midpoint = (trial_start + trial_end) / 2;

        stage_idx = find(stage_times_sec <= trial_midpoint, 1, 'last');

        if ~isempty(stage_idx)
            trials.SleepStage{find(subj_trial_idx, 1, 'first') + t_idx - 1} = subj_stages.(stage_col){stage_idx};
        else
            trials.SleepStage{find(subj_trial_idx, 1, 'first') + t_idx - 1} = 'Unknown';
        end
    end
end

% Filter trials to only include specified sleep stages
trials_before = height(trials);
trials = trials(ismember(trials.SleepStage, sleep_stages), :);
fprintf('Filtered trials: %d -> %d (kept only %s trials)\n', ...
    trials_before, height(trials), strjoin(sleep_stages, ', '));

%% Filter Spindles
fprintf('\nFiltering spindles...\n');

primary_channels = cellfun(@(x) extract_primary_channel(x), ...
    spindles.Channel, 'UniformOutput', false);
spindles.PrimaryChannel = primary_channels;

spindles = spindles(ismember(spindles.SleepStage, sleep_stages), :);

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

%% Create Histogram Bins (centered at zero for trial onset)
bin_edges = -window_before:bin_width:window_after;
bin_centers = bin_edges(1:end-1) + bin_width/2;
n_bins = length(bin_centers);

fprintf('\nBin edges: %d bins from %.2f to %.2f s\n', n_bins, bin_edges(1), bin_edges(end));

% Get unique subjects
subjects = unique(trials.Subject);
n_subj = length(subjects);
n_cond = length(conditions);

%% Build electrode-level data table
fprintf('\nBuilding electrode-level data table...\n');

max_electrodes = 30;
n_rows_elec = n_subj * n_cond * max_electrodes * n_bins;
electrode_data = cell(n_rows_elec, 6);
elec_row_idx = 0;

for s = 1:n_subj
    subject = subjects{s};
    subj_spindles = spindles(strcmp(spindles.Subject, subject), :);
    subj_trials = trials(strcmp(trials.Subject, subject), :);

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

            n_trials_elec = height(cond_trials);
            all_spindle_times = [];

            elec_mask = strcmp(subj_spindles.PrimaryChannel, electrode);
            elec_spindles_all = subj_spindles(elec_mask, :);

            if ~isempty(elec_spindles_all)
                relative_times_cell = cell(n_trials_elec, 1);
                for t = 1:n_trials_elec
                    trial_onset = cond_trials.StartTime(t);
                    window_start = trial_onset - window_before;
                    window_end = trial_onset + window_after;

                    trial_mask = elec_spindles_all.Start >= window_start & ...
                                 elec_spindles_all.Start < window_end;

                    if any(trial_mask)
                        relative_times_cell{t} = elec_spindles_all.Start(trial_mask) - trial_onset;
                    end
                end
                all_spindle_times = vertcat(relative_times_cell{:});
            end

            rate = compute_bin_rate(all_spindle_times, bin_edges, n_trials_elec);

            for b = 1:n_bins
                elec_row_idx = elec_row_idx + 1;
                electrode_data(elec_row_idx, :) = {subject, electrode, condition, b, bin_centers(b), rate(b)};
            end
        end
    end
    fprintf('  %s: %d electrodes processed\n', subject, length(unique_electrodes));
end

electrode_data = electrode_data(1:elec_row_idx, :);

electrode_tbl = cell2table(electrode_data, ...
    'VariableNames', {'Subject', 'Electrode', 'Condition', 'BinIdx', 'BinCenter', 'SpindleProb'});
electrode_tbl.Subject = categorical(electrode_tbl.Subject);
electrode_tbl.Electrode = categorical(electrode_tbl.Electrode);
electrode_tbl.Condition = categorical(electrode_tbl.Condition);

fprintf('Electrode-level table: %d rows\n', height(electrode_tbl));

%% Compute subject-level means (aggregate across electrodes)
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

%% Z-score normalization per participant
fprintf('\nComputing z-score normalization per participant (method: %s)...\n', zscore_method);

subject_probs_z = nan(size(subject_probs));

if strcmp(zscore_method, 'off')
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

% Average across subjects (z-scored)
mean_probs_z = squeeze(mean(subject_probs_z, 1, 'omitnan'));
sem_probs_z = squeeze(std(subject_probs_z, 0, 1, 'omitnan') ./ sqrt(sum(~isnan(subject_probs_z), 1)));

% Prepare ROI string for figure title
if strcmp(roi_electrodes, 'all')
    roi_str = 'all';
else
    if iscell(roi_electrodes)
        roi_str = strjoin(roi_electrodes, ', ');
    else
        roi_str = roi_electrodes;
    end
end

%% Create Figure
fprintf('\n=== Creating Z-scored Figure ===\n');

if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

filename_base = 'figure3_temporalHistogram_zscoreOnly';

% Y-limits: symmetrical around zero for z-scored data
max_abs_y = max(abs(mean_probs_z(:)) + abs(sem_probs_z(:)), [], 'omitnan');
if isnan(max_abs_y) || max_abs_y <= 0
    max_abs_y = 0.5;
else
    max_abs_y = max_abs_y * 1.2;
end
min_y = -max_abs_y;
max_y = max_abs_y;

% Layout
left_margin   = 0.08;
right_margin  = 0.02;
gap           = 0.04;
bottom_margin = 0.15;

fig_title_bot = 0.93;
cond_lbl_h    = 0.04;
cond_lbl_bot  = fig_title_bot - cond_lbl_h - 0.01;
cond_lbl_top  = cond_lbl_bot + cond_lbl_h;

plot_top    = cond_lbl_bot - 0.005;
plot_height = plot_top - bottom_margin;
plot_width  = (1 - left_margin - right_margin - (n_cond-1)*gap) / n_cond;

% Create figure
fig_width_cm  = 18;
fig_height_cm = 7;

fig = figure('Units', 'centimeters', ...
             'Position', [2, 2, fig_width_cm, fig_height_cm], ...
             'Color', 'white', ...
             'PaperUnits', 'centimeters', ...
             'PaperSize', [fig_width_cm, fig_height_cm], ...
             'PaperPosition', [0, 0, fig_width_cm, fig_height_cm]);

cond_display = {'5 Hz', '1 Hz', 'OFF'};

ax_handles = gobjects(1, n_cond);
for c = 1:n_cond
    condition = conditions{c};
    left_pos  = left_margin + (c-1) * (plot_width + gap);
    ax_handles(c) = axes('Position', [left_pos, bottom_margin, plot_width, plot_height]);
    hold on;

    bar(bin_centers, mean_probs_z(:, c), ...
        'FaceColor', colors.(condition), ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.8, ...
        'BarWidth', 0.85);

    errorbar(bin_centers, mean_probs_z(:, c), sem_probs_z(:, c), ...
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
        ylabel('Spindle Rate (z-scored)', 'FontName', pub.font_name, ...
            'FontSize', pub.font_size_label);
    else
        set(gca, 'YTickLabel', []);
    end
    ylim([min_y, max_y]);
end

% Condition labels above each subplot
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

% Figure title
if strcmp(zscore_method, 'off')
    title_str = sprintf('Temporal Distribution of Spindles (ROI: %s) [Z-scored, OFF baseline]', roi_str);
else
    title_str = sprintf('Temporal Distribution of Spindles (ROI: %s) [Z-scored, all conditions]', roi_str);
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

%% Save
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'subject_probs', 'subject_probs_z', 'mean_probs_z', 'sem_probs_z', ...
     'electrode_tbl', 'bin_centers', 'bin_edges', 'subjects', 'conditions', ...
     'roi_electrodes', 'zscore_method', 'pub', '-v7.3');

fprintf('\nSaving figure...\n');
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));
fprintf('  Saved: %s.png/.svg/.fig\n', filename_base);
fprintf('\nOutputs saved to: %s\n', OUTPUT_DIR);
fprintf('=== Done ===\n');

end

%% Helper Functions

function rate = compute_bin_rate(spindle_times, bin_edges, n_total_obs)
    n_bins = numel(bin_edges) - 1;
    rate = zeros(1, n_bins);

    if isempty(spindle_times) || n_total_obs == 0
        return;
    end

    for i = 1:n_bins
        bin_start = bin_edges(i);
        bin_end   = bin_edges(i+1);
        in_bin = (spindle_times >= bin_start) & (spindle_times < bin_end);
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
