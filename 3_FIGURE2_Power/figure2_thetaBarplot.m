function figure2_thetaBarplot()
%% FIGURE 2: Theta-Band Power Barplot with LME
% Loads the kept-trial list produced by figure2_topography.m
% (figure2_trial_indices.mat), reads only those trials from the
% per-trial TFR files, log-transforms the raw power, summarises per
% subject x electrode x condition, and runs an LME.
%
% LME: Power ~ 1 + Condition + (Condition | Subject) + (1 | Electrode)

clear; clc;

%% ========================================================================
%  PATHS
%  ========================================================================
SCRIPT_FILE = matlab.desktop.editor.getActiveFilename;
SCRIPT_DIR  = fileparts(SCRIPT_FILE);

addpath(SCRIPT_DIR);
addpath(fullfile(SCRIPT_DIR, 'functions'));
addpath(fullfile(SCRIPT_DIR, 'functions_figure2_topography'));
addpath(fullfile(SCRIPT_DIR, 'functions_figure2_tfr_timeseries'));  % extract_tfr_struct
OUTPUT_DIR         = fullfile(SCRIPT_DIR, 'outputs');
TRIAL_INDICES_FILE = fullfile(OUTPUT_DIR, 'figure2_trial_indices.mat');

paths    = figure2_paths_config();
TFR_PATH = paths.tfr_spindle;

%% ========================================================================
%  PARAMETERS
%  ========================================================================

% Participants and design
participants     = {'sub5','sub6','sub7','sub8','sub9','sub10','sub11','sub12', ...
    'sub13','sub14','sub15','sub16','sub17','sub18','sub19','sub20','sub21','sub22', ...
    'sub23','sub24'};
session          = 'ses1';
conditions       = {'x5HZ', 'x1HZ', 'OFF'};
condition_labels = {'5 Hz', '1 Hz', 'Off'};

% Load range (just wide enough for theta)
load_freq_range = [4, 8];
load_time_range = [-1, 2];

% Theta analysis window {f_lo, f_hi, t_lo, t_hi, label}
time_freq_windows = { 4, 8, 0.5, 1.5, 'Theta' };
window_label      = time_freq_windows{1, 5};

% Trial summarisation (matches topography pipeline)
summary_method       = 'trimmed_mean';
trimmed_mean_percent = 0;

% LME
alpha         = 0.05;
model_formula = 'Power ~ 1 + Condition + (Condition | Subject) + (1 | Electrode)';
fit_method    = 'ML';
output_name   = 'figure2_powerBarplot_theta';

% Publication settings
pub = struct('fig_width_cm', 8, 'fig_height_cm', 8, 'font_name', 'Arial', ...
    'font_size_axis', 7, 'font_size_label', 8, 'font_size_title', 9, 'bar_width', 0.6);
colors = [1.0 0.55 0.0;   % 5 Hz - orange
          0.0 0.20 0.60;  % 1 Hz - blue
          0.6 0.60 0.60]; % Off  - gray

fprintf('=== FIGURE 2: %s Power Barplot ===\n', window_label);

%% ========================================================================
%  STEP 1: LOAD SAVED TRIAL INDICES
%  ========================================================================
if ~exist(TRIAL_INDICES_FILE, 'file')
    error(['Required trial-indices file not found:\n  %s\n' ...
           'Run figure2_topography.m first.'], TRIAL_INDICES_FILE);
end
fprintf('Loading kept-trial list from %s\n', TRIAL_INDICES_FILE);
loaded = load(TRIAL_INDICES_FILE, 'trial_indices');
trial_indices = loaded.trial_indices;

%% ========================================================================
%  STEP 2: LOAD ONLY KEPT TRIALS
%  ========================================================================
fprintf('\n--- Loading kept trials (no filter re-application) ---\n');
ft_defaults;
all_data = load_kept_trials(TFR_PATH, participants, session, conditions, ...
    trial_indices, load_time_range, load_freq_range);

