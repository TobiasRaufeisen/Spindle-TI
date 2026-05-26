function figure3_metricsBarplot()
%% FIGURE 3: Spindle Metrics Barplot (Combined)
% 4 subplots: Duration, Amplitude, Frequency, Density
% Duration/Amplitude/Frequency: LME on electrode-level data with post-hoc contrasts
% Density: LME on electrode-level data with post-hoc contrasts

clear; clc;

% ====================================================================
%  CONFIGURATION
%  ====================================================================

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
roi_electrodes = {};  % Empty = all electrodes; or specify e.g. {'CZ', 'C3', 'C4'}

% Spindle filtering criteria
freq_range = [12, 16];
dur_range = [0.5, 3.0];
amp_range = [15, 100];

% Statistical parameters
alpha = 0.05;

% Colors
colors = [
    1.0, 0.55, 0.0;  % Orange for x5HZ
    0.0, 0.2, 0.6;   % Dark blue for x1HZ
    0.6, 0.6, 0.6    % Gray for OFF
];

% Publication settings
pub = struct();
pub.fig_width_cm = 12;
pub.fig_height_cm = 10;
pub.font_name = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;
pub.bar_width = 0.6;

fprintf('=== FIGURE 3: Spindle Metrics Barplot (Combined) ===\n');

% ====================================================================
%  1. LOAD & FILTER DATA
%  ====================================================================

fprintf('\nLoading data...\n');
loaded = load(DATA_FILE, 'all_spindles', 'all_condition_durations');
spindles = loaded.all_spindles;
durations = loaded.all_condition_durations;
fprintf('Loaded %d spindles\n', height(spindles));

% Extract primary channels
spindles.PrimaryChannel = cellfun(@(x) extract_primary_channel(x), ...
    spindles.Channel, 'UniformOutput', false);

% Apply filters
spindles = spindles(ismember(spindles.SleepStage, sleep_stages), :);
spindles = spindles(ismember(spindles.Condition, conditions), :);
if ~isempty(roi_electrodes)
    spindles = spindles(ismember(spindles.PrimaryChannel, roi_electrodes), :);
    fprintf('After electrode filter (%s): %d spindles\n', strjoin(roi_electrodes, ', '), height(spindles));
end
spindles = spindles(spindles.Frequency >= freq_range(1) & ...
                   spindles.Frequency <= freq_range(2), :);
spindles = spindles(spindles.Duration >= dur_range(1) & ...
                   spindles.Duration <= dur_range(2), :);
spindles = spindles(spindles.Amplitude >= amp_range(1) & ...
                   spindles.Amplitude <= amp_range(2), :);
fprintf('Filtered spindles: %d\n', height(spindles));

% ====================================================================
%  2. COMPUTE ELECTRODE-LEVEL MEANS (Duration, Amplitude, Frequency)
%  ====================================================================

fprintf('\nComputing electrode-level means...\n');

subjects = unique(spindles.Subject);
n_subj = length(subjects);
n_cond = length(conditions);

electrodes_all = unique(spindles.PrimaryChannel);
n_elec_all = length(electrodes_all);

metrics_simple = {'Duration', 'Amplitude', 'Frequency'};
n_metrics_simple = length(metrics_simple);

% Build electrode-level tables for each metric
T_metrics = struct();
subject_means = struct();

for m = 1:n_metrics_simple
    metric = metrics_simple{m};
    max_rows = n_subj * n_cond * n_elec_all;
    subj_arr = cell(max_rows, 1);
    cond_arr = cell(max_rows, 1);
    elec_arr = cell(max_rows, 1);
    val_arr = nan(max_rows, 1);
    row = 0;

    for s = 1:n_subj
        subj = subjects{s};
        for c = 1:n_cond
            cond = conditions{c};
            for e = 1:n_elec_all
                elec = electrodes_all{e};
                mask = strcmp(spindles.Subject, subj) & ...
                       strcmp(spindles.Condition, cond) & ...
                       strcmp(spindles.PrimaryChannel, elec);
                if sum(mask) > 0
                    row = row + 1;
                    subj_arr{row} = subj;
                    cond_arr{row} = cond;
                    elec_arr{row} = elec;
                    val_arr(row) = mean(spindles.(metric)(mask), 'omitnan');
                end
            end
        end
    end

    T = table(subj_arr(1:row), cond_arr(1:row), elec_arr(1:row), val_arr(1:row), ...
        'VariableNames', {'Subject', 'Condition', 'Electrode', 'Value'});
    T.Subject = categorical(T.Subject);
    T.Condition = categorical(T.Condition);
    T.Electrode = categorical(T.Electrode);
    T_metrics.(metric) = T;
    fprintf('  %s: %d electrode-level observations\n', metric, height(T));

    % Aggregate to subject level for plotting
    subj_summary = groupsummary(T, {'Subject', 'Condition'}, 'mean', 'Value');
    metric_subjects = categories(T.Subject);
    n_subj_metric = length(metric_subjects);
    mat = nan(n_subj_metric, n_cond);
    for si = 1:n_subj_metric
        for ci = 1:n_cond
            smask = subj_summary.Subject == metric_subjects{si} & ...
                    subj_summary.Condition == conditions{ci};
            if any(smask)
                mat(si, ci) = subj_summary.mean_Value(smask);
            end
        end
    end
    subject_means.(metric) = mat;
end

fprintf('Computed electrode-level data for %d subjects across %d electrodes\n', n_subj, n_elec_all);

% ====================================================================
%  3. COMPUTE DENSITY (electrode-level)
%  ====================================================================

fprintf('\nComputing spindle density...\n');

electrodes = unique(spindles.PrimaryChannel);
n_elec = length(electrodes);

% Build electrode-level table for LME
max_rows = n_subj * n_cond * n_elec;
subj_arr = cell(max_rows, 1);
cond_arr = cell(max_rows, 1);
elec_arr = cell(max_rows, 1);
dens_arr = nan(max_rows, 1);
row = 0;
for s = 1:n_subj
    subj = subjects{s};
    for c = 1:n_cond
        cond = conditions{c};
        dur_mask = strcmp(durations.Subject, subj) & strcmp(durations.Condition, cond) & ...
                   ismember(durations.SleepStage, sleep_stages);
        if ~any(dur_mask), continue; end
        total_min = sum(durations.Duration_min(dur_mask));
        if total_min <= 0, continue; end

        for e = 1:n_elec
            elec = electrodes{e};
            sp_mask = strcmp(spindles.Subject, subj) & strcmp(spindles.Condition, cond) & ...
                      strcmp(spindles.PrimaryChannel, elec);
            n_spindles = sum(sp_mask);
            density = n_spindles / total_min;

            row = row + 1;
            subj_arr{row} = subj;
            cond_arr{row} = cond;
            elec_arr{row} = elec;
            dens_arr(row) = density;
        end
    end
