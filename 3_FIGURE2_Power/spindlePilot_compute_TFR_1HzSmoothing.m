%% =================== FIELDTRIP TFR PIPELINE (STRUCTURED + per-trial) ===================
% Per-participant / per-condition / per-trial multitaper TFR with 1 Hz
% spectral smoothing in the spindle band. Outputs go to TFR_1HzSmoothing/.
% Participants, electrodes, and conditions all accept 'all'. The overview
% section optionally plots whole-recording spectra.

% =========================================================================
% PATH CONFIGURATION
% =========================================================================
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
PROCESSED_DATA_DIR = fullfile(REPO_ROOT, 'data');  % in-repo, gitignored (see README "Data Availability")
RESULTS_DIR = fullfile(REPO_ROOT, '3_FIGURE2_Power');
% =========================================================================

%% =================== SECTION A: OVERVIEW (whole recording) ===================
cfg_over = struct();
cfg_over.participants = {'sub15'};  % {'sub15'} or 'all'
cfg_over.session      = 'ses1';
cfg_over.electrodes   = {'Cz'};  % {'Cz'} or 'all'
cfg_over.base_path    = fullfile(PROCESSED_DATA_DIR, 'analysis');
cfg_over.output_base  = RESULTS_DIR;
cfg_over.output_path  = fullfile(cfg_over.output_base, 'TFR_1HzSmoothing');

cfg_over.freq_range   = [0.5 30];   % Hz
cfg_over.time_window  = 4;          % seconds (adaptive: 4/freq)
cfg_over.tapsmofrq    = 2;          % base spectral smoothing (will be lifted per-foi to ensure NW>=1)
cfg_over.create_plots = true;       % <— enable overview plotting
cfg_over.save_results = true;

fprintf('=== Running Overview TFR Analysis (FieldTrip) - 1Hz SMOOTHING ===\n');
overview_results = spindlePilot_overview_tfr_ft_STRUCT(cfg_over);
fprintf('Overview analysis complete.\n\n');

%% =================== SECTION B: TRIAL TFR (Two-Pass: Spindle + Slow-Wave) ===================
% Common base for both passes (structured)
base = struct();
base.participants  = 'all';                              % {'sub15'} or 'all'
base.session       = 'ses1';
base.conditions    = {'x1HZ','x5HZ','OFF'};              % {'x1HZ','x5HZ','OFF'} or 'all'
base.electrodes    = 'all';   % {'Cz','C3','C4'} or 'all'
base.base_path     = fullfile(PROCESSED_DATA_DIR, 'analysis');
base.output_base   = RESULTS_DIR;
base.root_output   = fullfile(base.output_base, 'TFR_1HzSmoothing');
base.create_plots  = false;                              % no plots during calculation
base.save_results  = true;                               % save FieldTrip structures

% Trial timing for both passes
base.pre_trial     = 6.0;    % seconds
base.post_trial    = 6.0;    % seconds
base.time_step     = 0.05;   % seconds
base.pad           = 'nextpow2'; % match first-script style padding

if ~exist(cfg_over.output_path, 'dir'), mkdir(cfg_over.output_path); end
if ~exist(base.root_output, 'dir'), mkdir(base.root_output); end

% ---- PASS 1: Spindle-focused (1Hz SMOOTHING) ----
cfg_sp = base;
cfg_sp.output_path = fullfile(base.root_output, 'spindle_trials');
cfg_sp.time_window = 1;        % s
cfg_sp.tapsmofrq   = 1.0;         % Hz spectral smoothing
cfg_sp.freq_range  = [5 30];      % Hz
cfg_sp.foi_step    = 0.25;        % Hz
cfg_sp.match_trial_counts = false; 
cfg_sp.random_seed = 42;          % For reproducibility
fprintf('=== PASS 1: Spindle-Focused Trial TFR (1Hz SMOOTHING - STRUCTURED + per-trial logic) ===\n');
trial_results_SP = spindlePilot_trial_tfr_ft_PERTRIAL(cfg_sp, 'SP');
fprintf('Spindle pass complete.\n\n');

%% ---- PASS 2: Slow-wave-focused ----
cfg_sw = base;
cfg_sw.output_path = fullfile(base.root_output, 'slowwave_trials');
cfg_sw.time_window = 3.0;         % s
cfg_sw.tapsmofrq   = 0.5;         % Hz spectral smoothing
cfg_sw.freq_range  = [0.1 4];     % Hz
cfg_sw.foi_step    = 0.25;        % Hz
cfg_sw.match_trial_counts = true; % IMPORTANT: Match trial counts for equal SNR across conditions
cfg_sw.random_seed = 42;          % For reproducibility
fprintf('=== PASS 2: Slow-Wave-Focused Trial TFR (STRUCTURED + per-trial logic) ===\n');
trial_results_SW = spindlePilot_trial_tfr_ft_PERTRIAL(cfg_sw, 'SW');
fprintf('Slow-wave pass complete.\n');

