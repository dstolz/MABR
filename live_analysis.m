function r = live_analysis(ABR,type)

D = ABR.ADC.SweepData;

switch type
    case 'corr'
        r = corrcoef(D);
        r = tril(r,-1);
        r = r(r~=0);
        z = (log(1+r) - log(1-r))./2; % z’ = .5[ln(1+r) – ln(1-r)]
        r = mean(z,'all');
        
end