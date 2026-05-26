function figure3_onsetDelayBarplot()
%% FIGURE 3: Spindle Onset Delay Barplot
% Shows the delay from trial onset to first spindle detection per condition
% Averaged across ROI electrodes (CZ, C3, C4, CP1, CP2)
% Includes LMM statistics, error bars, individual subject points, and significance markers

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
sleep_stages = {'N2', 'N3'};
roi_electrodes = {'CZ', 'C3', 'C4', 'FC1', 'FC2', 'FZ'};
%roi_electrodes = {'FP1', 'FP2', 'F7', 'F3', 'FZ', 'F4', 'FC5', 'FC1', 'FC6', 'T7', 'C3', 'CZ', 'C4', 'T8', 'CP5', 'CP1', 'CP2', 'CP6', 'P7', 'P3', 'PZ', 'P4', 'POZ', 'O1', 'O2', 'F8', 'FC2', 'P8'};

% Spindle filtering criteria
freq_range = [12, 16];
dur_range = [0.5, 3];
amp_range = [15, 100];
delay_max_window = 8.0;  % Maximum delay to consider (seconds)

% Statistical parameters
alpha = 0.05;

% Publication settings
pub = struct();
pub.fig_width_cm = 8.5;
pub.fig_height_cm = 7;
pub.font_name = 'Arial';
pub.font_size_axis = 8;
pub.font_size_label = 9;
pub.font_size_title = 10;
pub.bar_width = 0.7;

% Colors
colors = [
    0.2, 0.4, 0.8;   % Blue for x1HZ
    1.0, 0.55, 0.0;   % Red for x5HZ
    0.5, 0.5, 0.5    % Gray for OFF
];

fprintf('=== FIGURE 3: Onset Delay Barplot ===\n');

% Load Data
fprintf('\nLoading data...\n');
loaded = load(DATA_FILE, 'all_spindles');
spindles = loaded.all_spindles;
fprintf('Loaded %d spindles\n', height(spindles));

% Filter and Prepare Data
fprintf('\nFiltering spindles...\n');

% Extract primary channels
primary_channels = cellfun(@(x) extract_primary_channel(x), ...
    spindles.Channel, 'UniformOutput', false);
spindles.PrimaryChannel = primary_channels;

% Compute onset delay
if ismember('ConditionStartTime', spindles.Properties.VariableNames) && ...
   ismember('Start', spindles.Properties.VariableNames)
    spindles.OnsetDelay = spindles.Start - spindles.ConditionStartTime;
else
    error('Cannot compute onset delay (missing ConditionStartTime or Start)');
end

% Apply filters
spindles = spindles(ismember(spindles.SleepStage, sleep_stages), :);
spindles = spindles(ismember(spindles.Condition, conditions), :);
spindles = spindles(ismember(spindles.PrimaryChannel, roi_electrodes), :);

spindles = spindles(spindles.Frequency >= freq_range(1) & ...
                   spindles.Frequency <= freq_range(2), :);
spindles = spindles(spindles.Duration >= dur_range(1) & ...
                   spindles.Duration <= dur_range(2), :);
spindles = spindles(spindles.Amplitude >= amp_range(1) & ...
                   spindles.Amplitude <= amp_range(2), :);

% Filter by valid onset delay
spindles = spindles(spindles.OnsetDelay >= 0 & ...
                   spindles.OnsetDelay <= delay_max_window & ...
                   isfinite(spindles.OnsetDelay), :);

fprintf('Final filtered spindles: %d\n', height(spindles));

% Extract Minimum Onset Delay per Trial
fprintf('\nExtracting minimum onset delay per trial...\n');

% Create unique trial identifier
cst_str = compose('%.6f', spindles.ConditionStartTime);
trial_key = strcat(string(spindles.Subject), '|', string(spindles.Condition), '|', ...
                   string(spindles.PrimaryChannel), '|', cst_str);

% Get minimum delay per trial
[unique_keys, ~, gi] = unique(trial_key, 'stable');
min_delays = accumarray(gi, spindles.OnsetDelay, [], @min);