%% =================== SECTION C: CUSTOM PLOTTING (optional) ===================
plot_cfg = struct();
plot_cfg.root_output   = base.root_output;
plot_cfg.pass          = 'SP';                         % 'SP' or 'SW'
plot_cfg.participants  = 'all';                        % {'sub15'} or 'all'
plot_cfg.conditions    = 'all';                        % {'x1HZ','x5HZ','OFF'} or 'all'
plot_cfg.electrodes    = {'Cz','C3','C4', 'CP3', 'CP4', 'CP5', 'CP6'};             % or 'all'
plot_cfg.freq_range    = [8 18];                           % [] => full in files
plot_cfg.time_range    = [-2 6];                       % seconds
plot_cfg.save_fig_dir  = fullfile(base.output_base, 'figures_1HzSmoothing');
plot_cfg.figure_title  = 'Custom Trial TFR (Raw Power, Per-Trial Averaged, 1Hz Smoothing)';
plot_cfg.colormap      = 'parula';
plot_cfg.debug         = true;

% Uncomment to run plotting
fprintf('=== Custom plotting of trial results (%s) ===\n', plot_cfg.pass);
spindlePilot_plot_trial_custom_ft_STRUCT(plot_cfg);
fprintf('Custom plotting complete.\n');

%% ====================== FUNCTIONS ======================

function results = spindlePilot_overview_tfr_ft_STRUCT(config)
fprintf('\n========== OVERVIEW TFR ANALYSIS (FieldTrip) ==========\n');
if ~exist(config.output_path, 'dir'), mkdir(config.output_path); end

% ----- resolve participants (supports 'all')
participants = resolve_participants_LIST(config.participants, config.base_path, config.session);

results = struct();
for p = 1:length(participants)
    participant = participants{p};
    fprintf('\n--- Processing %s ---\n', participant);

    % Load data
    pdata = load_participant_data_STRUCT(participant, config.session, config.base_path);
    continuous_eeg = pdata.eeg;

    % ----- resolve electrodes (supports 'all')
    electrodes = resolve_electrodes_LIST(config.electrodes, continuous_eeg.label);

    % Select electrodes
    cfg_sel = [];
    cfg_sel.channel = electrodes;
    data_sel = ft_selectdata(cfg_sel, continuous_eeg);

    % Build adaptive windows
    foi = config.freq_range(1):0.5:config.freq_range(2);
    t_ftimwin = config.time_window ./ foi;   % seconds (adaptive)

    % SAFETY: ensure NW >= 1 per frequency for DPSS
    tapsmo_min = 1 ./ t_ftimwin;
    tapsmofrq  = max(config.tapsmofrq, tapsmo_min) + 0.05;

    % Time-frequency config
    cfg_tfr = [];
    cfg_tfr.method     = 'mtmconvol';
    cfg_tfr.foi        = foi;
    cfg_tfr.t_ftimwin  = t_ftimwin(:);
    cfg_tfr.tapsmofrq  = tapsmofrq(:);
    cfg_tfr.taper      = 'dpss';
    cfg_tfr.toi        = 'all';
    cfg_tfr.keeptrials = 'no';
    cfg_tfr.output     = 'pow';
    cfg_tfr.pad        = 'nextpow2';

    % Run TFR
    tfr_result = ft_freqanalysis(cfg_tfr, data_sel);
    results.(participant) = tfr_result;

    % Save results
    if isfield(config,'save_results') && config.save_results
        outname = fullfile(config.output_path, sprintf('TFR_overview_%s_%s.mat', participant, config.session));
        save(outname, 'tfr_result', '-v7.3');
        fprintf('Saved overview: %s\n', outname);
    end

    % Plot results
    if isfield(config,'create_plots') && config.create_plots
        figure('Name', sprintf('%s overview', participant), 'Position', [100 100 1000 600]);

        cfg_plot = [];
        cfg_plot.channel  = 'all';    % average over selected electrodes
        cfg_plot.xlim     = [tfr_result.time(1) tfr_result.time(end)];
        cfg_plot.ylim     = [foi(1) foi(end)];
        cfg_plot.zlim     = 'maxabs';
        cfg_plot.colormap = parula;
        cfg_plot.title    = sprintf('Overview TFR - %s (%s)', participant, config.session);

        ft_singleplotTFR(cfg_plot, tfr_result);

        % Optional: save figure
        if config.save_results
            fig_dir = strrep(config.output_path, 'TFR_1HzSmoothing', 'figures_1HzSmoothing');
            if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
            figname = fullfile(fig_dir, sprintf('TFR_overview_%s_%s.png', participant, config.session));
            saveas(gcf, figname);
            fprintf('Saved overview figure: %s\n', figname);
        end
    end
