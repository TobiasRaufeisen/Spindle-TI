function allData = spindlePilot_autoRejectChannelsMain(allData)
% Automatic channel rejection on eeg_main using log-variance z > 1.5
% (computed only between STIM_START and STIM_STOP, if available).

subjects = fieldnames(allData);

for i = 1:numel(subjects)
    subj = subjects{i};
    sessions = fieldnames(allData.(subj));

    for j = 1:numel(sessions)
        sess = sessions{j};

        % ----- check EEG presence -----
        if ~isfield(allData.(subj).(sess),'eeg_main') || ...
           isempty(allData.(subj).(sess).eeg_main)
            fprintf('No main EEG data for %s %s, skipping.\n',subj,sess);
            continue;
        end

        fprintf('\n===== AUTO REJECTION %s %s =====\n',subj,sess);
        data   = allData.(subj).(sess).eeg_main;
        labels = data.label(:);
        originalChannels = labels;
        nChan  = numel(labels);

        % ----- concatenate trials -----
        dat = cat(2, data.trial{:});          % [nChan x nSamples]
        t   = cat(2, data.time{:});           % [1 x nSamples], same order

        % ----- find STIM_START / STIM_STOP in event markers -----
        datStim = dat;
        usedStimInterval = false;

        if isfield(allData.(subj).(sess),'eventMarker')
            em = allData.(subj).(sess).eventMarker;

            if isfield(em,'time_series') && isfield(em,'time_stamps') ...
                    && numel(em.time_series) == numel(em.time_stamps)

                iStart = find(strcmp(em.time_series,'STIM_START'),1,'first');
                iStop  = find(strcmp(em.time_series,'STIM_STOP'),1,'last');

                if ~isempty(iStart) && ~isempty(iStop)
                    tStart = em.time_stamps(iStart);
                    tStop  = em.time_stamps(iStop);

                    % map timestamps to nearest EEG sample indices
                    [~, s1] = min(abs(t - tStart));
                    [~, s2] = min(abs(t - tStop));

                    s1 = max(1, min(s1, size(dat,2)));
                    s2 = max(1, min(s2, size(dat,2)));

                    if s2 > s1
                        datStim = dat(:, s1:s2);
                        usedStimInterval = true;
                    end
                end
            end
        end

        if usedStimInterval
            fprintf('Using STIM_START–STIM_STOP interval for variance estimation.\n');
        else
            fprintf('No valid STIM interval; using full data.\n');
        end

        % ----- variance metric (log-variance z > 1.5) -----
        v   = nanvar(datStim,0,2);
        zv  = zscore(log(v + eps));          % log-variance z
        bad = labels(zv > 1.5);              % conservative threshold

        % ensure at least one channel remains
        if numel(bad) >= nChan
            [~,idxKeep] = min(zv);           % keep channel with lowest z
            bad = setdiff(labels, labels(idxKeep));
        end

        fprintf('Rejected (log-var z>1.5): ');
        if isempty(bad)
            fprintf('none\n');
        else
            fprintf('%s\n', strjoin(bad', ', '));
        end

        % ----- build cleaned and rejected datasets -----
        if isempty(bad)
            eeg_clean     = data;
            rejected_data = [];
        else
            cfg_keep = [];
            cfg_keep.channel = setdiff(originalChannels, bad);
            eeg_clean = ft_selectdata(cfg_keep, data);

            cfg_rej = [];
            cfg_rej.channel = bad;
            rejected_data = ft_selectdata(cfg_rej, data);
        end

        keptChannels     = eeg_clean.label;
        rejectedChannels = bad;

        % ----- store results, mirroring your original structure -----
        allData.(subj).(sess).eeg_main             = eeg_clean;
        allData.(subj).(sess).eeg_rejected         = rejected_data;
        allData.(subj).(sess).rejectedChannelsList = rejectedChannels;
        allData.(subj).(sess).keptChannelsList     = keptChannels;
        allData.(subj).(sess).originalChannelsList = originalChannels;
        allData.(subj).(sess).autoBadChannels.var_z1p5 = rejectedChannels;

        fprintf('Summary:\n');
        fprintf('  Original channels: %d\n', numel(originalChannels));
        fprintf('  Kept channels    : %d\n', numel(keptChannels));
        fprintf('  Rejected channels: %d\n', numel(rejectedChannels));
    end
end

fprintf('\nAutomatic channel rejection completed for all subjects and sessions.\n');
end
