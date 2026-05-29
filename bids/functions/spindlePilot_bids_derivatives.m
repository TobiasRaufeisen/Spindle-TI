function spindlePilot_bids_derivatives(subjects, paths, bidsRoot, task)
% SPINDLEPILOT_BIDS_DERIVATIVES  Stage analysis-ready outputs as BIDS derivatives.
%
%   spindlePilot_bids_derivatives(SUBJECTS, PATHS, BIDSROOT, TASK)
%
%   Two derivative pipelines are written:
%
%   1. derivatives/spindlepilot-preprocessing/
%      Per-subject epoched FieldTrip MAT files at 500 Hz, renamed from
%      sub<N>_ses1_ANALYSIS.mat to sub-<NN>_ses-01_task-<task>_desc-preproc_eeg.mat.
%      An accompanying _eeg.json captures the analysis-time sampling rate
%      and re-reference.
%
%   2. derivatives/comprehensive-analysis/
%      The single comprehensive_analysis.mat (event tables, sleep stages,
%      trial metadata) is copied to the pipeline root, along with the
%      per-subject YASA spindle / slow-wave / sleep-stage CSV outputs that
%      figure scripts consume.
%
%   Both pipelines get their own dataset_description.json with GeneratedBy
%   and SourceDatasets pointing at the raw release.
%
% Author: Tobias Raufeisen

    arguments
        subjects (1,:) double
        paths    struct
        bidsRoot (1,:) char
        task     (1,:) char = 'spindleti'
    end

    derivRoot = fullfile(bidsRoot, 'derivatives');
    if ~exist(derivRoot,'dir'); mkdir(derivRoot); end

    prepRoot = fullfile(derivRoot, 'spindlepilot-preprocessing');
    if ~exist(prepRoot,'dir'); mkdir(prepRoot); end
    writeDerivativeDescription(prepRoot, ...
        'SpindlePilot preprocessing', ...
        'Epoched FieldTrip MAT files at 500 Hz after the SpindlePilot preprocessing pipeline.');

    for s = subjects
        subTag = sprintf('sub-%02d', s);
        srcMat = fullfile(paths.processed.analysis, sprintf('sub%d_ses1_ANALYSIS.mat', s));
        if ~exist(srcMat,'file')
            warning('spindlePilot_bids_derivatives:MissingAnalysis', ...
                    'Skipping %s: %s not found.', subTag, srcMat);
            continue;
        end
        dstDir = fullfile(prepRoot, subTag, 'ses-01', 'eeg');
        if ~exist(dstDir,'dir'); mkdir(dstDir); end
        dstName = sprintf('%s_ses-01_task-%s_run-01_desc-preproc_eeg.mat', subTag, task);
        dstMat  = fullfile(dstDir, dstName);
        % De-identify before publishing: FieldTrip structures embed a cfg
        % provenance chain (callinfo: OS username, hostname, working-directory
        % path, processing date) and eeg.hdr.orig (the raw LSL stream info,
        % including the recording host). Strip both rather than copying verbatim.
        try
            scrubbed = scrubProvenance(load(srcMat));
            save(dstMat, '-struct', 'scrubbed', '-v7.3');
        catch ME
            warning('spindlePilot_bids_derivatives:ScrubFailed', ...
                    'Skipping %s: could not de-identify %s (%s).', subTag, srcMat, ME.message);
            continue;
        end

        sidecar = struct();
        sidecar.SamplingFrequency = 500;
        sidecar.EEGReference      = 'linked mastoids (TP9+TP10)/2';
        sidecar.SoftwareFilters   = struct( ...
            'HighPass', struct('CutoffFrequency', 0.3, 'FilterType', 'Butterworth', 'Order', 2), ...
            'LowPass',  struct('CutoffFrequency', 30,  'FilterType', 'Butterworth', 'Order', 4), ...
            'Notch',    struct('CutoffFrequency', 50,  'FilterType', 'Butterworth'));
        sidecar.Description = ['Epoched 500 Hz FieldTrip MAT (8 s trials, ' ...
            'OFF/1HZ/5HZ with separate refractory and ramping epochs). ' ...
            'See https://github.com/TobiasRaufeisen/Spindle-TI for the exact pipeline.'];
        writeJson(sidecar, fullfile(dstDir, ...
            sprintf('%s_ses-01_task-%s_run-01_desc-preproc_eeg.json', subTag, task)));
    end

    compRoot = fullfile(derivRoot, 'comprehensive-analysis');
    if ~exist(compRoot,'dir'); mkdir(compRoot); end
    writeDerivativeDescription(compRoot, ...
        'SpindlePilot comprehensive event analysis', ...
        ['comprehensive_analysis.mat (sample-precise spindle / slow-wave / ' ...
         'sleep-stage tables with trial context) plus the per-subject YASA CSV outputs.']);

    compSrc = fullfile(paths.results.sleep_staging, '..', 'comprehensive_analysis.mat');
    compSrc = char(java.io.File(compSrc).getCanonicalPath());
    if exist(compSrc,'file')
        copyfile(compSrc, fullfile(compRoot,'comprehensive_analysis.mat'));
    else
        compSrcAlt = fullfile(paths.results_root, 'comprehensive_analysis.mat');
        if exist(compSrcAlt,'file')
            copyfile(compSrcAlt, fullfile(compRoot,'comprehensive_analysis.mat'));
        else
            warning('spindlePilot_bids_derivatives:NoComprehensive', ...
                    'comprehensive_analysis.mat not found at expected locations.');
        end
    end

    yasaSrc = paths.results.sleep_staging;
    if ~exist(yasaSrc,'dir')
        yasaSrc = fullfile(paths.results_root, 'SleepStagingAndEvents');
    end
    if exist(yasaSrc,'dir')
        yasaDst = fullfile(compRoot,'yasa');
        if ~exist(yasaDst,'dir'); mkdir(yasaDst); end
        listing = dir(fullfile(yasaSrc,'*.csv'));
        for k = 1:numel(listing)
            srcFile = fullfile(listing(k).folder, listing(k).name);
            copyfile(srcFile, fullfile(yasaDst, listing(k).name));
        end
    else
        warning('spindlePilot_bids_derivatives:NoYasaDir', ...
                'YASA source directory not found; skipping CSV copy.');
    end
