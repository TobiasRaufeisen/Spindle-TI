function spindlePilot_add_brewermap(paths)
%SPINDLEPILOT_ADD_BREWERMAP  Add BrewerMap toolbox if it is available.
%   SPINDLEPILOT_ADD_BREWERMAP(PATHS) tries to add the BrewerMap toolbox
%   to the MATLAB path. PATHS is optional and should be the structure
%   returned by `spindlePilot_paths`. If omitted the helper will call
%   `spindlePilot_paths` internally.
%
%   The search order is:
%       1) data_paths.brewermap_toolbox (if defined by the user)
%       2) Environment variable SPINDLEPILOT_BREWERMAP
%       3) <repo_root>/toolboxes/DrosteEffect-BrewerMap-3.2.5.0
%
%   Missing directories simply trigger a warning; the analysis can proceed
%   without the optional colormap helper.

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
