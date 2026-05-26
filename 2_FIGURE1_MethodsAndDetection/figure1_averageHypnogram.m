function figure1_averageHypnogram()
%% FIGURE 1: Average Hypnogram
% Creates an average hypnogram across all subjects showing typical sleep
% progression during the nap
%
% This demonstrates the sleep architecture and quality of the nap protocol

clear; clc;

%% Configuration
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
RESULTS_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
OUTPUT_DIR = fullfile(REPO_ROOT, '2_FIGURE1_MethodsAndDetection', 'outputs');

% Data file
data_file = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');

% Stage encoding for hypnogram
stage_map = containers.Map({'Wake', 'N1', 'N2', 'N3', 'REM'}, [0, 1, 2, 3, -1]);
stage_labels = {'REM', 'Wake', 'N1', 'N2', 'N3'};  % Sorted by stage_values
stage_values = [-1, 0, 1, 2, 3];  % Must be in increasing order for YTick
stage_colors = [0.9 0.6 0.3;   % Orange for REM
                0.9 0.9 0.9;   % Light gray for Wake
                0.7 0.85 1.0;  % Light blue for N1
                0.3 0.6 0.9;   % Medium blue for N2
                0.1 0.3 0.7];  % Dark blue for N3

% Publication settings
pub = struct();
pub.fig_width_cm = 17;
pub.fig_height_cm = 5;
pub.font_name = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;
pub.bin_size_min = 0.5;  % 30-second bins for smooth average
pub.apply_continuity = true;  % Apply continuity/smoothing rule
pub.continuity_window = 2;  % Inner window for immediate neighbors
pub.continuity_outer_window = 3;  % Outer window to check for consistent surrounding stage
pub.min_subject_pct = 0.80;  % Only show time points with >= 80% of subjects

fprintf('=== FIGURE 1: Average Hypnogram ===\n');

%% Load data
fprintf('Loading data from: %s\n', data_file);
if ~exist(data_file, 'file')
    error('Data file not found: %s', data_file);
end

load(data_file, 'all_sleep_stages', 'subjects');
fprintf('Loaded data for %d subjects\n', length(subjects));

%% Process each subject's hypnogram
fprintf('Processing hypnograms...\n');

% Find maximum recording duration
max_duration_min = 0;
subject_hypnograms = cell(length(subjects), 1);

for s = 1:length(subjects)
    subject = subjects{s};
    subj_stages = all_sleep_stages(strcmp(all_sleep_stages.Subject, subject), :);

    % Sort by timestamp
    [~, sort_idx] = sort(subj_stages.Timestamp);
    subj_stages = subj_stages(sort_idx, :);

    % Convert to time series
    if isduration(subj_stages.Timestamp)
        times = minutes(subj_stages.Timestamp);  % Convert duration to minutes
    elseif isdatetime(subj_stages.Timestamp)
        times = minutes(subj_stages.Timestamp - subj_stages.Timestamp(1));  % Elapsed time in minutes
    else
        times = subj_stages.Timestamp / 60;  % Assume numeric in seconds
    end
    stages = cell(height(subj_stages), 1);
    for i = 1:height(subj_stages)
        stages{i} = subj_stages.Stage{i};
    end

    subject_hypnograms{s}.times = times;
    subject_hypnograms{s}.stages = stages;

    max_duration_min = max(max_duration_min, max(times));

    fprintf('  %s: %.1f min, %d stage transitions\n', ...
            subject, max(times), length(times));
end

fprintf('Maximum recording duration: %.1f min\n', max_duration_min);

%% Create common time grid and average
time_grid = 0:pub.bin_size_min:ceil(max_duration_min);
n_bins = length(time_grid);
n_subj = length(subjects);

% Matrix to store all subjects' hypnograms on common grid
hypno_matrix = nan(n_subj, n_bins);

for s = 1:n_subj
    subj_data = subject_hypnograms{s};

    % Interpolate to common time grid
    for t = 1:n_bins
        curr_time = time_grid(t);

        % Find the stage at this time
        idx = find(subj_data.times <= curr_time, 1, 'last');

        if ~isempty(idx)
            stage_str = subj_data.stages{idx};
            if stage_map.isKey(stage_str)
                hypno_matrix(s, t) = stage_map(stage_str);
            end
        end
    end
end

% Compute mode (most common stage) at each time point
% Also track how many subjects contribute at each time point
hypno_avg = nan(1, n_bins);
subject_count = zeros(1, n_bins);

