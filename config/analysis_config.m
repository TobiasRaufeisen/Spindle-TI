function analysis_config()
%ANALYSIS_CONFIG  Apply project-wide MATLAB figure/axes appearance defaults.
%   Sets graphics defaults (white background, Arial fonts, publication line
%   widths) so SpindlePilot figures share a consistent look. Called by
%   spindlePilot_startup.

    set(groot, 'DefaultFigureColor', 'white');
    set(groot, 'DefaultFigurePaperPositionMode', 'auto');
    set(groot, 'DefaultFigureWindowStyle', 'normal');
    set(groot, 'DefaultFigureMenuBar', 'figure');
    set(groot, 'DefaultFigureToolBar', 'auto');
    set(groot, 'DefaultAxesFontName', 'Arial');
    set(groot, 'DefaultAxesFontSize', 12);
    set(groot, 'DefaultTextFontName', 'Arial');
    set(groot, 'DefaultTextFontSize', 12);
    set(groot, 'DefaultAxesLineWidth', 1.2);
    set(groot, 'DefaultAxesBox', 'off');
    set(groot, 'DefaultAxesTickDir', 'out');
    set(groot, 'DefaultAxesTickLength', [0.02, 0.02]);
    set(groot, 'DefaultLineLineWidth', 2);
    set(groot, 'DefaultLineMarkerSize', 8);

    format long g;
end
