function spindlePilot_bids_subject(subNum, rawRoot, bidsRoot, metaDir, task, opts)
% SPINDLEPILOT_BIDS_SUBJECT  Convert one subject's raw XDF to BIDS BrainVision + sidecars,
% and optionally also write the TI stimulator readback as a derivative.
%
%   spindlePilot_bids_subject(SUBNUM, RAWROOT, BIDSROOT, METADIR, TASK, OPTS)
%
%   Inputs
%     subNum     Numeric subject id (5..24). Recorder-side folder is
%                sub-P<SUBNUM, zero-padded to 3>; published BIDS id is
%                sub-<SUBNUM, zero-padded to 2>.
%     rawRoot    Path containing sub-P*/ses-S*/eeg/*.xdf (e.g. <repo>/data/raw).
%     bidsRoot   Output BIDS root (e.g. <repo>/data/bids).
%     metaDir    Folder holding the shared metadata templates
%                (task-spindleti_eeg.json, ...).
%     task       Task name string (default 'spindleti').
%     opts       Optional struct of flags:
%                  .writeRaw            (default true)  - write the BIDS BrainVision raw EEG + sidecars
%                  .writeTI             (default true)  - write the TI / DAQ readback into
%                                                         derivatives/ti-stimulation/
%                  .refreshSidecarsOnly (default false) - skip XDF reload and binary EEG;
%                                                         rewrite per-subject sidecars
%                                                         (_eeg.json, _channels.tsv) from the
%                                                         current template, sanitize _scans.tsv,
%                                                         and migrate filenames from run-1 to
%                                                         run-01 if needed.
%
% Author: Tobias Raufeisen

    arguments
        subNum   (1,1) double
        rawRoot  (1,:) char
        bidsRoot (1,:) char
        metaDir  (1,:) char
        task     (1,:) char = 'spindleti'
        opts     struct    = struct()
    end

    if ~isfield(opts,'writeRaw');            opts.writeRaw = true; end
    if ~isfield(opts,'writeTI');             opts.writeTI  = true; end
    if ~isfield(opts,'refreshSidecarsOnly'); opts.refreshSidecarsOnly = false; end

    assert(subNum >= 5 && subNum <= 24, ...
        'spindlePilot_bids_subject:OutOfRange', ...
        'subNum=%d is outside the published range (5..24); pilots P001..P004 are excluded.', subNum);

    bidsSub = sprintf('%02d', subNum);
    ses     = '01';
    run     = '01';

    if opts.refreshSidecarsOnly
        refreshSidecarsForSubject(bidsRoot, bidsSub, ses, task, run, metaDir);
        return;
    end

    fprintf('\n=== sub-%s : loading XDF ===\n', bidsSub);
    allData = spindlePilot_loadData(rawRoot, subNum, 1);
    allData = spindlePilot_relabelElectrodes(allData);

    subField = sprintf('sub%d', subNum);
    sesField = 'ses1';
    eeg      = allData.(subField).(sesField).eeg;
    markers  = allData.(subField).(sesField).eventMarker;
    tiStream = allData.(subField).(sesField).TI;

    [eeg, dropped] = dropChannels(eeg, {'XX','XXX','AUX_4','Markers'});
    if ~isempty(dropped)
        fprintf('  dropped channels: %s\n', strjoin(dropped, ', '));
    end

    fs = double(eeg.fsample);  % keep full precision; actiCHamp ~10000.13 Hz, not exactly 10000
    % Recording-start reference for event onsets and the TI StartTime. Use the first
    % EEG sample's LSL timestamp: this is exactly what spindlePilot_createEpochsAllData
    % uses (raw_t(1)), so the BIDS onsets stay consistent with the analysis epochs.
    % For xdf2fieldtrip this equals eeg.hdr.FirstTimeStamp, but time{1}(1) is the
    % authoritative axis and stays correct even if the time axis is re-referenced upstream.
    eegStartTime = eeg.time{1}(1);

    if opts.writeRaw
        eventsTable     = spindlePilot_bids_events(markers, eegStartTime);
        channelsTable   = spindlePilot_bids_channels(eeg.label, fs);
        eegOnlyLabels   = channelsTable.name(strcmp(channelsTable.type,'EEG'));
        electrodesTable = spindlePilot_bids_electrodes(eegOnlyLabels);

        cfg                       = [];
        cfg.method                = 'convert';
        cfg.dataformat            = 'brainvision_eeg';
        cfg.bidsroot              = bidsRoot;
        cfg.sub                   = bidsSub;
        cfg.ses                   = ses;
        cfg.task                  = task;
        cfg.run                   = run;
        cfg.datatype              = 'eeg';
        % Overwrite the per-run channels/electrodes/events TSVs instead of the
        % data2bids default ('merge'). We always regenerate from raw, and the
        % full-row merge of events.tsv would otherwise APPEND a second copy of
        % every event when re-exporting into a non-empty bids root (duplicated,
        % unsorted events). participants.tsv / scans.tsv are merged separately
        % by data2bids and are unaffected by this option.
        cfg.writetsv              = 'replace';

        cfg.dataset_description   = jsondecode(fileread(fullfile(metaDir,'dataset_description.json')));
        cfg.eeg                   = jsondecode(fileread(fullfile(metaDir,'task-spindleti_eeg.json')));
        cfg.eeg.SamplingFrequency = fs;
        cfg.coordsystem           = jsondecode(fileread(fullfile(metaDir,'coordsystem.json')));

        cfg.channels.name                = channelsTable.name;
        cfg.channels.type                = channelsTable.type;
        cfg.channels.units               = channelsTable.units;
        cfg.channels.sampling_frequency  = channelsTable.sampling_frequency;
        cfg.channels.low_cutoff          = channelsTable.low_cutoff;
        cfg.channels.high_cutoff         = channelsTable.high_cutoff;
        cfg.channels.notch               = channelsTable.notch;
        cfg.channels.status              = channelsTable.status;
        cfg.channels.status_description  = channelsTable.status_description;

        cfg.electrodes.name = electrodesTable.name;
        cfg.electrodes.x    = electrodesTable.x;
        cfg.electrodes.y    = electrodesTable.y;
        cfg.electrodes.z    = electrodesTable.z;

        cfg.events = eventsTable;

        fprintf('  writing BIDS BrainVision via data2bids ...\n');
        data2bids(cfg, eeg);

        scansPath = fullfile(bidsRoot, ['sub-' bidsSub], ['ses-' ses], ...
                             sprintf('sub-%s_ses-%s_scans.tsv', bidsSub, ses));
        normaliseScansTsvPaths(scansPath);
    else
        fprintf('  (writeRaw=false; skipping BrainVision + sidecar write)\n');
    end

    if opts.writeTI
        tiBase = sprintf('sub-%s_ses-%s_task-%s_recording-ti', bidsSub, ses, task);
        tiDir  = fullfile(bidsRoot, 'derivatives', 'ti-stimulation', ...
                          ['sub-' bidsSub], ['ses-' ses], 'eeg');
        rawEegRelPath = sprintf('sub-%s/ses-%s/eeg/sub-%s_ses-%s_task-%s_run-%s_eeg.vhdr', ...
                                bidsSub, ses, bidsSub, ses, task, run);
        writeTiPipelineDescription(fullfile(bidsRoot,'derivatives','ti-stimulation'));
        spindlePilot_bids_ti(tiStream, eegStartTime, tiDir, tiBase, rawEegRelPath);
    end
end

function refreshSidecarsForSubject(bidsRoot, bidsSub, ses, task, run, metaDir)
% Rewrite per-subject sidecars from the current template without touching
% the binary EEG. Also migrate any legacy run-1 filenames to run-01 in place.

    fprintf('\n=== sub-%s : refreshing sidecars ===\n', bidsSub);
    eegDir = fullfile(bidsRoot, ['sub-' bidsSub], ['ses-' ses], 'eeg');
    if ~exist(eegDir, 'dir')
        error('refreshSidecarsForSubject:Missing', ...
              'No BIDS output for sub-%s at %s', bidsSub, eegDir);
    end

    legacyRun  = '1';
    legacyBase = sprintf('sub-%s_ses-%s_task-%s_run-%s', bidsSub, ses, task, legacyRun);
    targetBase = sprintf('sub-%s_ses-%s_task-%s_run-%s', bidsSub, ses, task, run);

    if ~strcmp(legacyBase, targetBase) && exist(fullfile(eegDir, [legacyBase '_eeg.vhdr']), 'file')
        fprintf('  migrating filenames run-%s -> run-%s\n', legacyRun, run);
        renameSuffixes(eegDir, legacyBase, targetBase, ...
            {'_eeg.eeg', '_eeg.vhdr', '_eeg.vmrk', '_eeg.json', ...
             '_channels.tsv', '_events.tsv'});
        rewriteHeaderFileRefs(fullfile(eegDir, [targetBase '_eeg.vhdr']), legacyBase, targetBase);
        rewriteHeaderFileRefs(fullfile(eegDir, [targetBase '_eeg.vmrk']), legacyBase, targetBase);
    end

    vhdrPath = fullfile(eegDir, [targetBase '_eeg.vhdr']);
    if ~exist(vhdrPath, 'file')
        error('refreshSidecarsForSubject:NoVhdr', 'Missing %s', vhdrPath);
    end

    % Prefer the existing _eeg.json's full-precision SamplingFrequency and
    % RecordingDuration over re-deriving from the .vhdr (which truncates
    % SamplingInterval to 6 decimal microseconds, losing ~3 ppm).
    eegJsonPath = fullfile(eegDir, [targetBase '_eeg.json']);
    [fsFromVhdr, nSamplesFromVhdr] = parseSamplingFromVhdr(vhdrPath);
    fs                = fsFromVhdr;
    recordingDuration = (nSamplesFromVhdr - 1) / fs;
    if exist(eegJsonPath, 'file')
        try
            old = jsondecode(fileread(eegJsonPath));
            if isfield(old, 'SamplingFrequency') && isfinite(old.SamplingFrequency) && old.SamplingFrequency > 0
                fs = old.SamplingFrequency;
            end
            if isfield(old, 'RecordingDuration') && isfinite(old.RecordingDuration) && old.RecordingDuration > 0
                recordingDuration = old.RecordingDuration;
            end
        catch
        end
    end

    eegJson = jsondecode(fileread(fullfile(metaDir, 'task-spindleti_eeg.json')));
    eegJson.SamplingFrequency = fs;
    eegJson.RecordingDuration = recordingDuration;
    eegJson.EEGChannelCount   = 30;
    eegJson.EOGChannelCount   = 2;
    eegJson.EMGChannelCount   = 1;
    writeJsonFile(eegJson, eegJsonPath);

    channelLabels = parseChannelLabelsFromVhdr(vhdrPath);
    channelsTable = spindlePilot_bids_channels(channelLabels, fs);
    writetable(channelsTable, fullfile(eegDir, [targetBase '_channels.tsv']), ...
        'FileType', 'text', 'Delimiter', '\t');

    scansPath = fullfile(bidsRoot, ['sub-' bidsSub], ['ses-' ses], ...
                         sprintf('sub-%s_ses-%s_scans.tsv', bidsSub, ses));
    if exist(scansPath, 'file')
        rewriteScansTsvForRenamedRun(scansPath, legacyBase, targetBase);
        normaliseScansTsvPaths(scansPath);
    end

    fprintf('  sidecars refreshed (fs=%.6f Hz, %.3f s)\n', fs, recordingDuration);
end

function renameSuffixes(eegDir, oldBase, newBase, suffixes)
    for k = 1:numel(suffixes)
        src = fullfile(eegDir, [oldBase suffixes{k}]);
        dst = fullfile(eegDir, [newBase suffixes{k}]);
        if exist(src, 'file')
            movefile(src, dst);
        end
    end
end

function rewriteHeaderFileRefs(path, oldBase, newBase)
    if ~exist(path, 'file'); return; end
    txt = fileread(path);
    txt = strrep(txt, [oldBase '_eeg.eeg'],  [newBase '_eeg.eeg']);
    txt = strrep(txt, [oldBase '_eeg.vmrk'], [newBase '_eeg.vmrk']);
    fid = fopen(path, 'w');
    fwrite(fid, txt, 'char');
    fclose(fid);
end

function [fs, nSamples] = parseSamplingFromVhdr(vhdrPath)
    txt = fileread(vhdrPath);
    intervalUs = regexp(txt, 'SamplingInterval=([\d.eE+-]+)', 'tokens', 'once');
    if isempty(intervalUs)
        error('parseSamplingFromVhdr:NoInterval', 'SamplingInterval not found in %s', vhdrPath);
    end
    fs = 1 / (str2double(intervalUs{1}) * 1e-6);
    [eegDir, name, ~] = fileparts(vhdrPath);
    dataMatch = regexp(txt, 'DataFile=(\S+)', 'tokens', 'once');
    nChMatch  = regexp(txt, 'NumberOfChannels=(\d+)', 'tokens', 'once');
    binaryFmt = regexp(txt, 'BinaryFormat=(\S+)', 'tokens', 'once');
    if isempty(dataMatch) || isempty(nChMatch) || isempty(binaryFmt)
        error('parseSamplingFromVhdr:HeaderIncomplete', 'Could not parse data layout from %s', vhdrPath);
    end
    dataPath = fullfile(eegDir, dataMatch{1});
    nCh = str2double(nChMatch{1});
    bytesPerSample = brainvisionBytesPerSample(binaryFmt{1});
    info = dir(dataPath);
    if isempty(info)
        warning('parseSamplingFromVhdr:NoData', 'Data file %s missing; cannot derive RecordingDuration', dataPath);
        nSamples = NaN;
    else
        nSamples = info.bytes / (nCh * bytesPerSample);
    end
    [~, ~] = deal(name, eegDir);
end

function b = brainvisionBytesPerSample(fmt)
    switch lower(fmt)
        case 'ieee_float_32'; b = 4;
        case 'int_16';        b = 2;
        case 'uint_16';       b = 2;
        otherwise
            error('brainvisionBytesPerSample:UnknownFormat', 'Unsupported BinaryFormat: %s', fmt);
    end
end

function labels = parseChannelLabelsFromVhdr(vhdrPath)
    txt = fileread(vhdrPath);
    matches = regexp(txt, 'Ch\d+=([^,\r\n]+),', 'tokens');
    labels = cellfun(@(c) c{1}, matches, 'UniformOutput', false);
    labels = labels(:);
end

function writeJsonFile(s, path)
    txt = jsonencode(s, 'PrettyPrint', true);
    fid = fopen(path, 'w');
    if fid == -1
        error('writeJsonFile:OpenFailed', 'Could not open %s for writing.', path);
    end
    fwrite(fid, txt, 'char');
    fclose(fid);
end

function normaliseScansTsvPaths(scansPath)
% Replace Windows backslashes with POSIX forward slashes in the filename
% column of an existing _scans.tsv. BIDS requires POSIX paths.
    if ~exist(scansPath, 'file'); return; end
    txt = fileread(scansPath);
    if isempty(strfind(txt, '\')) %#ok<STREMP>
        return;
    end
    lines = strsplit(txt, newline());
    for k = 1:numel(lines)
        if k == 1 || isempty(strtrim(lines{k}))
            continue;
        end
        lines{k} = strrep(lines{k}, '\', '/');
    end
    fid = fopen(scansPath, 'w');
    fwrite(fid, strjoin(lines, newline()), 'char');
    fclose(fid);
end

function rewriteScansTsvForRenamedRun(scansPath, oldBase, newBase)
    if ~exist(scansPath, 'file'); return; end
    txt = fileread(scansPath);
    txt = strrep(txt, [oldBase '_eeg.vhdr'], [newBase '_eeg.vhdr']);
    fid = fopen(scansPath, 'w');
    fwrite(fid, txt, 'char');
    fclose(fid);
end

function [eegOut, droppedLabels] = dropChannels(eeg, toDrop)
    keep = ~ismember(eeg.label, toDrop);
    droppedLabels = eeg.label(~keep);
    if all(keep)
        eegOut = eeg;
        return;
    end
    cfg = [];
    cfg.channel = eeg.label(keep);
    eegOut = ft_selectdata(cfg, eeg);
end

function writeTiPipelineDescription(pipelineDir)
    if ~exist(pipelineDir,'dir'); mkdir(pipelineDir); end
    descPath = fullfile(pipelineDir,'dataset_description.json');
    if exist(descPath,'file'); return; end
    d = struct();
    d.Name        = 'TI stimulation readback';
    d.BIDSVersion = '1.10.0';
    d.DatasetType = 'derivative';
    d.GeneratedBy = {struct( ...
        'Name',    'Spindle-TI', ...
        'Version', '1.0.0', ...
        'CodeURL', 'https://github.com/TobiasRaufeisen/Spindle-TI')};
    d.SourceDatasets = {struct( ...
        'URL',     'TODO_FILL_AFTER_OPENNEURO_UPLOAD', ...
        'Version', '1.0.0')};
    d.Description = ['Per-sample analog DAQ readback of the temporal-interference stimulator output, ' ...
        'captured at 20 kHz in parallel with EEG via Lab Streaming Layer. Stored per subject as ' ...
        '_physio.tsv.gz with a sidecar JSON describing the channels, sampling frequency, and start time ' ...
        'relative to the EEG file.'];
    txt = jsonencode(d, 'PrettyPrint', true);
    fid = fopen(descPath,'w'); fwrite(fid, txt, 'char'); fclose(fid);
end
