function interp_data = interpolate_to_common_grid(data, orig_freq, orig_time, target_freq, target_time)
% Bilinear interpolation of [freq x time] data to a common grid.
%
% INPUTS
%   data        - [freq x time] matrix
%   orig_freq   - original frequency vector
%   orig_time   - original time vector
%   target_freq - target frequency vector
%   target_time - target time vector
%
% OUTPUT
%   interp_data - [length(target_freq) x length(target_time)]

if isequal(orig_freq, target_freq) && isequal(orig_time, target_time)
    interp_data = data;
    return;
end

if length(orig_freq) < 2 || length(orig_time) < 2
    warning('Cannot interpolate — insufficient points (freq: %d, time: %d).', ...
        length(orig_freq), length(orig_time));
    interp_data = nan(length(target_freq), length(target_time));
    return;
end

[tg, fg] = meshgrid(orig_time, orig_freq);
[tt, ft] = meshgrid(target_time, target_freq);
interp_data = interp2(tg, fg, data, tt, ft, 'linear');
end
