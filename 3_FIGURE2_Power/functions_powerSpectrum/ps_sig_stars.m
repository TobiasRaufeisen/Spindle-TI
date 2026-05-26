function s = ps_sig_stars(p)
%PS_SIG_STARS Return significance indicator string for a p-value.
    if p < 0.001
        s = '***';
    elseif p < 0.01
        s = '**';
    elseif p < 0.05
        s = '*';
    else
        s = 'n.s.';
    end
end
