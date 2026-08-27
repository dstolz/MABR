classdef MetricBuffer < mabr.compute.PublishBuffer
% mabr.compute.MetricBuffer  What the metrics worker publishes: one value per
% job per condition, with the roster the columns refer to identified by
% number (the roster's keys travel over the DataQueue when they change; see
% mabr.compute.ComputeEngine).
%
%   Layout:
%       Info    [8 x 2] per-half scalars (Fields below)
%       Values  [2*MaxJobs x MaxConds]   NaN = nothing to report / not reached
%       Counts  [4 x MaxConds]           per half: clean sweeps behind each
%                                        condition, and whether it is live
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        Fields  = struct('RosterId',1,'NumConds',2,'NumJobs',3,'ReqSeq',4, ...
                         'Incomplete',5);
        NumInfo = 8;
    end

    properties (SetAccess = immutable)
        MaxJobs  (1,1) double
        MaxConds (1,1) double
    end

    methods
        function obj = MetricBuffer(cfg,writable)
            if nargin < 2, writable = false; end
            mj = cfg.MaxComputeJobs;
            mc = cfg.MaxComputeConditions;
            fmt = { ...
                'double',[mabr.compute.MetricBuffer.NumInfo 2],'Info'; ...
                'double',[2*mj mc],'Values'; ...
                'double',[4 mc],'Counts'};
            obj@mabr.compute.PublishBuffer(cfg.computeMetricFile,fmt,writable);
            obj.MaxJobs  = mj;
            obj.MaxConds = mc;
        end
        function zero(obj)
            % The header AND the per-half words: a fresh worker must not
            % leave a previous session's last publish readable.
            zero@mabr.compute.PublishBuffer(obj);
            obj.Map.Data.Info(:) = 0;
        end
    end

    methods (Access = protected)
        function writeHalf(obj,h,s)
            % s: RosterId, Values [nJobs x nConds], ReqSeq, Incomplete (a
            % bitmask of jobs a time budget left partly unevaluated).
            F  = obj.Fields;
            [nJ,nC] = size(s.Values);
            assert(nJ <= obj.MaxJobs && nC <= obj.MaxConds, ...
                'mabr:compute:MetricBuffer:size', ...
                '%d jobs x %d conditions exceeds the buffer''s %d x %d.', ...
                nJ,nC,obj.MaxJobs,obj.MaxConds);
            info = zeros(obj.NumInfo,1);
            info(F.RosterId)   = s.RosterId;
            info(F.NumConds)   = nC;
            info(F.NumJobs)    = nJ;
            info(F.ReqSeq)     = getf(s,'ReqSeq',0);
            info(F.Incomplete) = getf(s,'Incomplete',0);
            obj.Map.Data.Info(:,h+1) = info;
            if nJ > 0 && nC > 0
                obj.Map.Data.Values(obj.rows(h,obj.MaxJobs,nJ),1:nC) = s.Values;
            end
            if nC > 0
                obj.Map.Data.Counts(2*h+1,1:nC) = getf(s,'NumSweeps',zeros(1,nC));
                obj.Map.Data.Counts(2*h+2,1:nC) = double(getf(s,'Live',false(1,nC)));
            end
        end

        function s = readHalf(obj,h)
            F    = obj.Fields;
            info = double(obj.Map.Data.Info(:,h+1));
            nC   = info(F.NumConds);
            nJ   = info(F.NumJobs);
            if nJ < 0 || nJ > obj.MaxJobs || nC < 0 || nC > obj.MaxConds
                s = []; return
            end
            vals = zeros(nJ,nC);
            if nJ > 0 && nC > 0
                vals = double(obj.Map.Data.Values(obj.rows(h,obj.MaxJobs,nJ),1:nC));
            end
            ns = zeros(1,nC); lv = false(1,nC);
            if nC > 0
                ns = double(obj.Map.Data.Counts(2*h+1,1:nC));
                lv = logical(obj.Map.Data.Counts(2*h+2,1:nC));
            end
            s = struct('RosterId',info(F.RosterId),'Values',vals, ...
                'NumSweeps',ns,'Live',lv, ...
                'ReqSeq',info(F.ReqSeq),'Incomplete',info(F.Incomplete));
        end
    end
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
