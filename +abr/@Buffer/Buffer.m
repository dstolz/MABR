classdef Buffer
    
    properties
        SampleRate   (1,1) double {mustBePositive,mustBeFinite} = 1;
        
        Data         (:,1) single
        
        % in samples
        SweepOnsets  (:,1) double {mustBeNonnegative,mustBeInteger} = [];
        SweepLength  (1,1) double {mustBePositive,mustBeInteger} = 1;
        
        SweepValue   
        
        FrameSize    (1,1) double {mustBePositive,mustBeInteger} = 2048;
        
        PadValue     (1,1) = 0; % data type cast to obj.Data type
        PadToFrameSize matlab.lang.OnOffSwitchState = 'off';
        
        FFTOptions = struct('windowFcn',@hanning,'inDecibels',true);
    end
    
    properties (SetAccess = private,Dependent)
        N             (1,1)
        SweepDuration (1,1)
        TimeVector    (:,1)
        
        SweepData
        NumSweeps
        SweepMean
        
        RMS
    end
    
    
    properties (Access = private,Dependent)
        sweepIdx
    end
    
    methods
        % Constructor
        function obj = Buffer(Fs,Data,SweepOnsets,SweepLength)
            if nargin >= 1 && ~isempty(Fs), obj.SampleRate = Fs; end
            if nargin >= 2, obj.Data = Data; end
            if nargin >= 3 && ~isempty(SweepOnsets), obj.SweepOnsets = SweepOnsets; end
            if nargin == 4 && ~isempty(SweepLength), obj.SweepLength = SweepLength; end
            
            
        end
        
        
        function d = get.Data(obj)
            % Pad the buffer if its length does not evenly divide by the
            % FrameSize.
            d = obj.Data;
            
            if ~obj.PadToFrameSize, return; end
            
            n = length(d);
                           
            if rem(n,obj.FrameSize) == 0, return; end
            
            frsz = double(obj.FrameSize);
            a = fix(n/frsz);
            b = (a + 1)*frsz;
            
            d(end+1:end+b-n) = obj.PadValue;
        end
        
        
        function d = get.SweepDuration(obj)
            d = obj.SweepLength./obj.SampleRate;
        end
        
        function t = get.TimeVector(obj)
            t = 0:1/obj.SampleRate:obj.SweepDuration-1/obj.SampleRate;
        end
        
        
        function rms = get.RMS(obj)
            rms = sqrt(mean(obj.SweepData.^2,'omitnan'));
        end
        
        function idx = get.sweepIdx(obj)
            idx = ((0:obj.SweepLength-1)+obj.SweepOnsets)';
        end
        
        function s = get.SweepData(obj)
            idx = obj.sweepIdx;
            if isempty(idx), s = []; return; end
            ind = any(idx > obj.N | idx < 1);
            s = obj.Data(idx(:,~ind));
        end 
        
        function n = get.NumSweeps(obj)
            n = size(obj.SweepData,2);
        end
        
        function m = get.SweepMean(obj)
            m = mean(obj.SweepData,2);
        end
        
        function n = get.N(obj)
            n = length(obj.Data);
        end
        
        
        
        % Helper Functions ------------------------------------------------
        function obj = insertData(obj,data,dataOnset)
            obj.Data(dataOnset:length(data)-1) = data;
        end
        
        function obj = appendData(obj,data)
            obj.Data(end+1:end+length(data)) = data;
        end
        
        function obj = appendSweepOnsets(obj,sweepOnsets)
            obj.SweepOnsets = [obj.SweepOnsets; sweepOnsets];
        end
        
        function obj = preallocate(obj,n,val)
            if nargin < 3 || isempty(val), val = 0; end
            obj.Data = repmat(val,n,1);
        end
        
        % Plotting Functions ----------------------------------------------
        
        function h = plotMean(obj,ax,varargin)
            if nargin < 2 || isempty(ax), ax = gca; end
            if nargin < 3
                varargin = {'linestyle','-','linewidth',2,'color',[0.2 0.5 0.9]};
            end
                    
            h = plot(ax,obj.TimeVector,obj.SweepMean,varargin{:});
            
            grid(ax,'on');
            
            ax.XAxis.Limits = [0 obj.SweepDuration];
            ax.XAxis.Label.String = 'Time (sec)';
            ax.YAxis.Label.String = 'Amplitude';
            if nargout == 0, clear h; end
        end
        
        function h = plotSweeps(obj,ax,varargin)
            if nargin < 2 || isempty(ax), ax = gca; end
            if nargin < 3
                varargin = {'linestyle','-','linewidth',0.5,'color',[0.2 0.5 0.9]};
            end
                    
            h = plot(ax,obj.TimeVector,obj.SweepData,varargin{:});
            
            grid(ax,'on');
            
            ax.XAxis.Limits = [0 obj.SweepDuration];
            ax.XAxis.Label.String = 'Time (sec)';
            ax.YAxis.Label.String = 'Amplitude';
            
            if nargout == 0, clear h; end
        end
        
        function h = plotFFT(obj,ax,varargin)
            if nargin < 2 || isempty(ax), ax = gca; end
            if nargin < 3
                varargin = {'linestyle','-','linewidth',2,'color',[0.2 0.5 0.9]};
            end
            
            [M,f] = obj.fft;
            
            h = plot(ax,f,M,varargin{:});
            
            grid(ax,'on');
            
            ax.XAxis.Limits = f([1 end]);
            ax.XAxis.Label.String = 'Frequency (Hz)';
            ax.YAxis.Label.String = 'Magnitude (dB)';
            
            ax.YAxis.Limits = [min([-100; M]) max([0; M])];
            
            if nargout == 0, clear h; end

        end
        
        
        
        % Overloaded Functions --------------------------------------------
        function [M,f] = fft(obj)
            Y = obj.SweepMean;
            Y(isnan(Y)) = []; % may be padded with nans
            
            L = length(Y);
            
            w = window(obj.FFTOptions.windowFcn,L);
            
            Y = Y.*w;
            
            Y = fft(Y);
            P2 = abs(Y/L);
            M = P2(1:L/2+1);
            M(2:end-1) = 2*M(2:end-1);
            if obj.FFTOptions.inDecibels
                M = 20.*log10(M);
            end
            
            f = obj.SampleRate*(0:(L/2))/L;
        end
        
        
        function signalAnalyzer(obj)
            y = obj.SweepValue;
            if isempty(y), y = 1:obj.NumSweeps; end
            z = obj.SweepData;
            str = '';
            for i = 1:length(y)
                if isnumeric(y(i))
                    n = sprintf('Sig_%g',y(i));
                else
                    n = sprintf('Sig_%s',y(i));
                end
                n = matlab.lang.makeValidName(n);
                eval(sprintf('%s = z(:,i);',n));
                str = [str ',' n];
            end
            
            eval(sprintf('signalAnalyzer(%s,''SampleRate'',obj.SampleRate);',str));
            
        end
        
    end
    
    
    
end


