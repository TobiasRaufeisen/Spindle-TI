function [matched_data, match_info] = spindlePilot_matchTrialCounts(ft_data_struct, varargin)
%SPINDLEPILOT_MATCHTRIALCOUNTS Match trial counts across conditions for spectral analysis
%
% DESCRIPTION:
%   Balances trial counts across conditions by randomly subsampling to the
%   minimum trial count. This is REQUIRED for spectral power analyses (TFR, FFT)
%   where trials are averaged, as unequal trial counts create SNR differences
%   that bias power estimates.
%
%   NOTE: This function should ONLY be used for spectral power analyses.
%         Event-based analyses (spindle density, amplitude, etc.) should NOT
%         use trial matching, as they use normalized metrics and LME models
%         that properly handle unbalanced designs.
%
% USAGE:
%   [matched_data, match_info] = spindlePilot_matchTrialCounts(ft_data_struct)
%   [matched_data, match_info] = spindlePilot_matchTrialCounts(ft_data_struct, 'param', value)
%
% INPUTS:
%   ft_data_struct - Structure containing FieldTrip data per condition
%                    Format: ft_data_struct.CONDITION (e.g., ft_data_struct.x1HZ)
%                    Each condition should be a FieldTrip structure with .trial field
%
% OPTIONAL PARAMETERS:
%   'conditions'    - Cell array of condition names (default: all fields in struct)
%   'random_seed'   - Integer for reproducibility (default: 42)
%   'verbose'       - Boolean for detailed output (default: true)
%   'method'        - 'random' or 'sequential' (default: 'random')
%                     'random': randomly select trials to keep
%                     'sequential': keep first N trials
%
% OUTPUTS:
%   matched_data - Structure with same format as input, but with matched trial counts
%   match_info   - Structure containing matching information:
%       .original_counts    - Original trial counts per condition
%       .matched_count      - Number of trials after matching
%       .kept_trials        - Trial indices kept for each condition
%       .n_removed          - Number of trials removed per condition
%       .random_seed        - Random seed used
%       .conditions         - Conditions that were matched
%
% EXAMPLE:
%   % Load data for multiple conditions
%   data.OFF = ft_data_off;   % 100 trials
%   data.x1HZ = ft_data_1hz;  % 50 trials (fewer due to artifacts)
%   data.x5HZ = ft_data_5hz;  % 90 trials
%
%   % Match trial counts (all will be reduced to 50)
%   [matched_data, info] = spindlePilot_matchTrialCounts(data);
%
%   % Now all conditions have 50 trials with equal SNR
%   fprintf('All conditions now have %d trials\n', info.matched_count);
%
% WHY THIS MATTERS FOR SPECTRAL ANALYSIS:
%   When computing average power spectra or TFR:
%   - Power estimates are averaged across trials
%   - More trials = better SNR (noise cancels out more)
%   - SNR improves by sqrt(N) where N = number of trials
%   - Unequal trials creates systematic bias in power estimates
%
%   Example:
%     Condition A: 100 trials, SNR = 1.0 (baseline)
%     Condition B: 25 trials,  SNR = 0.5 (sqrt(25/100) = 0.5)
%
%   If you compare A vs B, you're comparing both:
%     1. True physiological differences (what you want)
%     2. Measurement quality differences (confound)
%
%   Trial matching removes the measurement quality confound.
%
% SEE ALSO:
%   ft_freqanalysis, ft_selectdata
%
% AUTHOR: Tobias Raufeisen
% DATE: 2025-10-21
% VERSION: 1.0

%% Parse inputs
p = inputParser;
addRequired(p, 'ft_data_struct', @isstruct);
addParameter(p, 'conditions', {}, @iscell);
addParameter(p, 'random_seed', 42, @isnumeric);
addParameter(p, 'verbose', true, @islogical);
addParameter(p, 'method', 'random', @(x) ismember(x, {'random', 'sequential'}));
parse(p, ft_data_struct, varargin{:});

conditions = p.Results.conditions;
random_seed = p.Results.random_seed;
verbose = p.Results.verbose;
method = p.Results.method;

%% Get condition names if not specified
if isempty(conditions)
    conditions = fieldnames(ft_data_struct);
end

n_conditions = length(conditions);

if n_conditions < 2
    error('spindlePilot:matchTrialCounts:TooFewConditions', ...
          'Need at least 2 conditions to match. Found: %d', n_conditions);
