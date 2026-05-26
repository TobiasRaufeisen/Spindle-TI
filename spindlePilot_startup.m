function spindlePilot_startup()
    % STARTUP_PROJECT Initialize the analysis environment
    clear;clc;
    fprintf('Setting up spindlePilot analysis environment...\n');
    
    % Get the project root directory (where this script lives)
    project_root = fileparts(mfilename('fullpath'));
    
    % Add all function directories to MATLAB's search path
    addpath(genpath(fullfile(project_root)));

    % Configure optional toolboxes using environment variables or repo defaults
    repo_root = fileparts(project_root);
    add_optional_path(resolve_path('SPINDLEPILOT_FIELDTRIP', fullfile(repo_root, 'toolboxes', 'fieldtrip')));
    add_optional_path(resolve_path('SPINDLEPILOT_EEGLAB', fullfile(repo_root, 'toolboxes', 'eeglab')));
    add_optional_path(resolve_path('SPINDLEPILOT_SHADEDERROR', fullfile(repo_root, 'toolboxes', 'raacampbell-shadedErrorBar')));
    add_optional_genpath(resolve_path('SPINDLEPILOT_LSL', fullfile(repo_root, 'toolboxes', 'LSL')));

    if exist('ft_defaults', 'file')
        ft_defaults;
    else
        warning('FieldTrip toolbox not found on the MATLAB path. Set SPINDLEPILOT_FIELDTRIP to the toolbox location.');
    end

    % Set up data directories (in-repo data/ folder; gitignored by default)
    data_root = fullfile(project_root, 'data');
    data_paths.raw       = resolve_path('SPINDLEPILOT_RAW',       fullfile(data_root, 'SpindlePilot', 'raw'));
    data_paths.processed = resolve_path('SPINDLEPILOT_PROCESSED', data_root);
    data_paths.analysis  = fullfile(data_root, 'analysis');
    data_paths.results   = fullfile(project_root, '1_eventDetection', 'eventDetectionResults');

    % Make data paths available to other functions
    assignin('base', 'data_paths', data_paths);

    % Create directories if they don't exist (only for directory paths)
    dir_fields = {'raw','processed','analysis','results'};
    for i = 1:length(dir_fields)
        field_name = dir_fields{i};
        if isfield(data_paths, field_name)
            current_path = data_paths.(field_name);
            if ~exist(current_path, 'dir')
                mkdir(current_path);
                fprintf('Created directory: %s\n', current_path);
            end
        end
    end

    % Add optional BrewerMap toolbox using shared helper
    paths = spindlePilot_paths();
    spindlePilot_add_brewermap(paths);

    % Load analysis configuration
    analysis_config();
    
    fprintf('Environment ready!\n');

    function path_out = resolve_path(env_var, fallbacks)
        if nargin < 2
            fallbacks = {};
        end

        path_out = getenv(env_var);
        if ~isempty(path_out)
            path_out = char(path_out);
            if exist(path_out, 'dir')
                return;
            end
        end

        if isstring(fallbacks) || ischar(fallbacks)
            fallbacks = cellstr(fallbacks);
        elseif ~iscell(fallbacks)
            error('resolve_path:InvalidFallback', 'Fallbacks must be a string, char vector, or cell array of char vectors.');
        end

        path_out = '';
        for idx = 1:numel(fallbacks)
            candidate = char(fallbacks{idx});
            if isempty(candidate)
                continue;
            end

            if exist(candidate, 'dir')
                path_out = candidate;
                return;
            end

            if isempty(path_out)
                path_out = candidate;
            end
        end

        if isempty(path_out)
            path_out = '';
        end
    end

    function add_optional_path(path_to_add)
        if isempty(path_to_add)
            return;
        end
        if exist(path_to_add, 'dir')
            addpath(path_to_add);
        end
    end

    function add_optional_genpath(path_to_add)
        if isempty(path_to_add)
            return;
        end
        if exist(path_to_add, 'dir')
            addpath(genpath(path_to_add));
        end
    end
end