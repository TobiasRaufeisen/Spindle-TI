function paths = figure2_paths_config()
%FIGURE2_PATHS_CONFIG Centralized path configuration for Figure 2 analysis
%
%   PATHS = figure2_paths_config() returns a struct with all paths needed for
%   Figure 2 analysis. This uses relative paths based on the current project
%   structure, making it device-independent.
%
%   USAGE:
%       paths = figure2_paths_config();
%       % Access paths like: paths.processed_data_dir, paths.results_dir, etc.
%
%   TO CUSTOMIZE:
%       Edit the paths below to match your local setup. The default
%       configuration uses relative paths within the project directory.

    % Get the project root directory (parent of FIGURE2_Power)
    current_dir = fileparts(mfilename('fullpath'));
    project_root = fileparts(current_dir);

    % Core directories
    paths.project_root = project_root;
    paths.results_dir = fullfile(project_root, '1_eventDetection', 'eventDetectionResults');

    % FieldTrip path
    % Option 1: If FieldTrip is already on your MATLAB path, leave empty
    % Option 2: Specify full path to your FieldTrip installation
    paths.fieldtrip = '';  % Leave empty if FieldTrip is on path
    % paths.fieldtrip = 'C:\path\to\fieldtrip';  % Uncomment and edit if needed

    % Processed data directory: in-repo `data/` folder (gitignored).
    % See README "Data Availability" for download instructions.
    paths.processed_data_dir = fullfile(project_root, 'data');

    % Analysis-specific paths
    paths.tfr_base = fullfile(current_dir, 'TFR_1HzSmoothing');
    paths.output_base = fullfile(current_dir, 'outputs');
    paths.figures_topography = fullfile(paths.output_base, 'figures_topography');

    % Figure 2 outputs directory (for all figures and stats)
    paths.output_dir = fullfile(current_dir, 'outputs');

    % TFR data paths
    paths.tfr_spindle = fullfile(paths.tfr_base, 'spindle_trials');
    paths.tfr_slowwave = fullfile(paths.tfr_base, 'slowwave_trials');

    % Output files
    paths.compute_output_file = fullfile(paths.output_dir, 'figure2_data.mat');
    paths.trial_indices_file = fullfile(paths.output_dir, 'figure2_trial_indices.mat');

    % Data analysis path (for trial-sorted analysis)
    paths.data_analysis = fullfile(paths.processed_data_dir, 'analysis');

    % Comprehensive analysis file
    paths.comprehensive_analysis = fullfile(paths.results_dir, 'comprehensive_analysis.mat');

    % Print configuration info
    fprintf('\n=== FIGURE 2 PATH CONFIGURATION ===\n');
    fprintf('Project root:      %s\n', paths.project_root);
    fprintf('Results directory: %s\n', paths.results_dir);
    fprintf('Processed data:    %s\n', paths.processed_data_dir);

    % Check if critical paths exist
    if ~exist(paths.results_dir, 'dir')
        fprintf('NOTE: Results directory will be created: %s\n', paths.results_dir);
    end

    if ~exist(paths.processed_data_dir, 'dir')
        warning('Processed data directory not found: %s\n         Please update this path in figure2_paths_config.m', paths.processed_data_dir);
    end

    if ~isempty(paths.fieldtrip)
        if ~exist(paths.fieldtrip, 'dir')
            warning('FieldTrip directory not found: %s\n         Please update this path or leave empty if FieldTrip is on path', paths.fieldtrip);
        end
    end

    fprintf('==================================\n\n');
end
