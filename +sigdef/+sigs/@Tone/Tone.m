classdef Tone < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019

    properties (Access = public)
        frequency   (1,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 1000;
        startPhase  (1,1) double {mustBeNonempty,mustBeGreaterThanOrEqual(startPhase,-90),mustBeLessThanOrEqual(startPhase,90)} = 0;
        windowFcn      (1,:) char   {mustBeNonempty} = 'blackmanharris'; % doc window
        windowOpts     cell = {};
        windowRFTime   (1,1) double {mustBeNonempty,mustBeNonnegative,mustBeFinite} = 0.001; % seconds
    end
    
    properties (Constant = true)
        D_frequency     = 'Frequency (Hz)';
        D_startPhase    = 'Start Phase (deg)';
        D_windowFcn     = 'Window Function';
        D_windowRFTime  = 'Window Rise/Fall Time (ms)';
        A_polarity      = true;
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
            
            obj.data = double(obj.polarity).*sin(2*pi*f*t+phi)';
            
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
        
        function set.windowFcn(obj,w)
            obj.windowFcn = w;
            obj.processUpdate;
        end
        
        function set.windowOpts(obj,w)
            obj.windowOpts = w;
            obj.processUpdate;
        end
        
        function set.windowRFTime(obj,wrf)
            obj.windowRFTime = wrf;
            obj.processUpdate;
        end
        
    end
    
    
    
end