function figure3_densityBarplot()
%% FIGURE 3: Spindle Density Barplot
% Shows spindle density (spindles/min) across conditions
% LME: Density ~ 1 + Condition + (1 + Condition | Subject) + (1 | Subject:Electrode)

clear; clc;

% Paths
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
RESULTS_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
DATA_FILE = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');
OUTPUT_DIR = fullfile(REPO_ROOT, '4_FIGURE3_Events', 'outputs');

% Parameters
conditions = {'x5HZ', 'x1HZ', 'OFF'};
sleep_stages = {'N2'};
roi_electrodes = {};  % Empty = all electrodes
freq_range = [12, 16];
dur_range = [0.5, 3.0];
amp_range = [15, 100];
alpha = 0.05;

% Publication settings
pub = struct('fig_width_cm', 8, 'fig_height_cm', 8, 'font_name', 'Arial', ...
    'font_size_axis', 7, 'font_size_label', 8, 'font_size_title', 9, 'bar_width', 0.6);
colors = [1.0, 0.55, 0.0; 0.2, 0.4, 0.8; 0.5, 0.5, 0.5];

fprintf('=== Spindle Density Barplot ===\n');

% Load Data
loaded = load(DATA_FILE, 'all_spindles', 'all_condition_durations');
spindles = loaded.all_spindles;
durations = loaded.all_condition_durations;
fprintf('Loaded %d spindles\n', height(spindles));

% Filter Spindles
spindles.PrimaryChannel = cellfun(@(x) extract_primary_channel(x), spindles.Channel, 'UniformOutput', false);
spindles = spindles(ismember(spindles.SleepStage, sleep_stages), :);
spindles = spindles(ismember(spindles.Condition, conditions), :);
if ~isempty(roi_electrodes)
    spindles = spindles(ismember(spindles.PrimaryChannel, roi_electrodes), :);
end
spindles = spindles(spindles.Frequency >= freq_range(1) & spindles.Frequency <= freq_range(2), :);
spindles = spindles(spindles.Duration >= dur_range(1) & spindles.Duration <= dur_range(2), :);
spindles = spindles(spindles.Amplitude >= amp_range(1) & spindles.Amplitude <= amp_range(2), :);
fprintf('Filtered spindles: %d\n', height(spindles));

% Compute Density per Subject/Condition/Electrode
subjects = unique(spindles.Subject);
electrodes = unique(spindles.PrimaryChannel);
n_subj = length(subjects);
n_cond = length(conditions);
n_elec = length(electrodes);

% Build table for LME (electrode-level data)
% Pre-allocate arrays to avoid table warnings
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

        % Get sleep duration for this subject-condition
        dur_mask = strcmp(durations.Subject, subj) & strcmp(durations.Condition, cond) & ...
                   ismember(durations.SleepStage, sleep_stages);
        if ~any(dur_mask), continue; end
        total_min = sum(durations.Duration_min(dur_mask));
        if total_min <= 0, continue; end

        for e = 1:n_elec
            elec = electrodes{e};

            % Count spindles for this subject-condition-electrode
            sp_mask = strcmp(spindles.Subject, subj) & strcmp(spindles.Condition, cond) & ...
                      strcmp(spindles.PrimaryChannel, elec);
            n_spindles = sum(sp_mask);

            % Density = spindles per minute
            density = n_spindles / total_min;

            row = row + 1;
            subj_arr{row} = subj;
            cond_arr{row} = cond;
            elec_arr{row} = elec;
            dens_arr(row) = density;
        end
    end
end
% Create table from pre-allocated arrays (trim to actual rows)
T = table(subj_arr(1:row), cond_arr(1:row), elec_arr(1:row), dens_arr(1:row), ...
    'VariableNames', {'Subject', 'Condition', 'Electrode', 'Density'});

T.Subject = categorical(T.Subject);
T.Condition = categorical(T.Condition);
T.Electrode = categorical(T.Electrode);
fprintf('Electrode-level observations: %d\n', height(T));

