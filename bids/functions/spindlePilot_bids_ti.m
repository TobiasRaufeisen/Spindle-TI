function spindlePilot_bids_ti(tiStream, eegFirstTs, outDir, baseName, rawEegRelPath)
% SPINDLEPILOT_BIDS_TI  Write the TI / DAQ analog readback as a BIDS _physio derivative.
%
%   spindlePilot_bids_ti(TISTREAM, EEGFIRSTTS, OUTDIR, BASENAME, RAWEEGRELPATH)
%
%   Writes:
%     <outDir>/<baseName>_physio.tsv.gz   (sample x channel, tab-separated, gzipped)
%     <outDir>/<baseName>_physio.json     (SamplingFrequency, StartTime, Columns, ...)
%
%   Inputs
%     tiStream      LSL stream struct as returned by load_xdf for the
%                   MyDAQStream stream (fields .info, .time_series).
%                   The per-sample .time_stamps from LSL are NOT reliable
%                   for this stream and are intentionally ignored; timing
%                   is reconstructed from nominal_srate + first_timestamp,
%                   matching spindlePilot_alignTimestamps.
%     eegFirstTs    Absolute LSL timestamp of the first EEG sample
%                   (used to express StartTime relative to the EEG file).
%     outDir        Output directory (created if missing).
%     baseName      Filename stem, e.g. 'sub-05_ses-01_task-spindleti_recording-ti'.
%     rawEegRelPath Path to the raw EEG file this physio recording sits alongside,
%                   relative to the BIDS dataset root. Written to RawSources in
%                   the sidecar so downstream tools can chain derivative -> raw.
%
% Author: Tobias Raufeisen

    arguments
        tiStream      struct
        eegFirstTs    (1,1) double
        outDir        (1,:) char
        baseName      (1,:) char
        rawEegRelPath (1,:) char
    end

    if ~exist(outDir,'dir'); mkdir(outDir); end

    firstTs = str2double(tiStream.info.first_timestamp);
    srate   = str2double(tiStream.info.nominal_srate);
    if ~isfinite(firstTs) || ~isfinite(srate) || srate <= 0
        error('spindlePilot_bids_ti:BadHeader', ...
              'TI stream info missing or invalid (first_timestamp=%s, nominal_srate=%s)', ...
              tiStream.info.first_timestamp, tiStream.info.nominal_srate);
    end

    data = double(tiStream.time_series);
    if size(data,1) > size(data,2)
        data = data';
    end
    [nCh, nSamp] = size(data);

    labels = arrayfun(@(k) sprintf('TI_ch%d', k), 1:nCh, 'UniformOutput', false);
    try
        chs = tiStream.info.desc.channels.channel;
        if iscell(chs)
            for k = 1:min(nCh, numel(chs))
                if isfield(chs{k},'label')
                    labels{k} = char(chs{k}.label);
                end
            end
        end
    catch
    end

    startTime = firstTs - eegFirstTs;

    tsvPath  = fullfile(outDir, [baseName '_physio.tsv']);
    gzPath   = [tsvPath '.gz'];
    jsonPath = fullfile(outDir, [baseName '_physio.json']);

    if exist(gzPath,'file'); delete(gzPath); end
    if exist(tsvPath,'file'); delete(tsvPath); end

    fprintf('  TI: writing %d ch x %d samp -> tsv ...\n', nCh, nSamp);
    t0 = tic;
    writematrix(data', tsvPath, 'Delimiter', 'tab', 'FileType', 'text');
    fprintf('  TI: tsv written in %.1f s (%.1f MB)\n', toc(t0), dir(tsvPath).bytes/1e6);
    t0 = tic;
    gzip(tsvPath);
    delete(tsvPath);
    fprintf('  TI: gzip done in %.1f s (compressed %.1f MB)\n', toc(t0), dir(gzPath).bytes/1e6);

    sidecar = struct();
    sidecar.SamplingFrequency = srate;
    sidecar.StartTime         = startTime;
    sidecar.Columns           = labels;
    sidecar.Description       = ['Analog DAQ readback of the temporal-interference (TI) stimulator output, ' ...
        'recorded in parallel with EEG via Lab Streaming Layer. Per-sample LSL timestamps for this stream ' ...
        'were not reliable; timing is reconstructed from nominal_srate and first_timestamp, matching the ' ...
        'spindlePilot_alignTimestamps step used in the analysis pipeline.'];
    sidecar.RawSources        = {rawEegRelPath};
    sidecar.Manufacturer      = 'National Instruments DAQ (recording) / TI Solutions AG (stimulator)';
    sidecar.RecordingType     = 'continuous';
    writeJson(sidecar, jsonPath);
end

function writeJson(s, path)
    txt = jsonencode(s, 'PrettyPrint', true);
    fid = fopen(path, 'w');
    if fid == -1, error('writeJson:OpenFailed','Could not open %s for writing.', path); end
    fwrite(fid, txt, 'char');
    fclose(fid);
end