end

T_density = table(subj_arr(1:row), cond_arr(1:row), elec_arr(1:row), dens_arr(1:row), ...
    'VariableNames', {'Subject', 'Condition', 'Electrode', 'Density'});
T_density.Subject = categorical(T_density.Subject);
T_density.Condition = categorical(T_density.Condition);
T_density.Electrode = categorical(T_density.Electrode);
fprintf('Electrode-level observations: %d\n', height(T_density));

% Keep only complete subjects
subj_cond_counts = groupcounts(T_density, 'Subject');
complete_subj = subj_cond_counts.Subject(subj_cond_counts.GroupCount == n_cond * n_elec);
T_density = T_density(ismember(T_density.Subject, complete_subj), :);
T_density.Subject = removecats(T_density.Subject);
fprintf('Complete subjects: %d\n', length(categories(T_density.Subject)));

% Aggregate to subject level for plotting
subj_density = groupsummary(T_density, {'Subject', 'Condition'}, 'mean', 'Density');
density_subjects = categories(T_density.Subject);
n_subj_density = length(density_subjects);

density_matrix = nan(n_subj_density, n_cond);
for s = 1:n_subj_density
    for c = 1:n_cond
        mask = subj_density.Subject == density_subjects{s} & subj_density.Condition == conditions{c};
        if any(mask)
            density_matrix(s, c) = subj_density.mean_Density(mask);
        end
    end
end

% ====================================================================
%  4. STATISTICS -- Duration, Amplitude, Frequency (electrode-level LME)
%  ====================================================================

fprintf('\n--- Statistics: Duration, Amplitude, Frequency ---\n');

