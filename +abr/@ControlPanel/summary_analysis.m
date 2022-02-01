function r = summary_analysis(data,type,options)
% r = summary_analysis(data,type,varargin)
% 
% Where data is an NxM matrix with N sweeps and M samples
%
% types:    'corr'  Computes the mean correlation coefficient across sweeps
%           'rms'   Computes the mean sweep RMS power
%           'peaks' Finds peaks in the data
%                   options.NumPeaks        default = 5;
%                   options.PeakPolarity    default = +1;
%           char name of a custom function that returns a scalar value.
%
% 

r = [];

switch type
    case 'corr'
        r = corrcoef(data);
        r = tril(r,-1);
        r = r(r~=0);
        z = (log(1+r) - log(1-r))./2; % z� = .5[ln(1+r) � ln(1-r)]
        r = mean(z,'all');
        
    case 'rms'
        r = mean(rms(data,2));
        
    case 'peaks' % varargin = {npeaks,findNegativePeaks}
        if nargin < 3, options = struct; end
        if ~isfield(options,'NumPeaks') || isempty(options.NumPeaks), options.NumPeaks = 5; end
        if ~isfield(options,'Polarity') || isempty(options.Polarity), options.Polarity = 1; end
        M = mean(data,2);
        if options.Polarity < 0, M = -M; end
        [pks,locs,w,p] = findpeaks(M,'NPeaks',options.NumPeaks);
        if options.Polarity < 0, pks = -pks; end
        r.pks  = pks;
        r.locs = locs;
        r.w    = w;
        r.p    = p;

    otherwise
%         if nargin == 3
%             r = feval(type,data,varargin{:});
%         else
            r = feval(type,data);
%         end
end