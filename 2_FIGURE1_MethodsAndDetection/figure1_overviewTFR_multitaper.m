function figure1_overviewTFR_multitaper()
%% FIGURE 1: Whole-Night Overview TFR with Hypnogram
% Computes the full-recording TFR for one representative participant,
% displays the hypnogram below with shared time axis, and shows stimulation
% block onsets as colored bars (Orange=5Hz, Dark Blue=1Hz, Grey=Off).
%
% Features:
% - Multitaper TFR with caching for fast reloading
% - Integrated hypnogram display
% - Stimulation block markers by condition
%
% Purely descriptive -- single participant, no statistics.

clear; clc;

% Configuration
% =========================================================================
% PATHS
% =========================================================================
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
PROCESSED_DATA_DIR = fullfile(REPO_ROOT, 'data');  % in-repo, gitignored (see README "Data Availability")
RESULTS_DIR        = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
OUTPUT_DIR         = fullfile(REPO_ROOT, '2_FIGURE1_MethodsAndDetection', 'outputs');
CACHE_DIR          = fullfile(OUTPUT_DIR, 'cache');
% =========================================================================

% Representative participant
participant = 'sub24';
session     = 'ses1';

% Electrodes to average  (central sites -- standard for sleep)
electrodes  = {'Cz'};

% TFR parameters -- multitaper (DPSS) with fixed 30 s window
freq_range  = [2, 20];   % Hz
foi_step    = 0.2;         % Hz
t_ftimwin   = 30;          % fixed window length  (s) -- matches sleep-epoch duration
taper_bw    = 4;           % time-bandwidth product NW  --  2*NW-1 = 7 tapers  |  freq resolution  2*NW/T -- 0.27 Hz
toi_step    = 15;          % output step size  (s) -- 50 % overlap
use_log     = true;        % true  --  10*log10 (dB)  |  false  --  linear power

% Frequency-band annotation boundaries  (Hz)
band_edges = [0.5, 4, 8, 12, 16, 30];
band_names = {'\delta', '\theta', '\alpha', '\sigma', '\beta'};

% Hypnogram settings
stage_map = containers.Map({'Wake', 'N1', 'N2', 'N3', 'REM'}, [0, 1, 2, 3, -1]);
stage_labels = {'REM', 'Wake', 'N1', 'N2', 'N3'};
stage_values = [-1, 0, 1, 2, 3];
hypno_bin_size_min = 0.5;
hypno_apply_continuity = true;
hypno_continuity_window = 1;
hypno_continuity_outer_window = 3;
hypno_median_filter_width = 11;  % Apply median filter to smooth isolated segments (in bins)

% Stimulation block marker colors
stim_colors = struct();
stim_colors.x5HZ = [1.0, 0.6, 0.0];      % Orange for 5Hz
stim_colors.x1HZ = [0.0, 0.2, 0.6];      % Dark blue for 1Hz
stim_colors.OFF  = [0.5, 0.5, 0.5];      % Grey for Off

% Publication settings
pub = struct();
pub.fig_width_cm  = 17;
pub.fig_height_cm = 12;
pub.font_name     = 'Arial';
pub.font_size_axis  = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;

fprintf('=== FIGURE 1: Whole-Night Overview TFR with Hypnogram ===\n');
fprintf('Participant : %s | Session : %s\n', participant, session);
fprintf('Electrodes  : %s\n\n', strjoin(electrodes, ', '));

% ============================================================
% 1.  LOAD EEG DATA
% ============================================================
fprintf('--- Loading continuous EEG ---\n');
analysis_file = fullfile(PROCESSED_DATA_DIR, 'analysis', ...
                         sprintf('%s_%s_ANALYSIS.mat', participant, session));
if ~exist(analysis_file, 'file')
    error('Analysis file not found: %s', analysis_file);
end

load(analysis_file, 'analysisData_saved');
continuous_eeg = analysisData_saved.(participant).(session).eeg;
epoched        = analysisData_saved.(participant).(session).epochedData;
clear analysisData_saved;

fprintf('  %d channels | %.1f min | %d Hz\n\n', ...
    length(continuous_eeg.label), ...
    (continuous_eeg.time{1}(end) - continuous_eeg.time{1}(1)) / 60, ...
    continuous_eeg.fsample);

