%% SPINDLE PILOT - COMPREHENSIVE EVENT ANALYSIS
%
% Builds the master event table for the project: loads per-subject
% YASA detections + preprocessed data, assigns sample-accurate stimulation
% condition, sleep stage, and trial context to every spindle and slow
% wave, and writes summary tables (by stage, condition, subject,
% electrode), a trial-level table, and a per-participant summary.

clear; clc;
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
cd(REPO_ROOT);
spindlePilot_startup();

% =========================================================================
% EXPLICIT PATH DEFINITIONS
% =========================================================================
ANALYSIS_DATA_DIR = fullfile(REPO_ROOT, 'data', 'analysis');  % in-repo, gitignored (see README "Data Availability")
RESULTS_ROOT_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
SLEEP_STAGING_DIR = fullfile(RESULTS_ROOT_DIR, 'SleepStagingAndEvents');
EVENT_DATA_OUTPUT_DIR = RESULTS_ROOT_DIR;
COMPREHENSIVE_OUTPUT_FILE = fullfile(RESULTS_ROOT_DIR, 'comprehensive_analysis.mat');
% =========================================================================


%% CONFIGURATION
subjects = {'sub5', 'sub6', 'sub7','sub8', 'sub9', 'sub10', 'sub11', 'sub12', 'sub13', 'sub14', 'sub15', 'sub16', 'sub17','sub18', 'sub19', 'sub20', 'sub21', 'sub22', 'sub23', 'sub24'};
session = 'ses1';
conditions_to_analyze = {'x1HZ', 'x5HZ', 'OFF', 'x1Hz_refract', 'x5Hz_refract', 'OFF_refract'};
sleep_stages_to_analyze = {'N2', 'N3'};
electrodes_to_analyze = {};

% Analysis parameters
search_window = 6;  % seconds - window for finding adjacent spindles
adjacency_threshold = 5;  % seconds - threshold for adjacent trial detection

% INITIALIZE STORAGE
all_spindles = table();
all_slowwaves = table();
all_sleep_stages = table();
all_condition_durations = table();
subject_spindles = cell(length(subjects), 1);
subject_slowwaves = cell(length(subjects), 1);
subject_sleep_stages = cell(length(subjects), 1);
subject_condition_durations = cell(length(subjects), 1);
analysisData_saved = struct();  % Initialize to accumulate all subjects' data

fprintf('=== COMPREHENSIVE SPINDLE PILOT EVENT ANALYSIS ===\n');
fprintf('Processing %d subjects: %s\n', length(subjects), strjoin(subjects, ', '));

%% MAIN PROCESSING LOOP
for s = 1:length(subjects)
    subject = subjects{s};
    fprintf('\n=== Processing %s (%d/%d) ===\n', subject, s, length(subjects));
    
    % Define file paths - using explicit path definitions
    spindle_csv = fullfile(SLEEP_STAGING_DIR, sprintf('subject%s_spindles.csv', subject(4:end)));
    slowwave_csv = fullfile(SLEEP_STAGING_DIR, sprintf('subject%s_slowwaves.csv', subject(4:end)));
    analysis_mat = fullfile(ANALYSIS_DATA_DIR, sprintf('%s_%s_ANALYSIS.mat', subject, session));
    sleep_stage_txt = fullfile(SLEEP_STAGING_DIR, sprintf('Sleep profile - spindlePilot_%s.txt', subject));

    % Validate all files exist
    files_to_check = {spindle_csv, slowwave_csv, analysis_mat, sleep_stage_txt};
    for f = 1:length(files_to_check)
        if ~exist(files_to_check{f}, 'file')
            error('Required file not found: %s', files_to_check{f});
        end
    end

    % Load raw data
    spindles_raw = readtable(spindle_csv);
    slowwaves_raw = readtable(slowwave_csv);
    sleep_stages = loadSleepStages(sleep_stage_txt);

    % Load and accumulate analysis data for this subject
    temp = load(analysis_mat, 'analysisData_saved');
    if ~isfield(temp.analysisData_saved, subject) || ~isfield(temp.analysisData_saved.(subject), session)
        error('Analysis data not found for %s %s', subject, session);
    end
    analysisData_saved.(subject) = temp.analysisData_saved.(subject);  % Accumulate instead of overwrite

    % Extract timing information
    eeg_data = analysisData_saved.(subject).(session).eeg;
    fsample = eeg_data.fsample;
    continuous_time = eeg_data.time{1};
    n_samples = length(continuous_time);
    epoched_data = analysisData_saved.(subject).(session).epochedData;
    conditions = fieldnames(epoched_data);
    
    fprintf('  EEG: %d Hz, %.2f min, %d samples\n', fsample, continuous_time(end)/60, n_samples);
    
    % Validate event times
    [spindles_raw, slowwaves_raw] = validateEventTimes(spindles_raw, slowwaves_raw, continuous_time);

    spindles = spindles_raw;
    slowwaves = slowwaves_raw;
    fprintf('  Using %d spindles, %d slowwaves\n', height(spindles), height(slowwaves));

    % Calculate precise condition information
    [condition_info, condition_samples] = calculateExactConditionInfo(conditions, epoched_data, continuous_time, fsample);
    
    % Enhance events with precise context
    enhanced_spindles = addPreciseContextToEvents(spindles, sleep_stages, condition_info, condition_samples, continuous_time, fsample, 'Start');
    enhanced_slowwaves = addPreciseContextToEvents(slowwaves, sleep_stages, condition_info, condition_samples, continuous_time, fsample, 'Start');

    % Add phase information to slowwaves for coupling analysis
    phase_params = struct('window_duration', 2.0, 'so_freq_range', [0.5 2], 'filter_order', 3);
    enhanced_slowwaves = addSlowwavePhaseInformation(enhanced_slowwaves, eeg_data, phase_params);

    % Calculate condition sleep information
    condition_sleep_info = calculateConditionSleepInfo(condition_info, sleep_stages, continuous_time, fsample);
    
    % Add subject identifiers
    enhanced_spindles.Subject = repmat({subject}, height(enhanced_spindles), 1);
    enhanced_slowwaves.Subject = repmat({subject}, height(enhanced_slowwaves), 1);
    sleep_stages.Subject = repmat({subject}, height(sleep_stages), 1);
    condition_sleep_info.Subject = repmat({subject}, height(condition_sleep_info), 1);

    % Store in cell arrays for efficient concatenation
    subject_spindles{s} = enhanced_spindles;
    subject_slowwaves{s} = enhanced_slowwaves;
    subject_sleep_stages{s} = sleep_stages;
    subject_condition_durations{s} = condition_sleep_info;

    % Generate individual plots
    % generateComprehensiveVisualization(enhanced_spindles, enhanced_slowwaves, sleep_stages, condition_sleep_info, sprintf('Individual: %s', subject));

    fprintf('  ✓ Complete: %d enhanced spindles, %d enhanced slowwaves\n', height(enhanced_spindles), height(enhanced_slowwaves));
