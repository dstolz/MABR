function r = analysis(ABR,type,varargin)

D = ABR.ADC.SweepData;

switch lower(type)
    case 'corr'
        r = corrcoef(D);
        r = tril(r,-1);
        r = r(r~=0);
        z = (log(1+r) - log(1-r))./2; % z’ = .5[ln(1+r) – ln(1-r)]
        r = mean(z,'all');
        
    case 'rms'
        r = mean(rms(D));
        
    case 'peaks' % varargin = {npeaks,findNegativePeaks}
        npeaks = 5;
        findNegativePeaks = false;
        if nargin == 3
            n = length(varargin);
            if ~isempty(varargin{1}), npeaks = varargin{1}; end
            if n >= 2 && ~isempty(varargin{2}), findNegativePeaks = true; end
        end
        M = mean(D,2);
        if findNegativePeaks, M = -M; end
        [pks,locs,w,p] = findpeaks(M,'NPeaks',npeaks);
        if findNegativePeaks, pks = -pks; end
        r.pks  = pks;
        r.locs = locs;
        r.w    = w;
        r.p    = p;

    otherwise
        if nargin == 3
            r = feval(type,D,varargin{:});
        else
            r = feval(type,D);
        end
end