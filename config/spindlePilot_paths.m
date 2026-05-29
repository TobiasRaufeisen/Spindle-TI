function paths = spindlePilot_paths()
%SPINDLEPILOT_PATHS  Resolve common SpindlePilot directories.
%   PATHS = SPINDLEPILOT_PATHS() returns the directories needed by the
%   BrewerMap helper and the BIDS export. It honours overrides placed in the
%   base-workspace `data_paths` struct by spindlePilot_startup and otherwise
%   falls back to repo-relative defaults under <project>/data.
%
%   Fields:
%       repo_root              - Parent of the project (holds toolboxes/)
%       project_root           - Root of analysis_spindlePilot
%       data_paths             - Passthrough of base-workspace overrides
%       results_root           - 1_eventDetection/eventDetectionResults
%       processed.analysis     - Folder of sub<N>_ses1_ANALYSIS.mat files
%       results.sleep_staging  - YASA sleep-staging / events output
%
%   See also: spindlePilot_startup, spindlePilot_add_brewermap,
%             spindlePilot_export_bids

    config_dir   = fileparts(mfilename('fullpath'));
    project_root = fileparts(config_dir);

    paths.repo_root    = fileparts(project_root);
    paths.project_root = project_root;
    paths.results_root = fullfile(project_root, '1_eventDetection', 'eventDetectionResults');

    % Pull overrides supplied by spindlePilot_startup if present
    if evalin('base', 'exist(''data_paths'', ''var'')')
        data_paths = evalin('base', 'data_paths');
    else
        data_paths = struct();
    end
    paths.data_paths = data_paths;

    processed_root = get_path(data_paths, 'processed', fullfile(project_root, 'data'));
    paths.processed.analysis = get_path(data_paths, 'analysis', fullfile(processed_root, 'analysis'));

    paths.results.sleep_staging = fullfile(paths.results_root, 'SleepStagingAndEvents_v3');

    function resolved = get_path(structure, field_name, fallback)
        resolved = fallback;
        if isfield(structure, field_name)
            candidate = structure.(field_name);
            if ~(ischar(candidate) || (isstring(candidate) && isscalar(candidate)))
                error('spindlePilot_paths:InvalidField', ...
                    'data_paths.%s must be a character vector or scalar string.', field_name);
            end
            candidate = char(candidate);
            if ~isempty(candidate)
                resolved = candidate;
            end
        end
    end
end
