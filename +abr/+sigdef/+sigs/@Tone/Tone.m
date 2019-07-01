classdef Tone < abr.sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019

    properties (Access = public)
        frequency       (1,1) abr.sigdef.sigProp
        startPhase      (1,1) abr.sigdef.sigProp
    end
    
    properties (Constant)
        Type = 'Tone';
    end
    
    methods
        
        % Constructor
        function obj = Tone(frequency,soundLevel,startPhase)
            obj.ignoreProcessUpdate = true;
            
            if nargin < 1 || isempty(frequency),  frequency = 'octaves(1,32,6)'; end
            if nargin < 2 || isempty(soundLevel), soundLevel = '-20:10:80'; end
            if nargin < 3 || isempty(startPhase), startPhase = 0;  end
            
            obj.soundLevel.Value = soundLevel;

            obj.frequency       = abr.sigdef.sigProp(frequency,'Frequency','kHz',1000);     
            obj.frequency.Alias = 'Frequency';
            obj.frequency.ValueFormat = '%0.2f';
            obj.frequency.Dependency = 'Nyquist';
            obj.frequency.MinValue = 1e-6;
                        
            obj.startPhase       = abr.sigdef.sigProp(startPhase,'Start Phase','deg');
            obj.startPhase.Alias = 'Start Phase';
                        
            obj.SortProperty = 'frequency';
            
            obj.Calibration.InterpMethod = 'makima';
            
            obj.informativeParams = {'frequency','soundLevel'};

            obj.ignoreProcessUpdate = false;
        end
        
        function obj = update(obj)
            time = obj.timeVector;
            
            A    = obj.soundLevel.realValue;
            freq = obj.frequency.realValue;            
            phi  = deg2rad(obj.startPhase.realValue);
            
            obj.data = cell(size(time));
            obj.dataParams = [];
            
            % make sure gate duration is less than half the signal duration
            for i = 1:numel(time)
                assert(time{i}(end) - time{i}(1) >= obj.windowRFTime.realValue*2, ...
                    'Window Rise/Fall time (%0.3f s) must be less than half the signal duration (%0.3f s)', ...
                    time{i}(end)-time{i}(1),obj.windowRFTime.realValue);
            end
            

            k = 1;
            for i = 1:numel(time)
                    for m = 1:numel(freq)
                        for n = 1:numel(phi)
                            for a = 1:numel(A)
                                % first check if calibration has been done
                                if obj.Calibration.calibration_is_valid
                                    A_V = obj.calibration.estimate_calibrated_voltage(freq(m),A(a));
                                else
                                    A_V = 1;
                                end
                                
                                obj.data{k,1} = A_V.*sin(2*pi*freq(m)*time{i}+phi(n));

                                obj.dataParams.frequency(k,1)  = freq(m);
                                obj.dataParams.soundLevel(k,1) = A(a);
                                obj.dataParams.startPhase(k,1) = phi(n);
                                obj.dataParams.duration(k,1)   = obj.duration.realValue(i); % same as timeVector
                                k = k + 1;
                            end
                        end
                    end
            end
            
            obj = obj.applyGate; % superclass function
        end
        
        function obj = set.frequency(obj,value)
            if isa(value,'abr.sigdef.sigProp')
                obj.frequency = value;
            else
                mustBeFinite(value);
                mustBePositive(value);
                mustBeNonempty(value);
                mustBeLessThan(obj.Fs/2);
                obj.frequency.Value = value;
                obj.processUpdate; % superclass function
            end
        end
        
        function obj = set.startPhase(obj,value)
            if isa(value,'abr.sigdef.sigProp')
                obj.startPhase = value;
            else
                mustBeNonempty(value);
                mustBeFinite(value);
                obj.startPhase.Value = value;
                obj.processUpdate; % superclass function
            end
        end
        
        
        
    end
    
    
    
end