end

% Efficiently concatenate all data
fprintf('\n=== COMBINING DATA FROM ALL SUBJECTS ===\n');
all_spindles = vertcat(subject_spindles{:});
all_slowwaves = vertcat(subject_slowwaves{:});
all_sleep_stages = vertcat(subject_sleep_stages{:});
all_condition_durations = vertcat(subject_condition_durations{:});
stg = string(all_condition_durations.SleepStage);
all_condition_durations = all_condition_durations(~ismember(stg, ["Movement","A"]), :);


fprintf('Combined: %d spindles, %d slowwaves across %d subjects\n', ...
    height(all_spindles), height(all_slowwaves), length(subjects));

%% COMPREHENSIVE TABLE CREATION
fprintf('\n=== CREATING COMPREHENSIVE SUMMARY TABLES ===\n');

% 1. Overall comprehensive summary
fprintf('Creating comprehensive summary statistics...\n');
comprehensive_summary = createComprehensiveSummary(all_spindles, all_slowwaves, all_condition_durations, conditions_to_analyze, sleep_stages_to_analyze);

% 2. Trial-level analysis table  
fprintf('Creating trial-level analysis table...\n');
trial_level_table = createTrialLevelTable(all_spindles, all_slowwaves, analysisData_saved, subjects, session, search_window, adjacency_threshold, conditions_to_analyze, sleep_stages_to_analyze);

% 3. Per-participant summary
fprintf('Creating per-participant summaries...\n');
participant_summary = createParticipantSummary(all_spindles, all_condition_durations, analysisData_saved, ...
    'subjects', subjects, ...
    'conditions', conditions_to_analyze, ...
    'electrodes', electrodes_to_analyze, ...
    'sleep_stages', sleep_stages_to_analyze, ...
    'all_sleep_stages', all_sleep_stages);

%% SAVE RESULTS
fprintf('\n=== SAVING RESULTS ===\n');

% Use explicit path definitions for output
results_dir = EVENT_DATA_OUTPUT_DIR;
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end

%% Save comprehensive results
save_file = COMPREHENSIVE_OUTPUT_FILE;

% Temporarily remove heavy columns from all_slowwaves ONLY for this file
all_slowwaves_backup = all_slowwaves;
cols_to_remove = {'RelativeTime', 'PhaseVector', 'FilteredWaveform'};
cols_to_remove = cols_to_remove(ismember(cols_to_remove, all_slowwaves.Properties.VariableNames));
all_slowwaves(:, cols_to_remove) = [];

save(save_file, ...
    'all_spindles', 'all_slowwaves', 'all_sleep_stages', ...
    'all_condition_durations', 'comprehensive_summary', ...
    'trial_level_table', 'participant_summary', ...
    'subjects', 'conditions_to_analyze', ...
    'sleep_stages_to_analyze', 'electrodes_to_analyze');

% Fall back to -v7.3 if the default format silently dropped a large table.
info = whos('-file', save_file);
names = {info.name};
if ~ismember('all_slowwaves', names)
    save(save_file, ...
        'all_spindles', 'all_slowwaves', 'all_sleep_stages', ...
        'all_condition_durations', 'comprehensive_summary', ...
        'trial_level_table', 'participant_summary', ...
        'subjects', 'conditions_to_analyze', ...
        'sleep_stages_to_analyze', 'electrodes_to_analyze', '-v7.3');
end

% Restore full all_slowwaves for subsequent individual-file saves
all_slowwaves = all_slowwaves_backup;

