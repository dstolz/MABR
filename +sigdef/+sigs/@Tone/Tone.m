classdef Tone < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019

    properties (Access = public)
        frequency   (:,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 1000;
        startPhase  (:,1) double {mustBeNonempty,mustBeGreaterThanOrEqual(startPhase,-90),mustBeLessThanOrEqual(startPhase,90)} = 0;
    end
    
    properties (Constant = true,Hidden = true)
        D_frequency = 'Frequency (Hz)';
        D_startPhase = 'Start Phase (deg)';
    end
    
    methods
        
        % Constructor
        function obj = Tone(frequency,startPhase)
            if nargin < 1 || isempty(frequency), frequency = 1000; end
            if nargin < 2 || isempty(startPhase), startPhase = 0; end
                        
            obj.frequency = frequency;
            obj.startPhase = startPhase;    
        end
        
        function update(obj)
            f = obj.frequency;
            t = obj.timeVector;
            phi = deg2rad(obj.startPhase);
            obj.data = obj.polarity*sin(2*pi*f*t+phi);
            
            obj.applyGate; % superclass function
        end
        
        function set.frequency(obj,f)
            obj.frequency = f;
            obj.processUpdate; % superclass function
        end
        
        function set.startPhase(obj,p)
            obj.startPhase = p;
            obj.processUpdate; % superclass function
        end
    end
    
    
    methods (Static)
        function obj = createDisplay(parent)
            % setup custom fields in some parent figure or panel
        end
    end
    
end