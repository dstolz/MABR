classdef RequestBuffer < mabr.compute.PublishBuffer
% mabr.compute.RequestBuffer  What the client asks of the compute workers:
% the two cadences and the job table. Written by the client, read by BOTH
% workers -- the fields are disjoint (the DSP worker reads only the live
% period), so one file with one writer serves both.
%
%   Requests change on a mouse click, not on a clock, and a worker that sees
%   a torn table would run the wrong metric for a cycle -- so this uses the
%   same double-buffer discipline as the result buffers rather than a lighter
%   scheme of its own. Seq doubles as the request revision: a worker adopts a
%   table when Seq differs from the last one it took, and echoes it back in
%   its publishes (ReqSeq) so a reader can tell which request a value answers.
%
%   Layout:
%       Info   [8 x 2]          LivePeriod, MetricPeriod, NumJobs
%       Jobs   [2*MaxJobs x 4]  per slot: Active MetricIdx WinLo WinHi (ms)
%
%   MetricIdx indexes mabr.metrics.online.catalog; 0 = inactive, -1 = a
%   custom function pushed to the metrics worker over its queue.
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        Fields  = struct('LivePeriod',1,'MetricPeriod',2,'NumJobs',3);
        NumInfo = 8;
        Custom  = -1;           % MetricIdx of a user-supplied metric
    end

    properties (SetAccess = immutable)
        MaxJobs (1,1) double
    end

    methods
        function obj = RequestBuffer(cfg,writable)
            if nargin < 2, writable = false; end
            mj  = cfg.MaxComputeJobs;
            fmt = { ...
                'double',[mabr.compute.RequestBuffer.NumInfo 2],'Info'; ...
                'double',[2*mj 4],'Jobs'};
            obj@mabr.compute.PublishBuffer(cfg.computeRequestFile,fmt,writable);
            obj.MaxJobs = mj;
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
            % s: LivePeriod, MetricPeriod, Jobs [MaxJobs x 4].
            F = obj.Fields;
            info = zeros(obj.NumInfo,1);
            info(F.LivePeriod)   = s.LivePeriod;
            info(F.MetricPeriod) = s.MetricPeriod;
            info(F.NumJobs)      = size(s.Jobs,1);
            obj.Map.Data.Info(:,h+1) = info;
            obj.Map.Data.Jobs(obj.rows(h,obj.MaxJobs,size(s.Jobs,1)),:) = s.Jobs;
        end

        function s = readHalf(obj,h)
            F    = obj.Fields;
            info = double(obj.Map.Data.Info(:,h+1));
            nJ   = info(F.NumJobs);
            if nJ < 0 || nJ > obj.MaxJobs, s = []; return; end
            s = struct('LivePeriod',info(F.LivePeriod), ...
                       'MetricPeriod',info(F.MetricPeriod), ...
                       'Jobs',double(obj.Map.Data.Jobs(obj.rows(h,obj.MaxJobs,nJ),:)));
        end
    end
end