%% Save individual files (each file independently: v7 first, then v7.3 if needed)
files_to_save = {
    'all_spindles.mat'         'all_spindles'
    'all_slowwaves.mat'        'all_slowwaves'
    'trial_level_analysis.mat' 'trial_level_table'
    'participant_summary.mat'  'participant_summary'
};

for i = 1:size(files_to_save,1)
    target  = fullfile(results_dir, files_to_save{i,1});
    varname = files_to_save{i,2};

    save(target, varname);

    % Fall back to -v7.3 if the default format silently dropped the variable.
    info = whos('-file', target);
    names = {info.name};
    if ~ismember(varname, names)
        save(target, varname, '-v7.3');
    end
end

fprintf('✓ Results saved to: %s\n', results_dir);


fprintf('\n=== ANALYSIS COMPLETE ===\n');
displaySummaryStats(comprehensive_summary);

%% ============== CORE FUNCTIONS ==============

function [spindles_valid, slowwaves_valid] = validateEventTimes(spindles, slowwaves, continuous_time)
    % Drop events that fall outside the continuous recording window.
    
    max_time = continuous_time(end);
    min_time = continuous_time(1);
    
    % Validate spindles
    if ismember('Start', spindles.Properties.VariableNames)
        time_col = 'Start';
    elseif ismember('Peak', spindles.Properties.VariableNames)
        time_col = 'Peak';
    else
        error('No recognizable time column found in spindles table');
    end
    
    spindle_mask = spindles.(time_col) >= min_time & spindles.(time_col) <= max_time;
    invalid_spindles = sum(~spindle_mask);
    if invalid_spindles > 0
        warning('%d spindles (%.1f%%) outside recording bounds [%.2f, %.2f]s', ...
            invalid_spindles, invalid_spindles/height(spindles)*100, min_time, max_time);
    end
    
    % Validate slowwaves
    slowwave_time_col = 'Start';
    if ~ismember(slowwave_time_col, slowwaves.Properties.VariableNames)
        slowwave_time_col = 'NegPeak';
    end
    
    if ismember(slowwave_time_col, slowwaves.Properties.VariableNames)
        slowwave_mask = slowwaves.(slowwave_time_col) >= min_time & slowwaves.(slowwave_time_col) <= max_time;
        invalid_slowwaves = sum(~slowwave_mask);
        if invalid_slowwaves > 0
            warning('%d slowwaves (%.1f%%) outside recording bounds', invalid_slowwaves, invalid_slowwaves/height(slowwaves)*100);
        end
    else
        slowwave_mask = true(height(slowwaves), 1);
    end
    
    spindles_valid = spindles(spindle_mask, :);
    slowwaves_valid = slowwaves(slowwave_mask, :);
end

function [condition_info, condition_samples] = calculateExactConditionInfo(conditions, epoched_data, continuous_time, fsample)
    % Build per-condition trial tables and a boolean sample mask covering
    % every sample that belongs to each condition.
    
    n_samples = length(continuous_time);
    condition_info = table();
    condition_samples = struct();
    
    for c = 1:length(conditions)
        cond_name = conditions{c};
        cond_data = epoched_data.(cond_name);
        
        if ~isfield(cond_data, 'sampleinfo')
            continue;
        end
        
        sample_mask = false(n_samples, 1);
        total_duration_sec = 0;
        trial_count = size(cond_data.sampleinfo, 1);
        trial_info = table();
        
        for trial = 1:trial_count
            start_sample = max(1, min(cond_data.sampleinfo(trial, 1), n_samples));
            end_sample = max(1, min(cond_data.sampleinfo(trial, 2), n_samples));
            
            sample_mask(start_sample:end_sample) = true;
            
            start_time = continuous_time(start_sample);
            end_time = continuous_time(end_sample);
            duration = end_time - start_time;
            
            block_num = 1;
            if isfield(cond_data, 'blocks') && length(cond_data.blocks) >= trial
                block_num = cond_data.blocks(trial);
            end
            
            total_duration_sec = total_duration_sec + duration;
            
            trial_info = [trial_info; table(trial, block_num, start_sample, end_sample, ...
                start_time, end_time, duration, ...
                'VariableNames', {'Trial', 'Block', 'StartSample', 'EndSample', ...
                'StartTime', 'EndTime', 'Duration'})];
        end
        
        condition_info = [condition_info; table({cond_name}, trial_count, total_duration_sec, ...
            total_duration_sec/60, {trial_info}, ...
            'VariableNames', {'Condition', 'NumTrials', 'TotalDuration_sec', ...
            'TotalDuration_min', 'TrialInfo'})];
        
        condition_samples.(cond_name) = sample_mask;
    end
end

