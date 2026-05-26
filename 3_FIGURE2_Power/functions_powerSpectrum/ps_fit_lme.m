function lme_results = ps_fit_lme(spectra_data, freq, conditions_to_compare, ...
        channels_computed, plot_ch_indices, subjects_used, electrode_handling)
%PS_FIT_LME Fit linear mixed-effects models on band-averaged power.
%
%   lme_results = ps_fit_lme(spectra_data, freq, conditions_to_compare,
%       channels_computed, plot_ch_indices, subjects_used, electrode_handling)
%
%   For each analysis band (Spindle 12-16 Hz, Artifact 4.5-5.5 Hz), builds a
%   long-format table and fits an LME with Holm-corrected post-hoc comparisons.
%
%   electrode_handling: 'average' collapses electrodes per subject,
%                       'random' adds (1|Electrode) as random effect.

    fprintf('\n=== Statistical Analysis: Linear Mixed-Effects Models ===\n');

    % Ensure subject labels exist (backward-compatible with older caches)
    for c = 1:length(conditions_to_compare)
        cond = conditions_to_compare{c};
        if isfield(spectra_data, cond) && ...
                (~isfield(spectra_data.(cond), 'subject_labels') || ...
                 isempty(spectra_data.(cond).subject_labels))
            n_entries = length(spectra_data.(cond).per_subject_channel_db);
            spectra_data.(cond).subject_labels = subjects_used(1:n_entries);
        end
    end

    % Frequency bands
    analysis_bands = struct('name', {'Spindle', 'Artifact'}, ...
                            'range', {[12, 16], [4.5, 5.5]});

    lme_results = struct();

    for b = 1:length(analysis_bands)
        band_name  = analysis_bands(b).name;
        band_range = analysis_bands(b).range;
        band_mask  = freq >= band_range(1) & freq <= band_range(2);

        fprintf('\n--- %s Band (%.1f-%.1f Hz, %d bins) ---\n', ...
            band_name, band_range(1), band_range(2), sum(band_mask));

        % Build long-format table (electrode-level)
        tbl_full = build_electrode_table(spectra_data, conditions_to_compare, ...
            channels_computed, plot_ch_indices, band_mask);

        % Electrode-averaged descriptives
        subj_avg = groupsummary(tbl_full, {'Condition', 'Subject'}, 'mean', 'Power');
        print_descriptives(subj_avg);

        % Select table and formula
        if strcmp(electrode_handling, 'random')
            tbl_lme     = tbl_full;
            formula_str = 'Power ~ Condition + (1|Subject) + (1|Electrode)';
        else
            tbl_lme = table(subj_avg.mean_Power, subj_avg.Condition, subj_avg.Subject, ...
                'VariableNames', {'Power', 'Condition', 'Subject'});
            formula_str = 'Power ~ Condition + (1|Subject)';
        end

        fprintf('Electrode handling: %s\n', electrode_handling);
        fprintf('LME: %d rows  |  %s\n', height(tbl_lme), formula_str);

        % Fit model
        lme = fitlme(tbl_lme, formula_str);
        disp(lme);

        anova_tbl = anova(lme);
        fprintf('Omnibus F-test for Condition:\n');
        disp(anova_tbl);

        % Post-hoc pairwise comparisons (Holm-corrected)
        posthoc = compute_posthoc(lme);

        % Store
        lme_results.(band_name).model        = lme;
        lme_results.(band_name).anova        = anova_tbl;
        lme_results.(band_name).posthoc      = posthoc;
        lme_results.(band_name).descriptives = subj_avg;
        lme_results.(band_name).table        = tbl_full;
        lme_results.(band_name).formula      = formula_str;
        lme_results.(band_name).band_range   = band_range;
    end

    fprintf('\n=== Statistical Analysis Complete ===\n');
end


%% ---- Local helpers ----

