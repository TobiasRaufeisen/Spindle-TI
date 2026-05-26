function common_time = find_common_time(all_data, participants, conditions)
% Find overlapping time vector across all participants and conditions.
%
% INPUTS
%   all_data     - struct.(participant).(condition).time
%   participants - cell array of participant IDs
%   conditions   - cell array of condition labels
%
% OUTPUT
%   common_time  - time vector covering the intersection of all axes

common_time = [];

for p = 1:length(participants)
    participant = participants{p};
    if ~isfield(all_data, participant), continue; end

    for c = 1:length(conditions)
        if ~isfield(all_data.(participant), conditions{c}), continue; end

        t = all_data.(participant).(conditions{c}).time;
        if isempty(common_time)
            common_time = t;
        else
            t_start = max(common_time(1), t(1));
            t_end   = min(common_time(end), t(end));
            common_time = common_time(common_time >= t_start & common_time <= t_end);
        end
    end
end
end