end
fprintf('\n========== COMPLETE (OVERVIEW) ==========\n');
end

function results = spindlePilot_trial_tfr_ft_PERTRIAL(config, pass_suffix)
% STRUCTURE like your second script but COMPUTATION like your first.
% Supports 'all' for participants, electrodes, and conditions.
fprintf('\n========== TRIAL TFR ANALYSIS (%s | per-trial) ==========\n', pass_suffix);
if ~exist(config.output_path, 'dir'), mkdir(config.output_path); end

% ----- resolve participants
participants = resolve_participants_LIST(config.participants, config.base_path, config.session);

results = struct();
for p = 1:length(participants)
    participant = participants{p};
    fprintf('\n--- Processing %s ---\n', participant);

    % Load data (need both continuous EEG and epochedData)
    pdata = load_participant_data_STRUCT(participant, config.session, config.base_path);
    eeg_data      = pdata.eeg;          % continuous
    epoched_data  = pdata.epochedData;  % per-condition

    % ----- resolve electrodes
    electrodes = resolve_electrodes_LIST(config.electrodes, eeg_data.label);

    % Map electrodes to indices
    chan_idx = find(ismember(eeg_data.label, electrodes));
    if isempty(chan_idx)
        warning('No requested electrodes found for %s, using all channels.', participant);
        chan_idx = 1:numel(eeg_data.label);
    end

    % ----- resolve conditions
    conditions = resolve_conditions_LIST(config.conditions, epoched_data);

    % ----- TRIAL MATCHING: If enabled, match trial counts across conditions
    if isfield(config, 'match_trial_counts') && config.match_trial_counts
        % First, collect all condition data into a structure for matching
        cond_data_for_matching = struct();
        for c = 1:length(conditions)
            condition = conditions{c};
            if isfield(epoched_data, condition) && ~isempty(epoched_data.(condition).trial)
                cond_data_for_matching.(condition) = epoched_data.(condition);
            end
        end

        % Apply trial matching if we have multiple conditions
        if length(fieldnames(cond_data_for_matching)) >= 2
            fprintf('  >>> TRIAL MATCHING ENABLED <<<\n');
            random_seed = 42; % Default
            if isfield(config, 'random_seed')
                random_seed = config.random_seed;
            end

            [matched_data, match_info] = spindlePilot_matchTrialCounts(cond_data_for_matching, ...
                'random_seed', random_seed, ...
                'verbose', true);

            % Replace epoched_data with matched data
            for c = 1:length(conditions)
                condition = conditions{c};
                if isfield(matched_data, condition)
                    epoched_data.(condition) = matched_data.(condition);
                end
            end

            % Store match info for later saving
            participant_match_info = match_info; %#ok<NASGU>
        else
            fprintf('  Trial matching requested but only 1 condition found, skipping.\n');
            participant_match_info = []; %#ok<NASGU>
        end
    else
        participant_match_info = []; %#ok<NASGU>
    end

    % Process each condition
    participant_result = struct();
    for c = 1:length(conditions)
        condition = conditions{c};
        if ~isfield(epoched_data, condition) || isempty(epoched_data.(condition).trial)
            fprintf('    Skipping (no trials): %s\n', condition);
            continue;
        end
        fprintf('    Condition: %s\n', condition);

        cond_data = epoched_data.(condition);
        n_trials  = numel(cond_data.trial);
        fs        = cond_data.fsample;
        preS      = round(config.pre_trial * fs);
        postS     = round(config.post_trial * fs);

        % Find extended epoch bounds for each trial (against continuous data)
        data_start = eeg_data.sampleinfo(1);
        data_end   = eeg_data.sampleinfo(2);
        extended_epochs = cell(n_trials,1);
        min_epoch_length = inf;

        for t = 1:n_trials
            orig_start = cond_data.sampleinfo(t,1);
            orig_end   = cond_data.sampleinfo(t,2);
            ext_start  = max(orig_start - preS, data_start);
            ext_end    = min(orig_end   + postS, data_end);
            extended_epochs{t} = [ext_start, ext_end];
            epoch_len = ext_end - ext_start + 1;
            if epoch_len < min_epoch_length, min_epoch_length = epoch_len; end
        end
        fprintf('      Global min extended length: %.2f s (%d samples)\n', min_epoch_length/fs, min_epoch_length);

        % Configure TFR for this pass
        cfg_tf = [];
        cfg_tf.method     = 'mtmconvol';
        cfg_tf.foi        = config.freq_range(1):config.foi_step:config.freq_range(2);
        cfg_tf.t_ftimwin  = config.time_window * ones(numel(cfg_tf.foi),1);
        cfg_tf.tapsmofrq  = config.tapsmofrq * ones(numel(cfg_tf.foi),1);
        cfg_tf.toi        = -config.pre_trial:config.time_step:config.post_trial;
        cfg_tf.keeptrials = 'yes';              % 1 rpt per call
        cfg_tf.output     = 'pow';
        if isfield(config,'pad') && ~isempty(config.pad)
            cfg_tf.pad = config.pad;
        end

        % Iterate trials: extract data from continuous, build FT single-trial, run ft_freqanalysis
        trial_tf_data = cell(n_trials,1);
        for t = 1:n_trials
            ext_start = extended_epochs{t}(1);
            sample_idx = ext_start:(ext_start + min_epoch_length - 1);
            base_idx = sample_idx - data_start + 1;
            trial_data = eeg_data.trial{1}(chan_idx, base_idx);
            trial_time = (0:(size(trial_data,2)-1))/fs - config.pre_trial;

            ft_data = [];
            ft_data.trial      = {trial_data};
            ft_data.time       = {trial_time};
            ft_data.label      = eeg_data.label(chan_idx);
            ft_data.fsample    = fs;
            ft_data.sampleinfo = [1 size(trial_data,2)];

            tf_result = ft_freqanalysis(cfg_tf, ft_data);
            trial_tf_data{t} = tf_result;

            if isfield(config,'save_results') && config.save_results
                trial_filename = sprintf('TFR_%s_trial_%s_%s_%s_%03d.mat', pass_suffix, participant, config.session, condition, t);
                trial_filepath = fullfile(config.output_path, trial_filename);
                tfr_single = tf_result; %#ok<NASGU>
                save(trial_filepath, 'tfr_single', '-v7.3');
            end

            if mod(t,25)==0 || t==n_trials
                fprintf('        Trial %d/%d done\n', t, n_trials);
            end
        end

        % Combine trials into rpt dimension and average overrpt
        if ~isempty(trial_tf_data)
            powspctrm_all = [];
            for t = 1:n_trials
                if t == 1
                    powspctrm_all = trial_tf_data{t}.powspctrm; % [1 x chan x freq x time]
                else
                    powspctrm_all = cat(1, powspctrm_all, trial_tf_data{t}.powspctrm);
                end
            end
            combined = trial_tf_data{1};
            combined.powspctrm = powspctrm_all;

            if isfield(combined, 'cumtapcnt') && ~isempty(combined.cumtapcnt)
                combined.cumtapcnt = repmat(combined.cumtapcnt, [size(powspctrm_all,1) 1]);
            end

            cfg_avg = [];
            cfg_avg.trials       = 'all';
            cfg_avg.avgoverrpt   = 'yes';
            condition_avg        = ft_freqdescriptives(cfg_avg, combined); % chan x freq x time

            participant_result.(condition) = condition_avg;

            if isfield(config,'save_results') && config.save_results
                avg_filename = sprintf('TFR_%s_avg_%s_%s_%s.mat', pass_suffix, participant, config.session, condition);
                avg_filepath = fullfile(config.output_path, avg_filename);
                tfr_avg = condition_avg; %#ok<NASGU>
                meta = struct('n_trials', n_trials, ...
                              'pre_sec', config.pre_trial, 'post_sec', config.post_trial, ...
                              'electrodes', {eeg_data.label(chan_idx)}, ...
                              'fs', fs, 'freq_range', config.freq_range, ...
                              'time_window', config.time_window, ...
                              'tapsmofrq', config.tapsmofrq, 'toi', cfg_tf.toi); %#ok<NASGU>

                % Add trial matching info if it was performed
                if exist('participant_match_info', 'var') && ~isempty(participant_match_info)
                    meta.trial_matching = participant_match_info; %#ok<NASGU>
                end

                save(avg_filepath, 'tfr_avg', 'meta', '-v7.3');
                fprintf('      Saved condition average: %s\n', avg_filename);
            end
        else
            participant_result.(condition) = [];
        end
    end

    results.(participant) = participant_result;