function tbl = build_electrode_table(spectra_data, conditions, channels, ch_indices, band_mask)
    Power = []; Condition = {}; Subject = {}; Electrode = {};

    for c = 1:length(conditions)
        cond = conditions{c};
        if ~isfield(spectra_data, cond), continue; end
        subj_spectra = spectra_data.(cond).per_subject_channel_db;
        subj_labels  = spectra_data.(cond).subject_labels;

        for s = 1:length(subj_spectra)
            mat = subj_spectra{s};
            for chi = 1:length(ch_indices)
                ch = ch_indices(chi);
                Power(end+1, 1)     = mean(mat(ch, band_mask), 'omitnan'); %#ok<AGROW>
                Condition{end+1, 1} = cond; %#ok<AGROW>
                Subject{end+1, 1}   = subj_labels{s}; %#ok<AGROW>
                Electrode{end+1, 1} = channels{ch}; %#ok<AGROW>
            end
        end
    end

    tbl = table(Power, categorical(Condition), categorical(Subject), categorical(Electrode), ...
        'VariableNames', {'Power', 'Condition', 'Subject', 'Electrode'});
    tbl.Condition = reordercats(tbl.Condition, {'OFF', 'x1HZ', 'x5HZ'});
end


function print_descriptives(subj_avg)
    fprintf('\nCondition means (dB, electrode-averaged per subject):\n');
    cats = categories(subj_avg.Condition);
    for ci = 1:length(cats)
        vals = subj_avg.mean_Power(subj_avg.Condition == cats{ci});
        fprintf('  %-5s: M = %7.2f, SD = %5.2f  (n = %d)\n', ...
            cats{ci}, mean(vals), std(vals), length(vals));
    end
end


function posthoc = compute_posthoc(lme)
    [beta, ~, ~] = fixedEffects(lme);
    covB = lme.CoefficientCovariance;

    % Contrasts (reference = OFF): [Intercept, x1HZ, x5HZ]
    H = [0  1  0;    % x1HZ - OFF
         0  0  1;    % x5HZ - OFF
         0 -1  1];   % x5HZ - x1HZ
    pair_labels = {'x1HZ vs OFF', 'x5HZ vs OFF', 'x5HZ vs x1HZ'};
    n_pairs = size(H, 1);

    est    = H * beta;
    p_raw  = zeros(n_pairs, 1);
    t_vals = zeros(n_pairs, 1);
    df_den = zeros(n_pairs, 1);

    for i = 1:n_pairs
        h = H(i, :);
        se = sqrt(h * covB * h');
        t_vals(i) = est(i) / se;
        [p_raw(i), ~, ~, DF2] = coefTest(lme, h);
        df_den(i) = DF2;
    end

    % Holm-Bonferroni correction
    [p_sorted, sort_idx] = sort(p_raw);
    p_holm = zeros(n_pairs, 1);
    for i = 1:n_pairs
        p_holm(sort_idx(i)) = min(1, p_sorted(i) * (n_pairs - i + 1));
    end
    for i = 2:n_pairs
        if p_holm(sort_idx(i)) < p_holm(sort_idx(i-1))
            p_holm(sort_idx(i)) = p_holm(sort_idx(i-1));
        end
    end

    fprintf('Post-hoc pairwise comparisons (Holm-corrected):\n');
    fprintf('%-20s  %8s  %8s  %6s  %10s  %10s\n', ...
        'Comparison', 'Est(dB)', 't', 'df', 'p_raw', 'p_holm');
    fprintf('%s\n', repmat('-', 1, 68));
    for i = 1:n_pairs
        fprintf('%-20s  %8.3f  %8.3f  %6.0f  %10.4f  %10.4f\n', ...
            pair_labels{i}, est(i), t_vals(i), df_den(i), p_raw(i), p_holm(i));
    end

    posthoc = struct('pair_labels', {pair_labels}, 'estimates', est, ...
        't_values', t_vals, 'df', df_den, 'p_raw', p_raw, 'p_holm', p_holm);
end
