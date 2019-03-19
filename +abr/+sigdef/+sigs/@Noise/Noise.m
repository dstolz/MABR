classdef Noise < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019

    properties (Access = public)
        HPfreq          (1,1) sigdef.sigProp
        LPfreq          (1,1) sigdef.sigProp
        filterOrder     (1,1) sigdef.sigProp
        seed            (1,1) sigdef.sigProp
    end
    

    properties (Access = private)
        filterDesign
    end
    
    methods
        
        % Constructor
        function obj = Noise(HPfreq,LPfreq,filterOrder)
            
            obj.Type = 'Noise';
            
            if nargin < 1 || isempty(HPfreq),       HPfreq = 0.004; end
            if nargin < 2 || isempty(LPfreq),       LPfreq = 12; end
            if nargin < 3 || isempty(filterOrder),  filterOrder = 20; end
            
            
            obj.HPfreq       = sigdef.sigProp(HPfreq,'High-Pass Fc','kHz',1000);
            obj.HPfreq.Alias = 'HP Freq';
            
            obj.LPfreq       = sigdef.sigProp(LPfreq,'Low-Pass Fc','kHz',1000);
            obj.LPfreq.Alias = 'LP Freq';
            
            obj.filterOrder  = sigdef.sigProp(filterOrder,'Filter order');
            obj.filterOrder.Alias = 'Filt Order';
            
            obj.seed         = sigdef.sigProp(0,'Seed#; 0 = "shuffle"');
            obj.seed.Alias = 'Seed';
        end
        
        function update(obj)
            obj.filterDesign = designfilt('bandpassfir', ...
                'FilterOrder',     obj.filterOrder.realValue, ...
                'CutoffFrequency1',obj.HPfreq.realValue, ...
                'CutoffFrequency2',obj.LPfreq.realValue, ...
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
        
        function obj = set.HPfreq(obj,value)
            if isa(value,'sigdef.sigProp')
                obj.HPfreq = value;
            else
                mustBePositive(value);
                mustBeFinite(value);
                mustBeNonempty(value);
                obj.HPfreq.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.LPfreq(obj,value)
            if isa(value,'sigdef.sigProp')
                obj.LPfreq = value;
            else
                mustBePositive(value);
                mustBeFinite(value);
                mustBeNonempty(value);
                obj.LPfreq.Value = value;
                obj.processUpdate;
            end
        end
        
        
    end
    
    
    
end