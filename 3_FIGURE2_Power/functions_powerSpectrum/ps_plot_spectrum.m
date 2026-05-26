function fig = ps_plot_spectrum(condition_stats, conditions_to_compare, freq, ...
        freq_range, spindle_band, artifact_band, cluster_results, ...
        cluster_cfg, subjects_used, channels_to_plot_resolved, pub, show_shaded_error)
%PS_PLOT_SPECTRUM Plot power spectra with frequency bands and cluster markers.
%
%   fig = ps_plot_spectrum(condition_stats, conditions_to_compare, freq,
%       freq_range, spindle_band, artifact_band, cluster_results,
%       cluster_cfg, subjects_used, channels_to_plot_resolved, pub, show_shaded_error)

    %% Condition appearance
    colors = struct('x5HZ', [1 0.55 0], 'x1HZ', [0 0.2 0.6], 'OFF', [0.6 0.6 0.6]);
    display_names = struct('x5HZ', '5 Hz', 'x1HZ', '1 Hz', 'OFF', 'OFF');

    % Display mapping for cluster comparison labels
    comp_display = {'5Hz', 'OFF'; '1Hz', 'OFF'; '5Hz', '1Hz'};

    %% Compute y-limits
    freq_mask = freq >= freq_range(1) & freq <= freq_range(2);
    y_lim = [Inf, -Inf];
    for c = 1:length(conditions_to_compare)
        cond = conditions_to_compare{c};
        if ~isfield(condition_stats, cond), continue; end
        mean_db = condition_stats.(cond).mean_pxx_db;
        y_lim(1) = min(y_lim(1), min(mean_db(freq_mask)));
        y_lim(2) = max(y_lim(2), max(mean_db(freq_mask)));
    end
    y_range = y_lim(2) - y_lim(1);
    y_lim = [y_lim(1) - 0.1*y_range, y_lim(2) + 0.1*y_range];

    %% Create figure
    fig = figure('Units', 'centimeters', ...
        'Position', [5 5 pub.fig_width_cm pub.fig_height_cm], ...
        'Color', 'white', ...
        'PaperUnits', 'centimeters', ...
        'PaperSize', [pub.fig_width_cm pub.fig_height_cm], ...
        'PaperPosition', [0 0 pub.fig_width_cm pub.fig_height_cm]);
    hold on;

    % Frequency band highlights
    draw_band(spindle_band, y_lim, [0.95 0.95 0.85]);
    draw_band(artifact_band, y_lim, [1.0 0.8 0.8]);

    % Power spectrum lines
    for c = 1:length(conditions_to_compare)
        cond = conditions_to_compare{c};
        if ~isfield(condition_stats, cond), continue; end

        mean_db = condition_stats.(cond).mean_pxx_db;
        sem_db  = condition_stats.(cond).sem_pxx_db;

        plot(freq(freq_mask), mean_db(freq_mask), ...
            'Color', colors.(cond), 'LineWidth', pub.line_width, ...
            'DisplayName', display_names.(cond));

        if show_shaded_error
            fv = freq(freq_mask); fv = fv(:)';
            mv = mean_db(freq_mask); mv = mv(:)';
            sv = sem_db(freq_mask);  sv = sv(:)';
            fill([fv fliplr(fv)], [mv+sv fliplr(mv-sv)], ...
                colors.(cond), 'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
                'HandleVisibility', 'off');
        end
    end

    %% Cluster significance bars
    if ~isempty(cluster_results)
        bar_height  = 0.012 * y_range;
        bar_gap     = 0.02 * y_range;
        bar_y_start = y_lim(1) + 0.015 * y_range;
        comp_fields = fieldnames(cluster_results);

        for comp = 1:length(comp_fields)
            res = cluster_results.(comp_fields{comp});
            bar_y = bar_y_start + (comp - 1) * (bar_height + bar_gap);

            disp_A = comp_display{comp, 1};
            disp_B = comp_display{comp, 2};

            draw_sig_bars(res.pos_clusters, res.pos_cluster_p, res.freq, ...
                bar_y, bar_height, cluster_cfg.cluster_alpha, ...
                sprintf('%s > %s', disp_A, disp_B), pub);
            draw_sig_bars(res.neg_clusters, res.neg_cluster_p, res.freq, ...
                bar_y, bar_height, cluster_cfg.cluster_alpha, ...
                sprintf('%s > %s', disp_B, disp_A), pub);
        end
    end

    hold off;

    %% Formatting
    set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
        'Box', 'off', 'TickDir', 'out');
    xlabel('Frequency (Hz)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
    ylabel('Power (dB)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
    xlim(freq_range);
    ylim(y_lim);
    grid on;
    legend('Location', 'northeast', 'FontName', pub.font_name, ...
        'FontSize', pub.font_size_axis, 'Box', 'off');

    % Title
    n_ch = length(channels_to_plot_resolved);
    if n_ch == 1
        ch_str = channels_to_plot_resolved{1};
    else
        ch_str = sprintf('%d channels', n_ch);
    end
    if length(subjects_used) == 1
        title_str = sprintf('Power Spectrum - %s (%s, N2)', subjects_used{1}, ch_str);
    else
        title_str = sprintf('Power Spectrum - %d subjects (%s, N2)', length(subjects_used), ch_str);
    end
    title(title_str, 'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

    % Band annotations
    text(mean(spindle_band), y_lim(2) - 0.05*y_range, 'Spindle', ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_axis-1, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
        'Color', [0.5 0.5 0]);
    text(mean(artifact_band), y_lim(2) - 0.05*y_range, '5Hz', ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_axis-1, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
        'Color', [0.6 0.2 0.2]);
end


%% ---- Local helpers ----

function draw_band(band, y_lim, color)
    patch([band(1) band(2) band(2) band(1)], ...
        [y_lim(1) y_lim(1) y_lim(2) y_lim(2)], ...
        color, 'EdgeColor', 'none', 'FaceAlpha', 0.3, 'HandleVisibility', 'off');
end


function draw_sig_bars(clusters, p_vals, freq_vec, bar_y, bar_height, alpha, label, pub)
    for cl = 1:length(p_vals)
        if p_vals(cl) < alpha
            cl_freqs = freq_vec(clusters{cl});
            fill([min(cl_freqs) max(cl_freqs) max(cl_freqs) min(cl_freqs)], ...
                [bar_y bar_y bar_y+bar_height bar_y+bar_height], ...
                [0 0 0], 'EdgeColor', 'none', 'FaceAlpha', 0.8, 'HandleVisibility', 'off');
            text(max(cl_freqs) + 0.15, bar_y + bar_height/2, label, ...
                'FontName', pub.font_name, 'FontSize', pub.font_size_axis-2, ...
                'VerticalAlignment', 'middle', 'Color', [0 0 0], 'Clipping', 'on');
        end
    end
end
