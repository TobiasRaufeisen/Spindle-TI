function figure1_sleepStagesBarplot()
%% FIGURE 1: Sleep Stages per Condition Barplot
% Creates a grouped barplot showing sleep stage durations (N1, N2, N3, REM)
% for each stimulation condition (OFF, 1Hz, 5Hz)
%
% This demonstrates that stimulation did not disrupt sleep architecture

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

% Analysis parameters
conditions = {'x5HZ', 'x1HZ', 'OFF'};
condition_labels = {'5 Hz', '1 Hz', 'Off'};  % Clean labels for plotting
sleep_stages = {'N1', 'N2', 'N3', 'REM'};    % Sleep stages to include
colors = [1.0 0.55 0.0;      % Orange for 5Hz
          0.0 0.2 0.6;       % Dark blue for 1Hz
          0.6 0.6 0.6];      % Gray for Off

% Publication settings
pub = struct();
pub.fig_width_cm = 8.5;
pub.fig_height_cm = 6;
pub.font_name = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;

fprintf('=== FIGURE 1: Sleep Stages Barplot ===\n');

%% Load data
fprintf('Loading data from: %s\n', data_file);
if ~exist(data_file, 'file')
    error('Data file not found: %s', data_file);
end

load(data_file, 'all_condition_durations', 'all_sleep_stages', 'subjects');
fprintf('Loaded data for %d subjects\n', length(subjects));

%% Compute sleep stage durations per condition
n_subj = length(subjects);
n_cond = length(conditions);
n_stages = length(sleep_stages);

% Matrix: subjects x conditions x stages
stage_data = nan(n_subj, n_cond, n_stages);

for s = 1:n_subj
    subject = subjects{s};
    for c = 1:n_cond
        condition = conditions{c};
        for st = 1:n_stages
            stage = sleep_stages{st};

            mask = strcmp(all_condition_durations.Subject, subject) & ...
                   strcmp(all_condition_durations.Condition, condition) & ...
                   strcmp(all_condition_durations.SleepStage, stage);

            stage_data(s, c, st) = sum(all_condition_durations.Duration_min(mask));
        end
    end
end

% Convert to percentages
% Calculate total sleep time per subject and condition
total_sleep = sum(stage_data, 3);  % Sum across stages: subjects x conditions

% Convert each stage to percentage of total sleep
stage_data_percent = nan(size(stage_data));
for s = 1:n_subj
    for c = 1:n_cond
        if total_sleep(s, c) > 0
            stage_data_percent(s, c, :) = (stage_data(s, c, :) / total_sleep(s, c)) * 100;
        end
    end
end

% Compute means and SEMs (in percentages)
stage_means = squeeze(mean(stage_data_percent, 1));  % conditions x stages
stage_sems = squeeze(std(stage_data_percent, 0, 1) / sqrt(n_subj));  % conditions x stages

fprintf('Computed stage percentages for %d conditions x %d stages\n', n_cond, n_stages);