% ============================================================
% 2.  EXTRACT STIMULATION BLOCK MARKERS
% ============================================================
fprintf('--- Extracting stimulation block markers ---\n');
stim_conditions = {'x1HZ', 'x5HZ', 'OFF'};  % Only main blocks, not refract
block_markers = [];  % Will store [time_min, condition_idx]

for cond_idx = 1:length(stim_conditions)
    cond_name = stim_conditions{cond_idx};

    if ~isfield(epoched, cond_name)
        continue;
    end

    epoch_data = epoched.(cond_name);

    % Check if block information is available
    if isfield(epoch_data, 'trialinfo') && isfield(epoch_data.trialinfo, 'block')
        % Block info explicitly available
        blocks = epoch_data.trialinfo.block;
        unique_blocks = unique(blocks);

        for block_num = unique_blocks'
            % Find first epoch of this block
            block_epochs = find(blocks == block_num);
            if ~isempty(block_epochs)
                first_epoch = block_epochs(1);
                block_start_sample = epoch_data.sampleinfo(first_epoch, 1);
                block_start_min = (block_start_sample - 1) / continuous_eeg.fsample / 60;
                block_markers = [block_markers; block_start_min, cond_idx]; %#ok<AGROW>
            end
        end
    else
        % Infer blocks from temporal gaps (assuming >30s gap = new block)
        if isfield(epoch_data, 'sampleinfo') && ~isempty(epoch_data.sampleinfo)
            sampleinfo = epoch_data.sampleinfo;

            % First epoch is always a block start
            block_start_sample = sampleinfo(1, 1);
            block_start_min = (block_start_sample - 1) / continuous_eeg.fsample / 60;
            block_markers = [block_markers; block_start_min, cond_idx]; %#ok<AGROW>

            % Detect gaps > 5s between epochs (lowered threshold to catch all blocks)
            for ep = 2:size(sampleinfo, 1)
                gap_samples = sampleinfo(ep, 1) - sampleinfo(ep-1, 2);
                gap_sec = gap_samples / continuous_eeg.fsample;

                if gap_sec > 5  % New block (lowered from 30s to catch consecutive blocks)
                    block_start_sample = sampleinfo(ep, 1);
                    block_start_min = (block_start_sample - 1) / continuous_eeg.fsample / 60;
                    block_markers = [block_markers; block_start_min, cond_idx]; %#ok<AGROW>
                end
            end
        end
    end
end

% Sort by time
if ~isempty(block_markers)
    block_markers = sortrows(block_markers, 1);
    fprintf('  Found %d block markers\n', size(block_markers, 1));
    for i = 1:size(block_markers, 1)
        fprintf('    Block %d: %.1f min - %s\n', i, block_markers(i,1), ...
                stim_conditions{block_markers(i,2)});
    end
else
    fprintf('  Warning: No block markers found\n');
end
fprintf('\n');

% ============================================================
% 3.  COMPUTE OR LOAD CACHED TFR
% ============================================================
if ~exist(CACHE_DIR, 'dir')
    mkdir(CACHE_DIR);
end

% Create cache filename and parameter hash
cache_params = struct();
cache_params.participant = participant;
cache_params.session = session;
cache_params.electrodes = electrodes;
cache_params.freq_range = freq_range;
cache_params.foi_step = foi_step;
cache_params.t_ftimwin = t_ftimwin;
cache_params.taper_bw = taper_bw;
cache_params.toi_step = toi_step;

cache_filename = fullfile(CACHE_DIR, sprintf('tfr_cache_%s_%s.mat', participant, session));

% Try to load cache
use_cached = false;
if exist(cache_filename, 'file')
    fprintf('--- Checking cached TFR ---\n');
    cached = load(cache_filename);

    % Compare parameters
    if isfield(cached, 'cache_params') && isequal(cached.cache_params, cache_params)
        fprintf('  Cache valid! Loading cached TFR...\n');
        tfr_result = cached.tfr_result;
        foi = cached.foi;
        use_cached = true;
    else
        fprintf('  Cache parameters mismatch. Recomputing...\n');
    end
    fprintf('\n');
end

