function figure1_singleHypnogram()
%% FIGURE 1_2: Single Participant Illustrative Hypnogram
% Creates an illustrative hypnogram from a single representative subject
% showing typical sleep progression during the nap
%
% This demonstrates individual sleep architecture during the nap protocol

clear; clc;

% Configuration
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
RESULTS_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
OUTPUT_DIR = fullfile(REPO_ROOT, '2_FIGURE1_MethodsAndDetection', 'outputs');

% Data file
data_file = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');

% Subject selection
% Specify a subject ID: e.g., 'sub5'
selected_subject = 'sub17';

% Stage encoding for hypnogram
stage_map = containers.Map({'Wake', 'N1', 'N2', 'N3', 'REM'}, [0, 1, 2, 3, -1]);
stage_labels = {'REM', 'Wake', 'N1', 'N2', 'N3'};  % Sorted by stage_values
stage_values = [-1, 0, 1, 2, 3];  % Must be in increasing order for YTick

% Publication settings
pub = struct();
pub.fig_width_cm = 17;
pub.fig_height_cm = 5;
pub.font_name = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;
pub.bin_size_min = 0.5;  % 30-second bins for smoothing
pub.apply_continuity = true;  % Apply continuity/smoothing rule
pub.continuity_window = 1;  % Inner window for immediate neighbors
pub.continuity_outer_window = 1;  % Outer window to check for consistent surrounding stage

fprintf('=== FIGURE 1_2: Single Participant Hypnogram ===\n');

% Load data
fprintf('Loading data from: %s\n', data_file);
if ~exist(data_file, 'file')
    error('Data file not found: %s', data_file);
end

load(data_file, 'all_sleep_stages', 'subjects');
fprintf('Loaded data for %d subjects\n', length(subjects));

% Select subject
if ~any(strcmp(subjects, selected_subject))
    error('Subject %s not found in data', selected_subject);
end
fprintf('Using subject: %s\n', selected_subject);

% Process selected subject's hypnogram
subj_stages = all_sleep_stages(strcmp(all_sleep_stages.Subject, selected_subject), :);

% Sort by timestamp
[~, sort_idx] = sort(subj_stages.Timestamp);
subj_stages = subj_stages(sort_idx, :);

% Convert to time series
if isduration(subj_stages.Timestamp)
    times = minutes(subj_stages.Timestamp);
elseif isdatetime(subj_stages.Timestamp)
    times = minutes(subj_stages.Timestamp - subj_stages.Timestamp(1));
else
    times = subj_stages.Timestamp / 60;
end

stages = cell(height(subj_stages), 1);
for i = 1:height(subj_stages)
    stages{i} = subj_stages.Stage{i};
end

% Convert stages to numeric values
stage_numeric = zeros(length(stages), 1);
for i = 1:length(stages)
    if stage_map.isKey(stages{i})
        stage_numeric(i) = stage_map(stages{i});
    else
        stage_numeric(i) = NaN;
    end
end

fprintf('Recording duration: %.1f min\n', max(times));
fprintf('Number of stage transitions: %d\n', length(times));

% Print stage summary
stage_summary = tabulate(stages);
fprintf('\nStage distribution:\n');
for i = 1:size(stage_summary, 1)
    fprintf('  %s: %d epochs (%.1f%%)\n', stage_summary{i,1}, ...
            stage_summary{i,2}, stage_summary{i,3});
end

% Apply smoothing/continuity rule
if pub.apply_continuity
    % Create common time grid with specified bin size
    time_grid = 0:pub.bin_size_min:ceil(max(times));
    n_bins = length(time_grid);

    % Interpolate to common time grid
    stage_binned = nan(1, n_bins);
    for t = 1:n_bins
        curr_time = time_grid(t);

        % Find the stage at this time
        idx = find(times <= curr_time, 1, 'last');

        if ~isempty(idx)
            stage_binned(t) = stage_numeric(idx);
        end
    end

    % Apply continuity rule (smoothing)
    n_changes = 0;

    % Iterate a few times to smooth out isolated epochs
    for iter = 1:5
        iter_changes = 0;

        for t = (pub.continuity_outer_window + 1):(n_bins - pub.continuity_outer_window)
            if isnan(stage_binned(t))
                continue;
            end

            % Get outer bins to determine the surrounding stage
            left_outer = stage_binned(t - pub.continuity_outer_window : t - pub.continuity_window - 1);
            right_outer = stage_binned(t + pub.continuity_window + 1 : t + pub.continuity_outer_window);

            % Check if all outer bins are the same stage
            outer_bins = [left_outer, right_outer];
            valid_outer = outer_bins(~isnan(outer_bins));

            if ~isempty(valid_outer) && length(valid_outer) >= 2
                % If all outer bins are the same
                if all(valid_outer == valid_outer(1))
                    surrounding_stage = valid_outer(1);

                    % If current bin differs from the surrounding stage, smooth it
                    if stage_binned(t) ~= surrounding_stage
                        stage_binned(t) = surrounding_stage;
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

    % Update stage_numeric with smoothed values at original time points
    for i = 1:length(times)
        % Find closest bin
        [~, bin_idx] = min(abs(time_grid - times(i)));
        if ~isnan(stage_binned(bin_idx))
            stage_numeric(i) = stage_binned(bin_idx);
        end
    end
end

% Create figure
fig = figure('Units', 'centimeters', ...
             'Position', [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color', 'white', ...
             'PaperUnits', 'centimeters', ...
             'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% Plot hypnogram as filled areas
hold on;

% Create step function for hypnogram
time_plot = [];
stage_plot = [];
for i = 1:length(times)
    if i < length(times)
        time_plot = [time_plot, times(i), times(i+1)];
        stage_plot = [stage_plot, stage_numeric(i), stage_numeric(i)];
    else
        % Last epoch - extend slightly
        time_plot = [time_plot, times(i), times(i) + 1];
        stage_plot = [stage_plot, stage_numeric(i), stage_numeric(i)];
    end
end

% Plot the line
plot(time_plot, stage_plot, 'k-', 'LineWidth', 1.2);

% Formatting
set(gca, 'YTick', stage_values, 'YTickLabel', stage_labels, ...
         'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
         'Box', 'off', 'TickDir', 'out', 'YDir', 'reverse');

xlabel('Time (min)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel('Sleep Stage', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
title(sprintf('Representative Hypnogram (Subject: %s)', selected_subject), ...
      'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

xlim([min(time_plot), max(time_plot)]);
ylim([min(stage_values)-0.5, max(stage_values)+0.5]);
grid on;

hold off;

%% Save figure
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

% Save as PNG, SVG, and FIG
filename_base = sprintf('figure1_hypnogram_single_%s', selected_subject);
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

% Save data
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'selected_subject', 'times', 'stages', 'stage_numeric', ...
     'stage_map', 'pub', 'time_plot', 'stage_plot');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('=== Done ===\n');

end
