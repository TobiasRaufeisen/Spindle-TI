function participants = ps_resolve_participants(participants, analysis_data_path, session)
%PS_RESOLVE_PARTICIPANTS Auto-detect participant IDs from analysis files.
%
%   participants = ps_resolve_participants(participants, analysis_data_path, session)
%
%   If participants is 'all', scans analysis_data_path for files matching
%   *_<session>_ANALYSIS.mat and extracts participant IDs. Otherwise returns
%   the input unchanged.

    if ~(ischar(participants) && strcmpi(participants, 'all'))
        return;
    end

    files = dir(fullfile(analysis_data_path, sprintf('*_%s_ANALYSIS.mat', session)));
    participants = {};
    for f = 1:length(files)
        tokens = regexp(files(f).name, '^(.+)_\w+_ANALYSIS\.mat$', 'tokens');
        if ~isempty(tokens)
            participants{end+1} = tokens{1}{1}; %#ok<AGROW>
        end
    end
    participants = sort(participants);
    fprintf('Auto-detected %d participants: %s\n', length(participants), strjoin(participants, ', '));
end
