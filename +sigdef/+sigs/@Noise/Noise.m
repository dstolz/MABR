classdef Noise < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019

    properties (Access = public)
        HPfreq      (1,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 400;
        LPfreq      (1,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 12000;
        filterOrder (1,1) double {mustBeNonempty,mustBePositive,mustBeInteger} = 20;
        seed        (1,:) double {mustBeNonempty,mustBeFinite} = 0;
        windowFcn      (1,:) char   {mustBeNonempty} = 'blackmanharris'; % doc window
        windowOpts     cell = {};
        windowRFTime   (1,1) double {mustBeNonempty,mustBeNonnegative,mustBeFinite} = 0.001; % seconds
        
    end
    
    properties (Constant = true)
        D_HPfreq        = 'High-Pass Fc (Hz)';
        D_LPfreq        = 'Low-Pass Fc (Hz)';
        D_filterOrder   = 'Filter order';
        D_seed          = 'Seed#; 0 = "shuffle"';
        D_windowFcn     = 'Window Function';
        D_windowRFTime  = 'Window Rise/Fall Time (ms)';
        A_polarity      = true;
    end

    properties (Access = private)
        filterDesign
    end
    
    methods
        
        % Constructor
        function obj = Noise(HPfreq,LPfreq,filterOrder)
            if nargin < 1 || isempty(HPfreq), HPfreq = 400; end
            if nargin < 2 || isempty(LPfreq), LPfreq = 12000; end
            if nargin < 3 || isempty(filterOrder), filterOrder = 20; end
            
            obj.HPfreq = HPfreq;
            obj.LPfreq = LPfreq;
            obj.filterOrder = filterOrder;
            
        end
        
        function update(obj)
            obj.filterDesign = designfilt('bandpassfir', ...
                'FilterOrder',     obj.filterOrder, ...
                'CutoffFrequency1',obj.HPfreq, ...
                'CutoffFrequency2',obj.LPfreq, ...
                'SampleRate',      obj.Fs);      
            
            if obj.seed == 0
                rng('shuffle');
            else
                rng(obj.seed);
            end
            
            y = randn(1,obj.N);
            y = y ./ max(abs(y));
            
            obj.data = filter(obj.filterDesign,y);
            
            obj.applyGate; % superclass function
        end
        
        function set.HPfreq(obj,f)
            obj.HPfreq = f;
            obj.processUpdate;
        end
        
        function set.LPfreq(obj,p)
            obj.LPfreq = p;
            obj.processUpdate;
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