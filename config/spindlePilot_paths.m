function paths = spindlePilot_paths()
%SPINDLEPILOT_PATHS  Resolve common directories used by the SpindlePilot project.
%   PATHS = SPINDLEPILOT_PATHS() gathers frequently used directories for
%   the SpindlePilot analyses. It relies on the `data_paths` structure
%   created by `spindlePilot_startup` when available and falls back to
%   sensible defaults that live relative to the repository root. The
%   returned structure contains fields for processed data, intermediate
%   results, and figure output locations so analysis scripts no longer
%   need to hard-code absolute paths.
%
%   The function never creates directories; analysis scripts should call
%   `spindlePilot_ensure_dir` (or MATLAB's `mkdir`) when they need to
%   materialise an output path.
%
%   =========================================================================
%   VERSION INFORMATION
%   =========================================================================
%   Current Data Version:    v3
%   Current Results Version: v3 (SleepStagingAndEvents)
%   =========================================================================
%
%   Fields in the returned structure:
%       repo_root                - Top level of the git repository
%       project_root             - Root of `analysis_spindlePilot`
%       results_root             - Directory containing saved results (1_eventDetection/eventDetectionResults)
%       processed_root           - Base directory for processed data
%       raw_root                 - Base directory for raw data
%
%   Processed data subdirectories (paths.processed.*):
%       analysis                 - `analysis` subdirectory under processed data
%       freqpower                - `freqpower` subdirectory under processed data
%       freqpower_results        - `freqpower/results`
%       timefreq                 - `timefreq` subdirectory under processed data
%       timefreq_results         - `timefreq/results`
%       tfr_output               - `tfrOutput` directory
%       tfr_output_struct        - `tfrOutput_STRUCT` directory
%       edf                      - EDF export directory
%
%   Results subdirectories (paths.results.*):
%       sleep_staging            - Sleep staging and events (v3)
%       comprehensive            - Comprehensive analysis output (v3)
%       sleep_descriptives       - 1_sleepDescriptives output
%       event_descriptives       - 2_sleepEventDescriptives output
%       spindle_stats            - 3_spindleEventStats output
%       slowwave_stats           - 4_slowwaveEventStats output
%       power_stats              - 5_powerDescriptivesStats output
%       coupling                 - 6_spindleCoupling output
%       field_strength           - 7_fieldStrengthModelling output
%       control                  - 8_controlAnalyses output
%       tfa_figures              - Time-frequency analysis figures
%       freqpower_figures        - Frequency power figures
%       density_figures          - Spindle density timeline figures
%
%   The structure also exposes the original `data_paths` fields (if
%   present) so scripts can access any custom definitions.
%
%   See also: spindlePilot_startup, spindlePilot_resolve_data_file

    % =========================================================================
    % VERSION CONFIGURATION - Update these when changing data/results versions
    % =========================================================================
    PROCESSED_DATA_VERSION = 'v3';           % Current processed data version
    RESULTS_VERSION = 'v3';                   % Current results version
    % =========================================================================

    config_dir = fileparts(mfilename('fullpath'));
    project_root = fileparts(config_dir);
    repo_root = fileparts(project_root);

    paths.repo_root = repo_root;
    paths.project_root = project_root;
    paths.results_root = fullfile(project_root, '1_eventDetection', 'eventDetectionResults');

    % Store version info for reference
    paths.version.processed_data = PROCESSED_DATA_VERSION;
    paths.version.results = RESULTS_VERSION;

    % Pull the user provided data paths if they exist
    if evalin('base', 'exist(''data_paths'', ''var'')')
        data_paths = evalin('base', 'data_paths');
    else
        data_paths = struct();
    end
    paths.data_paths = data_paths;

    % Data lives in an in-repo, gitignored `data/` folder (see README "Data Availability").
    data_root = fullfile(project_root, 'data');

    % Raw data path
    local_default_raw = fullfile(data_root, 'SpindlePilot');
    paths.raw_root = get_path(data_paths, 'raw', local_default_raw);

    % Processed data path - analysis .mat files live under <repo>/data/analysis
    local_default_processed = data_root;
    paths.processed_root = get_path(data_paths, 'processed', local_default_processed);


    % Processed data subdirectories
    paths.processed.analysis = get_path(data_paths, 'analysis', fullfile(paths.processed_root, 'analysis'));
    paths.processed.freqpower = get_path(data_paths, 'freqpower', fullfile(paths.processed_root, 'freqpower'));
    paths.processed.freqpower_results = get_path(data_paths, 'freqpower_results', fullfile(paths.processed.freqpower, 'results'));
    paths.processed.timefreq = get_path(data_paths, 'timefreq', fullfile(paths.processed_root, 'timefreq'));
    paths.processed.timefreq_results = get_path(data_paths, 'timefreq_results', fullfile(paths.processed.timefreq, 'results'));
    paths.processed.tfr_output = get_path(data_paths, 'tfr_output', fullfile(paths.processed_root, 'tfrOutput'));
    paths.processed.tfr_output_struct = get_path(data_paths, 'tfr_output_struct', fullfile(paths.processed_root, 'tfrOutput_STRUCT'));
    paths.processed.edf = get_path(data_paths, 'edf', fullfile(paths.processed_root, 'EDF'));

    % Results subdirectories - version-specific
    paths.results.sleep_staging = fullfile(paths.results_root, ['SleepStagingAndEvents_' RESULTS_VERSION]);

    % Figure output directories
    paths.results.figure1_outputs = fullfile(project_root, '2_FIGURE1_MethodsAndDetection', 'outputs');
    paths.results.figure2_outputs = fullfile(project_root, '3_FIGURE2_Power', 'outputs');
    paths.results.figure3_outputs = fullfile(project_root, '4_FIGURE3_Events', 'outputs');

    % TFR data directories
    paths.results.tfr_base = fullfile(project_root, '3_FIGURE2_Power', 'TFR_1HzSmoothing');
    paths.results.tfr_spindle = fullfile(paths.results.tfr_base, 'spindle_trials');
    paths.results.tfr_base_orig = fullfile(project_root, '3_FIGURE2_Power', 'TFR');
    paths.results.tfr_spindle_orig = fullfile(paths.results.tfr_base_orig, 'spindle_trials');

    % Helper --------------------------------------------------------------
    function resolved = get_path(structure, field_name, fallback)
        if isfield(structure, field_name)
            candidate = structure.(field_name);
            if ~(ischar(candidate) || (isstring(candidate) && isscalar(candidate)))
                error('spindlePilot_paths:InvalidField', ...
                    'data_paths.%s must be a character vector or scalar string.', field_name);
            end
            candidate = char(candidate);
            if ~isempty(candidate)
                resolved = candidate;
                return;
            end
        end
        resolved = fallback;
    end
end
