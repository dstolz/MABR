classdef Buffer
    % BUFFER   Class for handling acquired signals
    %
    %   BUFFER Properties:
    %       SampleRate       - Sampling rate of the data (Hz)
    %       Data             - Stored signal data
    %       ABRobj           - Associated object for additional processing
    %       SweepOnsets      - Onset indices of sweeps in the data
    %       SweepLength      - Length of each sweep (samples)
    %       SweepValue       - Value associated with each sweep
    %       FrameSize        - Frame size for processing (samples)
    %       PadValue         - Value used for padding data
    %       PadToFrameSize   - Toggle for padding data to frame size
    %       SmoothSpan       - Span for moving average smoothing
    %       DetrendPoly      - Polynomial order for detrending
    %       FFTOptions       - Structure with FFT options
    %
    %   BUFFER Methods:
    %       Buffer           - Constructor method
    %       saveobj          - Save object to a structure
    %       to_struct        - Convert object properties to a structure
    %       insertData       - Insert data at a specified onset
    %       appendData       - Append data to the existing buffer
    %       appendSweepOnsets- Append sweep onset indices
    %       preallocate      - Preallocate data buffer
    %       plotMean         - Plot the mean of sweeps
    %       plotSweeps       - Plot individual sweeps
    %       plotFFT          - Plot the FFT of the mean sweep
    %       fft              - Compute FFT of the mean sweep
    %       signalAnalyzer   - Launch Signal Analyzer app with sweep data
    properties
       SampleRate   (1,1) double {mustBePositive,mustBeFinite} = 1;
        % Sampling rate of the data in Hz.

        Data         (:,1) single
        % Column vector storing the signal data.

        ABRobj       (1,1)
        % Associated object for additional processing.

        SweepOnsets  (:,1) double {mustBeNonnegative,mustBeInteger} = [];
        % Onset indices of sweeps within the data buffer.

        SweepLength  (1,1) double {mustBePositive,mustBeInteger} = 1;
        % Length of each sweep in samples.

        SweepValue
        % Value associated with each sweep (e.g., stimulus level).

        FrameSize    (1,1) double {mustBePositive,mustBeInteger} = 2048;
        % Frame size for processing in samples.

        PadValue     (1,1) = 0;
        % Value used to pad the data buffer, cast to the type of Data.

        PadToFrameSize matlab.lang.OnOffSwitchState = 'off';
        % Toggle to pad data to match the frame size ('on' or 'off').

        SmoothSpan    (1,1) double {mustBeInteger,mustBeNonnegative} = 0;
        % Span for moving average smoothing of the sweep mean.

        DetrendPoly   (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(DetrendPoly,-1), mustBeLessThanOrEqual(DetrendPoly,9)} = -1;
        % Polynomial order for detrending the sweep mean (-1 to 9).

        FFTOptions = struct('windowFcn',@flattop,'inDecibels',true);
        % Structure containing FFT options:
        %   windowFcn   - Window function handle (e.g., @flattop)
        %   inDecibels  - Boolean to toggle decibel scaling of FFT output

        IsArtifact  (:,1) logical = false;
        % Logical vector indicating which sweeps are marked as artifacts.
    end

    properties (Dependent)
        N             (1,1)
        % Total number of samples in the Data buffer.

        SweepDuration (1,1)
        % Duration of each sweep in seconds.

        TimeVector    (:,1)
        % Time vector corresponding to one sweep.

        SweepData
        % Matrix containing segmented sweep data.

        NumSweeps
        % Number of sweeps in the data buffer.

        SweepMean
        % Mean waveform of the sweeps.

        noisePower
        % Estimated noise power of the sweeps.

        signalPower
        % Estimated signal power of the sweeps.

        RMS
        % Root mean square value of the sweep mean.

        SNR
        % Signal-to-noise ratio in decibels.

        adcDecimationFactor
        % Decimation factor from the associated ABR object.

        sweepIdx
        % Indices corresponding to each sweep segment.

        NumArtifacts
        % Number of sweeps marked as artifacts.
    end
    
    methods
        % Constructor
        function obj = Buffer(ABRobj,Fs,Data,SweepOnsets,SweepLength)            
            
            if nargin >= 1 && ~isempty(ABRobj), obj.ABRobj = ABRobj; end
            if nargin >= 2 && ~isempty(Fs), obj.SampleRate = Fs; end
            if nargin >= 3, obj.Data = Data; end
            if nargin >= 4 && ~isempty(SweepOnsets), obj.SweepOnsets = SweepOnsets; end
            if nargin == 5 && ~isempty(SweepLength), obj.SweepLength = SweepLength; end
            
        end
        
        
        function s = saveobj(obj)
            s = to_struct(obj);
        end
        
        function s = to_struct(obj)
            m = metaclass(obj);
            p = {m.PropertyList.Name};
            for i = 1:length(p)
                s.(p{i}) = obj.(p{i});
            end
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
            t = (0:obj.SweepLength-1)/obj.SampleRate;
        end
        
        function f = get.adcDecimationFactor(obj)
            if isequal(obj.ABRobj,0)
                f = 1;
            else
                f = obj.ABRobj.adcDecimationFactor;
            end
        end
        
        function rms = get.RMS(obj)
            rms = sqrt(mean(obj.SweepData.^2,'omitnan'));
        end
        
        function r = get.SNR(obj)
            r = 20 * log10(obj.signalPower/obj.noisePower);
        end
        
        function r = get.noisePower(obj)
            % plus-or-minus averaging as noise estimate
            x = obj.SweepData;
            if obj.N > 1
                x = mean(x(:,1:2:end),2) - mean(x(:,2:2:end),2);
            end
            r = sqrt(mean(x.^2));
        end
        
        function r = get.signalPower(obj)
            r = rms(obj.SweepMean);
        end
        
        function idx = get.sweepIdx(obj)
%             idx = ((0:obj.adcDecimationFactor:obj.SweepLength-1)+obj.SweepOnsets)';
            idx = ((0:obj.SweepLength-1)+obj.SweepOnsets)';
        end
        
        function s = get.SweepData(obj)
            idx = obj.sweepIdx;
            if isempty(idx), s = []; return; end
            ind = any(idx > obj.N | idx < 1,1);
            s = obj.Data(idx(:,~ind));
        end 
        
        function n = get.NumSweeps(obj)
            n = size(obj.SweepData,2);
        end
        
        function m = get.SweepMean(obj)
            m = mean(obj.SweepData,2);
            
            % optionally apply postprocessing
            
            % detrend
            if obj.DetrendPoly == 0
                m = m - mean(m);
            elseif obj.DetrendPoly > 0
                t = obj.TimeVector';
                [p,~,mu] = polyfit(t,m,obj.DetrendPoly);
                y = polyval(p,t,[],mu);
                m = m - y;
            end
            
            % smooth
            if obj.SmoothSpan > 0
                m = movmean(m,obj.SmoothSpan);
            end
                
        end
        
        
        function n = get.N(obj)
            n = length(obj.Data);
        end

        function n = get.NumArtifacts(obj)
            n = nnz(obj.IsArtifact);
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
            
            M = obj.SweepMean;
                    
            tvec = obj.TimeVector;
            
            h = plot(ax,tvec,M,varargin{:});
            
            grid(ax,'on');
            
            
            ax.XAxis.Limits = [min(tvec), max(tvec)];
            ax.YAxis.Limits = [-1.1 1.1] * max(abs(M));
            
            ax.XAxis.Label.String = 'Time (sec)';
            ax.YAxis.Label.String = 'Amplitude';
            
            grid(ax,'on');
            
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


