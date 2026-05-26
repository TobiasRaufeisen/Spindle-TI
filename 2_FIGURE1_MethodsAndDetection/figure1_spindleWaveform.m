function figure1_spindleWaveform()
%% FIGURE 1: Average Spindle Waveform Per Condition
% Shows the average spindle waveform aligned to peak for each condition
% (OFF, 1Hz, 5Hz) across specified electrodes or averaged across electrodes.
%
% This demonstrates the characteristic spindle morphology and compares
% spindle waveforms across stimulation conditions.

clear; clc;
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
%% Configuration
PROCESSED_DATA_DIR = fullfile(REPO_ROOT, 'data');  % in-repo, gitignored (see README "Data Availability")
RESULTS_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
OUTPUT_DIR = fullfile(REPO_ROOT, '2_FIGURE1_MethodsAndDetection', 'outputs');

% Analysis parameters
conditions = {'x1HZ', 'x5HZ', 'OFF'};
condition_labels = {'1 Hz', '5 Hz', 'OFF'};
electrodes = {'Cz', 'C3', 'C4', 'CP1', 'CP2', 'FC1', 'FC2'};  % Options: 'all', {}, or specific electrodes: {'Cz', 'C3', 'C4'}
sleep_stages = {'N2'};
session = 'ses1';

% Spindle parameters
spindle_window = [-0.5, 0.5];  % seconds around peak
spindle_freq_range = [12, 16]; % fast spindles
spindle_min_amplitude = 15;
spindle_max_amplitude = 100;
spindle_min_duration = 0.5;    % minimum spindle duration in seconds
spindle_max_duration = 3.0;    % maximum spindle duration in seconds
min_events_per_subject = 20;

% Handle 'all' electrodes option
if ischar(electrodes) && strcmpi(electrodes, 'all')
    electrodes = {};  % Empty cell array means use all electrodes
end

fprintf('=== FIGURE 1: Average Spindle Waveform ===\n');
if isempty(electrodes)
    fprintf('Electrodes: All electrodes\n');
else
    fprintf('Electrodes: %s\n', strjoin(electrodes, ', '));
end
fprintf('Conditions: %s\n', strjoin(conditions, ', '));

%% Load comprehensive analysis data
comprehensive_file = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');
fprintf('\nLoading spindle data from: %s\n', comprehensive_file);
if ~exist(comprehensive_file, 'file')
    error('Comprehensive analysis file not found: %s', comprehensive_file);
end
load(comprehensive_file, 'all_spindles', 'subjects');
fprintf('Loaded %d spindles across %d subjects\n', height(all_spindles), length(subjects));

% Get list of analysis files
fprintf('\n=== FINDING ANALYSIS FILES ===\n');
analysis_path = fullfile(PROCESSED_DATA_DIR, 'analysis');
analysis_files = dir(fullfile(analysis_path, '*_ANALYSIS.mat'));

if isempty(analysis_files)
    error('No analysis files found in %s', analysis_path);
end

% Prepare parameters
spindle_params = struct();
spindle_params.window = spindle_window;
spindle_params.freq_range = spindle_freq_range;
spindle_params.min_amplitude = spindle_min_amplitude;
spindle_params.max_amplitude = spindle_max_amplitude;
spindle_params.min_duration = spindle_min_duration;
spindle_params.max_duration = spindle_max_duration;
spindle_params.sleep_stages = sleep_stages;
spindle_params.electrodes = electrodes;
spindle_params.min_events_per_subject = min_events_per_subject;

% Process subjects one at a time (memory-friendly approach)
fprintf('\n=== PROCESSING SUBJECTS ONE AT A TIME ===\n');
spindle_averages = initialize_averages(conditions);