%% Create figure
fig = figure('Units', 'centimeters', ...
             'Position', [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color', 'white', ...
             'PaperUnits', 'centimeters', ...
             'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% Create grouped bar plot
b = bar(stage_means', 'grouped');

% Set colors for each condition
for c = 1:n_cond
    b(c).FaceColor = colors(c, :);
    b(c).EdgeColor = 'none';
    b(c).BarWidth = 0.85;
end

hold on;

% Add error bars
x_offset = [-0.27, 0, 0.27];  % Offsets for 3 groups
for c = 1:n_cond
    x_positions = (1:n_stages) + x_offset(c);
    errorbar(x_positions, stage_means(c, :), stage_sems(c, :), ...
             'k', 'LineStyle', 'none', 'LineWidth', 0.8, 'CapSize', 3);
end

% Formatting
set(gca, 'XTick', 1:n_stages, 'XTickLabel', sleep_stages, ...
         'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
         'Box', 'off', 'TickDir', 'out');
xlabel('Sleep Stage', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel('Percentage (%)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
title('Sleep Stage Distribution per Condition', ...
      'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

% Legend
leg = legend(b, condition_labels, 'Location', 'northwest', ...
       'FontName', pub.font_name, 'FontSize', pub.font_size_axis, 'Box', 'off');
% Adjust legend position to be closer to the top-left corner
leg.Position(1) = leg.Position(1) - 0.02;  % Move slightly left
leg.Position(2) = leg.Position(2) + 0.03;  % Move slightly up

ylim([0, min(100, max(stage_means(:) + stage_sems(:)) * 1.15)]);
grid on;
grid minor;

hold off;

%% Save figure
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

% Save as PNG, SVG, and FIG
filename_base = 'figure1_sleepStages';
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

% Save data
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'stage_means', 'stage_sems', 'stage_data_percent', 'stage_data', 'conditions', 'sleep_stages', ...
     'subjects', 'pub');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);

%% ====================================================================
%  CONSOLE OUTPUT: Results Summary for Paper
%  ====================================================================

% --- Also extract Wake data from the source table ---
wake_data_min = nan(n_subj, n_cond);
for s = 1:n_subj
    for c = 1:n_cond
        mask = strcmp(all_condition_durations.Subject, subjects{s}) & ...
               strcmp(all_condition_durations.Condition, conditions{c}) & ...
               strcmp(all_condition_durations.SleepStage, 'Wake');
        val = sum(all_condition_durations.Duration_min(mask));
        if ~isempty(val)
            wake_data_min(s, c) = val;
        end
    end
end

% Total time per condition (sleep + wake)
total_time_per_cond = total_sleep + wake_data_min;  % subjects x conditions

% Compute SDs (for reporting M +/- SD, not SEM)
stage_sds = squeeze(std(stage_data_percent, 0, 1));  % conditions x stages

fprintf('\n');
fprintf('====================================================================\n');
fprintf('  RESULTS: Sleep Stage Proportions & Architecture\n');
fprintf('  Script: figure1_sleepStagesBarplot.m\n');
fprintf('  N = %d subjects\n', n_subj);
fprintf('====================================================================\n');

% --- Overall sleep architecture (collapsed across conditions) ---
% Average each subject's percentages across conditions first, then M +/- SD
subj_avg_percent = squeeze(mean(stage_data_percent, 2));  % subjects x stages
overall_M  = mean(subj_avg_percent, 1);
overall_SD = std(subj_avg_percent, 0, 1);

fprintf('\n--- Overall Sleep Architecture (collapsed across conditions) ---\n');
fprintf('  %-6s  %8s  %8s\n', 'Stage', 'M (%)', 'SD (%)');
fprintf('  %-6s  %8s  %8s\n', '------', '--------', '--------');
for st = 1:n_stages
    fprintf('  %-6s  %8.1f  %8.1f\n', sleep_stages{st}, overall_M(st), overall_SD(st));
end

% --- Per-condition sleep stage proportions ---
fprintf('\n--- Sleep Stage Proportions per Condition (M +/- SD %%) ---\n');
fprintf('  %-6s', 'Stage');
for c = 1:n_cond
    fprintf('  %16s', condition_labels{c});
end
fprintf('\n');
fprintf('  %-6s', '------');
for c = 1:n_cond
    fprintf('  %16s', '----------------');
end
fprintf('\n');
for st = 1:n_stages
    fprintf('  %-6s', sleep_stages{st});
    for c = 1:n_cond
        fprintf('  %6.1f +/- %5.1f', stage_means(c, st), stage_sds(c, st));
    end
    fprintf('\n');
end

% --- Total sleep time per condition ---
fprintf('\n--- Total Sleep Time per Condition (minutes) ---\n');
fprintf('  %-8s  %8s  %8s\n', 'Cond', 'M', 'SD');
fprintf('  %-8s  %8s  %8s\n', '--------', '--------', '--------');
for c = 1:n_cond
    fprintf('  %-8s  %8.2f  %8.2f\n', condition_labels{c}, ...
        mean(total_sleep(:, c)), std(total_sleep(:, c)));
end
fprintf('  %-8s  %8.2f  %8.2f\n', 'Overall', ...
    mean(total_sleep(:)), std(total_sleep(:)));

% --- Wake / sleep disruption ---
fprintf('\n--- Wake Time per Condition (minutes) ---\n');
fprintf('  %-8s  %8s  %8s\n', 'Cond', 'M', 'SD');
fprintf('  %-8s  %8s  %8s\n', '--------', '--------', '--------');
has_wake = any(~isnan(wake_data_min(:)));
if has_wake
    for c = 1:n_cond
        fprintf('  %-8s  %8.2f  %8.2f\n', condition_labels{c}, ...
            mean(wake_data_min(:, c), 'omitnan'), std(wake_data_min(:, c), 0, 'omitnan'));
    end
    fprintf('  %-8s  %8.2f  %8.2f\n', 'Overall', ...
        mean(wake_data_min(:), 'omitnan'), std(wake_data_min(:), 0, 'omitnan'));

    % Wake as percentage of total time
    wake_pct = (wake_data_min ./ total_time_per_cond) * 100;
    fprintf('\n--- Wake as %% of Total Scored Time ---\n');
    fprintf('  %-8s  %8s  %8s\n', 'Cond', 'M (%)', 'SD (%)');
    fprintf('  %-8s  %8s  %8s\n', '--------', '--------', '--------');
    for c = 1:n_cond
        fprintf('  %-8s  %8.1f  %8.1f\n', condition_labels{c}, ...
            mean(wake_pct(:, c), 'omitnan'), std(wake_pct(:, c), 0, 'omitnan'));
    end
    fprintf('  %-8s  %8.1f  %8.1f\n', 'Overall', ...
        mean(wake_pct(:), 'omitnan'), std(wake_pct(:), 0, 'omitnan'));
else
    fprintf('  (No Wake epochs found in data)\n');
end

% --- Total scored time (sleep + wake) ---
fprintf('\n--- Total Scored Time per Condition (sleep + wake, minutes) ---\n');
fprintf('  %-8s  %8s  %8s\n', 'Cond', 'M', 'SD');
fprintf('  %-8s  %8s  %8s\n', '--------', '--------', '--------');
if has_wake
    for c = 1:n_cond
        fprintf('  %-8s  %8.2f  %8.2f\n', condition_labels{c}, ...
            mean(total_time_per_cond(:, c), 'omitnan'), std(total_time_per_cond(:, c), 0, 'omitnan'));
    end
    fprintf('  %-8s  %8.2f  %8.2f\n', 'Overall', ...
        mean(total_time_per_cond(:), 'omitnan'), std(total_time_per_cond(:), 0, 'omitnan'));
else
    fprintf('  (Same as Total Sleep Time -- no Wake data available)\n');
end

%% ====================================================================
%  STATISTICAL TEST: Repeated-Measures ANOVA per Sleep Stage
%  ====================================================================
fprintf('\n--- Repeated-Measures ANOVA: Stage %% across Conditions ---\n');
fprintf('  Testing whether sleep stage proportions differ across conditions.\n\n');

within = table(categorical(condition_labels'), 'VariableNames', {'Condition'});

fprintf('  %-6s  %10s  %10s  %10s\n', 'Stage', 'F', 'df', 'p');
fprintf('  %-6s  %10s  %10s  %10s\n', '------', '----------', '----------', '----------');

for st = 1:n_stages
    data_st = stage_data_percent(:, :, st);  % subjects x conditions
    T_rm = array2table(data_st, 'VariableNames', {'Cond_5Hz', 'Cond_1Hz', 'Cond_Off'});
    rm = fitrm(T_rm, 'Cond_5Hz-Cond_Off ~ 1', 'WithinDesign', within);
    ranova_tbl = ranova(rm);

    F_val = ranova_tbl.F(1);
    df1 = ranova_tbl.DF(1);
    df2 = ranova_tbl.DF(2);
    p_val = ranova_tbl.pValue(1);

    if p_val < 0.001
        p_str = '< .001';
    else
        p_str = sprintf('%.3f', p_val);
    end
    fprintf('  %-6s  %10.2f  %5d, %-4d  %8s\n', sleep_stages{st}, F_val, df1, df2, p_str);
end

%% ====================================================================
%  AROUSAL ANALYSIS: Wake Epochs Within Sleep Period per Condition
%  ====================================================================
fprintf('\n====================================================================\n');
fprintf('  AROUSAL ANALYSIS: Wake Epochs Within Sleep Period per Condition\n');
fprintf('  N = %d subjects\n', n_subj);
fprintf('====================================================================\n');
fprintf('  Sleep period = first N2 epoch to last N2/N3 epoch per condition.\n');
fprintf('  Arousal count = number of wake-scored epochs within that window.\n');

arousal_counts = nan(n_subj, n_cond);
sleep_period_epochs = nan(n_subj, n_cond);

for s = 1:n_subj
    subject = subjects{s};

    % Get this subject's hypnogram
    subj_mask = strcmp(all_sleep_stages.Subject, subject);
    subj_hyp = all_sleep_stages(subj_mask, :);
    subj_hyp = sortrows(subj_hyp, 'Timestamp');
    epoch_sec = seconds(subj_hyp.Timestamp - subj_hyp.Timestamp(1));

    for c = 1:n_cond
        condition = conditions{c};
        cond_mask = strcmp(all_condition_durations.Subject, subject) & ...
                    strcmp(all_condition_durations.Condition, condition);
        cond_rows = all_condition_durations(cond_mask, :);

        % Collect all time intervals for this condition (across all stages)
        all_intervals = [];
        for r = 1:height(cond_rows)
            iv = cond_rows.TimeIntervals{r};
            if ~isempty(iv)
                all_intervals = [all_intervals; iv(:, 1:2)]; %#ok<AGROW>
            end
        end

        if isempty(all_intervals)
            arousal_counts(s, c) = 0;
            sleep_period_epochs(s, c) = 0;
            continue;
        end

        % Time span of this condition (earliest trial to latest trial)
        cond_start = min(all_intervals(:, 1));
        cond_end   = max(all_intervals(:, 2));

        % Epochs within this condition's time span
        in_span = epoch_sec >= cond_start & epoch_sec < cond_end;
        span_stages = subj_hyp.Stage(in_span);

        % Find first N2 and last N2/N3 within span
        first_n2  = find(strcmp(span_stages, 'N2'), 1, 'first');
        last_n2n3 = find(strcmp(span_stages, 'N2') | strcmp(span_stages, 'N3'), 1, 'last');

        if isempty(first_n2) || isempty(last_n2n3) || first_n2 >= last_n2n3
            arousal_counts(s, c) = 0;
            sleep_period_epochs(s, c) = 0;
            continue;
        end

        % Count wake epochs between first N2 and last N2/N3
        between_stages = span_stages(first_n2:last_n2n3);
        arousal_counts(s, c) = sum(strcmp(between_stages, 'Wake'));
        sleep_period_epochs(s, c) = length(between_stages);
    end
end

% --- Descriptives: wake epoch counts ---
fprintf('\n--- Wake Epoch Count Within Sleep Period per Condition ---\n');
fprintf('  %-8s  %10s  %10s  %10s\n', 'Cond', 'M', 'SD', 'Median');
fprintf('  %-8s  %10s  %10s  %10s\n', '--------', '----------', '----------', '----------');
for c = 1:n_cond
    fprintf('  %-8s  %10.2f  %10.2f  %10.1f\n', condition_labels{c}, ...
        mean(arousal_counts(:, c), 'omitnan'), ...
        std(arousal_counts(:, c), 0, 'omitnan'), ...
        median(arousal_counts(:, c), 'omitnan'));
end

% --- Descriptives: wake as % of sleep period ---
arousal_pct = (arousal_counts ./ sleep_period_epochs) * 100;
fprintf('\n--- Wake as %% of Sleep Period Epochs ---\n');
fprintf('  %-8s  %10s  %10s\n', 'Cond', 'M (%)', 'SD (%)');
fprintf('  %-8s  %10s  %10s\n', '--------', '----------', '----------');
for c = 1:n_cond
    fprintf('  %-8s  %10.1f  %10.1f\n', condition_labels{c}, ...
        mean(arousal_pct(:, c), 'omitnan'), std(arousal_pct(:, c), 0, 'omitnan'));
end

% --- Repeated-measures ANOVA on arousal counts ---
T_arousal = array2table(arousal_counts, 'VariableNames', {'Cond_5Hz', 'Cond_1Hz', 'Cond_Off'});
rm_arousal = fitrm(T_arousal, 'Cond_5Hz-Cond_Off ~ 1', 'WithinDesign', within);
ranova_arousal = ranova(rm_arousal);

F_a = ranova_arousal.F(1);
df1_a = ranova_arousal.DF(1);
df2_a = ranova_arousal.DF(2);
p_a = ranova_arousal.pValue(1);

if p_a < 0.001
    p_a_str = '< .001';
else
    p_a_str = sprintf('%.3f', p_a);
end

fprintf('\n  rmANOVA on wake epoch count: F(%d,%d) = %.2f, p = %s\n', df1_a, df2_a, F_a, p_a_str);

% Post-hoc pairwise comparisons (only if significant)
if p_a < 0.05
    mc = multcompare(rm_arousal, 'Condition');
    fprintf('\n--- Post-hoc Pairwise Comparisons ---\n');
    for r = 1:height(mc)
        fprintf('  %s vs %s: diff = %.2f, p = %.3f\n', ...
            string(mc.Condition_1(r)), string(mc.Condition_2(r)), ...
            mc.Difference(r), mc.pValue(r));
    end
else
    fprintf('  No significant difference; post-hoc tests not performed.\n');
end

%% ====================================================================
%  FULL ANOVA TABLES (Supplementary Report)
%  ====================================================================
%  Writes complete repeated-measures ANOVA tables to a text file for the
%  supplementary materials. Each table includes:
%    - SS / df / MS for the Condition effect AND the residual (error) row
%    - F, uncorrected p, Greenhouse-Geisser-corrected p, Huynh-Feldt-corrected p
%    - Partial eta-squared (effect size)
%    - Mauchly's test of sphericity (W, ChiStat, df, p)
%    - Sphericity epsilon estimates (GG, HF, lower-bound)

supp_file = fullfile(OUTPUT_DIR, 'figure1_anova_supplementary.txt');
fid_supp = fopen(supp_file, 'w');
if fid_supp == -1
    warning('Could not open supplementary report file: %s', supp_file);
    fids = 1;
else
    fids = [1, fid_supp];
end

tee(fids, sprintf('\n\n====================================================================\n'));
tee(fids, sprintf('  FULL ANOVA TABLES -- Supplementary Report\n'));
tee(fids, sprintf('  Source: figure1_sleepStagesBarplot.m\n'));
tee(fids, sprintf('  N = %d subjects | Within factor: Condition (5 Hz / 1 Hz / Off)\n', n_subj));
tee(fids, sprintf('  Generated: %s\n', char(datetime('now'))));
tee(fids, sprintf('====================================================================\n'));

% --- (1) Sleep stage proportions: one full table per stage ---
tee(fids, sprintf('\n\n### 1. Sleep Stage Proportions Across Conditions ###\n'));
tee(fids, sprintf('   DV: Stage proportion (%% of total sleep time)\n'));

for st = 1:n_stages
    data_st = stage_data_percent(:, :, st);
    T_rm = array2table(data_st, 'VariableNames', {'Cond_5Hz', 'Cond_1Hz', 'Cond_Off'});
    rm_st = fitrm(T_rm, 'Cond_5Hz-Cond_Off ~ 1', 'WithinDesign', within);
    print_full_anova_table(rm_st, sprintf('Stage %s (%%)', sleep_stages{st}), fids);
end

% --- (2) Arousal counts ---
tee(fids, sprintf('\n\n### 2. Arousal Count Within Sleep Period Across Conditions ###\n'));
tee(fids, sprintf('   DV: Number of wake epochs between first N2 and last N2/N3\n'));
print_full_anova_table(rm_arousal, 'Arousal count', fids);

if fid_supp ~= -1
    fclose(fid_supp);
    fprintf('\nFull ANOVA tables saved to: %s\n', supp_file);
end

fprintf('\n====================================================================\n');
fprintf('=== Done ===\n');

end

% --------------------------------------------------------------------
function tee(fids, msg)
% Write the same message to multiple file handles (e.g. stdout + file).
for f = fids
    fprintf(f, '%s', msg);
end
end

% --------------------------------------------------------------------
function print_full_anova_table(rm, label, fids)
% Print a complete repeated-measures ANOVA table to all handles in fids.
%
% Includes the full SS decomposition (effect + residual + total),
% F, uncorrected and sphericity-corrected p-values, partial eta-squared,
% Mauchly's test of sphericity, and epsilon estimates.

ranova_tbl = ranova(rm);

% Mauchly's test (may fail if too few subjects relative to levels)
have_mauchly = false;
mauchly_tbl = [];
try
    mauchly_tbl = mauchly(rm);
    have_mauchly = true;
catch
end

% Epsilon estimates
have_eps = false;
eps_tbl = [];
try
    eps_tbl = epsilon(rm);
    have_eps = true;
catch
end

% Extract effect and error rows
SS_effect = ranova_tbl.SumSq(1);
SS_error  = ranova_tbl.SumSq(2);
df_effect = ranova_tbl.DF(1);
df_error  = ranova_tbl.DF(2);
MS_effect = ranova_tbl.MeanSq(1);
MS_error  = ranova_tbl.MeanSq(2);
F_val     = ranova_tbl.F(1);
p_val     = ranova_tbl.pValue(1);
p_GG      = ranova_tbl.pValueGG(1);
p_HF      = ranova_tbl.pValueHF(1);

% Effect size: partial eta-squared
eta_p2 = SS_effect / (SS_effect + SS_error);

tee(fids, sprintf('\n----- %s -----\n', label));

tee(fids, sprintf('\n  %-20s  %12s  %6s  %12s  %10s  %10s  %10s  %10s\n', ...
    'Source', 'SS', 'df', 'MS', 'F', 'p', 'p (GG)', 'p (HF)'));
tee(fids, sprintf('  %s\n', repmat('-', 1, 104)));
tee(fids, sprintf('  %-20s  %12.4f  %6d  %12.4f  %10.4f  %10.4f  %10.4f  %10.4f\n', ...
    'Condition',         SS_effect, df_effect, MS_effect, F_val, p_val, p_GG, p_HF));
tee(fids, sprintf('  %-20s  %12.4f  %6d  %12.4f\n', ...
    'Error (residual)',  SS_error, df_error, MS_error));
tee(fids, sprintf('  %-20s  %12.4f  %6d\n', ...
    'Total',             SS_effect + SS_error, df_effect + df_error));

tee(fids, sprintf('\n  Effect size: partial eta-squared = %.4f\n', eta_p2));

if have_mauchly
    tee(fids, sprintf('\n  Mauchly''s Test of Sphericity:\n'));
    tee(fids, sprintf('    W = %.4f, ChiStat = %.4f, df = %d, p = %.4f\n', ...
        mauchly_tbl.W(1), mauchly_tbl.ChiStat(1), mauchly_tbl.DF(1), mauchly_tbl.pValue(1)));
    if mauchly_tbl.pValue(1) < 0.05
        tee(fids, sprintf('    -> Sphericity violated; report GG-corrected p-value.\n'));
    else
        tee(fids, sprintf('    -> Sphericity assumption met.\n'));
    end
else
    tee(fids, sprintf('\n  Mauchly''s test not available for this design.\n'));
end

if have_eps
    tee(fids, sprintf('\n  Sphericity Epsilon Estimates:\n'));
    eps_names = eps_tbl.Properties.VariableNames;
    for k = 1:numel(eps_names)
        tee(fids, sprintf('    %-22s = %.4f\n', eps_names{k}, eps_tbl{1, k}));
    end
end

end
