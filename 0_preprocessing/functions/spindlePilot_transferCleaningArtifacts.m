function allData = spindlePilot_transferCleaningArtifacts(allData, cleaningReport)
% spindlePilot_transferCleaningArtifacts - Transfer artifact info from cleanMainEEG to allData
%
% This function takes the artifact information from spindlePilot_cleanMainEEG
% (which interpolates artifacts during filtering) and transfers it into the
% allData structure so that trials overlapping with these artifacts can be
% properly rejected during epoching.
%
% IMPORTANT: This should be called immediately after spindlePilot_cleanMainEEG
% to ensure artifact timing information is preserved for trial rejection.
%
% Usage:
%   [allData, report] = spindlePilot_cleanMainEEG(allData);
%   allData = spindlePilot_transferCleaningArtifacts(allData, report);
%
% Inputs:
%   allData        - Main data structure
%   cleaningReport - Report structure from spindlePilot_cleanMainEEG containing
%                    artifact timing information
%
% Output:
%   allData - Updated structure with artifact information stored in:
%             allData.(subject).(session).artifactTimes [Nx2] array of [start, end] times
%             allData.(subject).(session).artifactSamples [Nx2] array of [start, end] samples
%             allData.(subject).(session).artifactInfo - complete artifact metadata
%
% The artifact information will then be used by spindlePilot_createEpochsAllData
% to separate trials with artifacts into epochedData_withArtifacts.

if nargin < 2 || isempty(cleaningReport)
    warning('No cleaning report provided. No artifacts will be transferred.');
    return;
end

fprintf('Transferring artifact information from cleaning report to allData structure...\n');

subs = fieldnames(cleaningReport);

for isub = 1:numel(subs)
    sub = subs{isub};

    if ~isfield(allData, sub)
        warning('Subject %s in report but not in allData. Skipping.', sub);
        continue;
    end

    sessNames = fieldnames(cleaningReport.(sub));

    for isess = 1:numel(sessNames)
        sess = sessNames{isess};

        if ~isfield(allData.(sub), sess)
            warning('Session %s for subject %s in report but not in allData. Skipping.', sess, sub);
            continue;
        end

        rep = cleaningReport.(sub).(sess);

        % Check if artifacts were detected
        if ~isfield(rep, 'artifacts') || isempty(rep.artifacts)
            fprintf('  %s|%s: No artifacts detected during cleaning\n', sub, sess);
            continue;
        end

        artifacts = rep.artifacts;
        n_artifacts = numel(artifacts);

        if n_artifacts == 0
            fprintf('  %s|%s: No artifacts to transfer\n', sub, sess);
            continue;
        end

        % Extract artifact times and samples
        artifactTimes = zeros(n_artifacts, 2);
        artifactSamples = zeros(n_artifacts, 2);

        for k = 1:n_artifacts
            artifactTimes(k, :) = [artifacts(k).startTime, artifacts(k).endTime];
            artifactSamples(k, :) = [artifacts(k).startSample, artifacts(k).endSample];
        end

        % Calculate total artifact duration and percentage
        total_duration = sum(artifactTimes(:, 2) - artifactTimes(:, 1));

        % Get recording duration from eeg_main if available
        if isfield(allData.(sub).(sess), 'eeg_main') && ...
           ~isempty(allData.(sub).(sess).eeg_main)
            eeg_time = allData.(sub).(sess).eeg_main.time{1};
            recording_duration = eeg_time(end) - eeg_time(1);
            artifact_percentage = (total_duration / recording_duration) * 100;
        else
            artifact_percentage = NaN;
        end

        % Store artifact information in allData structure
        % This matches the format expected by spindlePilot_createEpochsAllData
        allData.(sub).(sess).artifactTimes = artifactTimes;
        allData.(sub).(sess).artifactSamples = artifactSamples;
        allData.(sub).(sess).artifactDuration = total_duration;
        allData.(sub).(sess).artifactPercentage = artifact_percentage;
        allData.(sub).(sess).artifactMethod = 'slope_interpolation';

        % Store complete artifact information in artifactInfo structure
        allData.(sub).(sess).artifactInfo = struct();
        allData.(sub).(sess).artifactInfo.artifactTimes = artifactTimes;
        allData.(sub).(sess).artifactInfo.artifactSamples = artifactSamples;
        allData.(sub).(sess).artifactInfo.total_duration = total_duration;
        allData.(sub).(sess).artifactInfo.percentage = artifact_percentage;
        allData.(sub).(sess).artifactInfo.method = 'slope_interpolation';
        allData.(sub).(sess).artifactInfo.detection_channel = rep.detection_ch;
        allData.(sub).(sess).artifactInfo.params = rep.params;
        allData.(sub).(sess).artifactInfo.n_detected = rep.n_detected;
        allData.(sub).(sess).artifactInfo.n_interpolated = rep.n_interpolated;

        % Create artifact mask for the full recording
        if isfield(allData.(sub).(sess), 'eeg_main') && ...
           ~isempty(allData.(sub).(sess).eeg_main)
            n_samples = length(allData.(sub).(sess).eeg_main.time{1});
            artifact_mask = false(1, n_samples);

            for k = 1:n_artifacts
                start_samp = max(1, artifactSamples(k, 1));
                end_samp = min(n_samples, artifactSamples(k, 2));
                artifact_mask(start_samp:end_samp) = true;
            end

            allData.(sub).(sess).artifactInfo.artifact_mask = artifact_mask;
        end

        % Report
        fprintf('  %s|%s: Transferred %d artifacts (%.2f s, %.1f%% of recording)\n', ...
                sub, sess, n_artifacts, total_duration, artifact_percentage);
        fprintf('    Detection channel: %s\n', rep.detection_ch);
        fprintf('    Method: Slope-based detection with interpolation\n');

        % Show individual artifacts (limit to first 10 for readability)
        n_to_show = min(10, n_artifacts);
        for k = 1:n_to_show
            duration = artifactTimes(k, 2) - artifactTimes(k, 1);
            fprintf('    Artifact %d: %.2f - %.2f s (%.3f s, samples %d-%d)\n', ...
                    k, artifactTimes(k, 1), artifactTimes(k, 2), duration, ...
                    artifactSamples(k, 1), artifactSamples(k, 2));
        end

        if n_artifacts > n_to_show
            fprintf('    ... and %d more artifacts\n', n_artifacts - n_to_show);
        end
    end
end

fprintf('\nArtifact transfer complete.\n');
fprintf('These artifacts will be used by spindlePilot_createEpochsAllData to separate\n');
fprintf('trials with artifacts into epochedData_withArtifacts.\n');

end