for f = 1:length(analysis_files)
    filename = analysis_files(f).name;
    filepath = fullfile(analysis_path, filename);

    tokens = regexp(filename, '(sub\d+)_ses\d+_ANALYSIS\.mat', 'tokens');
    if isempty(tokens), continue; end

    subj_id = tokens{1}{1};

    % Load only this subject's data
    loaded = load(filepath, 'analysisData_saved');
    if ~isfield(loaded, 'analysisData_saved'), continue; end

    analysis_data = loaded.analysisData_saved;
    if ~isfield(analysis_data, subj_id), continue; end

    subj_data = analysis_data.(subj_id);
    if ~isfield(subj_data, session), continue; end

    session_data = subj_data.(session);
    if ~isfield(session_data, 'eeg') || ~isfield(session_data, 'epochedData'), continue; end

    % Filter spindles for this subject
    subj_spindles = all_spindles(strcmp(all_spindles.Subject, subj_id), :);
    if isempty(subj_spindles)
        fprintf('  %s: No spindles found, skipping\n', subj_id);
        continue;
    end

    session_data.spindles = subj_spindles;

    fprintf('  Processing %s: %d channels, %d spindles\n', ...
        subj_id, length(session_data.eeg.label), height(subj_spindles));

    % Process this subject and accumulate results
    spindle_averages = process_single_subject(spindle_averages, subj_id, session_data, conditions, spindle_params);

    % Clear loaded data to free memory
    clear loaded analysis_data subj_data session_data subj_spindles;
end

% Compute grand averages across all subjects
spindle_averages = compute_grand_averages(spindle_averages, conditions, spindle_params);

%% Create figure
% Publication settings
pub = struct();
pub.fig_width_cm = 7;
pub.fig_height_cm = 5;
pub.font_name = 'Arial';
pub.font_size_axis = 9;
pub.font_size_label = 11;
pub.font_size_title = 9;
pub.font_size_legend = 9;
pub.line_width = 1;
pub.plot_error_bars = true;  % Show SEM shaded error bars
pub.colors = struct();
pub.colors.x1HZ = [0.00, 0.20, 0.60];    % Dark Blue (1 Hz)
pub.colors.x5HZ = [1.00, 0.55, 0.00];    % Orange (5 Hz)
pub.colors.OFF = [0.55, 0.55, 0.55];     % Gray (OFF)

fprintf('\n=== CREATING FIGURE ===\n');