end

function writeDerivativeDescription(pipelineDir, name, description)
    d = struct();
    d.Name        = name;
    d.BIDSVersion = '1.10.0';
    d.DatasetType = 'derivative';
    d.GeneratedBy = {struct( ...
        'Name',    'Spindle-TI', ...
        'Version', '1.0.0', ...
        'CodeURL', 'https://github.com/TobiasRaufeisen/Spindle-TI')};
    d.SourceDatasets = {struct( ...
        'URL',     'TODO_FILL_AFTER_OPENNEURO_UPLOAD', ...
        'Version', '1.0.0')};
    d.Description = description;
    writeJson(d, fullfile(pipelineDir,'dataset_description.json'));
end

function writeJson(s, path)
    txt = jsonencode(s, 'PrettyPrint', true);
    fid = fopen(path,'w');
    if fid == -1
        error('writeJson:OpenFailed','Could not open %s for writing.', path);
    end
    fwrite(fid, txt, 'char');
    fclose(fid);
end

function s = scrubProvenance(s)
% Recursively strip identifying provenance from a loaded FieldTrip structure
% before it is published as a derivative:
%   - any field named 'cfg'  (FieldTrip provenance: cfg.callinfo holds the OS
%     username, hostname, working-directory path and processing date/time, and
%     cfg.previous chains repeat them for every processing step)
%   - 'orig' under any 'hdr' (the raw LSL stream info, including the recording
%     host and acquisition metadata)
% Only metadata is removed; the scientific data fields (trial, time, label,
% fsample, sampleinfo, trialinfo, condition labels, ...) are left untouched.
    if isstruct(s)
        if isfield(s, 'cfg')
            s = rmfield(s, 'cfg');
        end
        fns = fieldnames(s);
        for k = 1:numel(s)
            for i = 1:numel(fns)
                fn = fns{i};
                v  = s(k).(fn);
                if strcmp(fn, 'hdr') && isstruct(v) && isfield(v, 'orig')
                    v = rmfield(v, 'orig');
                end
                if isstruct(v) || iscell(v)
                    s(k).(fn) = scrubProvenance(v);
                end
            end
        end
    elseif iscell(s)
        for i = 1:numel(s)
            if isstruct(s{i}) || iscell(s{i})
                s{i} = scrubProvenance(s{i});
            end
        end
    end
end