%% ========================================================================
%  STEP 3: LOG-TRANSFORM + SUMMARISATION METADATA
%  ========================================================================
for p = 1:length(participants)
    sub = participants{p};
    if ~isfield(all_data, sub), continue; end
    for c = 1:length(conditions)
        cond = conditions{c};
        if ~isfield(all_data.(sub), cond), continue; end
        all_data.(sub).(cond).trials = 10 * log10(all_data.(sub).(cond).trials);
        all_data.(sub).(cond).summary_method = summary_method;
        all_data.(sub).(cond).trim_percent   = trimmed_mean_percent;
    end
end

%% ========================================================================
%  STEP 4: COMPUTE SUBJECT-LEVEL THETA POWER
%  (uses canonical layout matching + trimmed-mean per electrode)
%  ========================================================================
fprintf('\n--- Computing subject-level theta power ---\n');
cfg = struct();
cfg.participants = participants;
cfg.conditions   = conditions;
cfg.topo_params  = struct( ...
    'time_freq_windows', {time_freq_windows}, ...
    'layout',            'easycapM1.mat');

compute_results = spindlePilot_visual_topographyTFR_compute_from_filtered( ...
    all_data, trial_indices, cfg);

subject_data     = compute_results.subject_data;
matched_channels = compute_results.matched_channels;

%% ========================================================================
%  STEP 5: BUILD LONG-FORMAT TABLE (Subject x Condition x Electrode)
%  ========================================================================
n_chan = length(matched_channels);
n_cond = length(conditions);
max_rows = length(participants) * n_cond * n_chan;
subj_arr = cell(max_rows, 1);
cond_arr = cell(max_rows, 1);
elec_arr = cell(max_rows, 1);
pow_arr  = nan(max_rows, 1);
row = 0;
for p = 1:length(participants)
    sub = participants{p};
    if ~isfield(subject_data, sub), continue; end
    for c = 1:n_cond
        cond = conditions{c};
        if ~isfield(subject_data.(sub), cond), continue; end
        vals = subject_data.(sub).(cond).(window_label);   % [n_chan x 1]
        for e = 1:n_chan
            if isnan(vals(e)), continue; end
            row = row + 1;
            subj_arr{row} = sub;
            cond_arr{row} = cond;
            elec_arr{row} = matched_channels{e};
            pow_arr(row)  = vals(e);
        end
    end
end
T = table(subj_arr(1:row), cond_arr(1:row), elec_arr(1:row), pow_arr(1:row), ...
    'VariableNames', {'Subject', 'Condition', 'Electrode', 'Power'});
T.Subject   = categorical(T.Subject);
T.Condition = categorical(T.Condition, conditions);
T.Electrode = categorical(T.Electrode);

% Keep only subjects with all Condition x Electrode cells present
subj_cond_counts = groupcounts(T, 'Subject');
complete_subj = subj_cond_counts.Subject(subj_cond_counts.GroupCount == n_cond * n_chan);
T = T(ismember(T.Subject, complete_subj), :);
T.Subject = removecats(T.Subject);
fprintf('Complete subjects: %d / %d | LME observations: %d\n', ...
    length(categories(T.Subject)), length(participants), height(T));

%% ========================================================================
%  STEP 6: FIT LME
%  ========================================================================
fprintf('\n--- LME ---\nFormula: %s\nFit method: %s\n', model_formula, fit_method);
lme = fitlme(T, model_formula, 'FitMethod', fit_method);
fprintf('AIC=%.2f  BIC=%.2f  LogLik=%.2f\n', ...
    lme.ModelCriterion.AIC, lme.ModelCriterion.BIC, lme.LogLikelihood);

lme_anova = anova(lme);
cond_row = find(strcmp(lme_anova.Term, 'Condition'), 1);
F_cond = lme_anova.FStat(cond_row);
p_cond = lme_anova.pValue(cond_row);
df1    = lme_anova.DF1(cond_row);
df2    = lme_anova.DF2(cond_row);
fprintf('\n--- ANOVA ---\n');
for i = 1:height(lme_anova)
    fprintf('%-15s F(%d,%.1f) = %.3f, p = %.4f\n', ...
        lme_anova.Term{i}, lme_anova.DF1(i), lme_anova.DF2(i), ...
        lme_anova.FStat(i), lme_anova.pValue(i));