fig = figure('Units', 'centimeters', ...
             'Position', [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color', 'white', ...
             'PaperUnits', 'centimeters', ...
             'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% Determine plotting mode
plot_individual_electrodes = ~isempty(electrodes) && length(electrodes) <= 3;

if plot_individual_electrodes
    % Create subplots for each electrode
    n_electrodes = length(electrodes);
    n_cols = min(3, n_electrodes);
    n_rows = ceil(n_electrodes / n_cols);

    for e = 1:n_electrodes
        subplot(n_rows, n_cols, e);
        hold on;

        electrode = electrodes{e};

        % Plot each condition
        for c = 1:length(conditions)
            cond = conditions{c};

            if ~isfield(spindle_averages, cond) || isempty(spindle_averages.(cond))
                continue;
            end

            avg = spindle_averages.(cond);

            % Find the electrode index
            elec_idx = find(strcmp(avg.label, electrode));

            if isempty(elec_idx)
                continue;
            end

            % Extract data for this electrode
            electrode_data = avg.data(elec_idx, :);

            if pub.plot_error_bars && isfield(avg, 'sem')
                electrode_sem = avg.sem(elec_idx, :);
                shadedErrorBar(avg.time * 1000, electrode_data, electrode_sem, ...
                    'lineProps', {'LineWidth', pub.line_width, 'Color', pub.colors.(cond), ...
                    'DisplayName', condition_labels{c}}, ...
                    'transparent', true);
            else
                plot(avg.time * 1000, electrode_data, 'LineWidth', pub.line_width, ...
                    'Color', pub.colors.(cond), 'DisplayName', condition_labels{c});
            end
        end

        % Formatting
        xline(0, 'k--', 'LineWidth', 1.0, 'HandleVisibility', 'off');
        xlabel('Time (ms)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
        ylabel('Amplitude (\muV)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
        title(sprintf('Electrode: %s', electrode), 'FontName', pub.font_name, ...
            'FontSize', pub.font_size_title, 'FontWeight', 'bold');
        legend('Location', 'best', 'FontName', pub.font_name, 'FontSize', pub.font_size_legend);
        set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
                 'Box', 'off', 'TickDir', 'out');
        yl = ylim; max_abs = max(abs(yl)); ylim([-max_abs, max_abs]);
        grid on;
        hold off;
    end

    sgtitle('Average Spindle Waveform Per Condition', ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_title + 2, 'FontWeight', 'bold');

else
    % Create single plot with averaged data across all electrodes
    hold on;

    for c = 1:length(conditions)
        cond = conditions{c};

        if ~isfield(spindle_averages, cond) || isempty(spindle_averages.(cond))
            continue;
        end

        avg = spindle_averages.(cond);

        % Average across all electrodes
        grand_avg = mean(avg.data, 1);

        if pub.plot_error_bars && isfield(avg, 'sem')
            % Average SEM across electrodes
            grand_sem = mean(avg.sem, 1);
            shadedErrorBar(avg.time * 1000, grand_avg, grand_sem, ...
                'lineProps', {'LineWidth', pub.line_width, 'Color', pub.colors.(cond), ...
                'DisplayName', condition_labels{c}}, ...
                'transparent', true);
        else
            plot(avg.time * 1000, grand_avg, 'LineWidth', pub.line_width, ...
                'Color', pub.colors.(cond), 'DisplayName', condition_labels{c});
        end
    end

    % Formatting
    xline(0, 'k--', 'LineWidth', 1.0, 'HandleVisibility', 'off');
    xlabel('Time (ms)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
    ylabel('Amplitude (\muV)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
    title('Average Spindle Waveform Per Condition', ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

    legend('Location', 'best', 'FontName', pub.font_name, 'FontSize', pub.font_size_legend);
    set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
             'Box', 'off', 'TickDir', 'out');
    yl = ylim; max_abs = max(abs(yl)); ylim([-max_abs, max_abs]);
    grid on;
    hold off;
end

%% Save figure
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

filename_base = 'figure1_spindleWaveform';
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

% Save data
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'spindle_averages', 'conditions', 'electrodes', 'spindle_window', ...
     'spindle_params', 'pub');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('=== Done ===\n');

end

%% Helper Functions

function averages = initialize_averages(conditions)
    % Initialize the averages structure for accumulating results
    averages = struct();
    for c = 1:length(conditions)
        cond = conditions{c};
        averages.(cond) = struct();
        averages.(cond).label = {};
        averages.(cond).per_subject = struct();
    end
end

function averages = process_single_subject(averages, subj_id, session_data, conditions, event_params)
    % Process a single subject and accumulate results (memory-friendly)

    % Common time axis for interpolation
    n_samples = 200;
    common_time = linspace(event_params.window(1), event_params.window(2), n_samples);

    if ~isfield(session_data, 'spindles')
        return;
    end

    events = session_data.spindles;
    eeg = session_data.eeg;

    % Filter spindles
    valid_mask = events.Frequency >= event_params.freq_range(1) & ...
                 events.Frequency <= event_params.freq_range(2) & ...
                 events.Amplitude >= event_params.min_amplitude & ...
                 events.Amplitude <= event_params.max_amplitude & ...
                 events.Duration >= event_params.min_duration & ...
                 events.Duration <= event_params.max_duration & ...
                 ismember(events.SleepStage, event_params.sleep_stages);

    valid_events = events(valid_mask, :);

    if isempty(valid_events)
        fprintf('    %s: No valid events\n', subj_id);
        return;
    end

    % Process each condition
    for c = 1:length(conditions)
        cond = conditions{c};
        cond_events = valid_events(strcmp(valid_events.Condition, cond), :);

        if isempty(cond_events), continue; end

        % Pre-select electrodes if specified
        if isfield(event_params, 'electrodes') && ~isempty(event_params.electrodes)
            [~, chan_idx] = ismember(event_params.electrodes, eeg.label);
            chan_idx = chan_idx(chan_idx > 0);
            if isempty(chan_idx), continue; end
            selected_labels = eeg.label(chan_idx);
        else
            chan_idx = 1:length(eeg.label);
            selected_labels = eeg.label;
        end

        % Get continuous data
        eeg_time = eeg.time{1};
        eeg_matrix = eeg.trial{1}(chan_idx, :);
        n_channels = size(eeg_matrix, 1);

        % Initialize sum array
        if isempty(averages.(cond).label)
            averages.(cond).label = selected_labels;
        end
        subj_sum = zeros(n_channels, n_samples);
        subj_count = 0;

        % Extract segments
        fs = 1 / mean(diff(eeg_time));

        % Process each event
        for ev = 1:height(cond_events)
            event_time = cond_events.Peak(ev);

            % Find closest sample to event time
            [~, center_idx] = min(abs(eeg_time - event_time));

            % Calculate sample window
            start_offset = round(event_params.window(1) * fs);
            end_offset = round(event_params.window(2) * fs);

            start_idx = center_idx + start_offset;
            end_idx = center_idx + end_offset;

            % Check bounds
            if start_idx < 1 || end_idx > length(eeg_time)
                continue;
            end

            % Extract segment
            segment_data = eeg_matrix(:, start_idx:end_idx);
            segment_time = eeg_time(start_idx:end_idx) - event_time;

            % Quick check for minimum length
            if size(segment_data, 2) < 10
                continue;
            end

            % Interpolate to common time axis (vectorized across channels)
            for ch = 1:n_channels
                interp_data = interp1(segment_time, segment_data(ch, :), common_time, 'linear', 'extrap');
                subj_sum(ch, :) = subj_sum(ch, :) + interp_data;
            end

            subj_count = subj_count + 1;
        end

        % Store per-subject average (only average, not raw data)
        if subj_count >= event_params.min_events_per_subject
            averages.(cond).per_subject.(subj_id).avg = subj_sum / subj_count;
            averages.(cond).per_subject.(subj_id).n_events = subj_count;
            fprintf('    %s - %s: %d events averaged\n', subj_id, cond, subj_count);
        elseif subj_count > 0
            fprintf('    %s - %s: %d events (excluded: < %d threshold)\n', ...
                subj_id, cond, subj_count, event_params.min_events_per_subject);
        end
    end
end

function averages = compute_grand_averages(averages, conditions, event_params)
    % Compute grand averages across all subjects

    n_samples = 200;
    common_time = linspace(event_params.window(1), event_params.window(2), n_samples);

    fprintf('\n=== COMPUTING GRAND AVERAGES ===\n');
    for c = 1:length(conditions)
        cond = conditions{c};
        subj_names = fieldnames(averages.(cond).per_subject);

        if isempty(subj_names)
            fprintf('  %s: No data available\n', cond);
            averages.(cond) = [];
            continue;
        end

        % Initialize grand average
        n_channels = size(averages.(cond).per_subject.(subj_names{1}).avg, 1);
        n_subjects = length(subj_names);
        grand_avg = zeros(n_channels, n_samples);
        total_events = 0;

        % Stack subject data for variance calculation
        subj_data_stack = zeros(n_channels, n_samples, n_subjects);

        % Average across subjects
        for subj_idx = 1:n_subjects
            subj = subj_names{subj_idx};
            subj_avg = averages.(cond).per_subject.(subj).avg;
            grand_avg = grand_avg + subj_avg;
            subj_data_stack(:, :, subj_idx) = subj_avg;
            total_events = total_events + averages.(cond).per_subject.(subj).n_events;
        end

        grand_avg = grand_avg / n_subjects;

        % Calculate SEM across participants
        subj_std = std(subj_data_stack, 0, 3);
        subj_sem = subj_std / sqrt(n_subjects);

        % Package results
        averages.(cond).time = common_time;
        averages.(cond).data = grand_avg;
        averages.(cond).sem = subj_sem;
        averages.(cond).n_events = total_events;
        averages.(cond).n_subjects = n_subjects;

        fprintf('  %s: %d events from %d subjects\n', cond, total_events, n_subjects);
    end
end