% Find complete subjects (have data for all conditions)
subj_cond_counts = groupcounts(T, 'Subject');
complete_subj = subj_cond_counts.Subject(subj_cond_counts.GroupCount == n_cond * n_elec);
T = T(ismember(T.Subject, complete_subj), :);
T.Subject = removecats(T.Subject);
fprintf('Complete subjects: %d\n', length(categories(T.Subject)));

% Statistics (LME)
model_formula = 'Density ~ 1 + Condition + (1 + Condition | Subject) + (1 | Subject:Electrode)';
%model_formula = 'Density ~ 1 + Condition + (1|Subject) + (1|Electrode)';

fprintf('\n========== LINEAR MIXED-EFFECTS MODEL ==========\n');
fprintf('Formula: %s\n', model_formula);
lme = fitlme(T, model_formula);

% Model specification
fprintf('\n--- Model Specification ---\n');
fprintf('Observations: %d\n', lme.NumObservations);
fprintf('Subjects: %d\n', length(categories(T.Subject)));
fprintf('Electrodes per subject: %d\n', length(categories(T.Electrode)));
fprintf('Conditions: %d (%s)\n', n_cond, strjoin(conditions, ', '));
fprintf('Estimation method: %s\n', lme.FitMethod);

% Model fit statistics
fprintf('\n--- Model Fit ---\n');
fprintf('AIC: %.2f\n', lme.ModelCriterion.AIC);
fprintf('BIC: %.2f\n', lme.ModelCriterion.BIC);
fprintf('Log-Likelihood: %.2f\n', lme.LogLikelihood);

% R^2 calculation (Nakagawa & Schielzeth approximation)
% R^2_conditional: variance explained by fixed + random effects
fitted_full = fitted(lme);
var_fitted_full = var(fitted_full);
var_resid = var(lme.residuals);
R2_conditional = var_fitted_full / (var_fitted_full + var_resid);

% R^2_marginal: variance explained by fixed effects only
X = designMatrix(lme, 'Fixed');
beta = fixedEffects(lme);
fitted_fixed = X * beta;
var_fitted_fixed = var(fitted_fixed);
R2_marginal = var_fitted_fixed / (var_fitted_fixed + var_resid);

fprintf('R^2 (marginal, fixed effects only): %.4f\n', R2_marginal);
fprintf('R^2 (conditional, fixed + random): %.4f\n', R2_conditional);

% Fixed effects
fprintf('\n--- Fixed Effects ---\n');
fe = fixedEffects(lme);
[~, ~, fe_stats] = fixedEffects(lme);
fprintf('%-20s %10s %10s %10s %10s %10s %10s\n', 'Name', 'Estimate', 'SE', 'Lower95', 'Upper95', 'tStat', 'pValue');
fprintf('%s\n', repmat('-', 1, 90));
for i = 1:height(fe_stats)
    fprintf('%-20s %10.4f %10.4f %10.4f %10.4f %10.3f %10.4f\n', ...
        fe_stats.Name{i}, fe_stats.Estimate(i), fe_stats.SE(i), ...
        fe_stats.Lower(i), fe_stats.Upper(i), fe_stats.tStat(i), fe_stats.pValue(i));
end

% Random effects variance components
fprintf('\n--- Random Effects (Variance Components) ---\n');
[~, ~, re_stats] = covarianceParameters(lme);
for k = 1:length(re_stats)
    re_tbl = re_stats{k};
    % Handle both dataset and table types
    if isa(re_tbl, 'dataset')
        re_tbl = dataset2table(re_tbl);
    end
    col_names = re_tbl.Properties.VariableNames;
    % Get group name (handle cell or char)
    grp_val = re_tbl.Group(1);
    if iscell(grp_val), grp_val = grp_val{1}; end
    fprintf('Group: %s\n', grp_val);
    for j = 1:height(re_tbl)
        % Get name - try Name1, Name, or Type column
        if ismember('Name1', col_names)
            name_val = re_tbl.Name1(j);
        elseif ismember('Name', col_names)
            name_val = re_tbl.Name(j);
        elseif ismember('Type', col_names)
            name_val = re_tbl.Type(j);
        else
            name_val = sprintf('Component %d', j);
        end
        if iscell(name_val), name_val = name_val{1}; end
        fprintf('  %-25s: %.6f [%.6f, %.6f]\n', name_val, re_tbl.Estimate(j), re_tbl.Lower(j), re_tbl.Upper(j));
    end