if ~use_cached
    fprintf('--- Selecting electrodes ---\n');
    cfg_sel         = [];
    cfg_sel.channel = electrodes;
    data_sel        = ft_selectdata(cfg_sel, continuous_eeg);
    fprintf('  Using: %s\n\n', strjoin(data_sel.label, ', '));

    % Frequency vector
    foi = freq_range(1) : foi_step : freq_range(2);

    % Time points of interest
    toi = data_sel.time{1}(1) : toi_step : data_sel.time{1}(end);

    % FieldTrip config
    cfg_tfr            = [];
    cfg_tfr.method     = 'mtmconvol';
    cfg_tfr.foi        = foi;
    cfg_tfr.t_ftimwin  = repmat(t_ftimwin, size(foi));
    cfg_tfr.taper      = 'dpss';
    cfg_tfr.tapsmofrq   = 2 * taper_bw / t_ftimwin;
    cfg_tfr.toi        = toi;
    cfg_tfr.keeptrials = 'no';
    cfg_tfr.output     = 'pow';
    cfg_tfr.pad        = 'nextpow2';

    fprintf('--- Computing TFR (%d frequencies x %d time points) ---\n', ...
            length(foi), length(toi));
    tfr_result = ft_freqanalysis(cfg_tfr, data_sel);
    clear data_sel;
    fprintf('  Done.\n\n');

    % Save to cache
    fprintf('--- Saving TFR to cache ---\n');
    save(cache_filename, 'tfr_result', 'foi', 'cache_params', '-v7.3');
    fprintf('  Cache saved: %s\n\n', cache_filename);
end

clear continuous_eeg;

% Average across channels (dim 1)  --  [nFreq x nTime]
power_avg = squeeze(mean(tfr_result.powspctrm, 1));

% Time axis in minutes from recording start
time_min  = (tfr_result.time - tfr_result.time(1)) / 60;

% Power scaling
if use_log
    power_db = 10 * log10(power_avg);
    unit_str = 'dB';
else
    power_db = power_avg;
    unit_str = 'linear';
end

% Robust colour limits  (1st--99th percentile)
clim_lo = prctile(power_db(:),  1);
clim_hi = prctile(power_db(:), 99);

fprintf('  Power: %.2f -- %.2f %s  |  display: %.2f -- %.2f %s\n\n', ...
        min(power_db(:)), max(power_db(:)), unit_str, clim_lo, clim_hi, unit_str);

% ============================================================
% 4.  LOAD HYPNOGRAM DATA
% ============================================================
fprintf('--- Loading hypnogram data ---\n');
hypno_file = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');
if ~exist(hypno_file, 'file')
    error('Hypnogram data file not found: %s', hypno_file);
end

load(hypno_file, 'all_sleep_stages', 'subjects');
fprintf('  Loaded data for %d subjects\n', length(subjects));

% Select subject
if ~any(strcmp(subjects, participant))
    error('Subject %s not found in hypnogram data', participant);
end

% Process hypnogram
subj_stages = all_sleep_stages(strcmp(all_sleep_stages.Subject, participant), :);
[~, sort_idx] = sort(subj_stages.Timestamp);
subj_stages = subj_stages(sort_idx, :);

% Convert to time series
if isduration(subj_stages.Timestamp)
    hypno_times = minutes(subj_stages.Timestamp);
elseif isdatetime(subj_stages.Timestamp)
    hypno_times = minutes(subj_stages.Timestamp - subj_stages.Timestamp(1));
else
    hypno_times = subj_stages.Timestamp / 60;
end

stages = cell(height(subj_stages), 1);
for i = 1:height(subj_stages)
    stages{i} = subj_stages.Stage{i};
end

% Convert stages to numeric values
stage_numeric = zeros(length(stages), 1);
for i = 1:length(stages)
    if stage_map.isKey(stages{i})
        stage_numeric(i) = stage_map(stages{i});
    else
        stage_numeric(i) = NaN;
    end
end

fprintf('  Hypnogram duration: %.1f min\n', max(hypno_times));
fprintf('  Number of stage transitions: %d\n\n', length(hypno_times));

