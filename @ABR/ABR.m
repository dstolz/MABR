classdef ABR < handle
    
    properties
        frameLength    {mustBeInteger,mustBePositive} = 128;
        adcFs         {mustBePositive,mustBeFinite}  = 11025; % downsampled to this after acquisitino
        
        DACfile = '';
        ADCfile = '';
        
        audioDevice;
        
        
        sweepRate {mustBePositive, mustBeFinite} = 21.1; % Hz
        numSweeps {mustBeInteger, mustBePositive} = 1024;
        eventOnset {mustBePositive,mustBeFinite} = 0.1; % seconds

        
        adcFilterHP {mustBePositive} = 30; % Hz
        adcFilterLP {mustBePositive} = 3000; % Hz
    end
    
    properties (GetAccess = public, SetAccess = private)
        APR = audioPlayerRecorder;
        
        WAVinfo;        % returns audioinfo(obj.DACfile)
        
        bufferPosition = uint32(0); % where we are in the playback buffer
        
        adcFilterDesign;
        
        adcBuffer;      % recording buffer
        dacBuffer;      % playback buffer
        
        adcData;        % recorded data organized as samples x sweep
        adcDataFiltered; % obj.adcData filtered
        
        sweepCount = 1;
        sweepOnsets;
        nextSweepTime;
                
        adcDecimationFactor = 4; % (really dependent)
    end
    
    properties (GetAccess = public, SetAccess = private, Dependent)
        dacFs;          % dependent on DACfile
        bitDepth;       % dependent on DACfile
        
        programState = 'Idle'; % depends on private property STATE
        
        
        dacBufferLength;
        dacBufferDuration;
        dacBufferTimeVector;
        
        adcBufferLength;
        adcBufferDuration;
        adcBufferTimeVector;
    end
    
    properties (Access = private)
        STATE = -1; % -1: IDLE, 0: READY, 1: RECORDING, 2: COMPLETED
        
    end
    
    
    
    methods        
        selectAudioDevice(obj,deviceString);
        triggerSweep(obj);
        prepareSweep(obj);
        
        % Constructor
        function obj = ABR(DACfile,audioDevice)
            % Make sure MATLAB is running at full steam
            [s,w] = dos('wmic process where name="MATLAB.exe" CALL setpriority 128'); % 128 = High
            if s ~=0
                warning('Failed to elevate the priority of MATLAB.exe')
                disp(w)
            end
            
            if nargin >= 1 && ~isempty(DACfile), obj.DACfile = DACfile; end
            if nargin >= 2 && ~isempty(audioDevice) && ischar(audioDevice)
                obj.selectAudioDevice(audioDevice); 
            end
            
            
            obj.adcFilterDesign = designfilt('bandpassfir', ...
                'FilterOrder',10, ...
                'CutoffFrequency1',obj.adcFilterHP, ...
                'CutoffFrequency2',obj.adcFilterLP, ...
                'SampleRate',obj.adcFs);
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
            if isempty(obj.DACfile) || ~exist(obj.DACfile,'file')
                warning('No valid WAV file specified')
                info = [];
            else
                info = audioinfo(obj.DACfile);
            end
        end
        
        
        % DAC
        function set.DACfile(obj,filename)
            if nargin < 2 || isempty(filename), return; end
            if ~exist(filename,'file')
                error('Invalid DACfile "%s"',filename);
            end
            obj.DACfile = filename;
            
            updateDACbuffer(obj);
        end
        
        function updateDACbuffer(obj) % only update buffer when file is loaded
            y = audioread(obj.DACfile);
            
            % make sure buffer is divisible by the frame length
            n = length(y);
            if n < obj.frameLength
                y = [y; zeros(obj.frameLength - n,1,'like',y)];
            elseif n > obj.frameLength
                m = mod(n,obj.frameLength);
                y = [y; zeros(obj.frameLength-m,1,'like',y)];
            end
            
            obj.dacBuffer = y;
            
            obj.adcDecimationFactor = floor(obj.dacFs/obj.adcFs);
        end
        
        function set.frameLength(obj,n)
            obj.frameLength = n;
            obj.updateDACbuffer;
        end
        
        function dacFs = get.dacFs(obj)
            if isempty(obj.DACfile), dacFs = NaN; return; end
            dacFs = obj.WAVinfo.SampleRate;
        end
        
        function bitDepth = get.bitDepth(obj)
            if isempty(obj.DACfile), bitDepth = NaN; return; end
            bitDepth = obj.WAVinfo.BitsPerSample;
        end
        
        function n = get.dacBufferLength(obj)
            n = length(obj.dacBuffer);
        end
        
        function d = get.dacBufferDuration(obj)
            d = obj.dacBufferLength/obj.dacFs;
        end
        
        function t = get.dacBufferTimeVector(obj)
            t = (0:obj.dacBufferLength-1)'./obj.dacFs;
        end
        
      
        % ADC
        function n = get.adcBufferLength(obj)
            n = round(obj.dacBufferLength/obj.adcDecimationFactor);
        end
        
        function d = get.adcBufferDuration(obj)
            d = obj.adcBufferLength/obj.adcFs;
        end
        
        function t = get.adcBufferTimeVector(obj)
            t = (0:obj.adcBufferLength-1)'./obj.adcFs;
        end
        
        function set.adcFs(obj,fs)
            obj.adcFs = fs;
            obj.adcFilterDesign.SampleRate = fs; %#ok<MCSUP>
        end
        
        function set.adcFilterHP(obj,f)
            assert(f > obj.adcFilterLP,'adcFilterHP must be lower than adcFilterLP'); %#ok<MCSUP>
            obj.adcFilterHP = f;
            obj.adcFilterDesign.CutoffFrequency1 = f; %#ok<MCSUP>
        end
        
        function set.adcFilterLP(obj,f)
            assert(f < obj.adcFilterHP,'adcFilterLP must be higher than adcFilterHP'); %#ok<MCSUP>
            obj.adcFilterLP = f;
            obj.adcFilterDesign.CutoffFrequency2 = f; %#ok<MCSUP>
        end
        
    end
    
    methods (Static)
        
    end
    
end