end
fprintf('\n========== COMPLETE (TRIALS | %s) ==========\n', pass_suffix);
end

function spindlePilot_plot_trial_custom_ft_STRUCT(cfg)
fprintf('\n========== CUSTOM PLOTTING (Per-Condition Averages) ==========\n');

% Determine pass directory
if strcmpi(cfg.pass,'SP')
    pass_dir = fullfile(cfg.root_output, 'spindle_trials');
elseif strcmpi(cfg.pass,'SW')
    pass_dir = fullfile(cfg.root_output, 'slowwave_trials');
else
    error('cfg.pass must be ''SP'' or ''SW''.');
end

% Discover participants if needed
if ~isfield(cfg,'participants') || isempty(cfg.participants) || (ischar(cfg.participants) && strcmpi(cfg.participants,'all'))
    d = dir(fullfile(pass_dir, 'TFR_*_avg_*.mat'));
    ps = cellfun(@(s) regexp(s, '^TFR_[^_]+_avg_(.*?)_', 'tokens','once'), {d.name}, 'uni', 0);
    ps = unique(cellfun(@(t) t{1}, ps(~cellfun('isempty',ps)), 'uni', 0));
    cfg.participants = ps;
end

if isempty(cfg.participants)
    warning('No participants found');
    return;
end