stats_results = struct();
%metric_model_formula = 'Value ~ 1 + Condition + (1 + Condition | Subject) + (1 | Subject:Electrode)';
metric_model_formula = 'Value ~1 + Condition + (Condition | Subject) + (1 | Electrode)';
for m = 1:n_metrics_simple
    metric = metrics_simple{m};
    T = T_metrics.(metric);
    fprintf('\n  %s (%d observations):\n', metric, height(T));
    fprintf('  Formula: %s\n', metric_model_formula);

    % Fit LME
    lme = fitlme(T, metric_model_formula);
    lme_anova = anova(lme);

    fprintf('  AIC: %.2f, BIC: %.2f\n', lme.ModelCriterion.AIC, lme.ModelCriterion.BIC);
    fprintf('  Main effect (Condition): F(%d,%.1f) = %.3f, p = %.4f', ...
        lme_anova.DF1(2), lme_anova.DF2(2), ...
        lme_anova.FStat(2), lme_anova.pValue(2));
    if lme_anova.pValue(2) < alpha
        fprintf(' *\n');
    else
        fprintf(' (n.s.)\n');
    end

    % R-squared (Nakagawa & Schielzeth)
    fitted_full = fitted(lme);
    var_resid = var(lme.residuals);
    R2_cond = var(fitted_full) / (var(fitted_full) + var_resid);
    X = designMatrix(lme, 'Fixed');
    beta = fixedEffects(lme);
    R2_marg = var(X * beta) / (var(X * beta) + var_resid);
    fprintf('  R2 marginal: %.4f, R2 conditional: %.4f\n', R2_marg, R2_cond);

    % Fixed effects
    fe = fixedEffects(lme);
    [~, ~, fe_stats] = fixedEffects(lme);
    fprintf('\n  Fixed Effects:\n');
    fprintf('  %-20s %10s %10s %10s %10s\n', 'Name', 'Estimate', 'SE', 'tStat', 'pValue');
    fprintf('  %s\n', repmat('-', 1, 65));
    for i = 1:height(fe_stats)
        fprintf('  %-20s %10.4f %10.4f %10.3f %10.4f\n', ...
            fe_stats.Name{i}, fe_stats.Estimate(i), fe_stats.SE(i), ...
            fe_stats.tStat(i), fe_stats.pValue(i));
    end

    % Post-hoc contrasts (Holm-Bonferroni)
    fprintf('\n  Post-hoc Contrasts (Holm-Bonferroni corrected):\n');
    cond_cats = categories(T.Condition);
    n_comp = n_cond * (n_cond - 1) / 2;
    posthoc_m = struct('pairs', cell(1, n_comp), 'cond1', cell(1, n_comp), ...
        'cond2', cell(1, n_comp), 'estimate', cell(1, n_comp), ...
        'se', cell(1, n_comp), 'df', cell(1, n_comp), ...
        't', cell(1, n_comp), 'p_uncorr', cell(1, n_comp), ...
        'p_holm', cell(1, n_comp), 'd', cell(1, n_comp));

    comp_idx = 0;
    for i = 1:n_cond-1
        for j = i+1:n_cond
            comp_idx = comp_idx + 1;
            posthoc_m(comp_idx).pairs = [i, j];
            posthoc_m(comp_idx).cond1 = conditions{i};
            posthoc_m(comp_idx).cond2 = conditions{j};

            H = zeros(1, length(fe));
            idx_i = find(strcmp(cond_cats, conditions{i}));
            idx_j = find(strcmp(cond_cats, conditions{j}));

            if idx_i == 1
                H(idx_j) = -1;
            elseif idx_j == 1
                H(idx_i) = 1;
            else
                H(idx_i) = 1;
                H(idx_j) = -1;
            end

            [p_val, F_val, ~, df2] = coefTest(lme, H);
            t_val = sign(H * fe) * sqrt(F_val);
            estimate = H * fe;
            cov_mat = lme.CoefficientCovariance;
            se_val = sqrt(H * cov_mat * H');

            posthoc_m(comp_idx).estimate = estimate;
            posthoc_m(comp_idx).se = se_val;
            posthoc_m(comp_idx).df = df2;
            posthoc_m(comp_idx).t = t_val;
            posthoc_m(comp_idx).p_uncorr = p_val;
            posthoc_m(comp_idx).d = estimate / std(T.Value);
        end
    end

    % Holm-Bonferroni correction
    p_uncorr_arr = [posthoc_m.p_uncorr];
    [p_sorted, sort_idx] = sort(p_uncorr_arr);
    p_holm_arr = zeros(1, n_comp);
    for k = 1:n_comp
        p_holm_arr(sort_idx(k)) = min(1, p_sorted(k) * (n_comp - k + 1));
    end
    for k = 2:n_comp
        if p_holm_arr(sort_idx(k)) < p_holm_arr(sort_idx(k-1))
            p_holm_arr(sort_idx(k)) = p_holm_arr(sort_idx(k-1));
        end
    end
    for k = 1:n_comp
        posthoc_m(k).p_holm = p_holm_arr(k);
    end

    fprintf('  %-15s %10s %10s %10s %12s %10s\n', ...
        'Comparison', 'Estimate', 't', 'p(uncorr)', 'p(Holm)', 'Cohen''s d');
    fprintf('  %s\n', repmat('-', 1, 75));
    for k = 1:n_comp
        sig_str = '';
        if posthoc_m(k).p_holm < 0.001, sig_str = '***';
        elseif posthoc_m(k).p_holm < 0.01, sig_str = '**';
        elseif posthoc_m(k).p_holm < 0.05, sig_str = '*';
        end
        fprintf('  %-15s %10.4f %10.3f %12.4f %12.4f %10.3f %s\n', ...
            sprintf('%s vs %s', posthoc_m(k).cond1, posthoc_m(k).cond2), ...
            posthoc_m(k).estimate, posthoc_m(k).t, ...
            posthoc_m(k).p_uncorr, posthoc_m(k).p_holm, posthoc_m(k).d, sig_str);
    end

    % Descriptive statistics for this metric (subject-level)
    metric_mat = subject_means.(metric);
    n_subj_m = size(metric_mat, 1);
    metric_means_m = mean(metric_mat, 1, 'omitnan');
    metric_sds_m = std(metric_mat, 0, 1, 'omitnan');
    metric_sems_m = metric_sds_m ./ sqrt(sum(~isnan(metric_mat), 1));
    metric_medians_m = median(metric_mat, 1, 'omitnan');
    metric_mins_m = min(metric_mat, [], 1, 'omitnan');
    metric_maxs_m = max(metric_mat, [], 1, 'omitnan');

    fprintf('\n  Descriptive Statistics (subject-level, N = %d):\n', n_subj_m);
    fprintf('  %-10s %8s %8s %8s %8s %8s %8s\n', 'Condition', 'Mean', 'SD', 'SEM', 'Median', 'Min', 'Max');
    fprintf('  %s\n', repmat('-', 1, 62));
    for c = 1:n_cond
        fprintf('  %-10s %8.3f %8.3f %8.3f %8.3f %8.3f %8.3f\n', ...
            conditions{c}, metric_means_m(c), metric_sds_m(c), metric_sems_m(c), ...
            metric_medians_m(c), metric_mins_m(c), metric_maxs_m(c));
    end

    % Store results
    stats_results.(metric).lme = lme;
    stats_results.(metric).anova = lme_anova;
    stats_results.(metric).means = metric_means_m;
    stats_results.(metric).sems = metric_sems_m;
    stats_results.(metric).sds = metric_sds_m;
    stats_results.(metric).posthoc = posthoc_m;
    stats_results.(metric).R2_marginal = R2_marg;
    stats_results.(metric).R2_conditional = R2_cond;
    stats_results.(metric).fe_stats = fe_stats;
    stats_results.(metric).model_formula = metric_model_formula;
end

% ====================================================================
%  5. STATISTICS -- Density (electrode-level LME with post-hoc)
%  ====================================================================

fprintf('\n--- Statistics: Density ---\n');

%model_formula = 'Density ~ 1 + Condition + (1 + Condition | Subject) + (1 | Subject:Electrode)';
model_formula = 'Density ~ 1 + Condition + (Condition | Subject) + (1 | Electrode)';

fprintf('  Formula: %s\n', model_formula);

lme_density = fitlme(T_density, model_formula);
lme_density_anova = anova(lme_density);

fprintf('  Observations: %d\n', lme_density.NumObservations);
fprintf('  AIC: %.2f, BIC: %.2f\n', lme_density.ModelCriterion.AIC, lme_density.ModelCriterion.BIC);
fprintf('  Main effect (Condition): F(%d,%.1f) = %.3f, p = %.4f\n', ...
    lme_density_anova.DF1(2), lme_density_anova.DF2(2), ...
    lme_density_anova.FStat(2), lme_density_anova.pValue(2));

% R^2 (Nakagawa & Schielzeth)
fitted_full = fitted(lme_density);
var_resid = var(lme_density.residuals);
R2_conditional = var(fitted_full) / (var(fitted_full) + var_resid);
X = designMatrix(lme_density, 'Fixed');
beta = fixedEffects(lme_density);
R2_marginal = var(X * beta) / (var(X * beta) + var_resid);
fprintf('  R^2 marginal: %.4f, R^2 conditional: %.4f\n', R2_marginal, R2_conditional);

% Fixed effects
fe = fixedEffects(lme_density);
[~, ~, fe_stats] = fixedEffects(lme_density);
fprintf('\n  Fixed Effects:\n');
fprintf('  %-20s %10s %10s %10s %10s\n', 'Name', 'Estimate', 'SE', 'tStat', 'pValue');
fprintf('  %s\n', repmat('-', 1, 65));
for i = 1:height(fe_stats)
    fprintf('  %-20s %10.4f %10.4f %10.3f %10.4f\n', ...
        fe_stats.Name{i}, fe_stats.Estimate(i), fe_stats.SE(i), ...
        fe_stats.tStat(i), fe_stats.pValue(i));
end

% Post-hoc contrasts (Holm-Bonferroni)
fprintf('\n  Post-hoc Contrasts (Holm-Bonferroni corrected):\n');
cond_cats = categories(T_density.Condition);
n_comp = n_cond * (n_cond - 1) / 2;
posthoc = struct('pairs', cell(1, n_comp), 'cond1', cell(1, n_comp), 'cond2', cell(1, n_comp), ...
    'estimate', cell(1, n_comp), 'se', cell(1, n_comp), 'df', cell(1, n_comp), ...
    't', cell(1, n_comp), 'p_uncorr', cell(1, n_comp), 'p_holm', cell(1, n_comp), 'd', cell(1, n_comp));

comp_idx = 0;
for i = 1:n_cond-1
    for j = i+1:n_cond
        comp_idx = comp_idx + 1;
        posthoc(comp_idx).pairs = [i, j];
        posthoc(comp_idx).cond1 = conditions{i};
        posthoc(comp_idx).cond2 = conditions{j};

        H = zeros(1, length(fe));
        idx_i = find(strcmp(cond_cats, conditions{i}));
        idx_j = find(strcmp(cond_cats, conditions{j}));

        if idx_i == 1
            H(idx_j) = -1;
        elseif idx_j == 1
            H(idx_i) = 1;
        else
            H(idx_i) = 1;
            H(idx_j) = -1;
        end

        [p_val, F_val, ~, df2] = coefTest(lme_density, H);
        t_val = sign(H * fe) * sqrt(F_val);
        estimate = H * fe;
        cov_mat = lme_density.CoefficientCovariance;
        se = sqrt(H * cov_mat * H');

        posthoc(comp_idx).estimate = estimate;
        posthoc(comp_idx).se = se;
        posthoc(comp_idx).df = df2;
        posthoc(comp_idx).t = t_val;
        posthoc(comp_idx).p_uncorr = p_val;
        posthoc(comp_idx).d = estimate / std(T_density.Density);
    end
end

% Holm-Bonferroni correction
p_uncorr = [posthoc.p_uncorr];
[p_sorted, sort_idx] = sort(p_uncorr);
p_holm = zeros(1, n_comp);
for k = 1:n_comp
    p_holm(sort_idx(k)) = min(1, p_sorted(k) * (n_comp - k + 1));
end
for k = 2:n_comp
    if p_holm(sort_idx(k)) < p_holm(sort_idx(k-1))
        p_holm(sort_idx(k)) = p_holm(sort_idx(k-1));
    end
end
for k = 1:n_comp
    posthoc(k).p_holm = p_holm(k);
end

fprintf('  %-15s %10s %10s %10s %12s %10s\n', ...
    'Comparison', 'Estimate', 't', 'p(uncorr)', 'p(Holm)', 'Cohen''s d');
fprintf('  %s\n', repmat('-', 1, 75));
for k = 1:n_comp
    sig_str = '';
    if posthoc(k).p_holm < 0.001, sig_str = '***';
    elseif posthoc(k).p_holm < 0.01, sig_str = '**';
    elseif posthoc(k).p_holm < 0.05, sig_str = '*';
    end
    fprintf('  %-15s %10.4f %10.3f %12.4f %12.4f %10.3f %s\n', ...
        sprintf('%s vs %s', posthoc(k).cond1, posthoc(k).cond2), ...
        posthoc(k).estimate, posthoc(k).t, ...
        posthoc(k).p_uncorr, posthoc(k).p_holm, posthoc(k).d, sig_str);
end

% Compute and display density descriptives
density_means = mean(density_matrix, 1, 'omitnan');
density_sds = std(density_matrix, 0, 1, 'omitnan');
density_sems = density_sds / sqrt(n_subj_density);
density_medians = median(density_matrix, 1, 'omitnan');
density_mins = min(density_matrix, [], 1, 'omitnan');
density_maxs = max(density_matrix, [], 1, 'omitnan');

fprintf('\n  Descriptive Statistics (subject-level, N = %d):\n', n_subj_density);
fprintf('  %-10s %8s %8s %8s %8s %8s %8s\n', 'Condition', 'Mean', 'SD', 'SEM', 'Median', 'Min', 'Max');
fprintf('  %s\n', repmat('-', 1, 62));
for c = 1:n_cond
    fprintf('  %-10s %8.3f %8.3f %8.3f %8.3f %8.3f %8.3f\n', ...
        conditions{c}, density_means(c), density_sds(c), density_sems(c), ...
        density_medians(c), density_mins(c), density_maxs(c));
end

% Store density stats
stats_results.Density.lme = lme_density;
stats_results.Density.anova = lme_density_anova;
stats_results.Density.means = density_means;
stats_results.Density.sems = density_sems;
stats_results.Density.sds = density_sds;
stats_results.Density.posthoc = posthoc;
stats_results.Density.R2_marginal = R2_marginal;
stats_results.Density.R2_conditional = R2_conditional;
stats_results.Density.fe_stats = fe_stats;
stats_results.Density.model_formula = model_formula;

% ====================================================================
%  6. SUPPLEMENTARY ANOVA TABLES (console)
%  ====================================================================

% Labels needed for output and plotting
if isempty(roi_electrodes)
    roi_label = 'All';
else
    roi_label = strjoin(roi_electrodes, ', ');
end
cond_labels = {'5 Hz', '1 Hz', 'Off'};
all_metrics = {'Duration', 'Amplitude', 'Frequency', 'Density'};
metric_ylabels = {'Duration (s)', 'Amplitude (\muV)', 'Frequency (Hz)', 'Density (spindles/min)'};
n_metrics = length(all_metrics);
filename_base = 'figure3_metricsBarplot';

% Full LME / ANOVA report to console
fprintf('\n========================================================================\n');
fprintf('  Full LME / ANOVA Report\n');
fprintf('========================================================================\n');
headlines = repmat(struct('metric','','F',NaN,'df1',NaN,'df2',NaN,'p',NaN,'sig',''), ...
    1, n_metrics);
for m = 1:n_metrics
    headlines(m) = write_lme_supplementary_report(1, ...
        stats_results.(all_metrics{m}).lme, all_metrics{m}, '');
end
local_print_summary_table(1, headlines);

% ====================================================================
%  7. PLOTTING -- Single figure with 4 subplots
%  ====================================================================

fprintf('\nCreating figure...\n');

if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end

% Data matrices for plotting
plot_data = cell(1, n_metrics);
for m = 1:n_metrics_simple
    plot_data{m} = subject_means.(metrics_simple{m});
end
plot_data{4} = density_matrix;

% Create figure
fig = figure('Units', 'centimeters', ...
    'Position', [2, 5, pub.fig_width_cm, pub.fig_height_cm], ...
    'Color', 'white', ...
    'PaperUnits', 'centimeters', ...
    'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
    'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

for m = 1:n_metrics
    subplot(2, 2, m);
    hold on;

    means = stats_results.(all_metrics{m}).means;
    sems = stats_results.(all_metrics{m}).sems;
    data = plot_data{m};

    % Bars
    for c = 1:n_cond
        bar(c, means(c), pub.bar_width, ...
            'FaceColor', colors(c,:), 'EdgeColor', 'none');
    end

    % Error bars
    errorbar(1:n_cond, means, sems, 'k.', 'LineWidth', 1.5, 'CapSize', 8);

    % Individual data points with connecting lines
    n_pts = size(data, 1);
    for s_idx = 1:n_pts
        subj_data = data(s_idx, :);
        valid = ~isnan(subj_data);
        if sum(valid) >= 2
            x_pos = find(valid);
            plot(x_pos, subj_data(valid), '-', ...
                'Color', [0.5, 0.5, 0.5, 0.3], 'LineWidth', 0.5);
        end
    end
    for c = 1:n_cond
        data_pts = data(:, c);
        valid = ~isnan(data_pts);
        scatter(ones(sum(valid), 1) * c, data_pts(valid), 15, colors(c,:), 'o', ...
            'MarkerEdgeColor', [0, 0, 0], ...
            'MarkerEdgeAlpha', 0.4, ...
            'MarkerFaceAlpha', 0.4, ...
            'LineWidth', 0.5);
    end

    % Significance brackets
    if isfield(stats_results.(all_metrics{m}), 'posthoc')
        ph = stats_results.(all_metrics{m}).posthoc;
        max_pt = max(data(:), [], 'omitnan');
        y_off = max_pt * 1.15;
        bracket_h = range([means(:); data(:)]) * 0.05;
        has_sig = false;
        for k = 1:length(ph)
            if ph(k).p_holm < alpha
                has_sig = true;
                c1 = ph(k).pairs(1); c2 = ph(k).pairs(2);
                plot([c1 c2], [y_off y_off], 'k-', 'LineWidth', 1.5);
                if ph(k).p_holm < 0.001
                    sig = '***';
                elseif ph(k).p_holm < 0.01
                    sig = '**';
                else
                    sig = '*';
                end
                text(mean([c1 c2]), y_off + bracket_h * 0.3, sig, ...
                    'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
                y_off = y_off + bracket_h * 2;
            end
        end
        if has_sig
            ylim([0, y_off + bracket_h]);
        end
    end

    hold off;

    set(gca, 'XTick', 1:n_cond, 'XTickLabel', cond_labels, ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
        'Box', 'off', 'TickDir', 'out');
    ylabel(metric_ylabels{m}, 'FontName', pub.font_name, ...
        'FontSize', pub.font_size_label, 'FontWeight', 'bold');

    ar = stats_results.(all_metrics{m}).anova;
    title(sprintf('p = %.3f', ar.pValue(2)), ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_title);

    grid on;
end

%% ====================================================================
%  8. SAVE
%  ====================================================================

fprintf('\nSaving...\n');

% --- Figure ---
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-vector');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

% --- Data ---
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
    'subject_means', 'density_matrix', 'T_density', 'T_metrics', 'stats_results', ...
    'subjects', 'conditions', 'roi_electrodes', 'pub', 'posthoc', '-v7.3');

% --- Stats text file ---
stats_file = fullfile(OUTPUT_DIR, [filename_base '_stats.txt']);
fid = fopen(stats_file, 'w');
fprintf(fid, 'FIGURE 3: Spindle Metrics Statistics\n');
fprintf(fid, 'Generated: %s\n', string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'ROI electrodes: %s\n', roi_label);
fprintf(fid, 'Sleep stage: %s\n', strjoin(sleep_stages, ', '));
fprintf(fid, 'Frequency range: [%.1f, %.1f] Hz\n', freq_range(1), freq_range(2));
fprintf(fid, 'Duration range: [%.2f, %.2f] s\n', dur_range(1), dur_range(2));
fprintf(fid, 'Amplitude range: [%.1f, %.1f] uV\n', amp_range(1), amp_range(2));
fprintf(fid, 'Number of subjects: %d\n', n_subj);
fprintf(fid, 'Alpha level: %.2f\n\n', alpha);

for m = 1:n_metrics_simple
    metric = metrics_simple{m};
    lme_m = stats_results.(metric).lme;
    ar = stats_results.(metric).anova;
    means_m = stats_results.(metric).means;
    sems_m = stats_results.(metric).sems;
    ph = stats_results.(metric).posthoc;

    fprintf(fid, '========================================\n');
    fprintf(fid, '%s\n', metric);
    fprintf(fid, '========================================\n');
    fprintf(fid, 'LME: %s\n\n', stats_results.(metric).model_formula);
    fprintf(fid, 'Observations: %d\n', lme_m.NumObservations);
    fprintf(fid, 'AIC: %.2f, BIC: %.2f\n', lme_m.ModelCriterion.AIC, lme_m.ModelCriterion.BIC);
    fprintf(fid, 'R2 marginal: %.4f, R2 conditional: %.4f\n\n', ...
        stats_results.(metric).R2_marginal, stats_results.(metric).R2_conditional);

    sds_m = stats_results.(metric).sds;
    fprintf(fid, 'Descriptive Statistics (subject-level, N = %d):\n', n_subj);
    fprintf(fid, '  %-10s  %10s  %10s  %10s  %10s  %10s\n', 'Condition', 'Mean', 'SD', 'SEM', 'Min', 'Max');
    fprintf(fid, '  %s\n', repmat('-', 1, 62));
    for c = 1:n_cond
        mat_m = subject_means.(metric);
        fprintf(fid, '  %-10s  %10.4f  %10.4f  %10.4f  %10.4f  %10.4f\n', ...
            cond_labels{c}, means_m(c), sds_m(c), sems_m(c), ...
            min(mat_m(:, c), [], 'omitnan'), max(mat_m(:, c), [], 'omitnan'));
    end

    fprintf(fid, '\nANOVA:\n');
    fprintf(fid, '  Condition: F(%d,%.1f) = %.3f, p = %.4f\n', ...
        ar.DF1(2), ar.DF2(2), ar.FStat(2), ar.pValue(2));

    fprintf(fid, '\nPost-hoc Contrasts (Holm-Bonferroni):\n');
    for k = 1:length(ph)
        sig_str = '';
        if ph(k).p_holm < 0.001, sig_str = '***';
        elseif ph(k).p_holm < 0.01, sig_str = '**';
        elseif ph(k).p_holm < 0.05, sig_str = '*';
        end
        fprintf(fid, '  %s vs %s: est=%.4f, t=%.3f, p_holm=%.4f, d=%.3f %s\n', ...
            ph(k).cond1, ph(k).cond2, ...
            ph(k).estimate, ph(k).t, ph(k).p_holm, ph(k).d, sig_str);
    end
    fprintf(fid, '\n');
end

fprintf(fid, '========================================\n');
fprintf(fid, 'Density\n');
fprintf(fid, '========================================\n');
fprintf(fid, 'LME: %s\n\n', stats_results.Density.model_formula);
fprintf(fid, 'Observations: %d\n', lme_density.NumObservations);
fprintf(fid, 'AIC: %.2f, BIC: %.2f\n', lme_density.ModelCriterion.AIC, lme_density.ModelCriterion.BIC);
fprintf(fid, 'R2 marginal: %.4f, R2 conditional: %.4f\n\n', R2_marginal, R2_conditional);

fprintf(fid, 'Descriptive Statistics:\n');
fprintf(fid, '  %-10s  Mean      SEM\n', 'Condition');
for c = 1:n_cond
    fprintf(fid, '  %-10s  %.4f    %.4f\n', cond_labels{c}, ...
        stats_results.Density.means(c), stats_results.Density.sems(c));
end

fprintf(fid, '\nANOVA:\n');
fprintf(fid, '  Condition: F(%d,%.1f) = %.3f, p = %.4f\n', ...
    lme_density_anova.DF1(2), lme_density_anova.DF2(2), ...
    lme_density_anova.FStat(2), lme_density_anova.pValue(2));

fprintf(fid, '\nPost-hoc Contrasts (Holm-Bonferroni):\n');
for k = 1:n_comp
    sig_str = '';
    if posthoc(k).p_holm < 0.001, sig_str = '***';
    elseif posthoc(k).p_holm < 0.01, sig_str = '**';
    elseif posthoc(k).p_holm < 0.05, sig_str = '*';
    end
    fprintf(fid, '  %s vs %s: est=%.4f, t=%.3f, p_holm=%.4f, d=%.3f %s\n', ...
        posthoc(k).cond1, posthoc(k).cond2, ...
        posthoc(k).estimate, posthoc(k).t, posthoc(k).p_holm, posthoc(k).d, sig_str);
end

fprintf(fid, '\n========================================\n');
fprintf(fid, '* p < %.2f\n', alpha);
fclose(fid);

% --- Supplementary ANOVA file + CSVs ---
supp_csv_dir = fullfile(OUTPUT_DIR, 'supplementary_anova');
if ~exist(supp_csv_dir, 'dir'), mkdir(supp_csv_dir); end

supp_file = fullfile(OUTPUT_DIR, [filename_base '_supplementary_anova.txt']);
sfid = fopen(supp_file, 'w');
fprintf(sfid, 'FIGURE 3 - Full LME / ANOVA Supplementary Report\n');
fprintf(sfid, 'Generated: %s\n', string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(sfid, 'ROI electrodes : %s\n', roi_label);
fprintf(sfid, 'Sleep stage    : %s\n', strjoin(sleep_stages, ', '));
fprintf(sfid, 'Frequency range: [%.1f, %.1f] Hz\n', freq_range(1), freq_range(2));
fprintf(sfid, 'Duration range : [%.2f, %.2f] s\n', dur_range(1), dur_range(2));
fprintf(sfid, 'Amplitude range: [%.1f, %.1f] uV\n', amp_range(1), amp_range(2));
fprintf(sfid, 'N subjects     : %d\n', n_subj);
fprintf(sfid, 'Alpha          : %.2f\n\n', alpha);
fprintf(sfid, 'LME models fitted with fitlme. Type III ANOVA with residual df.\n\n');

local_print_summary_table(sfid, headlines);

for m = 1:n_metrics
    write_lme_supplementary_report(sfid, stats_results.(all_metrics{m}).lme, ...
        all_metrics{m}, supp_csv_dir);
end
fclose(sfid);

fprintf('\nSaved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png / .svg / .fig\n', filename_base);
fprintf('  - %s.mat\n', filename_base);
fprintf('  - %s_stats.txt\n', filename_base);
fprintf('  - %s_supplementary_anova.txt\n', filename_base);
fprintf('  - supplementary_anova/ (CSV tables)\n');
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

function headline = write_lme_supplementary_report(fid, lme, metric_label, csv_dir)
%WRITE_LME_SUPPLEMENTARY_REPORT  Full LME report for one metric.

    safe_name = regexprep(lower(metric_label), '[^a-z0-9]', '_');

    % Compute ANOVA upfront so the headline can lead the report
    anova_ds  = anova(lme);
    anova_tbl = local_to_table(anova_ds);

    % Find the row for the Condition main effect (skip the Intercept row)
    cond_idx = find(strcmp(string(anova_tbl.Term), 'Condition'), 1);
    if isempty(cond_idx)
        cond_idx = min(2, height(anova_tbl));  % fallback: 2nd row
    end
    F_main   = anova_tbl.FStat(cond_idx);
    df1_main = anova_tbl.DF1(cond_idx);
    df2_main = anova_tbl.DF2(cond_idx);
    p_main   = anova_tbl.pValue(cond_idx);
    sig_main = local_sig_stars(p_main);

    headline = struct( ...
        'metric', metric_label, ...
        'F',      F_main, ...
        'df1',    df1_main, ...
        'df2',    df2_main, ...
        'p',      p_main, ...
        'sig',    sig_main);

    % --- Header ---
    fprintf(fid, '\n');
    fprintf(fid, '========================================================================\n');
    fprintf(fid, '  %s\n', upper(metric_label));
    fprintf(fid, '========================================================================\n');
    fprintf(fid, '  Condition: F(%d, %.0f) = %.3f, p = %.4f  %s\n', ...
        df1_main, df2_main, F_main, p_main, sig_main);
    fprintf(fid, '\n');

    % --- Model spec ---
    fprintf(fid, 'Formula: %s\n', char(lme.Formula));
    fprintf(fid, 'N observations: %d\n', lme.NumObservations);
    try
        grp_names = lme.Formula.GroupingVariableNames;
        if ~iscell(grp_names), grp_names = {grp_names}; end
        for g = 1:length(grp_names)
            gv = lme.Variables.(grp_names{g});
            fprintf(fid, 'N groups (%-12s): %d\n', grp_names{g}, length(unique(gv)));
        end
    catch
        % Older MATLAB versions: skip group counts
    end
    fprintf(fid, '\n');

    % --- Model fit statistics ---
    fitted_vals = fitted(lme);
    res         = lme.residuals;
    var_resid   = var(res);
    R2_cond     = var(fitted_vals) / (var(fitted_vals) + var_resid);
    X           = designMatrix(lme, 'Fixed');
    beta        = fixedEffects(lme);
    R2_marg     = var(X * beta) / (var(X * beta) + var_resid);

    fprintf(fid, '--- Model fit ---\n');
    fprintf(fid, '  Log-likelihood : %12.4f\n', lme.LogLikelihood);
    fprintf(fid, '  Deviance       : %12.4f\n', -2 * lme.LogLikelihood);
    fprintf(fid, '  AIC            : %12.4f\n', lme.ModelCriterion.AIC);
    fprintf(fid, '  BIC            : %12.4f\n', lme.ModelCriterion.BIC);
    fprintf(fid, '  R2 marginal    : %12.4f\n', R2_marg);
    fprintf(fid, '  R2 conditional : %12.4f\n', R2_cond);
    fprintf(fid, '  Residual var   : %12.4f\n', var_resid);
    fprintf(fid, '  Residual SD    : %12.4f\n\n', sqrt(var_resid));

    fit_tbl = table( ...
        lme.NumObservations, lme.LogLikelihood, -2*lme.LogLikelihood, ...
        lme.ModelCriterion.AIC, lme.ModelCriterion.BIC, ...
        R2_marg, R2_cond, var_resid, sqrt(var_resid), ...
        'VariableNames', {'N','LogLik','Deviance','AIC','BIC', ...
                          'R2_marginal','R2_conditional', ...
                          'ResidualVar','ResidualSD'});
    if ~isempty(csv_dir)
        writetable(fit_tbl, fullfile(csv_dir, sprintf('%s_model_fit.csv', safe_name)));
    end

    % --- Type III ANOVA table (computed upfront, see top of function) ---
    fprintf(fid, '--- Type III ANOVA (residual df) ---\n');
    fprintf(fid, '  %-22s %10s %8s %10s %12s   %s\n', ...
        'Term', 'F', 'numDF', 'denDF', 'p', 'sig');
    fprintf(fid, '  %s\n', repmat('-', 1, 75));
    for i = 1:height(anova_tbl)
        sig_i = local_sig_stars(anova_tbl.pValue(i));
        fprintf(fid, '  %-22s %10.3f %8d %10.2f %12.4g   %s\n', ...
            char(anova_tbl.Term(i)), anova_tbl.FStat(i), ...
            anova_tbl.DF1(i), anova_tbl.DF2(i), anova_tbl.pValue(i), sig_i);
    end
    fprintf(fid, '\n');
    if ~isempty(csv_dir)
        writetable(anova_tbl, fullfile(csv_dir, sprintf('%s_anova.csv', safe_name)));
    end

    % --- Fixed effects with 95% CIs ---
    fprintf(fid, '--- Fixed effects (estimate, SE, df, t, p, 95%% CI) ---\n');
    [~, ~, fe_ds] = fixedEffects(lme);
    fe_tbl = local_to_table(fe_ds);
    fprintf(fid, '  %-24s %10s %10s %8s %8s %12s %10s %10s\n', ...
        'Name', 'Estimate', 'SE', 'df', 't', 'p', 'CI_low', 'CI_high');
    fprintf(fid, '  %s\n', repmat('-', 1, 105));
    for i = 1:height(fe_tbl)
        df_i = NaN;
        if ismember('DF', fe_tbl.Properties.VariableNames), df_i = fe_tbl.DF(i); end
        fprintf(fid, '  %-24s %10.4f %10.4f %8.1f %8.3f %12.4g %10.4f %10.4f\n', ...
            char(fe_tbl.Name(i)), fe_tbl.Estimate(i), fe_tbl.SE(i), ...
            df_i, fe_tbl.tStat(i), fe_tbl.pValue(i), ...
            fe_tbl.Lower(i), fe_tbl.Upper(i));
    end
    fprintf(fid, '\n');
    if ~isempty(csv_dir)
        writetable(fe_tbl, fullfile(csv_dir, sprintf('%s_fixed_effects.csv', safe_name)));
    end

    % --- Random effects ---
    % Extract variance components and correlations from covarianceParameters,
    % then present as two clean tables: variances + correlation matrix.
    [~, ~, cov_stats] = covarianceParameters(lme);
    try
        grp_names_re = lme.Formula.GroupingVariableNames;
        if ~iscell(grp_names_re), grp_names_re = {grp_names_re}; end
    catch
        grp_names_re = {};
    end
    if isempty(grp_names_re)
        n_groups_re = max(0, length(cov_stats) - 1);
        grp_names_re = arrayfun(@(i) sprintf('Group%d', i), ...
            1:n_groups_re, 'UniformOutput', false);
    end
    n_groups_re = length(grp_names_re);

    % Collect variances and correlations separately
    var_labels = {};  var_vals = [];  var_sds = [];
    corr_labels_row = {};  corr_labels_col = {};  corr_vals = [];
    % Track per-group variance term names for building the correlation matrix
    grp_var_names = {};

    for ci = 1:min(n_groups_re, length(cov_stats))
        cs_tbl    = local_to_table(cov_stats{ci});
        grp_label = char(grp_names_re{ci});
        cur_var_names = {};
        for j = 1:height(cs_tbl)
            n1 = local_get_str(cs_tbl, 'Name1', j);
            n2 = local_get_str(cs_tbl, 'Name2', j);
            tp = local_get_str(cs_tbl, 'Type',  j);
            est = cs_tbl.Estimate(j);
            is_var = any(strcmpi(tp, {'std','Standard Deviation','Variance','var'})) ...
                  || strcmp(n1, n2);
            if is_var
                label = sprintf('%s (%s)', grp_label, n1);
                var_labels{end+1} = label; %#ok<AGROW>
                var_vals(end+1) = est;      %#ok<AGROW>
                var_sds(end+1) = sqrt(max(est, 0)); %#ok<AGROW>
                cur_var_names{end+1} = n1;  %#ok<AGROW>
            else
                row_label = sprintf('%s %s', grp_label, n1);
                col_label = sprintf('%s %s', grp_label, n2);
                corr_labels_row{end+1} = row_label; %#ok<AGROW>
                corr_labels_col{end+1} = col_label; %#ok<AGROW>
                corr_vals(end+1) = est;              %#ok<AGROW>
            end
        end
        grp_var_names = [grp_var_names, cur_var_names]; %#ok<AGROW>
    end
    % Add residual
    var_labels{end+1} = 'Residual';
    var_vals(end+1) = var_resid;
    var_sds(end+1) = sqrt(var_resid);

    % --- Print variances table ---
    fprintf(fid, '--- Random effects: Variances ---\n');
    max_label = max(cellfun(@length, var_labels));
    col_w = max(max_label, 30);
    fprintf(fid, '  %-*s %12s %12s\n', col_w, 'Random Effect', 'Variance', 'SD');
    fprintf(fid, '  %s\n', repmat('-', 1, col_w + 26));
    for k = 1:length(var_labels)
        fprintf(fid, '  %-*s %12.4f %12.4f\n', col_w, var_labels{k}, var_vals(k), var_sds(k));
    end
    fprintf(fid, '\n');

    % --- Print correlations (lower triangle) if any exist ---
    if ~isempty(corr_vals)
        fprintf(fid, '--- Random effects: Correlations ---\n');
        % Build unique ordered list of column labels
        [unique_cols, ~, ~] = unique(corr_labels_col, 'stable');
        % Column header
        col_hdr_w = 12;
        fprintf(fid, '  %-*s', col_w, '');
        for c = 1:length(unique_cols)
            % Shorten label: strip group prefix for header
            hdr = unique_cols{c};
            fprintf(fid, ' %*s', col_hdr_w, hdr);
        end
        fprintf(fid, '\n');
        fprintf(fid, '  %s\n', repmat('-', 1, col_w + length(unique_cols) * (col_hdr_w + 1)));
        % Rows: unique row labels in order of appearance
        [unique_rows, ~, ~] = unique(corr_labels_row, 'stable');
        for r = 1:length(unique_rows)
            fprintf(fid, '  %-*s', col_w, unique_rows{r});
            for c = 1:length(unique_cols)
                idx = find(strcmp(corr_labels_row, unique_rows{r}) & ...
                           strcmp(corr_labels_col, unique_cols{c}));
                if ~isempty(idx)
                    fprintf(fid, ' %*.3f', col_hdr_w, corr_vals(idx(1)));
                else
                    fprintf(fid, ' %*s', col_hdr_w, '');
                end
            end
            fprintf(fid, '\n');
        end
        fprintf(fid, '\n');
    end

    % --- CSV export (keep full detail for machine readability) ---
    if ~isempty(csv_dir)
        re_csv_rows = {};
        for k = 1:length(var_labels)
            re_csv_rows(end+1,:) = {var_labels{k}, 'variance', var_vals(k), var_sds(k)}; %#ok<AGROW>
        end
        for k = 1:length(corr_vals)
            re_csv_rows(end+1,:) = {sprintf('%s / %s', corr_labels_row{k}, corr_labels_col{k}), ...
                'correlation', corr_vals(k), NaN}; %#ok<AGROW>
        end
        re_tbl = cell2table(re_csv_rows, ...
            'VariableNames', {'Effect','Type','Estimate','SD'});
        writetable(re_tbl, fullfile(csv_dir, sprintf('%s_random_effects.csv', safe_name)));
    end

    fprintf(fid, '\n');
end

function tbl = local_to_table(x)
%LOCAL_TO_TABLE  Convert dataset/table to table for uniform handling.
    if isa(x, 'dataset')
        tbl = dataset2table(x);
    elseif istable(x)
        tbl = x;
    else
        tbl = table(x);
    end
end

function s = local_get_str(tbl, varname, row)
%LOCAL_GET_STR  Safely fetch a string-like column entry from a table row.
    if ~ismember(varname, tbl.Properties.VariableNames)
        s = '';
        return;
    end
    col = tbl.(varname);
    if ischar(col)
        % Char matrix: index by row so each row stays a string.
        if size(col, 1) >= row
            s = strtrim(col(row, :));
        else
            s = strtrim(col);
        end
        return;
    end
    v = col(row);
    if iscell(v), v = v{1}; end
    if isstring(v) || ischar(v)
        s = char(v);
    elseif iscategorical(v)
        s = char(v);
    else
        s = num2str(v);
    end
end

function s = local_sig_stars(p)
%LOCAL_SIG_STARS  Return APA-style significance marker for a p-value.
    if isnan(p),       s = '   ';
    elseif p < 0.001,  s = '***';
    elseif p < 0.01,   s = '** ';
    elseif p < 0.05,   s = '*  ';
    elseif p < 0.1,    s = '.  ';
    else,              s = 'n.s';
    end
end

function local_print_summary_table(fid, headlines)
%LOCAL_PRINT_SUMMARY_TABLE  Print one-line-per-metric ANOVA summary.
%  This is the table to copy directly into the supplementary materials.
    fprintf(fid, '\n');
    fprintf(fid, '========================================================================\n');
    fprintf(fid, '  ANOVA Summary: Main effect of Condition\n');
    fprintf(fid, '========================================================================\n');
    fprintf(fid, '  %-12s  %8s  %5s  %8s  %10s   %s\n', ...
        'Metric', 'F', 'numDF', 'denDF', 'p', 'sig');
    fprintf(fid, '  %s\n', repmat('-', 1, 60));
    for k = 1:length(headlines)
        h = headlines(k);
        fprintf(fid, '  %-12s  %8.3f  %5d  %8.0f  %10.4f   %s\n', ...
            h.metric, h.F, h.df1, h.df2, h.p, h.sig);
    end
    fprintf(fid, '  %s\n', repmat('-', 1, 60));
    fprintf(fid, '  sig codes: *** p<.001  ** p<.01  * p<.05  . p<.1  n.s p>=.1\n');
    fprintf(fid, '\n');
end