function enhanced_events = addPreciseContextToEvents(events, sleep_stages, condition_info, condition_samples, continuous_time, fsample, time_col)
    % Annotate each event with sleep stage, current condition, trial,
    % and previous condition using sample-based matching.
    
    enhanced_events = events;
    enhanced_events.SleepStage = cell(height(events), 1);
    enhanced_events.Condition = cell(height(events), 1);
    enhanced_events.PreviousCondition = cell(height(events), 1);
    enhanced_events.TimeSincePrevCondition = NaN(height(events), 1);
    enhanced_events.EventSample = NaN(height(events), 1);
    enhanced_events.ConditionStartTime = NaN(height(events), 1);
    enhanced_events.TimeFromConditionStart = NaN(height(events), 1);
    
    conditions = fieldnames(condition_samples);
    priority_order = sortConditionsByPriority(conditions);
    
    for i = 1:height(events)
        event_time = events.(time_col)(i);
        event_sample = max(1, min(round(event_time * fsample), length(continuous_time)));
        enhanced_events.EventSample(i) = event_sample;
        
        % Get sleep stage
        enhanced_events.SleepStage{i} = getSleepStageAtTime(event_time, sleep_stages);
        
        % Find condition (prioritized to handle overlaps)
        found_condition = false;
        for c = 1:length(priority_order)
            cond_name = priority_order{c};
            if condition_samples.(cond_name)(event_sample)
                enhanced_events.Condition{i} = cond_name;
                found_condition = true;
                
                % Find specific trial
                trial_info = condition_info.TrialInfo{strcmp(condition_info.Condition, cond_name)};
                for t = 1:height(trial_info)
                    if event_sample >= trial_info.StartSample(t) && event_sample <= trial_info.EndSample(t)
                        enhanced_events.ConditionStartTime(i) = trial_info.StartTime(t);
                        enhanced_events.TimeFromConditionStart(i) = event_time - trial_info.StartTime(t);
                        break;
                    end
                end
                break;
            end
        end
        
        if ~found_condition
            enhanced_events.Condition{i} = 'None';
        end
        
        % Find previous condition
        [prev_cond, time_since] = findPreviousCondition(event_sample, condition_info, condition_samples);
        enhanced_events.PreviousCondition{i} = prev_cond;
        enhanced_events.TimeSincePrevCondition(i) = time_since;
    end
end

function priority_order = sortConditionsByPriority(conditions)
    % Sort conditions so that refractory variants are matched before their
    % parent condition, so an event inside a refractory window is not
    % swallowed by the broader condition mask.
    
    priority_order = {};
    
    % Refractory conditions first (most specific)
    for i = 1:length(conditions)
        if contains(conditions{i}, 'refract', 'IgnoreCase', true)
            priority_order{end+1} = conditions{i};
        end
    end
    
    % Then other conditions
    for i = 1:length(conditions)
        if ~contains(conditions{i}, 'refract', 'IgnoreCase', true)
            priority_order{end+1} = conditions{i};
        end
    end
end

function stage = getSleepStageAtTime(event_time_sec, sleep_stages)
    % Get sleep stage at specific time
    
    stage = 'Wake';  % Default
    
    if height(sleep_stages) == 0
        return;
    end
    
    stage_times_sec = seconds(sleep_stages.Timestamp - sleep_stages.Timestamp(1));
    
    stage_idx = find(stage_times_sec <= event_time_sec, 1, 'last');
    if ~isempty(stage_idx)
        stage = sleep_stages.Stage{stage_idx};
    end
end

function [prev_cond, time_since] = findPreviousCondition(event_sample, condition_info, condition_samples)
    % Find most recent condition before event
    
    prev_cond = 'None';
    time_since = NaN;
    
    latest_end_sample = 0;
    conditions = condition_info.Condition;
    
    for c = 1:length(conditions)
        cond_name = conditions{c};
        trial_info = condition_info.TrialInfo{c};
        
        for t = 1:height(trial_info)
            end_sample = trial_info.EndSample(t);
            if end_sample < event_sample && end_sample > latest_end_sample
                latest_end_sample = end_sample;
                prev_cond = cond_name;
            end
        end
    end
    
    if latest_end_sample > 0
        time_since = (event_sample - latest_end_sample) / 500; % Assuming 500 Hz
    end
end

function condition_sleep_info = calculateConditionSleepInfo(condition_info, sleep_stages, continuous_time, fsample)
    % Calculate detailed sleep stage durations within each condition with full breakdown
    
    condition_sleep_info = table();
    
    if height(sleep_stages) == 0
        return;
    end
    
    stage_times_sec = seconds(sleep_stages.Timestamp - sleep_stages.Timestamp(1));
    unique_stages = unique(sleep_stages.Stage);
    
    for c = 1:height(condition_info)
        cond_name = condition_info.Condition{c};
        trial_info = condition_info.TrialInfo{c};
        
        for stage_idx = 1:length(unique_stages)
            stage = unique_stages{stage_idx};
            total_duration_sec = 0;
            total_samples = 0;
            trials_with_stage = 0;
            time_intervals = [];
            
            % Check each trial for this sleep stage
            for t = 1:height(trial_info)
                trial_start_time = trial_info.StartTime(t);
                trial_end_time = trial_info.EndTime(t);
                trial_start_sample = trial_info.StartSample(t);
                trial_end_sample = trial_info.EndSample(t);
                
                trial_has_stage = false;
                trial_stage_intervals = [];
                
                % Find overlapping sleep stage segments within this trial
                for s = 1:height(sleep_stages)-1
                    stage_start_time = stage_times_sec(s);
                    stage_end_time = stage_times_sec(s+1);
                    
                    if strcmp(sleep_stages.Stage{s}, stage)
                        % Calculate overlap between trial and sleep stage
                        overlap_start_time = max(trial_start_time, stage_start_time);
                        overlap_end_time = min(trial_end_time, stage_end_time);
                        
                        if overlap_end_time > overlap_start_time
                            trial_has_stage = true;
                            overlap_duration = overlap_end_time - overlap_start_time;
                            overlap_samples = round(overlap_duration * fsample);
                            
                            total_duration_sec = total_duration_sec + overlap_duration;
                            total_samples = total_samples + overlap_samples;
                            
                            % Store interval information: [start_time, end_time, trial_number]
                            trial_stage_intervals = [trial_stage_intervals; ...
                                overlap_start_time, overlap_end_time, t];
                        end
                    end
                end
                
                if trial_has_stage
                    trials_with_stage = trials_with_stage + 1;
                    time_intervals = [time_intervals; trial_stage_intervals];
                end
            end
            
            % Only add rows for stages that actually occurred
            if total_duration_sec > 0 || trials_with_stage > 0
                num_intervals = size(time_intervals, 1);
                
                condition_sleep_info = [condition_sleep_info; table({cond_name}, {stage}, ...
                    total_duration_sec, total_duration_sec/60, total_samples, ...
                    trials_with_stage, num_intervals, {time_intervals}, ...
                    'VariableNames', {'Condition', 'SleepStage', 'Duration_sec', 'Duration_min', ...
                    'Samples', 'TrialsWithStage', 'NumIntervals', 'TimeIntervals'})];
            else
                % Add zero entry for completeness
                condition_sleep_info = [condition_sleep_info; table({cond_name}, {stage}, ...
                    0, 0, 0, 0, 0, {[]}, ...
                    'VariableNames', {'Condition', 'SleepStage', 'Duration_sec', 'Duration_min', ...
                    'Samples', 'TrialsWithStage', 'NumIntervals', 'TimeIntervals'})];
            end
        end
    end