end
fprintf('Condition main effect: F(%d,%.1f) = %.3f, p = %.4f\n', df1, df2, F_cond, p_cond);

%% ========================================================================
%  STEP 7: POST-HOC (pairwise, Holm-Bonferroni)
%  ========================================================================
posthoc = run_posthoc_contrasts(lme, T, conditions, n_cond);

fprintf('\n--- Post-hoc (Holm-Bonferroni) ---\n');
fprintf('%-18s %9s %9s %9s %9s %9s %9s\n', ...
    'Comparison','Est(dB)','SE','t','df','p(un)','p(Holm)');
fprintf('%s\n', repmat('-', 1, 84));
for k = 1:length(posthoc)
    fprintf('%-18s %9.3f %9.3f %9.3f %9.1f %9.4f %9.4f\n', ...
        sprintf('%s vs %s', posthoc(k).cond1, posthoc(k).cond2), ...
        posthoc(k).estimate, posthoc(k).se, posthoc(k).t, posthoc(k).df, ...
        posthoc(k).p_uncorr, posthoc(k).p_holm);
end

%% ========================================================================
%  STEP 8: SUBJECT-LEVEL MEANS FOR BARPLOT (average across electrodes)
%  ========================================================================
subj_list = categories(T.Subject);
n_subj = length(subj_list);
power_matrix = nan(n_subj, n_cond);
for s = 1:n_subj
    for c = 1:n_cond
        m = T.Subject == subj_list{s} & T.Condition == conditions{c};
        power_matrix(s, c) = mean(T.Power(m), 'omitnan');
    end
end
means = mean(power_matrix, 1, 'omitnan');
sems  = std(power_matrix, 0, 1, 'omitnan') / sqrt(n_subj);

%% ========================================================================
%  STEP 9: PLOT
%  ========================================================================
if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end
fig = figure('Units','centimeters', ...
    'Position',[5 5 pub.fig_width_cm pub.fig_height_cm], ...
    'Color','white', 'PaperUnits','centimeters', ...
    'PaperSize',[pub.fig_width_cm pub.fig_height_cm], ...
    'PaperPosition',[0 0 pub.fig_width_cm pub.fig_height_cm]);
hold on;

for c = 1:n_cond
    bar(c, means(c), pub.bar_width, 'FaceColor', colors(c,:), ...
        'EdgeColor','k', 'LineWidth',1.2);
end
errorbar(1:n_cond, means, sems, 'k.', 'LineWidth',1.5, 'CapSize',10);

for s = 1:n_subj
    if all(~isnan(power_matrix(s,:)))
        plot(1:n_cond, power_matrix(s,:), '-', ...
            'Color', [0.6 0.6 0.6 0.3], 'LineWidth', 0.5);
    end
end

rng(42);
for c = 1:n_cond
    pts = power_matrix(:, c);
    v   = ~isnan(pts);
    xj  = c + 0.15 * (rand(sum(v), 1) - 0.5);
    scatter(xj, pts(v), 15, colors(c,:), 'o', ...
        'MarkerEdgeColor',[0 0 0], 'MarkerEdgeAlpha',0.4, ...
        'MarkerFaceAlpha',0.4, 'LineWidth',0.5);
end

y_top     = max(power_matrix(:), [], 'omitnan');
y_min     = min(power_matrix(:), [], 'omitnan');
y_off     = y_top * 1.15;
bracket_h = range([means(:); power_matrix(:)]) * 0.05;
for k = 1:length(posthoc)
    if posthoc(k).p_holm < alpha
        c1 = posthoc(k).pairs(1); c2 = posthoc(k).pairs(2);
        plot([c1 c2], [y_off y_off], 'k-', 'LineWidth', 1.5);
        if     posthoc(k).p_holm < 0.001, sig_str = '***';
        elseif posthoc(k).p_holm < 0.01,  sig_str = '**';
        else,                             sig_str = '*';
        end
        text(mean([c1 c2]), y_off + bracket_h*0.3, sig_str, ...
            'HorizontalAlignment','center', 'FontSize',12, 'FontWeight','bold');
        y_off = y_off + bracket_h * 2;
    end