% Apply smoothing/continuity rule
if hypno_apply_continuity
    time_grid = 0:hypno_bin_size_min:ceil(max(hypno_times));
    n_bins = length(time_grid);

    stage_binned = nan(1, n_bins);
    for t = 1:n_bins
        curr_time = time_grid(t);
        idx = find(hypno_times <= curr_time, 1, 'last');
        if ~isempty(idx)
            stage_binned(t) = stage_numeric(idx);
        end
    end

    n_changes = 0;
    for iter = 1:5
        iter_changes = 0;
        for t = (hypno_continuity_outer_window + 1):(n_bins - hypno_continuity_outer_window)
            if isnan(stage_binned(t))
                continue;
            end

            left_outer = stage_binned(t - hypno_continuity_outer_window : t - hypno_continuity_window - 1);
            right_outer = stage_binned(t + hypno_continuity_window + 1 : t + hypno_continuity_outer_window);
            outer_bins = [left_outer, right_outer];
            valid_outer = outer_bins(~isnan(outer_bins));

            if ~isempty(valid_outer) && length(valid_outer) >= 2
                if all(valid_outer == valid_outer(1))
                    surrounding_stage = valid_outer(1);
                    if stage_binned(t) ~= surrounding_stage
                        stage_binned(t) = surrounding_stage;
                        iter_changes = iter_changes + 1;
                    end
                end
            end
        end

        n_changes = n_changes + iter_changes;
        if iter_changes == 0
            break;
        end
    end

    fprintf('  Applied continuity rule: %d bins smoothed\n', n_changes);

    % Apply median filter to remove isolated short segments
    if hypno_median_filter_width > 0
        stage_binned_smooth = stage_binned;
        half_win = floor(hypno_median_filter_width / 2);

        for t = (half_win + 1):(n_bins - half_win)
            if ~isnan(stage_binned(t))
                window_vals = stage_binned(t - half_win : t + half_win);
                valid_vals = window_vals(~isnan(window_vals));

                if ~isempty(valid_vals)
                    % Use mode (most common value) instead of median for discrete stages
                    stage_binned_smooth(t) = mode(valid_vals);
                end
            end
        end

        n_smoothed = sum(stage_binned ~= stage_binned_smooth & ~isnan(stage_binned));
        stage_binned = stage_binned_smooth;
        fprintf('  Applied median filter: %d bins smoothed\n', n_smoothed);
    end

    % Update stage_numeric with smoothed values
    for i = 1:length(hypno_times)
        [~, bin_idx] = min(abs(time_grid - hypno_times(i)));
        if ~isnan(stage_binned(bin_idx))
            stage_numeric(i) = stage_binned(bin_idx);
        end
    end
end

% Create step function for hypnogram
time_plot = [];
stage_plot = [];
for i = 1:length(hypno_times)
    if i < length(hypno_times)
        time_plot = [time_plot, hypno_times(i), hypno_times(i+1)]; %#ok<AGROW>
        stage_plot = [stage_plot, stage_numeric(i), stage_numeric(i)]; %#ok<AGROW>
    else
        time_plot = [time_plot, hypno_times(i), hypno_times(i) + 1]; %#ok<AGROW>
        stage_plot = [stage_plot, stage_numeric(i), stage_numeric(i)]; %#ok<AGROW>
    end
end

fprintf('\n');

%% ============================================================
% 5.  TRIM TIME RANGE (OPTIONAL)
% ============================================================
% Set time range to display (in minutes)
% Set to [] or comment out to display full recording
% Example: trim_time_range = [0, 50];  % Display only first 50 minutes
trim_time_range = [0 50];  % Default: show full recording

% Save full data for non-destructive trimming
if ~exist('time_min_full', 'var')
    time_min_full = time_min;
    power_db_full = power_db;
    time_plot_full = time_plot;
    stage_plot_full = stage_plot;
    block_markers_full = block_markers;
end

if ~isempty(trim_time_range)
    fprintf('--- Trimming time range to %.1f - %.1f minutes ---\n', trim_time_range(1), trim_time_range(2));

    % Trim TFR data (from full data)
    time_mask = time_min_full >= trim_time_range(1) & time_min_full <= trim_time_range(2);
    time_min = time_min_full(time_mask);
    power_db = power_db_full(:, time_mask);

    fprintf('  TFR trimmed: %d time points remaining\n', length(time_min));

    % Trim hypnogram data (from full data)
    hypno_mask = time_plot_full >= trim_time_range(1) & time_plot_full <= trim_time_range(2);
    time_plot = time_plot_full(hypno_mask);
    stage_plot = stage_plot_full(hypno_mask);

    fprintf('  Hypnogram trimmed: %d time points remaining\n', length(time_plot));

    % Trim block markers (from full data)
    if ~isempty(block_markers_full)
        marker_mask = block_markers_full(:, 1) >= trim_time_range(1) & block_markers_full(:, 1) <= trim_time_range(2);
        block_markers = block_markers_full(marker_mask, :);
        fprintf('  Block markers trimmed: %d markers remaining\n', size(block_markers, 1));
    end

    fprintf('\n');