% Reconstruct table
trial_data = table();
for i = 1:length(unique_keys)
    parts = split(unique_keys{i}, '|');
    trial_data.Subject{i} = char(parts{1});
    trial_data.Condition{i} = char(parts{2});
    trial_data.Channel{i} = char(parts{3});
    trial_data.OnsetDelay(i) = min_delays(i);
end

fprintf('Extracted %d trial onset delays\n', height(trial_data));

% Compute Subject-Level Means Across ROI
fprintf('\nComputing subject-level means across ROI...\n');

subjects = unique(trial_data.Subject);
n_subj = length(subjects);
n_cond = length(conditions);

subject_means = nan(n_subj, n_cond);

for s = 1:n_subj
    subject = subjects{s};

    for c = 1:n_cond
        condition = conditions{c};

        % Get all trial delays for this subject-condition across ROI
        mask = strcmp(trial_data.Subject, subject) & ...
               strcmp(trial_data.Condition, condition);

        delays = trial_data.OnsetDelay(mask);

        if ~isempty(delays)
            subject_means(s, c) = mean(delays, 'omitnan');
        end
    end
end

fprintf('Computed means for %d subjects\n', n_subj);

% Filter for complete cases (subjects with data in ALL conditions)
fprintf('\nFiltering for subjects with data in all conditions...\n');
complete_subjects_mask = all(~isnan(subject_means), 2);
n_complete = sum(complete_subjects_mask);

fprintf('  Total subjects: %d\n', n_subj);
fprintf('  Subjects with all conditions: %d\n', n_complete);
fprintf('  Subjects excluded: %d\n', n_subj - n_complete);

% Filter data to only complete subjects
subjects_filtered = subjects(complete_subjects_mask);
subject_means_filtered = subject_means(complete_subjects_mask, :);

% Statistical Analysis - LMM
fprintf('\nRunning LMM statistical analysis...\n');

% Prepare table for LMM using filtered (complete) subjects only
lmm_table = table();
for s = 1:n_complete
    for c = 1:n_cond
        lmm_table = [lmm_table; {subjects_filtered{s}, conditions{c}, subject_means_filtered(s, c)}];
    end
end
lmm_table.Properties.VariableNames = {'Subject', 'Condition', 'OnsetDelay'};
lmm_table.Subject = categorical(lmm_table.Subject);
lmm_table.Condition = categorical(lmm_table.Condition);

% Fit LMM
fprintf('Fitting LMM: OnsetDelay ~ Condition + (1|Subject)\n');
lme = fitlme(lmm_table, 'OnsetDelay ~ Condition + (1|Subject)');

% ANOVA
anova_results = anova(lme);
fprintf('LMM ANOVA: F(%d,%d) = %.3f, p = %.4f\n', ...
    anova_results.DF1(2), anova_results.DF2(2), ...
    anova_results.FStat(2), anova_results.pValue(2));

% Post-hoc pairwise comparisons
fprintf('\nPost-hoc pairwise comparisons:\n');
pair_indices = nchoosek(1:n_cond, 2);
posthoc_results = table();

for p = 1:size(pair_indices, 1)
    c1_idx = pair_indices(p, 1);
    c2_idx = pair_indices(p, 2);
    c1 = conditions{c1_idx};
    c2 = conditions{c2_idx};

    % Get paired subjects (all are valid since we filtered for complete cases)
    vals1 = subject_means_filtered(:, c1_idx);
    vals2 = subject_means_filtered(:, c2_idx);

    [h, p, ci, stats] = ttest(vals1, vals2);

    % Cohen's d
    cohens_d = mean(vals1 - vals2) / std(vals1 - vals2);

    fprintf('  %s vs %s: n=%d, t(%d)=%.3f, p=%.4f, d=%.3f', ...
        c1, c2, n_complete, stats.df, stats.tstat, p, cohens_d);

    if p < alpha
        fprintf(' *\n');
    else
        fprintf('\n');
    end

    posthoc_results = [posthoc_results; {c1, c2, n_complete, stats.tstat, ...
        stats.df, p, cohens_d}];
end
posthoc_results.Properties.VariableNames = {'Condition_1', 'Condition_2', ...
    'n_paired', 'tStat', 'df', 'pValue', 'cohens_d'};

% Create Figure
fprintf('\nCreating figure...\n');

if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