end

% ANOVA table for fixed effects
fprintf('\n--- ANOVA (Type III) ---\n');
lme_res = anova(lme);
fprintf('%-15s %5s %8s %10s %10s\n', 'Term', 'DF1', 'DF2', 'F', 'pValue');
fprintf('%s\n', repmat('-', 1, 55));
for i = 1:height(lme_res)
    fprintf('%-15s %5d %8.1f %10.3f %10.4f\n', ...
        lme_res.Term{i}, lme_res.DF1(i), lme_res.DF2(i), lme_res.FStat(i), lme_res.pValue(i));
end
fprintf('\nMain effect (Condition): F(%d,%.1f) = %.3f, p = %.4f\n', ...
    lme_res.DF1(2), lme_res.DF2(2), lme_res.FStat(2), lme_res.pValue(2));

% Aggregate to subject level for plotting
subj_means = groupsummary(T, {'Subject', 'Condition'}, 'mean', 'Density');
subjects = categories(T.Subject);
n_subj = length(subjects);

density_matrix = nan(n_subj, n_cond);
for s = 1:n_subj
    for c = 1:n_cond
        mask = subj_means.Subject == subjects{s} & subj_means.Condition == conditions{c};
        if any(mask)
            density_matrix(s, c) = subj_means.mean_Density(mask);
        end
    end
end

% Post-hoc contrasts (LME-based)
fprintf('\n--- Post-hoc Contrasts (Holm-Bonferroni corrected) ---\n');
cond_cats = categories(T.Condition);
n_comp = n_cond * (n_cond - 1) / 2;
posthoc = struct('pairs', cell(1, n_comp), 'cond1', cell(1, n_comp), 'cond2', cell(1, n_comp), ...
    'estimate', cell(1, n_comp), 'se', cell(1, n_comp), 'df', cell(1, n_comp), ...
    't', cell(1, n_comp), 'p_uncorr', cell(1, n_comp), 'p_holm', cell(1, n_comp), 'd', cell(1, n_comp));

