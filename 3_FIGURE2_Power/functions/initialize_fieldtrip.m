function initialize_fieldtrip(ft_path)
%INITIALIZE_FIELDTRIP Initialize FieldTrip toolbox
%   Adds FieldTrip to path and runs ft_defaults if available

    if exist(ft_path, 'dir')
        addpath(ft_path);
    end
    if exist('ft_defaults', 'file')
        try
            ft_defaults;
        catch ME
            warning('Failed to run ft_defaults: %s', getReport(ME, 'basic'));
        end
    else
        warning('FieldTrip not found on path. Layout/plots may fail.');
    end
end