fig = figure('Units', 'centimeters', ...
             'Position', [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color', 'white', ...
             'PaperUnits', 'centimeters', ...
             'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% Calculate means and SEMs using filtered data
means = mean(subject_means_filtered, 1, 'omitnan');
sems = std(subject_means_filtered, 0, 1, 'omitnan') ./ sqrt(n_complete);

% Create bars
hold on;
for c = 1:n_cond
    bar(c, means(c), pub.bar_width, 'FaceColor', colors(c,:), ...
        'EdgeColor', 'k', 'LineWidth', 1.2);
end

% Add error bars
errorbar(1:n_cond, means, sems, 'k.', 'LineWidth', 1.5, 'CapSize', 10);

% Add connecting lines for individual subjects (faint)
for s = 1:n_complete
    data_points = subject_means_filtered(s, :);
    plot(1:n_cond, data_points, '-', 'Color', [0.6, 0.6, 0.6, 0.3], 'LineWidth', 0.5);
end

% Add individual data points with jitter
for c = 1:n_cond
    data_points = subject_means_filtered(:, c);

    x_jitter = c + 0.15 * (rand(n_complete, 1) - 0.5);

    scatter(x_jitter, data_points, 15, colors(c,:), 'o', ...
        'MarkerEdgeColor', [0, 0, 0], ...
        'MarkerEdgeAlpha', 0.4, ...
        'MarkerFaceAlpha', 0.4, ...
        'LineWidth', 0.5);
end

% Add significance markers
% Calculate y_max based on actual maximum individual data point
max_individual_point = max(subject_means_filtered(:), [], 'omitnan');
y_max = max_individual_point * 1.15;  % Add 15% margin above highest point
y_offset = y_max;
line_height = range([means(:); subject_means_filtered(:)]) * 0.05;

for p = 1:height(posthoc_results)
    if posthoc_results.pValue(p) < alpha
        c1 = char(posthoc_results.Condition_1(p));
        c2 = char(posthoc_results.Condition_2(p));
        c1_idx = find(strcmp(conditions, c1));
        c2_idx = find(strcmp(conditions, c2));

        % Draw significance line
        plot([c1_idx, c2_idx], [y_offset, y_offset], 'k-', 'LineWidth', 1.5);

        % Add asterisks
        if posthoc_results.pValue(p) < 0.001
            sig_text = '***';
        elseif posthoc_results.pValue(p) < 0.01
            sig_text = '**';
        else
            sig_text = '*';
        end

        text(mean([c1_idx, c2_idx]), y_offset + line_height*0.3, sig_text, ...
            'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold');

        y_offset = y_offset + line_height * 2;
    end
end

hold off;

% Formatting
condition_labels = cellfun(@(x) strrep(strrep(x, 'x', ''), 'HZ', ' Hz'), ...
    conditions, 'UniformOutput', false);
set(gca, 'XTick', 1:n_cond, 'XTickLabel', condition_labels);
set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
    'Box', 'off', 'TickDir', 'out');

xlabel('Condition', 'FontName', pub.font_name, 'FontSize', pub.font_size_label, ...
    'FontWeight', 'bold');
ylabel('Spindle Onset Delay (s)', 'FontName', pub.font_name, ...
    'FontSize', pub.font_size_label, 'FontWeight', 'bold');
title(sprintf('Spindle Onset Delay (ROI: %s)', strjoin(roi_electrodes, ', ')), ...
    'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

ylim([0, y_offset]);
grid on;

%% Save Figure
filename_base = 'figure3_onsetDelayBarplot';

print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'subject_means_filtered', 'subjects_filtered', 'means', 'sems', 'conditions', ...
     'lme', 'anova_results', 'posthoc_results', 'roi_electrodes', 'pub', ...
     'n_complete', 'complete_subjects_mask', 'subject_means', 'subjects', '-v7.3');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('=== Done ===\n');

end

%% Helper Functions

function primary = extract_primary_channel(ch)
    if iscell(ch), ch = ch{1}; end
    ch = strtok(ch, '+');
    ch = regexprep(ch, 'A[12]', '');
    ch = regexprep(ch, '[^A-Za-z0-9]', '');
    primary = upper(ch);
end
