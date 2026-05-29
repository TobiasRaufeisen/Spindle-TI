function spindlePilot_export_bids(subjects, opts)
% SPINDLEPILOT_EXPORT_BIDS  Convert the SpindlePilot dataset to BIDS-EEG.
%
%   spindlePilot_export_bids()
%   spindlePilot_export_bids(SUBJECTS)
%   spindlePilot_export_bids(SUBJECTS, OPTS)
%
%   With no arguments converts the full published set (subjects 5..24).
%   Pass SUBJECTS = 5 to do a single-subject smoke test before committing
%   to the full run.

%
%   Output goes to <repo>/data/bids/ (gitignored). The validator can be run
%   from a shell with:
%     npx @bids-standard/bids-validator data/bids
%
%   Prerequisites: spindlePilot_startup must have been run so that FieldTrip,
%   xdfimport and the project paths are on the MATLAB path.
%
% Author: Tobias Raufeisen

    arguments
        subjects (1,:) double = 5:24
        opts struct = struct()
    end

    paths = spindlePilot_paths();
    repoRoot = paths.project_root;  % spindlePilot_paths.repo_root is the PARENT folder

    defaults = struct( ...
        'rawRoot',             fullfile(repoRoot, 'data', 'raw'), ...
        'bidsRoot',            fullfile(repoRoot, 'data', 'bids'), ...
        'task',                'spindleti', ...
        'writeRaw',            true, ...
        'writeTI',             true, ...
        'writeDerivatives',    true, ...
        'refreshSidecarsOnly', false);
    opts = mergeStructs(defaults, opts);

    if opts.refreshSidecarsOnly
        opts.writeRaw = false;
        opts.writeTI  = false;
    end

    metaDir = fullfile(repoRoot, 'bids', 'metadata');

    if ~exist(opts.bidsRoot,'dir'); mkdir(opts.bidsRoot); end

    if ~exist('data2bids','file')
        error('spindlePilot_export_bids:FieldTripMissing', ...
              'FieldTrip data2bids not found. Run spindlePilot_startup first.');
    end

    fprintf('\n==== Spindle-TI BIDS export ====\n');
    fprintf('  raw root : %s\n', opts.rawRoot);
    fprintf('  bids root: %s\n', opts.bidsRoot);
    fprintf('  task     : %s\n', opts.task);
    fprintf('  subjects : %s\n', mat2str(subjects));

    % Seed the dataset-level files so the root looks like a BIDS dataset even
    % for partial / refresh-only runs. These are re-applied at the end because
    % data2bids clobbers some of them (see the closing copy below).
    copyDatasetLevelFiles(metaDir, opts.bidsRoot);

    if opts.writeRaw || opts.writeTI || opts.refreshSidecarsOnly
        subjectOpts = struct( ...
            'writeRaw',            opts.writeRaw, ...
            'writeTI',             opts.writeTI, ...
            'refreshSidecarsOnly', opts.refreshSidecarsOnly);
        for s = subjects
            try
                spindlePilot_bids_subject(s, opts.rawRoot, opts.bidsRoot, metaDir, opts.task, subjectOpts);
            catch ME
                warning('spindlePilot_export_bids:SubjectFailed', ...
                        'sub-%02d failed: %s', s, ME.message);
            end
        end
    end

    if opts.writeDerivatives
        spindlePilot_bids_derivatives(subjects, paths, opts.bidsRoot, opts.task);
    end

    % data2bids rewrites README and dataset_description.json on every subject
    % call: it replaces README with FieldTrip's default placeholder template and
    % re-encodes dataset_description.json (wrapping the Authors/Funding string
    % lists into nested arrays, which is invalid BIDS). Re-apply the curated
    % templates last so the published dataset carries our versions, not data2bids'.
    if opts.writeRaw
        copyDatasetLevelFiles(metaDir, opts.bidsRoot);
    end

    fprintf('\nDone. Validate with: npx @bids-standard/bids-validator "%s"\n', opts.bidsRoot);
end

function copyDatasetLevelFiles(metaDir, bidsRoot)
    files = {'dataset_description.json', 'participants.tsv', 'participants.json', ...
             'README', 'CHANGES', 'task-spindleti_eeg.json', 'task-spindleti_events.json'};
    for k = 1:numel(files)
        src = fullfile(metaDir, files{k});
        if exist(src,'file')
            copyfile(src, fullfile(bidsRoot, files{k}));
        else
            warning('copyDatasetLevelFiles:Missing', 'Template not found: %s', src);
        end
    end
end

function out = mergeStructs(defaults, override)
    out = defaults;
    if isempty(override) || ~isstruct(override)
        return;
    end
    fn = fieldnames(override);
    for i = 1:numel(fn)
        out.(fn{i}) = override.(fn{i});
    end
end