end

function sleep_stages = loadSleepStages(filename)
    % Load sleep stage data from text file
    
    if ~exist(filename, 'file')
        warning('Sleep stage file not found: %s', filename);
        sleep_stages = table();
        return;
    end
    
    fid = fopen(filename, 'r');
    if fid == -1
        error('Cannot open sleep stage file: %s', filename);
    end
    
    timestamps = {};
    stages = {};
    
    line = fgetl(fid);
    while ischar(line)
        if contains(line, ';') && ~isempty(strtrim(line))
            parts = strsplit(line, ';');
            if length(parts) >= 2
                timestamp_str = strtrim(parts{1});
                stage_str = strtrim(parts{2});
                
                % Fix comma decimal separator to period for MATLAB datetime parsing
                timestamp_str = strrep(timestamp_str, ',', '.');
                
                dt = datetime(timestamp_str, 'InputFormat', 'dd.MM.yyyy HH:mm:ss.SSS');
                timestamps{end+1} = dt;
                stages{end+1} = stage_str;
            end
        end
        line = fgetl(fid);
    end
    fclose(fid);
    
    if isempty(timestamps)
        warning('No valid sleep stage entries found in: %s', filename);
        sleep_stages = table();
    else
        sleep_stages = table([timestamps{:}]', stages', 'VariableNames', {'Timestamp', 'Stage'});
        fprintf('  Loaded %d sleep stage entries\n', height(sleep_stages));
    end
end

