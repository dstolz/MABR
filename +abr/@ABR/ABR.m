classdef ABR < handle
% ABR
% 
% Daniel Stolzberg, PhD (c) 2019
    properties
        frameLength   (1,1) uint16 {mustBeInteger,mustBePositive} = 2048;
        adcFs         (1,1) double {mustBePositive,mustBeFinite}  = 11025; % downsampled to this after acquisitino
        
        dacFs         (1,1) double {mustBeFinite,mustBePositive} = 44100;
        dacBuffer     (:,1) double {mustBeFinite,mustBeGreaterThanOrEqual(dacBuffer,-1),mustBeLessThanOrEqual(dacBuffer,1)};      % playback buffer
        
        dacFile       (1,:) char
        ADCfile       (1,:) char
        
        audioDevice   (1,:) char
        
        
        sweepRate     (1,1) double {mustBePositive, mustBeFinite} = 21.1; % Hz
        numSweeps     (1,1) double {mustBeInteger, mustBePositive} = 1024;
        eventOnset    (1,1) double {mustBePositive,mustBeFinite} = 0.1; % seconds
        
        adcWindow     (1,2) double {mustBeFinite} = [0 0.015]; % seconds
        
        adcFilterOrder (1,1) double {mustBePositive,mustBeInteger} = 10;
        adcFilterHP    (1,1) double {mustBePositive,mustBeFinite}  = 10; % Hz
        adcFilterLP    (1,1) double {mustBePositive,mustBeFinite}  = 3000; % Hz
        
        adcNotchFilterFreq (1,1) double {mustBePositive,mustBeFinite} = 60; % Hz
        
        adcUseBPFilter    (1,1) logical = true;
        adcUseNotchFilter (1,1) logical = true;
    end
    
    properties (GetAccess = public, SetAccess = private)
        APR = audioPlayerRecorder;
        
        WAVinfo;        % returns audioinfo(obj.dacFile)
        
        bufferPosition = uint32(0); % where we are in the playback buffer
        
        adcFilterDesign;
        adcNotchFilterDesign
        adcBuffer;      % recording buffer
        
        adcData;        % recorded data organized as samples x sweep
        adcSweepData;   % sweep-based data samples x sweeps
        
        sweepCount = 1;
        sweepOnsets;
        nextSweepTime;
                
        adcDecimationFactor = 4; % (really dependent)
    end
    
    properties (GetAccess = public, SetAccess = private, Dependent)
        dacBitDepth;       % dependent on dacFile
        
        programState = 'Idle'; % depends on private property STATE
        
        
        dacBufferLength;
        dacBufferDuration;
        dacBufferTimeVector;
        
        adcBufferLength;
        adcBufferDuration;
        adcBufferTimeVector;
    end
    
    properties (Access = private,Hidden = true)
        STATE = -1; % -1: IDLE, 0: READY, 1: RECORDING, 2: COMPLETED
        
        dacPaddingSamples = [0 0 0 0]; % [prestim, poststim, stim, framepad]
    end
    
    
    
    methods   
        playrec(obj,app,ax,varargin); % TESTING
        selectAudioDevice(obj,deviceString);
        triggerSweep(obj);
        prepareSweep(obj);
        
        % Constructor
        function obj = ABR(dacFile,audioDevice)
            % Make sure MATLAB is running at full steam
            [s,w] = dos('wmic process where name="MATLAB.exe" CALL setpriority 128'); % 128 = High
            if s ~=0
                warning('Failed to elevate the priority of MATLAB.exe')
                disp(w)
            end
            
            if nargin >= 1 && ~isempty(dacFile), obj.dacFile = dacFile; end
            if nargin >= 2 && ~isempty(audioDevice) && ischar(audioDevice)
                obj.selectAudioDevice(audioDevice); 
            end

        end
        
        % Destructor
        function delete(obj)
            try
               delete(obj.APR); 
               delete(obj.adcFilterDesign);
            catch me
                
            end
        end
        
        
        
        
        
        
        
        
        % PROPERTY METHODS
        function s = get.programState(obj)
            switch obj.STATE
                case -1, s = 'Idle';
                case 0,  s = 'Read';
                case 1,  s = 'Recording';
                case 2,  s = 'Finished';
            end
        end
        
        
        function info = get.WAVinfo(obj)
            if isempty(obj.dacFile) || ~exist(obj.dacFile,'file')
                info = [];
            else
                info = audioinfo(obj.dacFile);
            end
        end
        
        
        % DAC -------------------------------------------------------------
        function set.dacFile(obj,filename)
            if nargin < 2 || isempty(filename), return; end
            if ~exist(filename,'file')
                error('Invalid dacFile "%s"',filename);
            end
            obj.dacFile = filename;
            
            updateDACbuffer(obj);
        end
        
        function updateDACbuffer(obj) % only update buffer when file is loaded
