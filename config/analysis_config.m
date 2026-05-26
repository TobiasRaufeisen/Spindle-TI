function analysis_config()
    % ANALYSIS_CONFIG Define global analysis parameters and environment settings
    % This function establishes your computational laboratory environment
    % Think of this like setting up optimal working conditions that remain
    % consistent across all your different experiments and analyses
    
    fprintf('Loading analysis configuration...\n');
    
    % ==== FIGURE APPEARANCE AND BEHAVIOR SETTINGS ====
    % These settings define how your figures will look and behave consistently
    % across all your analyses, creating a professional, standardized visual environment
    
    % Set default figure properties that will apply to all new figures
    % This is like establishing consistent lighting and display conditions in your lab
    set(groot, 'DefaultFigurePosition', [100, 100, 1200, 800]); % [left, bottom, width, height]
    set(groot, 'DefaultFigureColor', 'white'); % Clean white background
    set(groot, 'DefaultFigurePaperPositionMode', 'auto'); % Ensures printed figures match screen
    
    % Configure figure window behavior for optimal workflow
    set(groot, 'DefaultFigureWindowStyle', 'normal'); % Use normal windows (not docked)
    set(groot, 'DefaultFigureMenuBar', 'figure'); % Include standard menu bar
    set(groot, 'DefaultFigureToolBar', 'auto'); % Include toolbar for interactive exploration
    
    % Set up consistent, publication-ready text formatting
    % This ensures all your figures have professional typography
    set(groot, 'DefaultAxesFontName', 'Arial'); % Professional, readable font
    set(groot, 'DefaultAxesFontSize', 12); % Large enough for presentations and papers
    set(groot, 'DefaultTextFontName', 'Arial');
    set(groot, 'DefaultTextFontSize', 12);
    
    % Configure axis appearance for clean, professional plots
    set(groot, 'DefaultAxesLineWidth', 1.2); % Slightly thicker axes for visibility
    set(groot, 'DefaultAxesBox', 'off'); % Clean appearance without top/right box lines
    set(groot, 'DefaultAxesTickDir', 'out'); % Ticks point outward for cleaner look
    set(groot, 'DefaultAxesTickLength', [0.02, 0.02]); % Reasonable tick length
    
    % Set up consistent line and marker properties for data visualization
    set(groot, 'DefaultLineLineWidth', 2); % Thick enough to see clearly
    set(groot, 'DefaultLineMarkerSize', 8); % Visible but not overwhelming markers
    
    % Configure color scheme for consistent, accessible visualization
    % Define a professional color palette that works well for scientific figures
    config.colors.primary = [0.2, 0.4, 0.8]; % Professional blue
    config.colors.secondary = [0.8, 0.4, 0.2]; % Complementary orange
    config.colors.accent = [0.4, 0.8, 0.2]; % Accent green
    config.colors.neutral = [0.5, 0.5, 0.5]; % Neutral gray
    config.colors.warning = [0.9, 0.6, 0.1]; % Warning yellow
    config.colors.error = [0.9, 0.2, 0.2]; % Error red
    
    % ==== COMPUTATIONAL ENVIRONMENT SETTINGS ====
    % These settings optimize MATLAB's behavior for scientific computing
    
    % Configure MATLAB's display and warning behavior
    format long g; % Use readable number formatting that shows appropriate precision
    
    % ==== ANALYSIS WORKFLOW PREFERENCES ====
    % These settings define how you prefer to work, not what you're analyzing
    
    % File handling preferences
    config.file_handling.auto_save_figures = true; % Automatically save important figures
    config.file_handling.figure_format = 'png'; % Default format for saved figures
    config.file_handling.figure_dpi = 300; % High resolution for publications
    
    % Display preferences for analysis outputs
    config.display.show_progress = true; % Show progress bars for long computations
    config.display.verbose_output = true; % Concise output unless debugging
    
    % Quality control preferences
    config.quality_control.confirm_overwrite = true; % Ask before overwriting important files
    config.quality_control.validate_inputs = true; % Check input parameters for common errors
    
    % ==== NEUROSCIENCE-SPECIFIC ENVIRONMENT SETTINGS ====
    % These are domain-specific preferences that enhance neuroscience workflows
    
    % EEG visualization preferences
    config.eeg_display.time_unit = 'seconds'; % Prefer seconds over samples for time axes
    config.eeg_display.amplitude_unit = 'microvolts'; % Standard amplitude unit
    
    % Statistical reporting preferences
    config.statistics.alpha_display_threshold = 0.05; % Show p-values below this threshold
    config.statistics.effect_size_reporting = true; % Always report effect sizes
    config.statistics.confidence_interval_level = 0.95; % Standard confidence level
    
    % Make all configuration available to other functions
    assignin('base', 'config', config);
    
    fprintf('Configuration loaded successfully.\n');
    fprintf('Figure defaults set for professional scientific visualization.\n');
    fprintf('Environment optimized for neuroscience analysis workflow.\n');
end