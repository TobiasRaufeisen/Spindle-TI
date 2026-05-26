function config = build_pipeline_config(params)
%BUILD_PIPELINE_CONFIG Map parameter block to pipeline config struct.
%   CONFIG = BUILD_PIPELINE_CONFIG(PARAMS) translates the flat params struct
%   from the main script into the nested config struct expected by the shared
%   pipeline functions (load, filter, compute, stats).
%
%   INPUTS:
%     params - parameter struct defined in the main script
%
%   OUTPUTS:
%     config - config struct compatible with spindlePilot_visual_topographyTFR_* functions

    % Start with defaults from the shared config function
    config = spindlePilot_visual_topographyTFR_config(params.event_type);

    % Participants and design
    config.participants = params.participants;
    config.session      = params.session;
    config.conditions   = params.conditions;

    % Loading ranges
    config.freq_range      = params.load_freq_range;
    config.load_time_range = params.load_time_range;
    config.time_range      = params.sleep_stage_analysis_window;

    % Analysis windows
    config.topo_params.time_freq_windows = params.time_freq_windows;

    % Filter pipeline
    config.filter_order           = params.filter_order;
    config.sleep_stage_filter     = params.sleep_stage_filter;
    config.artifact               = params.artifact;
    config.transform.use_log_transform   = params.log_transform;
    config.summary.method                = params.summary_method;
    config.summary.trimmed_mean_percent  = params.trimmed_mean_percent;
    config.electrode_filtering_mode      = params.electrode_filtering_mode;

    % Z-score filter
    config.zscore_spindle_power = params.zscore_filter;

    % Power filter disabled
    config.power_filter.enabled = false;

    % Statistics
    config.stats = params.stats;
end