for t = 1:n_bins
    valid_stages = hypno_matrix(~isnan(hypno_matrix(:, t)), t);
    subject_count(t) = length(valid_stages);

    if ~isempty(valid_stages)
        hypno_avg(t) = mode(valid_stages);
    end
end

% Find time range with sufficient subject coverage
min_subjects = ceil(n_subj * pub.min_subject_pct);
valid_time_idx = subject_count >= min_subjects;
last_valid_idx = find(valid_time_idx, 1, 'last');

if isempty(last_valid_idx)
    warning('No time points with %.0f%% subject coverage. Using all data.', pub.min_subject_pct * 100);
    last_valid_idx = n_bins;
end

fprintf('Averaged %d subjects into %d time bins (%.1f min bins)\n', ...
        n_subj, n_bins, pub.bin_size_min);
fprintf('Valid time range: 0-%.1f min (>= %d subjects, %.0f%% coverage)\n', ...
        time_grid(last_valid_idx), min_subjects, pub.min_subject_pct * 100);

%% Apply continuity rule (smoothing)
if pub.apply_continuity
    hypno_raw = hypno_avg;  % Save original for comparison
    n_changes = 0;

    % Iterate a few times to smooth out isolated epochs
    for iter = 1:5
        iter_changes = 0;

        for t = (pub.continuity_outer_window + 1):(n_bins - pub.continuity_outer_window)
            if isnan(hypno_avg(t))
                continue;
            end

            % Get outer bins to determine the surrounding stage
            left_outer = hypno_avg(t - pub.continuity_outer_window : t - pub.continuity_window - 1);
            right_outer = hypno_avg(t + pub.continuity_window + 1 : t + pub.continuity_outer_window);

            % Check if all outer bins are the same stage
            outer_bins = [left_outer, right_outer];
            valid_outer = outer_bins(~isnan(outer_bins));

            if ~isempty(valid_outer) && length(valid_outer) >= 2
                % If all outer bins are the same
                if all(valid_outer == valid_outer(1))
                    surrounding_stage = valid_outer(1);

                    % If current bin differs from the surrounding stage, smooth it
                    if hypno_avg(t) ~= surrounding_stage
                        hypno_avg(t) = surrounding_stage;
                        iter_changes = iter_changes + 1;
                    end
                end
            end
        end

        n_changes = n_changes + iter_changes;
        if iter_changes == 0
            break;  % No more changes, stop iterating
        end
    end

    fprintf('Applied continuity rule: %d bins smoothed\n', n_changes);
end

%% Create figure
fig = figure('Units', 'centimeters', ...
             'Position', [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color', 'white', ...
             'PaperUnits', 'centimeters', ...
             'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% Plot hypnogram as filled areas
hold on;

% Plot each stage as a separate patch for better control
for st = 1:length(stage_values)
    stage_val = stage_values(st);

    % Find continuous segments of this stage
    is_stage = hypno_avg == stage_val;
    stage_starts = find(diff([0, is_stage]) == 1);
    stage_ends = find(diff([is_stage, 0]) == -1);

    for seg = 1:length(stage_starts)
        x_seg = [time_grid(stage_starts(seg)), time_grid(stage_ends(seg)), ...
                 time_grid(stage_ends(seg)), time_grid(stage_starts(seg))];
        y_seg = [stage_val-0.4, stage_val-0.4, stage_val+0.4, stage_val+0.4];

        patch(x_seg, y_seg, stage_colors(st, :), 'EdgeColor', 'none', 'FaceAlpha', 0.9);
    end
end

% Plot the line
valid_idx = ~isnan(hypno_avg);
plot(time_grid(valid_idx), hypno_avg(valid_idx), 'k-', 'LineWidth', 1.2);

% Formatting
set(gca, 'YTick', stage_values, 'YTickLabel', stage_labels, ...
         'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
         'Box', 'off', 'TickDir', 'out', 'YDir', 'reverse');
xlabel('Time (min)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel('Sleep Stage', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
title('Average Hypnogram Across Subjects', ...
      'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

xlim([0, time_grid(last_valid_idx)]);
ylim([min(stage_values)-0.5, max(stage_values)+0.5]);
grid on;

hold off;

%% Save figure
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

% Save as PNG, SVG, and FIG
filename_base = 'figure1_hypnogram';
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

% Save data
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'time_grid', 'hypno_avg', 'hypno_matrix', 'subject_hypnograms', ...
     'subject_count', 'last_valid_idx', 'stage_map', 'subjects', 'pub');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('=== Done ===\n');

end
