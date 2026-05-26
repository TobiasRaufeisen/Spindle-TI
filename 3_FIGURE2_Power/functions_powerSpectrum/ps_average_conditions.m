function [condition_stats, plot_ch_indices, channels_to_plot_resolved] = ps_average_conditions( ...
        spectra_data, freq, conditions_to_compare, channels_computed, ...
        channels_to_plot, subjects_used)
%PS_AVERAGE_CONDITIONS Average selected channels per subject and compute grand means.
%
%   [condition_stats, plot_ch_indices, channels_to_plot_resolved] = ps_average_conditions(...)
%
%   For each condition, averages the selected channels within each subject,
%   then computes the grand mean and SEM across subjects.
%
%   Outputs:
%     condition_stats            - struct per condition with mean_pxx_db, sem_pxx_db,
%                                  per_subject_db, freq, n_subjects
%     plot_ch_indices            - indices into channels_computed used for plotting
%     channels_to_plot_resolved  - resolved channel label list

    %% Resolve channel selection
    if ischar(channels_to_plot) && strcmpi(channels_to_plot, 'all')
        plot_ch_indices = 1:length(channels_computed);
        channels_to_plot_resolved = channels_computed;
    else
        plot_ch_indices = [];
        channels_to_plot_resolved = {};
        for ch = 1:length(channels_to_plot)
            idx = find(strcmp(channels_computed, channels_to_plot{ch}));
            if ~isempty(idx)
                plot_ch_indices(end+1) = idx; %#ok<AGROW>
                channels_to_plot_resolved{end+1} = channels_to_plot{ch}; %#ok<AGROW>
            else
                warning('Channel %s not in computed channels.', channels_to_plot{ch});
            end
        end
    end

    fprintf('\nAveraging channels for plot: %s\n', strjoin(channels_to_plot_resolved, ', '));
    fprintf('Averaging across %d subjects: %s\n', length(subjects_used), strjoin(subjects_used, ', '));

    %% Compute per-condition grand average
    condition_stats = struct();

    for c = 1:length(conditions_to_compare)
        cond_name = conditions_to_compare{c};
        subj_data = spectra_data.(cond_name).per_subject_channel_db;

        if isempty(subj_data)
            warning('No data for condition %s. Skipping.', cond_name);
            continue;
        end

        n_subj  = length(subj_data);
        n_freqs = size(subj_data{1}, 2);

        % Average selected channels within each subject -> [n_subjects x n_freqs]
        subj_matrix = NaN(n_subj, n_freqs);
        for si = 1:n_subj
            subj_matrix(si, :) = mean(subj_data{si}(plot_ch_indices, :), 1, 'omitnan');
        end

        grand_mean = mean(subj_matrix, 1);
        if n_subj > 1
            grand_sem = std(subj_matrix, 0, 1) / sqrt(n_subj);
        else
            grand_sem = zeros(size(grand_mean));
        end

        condition_stats.(cond_name).mean_pxx_db    = grand_mean;
        condition_stats.(cond_name).sem_pxx_db     = grand_sem;
        condition_stats.(cond_name).freq           = freq;
        condition_stats.(cond_name).n_subjects     = n_subj;
        condition_stats.(cond_name).per_subject_db = subj_matrix;

        fprintf('%s: grand average from %d subjects, %.1f-%.1f Hz\n', ...
                cond_name, n_subj, min(freq), max(freq));
    end

    if isempty(fieldnames(condition_stats))
        error('No valid data found for any condition.');
    end
end