else
    % Use full data when no trimming
    time_min = time_min_full;
    power_db = power_db_full;
    time_plot = time_plot_full;
    stage_plot = stage_plot_full;
    block_markers = block_markers_full;
end

% ============================================================
% 6.  PLOT
% ============================================================
fig = figure('Units', 'centimeters', ...
             'Position',      [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color',         'white', ...
             'PaperUnits',    'centimeters', ...
             'PaperSize',     [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% Define axes positions [left, bottom, width, height]
tfr_pos         = [0.13, 0.40, 0.68, 0.38];   % Top: TFR (increased height)
hypno_pos       = [0.13, 0.12, 0.68, 0.25];   % Bottom: Hypnogram

% ---- TFR heatmap ----
ax_tfr = axes(fig, 'Position', tfr_pos);
axes(ax_tfr);

title(ax_tfr, ...
      sprintf('Whole-Night TFR with Hypnogram -- %s (%s)', participant, strjoin(electrodes, ', ')), ...
      'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

imagesc(time_min, foi, power_db);
set(ax_tfr, 'YDir', 'normal');
colormap(ax_tfr, parula(256));
set(ax_tfr, 'CLim', [clim_lo, clim_hi]);

% Frequency-band boundary lines
for i = 2 : length(band_edges) - 1
    yline(band_edges(i), 'w--', 'LineWidth', 0.7, 'Alpha', 0.5);
end

% Band-name labels
for i = 1 : length(band_names)
    mid_freq = mean(band_edges(i : i+1));
    text(ax_tfr, time_min(3), mid_freq, band_names{i}, ...
         'Color', 'white', 'FontName', pub.font_name, ...
         'FontSize', pub.font_size_axis, 'FontWeight', 'bold', ...
         'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
end

% Axes formatting
set(ax_tfr, 'XTick', [], ...
            'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
            'Box', 'off', 'TickDir', 'out');
ylabel(ax_tfr, 'Frequency (Hz)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
xlim(ax_tfr, [time_min(1), time_min(end)]);
ylim(ax_tfr, [foi(1), foi(end)]);

% Colorbar
cb = colorbar(ax_tfr, 'Location', 'EastOutside');
cb.Label.String   = sprintf('Power (%s)', unit_str);
cb.Label.FontName = pub.font_name;
cb.Label.FontSize = pub.font_size_label;
set(cb, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis);

% Realign TFR axes after colorbar
ax_tfr.Position = tfr_pos;

% ---- Hypnogram ----
ax_hypno = axes(fig, 'Position', hypno_pos);
hold(ax_hypno, 'on');

% Plot simple black line hypnogram
plot(time_plot, stage_plot, 'k-', 'LineWidth', 1.2);

% Add stimulation block markers as colored vertical lines at the top
y_limits = [min(stage_values)-0.5, max(stage_values)+0.5];
stim_line_top = y_limits(1) + 0.05;  % Just below the top of the plot
stim_line_bottom = y_limits(1) + 0.35;  % Short line

for i = 1:size(block_markers, 1)
    block_time = block_markers(i, 1);
    cond_idx = block_markers(i, 2);
    cond_name = stim_conditions{cond_idx};

    % Get color for this condition
    if isfield(stim_colors, cond_name)
        bar_color = stim_colors.(cond_name);
    else
        bar_color = [0.5, 0.5, 0.5];  % Default grey
    end

    % Draw vertical line at top of hypnogram
    plot(ax_hypno, [block_time, block_time], [stim_line_top, stim_line_bottom], ...
         'Color', bar_color, 'LineWidth', 3);
end

% Format hypnogram axis
set(ax_hypno, 'YTick', stage_values, 'YTickLabel', stage_labels, ...
              'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
              'Box', 'off', 'TickDir', 'out', 'YDir', 'reverse');
xlabel(ax_hypno, 'Time (min)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel(ax_hypno, 'Sleep Stage', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
xlim(ax_hypno, [time_min(1), time_min(end)]);
ylim(ax_hypno, y_limits);
grid(ax_hypno, 'on');

hold(ax_hypno, 'off');

%% ============================================================
% 7.  SAVE
% ============================================================
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

filename_base = sprintf('figure1_overviewTFR_hypno_%s', participant);
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

% Save plot data
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'power_db', 'time_min', 'foi', ...
     'time_plot', 'stage_plot', 'stage_numeric', 'hypno_times', ...
     'block_markers', 'stim_conditions', ...
     'electrodes', 'participant', 'session', ...
     'clim_lo', 'clim_hi', 'pub');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('=== Done ===\n');

%% ============================================================
% 8.  BLOCK STRUCTURE SCHEMATIC (SEPARATE FIGURE)
% ============================================================
% Single horizontal bar: 5Hz trials -- 1Hz trials -- OFF trials,
% mimicking the stimulation bar on the hypnogram (zoomed in).
fprintf('\n--- Creating Block Structure schematic ---\n');

% Trial parameters
n_trials_per_cond = 5;
stim_dur_s  = 2;            % active stimulation (s)
pause_dur_s = 6;            % high-frequency pause (s)
trial_dur_s = stim_dur_s + pause_dur_s;   % 8 s
cond_dur_s  = n_trials_per_cond * trial_dur_s;  % 40 s per condition
ramp_dur_s  = 5;            % ramp triangle width (s)

% X-positions (left to right: 5Hz -- 1Hz -- ramp-down -- OFF -- ramp-up)
x_5hz   = 0;
x_1hz   = cond_dur_s;                     % 40
x_rdn   = 2 * cond_dur_s;                 % 80  (ramp-down start)
x_off   = x_rdn + ramp_dur_s;             % 85  (OFF start)
x_rup   = x_off + cond_dur_s;             % 125 (ramp-up start)
total_w = x_rup + ramp_dur_s;             % 130

% Figure -- roughly square
schema_w_cm = 10;
schema_h_cm = 7;
fig_schema = figure('Units', 'centimeters', ...
                    'Position',      [5, 1, schema_w_cm, schema_h_cm], ...
                    'Color',         'white', ...
                    'PaperUnits',    'centimeters', ...
                    'PaperSize',     [schema_w_cm, schema_h_cm], ...
                    'PaperPosition', [0, 0, schema_w_cm, schema_h_cm]);

ax_schema = axes(fig_schema, 'Position', [0.06, 0.25, 0.92, 0.62]);
hold(ax_schema, 'on');

% Colours -- vibrant (stim) and desaturated (pause)
mix_w = 0.60;
col_s = {[1.0 0.6 0.0], ...        % 5 Hz  (orange)
         [0.0 0.2 0.6], ...        % 1 Hz  (dark blue)
         [0.5 0.5 0.5]};           % OFF   (grey)
col_p = {col_s{1}*(1-mix_w) + [1 1 1]*mix_w, ...   % pale orange
         col_s{2}*(1-mix_w) + [1 1 1]*mix_w, ...   % pale blue
         col_s{3}*(1-mix_w) + [1 1 1]*mix_w};      % pale grey
cond_labels_s = {'5 Hz', '1 Hz', 'OFF'};
col_ramp = [0.65 0.65 0.65];                        % grey for ramps

% Bar geometry -- tall bar extending downward (top=0, bottom=negative)
bar_top    = 0;
bar_bottom = -1;
bar_h      = bar_top - bar_bottom;  % height = 1
bar_mid    = (bar_top + bar_bottom) / 2;

% --- Draw condition blocks (5Hz | 1Hz | OFF) ---
cond_x_starts = [x_5hz, x_1hz, x_off];
for g = 1:3
    for t = 0:(n_trials_per_cond - 1)
        x0 = cond_x_starts(g) + t * trial_dur_s;
        % Active-stimulation segment (vibrant)
        rectangle(ax_schema, 'Position', [x0, bar_bottom, stim_dur_s, bar_h], ...
                  'FaceColor', col_s{g}, 'EdgeColor', 'none');
        % Pause segment (desaturated)
        rectangle(ax_schema, 'Position', [x0 + stim_dur_s, bar_bottom, pause_dur_s, bar_h], ...
                  'FaceColor', col_p{g}, 'EdgeColor', 'none');
    end
    % Condition label above each group
    text(ax_schema, cond_x_starts(g) + cond_dur_s/2, bar_top + 0.12, cond_labels_s{g}, ...
         'FontName', pub.font_name, 'FontSize', 10, ...
         'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'bottom', 'Color', col_s{g});
end

% --- Ramp triangles ---
% Ramp-down (1Hz -- OFF): vertical base on left, peak (point) at right
fill(ax_schema, [x_rdn, x_rdn, x_rdn + ramp_dur_s], ...
     [bar_bottom, bar_top, bar_mid], col_ramp, 'EdgeColor', 'none');
% Ramp-up (OFF -- next): peak (point) at left, vertical base on right
fill(ax_schema, [x_rup, x_rup + ramp_dur_s, x_rup + ramp_dur_s], ...
     [bar_mid, bar_bottom, bar_top], col_ramp, 'EdgeColor', 'none');

% --- Time brackets under first trial with arrow-connected labels ---
bk_tick = 0.06;
lw_bk   = 0.8;
lbl_fs  = 9;               % bigger font for annotations
arr_clr = [0.3 0.3 0.3];   % arrow/label colour

% Stim bracket (0 to 2) -- higher
bk_y_stim = bar_bottom - 0.18;
plot(ax_schema, [0 stim_dur_s],          [bk_y_stim bk_y_stim], '-k', 'LineWidth', lw_bk);
plot(ax_schema, [0 0],                   [bk_y_stim-bk_tick bk_y_stim+bk_tick], '-k', 'LineWidth', lw_bk);
plot(ax_schema, [stim_dur_s stim_dur_s], [bk_y_stim-bk_tick bk_y_stim+bk_tick], '-k', 'LineWidth', lw_bk);
% Pause bracket (2 to 8) -- clearly lower
bk_y_pause = bk_y_stim - 0.25;
plot(ax_schema, [stim_dur_s trial_dur_s],  [bk_y_pause bk_y_pause], '-k', 'LineWidth', lw_bk);
plot(ax_schema, [stim_dur_s stim_dur_s],   [bk_y_pause-bk_tick bk_y_pause+bk_tick], '-k', 'LineWidth', lw_bk);
plot(ax_schema, [trial_dur_s trial_dur_s], [bk_y_pause-bk_tick bk_y_pause+bk_tick], '-k', 'LineWidth', lw_bk);

% Arrow lines from bracket midpoints to spaced-out labels
lbl_y = bk_y_pause - 0.50;
% "2 s stim" -- arrow from left edge of stim bracket, going left
stim_lbl_x = -16;
plot(ax_schema, [0, stim_lbl_x], [bk_y_stim, lbl_y + 0.08], ...
     '-', 'Color', arr_clr, 'LineWidth', 0.6);
text(ax_schema, stim_lbl_x, lbl_y, '2 s stim', ...
     'FontName', pub.font_name, 'FontSize', lbl_fs, ...
     'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
     'FontAngle', 'italic', 'Color', arr_clr);
% "6 s pause" -- arrow from right edge of pause bracket, going right
pause_lbl_x = trial_dur_s + 14;
plot(ax_schema, [trial_dur_s, pause_lbl_x], [bk_y_pause, lbl_y + 0.08], ...
     '-', 'Color', arr_clr, 'LineWidth', 0.6);
text(ax_schema, pause_lbl_x, lbl_y, '6 s pause', ...
     'FontName', pub.font_name, 'FontSize', lbl_fs, ...
     'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
     'FontAngle', 'italic', 'Color', arr_clr);

% Axes limits & hide frame
xlim(ax_schema, [-22, total_w + 3]);
ylim(ax_schema, [lbl_y - 0.15, bar_top + 0.50]);
set(ax_schema, 'Visible', 'off');
hold(ax_schema, 'off');

% Save schematic figure
schema_base = 'figure1_blockStructure';
print(fig_schema, fullfile(OUTPUT_DIR, [schema_base '.png']), '-dpng', '-r300');
set(fig_schema, 'Renderer', 'painters');
print(fig_schema, fullfile(OUTPUT_DIR, [schema_base '.svg']), '-dsvg', '-painters');
savefig(fig_schema, fullfile(OUTPUT_DIR, [schema_base '.fig']));

fprintf('  Block structure schematic saved:\n');
fprintf('    - %s.png\n', schema_base);
fprintf('    - %s.svg\n', schema_base);
fprintf('    - %s.fig\n', schema_base);
fprintf('=== Block Structure Schematic Complete ===\n');

end