% Build contrast matrix for each pairwise comparison
% Fixed effects order: (Intercept), Condition_level2, Condition_level3, ...
% Reference level is cond_cats{1}
comp_idx = 0;
for i = 1:n_cond-1
    for j = i+1:n_cond
        comp_idx = comp_idx + 1;
        posthoc(comp_idx).pairs = [i, j];
        posthoc(comp_idx).cond1 = conditions{i};
        posthoc(comp_idx).cond2 = conditions{j};

        % Build contrast vector
        H = zeros(1, length(fe));
        idx_i = find(strcmp(cond_cats, conditions{i}));
        idx_j = find(strcmp(cond_cats, conditions{j}));

        % Reference category handling
        if idx_i == 1
            H(idx_j) = -1;  % ref vs non-ref: coefficient is negative
        elseif idx_j == 1
            H(idx_i) = 1;   % non-ref vs ref: coefficient is positive
        else
            H(idx_i) = 1;
            H(idx_j) = -1;  % non-ref vs non-ref
        end

        [p_val, F_val, ~, df2] = coefTest(lme, H);
        t_val = sign(H * fe) * sqrt(F_val);
        estimate = H * fe;

        % Get SE from contrast
        cov_mat = lme.CoefficientCovariance;
        se = sqrt(H * cov_mat * H');

        posthoc(comp_idx).estimate = estimate;
        posthoc(comp_idx).se = se;
        posthoc(comp_idx).df = df2;
        posthoc(comp_idx).t = t_val;
        posthoc(comp_idx).p_uncorr = p_val;

        % Cohen's d from contrast (estimate / pooled SD)
        pooled_sd = std(T.Density);
        posthoc(comp_idx).d = estimate / pooled_sd;
    end
end

% Holm-Bonferroni correction
p_uncorr = [posthoc.p_uncorr];
[p_sorted, sort_idx] = sort(p_uncorr);
p_holm = zeros(1, n_comp);
for k = 1:n_comp
    p_holm(sort_idx(k)) = min(1, p_sorted(k) * (n_comp - k + 1));
end
% Enforce monotonicity
for k = 2:n_comp
    if p_holm(sort_idx(k)) < p_holm(sort_idx(k-1))
        p_holm(sort_idx(k)) = p_holm(sort_idx(k-1));
    end
end
for k = 1:n_comp
    posthoc(k).p_holm = p_holm(k);
end

% Print results
fprintf('%-15s %10s %10s %10s %10s %12s %12s %10s\n', ...
    'Comparison', 'Estimate', 'SE', 'df', 't', 'p(uncorr)', 'p(Holm)', 'Cohen''s d');
fprintf('%s\n', repmat('-', 1, 100));
for k = 1:n_comp
    sig_str = '';
    if posthoc(k).p_holm < 0.001, sig_str = '***';
    elseif posthoc(k).p_holm < 0.01, sig_str = '**';
    elseif posthoc(k).p_holm < 0.05, sig_str = '*';
    end
    fprintf('%-15s %10.4f %10.4f %10.1f %10.3f %12.4f %12.4f %10.3f %s\n', ...
        sprintf('%s vs %s', posthoc(k).cond1, posthoc(k).cond2), ...
        posthoc(k).estimate, posthoc(k).se, posthoc(k).df, posthoc(k).t, ...
        posthoc(k).p_uncorr, posthoc(k).p_holm, posthoc(k).d, sig_str);
end

%% Create Figure
if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end

means = mean(density_matrix, 1, 'omitnan');
sems = std(density_matrix, 0, 1, 'omitnan') / sqrt(n_subj);

fig = figure('Units', 'centimeters', 'Position', [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
    'Color', 'white', 'PaperUnits', 'centimeters', ...
    'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
    'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

hold on;
for c = 1:n_cond
    bar(c, means(c), pub.bar_width, 'FaceColor', colors(c,:), 'EdgeColor', 'k', 'LineWidth', 1.2);
end
errorbar(1:n_cond, means, sems, 'k.', 'LineWidth', 1.5, 'CapSize', 10);

% Connecting lines per subject (faint)
for s = 1:n_subj
    if all(~isnan(density_matrix(s,:)))
        plot(1:n_cond, density_matrix(s,:), '-', ...
            'Color', [0.6, 0.6, 0.6, 0.3], 'LineWidth', 0.5);
    end
end

% Individual data points (jittered)
rng(42);
for c = 1:n_cond
    data_pts = density_matrix(:, c);
    valid = ~isnan(data_pts);
    x_jitter = c + 0.15 * (rand(sum(valid), 1) - 0.5);
    scatter(x_jitter, data_pts(valid), 15, colors(c,:), 'o', ...
        'MarkerEdgeColor', [0,0,0], 'MarkerEdgeAlpha', 0.4, 'MarkerFaceAlpha', 0.4, 'LineWidth', 0.5);
end

% Significance brackets (using Holm-corrected p-values)
max_individual_point = max(density_matrix(:), [], 'omitnan');
y_off = max_individual_point * 1.15;
bracket_h = range([means(:); density_matrix(:)]) * 0.05;
for k = 1:length(posthoc)
    if posthoc(k).p_holm < alpha
        c1 = posthoc(k).pairs(1); c2 = posthoc(k).pairs(2);
        plot([c1 c2], [y_off y_off], 'k-', 'LineWidth', 1.5);
        if posthoc(k).p_holm < 0.001
            sig = '***';
        elseif posthoc(k).p_holm < 0.01
            sig = '**';
        else
            sig = '*';
        end
        text(mean([c1 c2]), y_off + bracket_h*0.3, sig, 'HorizontalAlignment', 'center', ...
            'FontSize', 12, 'FontWeight', 'bold');
        y_off = y_off + bracket_h * 2;
    end
end
hold off;

% Formatting
cond_labels = {'5 Hz', '1 Hz', 'Off'};
set(gca, 'XTick', 1:n_cond, 'XTickLabel', cond_labels, ...
    'FontName', pub.font_name, 'FontSize', pub.font_size_axis, 'Box', 'off', 'TickDir', 'out');
xlabel('Condition', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel('Density (spindles/min)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label, 'FontWeight', 'bold');
title(sprintf('Spindle Density (p=%.3f)', lme_res.pValue(2)), ...
    'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');
ylim([0, y_off + bracket_h]);
grid on;

% Summary
fprintf('\n========== SUMMARY ==========\n');
fprintf('\n--- Methods Text ---\n');
fprintf(['Spindle density was analyzed using a linear mixed-effects model (LME) with ' ...
    'condition (5 Hz, 1 Hz, Off) as fixed effect, random intercepts and slopes for ' ...
    'condition per subject, and random intercepts for electrode nested within subject. ' ...
    'Model: %s. Post-hoc pairwise comparisons were performed using model-based contrasts ' ...
    'with Holm-Bonferroni correction for multiple comparisons (n=%d tests).\n'], model_formula, n_comp);

fprintf('\n--- Results Text ---\n');
fprintf(['The LME revealed a %s main effect of condition on spindle density ' ...
    '(F(%d,%.1f) = %.2f, p %s; AIC = %.1f, BIC = %.1f). '], ...
    conditional_str(lme_res.pValue(2) < alpha, 'significant', 'non-significant'), ...
    lme_res.DF1(2), lme_res.DF2(2), lme_res.FStat(2), ...
    format_pvalue(lme_res.pValue(2)), lme.ModelCriterion.AIC, lme.ModelCriterion.BIC);

% Report significant post-hoc comparisons
sig_comps = find([posthoc.p_holm] < alpha);
if ~isempty(sig_comps)
    fprintf('Post-hoc contrasts revealed ');
    comp_strs = cell(1, length(sig_comps));
    for idx = 1:length(sig_comps)
        k = sig_comps(idx);
        comp_strs{idx} = sprintf('%s vs %s (Î” = %.3f, t(%.1f) = %.2f, p_holm %s, d = %.2f)', ...
            posthoc(k).cond1, posthoc(k).cond2, posthoc(k).estimate, posthoc(k).df, ...
            posthoc(k).t, format_pvalue(posthoc(k).p_holm), posthoc(k).d);
    end
    fprintf('%s.\n', strjoin(comp_strs, '; '));
else
    fprintf('No post-hoc comparisons survived correction.\n');
end

% Save
fname = 'figure3_densityBarplot';
print(fig, fullfile(OUTPUT_DIR, [fname '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [fname '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [fname '.fig']));

% Save comprehensive statistics structure
stats = struct();
stats.model_formula = model_formula;
stats.n_observations = lme.NumObservations;
stats.n_subjects = length(categories(T.Subject));
stats.n_electrodes = length(categories(T.Electrode));
stats.n_conditions = n_cond;
stats.conditions = conditions;
stats.fit_method = lme.FitMethod;
stats.AIC = lme.ModelCriterion.AIC;
stats.BIC = lme.ModelCriterion.BIC;
stats.LogLikelihood = lme.LogLikelihood;
stats.R2_marginal = R2_marginal;
stats.R2_conditional = R2_conditional;
stats.fixed_effects = fe_stats;
stats.anova = lme_res;
stats.posthoc = posthoc;
stats.alpha = alpha;

save(fullfile(OUTPUT_DIR, [fname '.mat']), 'T', 'density_matrix', 'subjects', 'conditions', 'lme', 'lme_res', 'posthoc', 'stats');

fprintf('\n========================================\n');
fprintf('Saved to: %s\n', OUTPUT_DIR);
end

function primary = extract_primary_channel(ch)
    if iscell(ch), ch = ch{1}; end
    ch = strtok(ch, '+');
    ch = regexprep(ch, 'A[12]', '');
    ch = regexprep(ch, '[^A-Za-z0-9]', '');
    primary = upper(ch);
end

function str = conditional_str(cond, true_str, false_str)
    if cond
        str = true_str;
    else
        str = false_str;
    end
end

function str = format_pvalue(p)
    if p < 0.001
        str = '< .001';
    elseif p < 0.01
        str = sprintf('= %.3f', p);
    else
        str = sprintf('= %.2f', p);
    end
end
