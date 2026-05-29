function spindlePilot_add_brewermap(paths)

    if nargin < 1 || ~isstruct(paths)
        paths = spindlePilot_paths();
    end

    candidate_paths = {};

    if isfield(paths.data_paths, 'brewermap_toolbox')
        candidate_paths{end+1} = char(paths.data_paths.brewermap_toolbox); %#ok<AGROW>
    end

    env_path = getenv('SPINDLEPILOT_BREWERMAP');
    if ~isempty(env_path)
        candidate_paths{end+1} = env_path; %#ok<AGROW>
    end

    candidate_paths{end+1} = fullfile(paths.repo_root, 'toolboxes', 'DrosteEffect-BrewerMap-3.2.5.0');

    for idx = 1:numel(candidate_paths)
        candidate = candidate_paths{idx};
        if isempty(candidate)
            continue;
        end
        if exist(candidate, 'dir')
            addpath(candidate);
            return;
        end
    end

    warning('spindlePilot:MissingToolbox', ...
        ['DrosteEffect BrewerMap toolbox not found. Set SPINDLEPILOT_BREWERMAP ', ...
         'or data_paths.brewermap_toolbox to the toolbox location.']);
end
