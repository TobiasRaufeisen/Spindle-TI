function config = spindlePilot_visual_topographyTFR_config(event_type)
%SPINDLEPILOT_VISUAL_TOPOGRAPHYTFR_CONFIG Default configuration for TFR topography pipeline.
%
%   CONFIG = spindlePilot_visual_topographyTFR_config() returns a struct with
%   paths, analysis parameters, and plotting/statistics defaults used by the
%   spindlePilot topography scripts. Pass 'spindle' or 'slowwave' as an optional
%   argument to switch the event type and frequency range.
%
%   The returned CONFIG is consumed by:
%     - spindlePilot_visual_topographyTFR_compute
%     - spindlePilot_visual_topographyTFR_plot
%     - spindlePilot_visual_topographyTFR_stats

    if nargin < 1 || isempty(event_type)
        event_type = 'spindle';
    end

    % ----------------------------------------------------------------------
    % Paths (using centralized path configuration)
    % ----------------------------------------------------------------------
    % Load paths from centralized config
    paths = figure2_paths_config();

    config.paths.processed_data_dir = paths.processed_data_dir;
    config.paths.results_dir = paths.results_dir;
    config.paths.fieldtrip = paths.fieldtrip;

    config.paths.tfr_base = paths.tfr_base;
    config.paths.output_base = paths.output_base;
    config.paths.figures_topography = paths.figures_topography;
    config.paths.comprehensive_analysis = paths.comprehensive_analysis;
    config.base_path = paths.data_analysis;  % For loading ANALYSIS.mat files with sampleinfo
    config.io.compute_output_file = paths.compute_output_file;
    config.io.save_compute_results = true;

    % ----------------------------------------------------------------------
    % Participants and task settings
    % ----------------------------------------------------------------------
    config.participants = {'sub5', 'sub6','sub7', 'sub8','sub9','sub10','sub11','sub12','sub13','sub14', ...
        'sub15','sub16','sub17','sub18','sub19','sub20','sub21','sub22','sub23','sub24'};
    config.session = 'ses1';
    config.conditions = {'x5HZ', 'x1HZ', 'OFF'};
    config.time_range = [0.25 1.75];

    % ----------------------------------------------------------------------
    % Execution control flags
    % ----------------------------------------------------------------------
    config.run_compute = true;  % Run data computation (set false to load existing)
    config.run_plot = true;     % Run any plotting
    config.plot.conditions = true;      % Plot individual condition topographies
    config.plot.differences = true;     % Plot difference topographies
    config.plot.subjects = true;        % Plot individual subject topographies

    % ----------------------------------------------------------------------
    % Time-frequency windows and plotting defaults
    % ----------------------------------------------------------------------
    config.topo_params = struct();
    config.topo_params.time_freq_windows = {
        12, 16, 0.25, 1.75, 'StimClean';
        %12, 16, 2.0, 6.0, 'PostStim';
    };
    config.topo_params.layout = 'easycapM1.mat';
    % Colormap for topographies (viridis is used by default in plots for publications)
    % Other options: 'parula', 'jet', 'hot', 'cool'
    config.topo_params.colormap_name = 'parula';
    config.topo_params.show_markers = true;
    config.topo_params.marker_size = 4;  % Increased for publication visibility

    % ----------------------------------------------------------------------
    % Filter pipeline configuration
    % ----------------------------------------------------------------------
    % Define the order of filter operations (can be reordered as needed)
    % Available filters: 'sleep_stage', 'artifact', 'log_transform', 'power_filter'
    config.filter_order = {'sleep_stage', 'artifact', 'log_transform'};

    % Sleep stage filter
    config.sleep_stage_filter.enabled = true;
    config.sleep_stage_filter.stages = {'N2'};

    % Log transform
    config.transform.use_log_transform = true;

    % Trial summarization
    config.summary.method = 'trimmed_mean';
    config.summary.trimmed_mean_percent = 0;

    % Artifact rejection
    config.artifact.apply = true;
    config.artifact.mad_threshold = 3.5;
    config.artifact.handling = 'reject_trial'; % 'reject_trial' | 'reject_channel' | 'interpolate_channel'

    % Power filter (typically disabled for unbiased analysis)
    config.power_filter.enabled = false;
    config.power_filter.params = struct( ...
        'time_window', [0.25 1.75], ...
        'freq_range', [12 16], ...
        'spike_len_sec', 0.5, ...
        'spike_vs_rest_ratio', 4, ...
        'guard_sec', 0);

    % ----------------------------------------------------------------------
    % Statistics defaults
    % ----------------------------------------------------------------------
    config.stats = struct();
    config.stats.alpha = 0.05;
    config.stats.cluster_alpha = 0.1;
    config.stats.n_permutations = 2000;
    config.stats.min_cluster_size = 2;
    config.stats.run = true;

    % ----------------------------------------------------------------------
    % Event type specific paths/ranges
    % ----------------------------------------------------------------------
    switch lower(event_type)
        case 'spindle'
            config.event_type = 'spindle';
            config.freq_range = [12 16];
            config.paths.tfr = paths.tfr_spindle;
        case 'slowwave'
            config.event_type = 'slowwave';
            config.freq_range = [0 5];
            config.paths.tfr = paths.tfr_slowwave;
        otherwise
            error('Unsupported event_type: %s', event_type);
    end

    config.power_filter.params.freq_range = config.freq_range;
end
