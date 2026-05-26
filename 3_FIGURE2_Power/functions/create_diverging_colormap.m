function cm = create_diverging_colormap(m)
%CREATE_DIVERGING_COLORMAP Blue-white-red diverging colormap.
%   CM = CREATE_DIVERGING_COLORMAP(M) returns an M-by-3 colormap matrix
%   ranging from blue through white to red. Suitable for difference and
%   t-value topographies and time-frequency difference maps.
%
%   INPUTS:
%     m - number of colormap entries (default 256)
%
%   OUTPUTS:
%     cm - [m x 3] colormap matrix

    if nargin < 1, m = 256; end

    m1 = floor(m / 2);

    % Blue to white
    r_bw = linspace(0, 1, m1)';
    g_bw = linspace(0, 1, m1)';
    b_bw = ones(m1, 1);

    % White to red
    m2 = m - m1;
    r_wr = ones(m2, 1);
    g_wr = linspace(1, 0, m2)';
    b_wr = linspace(1, 0, m2)';

    cm = [r_bw, g_bw, b_bw; r_wr, g_wr, b_wr];
end