%             if isempty(obj.dacFile)
%                 y  = obj.dacBuffer;
%             else
%                 y = audioread(obj.dacFile);
%             end
%             
%             % add in any additional padding for adc window            
%             obj.dacPaddingSamples(3) = length(y); % original buffer length
%             obj.dacPaddingSamples(1) = round(obj.dacFs*abs(obj.adcWindow(1)));
%             obj.dacPaddingSamples(2) = max([0 round(obj.dacFs*(obj.adcWindow(2)))-length(y)]);
%             y = [zeros(obj.dacPaddingSamples(1),1); y; zeros(obj.dacPaddingSamples(2),1)];
%             
%             % make sure buffer is divisible by the frame length
%             n = length(y);
%             if n < obj.frameLength
%                 y = [y; zeros(obj.frameLength-n,1,'like',y)];
%                 obj.dacPaddingSamples(4) = obj.frameLength-n; % frame padding
%             elseif n > obj.frameLength
%                 m = mod(n,obj.frameLength);
%                 y = [y; zeros(obj.frameLength-m,1,'like',y)];
%                 obj.dacPaddingSamples(4) = obj.frameLength-m; % frame padding
%             end
%             
%             obj.dacBuffer = y;
            
            obj.adcDecimationFactor = floor(obj.dacFs/obj.adcFs);
        end
        
        function set.frameLength(obj,n)
            obj.frameLength = n;
            obj.updateDACbuffer;
        end
        
        function dacFs = get.dacFs(obj)
            if isempty(obj.dacFile)
                dacFs = obj.dacFs;
            else
                dacFs = obj.WAVinfo.SampleRate;
            end
        end
        
        function dacBitDepth = get.dacBitDepth(obj)
            if isempty(obj.dacFile), dacBitDepth = NaN; return; end
            dacBitDepth = obj.WAVinfo.BitsPerSample;
        end
        
        function n = get.dacBufferLength(obj)
            n = length(obj.dacBuffer);
        end
        
        function d = get.dacBufferDuration(obj)
            d = obj.dacBufferLength/obj.dacFs;
        end
        
        function t = get.dacBufferTimeVector(obj)
%             t = linspace(-obj.dacPaddingSamples(1),sum(obj.dacPaddingSamples([2 3 4])),obj.dacBufferLength)'/obj.dacFs;
            t = 0:1/obj.dacFs:obj.dacBufferDuration-1/obj.dacFs;
        end
        
      
        % ADC -------------------------------------------------------------
        function createADCfilt(obj)
            
            if isa(obj.adcFilterDesign,'digitalFilter')
                % don't bother replacing filter design if relevant
                % parameters are unchanged
                a(1) = obj.adcFilterDesign.FilterOrder == obj.adcFilterOrder;
                a(2) = obj.adcFilterDesign.CutoffFrequency1 == obj.adcFilterHP;
                a(3) = obj.adcFilterDesign.CutoffFrequency2 == obj.adcFilterLP;
                a(4) = obj.adcFilterDesign.SampleRate == obj.adcFs;
                if all(a), return; end
            end
            
            
            % create ADC bandpassfilter
            % NOTE: properties can not be updated dynamically
            obj.adcFilterDesign = designfilt('bandpassfir', ...
                'FilterOrder',     obj.adcFilterOrder, ...
                'CutoffFrequency1',obj.adcFilterHP, ...
                'CutoffFrequency2',obj.adcFilterLP, ...
                'SampleRate',      obj.adcFs);
            
            % Notch filter
            obj.adcNotchFilterDesign = designfilt('bandstopfir', ...
                'FilterOrder',10, ...
                'CutoffFrequency1',obj.adcNotchFilterFreq-1, ...
                'CutoffFrequency2',obj.adcNotchFilterFreq+1, ...
                'SampleRate',      obj.adcFs);
        end
        
        function set.adcWindow(obj,win)
            assert(numel(win) == 2,'adcWindow must have two values');
            
            win = sort(win);
            assert(win(1) <= 0 & win(2) >= obj.dacBufferDuration, ...
                'adcWindow must be at least the duration of the dac buffer'); %#ok<MCSUP>
            obj.adcWindow = win;
        end
        
        function n = get.adcBufferLength(obj)
            n = length(obj.adcBufferTimeVector);
        end
        
        function d = get.adcBufferDuration(obj)
            d = obj.adcBufferLength./obj.adcFs;
        end
        
        function t = get.adcBufferTimeVector(obj)            
            t = linspace(obj.adcWindow(1),obj.adcWindow(2),obj.dacBufferLength./obj.adcDecimationFactor)';
        end
        
        function set.adcFs(obj,fs)
            obj.adcFs = fs;
        end
        
        function set.adcFilterHP(obj,f)
            assert(f < obj.adcFilterLP,'adcFilterHP must be lower than adcFilterLP'); %#ok<MCSUP>
            assert(f < obj.adcFs/2,sprintf('Filter must be below Nyquist rate = %.3f Hz',obj.adcFs/2));  %#ok<MCSUP>
            obj.adcFilterHP = f;
        end
        
        function set.adcFilterLP(obj,f)
            assert(f > obj.adcFilterHP,'adcFilterLP must be higher than adcFilterHP'); %#ok<MCSUP>
            assert(f < obj.adcFs/2,sprintf('Filter must be below Nyquist rate = %.3f Hz',obj.adcFs/2));  %#ok<MCSUP>
            obj.adcFilterLP = f;
        end
        
        function set.adcFilterOrder(obj,order)
            obj.adcFilterOrder = order;
        end
        
        
        
    end
    
    methods (Static)
        
    end
    
end