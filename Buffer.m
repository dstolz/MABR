classdef Buffer
    
    properties
        SampleRate   (1,1) double {mustBePositive,mustBeFinite} = 1;
        
        Data         (:,1)
        
        % in samples
        SweepOnsets  (:,1) double {mustBePositive,mustBeInteger} = 1;
        SweepLength  (1,1) double {mustBePositive,mustBeInteger} = 1;
        
        FrameSize    (1,1) double {mustBePositive,mustBeInteger} = 1;
        
        PadValue     (1,1) = 0; % data type cast to obj.Data type
        PadToFrameSize matlab.lang.OnOffSwitchState = 'on';
        
        FFTOptions  = struct('windowFcn',@hanning,'inDecibels',true);
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
            
            n = length(d);
            
            m = obj.sweepIdx(end); % max sweep index
                
            if rem(n,obj.FrameSize) == 0, return; end
            
            a = fix(n/obj.FrameSize);
            b = (a + 1)*obj.FrameSize;
            
                
            d(end+1:end+b-n) = cast(obj.PadValue,'like',d).*ones(b-n,1,'like',d);
            
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
            ind = any(idx > obj.N);
            s = obj.Data(idx(:,~ind));
        end 
        
        function n = get.NumSweeps(obj)
            n = size(obj.SweepData,2);
        end
        
        function m = get.SweepMean(obj)
            m = mean(obj.SweepData,2,'omitnan');
        end
        
        function n = get.N(obj)
            n = length(obj.Data);
        end
        
        
        
        % Helper Functions ------------------------------------------------
        function insertData(obj,data,dataOnset)
            obj.Data(dataOnset:length(data)-1) = data;
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
        
    end
    
    
    
end