end
hold off;

set(gca, 'XTick', 1:n_cond, 'XTickLabel', condition_labels, ...
    'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
    'Box', 'off', 'TickDir', 'out');
xlabel('Condition', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel('Power (dB)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label, 'FontWeight','bold');
title(sprintf('Theta-Band Power (p=%.3f)', p_cond), ...
    'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight','bold');
ylim([min(0, y_min * 1.1), y_off + bracket_h]);
grid on;

%% ========================================================================
%  STEP 10: SAVE OUTPUTS
%  ========================================================================
print(fig, fullfile(OUTPUT_DIR, [output_name '.png']), '-dpng', '-r300');
print(fig, fullfile(OUTPUT_DIR, [output_name '.svg']), '-dsvg', '-vector');
savefig(fig, fullfile(OUTPUT_DIR, [output_name '.fig']));

settings = struct( ...
    'participants',         {participants}, ...
    'session',              session, ...
    'conditions',           {conditions}, ...
    'time_freq_window',     {time_freq_windows(1, :)}, ...
    'load_time_range',      load_time_range, ...
    'load_freq_range',      load_freq_range, ...
    'summary_method',       summary_method, ...
    'trimmed_mean_percent', trimmed_mean_percent, ...
    'log_transform',        true, ...
    'trial_indices_source', TRIAL_INDICES_FILE);

lme_stats = struct();
lme_stats.model_formula       = model_formula;
lme_stats.fit_method          = fit_method;
lme_stats.n_observations      = lme.NumObservations;
lme_stats.n_subjects          = length(categories(T.Subject));
lme_stats.n_electrodes        = length(categories(T.Electrode));
lme_stats.n_conditions        = n_cond;
lme_stats.conditions          = conditions;
lme_stats.AIC                 = lme.ModelCriterion.AIC;
lme_stats.BIC                 = lme.ModelCriterion.BIC;
lme_stats.LogLikelihood       = lme.LogLikelihood;
lme_stats.anova               = lme_anova;
lme_stats.anova_F_Condition   = F_cond;
lme_stats.anova_p_Condition   = p_cond;
lme_stats.anova_DF1_Condition = df1;
lme_stats.anova_DF2_Condition = df2;
[~, ~, fe_stats] = fixedEffects(lme);
lme_stats.fixed_effects = fe_stats;
lme_stats.posthoc       = posthoc;
lme_stats.alpha         = alpha;
lme_stats.window_label  = window_label;
lme_stats.settings      = settings;

save(fullfile(OUTPUT_DIR, [output_name '.mat']), ...
    'lme_stats', 'posthoc', 'power_matrix', 'T', 'window_label', ...
    'subject_data', 'matched_channels', 'settings', '-v7.3');

write_stats_text_report(fullfile(OUTPUT_DIR, [output_name '_stats.txt']), ...
    model_formula, fit_method, lme, lme_anova, posthoc, window_label, ...
    length(categories(T.Subject)), length(categories(T.Electrode)), ...
    settings);

fprintf('\n=== COMPLETE ===\n');
fprintf('Output directory: %s\n', OUTPUT_DIR);
fprintf('Figure: %s.{png,svg,fig}\n', output_name);
fprintf('Stats:  %s.mat, %s_stats.txt\n', output_name, output_name);

end

%% ========================================================================
%  LOCAL HELPERS
%  ========================================================================

function all_data = load_kept_trials(tfr_path, participants, session, ...
    conditions, trial_indices, time_range, freq_range)
% Read per-trial TFR files for each (subject, condition), keeping only the
% trials listed in trial_indices.(sub).(cond).kept. Produces the same
% structure as spindlePilot_visual_topographyTFR_load, so that
% compute_from_filtered can consume it directly.
    EXCLUDE_CHANNELS = {'ROCA1','ROCA2','LOCA1','LOCA2','XX','XXX', ...
        'EOG','HEOG','VEOG','ECG','ECG1','ECG2','EMG','EMG1','EMG2','EMG1EMG2'};

    all_data = struct();
    total_loaded = 0;

    for p = 1:length(participants)
        sub = participants{p};
        for c = 1:length(conditions)
            cond = conditions{c};

            if ~isfield(trial_indices, sub) || ~isfield(trial_indices.(sub), cond)
                continue;
            end
            if ~isfield(trial_indices.(sub).(cond), 'kept')
                fprintf('  [skip] %s %s: no .kept field in trial_indices\n', sub, cond);
                continue;
            end
            kept = trial_indices.(sub).(cond).kept;
            if isempty(kept), continue; end

            files = dir(fullfile(tfr_path, sprintf('TFR_SP_trial_%s_%s_%s_*.mat', ...
                sub, session, cond)));
            if isempty(files)
                fprintf('  [skip] %s %s: no TFR files on disk\n', sub, cond);
                continue;
            end

            channels    = {};
            freq_axis   = [];
            time_axis   = [];
            trial_buf   = [];
            filled_rows = false(length(kept), 1);

            for f = 1:length(files)
                tk = regexp(files(f).name, '_(\d+)\.mat$', 'tokens');
                if isempty(tk), continue; end
                trial_num = str2double(tk{1}{1});
                idx = find(kept == trial_num, 1);
                if isempty(idx), continue; end

                tfr = extract_tfr_struct(load(fullfile(tfr_path, files(f).name)));

                keep_ch = setdiff(tfr.label, EXCLUDE_CHANNELS, 'stable');
                ch_idx  = find(ismember(tfr.label, keep_ch));
                if isempty(ch_idx), continue; end
                tfr.label = tfr.label(ch_idx);
                if ndims(tfr.powspctrm) == 4
                    tfr.powspctrm = tfr.powspctrm(:, ch_idx, :, :);
                else
                    tfr.powspctrm = tfr.powspctrm(ch_idx, :, :);
                end

                fi = tfr.freq >= freq_range(1) & tfr.freq <= freq_range(2);
                ti = tfr.time >= time_range(1) & tfr.time <= time_range(2);
                if ~any(fi) || ~any(ti), continue; end

                if ndims(tfr.powspctrm) == 4
                    slice = squeeze(tfr.powspctrm(1, :, fi, ti));
                else
                    slice = tfr.powspctrm(:, fi, ti);
                end

                if isempty(channels)
                    channels   = tfr.label;
                    freq_axis  = tfr.freq(fi);
                    time_axis  = tfr.time(ti);
                    trial_buf  = zeros(length(kept), length(channels), ...
                        length(freq_axis), length(time_axis));
                end

                trial_buf(idx, :, :, :) = slice; %#ok<AGROW> allocated once on first pass
                filled_rows(idx) = true;
            end

            if ~any(filled_rows), continue; end
            all_data.(sub).(cond).trials   = trial_buf(filled_rows, :, :, :);
            all_data.(sub).(cond).channels = channels;
            all_data.(sub).(cond).freq     = freq_axis;
            all_data.(sub).(cond).time     = time_axis;

            n_ok = sum(filled_rows);
            total_loaded = total_loaded + n_ok;
            fprintf('  %s %s: %d/%d kept trials loaded\n', ...
                sub, cond, n_ok, length(kept));
        end
    end
    fprintf('Total kept trials loaded: %d\n', total_loaded);
end


function posthoc = run_posthoc_contrasts(lme, T, conditions, n_cond)
% Pairwise Condition contrasts via coefTest, with Holm-Bonferroni.
    cond_cats = categories(T.Condition);
    fe        = fixedEffects(lme);
    cov_mat   = lme.CoefficientCovariance;
    pooled_sd = std(T.Power);

    n_comp = n_cond * (n_cond - 1) / 2;
    posthoc = struct('pairs', cell(1, n_comp), 'cond1', cell(1, n_comp), ...
        'cond2', cell(1, n_comp), 'estimate', cell(1, n_comp), ...
        'se', cell(1, n_comp), 'df', cell(1, n_comp), 't', cell(1, n_comp), ...
        'p_uncorr', cell(1, n_comp), 'p_holm', cell(1, n_comp), 'd', cell(1, n_comp));

    k = 0;
    for i = 1:n_cond-1
        for j = i+1:n_cond
            k = k + 1;
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
            [p_val, F_val, ~, df_den] = coefTest(lme, H);
            t_val = sign(H * fe) * sqrt(F_val);
            est   = H * fe;
            se    = sqrt(H * cov_mat * H');
            posthoc(k).pairs    = [i j];
            posthoc(k).cond1    = conditions{i};
            posthoc(k).cond2    = conditions{j};
            posthoc(k).estimate = est;
            posthoc(k).se       = se;
            posthoc(k).df       = df_den;
            posthoc(k).t        = t_val;
            posthoc(k).p_uncorr = p_val;
            posthoc(k).d        = est / pooled_sd;
        end
    end

    % Holm-Bonferroni
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
end


function write_stats_text_report(path, formula, fit_method, lme, lme_anova, ...
    posthoc, window_label, n_subj, n_elec, settings)
    fid = fopen(path, 'w');
    cleanupObj = onCleanup(@() fclose(fid));  % close fid when function exits

    fprintf(fid, '========================================\n');
    fprintf(fid, 'FIGURE 2: %s POWER BARPLOT\n', upper(window_label));
    fprintf(fid, 'LME + ANOVA + Holm-corrected pairwise contrasts\n');
    fprintf(fid, '========================================\n\n');
    fprintf(fid, 'Generated: %s\n\n', char(datetime('now')));

    fprintf(fid, '--- Trial selection ---\n');
    fprintf(fid, 'Kept-trial list loaded from:\n  %s\n', settings.trial_indices_source);
    fprintf(fid, '(produced by figure2_topography.m; no filters were re-applied here)\n\n');

    fprintf(fid, '--- Analysis window ---\n');
    win = settings.time_freq_window;
    fprintf(fid, 'Frequency: %.1f - %.1f Hz\n', win{1}, win{2});
    fprintf(fid, 'Time:      %.2f - %.2f s\n',  win{3}, win{4});
    fprintf(fid, 'Label:     %s\n\n', win{5});

    fprintf(fid, '--- Processing on kept trials ---\n');
    fprintf(fid, 'Log-transform: %s (10*log10 -> dB)\n', yes_no(settings.log_transform));
    fprintf(fid, 'Summary:       %s (trim %d%%)\n\n', ...
        settings.summary_method, settings.trimmed_mean_percent);

    fprintf(fid, '--- Model ---\n');
    fprintf(fid, 'Formula:     %s\n', formula);
    fprintf(fid, 'Fit method:  %s\n', fit_method);
    fprintf(fid, 'Observations: %d | Subjects: %d | Electrodes: %d\n\n', ...
        lme.NumObservations, n_subj, n_elec);
    fprintf(fid, 'AIC = %.2f   BIC = %.2f   LogLikelihood = %.2f\n\n', ...
        lme.ModelCriterion.AIC, lme.ModelCriterion.BIC, lme.LogLikelihood);

    fprintf(fid, '--- ANOVA (Type III) ---\n');
    for i = 1:height(lme_anova)
        fprintf(fid, '%-15s F(%d,%.1f) = %.3f, p = %.4f\n', ...
            lme_anova.Term{i}, lme_anova.DF1(i), lme_anova.DF2(i), ...
            lme_anova.FStat(i), lme_anova.pValue(i));
    end

    fprintf(fid, '\n--- Post-hoc Contrasts (Holm-Bonferroni) ---\n');
    fprintf(fid, '%-18s %9s %9s %9s %9s %9s %9s %9s\n', ...
        'Comparison','Est(dB)','SE','t','df','p(un)','p(Holm)','Cohen d');
    for k = 1:length(posthoc)
        fprintf(fid, '%-18s %9.3f %9.3f %9.3f %9.1f %9.4f %9.4f %9.3f\n', ...
            sprintf('%s vs %s', posthoc(k).cond1, posthoc(k).cond2), ...
            posthoc(k).estimate, posthoc(k).se, posthoc(k).t, posthoc(k).df, ...
            posthoc(k).p_uncorr, posthoc(k).p_holm, posthoc(k).d);
    end
end


function s = yes_no(tf)
    if tf, s = 'yes'; else, s = 'no'; end
end