function summary_stats = createComprehensiveSummary(spindles, slowwaves, condition_durations, conditions, sleep_stages)
    % Create comprehensive summary statistics across all dimensions
    
    fprintf('  Computing comprehensive statistics...\n');
    
    summary_stats = struct();
    
    % Overall statistics
    summary_stats.Overall.TotalSpindles = height(spindles);
    summary_stats.Overall.TotalSlowwaves = height(slowwaves);
    summary_stats.Overall.Subjects = unique(spindles.Subject);
    summary_stats.Overall.NumSubjects = length(summary_stats.Overall.Subjects);
    
    % By sleep stage
    summary_stats.BySleepStage = table();
    for s = 1:length(sleep_stages)
        stage = sleep_stages{s};
        stage_spindles = spindles(strcmp(spindles.SleepStage, stage), :);
        stage_slowwaves = slowwaves(strcmp(slowwaves.SleepStage, stage), :);
        stage_durations = condition_durations(strcmp(condition_durations.SleepStage, stage), :);
        
        total_duration_min = sum(stage_durations.Duration_min);
        spindle_density = height(stage_spindles) / max(total_duration_min, 1);
        slowwave_density = height(stage_slowwaves) / max(total_duration_min, 1);
        
        summary_stats.BySleepStage = [summary_stats.BySleepStage; table({stage}, ...
            height(stage_spindles), height(stage_slowwaves), total_duration_min, ...
            spindle_density, slowwave_density, ...
            'VariableNames', {'SleepStage', 'NumSpindles', 'NumSlowwaves', ...
            'Duration_min', 'SpindleDensity', 'SlowwaveDensity'})];
    end
    
    % By condition
    summary_stats.ByCondition = table();
    for c = 1:length(conditions)
        condition = conditions{c};
        cond_spindles = spindles(strcmp(spindles.Condition, condition), :);
        cond_slowwaves = slowwaves(strcmp(slowwaves.Condition, condition), :);
        cond_durations = condition_durations(strcmp(condition_durations.Condition, condition), :);
        
        sleep_durations = cond_durations(ismember(cond_durations.SleepStage, sleep_stages), :);
        total_sleep_min = sum(sleep_durations.Duration_min);
        
        sleep_spindles = cond_spindles(ismember(cond_spindles.SleepStage, sleep_stages), :);
        sleep_slowwaves = cond_slowwaves(ismember(cond_slowwaves.SleepStage, sleep_stages), :);
        
        spindle_density = height(sleep_spindles) / max(total_sleep_min, 1);
        slowwave_density = height(sleep_slowwaves) / max(total_sleep_min, 1);
        
        summary_stats.ByCondition = [summary_stats.ByCondition; table({condition}, ...
            height(cond_spindles), height(cond_slowwaves), total_sleep_min, ...
            spindle_density, slowwave_density, ...
            'VariableNames', {'Condition', 'NumSpindles', 'NumSlowwaves', ...
            'SleepDuration_min', 'SpindleDensity', 'SlowwaveDensity'})];
    end
    
    % By subject
    subjects = unique(spindles.Subject);
    summary_stats.BySubject = table();
    for s = 1:length(subjects)
        subject = subjects{s};
        subj_spindles = spindles(strcmp(spindles.Subject, subject), :);
        subj_slowwaves = slowwaves(strcmp(slowwaves.Subject, subject), :);
        subj_durations = condition_durations(strcmp(condition_durations.Subject, subject), :);
        
        sleep_durations = subj_durations(ismember(subj_durations.SleepStage, sleep_stages), :);
        total_sleep_min = sum(sleep_durations.Duration_min);
        
        sleep_spindles = subj_spindles(ismember(subj_spindles.SleepStage, sleep_stages), :);
        sleep_slowwaves = subj_slowwaves(ismember(subj_slowwaves.SleepStage, sleep_stages), :);
        
        spindle_density = height(sleep_spindles) / max(total_sleep_min, 1);
        slowwave_density = height(sleep_slowwaves) / max(total_sleep_min, 1);
        
        summary_stats.BySubject = [summary_stats.BySubject; table({subject}, ...
            height(subj_spindles), height(subj_slowwaves), total_sleep_min, ...
            spindle_density, slowwave_density, ...
            'VariableNames', {'Subject', 'NumSpindles', 'NumSlowwaves', ...
            'SleepDuration_min', 'SpindleDensity', 'SlowwaveDensity'})];
    end
end

function trial_table = createTrialLevelTable(spindles, slowwaves, analysisData_saved, subjects, session, search_window, adjacency_threshold, conditions, sleep_stages)
    % Create detailed trial-level analysis table
    
    fprintf('  Creating trial-level analysis table...\n');
    
    trial_table = table();
    
    for s = 1:length(subjects)
        subject = subjects{s};
        
        if ~isfield(analysisData_saved, subject) || ~isfield(analysisData_saved.(subject), session)
            continue;
        end
        
        subj_spindles = spindles(strcmp(spindles.Subject, subject), :);
        epoched_data = analysisData_saved.(subject).(session).epochedData;
        eeg_data = analysisData_saved.(subject).(session).eeg;
        continuous_time = eeg_data.time{1};
        
        for c = 1:length(conditions)
            cond_name = conditions{c};
            if ~isfield(epoched_data, cond_name)
                continue;
            end
            
            cond_data = epoched_data.(cond_name);
            if ~isfield(cond_data, 'sampleinfo')
                continue;
            end
            
            trial_count = size(cond_data.sampleinfo, 1);
            
            for trial_idx = 1:trial_count
                start_sample = cond_data.sampleinfo(trial_idx, 1);
                end_sample = cond_data.sampleinfo(trial_idx, 2);
                start_time = continuous_time(max(1, min(start_sample, length(continuous_time))));
                end_time = continuous_time(max(1, min(end_sample, length(continuous_time))));

                % Find spindles in trial
                trial_spindles = subj_spindles(subj_spindles.Start >= start_time & subj_spindles.Start <= end_time, :);
                has_spindle = height(trial_spindles) > 0;
                num_spindles = height(trial_spindles);

                % Spindle metrics
                if has_spindle
                    spindle_latency = min(trial_spindles.Start) - start_time;
                    spindle_channels = unique(trial_spindles.Channel);
                    spindle_amplitude = mean(trial_spindles.Amplitude);
                    spindle_frequency = mean(trial_spindles.Frequency);
                else
                    spindle_latency = NaN;
                    spindle_channels = {''};
                    spindle_amplitude = NaN;
                    spindle_frequency = NaN;
                end

                % Adjacent spindles
                spindles_before = subj_spindles(subj_spindles.Start >= (start_time - search_window) & subj_spindles.Start < start_time, :);
                spindles_after = subj_spindles(subj_spindles.Start > end_time & subj_spindles.Start <= (end_time + search_window), :);

                has_spindle_before = height(spindles_before) > 0;
                has_spindle_after = height(spindles_after) > 0;

                time_since_spindle = NaN;
                time_to_spindle = NaN;

                if has_spindle_before
                    time_since_spindle = start_time - max(spindles_before.Start);
                end
                if has_spindle_after
                    time_to_spindle = min(spindles_after.Start) - end_time;
                end

                block_num = 1;
                if isfield(cond_data, 'blocks') && length(cond_data.blocks) >= trial_idx
                    block_num = cond_data.blocks(trial_idx);
                end

                % Use the trial's position within its block (stored in
                % cond_data.trials) rather than its post-rejection index,
                % so block position is preserved when trials drop out.
                original_trial_num = trial_idx;
                if isfield(cond_data, 'trials') && length(cond_data.trials) >= trial_idx
                    original_trial_num = cond_data.trials(trial_idx);
                end

                trial_table = [trial_table; table({subject}, {cond_name}, original_trial_num, block_num, ...
                    start_sample, end_sample, start_time, end_time, end_time - start_time, ...
                    has_spindle, num_spindles, spindle_latency, {spindle_channels}, ...
                    spindle_amplitude, spindle_frequency, has_spindle_before, time_since_spindle, ...
                    has_spindle_after, time_to_spindle, ...
                    'VariableNames', {'Subject', 'Condition', 'Trial', 'Block', ...
                    'StartSample', 'EndSample', 'StartTime', 'EndTime', 'Duration', ...
                    'HasSpindle', 'NumSpindles', 'SpindleLatency', 'SpindleChannels', ...
                    'SpindleAmplitude', 'SpindleFrequency', 'HasSpindleBefore', 'TimeSinceSpindle', ...
                    'HasSpindleAfter', 'TimeToSpindle'})];
            end
        end
    end
