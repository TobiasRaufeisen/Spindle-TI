function figure1_hypnoProbability()
%% FIGURE 1: Hypnodensity Graph
% Creates a hypnodensity graph across all subjects showing the
% proportion of subjects in each sleep stage at each time point during the nap.

clear; clc;

% Configuration
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
RESULTS_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
OUTPUT_DIR  = fullfile(REPO_ROOT, '2_FIGURE1_MethodsAndDetection', 'outputs');

% Data file
data_file = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');

% Stage encoding (same codes used when building the subject matrix)
stage_map = containers.Map({'Wake', 'N1', 'N2', 'N3', 'REM'}, [0, 1, 2, 3, -1]);

% Stacking order for the area plot (bottom to top).
% Colours match the original average-hypnogram script.
stack_labels = {'Wake', 'N1',  'N2',  'N3',  'REM'};
stack_values = [ 0,      1,     2,     3,    -1   ];
stack_colors = [0.9  0.9  0.9;   % Light gray  -- Wake
                0.7  0.85 1.0;   % Light blue  -- N1
                0.3  0.6  0.9;   % Medium blue -- N2
                0.1  0.3  0.7;   % Dark blue   -- N3
                0.9  0.6  0.3];  % Orange      -- REM

% Publication settings
pub = struct();
pub.fig_width_cm    = 17;
pub.fig_height_cm   = 6;
pub.font_name       = 'Arial';
pub.font_size_axis  = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;
pub.bin_size_min    = 0.5;   % 30-second bins
pub.min_subject_pct = 0.80;  % Only show time points with >= 80 % of subjects

fprintf('=== FIGURE 1: Hypnodensity Graph ===\n');

% Load data
fprintf('Loading data from: %s\n', data_file);
if ~exist(data_file, 'file')
    error('Data file not found: %s', data_file);
end

load(data_file, 'all_sleep_stages', 'subjects');
fprintf('Loaded data for %d subjects\n', length(subjects));

% Process each subject's hypnogram (identical to averageHypnogram)
fprintf('Processing hypnograms...\n');

max_duration_min    = 0;
subject_hypnograms  = cell(length(subjects), 1);

for s = 1:length(subjects)
    subject     = subjects{s};
    subj_stages = all_sleep_stages(strcmp(all_sleep_stages.Subject, subject), :);

    % Sort by timestamp
    [~, sort_idx] = sort(subj_stages.Timestamp);
    subj_stages  = subj_stages(sort_idx, :);

    % Convert to elapsed minutes
    if isduration(subj_stages.Timestamp)
        times = minutes(subj_stages.Timestamp);
    elseif isdatetime(subj_stages.Timestamp)
        times = minutes(subj_stages.Timestamp - subj_stages.Timestamp(1));
    else
        times = subj_stages.Timestamp / 60;   % assume numeric seconds
    end

    stages = cell(height(subj_stages), 1);
    for i = 1:height(subj_stages)
        stages{i} = subj_stages.Stage{i};
    end

    subject_hypnograms{s}.times  = times;
    subject_hypnograms{s}.stages = stages;
    max_duration_min = max(max_duration_min, max(times));

    fprintf('  %s: %.1f min, %d stage transitions\n', ...
            subject, max(times), length(times));
end

fprintf('Maximum recording duration: %.1f min\n', max_duration_min);

% Map every subject onto the common time grid
time_grid = 0:pub.bin_size_min:ceil(max_duration_min);
n_bins    = length(time_grid);
n_subj    = length(subjects);

% hypno_matrix(s,t) = stage code for subject s at bin t  (NaN = no data)
hypno_matrix = nan(n_subj, n_bins);

for s = 1:n_subj
    subj_data = subject_hypnograms{s};

    for t = 1:n_bins
        idx = find(subj_data.times <= time_grid(t), 1, 'last');

        if ~isempty(idx)
            stage_str = subj_data.stages{idx};
            if stage_map.isKey(stage_str)
                hypno_matrix(s, t) = stage_map(stage_str);
            end
        end
    end
end

% Compute hypnodensity values at every time bin
n_stages    = length(stack_values);
prob_matrix = zeros(n_bins, n_stages);   % rows = time, cols = stacking order
subject_count = zeros(1, n_bins);

for t = 1:n_bins
    valid = hypno_matrix(~isnan(hypno_matrix(:, t)), t);
    subject_count(t) = length(valid);

    if ~isempty(valid)
        for st = 1:n_stages
            prob_matrix(t, st) = sum(valid == stack_values(st)) / length(valid);
        end
    end
end

% Determine the valid time range based on subject coverage
min_subjects  = ceil(n_subj * pub.min_subject_pct);
valid_time_idx = subject_count >= min_subjects;
last_valid_idx = find(valid_time_idx, 1, 'last');

if isempty(last_valid_idx)
    warning('No time points with %.0f%% subject coverage. Using all data.', ...
            pub.min_subject_pct * 100);
    last_valid_idx = n_bins;
end

fprintf('Computed hypnodensity over %d time bins (%.1f min bins)\n', n_bins, pub.bin_size_min);
fprintf('Valid time range: 0-%.1f min (>= %d subjects, %.0f%% coverage)\n', ...
        time_grid(last_valid_idx), min_subjects, pub.min_subject_pct * 100);

% Create figure
fig = figure('Units',          'centimeters', ...
             'Position',       [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color',          'white', ...
             'PaperUnits',     'centimeters', ...
             'PaperSize',      [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition',  [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% Trim data to the valid time range
t_plot = time_grid(1:last_valid_idx);
p_plot = prob_matrix(1:last_valid_idx, :);

% Stacked area plot -- columns stack in order: Wake, N1, N2, N3, REM
h = area(t_plot, p_plot);

for st = 1:n_stages
    h(st).FaceColor = stack_colors(st, :);
    h(st).EdgeColor = [0.3 0.3 0.3];
    h(st).LineWidth = 0.75;
end

% Axes formatting
set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
         'Box', 'off', 'TickDir', 'out');
xlabel('Time (min)',   'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel('Probability',  'FontName', pub.font_name, 'FontSize', pub.font_size_label);
title('Sleep Stage Hypnodensity Graph', ...
      'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

xlim([0, time_grid(last_valid_idx)]);
ylim([0, 1]);
yticks(0:0.2:1);
grid on;

% Legend -- listed in stacking order (bottom to top)
legend(h, stack_labels, ...
       'Location', 'best', ...
       'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
       'Box', 'off');

%% Save figure
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

filename_base = 'figure1_hypnoProbability';
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

% Save data (prob_matrix replaces hypno_avg; hypno_matrix kept for reference)
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'time_grid', 'prob_matrix', 'hypno_matrix', 'subject_hypnograms', ...
     'subject_count', 'last_valid_idx', 'stack_labels', 'stack_values', ...
     'stack_colors', 'subjects', 'pub');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('=== Done ===\n');

end
