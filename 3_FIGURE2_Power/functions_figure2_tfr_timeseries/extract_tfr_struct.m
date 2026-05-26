function tfr = extract_tfr_struct(tfr_data)
% Extract the TFR structure from a loaded .mat file.
%
% INPUT   tfr_data - struct returned by load()
% OUTPUT  tfr      - FieldTrip-style TFR struct

if isfield(tfr_data, 'tfr_single')
    tfr = tfr_data.tfr_single;
elseif isfield(tfr_data, 'tf_result')
    tfr = tfr_data.tf_result;
else
    fn  = fieldnames(tfr_data);
    tfr = tfr_data.(fn{1});
end
end