end

function summary_table = createParticipantSummary(all_spindles, all_condition_durations, analysisData_saved, varargin)
    % Create comprehensive per-participant summary
    
    fprintf('  Creating participant summary table...\n');
    
    p = inputParser;
    addParameter(p, 'subjects', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'conditions', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'sleep_stages', {'N2', 'N3'}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'electrodes', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'all_sleep_stages', [], @(x) istable(x));
    parse(p, varargin{:});

    if isempty(p.Results.all_sleep_stages)
        error('all_sleep_stages table must be provided for participant summary');
    end

    subjects = p.Results.subjects;
    if isempty(subjects)
        subjects = unique(all_spindles.Subject);
    else
        subjects = cellstr(subjects);
    end

    conditions = p.Results.conditions;
    if isempty(conditions)
        conditions = unique(all_condition_durations.Condition);
        conditions = conditions(~strcmp(conditions, 'None'));
    else
        conditions = cellstr(conditions);
    end

    sleep_stages = cellstr(p.Results.sleep_stages);
    electrodes = cellstr(p.Results.electrodes);

    % Filter by electrodes if specified
    filtered_spindles = all_spindles;
    if ~isempty(electrodes)
        electrode_mask = false(height(all_spindles), 1);
        for e = 1:length(electrodes)
            electrode_mask = electrode_mask | strcmp(all_spindles.Channel, electrodes{e});
        end
        filtered_spindles = all_spindles(electrode_mask, :);
    end

    summary_table = table();
    
    for s = 1:length(subjects)
        subject = subjects{s};
        subj_spindles = filtered_spindles(strcmp(filtered_spindles.Subject, subject), :);
        subj_durations = all_condition_durations(strcmp(all_condition_durations.Subject, subject), :);
        
        for c = 1:length(conditions)
            condition = conditions{c};
            cond_spindles = subj_spindles(strcmp(subj_spindles.Condition, condition), :);
            cond_durations = subj_durations(strcmp(subj_durations.Condition, condition), :);
            
            for st = 1:length(sleep_stages)
                stage = sleep_stages{st};
                
                stage_cond_spindles = cond_spindles(strcmp(cond_spindles.SleepStage, stage), :);
                stage_cond_durations = cond_durations(strcmp(cond_durations.SleepStage, stage), :);
                
                total_duration_min = sum(stage_cond_durations.Duration_min);
                num_spindles = height(stage_cond_spindles);
                spindle_density = num_spindles / max(total_duration_min, 1);
                
                electrodes_str = strjoin(electrodes, ',');
                if isempty(electrodes_str)
                    electrodes_str = 'All';
                end
                
                summary_table = [summary_table; table({subject}, {condition}, {stage}, {electrodes_str}, ...
                    num_spindles, total_duration_min, spindle_density, ...
                    'VariableNames', {'Subject', 'Condition', 'SleepStage', 'Electrodes', ...
                    'NumSpindles', 'Duration_min', 'SpindleDensity'})];
            end
        end
    end
end