end

%% Get original trial counts
original_counts = zeros(1, n_conditions);

for i = 1:n_conditions
    cond = conditions{i};

    if ~isfield(ft_data_struct, cond)
        error('spindlePilot:matchTrialCounts:ConditionNotFound', ...
              'Condition "%s" not found in ft_data_struct', cond);
    end

    ft_data = ft_data_struct.(cond);

    % Check if it's a valid FieldTrip structure
    if ~isfield(ft_data, 'trial')
        error('spindlePilot:matchTrialCounts:InvalidFieldTrip', ...
              'Condition "%s" does not have .trial field (not a valid FieldTrip structure)', cond);
    end

    original_counts(i) = length(ft_data.trial);
end

%% Find minimum trial count
min_trials = min(original_counts);

if verbose
    fprintf('\n=== TRIAL MATCHING FOR SPECTRAL ANALYSIS ===\n');
    fprintf('Original trial counts:\n');
    for i = 1:n_conditions
        fprintf('  %s: %d trials', conditions{i}, original_counts(i));
        if original_counts(i) == min_trials
            fprintf(' (minimum)\n');
        else
            fprintf(' -> will remove %d trials\n', original_counts(i) - min_trials);
        end
    end
    fprintf('Target: %d trials per condition\n', min_trials);
    fprintf('Method: %s\n', method);
    fprintf('Random seed: %d\n\n', random_seed);
end

%% Set random seed for reproducibility
if strcmp(method, 'random')
    rng(random_seed);
end

%% Match trials for each condition
matched_data = struct();
kept_trials = cell(1, n_conditions);

for i = 1:n_conditions
    cond = conditions{i};
    ft_data = ft_data_struct.(cond);
    n_trials = original_counts(i);

    if n_trials == min_trials
        % No need to subsample
        matched_data.(cond) = ft_data;
        kept_trials{i} = 1:n_trials;

        if verbose
            fprintf('%s: Keeping all %d trials (already at minimum)\n', cond, n_trials);
        end
    else
        % Subsample trials
        if strcmp(method, 'random')
            % Random selection
            trial_indices = randperm(n_trials, min_trials);
            trial_indices = sort(trial_indices); % Sort for easier interpretation
        else
            % Sequential selection (first N trials)
            trial_indices = 1:min_trials;
        end

        kept_trials{i} = trial_indices;

        % Use FieldTrip's ft_selectdata to select trials
        cfg = [];
        cfg.trials = trial_indices;
        matched_data.(cond) = ft_selectdata(cfg, ft_data);

        if verbose
            fprintf('%s: Subsampled from %d to %d trials (removed %d trials)\n', ...
                    cond, n_trials, min_trials, n_trials - min_trials);
        end
    end
end

%% Verify matching worked
if verbose
    fprintf('\nVerification:\n');
    for i = 1:n_conditions
        cond = conditions{i};
        n_final = length(matched_data.(cond).trial);
        fprintf('  %s: %d trials\n', cond, n_final);

        if n_final ~= min_trials
            warning('spindlePilot:matchTrialCounts:MatchingFailed', ...
                    'Matching failed for %s: expected %d trials, got %d', ...
                    cond, min_trials, n_final);
        end
    end
    fprintf('Trial matching complete.\n');
    fprintf('===========================================\n\n');
end

%% Package match info
match_info = struct();
match_info.original_counts = original_counts;
match_info.matched_count = min_trials;
match_info.kept_trials = kept_trials;
match_info.n_removed = original_counts - min_trials;
match_info.random_seed = random_seed;
match_info.conditions = conditions;
match_info.method = method;
match_info.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');

% Add summary statistics
match_info.total_trials_original = sum(original_counts);
match_info.total_trials_matched = min_trials * n_conditions;
match_info.total_trials_removed = match_info.total_trials_original - match_info.total_trials_matched;
match_info.pct_removed = (match_info.total_trials_removed / match_info.total_trials_original) * 100;

if verbose
    fprintf('SUMMARY:\n');
    fprintf('  Total trials (original): %d\n', match_info.total_trials_original);
    fprintf('  Total trials (matched):  %d\n', match_info.total_trials_matched);
    fprintf('  Total trials removed:    %d (%.1f%%)\n', ...
            match_info.total_trials_removed, match_info.pct_removed);
    fprintf('\n');
end

end