% Default conditions if needed
if ~isfield(cfg,'conditions') || isempty(cfg.conditions) || (ischar(cfg.conditions) && strcmpi(cfg.conditions,'all'))
    % Try to infer by scanning files for the first participant
    d = dir(fullfile(pass_dir, sprintf('TFR_%s_avg_%s_*_*.mat', cfg.pass, cfg.participants{1})));
    conds = cellfun(@(s) regexp(s, '^TFR_[^_]+_avg_[^_]+_[^_]+_([^_]+)\.mat$', 'tokens','once'), {d.name}, 'uni', 0);
    conds = unique(cellfun(@(t) t{1}, conds(~isemptyCell(conds)), 'uni', 0));
    if isempty(conds), conds = {'x1HZ','x5HZ','OFF'}; end
    cfg.conditions = conds;
end

% Load and aggregate data by condition
condition_data = struct();

for ci = 1:numel(cfg.conditions)
    cond = cfg.conditions{ci};
    all_subj_data = {};

    for pi = 1:numel(cfg.participants)
        subj = cfg.participants{pi};
        fglob = dir(fullfile(pass_dir, sprintf('TFR_%s_avg_%s_*_%s.mat', cfg.pass, subj, cond)));
        if isempty(fglob)
            if cfg.debug, fprintf('    Missing: TFR_%s_avg_%s_*_%s.mat\n', cfg.pass, subj, cond); end
            continue;
        end
        fpath = fullfile(fglob(1).folder, fglob(1).name);
        S = load(fpath, 'tfr_avg');
        tfr_data = S.tfr_avg;

        % Electrode selection and average across selected
        if ischar(cfg.electrodes) && strcmpi(cfg.electrodes,'all')
            elec_idx = 1:numel(tfr_data.label);
        else
            elec_idx = find(ismember(tfr_data.label, cfg.electrodes));
        end
        if isempty(elec_idx)
            if cfg.debug, fprintf('    No requested electrodes in: %s\n', fglob(1).name); end
            continue;
        end

        tfr_elec_avg = struct();
        tfr_elec_avg.freq = tfr_data.freq;
        tfr_elec_avg.time = tfr_data.time;
        tfr_elec_avg.powspctrm = squeeze(mean(tfr_data.powspctrm(elec_idx,:,:),1)); % freq x time
        tfr_elec_avg.label = {'avg'};

        if cfg.debug
            fprintf('    Loaded %s|%s: time=[%.2f %.2f]s, freq=[%.1f %.1f]Hz, size=[%dx%d]\n', ...
                subj, cond, min(tfr_elec_avg.time), max(tfr_elec_avg.time), ...
                min(tfr_elec_avg.freq), max(tfr_elec_avg.freq), ...
                size(tfr_elec_avg.powspctrm,1), size(tfr_elec_avg.powspctrm,2));
        end

        all_subj_data{end+1} = tfr_elec_avg; %#ok<SAGROW>
    end

    % Manual grand average across subjects
    if ~isempty(all_subj_data)
        freq = all_subj_data{1}.freq;
        time = all_subj_data{1}.time;
        power_sum = zeros(numel(freq), numel(time));
        n_valid = 0;

        for j = 1:numel(all_subj_data)
            d = all_subj_data{j};
            if numel(d.freq)==numel(freq) && numel(d.time)==numel(time)
                power_sum = power_sum + d.powspctrm;
                n_valid = n_valid + 1;
            end
        end

        if n_valid>0
            avg_data = struct('freq', freq, 'time', time, 'powspctrm', power_sum/n_valid);
            condition_data.(cond) = avg_data;
            fprintf('  Condition %s: %d subjects averaged\n', cond, n_valid);
        else
            fprintf('  Condition %s: no compatible data\n', cond);
        end
    else
        fprintf('  Condition %s: no valid data found\n', cond);
    end