function generateComprehensiveVisualization(spindles, slowwaves, sleep_stages, condition_durations, title_str)
    % Generate comprehensive visualization plots
    
    figure('Position', [100, 100, 1400, 800]);
    sgtitle(sprintf('Comprehensive Analysis: %s', title_str), 'FontSize', 14, 'FontWeight', 'bold');
    
    % Spindle density by condition
    subplot(2, 3, 1);
    conditions = unique(spindles.Condition);
    conditions = conditions(~strcmp(conditions, 'None'));
    densities = zeros(length(conditions), 1);
    
    for c = 1:length(conditions)
        cond_spindles = spindles(strcmp(spindles.Condition, conditions{c}), :);
        cond_durations = condition_durations(strcmp(condition_durations.Condition, conditions{c}), :);
        total_duration = sum(cond_durations.Duration_min);
        densities(c) = height(cond_spindles) / max(total_duration, 1);
    end
    
    bar(densities);
    set(gca, 'XTickLabel', conditions);
    ylabel('Spindle Density (per min)');
    title('Spindle Density by Condition');
    
    % Sleep stage distribution  
    subplot(2, 3, 2);
    if height(condition_durations) > 0
        stages = unique(condition_durations.SleepStage);
        stage_durations = zeros(length(stages), 1);
        for s = 1:length(stages)
            stage_durations(s) = sum(condition_durations.Duration_min(strcmp(condition_durations.SleepStage, stages{s})));
        end
        pie(stage_durations, stages);
        title('Sleep Stage Distribution');
    end
    
    % Spindle amplitude distribution
    subplot(2, 3, 3);
    if height(spindles) > 0 && ismember('Amplitude', spindles.Properties.VariableNames)
        histogram(spindles.Amplitude, 20);
        xlabel('Amplitude (µV)');
        ylabel('Count');
        title('Spindle Amplitude Distribution');
    end
    
    % Spindle frequency distribution
    subplot(2, 3, 4);
    if height(spindles) > 0 && ismember('Frequency', spindles.Properties.VariableNames)
        histogram(spindles.Frequency, 20);
        xlabel('Frequency (Hz)');
        ylabel('Count');
        title('Spindle Frequency Distribution');
    end
    
    % Condition comparison
    subplot(2, 3, 5);
    if length(conditions) > 1
        condition_counts = zeros(length(conditions), 1);
        for c = 1:length(conditions)
            condition_counts(c) = sum(strcmp(spindles.Condition, conditions{c}));
        end
        bar(condition_counts);
        set(gca, 'XTickLabel', conditions);
        ylabel('Number of Spindles');
        title('Spindle Count by Condition');
    end
    
    % Sleep stage vs condition matrix
    subplot(2, 3, 6);
    if height(spindles) > 0
        sleep_stages_unique = unique(spindles.SleepStage);
        sleep_stages_unique = sleep_stages_unique(~strcmp(sleep_stages_unique, 'Wake'));
        
        if ~isempty(sleep_stages_unique) && length(conditions) > 1
            matrix_data = zeros(length(sleep_stages_unique), length(conditions));
            for s = 1:length(sleep_stages_unique)
                for c = 1:length(conditions)
                    matrix_data(s, c) = sum(strcmp(spindles.SleepStage, sleep_stages_unique{s}) & ...
                        strcmp(spindles.Condition, conditions{c}));
                end
            end
            
            imagesc(matrix_data);
            colorbar;
            set(gca, 'XTickLabel', conditions, 'YTickLabel', sleep_stages_unique);
            title('Spindles: Sleep Stage × Condition');
        end
    end
    
    drawnow;
end

function generateConditionDensityPlots(spindles, slowwaves, condition_durations)
    % Generate condition-specific density plots
    
    conditions = unique(spindles.Condition);
    conditions = conditions(~strcmp(conditions, 'None'));
    
    if length(conditions) < 2
        return;
    end
    
    figure('Position', [150, 150, 1200, 400]);
    sgtitle('Condition Density Comparison', 'FontSize', 14, 'FontWeight', 'bold');
    
    subplot(1, 2, 1);
    spindle_densities = zeros(length(conditions), 1);
    for c = 1:length(conditions)
        cond_spindles = spindles(strcmp(spindles.Condition, conditions{c}), :);
        cond_durations = condition_durations(strcmp(condition_durations.Condition, conditions{c}), :);
        sleep_durations = cond_durations(ismember(cond_durations.SleepStage, {'N2', 'N3'}), :);
        total_sleep_min = sum(sleep_durations.Duration_min);
        spindle_densities(c) = height(cond_spindles(ismember(cond_spindles.SleepStage, {'N2', 'N3'}), :)) / max(total_sleep_min, 1);
    end
    
    bar(spindle_densities);
    set(gca, 'XTickLabel', conditions);
    ylabel('Density (per min of N2/N3)');
    title('Spindle Density');
    
    subplot(1, 2, 2);
    slowwave_densities = zeros(length(conditions), 1);
    for c = 1:length(conditions)
        cond_slowwaves = slowwaves(strcmp(slowwaves.Condition, conditions{c}), :);
        cond_durations = condition_durations(strcmp(condition_durations.Condition, conditions{c}), :);
        sleep_durations = cond_durations(ismember(cond_durations.SleepStage, {'N2', 'N3'}), :);
        total_sleep_min = sum(sleep_durations.Duration_min);
        slowwave_densities(c) = height(cond_slowwaves(ismember(cond_slowwaves.SleepStage, {'N2', 'N3'}), :)) / max(total_sleep_min, 1);
    end
    
    bar(slowwave_densities);
    set(gca, 'XTickLabel', conditions);
    ylabel('Density (per min of N2/N3)');
    title('Slowwave Density');
    
    drawnow;
end

function displaySummaryStats(summary_stats)
    % Display key summary statistics
    
    fprintf('\n=== SUMMARY STATISTICS ===\n');
    fprintf('Total Subjects: %d\n', summary_stats.Overall.NumSubjects);
    fprintf('Total Spindles: %d\n', summary_stats.Overall.TotalSpindles);
    fprintf('Total Slowwaves: %d\n', summary_stats.Overall.TotalSlowwaves);
    
    fprintf('\n--- By Condition ---\n');
    disp(summary_stats.ByCondition);
    
    fprintf('\n--- By Sleep Stage ---\n');
    disp(summary_stats.BySleepStage);
end