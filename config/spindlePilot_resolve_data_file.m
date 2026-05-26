function file_path = spindlePilot_resolve_data_file(base_dir, patterns, description)
%SPINDLEPILOT_RESOLVE_DATA_FILE  Resolve data files using flexible patterns.
%   FILE_PATH = SPINDLEPILOT_RESOLVE_DATA_FILE(BASE_DIR, PATTERNS, DESCRIPTION)
%   searches the directories listed in BASE_DIR for files matching any of
%   the wildcard PATTERNS (string or cell array of strings). The search
%   prioritises the order of PATTERNS first, and then the order of base
%   directories. The first pattern that yields a match is used and, when
%   multiple files exist for that pattern, the most recently modified one
%   is selected. If no matches are found, the function returns an empty
%   string and prints a warning using DESCRIPTION to explain what was
%   expected.
%
%   Example:
%       spindle_table = spindlePilot_resolve_data_file(paths.results_root, ...
%           {'allOutputTables_noCollectiveSpindles*.mat', ...
%            fullfile('CompiledAnalysisOutput', 'allOutputTables*.mat')}, ...
%           'spindle summary table');
%
%   The helper makes it easier to keep analysis scripts agnostic to the
%   exact versioned filenames produced by upstream pipelines.

    if nargin < 3 || isempty(description)
        description = 'requested file';
    end

    if isstring(patterns) || ischar(patterns)
        patterns = cellstr(patterns);
    elseif ~iscellstr(patterns)
        error('spindlePilot_resolve_data_file:InvalidPatterns', ...
            'PATTERNS must be a character vector, string scalar, or cell array of character vectors.');
    end

    if nargin < 1 || isempty(base_dir)
        base_dirs = {''};
    elseif isstring(base_dir) || ischar(base_dir)
        base_dirs = cellstr(base_dir);
    elseif iscell(base_dir)
        base_dirs = cellfun(@char, base_dir, 'UniformOutput', false);
    else
        error('spindlePilot_resolve_data_file:InvalidBaseDir', ...
            'BASE_DIR must be a character vector, string scalar, or cell array of character vectors.');
    end

    base_dirs = unique(base_dirs, 'stable');

    file_path = '';

    for pat_idx = 1:numel(patterns)
        pattern = patterns{pat_idx};
        for dir_idx = 1:numel(base_dirs)
            current_dir = base_dirs{dir_idx};
            if isempty(current_dir)
                search_pattern = pattern;
            else
                search_pattern = fullfile(current_dir, pattern);
            end

            matches = dir(search_pattern);
            if isempty(matches)
                continue;
            end

            [~, latest_idx] = max([matches.datenum]);
            latest_match = matches(latest_idx);
            file_path = fullfile(latest_match.folder, latest_match.name);
            return;
        end
    end

    if isempty(base_dirs)
        location_msg = '(no base directories provided)';
    else
        location_msg = strjoin(base_dirs, ', ');
    end

    warning('spindlePilot:MissingDataFile', ...
        'Unable to locate %s in %s (patterns tested: %s).', ...
        description, location_msg, strjoin(patterns, ', '));
end