end

available_conds = fieldnames(condition_data);
if isempty(available_conds)
    warning('No data available for plotting');
    return;
end

% Create figure
figure('Position', [100, 100, 400*length(available_conds), 600], 'Name', cfg.figure_title);

% Plot each condition
for i = 1:length(available_conds)
    cond = available_conds{i};
    data = condition_data.(cond);

    subplot(1, length(available_conds), i);
    plot_data = data;

    if ~isempty(cfg.time_range)
        tidx = plot_data.time >= cfg.time_range(1) & plot_data.time <= cfg.time_range(2);
        plot_data.time = plot_data.time(tidx);
        plot_data.powspctrm = plot_data.powspctrm(:, tidx);
    end
    if ~isempty(cfg.freq_range)
        fidx = plot_data.freq >= cfg.freq_range(1) & plot_data.freq <= cfg.freq_range(2);
        plot_data.freq = plot_data.freq(fidx);
        plot_data.powspctrm = plot_data.powspctrm(fidx, :);
    end

    imagesc(plot_data.time, plot_data.freq, plot_data.powspctrm);
    axis xy;
    colormap(cfg.colormap);
    colorbar;
    xlabel('Time (s)'); ylabel('Frequency (Hz)');
    title(cond);

    hold on;
    if min(plot_data.time) <= 0 && max(plot_data.time) >= 0
        plot([0 0], [min(plot_data.freq) max(plot_data.freq)], 'w-', 'LineWidth', 2);
    end
    hold off;
end

sgtitle(sprintf('%s - Pass %s (Raw Power)', cfg.figure_title, cfg.pass));
end

%% ======================= HELPERS =======================

function participant_data = load_participant_data_STRUCT(participant, session, base_path)
data_file = fullfile(base_path, sprintf('%s_%s_ANALYSIS.mat', participant, session));
if ~exist(data_file,'file')
    error('File not found: %s', data_file);
end
S = load(data_file, 'analysisData_saved');
participant_data = S.analysisData_saved.(participant).(session);
end

function parts = resolve_participants_LIST(input, base_path, session)
if ischar(input) && strcmpi(input,'all')
    d = dir(fullfile(base_path, sprintf('*_%s_ANALYSIS.mat', session)));
    parts = cellfun(@(s) regexp(s, '^(.*?)_', 'tokens','once'), {d.name}, 'uni', 0);
    parts = unique(cellfun(@(t) t{1}, parts(~cellfun('isempty',parts)), 'uni', 0));
    if isempty(parts), error('No participants found in %s for session %s', base_path, session); end
elseif iscell(input)
    parts = input;
else
    error('participants must be a cell array or ''all''.');
end
end

function electrodes = resolve_electrodes_LIST(input, all_labels)
if ischar(input) && strcmpi(input,'all')
    electrodes = all_labels(:)'; % all channels
elseif iscell(input)
    electrodes = input;
else
    error('electrodes must be a cell array or ''all''.');
end
end

function conditions = resolve_conditions_LIST(input, epochedData)
if ischar(input) && strcmpi(input,'all')
    conditions = setdiff(fieldnames(epochedData), {'cfg'}); % ignore cfg fields
    % keep only those that actually have trials
    conditions = conditions(structfun(@(x) isstruct(x) && isfield(x,'trial') && ~isempty(x.trial), rmfield(epochedData, 'cfg')));
    if isempty(conditions), error('No conditions with trials found in epochedData.'); end
elseif iscell(input)
    conditions = input;
else
    error('conditions must be a cell array or ''all''.');
end
end

function tf = isemptyCell(c)
tf = cellfun('isempty', c);
end
